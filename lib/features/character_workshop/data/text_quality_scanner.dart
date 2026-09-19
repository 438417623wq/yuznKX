import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/models/card_field.dart';
import '../domain/models/card_project.dart';
import '../domain/models/check_report.dart';
import '../domain/models/project_entry.dart';

/// 本地文本质检器。
///
/// **全部在本地完成，不消耗任何 API 额度。** 参照参考项目里 `check-agent`
/// 子代理的职责，但改成纯规则扫描：手机上更快、更省，也更容易单测。
///
/// 原则：**宁可漏报，不要误报**。大量误报会让用户直接忽略整个质检结果，
/// 所以偏主观的检查一律降级成「提示」，只有确定的结构问题才标「错误」。
class TextQualityScanner {
  const TextQualityScanner._();

  /// 常见 AI 味词表（偏主观，只报「提示」）。
  static const List<String> _aiTells = <String>[
    '不禁',
    '不由自主',
    '仿佛',
    '彷佛',
    '嘴角勾起',
    '嘴角微微上扬',
    '空气中弥漫',
    '眸光',
    '意味深长',
    '眼神深邃',
    '微微颔首',
    '心中一惊',
    '心头一颤',
    '泛起涟漪',
    '眼中闪过一丝',
    '若有所思',
    '难以言喻',
    '霎时间',
    '刹那间',
    '宛如',
    '恍若',
  ];

  /// 感叹号密度阈值（每 100 字）。
  static const double _exclamationThreshold = 3.0;

  static CheckReport scan(CardProject project) {
    final issues = <CheckIssue>[];
    var seq = 0;

    String nextId() => 'c${seq++}_${const Uuid().v4().substring(0, 8)}';

    // ---------- 结构完整性 ----------

    if (project.entries.isEmpty) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.error,
          message: '项目里还没有任何条目',
          suggestion: '先回到「创作规划」阶段生成条目清单。',
        ),
      );
      return CheckReport(issues: issues, createdAt: DateTime.now());
    }

    // 只看「逐条产出」阶段该写的条目 —— 前端面板有自己的阶段，而且是可选的，
    // 算进来的话这里会一直挂着一条「没写完」。
    final unfinished = project.writingEntries
        .where((entry) => !entry.status.isSettled)
        .toList();
    if (unfinished.isNotEmpty) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.warning,
          message: '还有 ${unfinished.length} 条没有写完',
          entryId: unfinished.first.id,
          entryTitle: unfinished.first.title,
          suggestion: '回到「逐条产出」把剩下的写完，再导出。',
        ),
      );
    }

    final emptyContent = project.writingEntries
        .where((entry) =>
            entry.status == EntryStatus.done && !entry.hasContent)
        .toList();
    for (final entry in emptyContent) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.error,
          message: '「${entry.title}」标记为已完成，但内容是空的',
          entryId: entry.id,
          entryTitle: entry.title,
          suggestion: '补上内容，或把这条删掉。',
        ),
      );
    }

    // 名称必须有。
    final nameEntry = project.entries.firstWhere(
      (entry) => entry.kind == EntryKind.characterCard &&
          entry.fieldKey == kNameFieldKey,
      orElse: () => ProjectEntry(id: '', title: ''),
    );
    if (nameEntry.id.isEmpty || !nameEntry.hasContent) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.error,
          message: '角色没有名字',
          entryId: nameEntry.id.isEmpty ? null : nameEntry.id,
          suggestion: '名称是必填项，导出时会退化成项目名。',
        ),
      );
    }

    // 开场白缺失会让卡在酒馆里「点开没反应」。
    final hasFirstMes = project.entries.any((entry) =>
        entry.kind == EntryKind.characterCard &&
        entry.fieldKey == 'first_mes' &&
        entry.hasContent);
    if (!hasFirstMes) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.warning,
          message: '没有开场白（first_mes）',
          suggestion: '没有开场白的卡在酒馆里开局是空白的。',
        ),
      );
    }

    // ---------- 世界书专项 ----------

    final worldbook = project.entries
        .where((entry) => entry.goesToWorldbook)
        .toList();

    if (worldbook.isEmpty) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: CheckSeverity.warning,
          message: '没有任何世界书条目',
          suggestion: '世界书是这张卡「有世界」的关键，建议至少补 3~5 条。',
        ),
      );
    }

    for (final entry in worldbook) {
      if (!entry.hasContent) {
        continue;
      }
      if (entry.keys.isEmpty && !entry.constant) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.structure,
            severity: CheckSeverity.warning,
            message: '「${entry.title}」没有触发关键词，也不会常驻注入',
            entryId: entry.id,
            entryTitle: entry.title,
            suggestion: '补上关键词，或把这条设为「常驻注入」—— 否则它永远不会生效。',
          ),
        );
      }
    }

    // order 冲突（同序号的条目在酒馆里顺序不确定）。
    final orderBuckets = <int, List<ProjectEntry>>{};
    for (final entry in worldbook) {
      orderBuckets.putIfAbsent(entry.order, () => <ProjectEntry>[]).add(entry);
    }
    orderBuckets.forEach((order, entries) {
      if (entries.length > 1) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.structure,
            severity: CheckSeverity.info,
            message: '有 ${entries.length} 条世界书的插入顺序都是 $order',
            entryId: entries.first.id,
            entryTitle: entries.first.title,
            suggestion: '同序号的条目注入顺序不确定，建议改成不同的 order。',
          ),
        );
      }
    });

    // 标题重复。
    final titleBuckets = <String, List<ProjectEntry>>{};
    for (final entry in worldbook) {
      final key = entry.title.trim();
      if (key.isEmpty) {
        continue;
      }
      titleBuckets.putIfAbsent(key, () => <ProjectEntry>[]).add(entry);
    }
    titleBuckets.forEach((title, entries) {
      if (entries.length > 1) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.structure,
            severity: CheckSeverity.warning,
            message: '世界书里有 ${entries.length} 条都叫「$title」',
            entryId: entries.first.id,
            entryTitle: title,
            suggestion: '重名条目在酒馆里很难区分，建议改成不同的标题。',
          ),
        );
      }
    });

    // 关键词跨条目冲突：同一个词被两条以上世界书当成触发词。
    final keyOwners = <String, List<ProjectEntry>>{};
    for (final entry in worldbook) {
      for (final key in entry.keys) {
        final normalized = key.trim().toLowerCase();
        if (normalized.isEmpty) {
          continue;
        }
        keyOwners.putIfAbsent(normalized, () => <ProjectEntry>[]).add(entry);
      }
    }
    keyOwners.forEach((key, owners) {
      if (owners.length > 1) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.consistency,
            severity: CheckSeverity.info,
            message: '关键词「$key」同时被 ${owners.length} 条世界书使用',
            entryId: owners.first.id,
            entryTitle: owners.first.title,
            suggestion: '它们会一起被触发。如果这是有意的可以忽略。',
          ),
        );
      }
    });

    // ---------- 一致性 ----------

    final characterName = nameEntry.hasContent ? nameEntry.content.trim() : '';
    if (characterName.isNotEmpty) {
      final mentioned = project.entries.any((entry) =>
          entry.kind == EntryKind.worldbook &&
          entry.hasContent &&
          entry.content.contains(characterName));
      if (!mentioned && worldbook.isNotEmpty) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.consistency,
            severity: CheckSeverity.info,
            message: '世界书里没有任何条目提到主角「$characterName」',
            suggestion: '如果主角在世界观里有位置，建议加一条相关条目。',
          ),
        );
      }
    }

    // MVU 变量：取值应当在世界书里有对应描述。
    final variablePaths = _readVariablePaths(project.mvuVariablesJson);
    if (variablePaths.isNotEmpty && worldbook.isNotEmpty) {
      final worldbookText = worldbook
          .map((entry) => '${entry.title} ${entry.content}')
          .join('\n');
      final missing = variablePaths
          .where((path) => !worldbookText.contains(path))
          .toList();
      if (missing.length == variablePaths.length) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.consistency,
            severity: CheckSeverity.info,
            message: 'MVU 变量与世界书条目几乎没有对应关系',
            suggestion: '变量描述的状态（如场景、阶段）最好在世界书里有对应条目解释。',
          ),
        );
      }
    }

    // ---------- 文本质量 ----------

    for (final entry in project.entries) {
      if (!entry.hasContent) {
        continue;
      }
      final content = entry.content;
      final plain = _plainText(content);

      // AI 味词表。
      final hits = <String>[];
      for (final tell in _aiTells) {
        if (plain.contains(tell)) {
          hits.add(tell);
        }
      }
      if (hits.length >= 2) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.text,
            severity: CheckSeverity.info,
            message: '「${entry.title}」用了 ${hits.length} 个常见套话：${hits.take(5).join('、')}',
            entryId: entry.id,
            entryTitle: entry.title,
            suggestion: '换成具体的行为或细节会更有说服力。',
          ),
        );
      }

      // 感叹号密度。
      final exclamations = '！'.allMatches(plain).length +
          '!'.allMatches(plain).length;
      if (plain.length >= 100) {
        final density = exclamations / plain.length * 100;
        if (density > _exclamationThreshold) {
          issues.add(
            CheckIssue(
              id: nextId(),
              category: CheckCategory.text,
              severity: CheckSeverity.info,
              message: '「${entry.title}」感叹号密度偏高',
              entryId: entry.id,
              entryTitle: entry.title,
              suggestion: '情绪靠描写传达比靠标点更有效。',
            ),
          );
        }
      }

      // 重复短语（同一 4 字片段出现 3 次以上）。
      final repeated = _findRepeatedPhrase(plain);
      if (repeated != null) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.text,
            severity: CheckSeverity.info,
            message: '「${entry.title}」里「$repeated」重复出现多次',
            entryId: entry.id,
            entryTitle: entry.title,
            suggestion: '换一种说法，避免读起来像复制粘贴。',
          ),
        );
      }

      // 过短：世界书条目太短通常没信息量。
      if (entry.kind == EntryKind.worldbook && plain.length < 30) {
        issues.add(
          CheckIssue(
            id: nextId(),
            category: CheckCategory.text,
            severity: CheckSeverity.info,
            message: '「${entry.title}」只有 ${plain.length} 字，信息量可能不足',
            entryId: entry.id,
            entryTitle: entry.title,
            suggestion: '世界书条目建议 60 字以上，把「是什么、有什么特点」讲清楚。',
          ),
        );
      }
    }

    // ---------- 前端面板专项 ----------

    issues.addAll(_scanFrontend(project, nextId));

    // 排序：错误 → 警告 → 提示。
    issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));

    return CheckReport(issues: issues, createdAt: DateTime.now());
  }

  /// 前端面板的本地检查。
  ///
  /// 全是「跑了才知道」的坑：WebView 里没有网络、没有框架、高度是宿主量的。
  /// 这些在工坊预览里未必暴露（预览时可能刚好没触发），但到了聊天里就是白屏
  /// 或者面板不动。所以宁可提前说。
  static List<CheckIssue> _scanFrontend(
    CardProject project,
    String Function() nextId,
  ) {
    final html = project.frontendHtml;
    if (html.isEmpty) {
      return const <CheckIssue>[];
    }

    final issues = <CheckIssue>[];
    final lower = html.toLowerCase();

    void report({
      required CheckSeverity severity,
      required String message,
      required String suggestion,
    }) {
      issues.add(
        CheckIssue(
          id: nextId(),
          category: CheckCategory.structure,
          severity: severity,
          message: message,
          entryTitle: '前端面板',
          entryId: project.frontendEntry?.id,
          suggestion: suggestion,
        ),
      );
    }

    // 外链资源：WebView 是 loadHtmlString 加载的，没有网络。
    final hasRemoteAsset = RegExp(
      r'''(src|href)\s*=\s*["']https?://''',
      caseSensitive: false,
    ).hasMatch(lower);
    if (hasRemoteAsset) {
      report(
        severity: CheckSeverity.error,
        message: '面板引用了 http(s) 外链资源',
        suggestion: '聊天里的 WebView 没有网络，外链样式/脚本/图片都加载不出来。'
            '把样式内联进 <style>，图片改成内联 SVG 或 data URI。',
      );
    }

    // 框架：没有模块系统，也没有 CDN。
    final frameworkHits = <String>[
      if (lower.contains('vue')) 'Vue',
      if (lower.contains('react')) 'React',
      if (lower.contains('jquery') || html.contains(r'$(')) 'jQuery',
    ];
    if (frameworkHits.isNotEmpty) {
      report(
        severity: CheckSeverity.warning,
        message: '面板似乎引用了前端框架：${frameworkHits.join('、')}',
        suggestion: '面板里没有 CDN、没有模块加载器，框架跑不起来。'
            '用原生 DOM 操作写。',
      );
    }

    // 高度自测量会被视口高度破坏。
    if (lower.contains('100vh') ||
        RegExp(r'position\s*:\s*fixed').hasMatch(lower)) {
      report(
        severity: CheckSeverity.warning,
        message: '面板用了 100vh 或 position: fixed',
        suggestion: '宿主靠测量内容高度来撑开容器，视口高度会让测量结果失真、'
            '面板被裁掉。改成让内容自然往下排。',
      );
    }

    // 被 WebView 拦掉的对话框。
    if (RegExp(r'\b(alert|confirm|prompt)\s*\(').hasMatch(lower)) {
      report(
        severity: CheckSeverity.warning,
        message: '面板里用了 alert / confirm / prompt',
        suggestion: '这些在 WebView 里会被拦掉，点下去没反应。'
            '把提示画在面板里（比如一行状态文字）。',
      );
    }

    // 没绑变量 = 静态图，模型改了数值面板也不会动。
    final bindsVariables = lower.contains('ykx.');
    if (!bindsVariables) {
      report(
        severity: CheckSeverity.warning,
        message: '面板没有用到任何变量（找不到 YKX. 调用）',
        suggestion: '这块面板是静态的，剧情推进时数值不会变。'
            '用 YKX.getVariable / YKX.onVariablesChanged 把变量接上。',
      );
    } else if (!lower.contains('onvariableschanged')) {
      report(
        severity: CheckSeverity.info,
        message: '面板没有注册 YKX.onVariablesChanged',
        suggestion: '不注册的话，模型改了变量面板不会重绘 —— '
            '只有在页面重新加载时才看得到新值。',
      );
    }

    return issues;
  }

  /// 取出正文（数组型字段存的是 JSON 数组字符串）。
  static String _plainText(String raw) {
    final text = raw.trim();
    if (text.startsWith('[') && text.endsWith(']')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).join('\n');
        }
      } catch (_) {
        // 不是 JSON 就按原文处理。
      }
    }
    return text;
  }

  /// 从结构化变量表里取变量路径。
  static List<String> _readVariablePaths(String variablesJson) {
    final text = variablesJson.trim();
    if (text.isEmpty || !text.startsWith('[')) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        return const <String>[];
      }
      final paths = <String>[];
      for (final item in decoded) {
        if (item is Map) {
          final path = item['path']?.toString().trim() ?? '';
          if (path.isEmpty) {
            continue;
          }
          // 取路径末段（「角色.好感度」→「好感度」），世界书里通常写的是末段。
          final segments = path.split('.');
          paths.add(segments.last.trim());
        }
      }
      return paths;
    } catch (_) {
      return const <String>[];
    }
  }

  /// 找出出现 3 次以上的 4 字片段。找不到返回 null。
  static String? _findRepeatedPhrase(String text) {
    final compact = text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
    if (compact.length < 24) {
      return null;
    }

    const window = 4;
    final counts = <String, int>{};
    for (var i = 0; i + window <= compact.length; i++) {
      final phrase = compact.substring(i, i + window);
      counts[phrase] = (counts[phrase] ?? 0) + 1;
    }

    String? best;
    var bestCount = 0;
    counts.forEach((phrase, count) {
      if (count > bestCount) {
        bestCount = count;
        best = phrase;
      }
    });

    return bestCount >= 3 ? best : null;
  }
}
