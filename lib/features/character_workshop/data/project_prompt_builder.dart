import '../../chat/domain/models/chat_message.dart';
import '../domain/models/card_field.dart';
import '../domain/models/card_project.dart';
import '../domain/models/check_report.dart';
import '../domain/models/design_spec.dart';
import '../domain/models/project_entry.dart';

/// 创作工坊的提示词装配层。
///
/// 四个阶段各一套提示词。共同原则：
/// - **格式约束写死在 system**，创作内容放在 user；
/// - 每个阶段的输出都是**单个 JSON 对象**，便于复用同一套解析容错；
/// - 逐条生成时**只带已完成条目的标题与摘要**，不带全文 ——
///   这是上下文不随进度增长的关键。
class ProjectPromptBuilder {
  const ProjectPromptBuilder._();

  /// 格式修复重试时追加的提醒。
  static const String repairNote =
      '【重要】你上一次的输出无法被解析为合法 JSON。请重新输出，只输出一个 JSON 对象，'
      '不要任何解释、标题或 Markdown 代码块。';

  static ChatMessage _system(String content) =>
      ChatMessage(role: 'system', content: content, timestamp: DateTime.now());

  static ChatMessage _user(String content) =>
      ChatMessage(role: 'user', content: content, timestamp: DateTime.now());

  static String languageHint(OutputLanguage language) {
    switch (language) {
      case OutputLanguage.zh:
        return '简体中文';
      case OutputLanguage.en:
        return 'English';
      case OutputLanguage.auto:
        return '与【创作需求】相同的语言';
    }
  }

  static String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  // ============================================================
  // 阶段一：需求对齐
  // ============================================================

  /// 为某个维度生成候选方案。
  static List<ChatMessage> buildDesignCandidates({
    required CardProject project,
    required SpecDimension dimension,
    required OutputLanguage language,
    String userHint = '',
  }) {
    final system = StringBuffer()
      ..writeln('你是「角色卡设计师」，正在与用户做创作需求对齐。')
      ..writeln('用户要制作一张 SillyTavern 角色卡。现在**只讨论一个维度**：')
      ..writeln('【${dimension.label}】')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释、开场白或 Markdown 代码块。')
      ..writeln('2. 结构固定为：{"candidates": ["方案一", "方案二", "方案三"]}')
      ..writeln('3. 数组里给 3 个方案，每个 60~150 字。')
      ..writeln('4. 字符串内部禁止真实换行。')
      ..writeln()
      ..writeln('【要求】')
      ..writeln('- 三个方案必须**明显不同**，各有取舍（例如一个轻松、一个沉重、一个悬疑）。')
      ..writeln('- 每个方案都要具体：写清题材、设定、取向与卖点，不要堆空泛形容词。')
      ..writeln('- 方案要能直接拿来用，不是「可以更黑暗一些」这类建议。')
      ..writeln('- 语言：${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln();
    final confirmed = project.designSpec.toPromptBlock();
    if (confirmed.isNotEmpty) {
      user
        ..writeln('【已确认的需求】')
        ..writeln(confirmed)
        ..writeln();
    }
    user
      ..writeln('【当前要讨论的维度】${dimension.label}')
      ..writeln('这一维要回答的问题：${dimension.question}')
      ..writeln('补充说明：${dimension.hint}');
    if (userHint.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【用户自己的想法】')
        ..writeln(userHint.trim());
    }
    user
      ..writeln()
      ..writeln('请给出 3 个候选方案。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 阶段二：创作规划
  // ============================================================

  /// 产出条目清单（只列标题与职责，不写正文）。
  static List<ChatMessage> buildPlan({
    required CardProject project,
    required Set<String> fieldKeys,
    required int worldbookTarget,
    required bool mvuEnabled,
    required bool ejsEnabled,
    required OutputLanguage language,
    String userHint = '',
  }) {
    final fieldList = fieldKeys
        .map((key) {
          final field = cardFieldByKey(key);
          if (field == null) {
            return null;
          }
          return '- "$key"（${field.label}）：${field.instruction}';
        })
        .whereType<String>()
        .join('\n');

    final system = StringBuffer()
      ..writeln('你是「角色卡设计师」。用户已完成需求对齐，现在要你**制定创作规划**。')
      ..writeln()
      ..writeln('【极其重要】这一步**只列清单，不写任何正文**。')
      ..writeln('每条只需要说清楚「这条负责写什么」，具体内容留到下一步逐条产出。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"summary": "整体规划说明", "entries": [ ... ]}')
      ..writeln('3. entries 里每项的结构：')
      ..writeln('   {"kind": "...", "fieldKey": "...", "title": "...", '
          '"brief": "...", "keys": ["..."], "order": 100}')
      ..writeln('4. kind 只能取以下值：')
      ..writeln('   - "characterCard"：角色卡字段（必须带 fieldKey）')
      ..writeln('   - "worldbook"：世界书条目（关键词触发的设定）')
      ..writeln('   - "timeline"：时间线/世界历史')
      ..writeln('   - "event"：可被触发的剧情事件')
      ..writeln('   - "variableSchema"：动态变量结构（仅在需要变量时）')
      ..writeln('   - "greeting"：开场白')
      ..writeln('5. 字符串内部禁止真实换行。')
      ..writeln()
      ..writeln('【各字段说明】')
      ..writeln('- title：条目标题，2~10 个字，要能一眼看出这条写什么。')
      ..writeln('- brief：这条要写什么，20~60 字，具体到能指导写作。')
      ..writeln('- keys：**只有 worldbook / event / timeline 需要**，'
          '2~5 个会被用户消息触发的关键词。characterCard 与 greeting 留空数组。')
      ..writeln('- order：排序用，10 的倍数。角色卡字段从 10 起，世界书条目从 100 起。')
      ..writeln()
      ..writeln('【角色卡字段清单】必须且只能包含以下字段：')
      ..writeln(fieldList)
      ..writeln()
      ..writeln('【世界书要求】')
      ..writeln('- 规划 **$worldbookTarget 条左右**世界书条目，覆盖：'
          '核心地点、关键组织、重要术语或规则、以及会反复出现的配角。')
      ..writeln('- 每条 keys 必须给足，否则条目永远触发不了 —— 这是最常见的废卡原因。')
      ..writeln('- 条目之间不要重复覆盖同一个概念。');

    if (mvuEnabled) {
      system
        ..writeln()
        ..writeln('【动态变量】用户需要动态变量，请额外规划 1 条 '
            'kind 为 "variableSchema" 的条目，title 用「变量结构」。');
    }
    if (ejsEnabled) {
      system
        ..writeln()
        ..writeln('【EJS 模板】用户需要 EJS 动态方案。请在需要条件渲染的条目 '
            'brief 里注明「用 EJS 条件渲染」，并说明条件依赖哪些变量。');
    }
    system.writeln('- 语言：${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【需求对齐结果】')
      ..writeln(project.designSpec.toPromptBlock());
    if (userHint.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【用户补充要求】')
        ..writeln(userHint.trim());
    }
    user
      ..writeln()
      ..writeln('请输出创作规划 JSON。记住：只列清单，不要写正文。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 阶段三：逐条产出
  // ============================================================

  /// 写单条内容。
  ///
  /// [completed] 只传已完成条目的**标题与摘要**，不传全文 ——
  /// 上下文因此恒定，不随进度增长。
  static List<ChatMessage> buildEntryWrite({
    required CardProject project,
    required ProjectEntry entry,
    required List<ProjectEntry> completed,
    required EntryLength length,
    required OutputLanguage language,
    String userHint = '',
  }) {
    final isList = entry.kind == EntryKind.characterCard &&
        (cardFieldByKey(entry.fieldKey)?.isList ?? false);

    final system = StringBuffer()
      ..writeln('你是「角色卡设计师」，正在为一张 SillyTavern 角色卡撰写内容。')
      ..writeln('本次**只写一条**：${entry.title}')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。');
    if (isList) {
      system
        ..writeln('2. 结构固定为：{"items": ["第一项", "第二项", "第三项"]}')
        ..writeln('3. items 是数组，每项独立完整。');
    } else {
      system
        ..writeln('2. 结构固定为：{"content": "正文"}')
        ..writeln('3. 需要分段时在字符串里写 \\n，禁止真实换行。');
    }
    system
      ..writeln('4. 只输出这一个键，不要附带其它字段。')
      ..writeln()
      ..writeln('【写作要求】')
      ..writeln('- 用具体的行为、习惯、口癖和细节体现性格，不要堆砌空泛形容词。')
      ..writeln('- 所有内容必须与已完成的条目保持一致，不要引入矛盾设定。')
      ..writeln('- 字数：${length.hint}。')
      ..writeln('- 语言：${languageHint(language)}。');

    if (entry.kind == EntryKind.worldbook) {
      system
        ..writeln()
        ..writeln('【世界书条目写作要点】')
        ..writeln('- 写成「设定说明」而不是「剧情片段」，用陈述语气。')
        ..writeln('- 直接给出信息，不要写「据说」「也许」这类含糊表述。')
        ..writeln('- 不要复述关键词本身，要解释它是什么、有什么特点。');
    } else if (entry.kind == EntryKind.characterCard &&
        entry.fieldKey == 'first_mes') {
      system
        ..writeln()
        ..writeln('【开场白写作要点】')
        ..writeln('- 先写环境与动作描写（可用括号包裹动作），再接角色的台词。')
        ..writeln('- 结尾要留出用户回应的空间，不要自问自答。')
        ..writeln('- 不要替用户说话或代替用户做决定。');
    } else if (entry.kind == EntryKind.characterCard &&
        entry.fieldKey == 'mes_example') {
      system
        ..writeln()
        ..writeln('【示例对话写作要点】')
        ..writeln('- 用 <START> 分隔每一轮。')
        ..writeln('- 用户方用 {{user}}，角色方用 {{char}} 作为名字。');
    }
    if (project.plan.ejsEnabled) {
      system
        ..writeln()
        ..writeln('【EJS】如本条需要条件渲染，用 <%_ ... _%> 与 <%= ... %> '
            '写出 EJS 模板（只输出模板文本，不需要能运行）。');
    }

    final user = StringBuffer()
      ..writeln('【需求对齐结果】')
      ..writeln(project.designSpec.toPromptBlock())
      ..writeln()
      ..writeln('【本条任务】')
      ..writeln('- 类型：${entry.kind.label}')
      ..writeln('- 标题：${entry.title}');
    if (entry.brief.trim().isNotEmpty) {
      user.writeln('- 要写什么：${entry.brief.trim()}');
    }
    if (entry.keys.isNotEmpty) {
      user.writeln('- 触发关键词：${entry.keys.join('、')}');
    }

    if (completed.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【已完成条目（仅供保持设定一致，不要重复写这些内容）】');
      for (final item in completed) {
        final summary = _shorten(item.content, 120);
        user.writeln('- ${item.title}：$summary');
      }
    }

    if (userHint.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【用户对这条的额外要求】')
        ..writeln(userHint.trim());
    }

    user
      ..writeln()
      ..writeln('请输出 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 阶段四：MVU 动态变量
  // ============================================================

  /// 产出 MVU 三件套（schema.ts / initvar.yaml / 变量更新规则.yaml）+ 结构化变量表。
  static List<ChatMessage> buildMvu({
    required CardProject project,
    required OutputLanguage language,
  }) {
    final system = StringBuffer()
      ..writeln('你是 SillyTavern MVU 变量系统的专家。请为这张角色卡设计动态变量。')
      ..writeln()
      ..writeln('MVU 需要三份产物：')
      ..writeln('1. schema.ts —— 用 Zod 定义变量结构（TypeScript 源码）。')
      ..writeln('2. initvar.yaml —— 变量初始值，层级必须与 schema 一致。')
      ..writeln('3. 变量更新规则.yaml —— 每个变量什么时候更新、取值范围如何。')
      ..writeln()
      ..writeln('【变量命名约定】')
      ..writeln('- 无前缀：AI 可见且可更新（普通变量）。')
      ..writeln('- `_` 前缀：AI 可见但不可更新（派生状态）。')
      ..writeln('- `\$` 前缀：AI 不可见也不可更新（隐藏状态）。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"schema": "...", "initvar": "...", "updateRules": "...", '
          '"variables": [{"path": "角色.好感度", "type": "number", '
          '"range": "0~100", "initial": "35", "note": "对用户的好感"}]}')
      ..writeln('3. schema / initvar / updateRules 三个字段的值是**完整源码文本**，'
          '内部换行一律写成 \\n。')
      ..writeln('4. variables 是结构化变量表，path 用点分隔（如 `角色.好感度`）。')
      ..writeln()
      ..writeln('【设计要求】')
      ..writeln('- 变量数量控制在 5~15 个，只放真正需要跨轮次追踪的状态。')
      ..writeln('- 不要用变量存一次性描述，那是世界书条目的职责。')
      ..writeln('- schema 中枚举型变量，每个取值都要有明确含义。')
      ..writeln('- initvar 的层级必须与 schema 一致，取值必须是**具体数字或字符串**，'
          '不要写表达式或占位符。')
      ..writeln('- variables 里每一项都要给 `initial` —— 它是运行时的初始值来源，'
          '缺了面板会显示兜底 0。')
      ..writeln('- updateRules 写成**可直接执行**的分条自然语言（不要 YAML 结构），'
          '每条说明「变量路径 → 触发条件 → 变化量」，'
          '例如「角色.好感度：主角帮助了角色时 +5，被冒犯时 -10，范围 0~100」。'
          '它会被原样喂给模型当更新规则。')
      ..writeln('- 语言：变量名与注释用${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【需求对齐结果】')
      ..writeln(project.designSpec.toPromptBlock());

    final worldbookTitles = project.worldbookEntries
        .map((entry) => entry.title)
        .where((title) => title.trim().isNotEmpty)
        .toList();
    if (worldbookTitles.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【已有的世界书条目】')
        ..writeln(worldbookTitles.join('、'))
        ..writeln()
        ..writeln('变量的取值应与这些条目描述的世界观自洽。');
    }

    user
      ..writeln()
      ..writeln('请输出 MVU 变量设计 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 阶段四·五：前端面板
  // ============================================================

  /// 生成前端状态面板（一段自包含的 HTML + CSS + JS）。
  static List<ChatMessage> buildFrontend({
    required CardProject project,
    required OutputLanguage language,
    String userHint = '',
  }) {
    final system = StringBuffer()
      ..writeln('你是「前端角色卡」专家。请为这张角色卡写一块**自包含**的状态面板。')
      ..writeln();
    _writeFrontendRuntimeRules(system);
    system
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"html": "...", "variables": [{"path": "角色.好感度", "initial": 30}], '
          '"notes": "一句话说明这块面板展示什么"}')
      ..writeln('3. html 的值是**完整的 HTML 源码文本**，'
          '内部换行一律写成 \\n，内部的双引号写成 \\"。')
      ..writeln('4. variables 列出面板用到的变量路径与建议初始值，'
          '供作者在预览里调试。')
      ..writeln('- 语言：面板上的文案用${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【需求对齐结果】')
      ..writeln(project.designSpec.toPromptBlock());

    final mvuTable = project.mvuVariablesJson.trim();
    if (mvuTable.isNotEmpty && mvuTable != '[]') {
      user
        ..writeln()
        ..writeln('【已有的变量表（面板应优先展示这些变量）】')
        ..writeln(
          mvuTable.length > 2400
              ? '${mvuTable.substring(0, 2400)}…'
              : mvuTable,
        );
    }

    final worldbookTitles = project.worldbookEntries
        .map((entry) => entry.title)
        .where((title) => title.trim().isNotEmpty)
        .toList();
    if (worldbookTitles.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【已有的世界书条目】')
        ..writeln(worldbookTitles.join('、'));
    }

    if (userHint.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【作者额外要求】')
        ..writeln(userHint.trim());
    }

    user
      ..writeln()
      ..writeln('请输出前端面板 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  /// 前端面板的「运行环境 + 变量 API + 写法要求」。
  ///
  /// [buildFrontend] 与 [buildFrontendRefine] 共用 —— 两处必须给出**完全一致**
  /// 的约束，否则「生成时守规矩、迭代时跑偏」会变成很难查的问题。
  static void _writeFrontendRuntimeRules(StringBuffer buffer) {
    buffer
      ..writeln('【运行环境 —— 必须严格遵守】')
      ..writeln('1. 面板会以 HTML 字符串塞进一个 WebView 渲染，**没有网络**：'
          '不能引 CDN、外链字体、外部图片，也不能用 Vue / React / jQuery 等框架。')
      ..writeln('2. 只能是一段自包含的 HTML：样式写在 <style>，逻辑写在 <script>。')
      ..writeln('3. 宿主会自己测量页面高度来撑开容器。**不要**用 100vh / 100% 高度、'
          '不要 position: fixed、不要 overflow: hidden 裁掉内容 —— 让内容自然往下排。')
      ..writeln('4. 按手机屏幕考虑宽度（约 340~400px），字号 12~14px。')
      ..writeln('5. 深色背景（例如 #0f1720），文字用浅色，保证在聊天界面里看得清。')
      ..writeln()
      ..writeln('【变量 API —— 宿主注入的 window.YKX】')
      ..writeln('- YKX.getVariable("路径") 读一个变量；YKX.getVariables() 读全部。')
      ..writeln('- YKX.setVariable("路径", 值) 写一个变量。')
      ..writeln('- YKX.addVariable("路径", 增量) 数值增减（会自动解析成数字）。')
      ..writeln('- YKX.deleteVariable("路径") 删一个变量。')
      ..writeln('- YKX.onVariablesChanged(function (vars, reason) { ... }) '
          '变量变化时重绘。**必须注册它**，否则模型改了变量面板不会更新。')
      ..writeln('- YKX.log("...") 往客户端的调试面板打日志。')
      ..writeln()
      ..writeln('【写法要求】')
      ..writeln('- 变量读不到时要有默认值，不能让面板空白：'
          'var v = Number(YKX.getVariable(k)); if (!isFinite(v)) { v = 0; }')
      ..writeln('- 面板要"看得懂"：用进度条、数值、状态标签，不要只有一坨文字。')
      ..writeln('- 不要用 alert / confirm / prompt，WebView 里会被拦掉。');
  }

  /// 按用户的一句话要求**修改现有面板**（对话式迭代）。
  ///
  /// ⛔ 要求模型输出**完整替换后的 HTML**，不要 diff ——
  /// 模型对 diff 的准确率远低于重写，「改一半」的 HTML 直接是坏产物。
  static List<ChatMessage> buildFrontendRefine({
    required CardProject project,
    required OutputLanguage language,
    required String currentHtml,
    required String instruction,
  }) {
    final system = StringBuffer()
      ..writeln('你是「前端角色卡」专家。用户已经有一块状态面板，'
          '现在要按新要求修改它。')
      ..writeln();
    _writeFrontendRuntimeRules(system);
    system
      ..writeln()
      ..writeln('【修改原则】')
      ..writeln('1. 在**保留现有面板全部功能**的前提下做增量修改。')
      ..writeln('2. ⛔ 输出**完整替换后的 HTML**，不要输出 diff、不要输出片段、'
          '不要写「…保持不变…」。')
      ..writeln('3. ⛔ 用户没要求删的字段与功能，一个都不要删。')
      ..writeln('4. 用户要求新增的字段，如果变量表里已有对应路径就直接用；'
          '没有的话按同名风格起一个，并在 notes 里说明。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"html": "...", "notes": "一句话说明这次改了什么"}')
      ..writeln('3. html 是**完整源码文本**，内部换行一律写成 \\n，'
          '内部的双引号写成 \\"。')
      ..writeln('- 语言：面板上的文案用${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【用户的新要求】')
      ..writeln(instruction.trim());

    final mvuTable = project.mvuVariablesJson.trim();
    if (mvuTable.isNotEmpty && mvuTable != '[]') {
      user
        ..writeln()
        ..writeln('【可用的变量表】')
        ..writeln(
          mvuTable.length > 2400 ? '${mvuTable.substring(0, 2400)}…' : mvuTable,
        );
    }

    user
      ..writeln()
      ..writeln('【当前面板 HTML】')
      ..writeln('<<<')
      ..writeln(currentHtml.trim())
      ..writeln('>>>')
      ..writeln()
      ..writeln('请输出修改后的完整面板 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 质检：AI 复核
  // ============================================================

  /// AI 复核 —— 通读全部设定找矛盾。
  ///
  /// 本地规则（`text_quality_scanner.dart`）只能做字符串层面的检查
  /// （缺字段、AI 味、重复短语），**读不懂设定语义**。这一段补上：
  /// 人设走形、前后矛盾、变量与设定冲突、开场白脱节。
  ///
  /// [localIssueSummary] 是本地已经报出的问题，喂进去避免重复报。
  static List<ChatMessage> buildReview({
    required CardProject project,
    required OutputLanguage language,
    required List<String> localIssueSummary,
  }) {
    final system = StringBuffer()
      ..writeln('你是严格的角色卡质检员。请通读这张卡的全部设定，找出**真实存在**的问题。')
      ..writeln()
      ..writeln('【重点检查】')
      ..writeln('1. 设定一致性：世界观规则有没有自相矛盾的地方。')
      ..writeln('2. 人设走形：角色卡字段里的性格描述，与世界书 / 开场白里的言行是否一致。')
      ..writeln('3. 前后矛盾：条目之间有没有互相打架的陈述。')
      ..writeln('4. 变量与设定冲突：变量表里的字段与设定描述对不上。')
      ..writeln('5. 开场白脱节：first_mes 与设定是否吻合，有没有引入未定义的设定。')
      ..writeln()
      ..writeln('【严格要求】')
      ..writeln('- ⛔ **只报你确定的问题**。宁可漏报，不要误报 —— '
          '误报会让作者花时间去改本来没问题的东西。')
      ..writeln('- 不要报「可以更详细」「建议补充」这类主观意见。')
      ..writeln('- 不要报下面已经列出的问题（本地规则已经查过了）。')
      ..writeln('- 每条问题必须能指出**具体位置**（哪一条条目 / 哪个字段）。')
      ..writeln('- 真的没问题就输出空数组，不要硬凑数量。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"issues":[{"severity":"error|warning|info",'
          '"category":"consistency|structure|text",'
          '"message":"问题描述（一句话）",'
          '"entryTitle":"出问题的条目标题（必须与下面给出的标题完全一致）",'
          '"suggestion":"具体怎么改（要能直接照着改）"}]}')
      ..writeln('3. 最多 12 条，按 severity 从重到轻排。')
      ..writeln('- 语言：${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【需求对齐结果】')
      ..writeln(project.designSpec.toPromptBlock());

    final fields = project.characterFieldEntries
        .where((entry) => entry.hasContent)
        .toList();
    if (fields.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【角色卡字段】');
      for (final entry in fields) {
        user
          ..writeln('--- ${entry.title} ---')
          ..writeln(clipForPrompt(entry.content.trim(), 1200));
      }
    }

    final worldbook = project.worldbookEntries
        .where((entry) => entry.hasContent)
        .toList();
    if (worldbook.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【世界书条目】');
      for (final entry in worldbook) {
        user
          ..writeln('--- ${entry.title} ---')
          ..writeln(clipForPrompt(entry.content.trim(), 800));
      }
    }

    final frontend = project.frontendHtml.trim();
    if (frontend.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【前端面板 HTML（节选）】')
        ..writeln(clipForPrompt(frontend, 1500));
    }

    final mvu = project.mvuVariablesJson.trim();
    if (mvu.isNotEmpty && mvu != '[]') {
      user
        ..writeln()
        ..writeln('【变量表】')
        ..writeln(clipForPrompt(mvu, 1500));
    }

    if (localIssueSummary.isNotEmpty) {
      user
        ..writeln()
        ..writeln('【本地规则已经报出的问题（不要再报）】');
      for (final line in localIssueSummary) {
        user.writeln('- $line');
      }
    }

    user
      ..writeln()
      ..writeln('请输出质检结果 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  /// 截断过长文本（喂给 AI 的上下文要有上限）。
  static String clipForPrompt(String text, int max) =>
      text.length > max ? '${text.substring(0, max)}…' : text;

  // ============================================================
  // 质检：逐条修复
  // ============================================================

  /// 按一条质检意见修复某段内容。
  ///
  /// ⛔ 输出**完整替换后的内容**，不要 diff —— 模型对 diff 的准确率远低于
  /// 重写，「改一半」的内容直接是坏产物（与 `buildFrontendRefine` 同一条理由）。
  static List<ChatMessage> buildIssueRepair({
    required CardProject project,
    required OutputLanguage language,
    required CheckIssue issue,
    required String entryTitle,
    required String currentContent,
    required bool isFrontend,
  }) {
    final system = StringBuffer()
      ..writeln('你是角色卡编辑。请按质检意见修改下面这段内容。')
      ..writeln()
      ..writeln('【修改原则】')
      ..writeln('1. ⛔ 只改与这条问题相关的部分，**不要顺手重写其它内容**。')
      ..writeln('2. 保持原有的写作风格、人称、语气、格式'
          '（条目是 Markdown 就还是 Markdown）。')
      ..writeln('3. 输出**完整的修改后内容**，不要输出 diff、'
          '不要写「其余保持不变」这类省略。')
      ..writeln('4. 不要引入新的设定 —— 只解决被指出的问题。');
    if (isFrontend) {
      system.writeln('5. 这是前端面板 HTML：必须保持自包含（无 CDN、无框架）、'
          '不要用 100vh / position: fixed、变量读写继续用 window.YKX。');
    }
    system
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"content": "修改后的完整内容", "notes": "一句话说明改了什么"}')
      ..writeln('3. content 的值里，内部换行一律写成 \\n，'
          '内部的双引号写成 \\"。')
      ..writeln('- 语言：${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】${project.name}')
      ..writeln()
      ..writeln('【内容所属】${isFrontend ? '前端面板 HTML' : entryTitle}')
      ..writeln()
      ..writeln('【质检问题】')
      ..writeln('- 严重程度：${issue.severity.label}')
      ..writeln('- 问题：${issue.message}');

    final suggestion = issue.suggestion?.trim() ?? '';
    if (suggestion.isNotEmpty) {
      user.writeln('- 建议：$suggestion');
    }

    user
      ..writeln()
      ..writeln('【当前内容】')
      ..writeln('<<<')
      ..writeln(currentContent)
      ..writeln('>>>')
      ..writeln()
      ..writeln('请输出修改后的完整内容 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 材料拆解
  // ============================================================

  /// 从一段材料里提取六个维度的信息。
  static List<ChatMessage> buildMaterialExtract({
    required String projectName,
    required String chunk,
    required int chunkIndex,
    required int chunkTotal,
    required OutputLanguage language,
  }) {
    final system = StringBuffer()
      ..writeln('你是「角色卡设计师」。用户提供了一段创作素材，'
          '请从中提取信息，用于填写角色卡的需求对齐表。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释或 Markdown 代码块。')
      ..writeln('2. 结构固定为：')
      ..writeln('{"positioning": "...", "worldview": "...", "characters": "...", '
          '"dynamics": "...", "direction": "...", "opening": "..."}')
      ..writeln('3. 每个字段的值是**从素材中提取/归纳出的结论**，'
          '不是建议也不是提问。')
      ..writeln('4. 素材里没有涉及的维度，值填空字符串 ""，不要编造。')
      ..writeln('5. 每个字段控制在 200 字以内，字符串内部禁止真实换行。')
      ..writeln()
      ..writeln('【六个维度的含义】');
    for (final dimension in SpecDimension.values) {
      system.writeln('- ${dimension.key}（${dimension.label}）：${dimension.hint}');
    }
    system.writeln('- 语言：${languageHint(language)}。');

    final user = StringBuffer()
      ..writeln('【项目名】$projectName')
      ..writeln()
      ..writeln('【素材片段 ${chunkIndex + 1}/$chunkTotal】')
      ..writeln(chunk)
      ..writeln()
      ..writeln('请提取信息并输出 JSON。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }
}
