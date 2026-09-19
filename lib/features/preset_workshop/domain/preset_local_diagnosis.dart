import 'models/preset_diagnosis.dart';
import 'models/preset_project.dart';
import 'models/preset_slot.dart';
import 'preset_slot_catalog.dart';

/// 诊断用的外部上下文（工坊自己看不到的东西）。
///
/// 这些信息在 actions 层从各 provider 读出来再传进来 ——
/// 保持本文件是**纯函数**，方便单测。
class PresetDiagnosisContext {
  const PresetDiagnosisContext({
    this.characterWorldInfoCount = 0,
    this.globalWorldInfoCount = 0,
    this.activeGlobalRegexCount = 0,
  });

  /// 当前角色卡自带的世界书里，启用的条目数。
  final int characterWorldInfoCount;

  /// 全局世界书池里启用的条目数。
  final int globalWorldInfoCount;

  /// 全局正则池里启用的脚本数。
  final int activeGlobalRegexCount;

  int get worldInfoCount => characterWorldInfoCount + globalWorldInfoCount;
}

/// 本地规则诊断 —— 0 token，进诊断页自动跑。
///
/// ⛔ 这里查的全是**静默出错**：分析器不报、运行时不崩、界面上也看不出异常，
/// 但预设实际效果已经不对了。所以宁可多报一条提示，也别漏。
///
/// 结构层的规则尤其重要 —— 它们是 `Preset.parseWithReport` 那套
/// 「缺 identifier 就补、补进来的默认开启」机制的正面防线。
class PresetLocalDiagnosis {
  const PresetLocalDiagnosis._();

  /// 底部指令超过这个长度就该精简了。
  ///
  /// 思路文档的原话：「底部堆太多会让模型变傻」。
  static const int bottomInstructionLimit = 1200;

  /// 单个槽位超过这个长度会稀释注意力。
  static const int slotLengthLimit = 3000;

  /// 连续同 role 达到这个条数，部分渠道会拒收。
  static const int roleRunLimit = 3;

  /// 填了破限类内容的槽位达到这个数量，就该考虑「是不是下猛药了」。
  static const int jailbreakScatterLimit = 3;

  /// 承担「破限」作用的槽位。
  ///
  /// ⚠️ 这是**启发式**：思路文档说破限应「逐步升级、不要一次上猛药」，
  /// 但代码无法判断一段文本是不是破限 —— 只能数「破限位」有几个被填了。
  static const Set<String> jailbreakSlotIdentifiers = <String>{
    'ykxReset',
    'nsfw',
    'jailbreak',
    'ykxFakeCot',
  };

  /// 本引擎真正会替换的宏。
  ///
  /// ⛔ 名单来自 `ChatNotifier._replaceMacros` 与 `_resolveVariableMacros`：
  /// 只有这四类。酒馆生态里常见的 `{{personality}}` / `{{scenario}}` /
  /// `{{description}}` / `{{mesExamples}}` / `{{time}}` / `{{date}}` **一个都不支持**，
  /// 写了会原样发给模型 —— 静默失效，必须报出来。
  static final RegExp supportedMacroPattern = RegExp(
    r'^\s*(?:'
    r'user|char|charIfNotGroup|group'
    r'|(?:get|set|add|inc|dec)_(?:global|chat)_variable::[^}]+'
    r'|(?:getvar|setvar|addvar|incvar|decvar'
    r'|getglobalvar|setglobalvar|addglobalvar|incglobalvar|decglobalvar)::[^}]+'
    r'|(?:var|chatvar|globalvar)::[^}]+'
    r')\s*$',
  );

  static final RegExp _macroPattern = RegExp(r'\{\{([^{}]*)\}\}');

  static PresetDiagnosisReport run({
    required PresetProject project,
    PresetDiagnosisContext context = const PresetDiagnosisContext(),
  }) {
    final issues = <PresetDiagnosisIssue>[];
    final slots = project.slots;
    final enabled = project.enabledSlots;

    // ── 结构层 ──────────────────────────────────────────────────────────

    _checkHistoryMarker(project, issues);
    _checkMissingEngineSlots(project, issues);
    _checkPrefill(project, enabled, issues);
    _checkRoleRuns(enabled, issues);
    _checkAllDisabled(project, enabled, issues);
    _checkDuplicateIdentifiers(slots, issues);
    _checkUnknownIdentifiers(slots, issues);

    // ── 内容层 ──────────────────────────────────────────────────────────

    _checkBottomInstructionLength(project, issues);
    _checkSlotLength(enabled, issues);
    _checkJailbreakScatter(project, issues);
    _checkSeparatorStyle(enabled, issues);
    _checkMacros(enabled, issues);
    _checkEmptyEnabled(project, issues);

    // ── 冲突层 ──────────────────────────────────────────────────────────

    _checkWorldInfoPlacement(project, context, issues);
    _checkGlobalRegex(context, issues);

    return PresetDiagnosisReport(
      issues: issues,
      ranAt: DateTime.now(),
      aiReviewRequested: project.diagnosis.aiReviewRequested,
    );
  }

  // -------------------------------------------------------------------------
  // 结构层
  // -------------------------------------------------------------------------

  /// 规则 1：`chatHistory` 必须恰好一个，且启用。
  ///
  /// 它是**位置标记**不是内容槽：0 个 → 历史无处插入；多个 → 历史被插多次。
  /// 后者在组装时会让同一段对话出现两遍，而且**不报错**。
  static void _checkHistoryMarker(
    PresetProject project,
    List<PresetDiagnosisIssue> issues,
  ) {
    final all = project.slots
        .where((slot) => slot.identifier == 'chatHistory')
        .toList(growable: false);

    if (all.isEmpty) {
      issues.add(
        const PresetDiagnosisIssue(
          id: 'local.history_marker_missing',
          title: '缺少「聊天记录」槽位',
          detail: '「聊天记录」是历史插入点。没有它，对话历史不会被送进 prompt —— '
              '模型看不到之前聊了什么，会不断「重新开场」。',
          level: PresetIssueLevel.error,
          slotIdentifier: 'chatHistory',
          suggestion: '在结构排布里加回「聊天记录」槽位（它默认是锁定的，不该被删）。',
        ),
      );
      return;
    }

    if (all.length > 1) {
      issues.add(
        PresetDiagnosisIssue(
          id: 'local.history_marker_duplicated',
          title: '「聊天记录」槽位重复 ${all.length} 次',
          detail: '重复的插入点会让同一段历史被送进 prompt 多次，既浪费上下文，'
              '也会让模型以为对话重复发生。导出时会自动去重（只保留第一条），'
              '但顺序可能和你预期的不一样。',
          level: PresetIssueLevel.error,
          slotIdentifier: 'chatHistory',
          suggestion: '只保留一个「聊天记录」槽位。',
        ),
      );
      return;
    }

    if (!all.first.enabled) {
      issues.add(
        const PresetDiagnosisIssue(
          id: 'local.history_marker_disabled',
          title: '「聊天记录」槽位被禁用了',
          detail: '槽位存在但被关闭，等于没有 —— 历史照样进不了 prompt。',
          level: PresetIssueLevel.error,
          slotIdentifier: 'chatHistory',
          suggestion: '把「聊天记录」槽位打开。',
        ),
      );
    }
  }

  /// 规则 2：21 个引擎 identifier 一个都不能少。
  ///
  /// 少了的会在存盘读回时被 `_mergeWithDefaultPromptManagerPrompts` 补回来，
  /// **而且默认 `enabled: true`、追加在列表末尾** ——
  /// 既稀释底部注意力，又让最后一条不再是 assistant，prefill 直接失效。
  static void _checkMissingEngineSlots(
    PresetProject project,
    List<PresetDiagnosisIssue> issues,
  ) {
    final present = project.slots.map((slot) => slot.identifier).toSet();
    final missing =
        kEngineSlotIdentifiers.where((id) => !present.contains(id)).toList();
    if (missing.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.engine_slot_missing',
        title: '缺少 ${missing.length} 个引擎槽位',
        detail: '缺失：${missing.join("、")}。\n'
            '这些槽位在预设存盘读回时会被引擎自动补齐，**而且默认是开启的、'
            '追加在列表末尾** —— 会稀释底部注意力，还会让最后一条消息不再是 assistant，'
            'prefill 直接失效。',
        level: PresetIssueLevel.error,
        suggestion: '重新生成一次结构骨架（模板会自动补齐全部 21 个槽位）。',
      ),
    );
  }

  /// 规则 3：多轮结构下末条启用槽位必须是 assistant。
  ///
  /// 这是 prefill 的全部原理 —— 末尾以 assistant 收尾，模型会直接接着写。
  static void _checkPrefill(
    PresetProject project,
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    if (project.structureKind != PresetStructureKind.multiTurn) {
      return;
    }
    if (enabled.isEmpty) {
      return; // 规则 5 会报。
    }
    final last = enabled.last;
    if (last.role == 'assistant') {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.prefill_broken',
        title: '末尾不是 assistant，prefill 失效',
        detail: '当前结构是「伪造多轮」，但最后一条启用槽位是「${last.label}」'
            '（role = ${last.role}）。\n'
            'prefill 的原理就是让最后一条消息是 assistant —— 模型会当成自己'
            '上一句没说完，直接接着写。末尾不是 assistant 时这个效果就没有了。',
        level: PresetIssueLevel.warning,
        slotIdentifier: last.identifier,
        suggestion: '把「破限（辅助提示）」或「伪造思考 / 破限收尾」的 role 改成 '
            'assistant，并放到最后。',
      ),
    );
  }

  /// 规则 4：连续同 role 的 **user / assistant** 达到 3 条。
  ///
  /// ⛔ **只查 user / assistant，不查 system。** 这不是偷懒，是核实过的：
  /// - `_assemblePromptMessages` 给每个启用槽位各生成一条独立消息，**不合并**；
  /// - OpenAI 兼容适配层 `serializeChatMessages` 原样发出 —— 连续同 role 允许；
  /// - Claude / Gemini 适配层把所有 `system` 消息**提到顶层的系统提示字段**
  ///   （用空行拼接），所以连续多少条 system 都无所谓；
  ///   而 user / assistant 的相邻同 role 会被**合并成一条**，
  ///   硬拼在一起会读起来断裂。
  ///
  /// 所以真正值得提醒的是「被合并」的那两类。
  static void _checkRoleRuns(
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    if (enabled.isEmpty) {
      return;
    }

    final runs = <String>[];
    var runStart = 0;
    for (var i = 1; i <= enabled.length; i++) {
      final ended = i == enabled.length ||
          enabled[i].role != enabled[runStart].role;
      if (!ended) {
        continue;
      }
      final role = enabled[runStart].role;
      final length = i - runStart;
      if (role != 'system' && length >= roleRunLimit) {
        final labels =
            enabled.sublist(runStart, i).map((slot) => slot.label).join(' → ');
        runs.add('$role × $length（$labels）');
      }
      runStart = i;
    }

    if (runs.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.role_run',
        title: '有 ${runs.length} 处连续同 role 的 user/assistant',
        detail: '${runs.join("\n")}\n'
            'Claude / Gemini 会把相邻的同 role user/assistant 消息**合并成一条**'
            '（用空行拼接）。合并之后这几条会连成一段，'
            '如果它们本来是各自独立的意思，读起来就是断裂的。\n'
            '（连续多条 system 不受影响 —— 它们会被提到系统提示里。）',
        level: PresetIssueLevel.warning,
        suggestion: '把同一轮的几条写成连贯的一段，'
            '或者调整 role 让它们交替起来。',
      ),
    );
  }

  /// 规则 5：全禁用 = 预设什么都不会发生。
  static void _checkAllDisabled(
    PresetProject project,
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    if (project.slots.isEmpty || enabled.isNotEmpty) {
      return;
    }
    issues.add(
      const PresetDiagnosisIssue(
        id: 'local.all_disabled',
        title: '所有槽位都被禁用了',
        detail: '这个预设发出去的 prompt 里什么都没有，模型只会按自己的默认行为回复。',
        level: PresetIssueLevel.error,
        suggestion: '至少打开「顶部声明」和「聊天记录」两个槽位。',
      ),
    );
  }

  /// 规则 6：identifier 重复 —— 导出时会去重，后面的内容会**静默丢失**。
  static void _checkDuplicateIdentifiers(
    List<PresetSlot> slots,
    List<PresetDiagnosisIssue> issues,
  ) {
    final counts = <String, int>{};
    for (final slot in slots) {
      final id = slot.identifier.trim();
      if (id.isEmpty) {
        continue;
      }
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final duplicated = counts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => '${entry.key} × ${entry.value}')
        .toList(growable: false);
    if (duplicated.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.identifier_duplicated',
        title: '有 ${duplicated.length} 个重复的槽位标识',
        detail: '${duplicated.join("、")}\n'
            '同一个标识在引擎里只能有一个槽位。导出时会保留第一条、'
            '丢掉后面的 —— 后面那些内容不会报错，但也不会进 prompt。',
        level: PresetIssueLevel.warning,
        suggestion: '删掉重复的槽位，或者把内容合并进第一个。',
      ),
    );
  }

  /// 规则 6b：外部导入的、引擎和工坊都不认识的 identifier。
  ///
  /// 不报错（内容会原样进 prompt），但要提示用户它不受引擎控制。
  static void _checkUnknownIdentifiers(
    List<PresetSlot> slots,
    List<PresetDiagnosisIssue> issues,
  ) {
    final unknown = slots
        .map((slot) => slot.identifier.trim())
        .where((id) => id.isNotEmpty && !isEngineSlot(id) && !id.startsWith('ykx'))
        .toSet()
        .toList(growable: false);
    if (unknown.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.unknown_identifier',
        title: '有 ${unknown.length} 个外部槽位',
        detail: '${unknown.join("、")}\n'
            '这些标识不是本引擎自带的，引擎不会往里填内容 —— '
            '它们的内容会原样拼进 prompt。多用于从外部工具导入的预设。',
        level: PresetIssueLevel.info,
        suggestion: '如果不需要，可以直接删掉这些槽位。',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容层
  // -------------------------------------------------------------------------

  /// 规则 7：底部指令太长。
  ///
  /// 文档：「底部堆太多会让模型变傻」—— 底部的强注意力位要精简。
  static void _checkBottomInstructionLength(
    PresetProject project,
    List<PresetDiagnosisIssue> issues,
  ) {
    final jailbreak = project.slotOf('jailbreak');
    if (jailbreak == null || !jailbreak.enabled) {
      return;
    }
    final length = jailbreak.content.trim().length;
    if (length <= bottomInstructionLimit) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.bottom_too_long',
        title: '底部指令有 $length 字，偏长',
        detail: '底部是强注意力位，适合放「最需要被听进去的」几条指令。\n'
            '堆太多会挤占注意力 —— 文档的原话是「会让模型变傻」：'
            '它可能记住了格式要求，却忘了扮演本身。\n'
            '建议控制在 $bottomInstructionLimit 字以内。',
        level: PresetIssueLevel.warning,
        slotIdentifier: 'jailbreak',
        suggestion: '把可放可不放的内容挪到「顶部声明」，底部只留文风、人称、语言、'
            '字数、硬约束这几条。',
      ),
    );
  }

  /// 规则 8：单槽位过长 → 注意力稀释。
  static void _checkSlotLength(
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    final long = enabled
        .where((slot) => slot.content.trim().length > slotLengthLimit)
        .toList(growable: false);
    if (long.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.slot_too_long',
        title: '有 ${long.length} 个槽位超过 $slotLengthLimit 字',
        detail: long
            .map((slot) => '「${slot.label}」${slot.content.trim().length} 字')
            .join('\n'),
        level: PresetIssueLevel.info,
        suggestion: '长内容建议拆成多个槽位，或挪进世界书按需触发。',
      ),
    );
  }

  /// 规则 9：破限手段铺得太开。
  ///
  /// ⚠️ 启发式 —— 代码无法判断文本是不是破限，只能数「破限位」被填了几个。
  static void _checkJailbreakScatter(
    PresetProject project,
    List<PresetDiagnosisIssue> issues,
  ) {
    final filled = project.slots
        .where((slot) =>
            slot.enabled &&
            jailbreakSlotIdentifiers.contains(slot.identifier) &&
            slot.hasContent)
        .map((slot) => slot.label)
        .toList(growable: false);
    if (filled.length < jailbreakScatterLimit) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.jailbreak_scattered',
        title: '有 ${filled.length} 处填了破限类内容',
        detail: '${filled.join("、")}\n'
            '文档的比喻：「构建破限就像医生开药，直接下猛药当然可以药到病除，'
            '但对身体的破坏也很大」。\n'
            '同一个预设里铺这么多处，容易让模型「变傻」—— 只顾着配合，忘了扮演质量。',
        level: PresetIssueLevel.warning,
        suggestion: '按「轻 → 中 → 重」逐步升级：先只留最需要的那一处，不够再往上加。',
      ),
    );
  }

  /// 规则 10：分割标记风格混用。
  ///
  /// 同一个预设里混用 markdown 分隔线、XML 标签、自定义符号，
  /// 会让模型难以判断「板块边界」，尤其在多轮伪造结构里。
  static void _checkSeparatorStyle(
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    const markdown = 'markdown 分隔线（--- / *** / ###）';
    const xml = 'XML 标签（<tag>…</tag>）';
    const custom = '自定义符号（=== / ___ / ◆ 等）';

    final styles = <String>{};
    for (final slot in enabled) {
      if (!slot.hasContent) {
        continue;
      }
      final text = slot.content;
      if (RegExp(r'^\s*(?:-{3,}|\*{3,}|#{2,})\s*$', multiLine: true)
          .hasMatch(text)) {
        styles.add(markdown);
      }
      if (RegExp(r'</?[a-zA-Z][\w:-]*\s*/?>').hasMatch(text)) {
        styles.add(xml);
      }
      if (RegExp(r'^\s*(?:={3,}|_{3,}|[◆◇■□●○]{1,})\s*$', multiLine: true)
          .hasMatch(text)) {
        styles.add(custom);
      }
    }

    if (styles.length < 2) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.separator_style',
        title: '分割标记混用了 ${styles.length} 种风格',
        detail: '${styles.join("\n")}\n'
            '风格不统一时，模型对「板块从哪开始、到哪结束」的判断会变模糊，'
            '容易把两个板块的要求混在一起。',
        level: PresetIssueLevel.info,
        suggestion: '统一成一种风格。XML 标签在多轮伪造结构里最稳（可以跨消息闭合）。',
      ),
    );
  }

  /// 规则 11：宏拼写 —— 本引擎**只认四类宏**，其余会原样发给模型。
  ///
  /// 这是最容易踩的坑：预设是从酒馆生态抄来的话，
  /// `{{personality}}` / `{{scenario}}` / `{{time}}` 这些看着很正常，实际一个都不生效。
  static void _checkMacros(
    List<PresetSlot> enabled,
    List<PresetDiagnosisIssue> issues,
  ) {
    final unsupported = <String>{};
    final padded = <String>{};

    for (final slot in enabled) {
      if (!slot.hasContent) {
        continue;
      }
      for (final match in _macroPattern.allMatches(slot.content)) {
        final inner = match.group(1) ?? '';
        if (inner.trim().isEmpty) {
          continue;
        }
        // 引擎是 `replaceAll('{{char}}', ...)` 精确匹配 ——
        // `{{ char }}` 里有空格就匹配不上，等于没写。
        if (inner != inner.trim()) {
          padded.add('{{$inner}}');
          continue;
        }
        if (!supportedMacroPattern.hasMatch(inner)) {
          unsupported.add('{{$inner}}');
        }
      }
    }

    if (padded.isNotEmpty) {
      issues.add(
        PresetDiagnosisIssue(
          id: 'local.macro_whitespace',
          title: '有 ${padded.length} 个宏带了多余空格',
          detail: '${padded.join("、")}\n'
              '引擎是按 `{{char}}` 这样的精确字符串做替换的，'
              '大括号里多一个空格就匹配不上 —— 宏会原样发给模型。',
          level: PresetIssueLevel.warning,
          suggestion: '去掉大括号内侧的空格。',
        ),
      );
    }

    if (unsupported.isNotEmpty) {
      final shown = unsupported.take(12).toList(growable: false);
      issues.add(
        PresetDiagnosisIssue(
          id: 'local.unknown_macro',
          title: '有 ${unsupported.length} 个宏本引擎不支持',
          detail: '${shown.join("、")}'
              '${unsupported.length > shown.length ? " …等" : ""}\n'
              '本引擎只替换这几类：`{{char}}`、`{{user}}`、`{{charIfNotGroup}}`、'
              '`{{group}}`，以及变量宏（`{{getvar::名}}` / `{{setvar::名::值}}` / '
              '`{{get_chat_variable::名}}` 等）。\n'
              '其余（酒馆生态常见的 `{{personality}}`、`{{scenario}}`、`{{time}}` 等）'
              '**不会被替换，会原样发给模型** —— 这是静默失效，界面上看不出异常。',
          level: PresetIssueLevel.warning,
          suggestion: '把不支持的宏改成对应的槽位引用（比如把 `{{scenario}}` 换成'
              '「场景」槽位的内容），或直接删掉。',
        ),
      );
    }
  }

  /// 规则 12：启用但内容为空。
  ///
  /// 排除 marker（内容由引擎填）、排除用户自填槽（破限留空是正常选择）。
  static void _checkEmptyEnabled(
    PresetProject project,
    List<PresetDiagnosisIssue> issues,
  ) {
    final empty = project.enabledSlots
        .where((slot) =>
            !slot.marker && !slot.userOwned && !slot.hasContent)
        .map((slot) => slot.label)
        .toList(growable: false);
    if (empty.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.empty_enabled',
        title: '有 ${empty.length} 个槽位开着但没内容',
        detail: '${empty.join("、")}\n'
            '这些槽位占着位置却不产生任何消息，白占注意力。',
        level: PresetIssueLevel.info,
        suggestion: '要么补上内容，要么关掉它们。',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 冲突层
  // -------------------------------------------------------------------------

  /// 规则 13：世界书槽位被禁用，但确实有启用的世界书条目。
  ///
  /// 世界书找不到指定位置时会另找地方插入，可能打乱整个结构。
  static void _checkWorldInfoPlacement(
    PresetProject project,
    PresetDiagnosisContext context,
    List<PresetDiagnosisIssue> issues,
  ) {
    if (context.worldInfoCount <= 0) {
      return;
    }

    final disabled = <String>[];
    for (final identifier in const <String>['worldInfoBefore', 'worldInfoAfter']) {
      final slot = project.slotOf(identifier);
      if (slot != null && !slot.enabled) {
        disabled.add(slot.label);
      }
    }
    if (disabled.isEmpty) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.world_info_disabled',
        title: '有 ${context.worldInfoCount} 条启用世界书，但世界书槽位是关的',
        detail: '被关掉的：${disabled.join("、")}\n'
            '世界书槽位决定世界书内容插在 prompt 的哪个位置。关掉之后，'
            '引擎会退回到默认位置插入 —— 你的结构就被打乱了。',
        level: PresetIssueLevel.info,
        suggestion: '如果这个预设要配合世界书用，把「世界书（角色设定前）」打开。',
      ),
    );
  }

  /// 规则 14：全局正则池里有启用的脚本，可能改写预设写的指令块。
  static void _checkGlobalRegex(
    PresetDiagnosisContext context,
    List<PresetDiagnosisIssue> issues,
  ) {
    if (context.activeGlobalRegexCount <= 0) {
      return;
    }

    issues.add(
      PresetDiagnosisIssue(
        id: 'local.global_regex_active',
        title: '有 ${context.activeGlobalRegexCount} 条全局正则在生效',
        detail: '全局正则会作用在模型输出上（也可能作用在输入上）。\n'
            '如果其中某条规则匹配了预设里的指令块格式，'
            '它可能会把指令改掉 —— 表现是「预设明明写了却不生效」。',
        level: PresetIssueLevel.info,
        suggestion: '如果预设效果不符合预期，先到「设置 → 正则」里逐条关掉试试。',
      ),
    );
  }
}
