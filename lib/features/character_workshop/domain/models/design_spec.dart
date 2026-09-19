/// 需求对齐阶段（S1）的数据模型。
///
/// 设计原则：**先对齐需求再做规划**。六个维度逐维确认，全部确认后才允许进入
/// 创作规划阶段。每个维度允许三种来源的答案：AI 候选、用户改写、用户自填。

/// 需求对齐的六个维度。
///
/// 顺序即界面顺序，也即对话推进顺序。
enum SpecDimension {
  positioning(
    'positioning',
    '项目定位',
    '这是一张什么卡？给谁玩？',
    '题材、风格、受众、尺度、单角色还是群像、想要什么体验',
  ),
  worldview(
    'worldview',
    '世界观构思',
    '世界的基本规则是什么？',
    '时代背景、地理、力量体系、社会结构、日常与禁忌',
  ),
  characters(
    'characters',
    '角色构思',
    '核心角色是谁？彼此什么关系？',
    '主角的定位与性格内核、配角、关系网、角色之间的张力',
  ),
  dynamics(
    'dynamics',
    '互动与动态需求',
    '需要变量、状态栏或多结局吗？',
    '是否需要动态变量（好感度/数值成长/状态标记）、分支走向、结局设计',
  ),
  direction(
    'direction',
    '创作方向',
    '文字基调和篇幅怎么定？',
    '叙事人称、文字风格、单条条目篇幅、整卡字数预算',
  ),
  opening(
    'opening',
    '开场构思',
    '故事从哪一刻开始？',
    '开场场景、首轮交互、用户扮演的角色定位',
  );

  const SpecDimension(this.key, this.label, this.question, this.hint);

  /// 持久化键。
  final String key;

  /// 界面标题。
  final String label;

  /// 这一维要回答的核心问题。
  final String question;

  /// 给用户的补充说明（也用于拼 AI 提示词）。
  final String hint;

  static SpecDimension? fromKey(String? key) {
    for (final value in SpecDimension.values) {
      if (value.key == key) {
        return value;
      }
    }
    return null;
  }
}

/// 六维度对齐结果。
class DesignSpec {
  const DesignSpec({
    this.answers = const <String, String>{},
    this.candidates = const <String, List<String>>{},
    this.confirmed = const <String>{},
  });

  /// 维度 key → 用户确认的答案。
  final Map<String, String> answers;

  /// 维度 key → AI 给出的候选方案（保留下来便于回看与切换）。
  final Map<String, List<String>> candidates;

  /// 已确认的维度 key 集合。
  final Set<String> confirmed;

  bool isConfirmed(SpecDimension dimension) =>
      confirmed.contains(dimension.key) &&
      (answers[dimension.key]?.trim().isNotEmpty ?? false);

  bool get isComplete =>
      SpecDimension.values.every((dimension) => isConfirmed(dimension));

  /// 已确认的维度数。
  int get confirmedCount =>
      SpecDimension.values.where(isConfirmed).length;

  /// 第一个未确认的维度，全部确认时返回 null。
  SpecDimension? get firstUnconfirmed {
    for (final dimension in SpecDimension.values) {
      if (!isConfirmed(dimension)) {
        return dimension;
      }
    }
    return null;
  }

  String answerOf(SpecDimension dimension) => answers[dimension.key]?.trim() ?? '';

  List<String> candidatesOf(SpecDimension dimension) =>
      candidates[dimension.key] ?? const <String>[];

  DesignSpec copyWith({
    Map<String, String>? answers,
    Map<String, List<String>>? candidates,
    Set<String>? confirmed,
  }) {
    return DesignSpec(
      answers: answers ?? this.answers,
      candidates: candidates ?? this.candidates,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  DesignSpec withAnswer(SpecDimension dimension, String value) {
    final nextAnswers = Map<String, String>.from(answers)
      ..[dimension.key] = value;
    final nextConfirmed = Set<String>.from(confirmed);
    if (value.trim().isEmpty) {
      nextConfirmed.remove(dimension.key);
    } else {
      nextConfirmed.add(dimension.key);
    }
    return copyWith(answers: nextAnswers, confirmed: nextConfirmed);
  }

  DesignSpec withCandidates(SpecDimension dimension, List<String> values) {
    final next = Map<String, List<String>>.from(candidates)
      ..[dimension.key] = values;
    return copyWith(candidates: next);
  }

  DesignSpec withoutConfirmation(SpecDimension dimension) {
    final nextConfirmed = Set<String>.from(confirmed)..remove(dimension.key);
    return copyWith(confirmed: nextConfirmed);
  }

  /// 拼成给下游阶段（规划 / 写作）用的紧凑文本。
  String toPromptBlock() {
    final buffer = StringBuffer();
    for (final dimension in SpecDimension.values) {
      final answer = answerOf(dimension);
      if (answer.isEmpty) {
        continue;
      }
      buffer.writeln('【${dimension.label}】$answer');
    }
    return buffer.toString().trimRight();
  }

  /// 可导出的 Markdown 形态（design-spec.md）。
  String toMarkdown(String projectName) {
    final buffer = StringBuffer()
      ..writeln('# $projectName — 设计规格')
      ..writeln();
    for (final dimension in SpecDimension.values) {
      buffer.writeln('## ${dimension.label}');
      buffer.writeln();
      final answer = answerOf(dimension);
      buffer.writeln(answer.isEmpty ? '（未填写）' : answer);
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'answers': answers,
      'candidates': candidates,
      'confirmed': confirmed.toList(),
    };
  }

  factory DesignSpec.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'];
    final rawCandidates = json['candidates'];
    final rawConfirmed = json['confirmed'];

    final answers = <String, String>{};
    if (rawAnswers is Map) {
      rawAnswers.forEach((key, value) {
        final text = value?.toString() ?? '';
        if (text.isNotEmpty) {
          answers[key.toString()] = text;
        }
      });
    }

    final candidates = <String, List<String>>{};
    if (rawCandidates is Map) {
      rawCandidates.forEach((key, value) {
        if (value is List) {
          candidates[key.toString()] = value
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList();
        }
      });
    }

    final confirmed = <String>{};
    if (rawConfirmed is List) {
      for (final item in rawConfirmed) {
        confirmed.add(item.toString());
      }
    }

    return DesignSpec(
      answers: answers,
      candidates: candidates,
      confirmed: confirmed,
    );
  }
}
