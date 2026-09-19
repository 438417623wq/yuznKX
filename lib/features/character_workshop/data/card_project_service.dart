import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../api_connection/data/api_connection_provider.dart';
import '../../api_connection/domain/models/api_connection.dart';
import '../../chat/data/chat_provider.dart';
import '../../chat/domain/models/chat_message.dart';
import '../domain/models/card_field.dart';
import '../domain/models/card_project.dart';
import '../domain/models/check_report.dart';
import '../domain/models/design_spec.dart';
import '../domain/models/project_entry.dart';
import 'project_prompt_builder.dart';

/// 工坊异常：`message` 直接面向用户，`rawOutput` 用于排查。
class WorkshopException implements Exception {
  WorkshopException(this.message, {this.rawOutput});

  final String message;
  final String? rawOutput;

  @override
  String toString() => message;
}

/// 创作规划阶段的结果。
class PlanResult {
  PlanResult({required this.summary, required this.entries});

  final String summary;

  /// 条目骨架（content 为空）。
  final List<ProjectEntry> entries;
}

/// MVU 设计结果。
class MvuResult {
  MvuResult({
    required this.schema,
    required this.initvar,
    required this.updateRules,
    required this.variablesJson,
  });

  final String schema;
  final String initvar;
  final String updateRules;

  /// 结构化变量表（JSON 字符串）。
  final String variablesJson;
}

final cardProjectServiceProvider =
    Provider<CardProjectService>((ref) => CardProjectService(ref));

/// 创作工坊的 AI 服务层。
///
/// 只做「拼提示词 → 调模型 → 解析 JSON」，不持有任何 UI 状态。
/// 四套提示词的输出格式都统一成单个 JSON 对象，因此可以共用同一套解析容错。
class CardProjectService {
  CardProjectService(this._ref);

  final Ref _ref;

  /// 格式失败时最多再让模型重发几次。
  static const int _maxRepairAttempts = 2;

  // 各阶段的采样温度：对齐要发散、规划要稳、写作要活、变量要准、提取要忠实。
  static const double _tempDesign = 0.95;
  static const double _tempPlan = 0.7;
  static const double _tempWrite = 0.85;
  static const double _tempMvu = 0.5;
  static const double _tempExtract = 0.3;
  static const double _tempFrontend = 0.6;

  /// AI 复核与逐条修复都要「稳定复现」，温度压到最低档。
  static const double _tempReview = 0.2;

  // ============================================================
  // 阶段一：需求对齐
  // ============================================================

  /// 为某个维度生成 3 个候选方案。
  Future<List<String>> generateDesignCandidates({
    required CardProject project,
    required SpecDimension dimension,
    required OutputLanguage language,
    String userHint = '',
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildDesignCandidates(
        project: project,
        dimension: dimension,
        language: language,
        userHint: userHint,
      ),
      temperature: _tempDesign,
      maxTokens: 1600,
      stageText: '正在为「${dimension.label}」想方案…',
    );

    final candidates = _readStringList(parsed['candidates']);
    if (candidates.isEmpty) {
      throw WorkshopException('模型没有给出候选方案，请重试。');
    }
    return candidates;
  }

  // ============================================================
  // 阶段二：创作规划
  // ============================================================

  /// 产出条目清单。
  Future<PlanResult> generatePlan({
    required CardProject project,
    required Set<String> fieldKeys,
    required int worldbookTarget,
    required bool mvuEnabled,
    required bool ejsEnabled,
    required OutputLanguage language,
    String userHint = '',
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildPlan(
        project: project,
        fieldKeys: fieldKeys,
        worldbookTarget: worldbookTarget,
        mvuEnabled: mvuEnabled,
        ejsEnabled: ejsEnabled,
        language: language,
        userHint: userHint,
      ),
      temperature: _tempPlan,
      maxTokens: 3000,
      stageText: '正在制定创作规划…',
    );

    final rawEntries = parsed['entries'];
    if (rawEntries is! List || rawEntries.isEmpty) {
      throw WorkshopException('模型没有产出条目清单，请重试。');
    }

    final entries = <ProjectEntry>[];
    for (final item in rawEntries) {
      if (item is! Map) {
        continue;
      }
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final title = map['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        continue;
      }
      final kind = EntryKind.fromKey(map['kind']?.toString());
      final orderRaw = map['order'];
      final order = orderRaw is num
          ? orderRaw.toInt()
          : int.tryParse(orderRaw?.toString() ?? '') ?? 100;

      entries.add(
        ProjectEntry(
          id: _newId(),
          title: title,
          kind: kind,
          brief: map['brief']?.toString().trim() ?? '',
          fieldKey: map['fieldKey']?.toString().trim() ?? '',
          keys: _readStringList(map['keys']),
          order: order,
        ),
      );
    }

    if (entries.isEmpty) {
      throw WorkshopException('模型产出的条目清单是空的，请重试。');
    }

    return PlanResult(
      summary: parsed['summary']?.toString().trim() ?? '',
      entries: entries,
    );
  }

  // ============================================================
  // 阶段三：逐条产出
  // ============================================================

  /// 写单条内容，返回可直接存入 `entry.content` 的文本。
  ///
  /// 数组型字段会存成 JSON 数组字符串（由打包器统一拆分）。
  Future<String> writeEntry({
    required CardProject project,
    required ProjectEntry entry,
    required List<ProjectEntry> completed,
    required EntryLength length,
    required OutputLanguage language,
    String userHint = '',
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildEntryWrite(
        project: project,
        entry: entry,
        completed: completed,
        length: length,
        language: language,
        userHint: userHint,
      ),
      temperature: _tempWrite,
      maxTokens: length.maxTokens,
      stageText: '正在写「${entry.title}」…',
      onDelta: onDelta,
      onStage: onStage,
    );

    // 数组型字段：模型可能返回 items 数组，也可能直接给 content 文本。
    final items = parsed['items'];
    if (items is List) {
      final values = items
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isEmpty) {
        throw WorkshopException('模型返回的 items 是空数组。');
      }
      return jsonEncode(values);
    }

    final content = parsed['content']?.toString().trim() ?? '';
    if (content.isEmpty) {
      throw WorkshopException('模型返回的内容是空的。');
    }
    return content;
  }

  // ============================================================
  // 阶段四：MVU 动态变量
  // ============================================================

  Future<MvuResult> generateMvu({
    required CardProject project,
    required OutputLanguage language,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildMvu(
        project: project,
        language: language,
      ),
      temperature: _tempMvu,
      maxTokens: 4000,
      stageText: '正在设计动态变量…',
    );

    final schema = parsed['schema']?.toString().trim() ?? '';
    final initvar = parsed['initvar']?.toString().trim() ?? '';
    final updateRules = parsed['updateRules']?.toString().trim() ?? '';
    if (schema.isEmpty && initvar.isEmpty && updateRules.isEmpty) {
      throw WorkshopException('模型没有返回 MVU 变量设计，请重试。');
    }

    final variables = parsed['variables'];
    return MvuResult(
      schema: schema,
      initvar: initvar,
      updateRules: updateRules,
      variablesJson: variables is List ? jsonEncode(variables) : '[]',
    );
  }

  // ============================================================
  // 阶段四·五：前端面板
  // ============================================================

  /// 生成前端状态面板，返回可直接存进 `entry.content` 的 HTML 源码。
  ///
  /// 返回的是**原始 HTML**，不是 JSON —— JSON 那层只是传输格式，
  /// 拆包之后就丢掉，避免把转义过的字符串一路带进预览和角色卡。
  Future<String> generateFrontend({
    required CardProject project,
    required OutputLanguage language,
    String userHint = '',
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildFrontend(
        project: project,
        language: language,
        userHint: userHint,
      ),
      temperature: _tempFrontend,
      // 面板 HTML 通常比一段设定长得多，给足预算。
      maxTokens: 6000,
      stageText: '正在设计前端面板…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final html = _readFrontendHtml(parsed['html']);
    if (html.isEmpty) {
      throw WorkshopException('模型没有返回面板 HTML，请重试。');
    }
    return html;
  }

  /// 读文本字段。
  ///
  /// 名字里有 Frontend 是历史原因，实际通用于任何「模型吐一坨文本」的字段
  /// （面板 HTML、条目正文都走它）。容错点：模型偶尔会把长文本拆成数组。
  String _readFrontendHtml(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    if (value is List) {
      return value
          .map((item) => item.toString())
          .join('\n')
          .trim();
    }
    return '';
  }

  /// 按用户的一句话要求修改现有面板（对话式迭代）。
  ///
  /// ⛔ **不直接落库** —— 返回 HTML 交给 UI 做「待确认」，
  /// 用户看过预览、对比过版本再决定要不要应用。
  Future<String> refineFrontend({
    required CardProject project,
    required OutputLanguage language,
    required String currentHtml,
    required String instruction,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildFrontendRefine(
        project: project,
        language: language,
        currentHtml: currentHtml,
        instruction: instruction,
      ),
      temperature: _tempFrontend,
      maxTokens: 6000,
      stageText: '正在按你的要求修改面板…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final html = _readFrontendHtml(parsed['html']);
    if (html.isEmpty) {
      throw WorkshopException('模型没有返回面板 HTML，请重试。');
    }
    return html;
  }

  // ============================================================
  // 质检：AI 复核
  // ============================================================

  /// AI 复核：读全部设定找矛盾。
  ///
  /// 返回的问题 `source` 一律是 [CheckSource.ai]。
  /// [localIssues] 会被转成「已经报过的问题」清单喂进去，避免重复。
  Future<List<CheckIssue>> reviewCard({
    required CardProject project,
    required OutputLanguage language,
    required List<CheckIssue> localIssues,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildReview(
        project: project,
        language: language,
        localIssueSummary: localIssues
            .map(
              (issue) => issue.entryTitle == null || issue.entryTitle!.isEmpty
                  ? issue.message
                  : '${issue.entryTitle}：${issue.message}',
            )
            .toList(growable: false),
      ),
      temperature: _tempReview,
      maxTokens: 3000,
      stageText: '正在通读设定找矛盾…',
      onStage: onStage,
    );

    final raw = parsed['issues'];
    if (raw is! List) {
      return const <CheckIssue>[];
    }

    final issues = <CheckIssue>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) {
        continue;
      }
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final message = map['message']?.toString().trim() ?? '';
      if (message.isEmpty) {
        continue;
      }
      final title = map['entryTitle']?.toString().trim() ?? '';
      issues.add(
        CheckIssue(
          id: 'ai_${DateTime.now().microsecondsSinceEpoch}_$index',
          category: CheckCategory.fromKey(map['category']?.toString()),
          severity: CheckSeverity.fromKey(map['severity']?.toString()),
          message: message,
          entryId: _findEntryIdByTitle(project, title),
          entryTitle: title.isEmpty ? null : title,
          suggestion: map['suggestion']?.toString().trim(),
          source: CheckSource.ai,
        ),
      );
    }
    return issues;
  }

  /// 按标题找条目 ID（模型给的标题未必逐字一致，做两级匹配）。
  String? _findEntryIdByTitle(CardProject project, String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final entry in project.entries) {
      if (entry.title.trim() == normalized) {
        return entry.id;
      }
    }
    for (final entry in project.entries) {
      final entryTitle = entry.title.trim();
      if (entryTitle.isEmpty) {
        continue;
      }
      if (normalized.contains(entryTitle) || entryTitle.contains(normalized)) {
        return entry.id;
      }
    }
    return null;
  }

  // ============================================================
  // 质检：逐条修复
  // ============================================================

  /// 按一条质检意见修复内容，返回**完整替换后**的文本。
  ///
  /// ⛔ 不落库 —— 由 UI 先做 diff 预览，用户确认了再应用。
  Future<String> repairIssue({
    required CardProject project,
    required OutputLanguage language,
    required CheckIssue issue,
    required String entryTitle,
    required String currentContent,
    required bool isFrontend,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildIssueRepair(
        project: project,
        language: language,
        issue: issue,
        entryTitle: entryTitle,
        currentContent: currentContent,
        isFrontend: isFrontend,
      ),
      temperature: _tempReview,
      maxTokens: isFrontend ? 6000 : 3000,
      stageText: '正在按质检意见修复…',
    );

    final content = _readFrontendHtml(parsed['content']);
    if (content.trim().isEmpty) {
      throw WorkshopException('模型没有返回修复后的内容，请重试。');
    }
    return content;
  }

  // ============================================================
  // 材料拆解
  // ============================================================

  /// 从一段材料里提取六个维度。
  Future<Map<String, String>> extractMaterialChunk({
    required String projectName,
    required String chunk,
    required int chunkIndex,
    required int chunkTotal,
    required OutputLanguage language,
  }) async {
    final parsed = await _run(
      messages: ProjectPromptBuilder.buildMaterialExtract(
        projectName: projectName,
        chunk: chunk,
        chunkIndex: chunkIndex,
        chunkTotal: chunkTotal,
        language: language,
      ),
      temperature: _tempExtract,
      maxTokens: 1400,
      stageText: '正在拆解素材（${chunkIndex + 1}/$chunkTotal）…',
    );

    final result = <String, String>{};
    for (final dimension in SpecDimension.values) {
      final value = parsed[dimension.key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        result[dimension.key] = value;
      }
    }
    return result;
  }

  // ============================================================
  // 内部：调用 + 解析容错
  // ============================================================

  Future<Map<String, dynamic>> _run({
    required List<ChatMessage> messages,
    required double temperature,
    required int maxTokens,
    required String stageText,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final connection = _requireConnection();
    var currentMessages = messages;
    String? lastRaw;
    String? lastError;

    for (var attempt = 0; attempt <= _maxRepairAttempts; attempt++) {
      final isRepair = attempt > 0;
      onStage?.call(
        isRepair ? '输出格式有误，正在重试（$attempt/$_maxRepairAttempts）…' : stageText,
      );

      final raw = await _requestText(
        connection: connection,
        messages: currentMessages,
        temperature: temperature,
        maxTokens: maxTokens,
        // 修复重试不推流，避免预览里出现半截的错误输出。
        onDelta: isRepair ? null : onDelta,
      );
      lastRaw = raw;

      try {
        final parsed = _parseJsonObject(raw);
        if (parsed.isEmpty) {
          throw WorkshopException('模型返回了空对象。');
        }
        return parsed;
      } catch (error) {
        lastError =
            error is WorkshopException ? error.message : error.toString();
        final repairMessages = List<ChatMessage>.from(messages);
        final note = StringBuffer()
          ..write('\n\n${ProjectPromptBuilder.repairNote}')
          ..write('\n失败原因：${_shorten(lastError, 160)}');
        // 把提醒追加到最后一条 user 消息上。
        for (var i = repairMessages.length - 1; i >= 0; i--) {
          if (repairMessages[i].role == 'user') {
            repairMessages[i] =
                repairMessages[i].copyWith(content: '${repairMessages[i].content}$note');
            break;
          }
        }
        currentMessages = repairMessages;
      }
    }

    throw WorkshopException(
      '生成失败：模型连续 ${_maxRepairAttempts + 1} 次都没有返回合法 JSON。'
      '${lastError == null ? '' : '\n最后原因：$lastError'}',
      rawOutput: lastRaw,
    );
  }

  ApiConnection _requireConnection() {
    final connection = _ref.read(activeApiConnectionProvider);
    if (connection == null) {
      throw WorkshopException('还没有可用的 API 连接，请先到「设置 → API 连接」里添加并选中一个。');
    }
    return connection;
  }

  Future<String> _requestText({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    required double temperature,
    required int maxTokens,
    void Function(String delta)? onDelta,
  }) async {
    final service = _ref.read(chatServiceProvider);

    // 工坊是独立的一次性请求：不读聊天记录、不注入记忆与世界书。
    final parameters = <String, dynamic>{
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    final buffer = StringBuffer();
    await for (final event in service.streamMessage(
      connection: connection,
      messages: messages,
      parameters: parameters,
    )) {
      final text = event.text;
      if (text == null || text.isEmpty) {
        continue;
      }
      buffer.write(text);
      onDelta?.call(text);
    }

    final result = buffer.toString();
    if (result.trim().isEmpty) {
      throw WorkshopException('模型没有返回任何内容，请检查 API 连接与模型名是否正确。');
    }
    return result;
  }

  /// 三级容错：去代码围栏 → 截取首尾大括号 → 修掉尾随逗号与裸换行后重试解析。
  ///
  /// 这套逻辑是从旧版工坊原样搬过来的 —— JSON 修复能力是攒出来的，不重写。
  Map<String, dynamic> _parseJsonObject(String raw) {
    final candidate = _extractJsonObject(raw);
    if (candidate == null) {
      throw WorkshopException('模型输出里找不到 JSON 对象。');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (firstError) {
      // 模型最常见的两种手滑：对象/数组末尾多一个逗号；长文本里漏写 \n 转义。
      final repaired = _escapeRawNewlinesInStrings(
        candidate.replaceAllMapped(
          RegExp(r',\s*([}\]])'),
          (match) => match.group(1) ?? '',
        ),
      );
      try {
        decoded = jsonDecode(repaired);
      } catch (_) {
        throw WorkshopException(
          '模型输出的 JSON 无法解析：${_shorten(firstError.toString(), 120)}',
        );
      }
    }

    if (decoded is! Map) {
      throw WorkshopException('模型输出的不是一个 JSON 对象。');
    }

    var map = decoded.map((key, value) => MapEntry(key.toString(), value));

    // 有些模型会自作主张套一层 {"data": {...}} / {"result": {...}}。
    for (final wrapper in const <String>['data', 'result', 'character', 'card']) {
      final inner = map[wrapper];
      if (inner is Map &&
          (inner.containsKey('candidates') ||
              inner.containsKey('entries') ||
              inner.containsKey('content') ||
              inner.containsKey('items') ||
              inner.containsKey('schema') ||
              inner.containsKey('positioning'))) {
        map = inner.map((key, value) => MapEntry(key.toString(), value));
        break;
      }
    }
    return map;
  }

  /// 逐字符扫描，把字符串字面量内部的裸换行补成 `\n`。
  ///
  /// 中文模型写长文本时经常忘记转义换行，这是 JSON 解析失败的头号原因。
  /// 裸换行无法用简单的正则安全匹配，所以用状态机扫描。
  String _escapeRawNewlinesInStrings(String input) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (!inString) {
        if (char == '"') {
          inString = true;
        }
        buffer.write(char);
        continue;
      }

      if (escaped) {
        escaped = false;
        buffer.write(char);
        continue;
      }

      if (char == '\\') {
        escaped = true;
        buffer.write(char);
        continue;
      }

      if (char == '"') {
        inString = false;
        buffer.write(char);
        continue;
      }

      if (char == '\n') {
        buffer.write(r'\n');
        continue;
      }

      if (char == '\r') {
        continue;
      }

      if (char == '\t') {
        buffer.write(r'\t');
        continue;
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  String? _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final fenced = RegExp(r'```[a-zA-Z]*\s*([\s\S]*?)```').firstMatch(text);
    if (fenced != null) {
      text = (fenced.group(1) ?? '').trim();
    } else if (text.contains('```')) {
      text = text.replaceAll('```', '').trim();
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return text.substring(start, end + 1);
  }

  List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      // 模型偶尔会把数组写成顿号分隔的字符串。
      return value
          .split(RegExp(r'[,，、;；\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  static String _newId() => const Uuid().v4();
}
