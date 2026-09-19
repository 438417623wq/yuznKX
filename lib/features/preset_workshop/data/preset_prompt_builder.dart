import '../../chat/domain/models/chat_message.dart';
import '../domain/models/preset_diagnosis.dart';
import '../domain/models/preset_project.dart';
import '../domain/models/preset_slot.dart';
import '../domain/preset_slot_catalog.dart';

/// 预设工坊的提示词装配层。
///
/// 共同原则（照 `ProjectPromptBuilder` 的约定）：
/// - **格式约束写死在 system**，创作内容放在 user；
/// - 每个阶段的输出都是**单个 JSON 对象**，复用同一套解析容错；
/// - 生成时不带无关上下文，只带「需求 + 结构表 + 该槽位的意图」。
class PresetPromptBuilder {
  const PresetPromptBuilder._();

  /// 格式修复重试时追加的提醒。
  static const String repairNote =
      '【重要】你上一次的输出无法被解析为合法 JSON。请重新输出，只输出一个 JSON 对象，'
      '不要任何解释、标题或 Markdown 代码块。\n'
      '如果上次是因为内容太长被截断，请把每个槽位的内容压缩到 300 字以内。';

  static ChatMessage _system(String content) =>
      ChatMessage(role: 'system', content: content, timestamp: DateTime.now());

  static ChatMessage _user(String content) =>
      ChatMessage(role: 'user', content: content, timestamp: DateTime.now());

  static String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  // ============================================================
  // 共用的「预设工程学」说明
  // ============================================================

  /// 写预设的方法论 —— 直接对应《预设思路》。
  ///
  /// 每个生成类提示词都带上它，避免模型按「写一段角色设定」的思路来写预设。
  static String _methodology() {
    return '''
【预设是什么】
SillyTavern 的预设是一串按顺序发给模型的消息。顺序 = 最终 prompt 的顺序，
所以**调整结构就是在调整模型的注意力分布**：
- 开头（顶部）与结尾（底部）的注意力最强，适合放「这次要做什么」和「必须遵守什么」；
- 中间（数据区）注意力最弱，适合放设定资料、世界书、角色卡这类「查阅型」内容；
- 聊天记录的位置决定了模型把「过去」看得多重。

【role 的意义】
每条槽位都有一个 role（system / user / assistant）：
- 全部用 system：兼容性最好，任何渠道都认。
- user / assistant 交替：可以「伪造多轮对话」，让模型以为自己已经在扮演中。
- **末尾以 assistant 收尾 = prefill**：模型会当成自己上一句没说完，直接接着写。
  这是让扮演立刻进入状态最有效的手段。

【写作要求】
- 写的是**给模型看的指令**，不是给用户看的说明。要短、要具体、要可执行。
- 不要出现「你可以…」「建议…」「如果需要…」这类含糊措辞，直接下命令或直接陈述。
- 不要写「作为一个 AI」之类的自我指涉，也不要解释你在做什么。
- 每个槽位只负责一件事。跨槽位重复同一句要求会稀释注意力。
- 破限不是越多越好：「就像医生开药，直接下猛药当然可以药到病除，但对身体的破坏也很大」。
  按档位来，低档够用就不上高档。''';
  }

  /// 结构表：让模型看到「有哪些槽位、什么 role、什么顺序、要写什么」。
  static String _slotTable(PresetProject project) {
    final buffer = StringBuffer();
    var index = 0;
    for (final slot in project.slots) {
      index++;
      final marker = slot.marker ? '【内容由引擎填】' : '';
      final owned = slot.userOwned ? '【用户自填，不要写】' : '';
      final state = slot.enabled ? '启用' : '关闭';
      buffer.writeln(
        '$index. $state | role=${slot.role} | 「${slot.label}」$marker$owned',
      );
      if (slot.intent.trim().isNotEmpty) {
        buffer.writeln('   意图：${slot.intent.trim()}');
      }
      if (slot.content.trim().isNotEmpty && !slot.userOwned) {
        buffer.writeln('   当前内容：${_shorten(slot.content, 200)}');
      }
    }
    return buffer.toString();
  }

  /// 需求块。
  static String _briefBlock(PresetProject project) {
    final text = project.brief.toPromptText();
    return text.trim().isEmpty ? '（未填写需求）' : text;
  }

  /// 待生成的槽位（可被 AI 写的）。
  static List<PresetSlot> editableSlots(PresetProject project) => project.slots
      .where((slot) => slot.enabled && !slot.marker && !slot.userOwned)
      .toList(growable: false);

  // ============================================================
  // 阶段：填充内容（一次生成全部可写槽位）
  // ============================================================

  static List<ChatMessage> buildGenerateSlots({required PresetProject project}) {
    final targets = editableSlots(project);
    final structure = project.structureKind;

    final system = StringBuffer()
      ..writeln('你是「预设工程师」，专门为 SillyTavern 写扮演预设。')
      ..writeln()
      ..writeln(_methodology())
      ..writeln()
      ..writeln('【本次结构类型】${structure.label} —— ${structure.description}')
      ..writeln(
        structure == PresetStructureKind.multiTurn
            ? '注意：这是**伪造多轮**结构。\n'
                '- 每个启用槽位都会成为**独立的一条消息**，引擎不合并。\n'
                '- OpenAI 兼容渠道原样发出（连续同 role 允许）。\n'
                '- Claude / Gemini 会把相邻的**同 role user/assistant 合并成一条**'
                '（用空行拼接），并把所有 system 消息提到最前面的系统提示里。\n'
                '所以：需要「同一轮里说几件事」时写成**连贯的一段话**，'
                '不要写成互相独立、各说各话的段落 —— 否则在 Claude 上会被硬拼在一起，'
                '读起来是断裂的。'
            : '注意：这是**单块**结构，所有内容都走 system。'
                '在 Claude / Gemini 上这些 system 消息会被合并成一份系统提示；'
                '在 OpenAI 兼容渠道上则是连续多条 system。'
                '每个槽位写一段独立、自洽的指令。',
      )
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('1. 只输出一个 JSON 对象，禁止任何解释、开场白或 Markdown 代码块。')
      ..writeln('2. 结构固定为：{"slots": [{"identifier": "槽位标识", "content": "正文"}, ...]}')
      ..writeln('3. **每个待生成槽位都必须出现一次**，identifier 原样照抄，不要改、不要漏。')
      ..writeln('4. 字符串内部禁止真实换行 —— 需要换行时写 \\n。')
      ..writeln('5. 不要给标记为「内容由引擎填」或「用户自填」的槽位写内容。')
      ..writeln('6. 每个槽位的正文控制在 400 字以内，宁可精炼。');

    final user = StringBuffer()
      ..writeln('【预设名】${project.name}')
      ..writeln()
      ..writeln('【扮演需求】')
      ..writeln(_briefBlock(project))
      ..writeln()
      ..writeln('【结构表（顺序 = 消息顺序）】')
      ..writeln(_slotTable(project))
      ..writeln()
      ..writeln('【需要你写内容的槽位】')
      ..writeln(targets.map((slot) => slot.identifier).join('、'))
      ..writeln()
      ..writeln('【额外要求】')
      ..writeln('- 「${slotLabelOf('main')}」写清本次扮演的方式与名词约定，'
          '以及文风、人称、语言、输出量的总要求。')
      ..writeln('- 「${slotLabelOf('jailbreak')}」是底部强注意力位，**只放最关键的几条硬约束**，'
          '越短越好（200 字以内）。')
      ..writeln('- 「${slotLabelOf('ykxHistoryOpen')}」与「${slotLabelOf('ykxHistoryClose')}」'
          '用来把聊天记录包进一对标签：前一条以开标签收尾，后一条以闭标签开头，'
          '中间不要写别的。标签名自拟一个独特的（例如 <game_save>）。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 单槽位重新生成
  // ============================================================

  static List<ChatMessage> buildRegenerateSlot({
    required PresetProject project,
    required PresetSlot slot,
    String userHint = '',
  }) {
    final system = StringBuffer()
      ..writeln('你是「预设工程师」。现在**只重写一个槽位**。')
      ..writeln()
      ..writeln(_methodology())
      ..writeln()
      ..writeln('【输出格式】')
      ..writeln('只输出一个 JSON 对象：{"content": "正文"}，不要任何其它字段或解释。')
      ..writeln('字符串内部禁止真实换行，需要换行时写 \\n。');

    final user = StringBuffer()
      ..writeln('【扮演需求】')
      ..writeln(_briefBlock(project))
      ..writeln()
      ..writeln('【完整结构（供你判断上下文）】')
      ..writeln(_slotTable(project))
      ..writeln()
      ..writeln('【要重写的槽位】${slot.identifier}（「${slot.label}」，role=${slot.role}）')
      ..writeln('该槽位的意图：${slot.intent.trim().isEmpty ? "（未标注）" : slot.intent.trim()}');
    if (slot.content.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【当前内容（要替换掉）】')
        ..writeln(slot.content.trim());
    }
    if (userHint.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【用户的额外要求】')
        ..writeln(userHint.trim());
    }
    user
      ..writeln()
      ..writeln('【要求】只写这一个槽位的内容，不要顺带改别的槽位。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 对话式微调
  // ============================================================

  static List<ChatMessage> buildRefine({
    required PresetProject project,
    required String instruction,
    String? focusSlotIdentifier,
  }) {
    final system = StringBuffer()
      ..writeln('你是「预设工程师」。用户会对当前预设提出修改要求，你来改。')
      ..writeln()
      ..writeln(_methodology())
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('只输出一个 JSON 对象：')
      ..writeln('{"reply": "一句话说明你改了什么", '
          '"slots": [{"identifier": "槽位标识", "content": "改后的完整正文"}]}')
      ..writeln()
      ..writeln('【重要】')
      ..writeln('- `slots` 里**只放真正改动过的槽位**，没改的一个都不要带。')
      ..writeln('- 每条是**改后的完整正文**，不是差异片段 —— 会整段替换掉原来的内容。')
      ..writeln('- 不要改槽位的顺序、role 或开关，那些由用户自己调。')
      ..writeln('- 字符串内部禁止真实换行，需要换行时写 \\n。');

    final user = StringBuffer()
      ..writeln('【扮演需求】')
      ..writeln(_briefBlock(project))
      ..writeln()
      ..writeln('【当前预设全文】')
      ..writeln(_slotTable(project))
      ..writeln()
      ..writeln('【用户的要求】')
      ..writeln(instruction.trim());
    if (focusSlotIdentifier != null && focusSlotIdentifier.trim().isNotEmpty) {
      user
        ..writeln()
        ..writeln('【用户当前正在看】$focusSlotIdentifier'
            '（如果要求含糊，优先理解为针对这个槽位）');
    }

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // AI 复核诊断
  // ============================================================

  static List<ChatMessage> buildReview({required PresetProject project}) {
    final system = StringBuffer()
      ..writeln('你是「预设质检员」，负责找出这份预设里的**语义层问题**。')
      ..writeln()
      ..writeln('【只报这几类问题】')
      ..writeln('1. 指令歧义 —— 模型可能理解成别的意思。')
      ..writeln('2. 自相矛盾 —— 两处要求互相冲突（例如一处要简洁、一处要详尽）。')
      ..writeln('3. 指令冲突 —— 与角色卡 / 世界书的常规写法打架。')
      ..writeln('4. 不可执行 —— 要求太抽象，模型无法照着做（例如「文笔要好」）。')
      ..writeln('5. 结构性问题 —— 某个槽位的内容放错了位置（该放底部的放了顶部）。')
      ..writeln()
      ..writeln('【输出格式】必须严格遵守：')
      ..writeln('只输出一个 JSON 对象：')
      ..writeln('{"issues": [{"title": "一句话问题", "detail": "为什么是问题", '
          '"level": "error|warning|info", "slotIdentifier": "槽位标识或空字符串", '
          '"suggestion": "具体怎么改"}]}')
      ..writeln()
      ..writeln('【纪律】')
      ..writeln('- **只报你确定的问题**，最多 12 条。宁可少报，不要凑数。')
      ..writeln('- 没发现问题就返回 {"issues": []}。')
      ..writeln('- 不要报错别字、标点、格式这类小事。')
      ..writeln('- 不要建议「增加更多细节」这种没有落点的东西。')
      ..writeln('- 字符串内部禁止真实换行，需要换行时写 \\n。');

    final user = StringBuffer()
      ..writeln('【扮演需求】')
      ..writeln(_briefBlock(project))
      ..writeln()
      ..writeln('【预设全文】')
      ..writeln(_slotTable(project))
      ..writeln()
      ..writeln('注意：标记为「内容由引擎填」的槽位（世界书、角色卡、聊天记录）'
          '在运行时才注入，这里看不到内容是正常的，不要因此报问题。');

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }

  // ============================================================
  // 逐条修复
  // ============================================================

  static List<ChatMessage> buildRepairSlot({
    required PresetProject project,
    required PresetSlot slot,
    required PresetDiagnosisIssue issue,
  }) {
    final system = StringBuffer()
      ..writeln('你是「预设工程师」。质检发现了下面这个问题，你来修。')
      ..writeln()
      ..writeln(_methodology())
      ..writeln()
      ..writeln('【输出格式】')
      ..writeln('只输出一个 JSON 对象：{"content": "修好之后的完整正文"}')
      ..writeln('字符串内部禁止真实换行，需要换行时写 \\n。')
      ..writeln()
      ..writeln('【纪律】')
      ..writeln('- 只改这一个槽位。')
      ..writeln('- **只改问题相关的部分**，其余原文尽量保持不动 —— 用户可能已经手改过。')
      ..writeln('- 不要顺手「优化」文风或加内容。');

    final user = StringBuffer()
      ..writeln('【扮演需求】')
      ..writeln(_briefBlock(project))
      ..writeln()
      ..writeln('【要修的槽位】${slot.identifier}（「${slot.label}」，role=${slot.role}）')
      ..writeln()
      ..writeln('【当前内容】')
      ..writeln(slot.content.trim().isEmpty ? '（空）' : slot.content.trim())
      ..writeln()
      ..writeln('【质检问题】${issue.title}')
      ..writeln(issue.detail)
      ..writeln();
    if (issue.suggestion.trim().isNotEmpty) {
      user
        ..writeln('【建议的修法】')
        ..writeln(issue.suggestion.trim());
    }

    return <ChatMessage>[_system(system.toString()), _user(user.toString())];
  }
}
