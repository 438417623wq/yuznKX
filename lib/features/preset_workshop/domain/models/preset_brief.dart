/// 需求对齐阶段收集的维度。
///
/// 向导第一屏把这些维度逐项确认，之后所有生成都围绕它展开 ——
/// 相当于角色工坊的 `DesignSpec`。
library;

/// 希望 AI 怎么扮演。
enum RpMode {
  kp(
    'kp',
    'KP 引导',
    'AI 当主持人（KP），按设定构建故事、塑造角色、推动剧情，玩家自由行动',
  ),
  novel(
    'novel',
    '小说模拟器',
    'AI 像写小说一样叙述，兼顾叙事推进与角色对话',
  ),
  firstPerson(
    'first_person',
    '第一人称扮演',
    'AI 直接变成角色，用角色的口吻说话与思考',
  ),
  custom('custom', '自定义', '自己描述想要的扮演方式');

  const RpMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static RpMode fromKey(String? key) {
    for (final value in RpMode.values) {
      if (value.key == key) {
        return value;
      }
    }
    return RpMode.kp;
  }
}

/// 目标渠道。不同渠道对提示词的「甲」和注意力分布不一样，
/// 所以向导会据此调整结构建议与破限档位。
enum TargetChannel {
  openai(
    'openai',
    'OpenAI 兼容',
    '最常见。系统提示词权重高，破限放在首尾即可',
  ),
  claude(
    'claude',
    'Claude',
    '对原生 role 权重敏感，多用 role 层手段、少堆提示词',
  ),
  gemini(
    'gemini',
    'Gemini',
    '低甲模型。建议顶部破限，把底部强注意力留给指令',
  ),
  local(
    'local',
    '本地模型',
    '注意力有限，结构要短、指令要少，否则会「变傻」',
  );

  const TargetChannel(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static TargetChannel fromKey(String? key) {
    for (final value in TargetChannel.values) {
      if (value.key == key) {
        return value;
      }
    }
    return TargetChannel.openai;
  }

  /// 该渠道建议的破限档位（向导默认值）。
  JailbreakLevel get suggestedLevel {
    switch (this) {
      case TargetChannel.gemini:
        // 低甲：顶部够用，底部留给指令。
        return JailbreakLevel.medium;
      case TargetChannel.claude:
        // 靠 role 层与结构，不靠堆提示词。
        return JailbreakLevel.light;
      case TargetChannel.local:
        return JailbreakLevel.none;
      case TargetChannel.openai:
        return JailbreakLevel.medium;
    }
  }
}

/// 叙事人称。
enum PovMode {
  second('second', '第二人称', '「你」—— 沉浸感强，适合互动'),
  third('third', '第三人称', '「他 / 她」—— 适合小说式叙述'),
  first('first', '第一人称', '「我」—— 由玩家视角展开');

  const PovMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PovMode fromKey(String? key) {
    for (final value in PovMode.values) {
      if (value.key == key) {
        return value;
      }
    }
    return PovMode.second;
  }

  /// 写进底部指令的措辞。
  String get promptValue {
    switch (this) {
      case PovMode.second:
        return 'second person';
      case PovMode.third:
        return 'third person';
      case PovMode.first:
        return 'first person';
    }
  }
}

/// 破限档位。
///
/// 思路文档的原话：**「构建破限就像医生开药，直接下猛药当然可以药到病除，
/// 但对身体的破坏也很大」** —— 所以档位从低往高给，默认不推荐最高档。
enum JailbreakLevel {
  none(
    0,
    '不设',
    '只靠 role 与结构，不额外加破限文本。适合本地模型与自带宽松设定的卡',
  ),
  light(1, '轻', '只在 role 层做处理，不占用首尾的强注意力位置'),
  medium(2, '中', 'role 层 + 顶部声明各一处'),
  heavy(3, '重', '顶部 + 底部都占用。⚠️ 容易让模型「变傻」，先试低档');

  const JailbreakLevel(this.value, this.label, this.description);

  final int value;
  final String label;
  final String description;

  static JailbreakLevel fromValue(int? value) {
    for (final level in JailbreakLevel.values) {
      if (level.value == value) {
        return level;
      }
    }
    return JailbreakLevel.none;
  }

  bool get needsTop => value >= 2;

  bool get needsBottom => value >= 3;
}

/// 预设需求。
class PresetBrief {
  const PresetBrief({
    this.rpMode = RpMode.kp,
    this.rpModeNote = '',
    this.channel = TargetChannel.openai,
    this.pov = PovMode.second,
    this.language = 'zh-cn',
    this.wordLimit = 600,
    this.styleTags = const <String>[],
    this.jailbreakLevel = JailbreakLevel.none,
    this.wantCot = false,
    this.extraNotes = '',
  });

  final RpMode rpMode;

  /// [RpMode.custom] 时的自由描述。
  final String rpModeNote;

  final TargetChannel channel;

  final PovMode pov;

  /// 输出语言（`zh-cn` / `en` …）。
  final String language;

  /// 建议输出字数。
  final int wordLimit;

  /// 文风标签。
  final List<String> styleTags;

  final JailbreakLevel jailbreakLevel;

  /// 是否在末尾放一段伪造的思考块（COT）来引导正文。
  final bool wantCot;

  final String extraNotes;

  /// 需求是否够用（RP 方式与渠道必填，自定义方式要有描述）。
  bool get isComplete {
    if (rpMode == RpMode.custom && rpModeNote.trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// 给 AI 看的需求摘要。
  String toPromptText() {
    final buffer = StringBuffer()
      ..writeln('- 扮演方式：${rpMode.label}'
          '${rpModeNote.trim().isEmpty ? "" : "（${rpModeNote.trim()}）"}')
      ..writeln('- 扮演方式说明：${rpMode.description}')
      ..writeln('- 目标渠道：${channel.label}（${channel.description}）')
      ..writeln('- 叙事人称：${pov.label}（${pov.description}）')
      ..writeln('- 输出语言：$language')
      ..writeln('- 建议输出量：约 $wordLimit 字')
      ..writeln('- 破限档位：${jailbreakLevel.label} —— ${jailbreakLevel.description}')
      ..writeln('- 末尾伪造思考块（COT）：${wantCot ? "要" : "不要"}');
    if (styleTags.isNotEmpty) {
      buffer.writeln('- 文风要求：${styleTags.join("、")}');
    }
    if (extraNotes.trim().isNotEmpty) {
      buffer.writeln('- 其它补充：${extraNotes.trim()}');
    }
    return buffer.toString().trim();
  }

  PresetBrief copyWith({
    RpMode? rpMode,
    String? rpModeNote,
    TargetChannel? channel,
    PovMode? pov,
    String? language,
    int? wordLimit,
    List<String>? styleTags,
    JailbreakLevel? jailbreakLevel,
    bool? wantCot,
    String? extraNotes,
  }) {
    return PresetBrief(
      rpMode: rpMode ?? this.rpMode,
      rpModeNote: rpModeNote ?? this.rpModeNote,
      channel: channel ?? this.channel,
      pov: pov ?? this.pov,
      language: language ?? this.language,
      wordLimit: wordLimit ?? this.wordLimit,
      styleTags: styleTags ?? this.styleTags,
      jailbreakLevel: jailbreakLevel ?? this.jailbreakLevel,
      wantCot: wantCot ?? this.wantCot,
      extraNotes: extraNotes ?? this.extraNotes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rpMode': rpMode.key,
        'rpModeNote': rpModeNote,
        'channel': channel.key,
        'pov': pov.key,
        'language': language,
        'wordLimit': wordLimit,
        'styleTags': styleTags,
        'jailbreakLevel': jailbreakLevel.value,
        'wantCot': wantCot,
        'extraNotes': extraNotes,
      };

  factory PresetBrief.fromJson(Map<String, dynamic> json) {
    return PresetBrief(
      rpMode: RpMode.fromKey(json['rpMode']?.toString()),
      rpModeNote: json['rpModeNote']?.toString() ?? '',
      channel: TargetChannel.fromKey(json['channel']?.toString()),
      pov: PovMode.fromKey(json['pov']?.toString()),
      language: json['language']?.toString() ?? 'zh-cn',
      wordLimit: json['wordLimit'] is int ? json['wordLimit'] as int : 600,
      styleTags: json['styleTags'] is List
          ? (json['styleTags'] as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      jailbreakLevel: JailbreakLevel.fromValue(
        json['jailbreakLevel'] is int ? json['jailbreakLevel'] as int : 0,
      ),
      wantCot: json['wantCot'] == true,
      extraNotes: json['extraNotes']?.toString() ?? '',
    );
  }
}

/// 向导里可选的文风标签（点一下就加，也可以自己写）。
const List<String> kStyleTagSuggestions = <String>[
  '冷硬简洁',
  '华丽繁复',
  '轻小说',
  '古典文言',
  '细腻心理描写',
  '大量对话推进',
  '感官细节丰富',
  '克制冷淡',
  '幽默诙谐',
  '阴暗压抑',
];
