/// 预设工坊里的一个「槽位」—— 引擎 `PresetPrompt` 的工坊侧表示。
///
/// **槽位的顺序 = 最终发给模型的消息顺序**（见 `_assemblePromptMessages`），
/// 所以 [PresetProject.slots] 的列表顺序就是预设的结构。
///
/// 槽位分两类：
/// - **引擎默认槽位**（`main` / `worldInfoBefore` / `charDescription` …）：
///   [identifier] 必须原样保留，引擎靠它决定「这个位置放什么内容」。
///   ⛔ 不能改名 —— 改了就不是同一个槽位了。
/// - **工坊自定义槽位**（`ykx` 前缀）：引擎不认识，内容原样进 prompt。
library;

class PresetSlot {
  const PresetSlot({
    required this.identifier,
    required this.label,
    required this.role,
    this.content = '',
    this.enabled = true,
    this.marker = false,
    this.systemPrompt = false,
    this.position,
    this.legacyPositioning = true,
    this.userOwned = false,
    this.locked = false,
    this.intent = '',
  });

  /// 引擎标识。默认槽位用引擎自己的名字，自定义槽位用 `ykx` 前缀。
  final String identifier;

  /// 中文显示名。
  final String label;

  /// `system` / `user` / `assistant`。
  ///
  /// ⛔ 这是「伪造多轮 role」的关键：改成 `assistant` 并排在末尾，
  /// 就是 prefill（让模型接着往下写）。
  final String role;

  final String content;

  final bool enabled;

  /// 引擎位置标记（`chatHistory` / `worldInfoBefore` / `charDescription` …）。
  ///
  /// ⛔ marker 槽位的内容由**引擎填充**（世界书、角色卡、历史），
  /// 工坊只负责决定它的**位置**和**开关**。往里写文本只会被前置到内置内容前。
  final bool marker;

  final bool systemPrompt;

  /// 相对 `main` 的位置（`start` / `end`）。**不参与聊天组装**，
  /// 只为导出到酒馆时保持语义。
  final String? position;

  final bool legacyPositioning;

  /// 用户自填槽位 —— **AI 生成/微调时绝不覆盖**（破限文本走这里）。
  final bool userOwned;

  /// 结构锁定槽位 —— AI 不可增删、不可改 role。
  ///
  /// `chatHistory` 必须锁定：它是历史插入点，多一个少一个都会出错。
  final bool locked;

  /// 该槽位的设计意图。既展示给用户，也喂给 AI 当生成依据。
  final String intent;

  bool get isMarker => marker;

  bool get hasContent => content.trim().isNotEmpty;

  bool get isEmpty => !hasContent;

  /// 是否工坊自定义槽位。
  bool get isCustom => identifier.startsWith('ykx');

  /// 能否被 AI 改写内容。
  bool get aiEditable => !userOwned;

  PresetSlot copyWith({
    String? identifier,
    String? label,
    String? role,
    String? content,
    bool? enabled,
    bool? marker,
    bool? systemPrompt,
    Object? position = _unset,
    bool? legacyPositioning,
    bool? userOwned,
    bool? locked,
    String? intent,
  }) {
    return PresetSlot(
      identifier: identifier ?? this.identifier,
      label: label ?? this.label,
      role: role ?? this.role,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      marker: marker ?? this.marker,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      position:
          identical(position, _unset) ? this.position : position as String?,
      legacyPositioning: legacyPositioning ?? this.legacyPositioning,
      userOwned: userOwned ?? this.userOwned,
      locked: locked ?? this.locked,
      intent: intent ?? this.intent,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'identifier': identifier,
        'label': label,
        'role': role,
        'content': content,
        'enabled': enabled,
        'marker': marker,
        'systemPrompt': systemPrompt,
        'position': position,
        'legacyPositioning': legacyPositioning,
        'userOwned': userOwned,
        'locked': locked,
        'intent': intent,
      };

  factory PresetSlot.fromJson(Map<String, dynamic> json) {
    return PresetSlot(
      identifier: json['identifier']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      role: json['role']?.toString() ?? 'system',
      content: json['content']?.toString() ?? '',
      enabled: json['enabled'] != false,
      marker: json['marker'] == true,
      systemPrompt: json['systemPrompt'] == true,
      position: json['position']?.toString(),
      legacyPositioning: json['legacyPositioning'] != false,
      userOwned: json['userOwned'] == true,
      locked: json['locked'] == true,
      intent: json['intent']?.toString() ?? '',
    );
  }

  @override
  String toString() =>
      'PresetSlot($identifier, $role, ${enabled ? "on" : "off"}, '
      '${content.length}B)';
}

const Object _unset = Object();
