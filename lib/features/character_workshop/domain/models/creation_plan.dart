import 'card_field.dart';

/// 创作规划阶段（S2）的附加设定。
///
/// 注意：条目清单本身不在这里 —— 它直接就是 `CardProject.entries`。
/// 规划阶段产出条目的「骨架」（title/kind/brief/keys/order，content 为空），
/// 写作阶段逐条填充 content。共用同一个列表可以避免两套模型同步的问题。
class CreationPlan {
  const CreationPlan({
    this.summary = '',
    this.mvuEnabled = false,
    this.ejsEnabled = false,
    this.targetWordCount = 0,
    this.worldbookTarget = 8,
    this.length = EntryLength.standard,
    this.language = OutputLanguage.zh,
    this.plannedFieldKeys = kDefaultCardFieldKeys,
  });

  /// AI 给的整体规划说明（为什么这么拆条目）。
  final String summary;

  /// 是否需要 MVU 动态变量。
  final bool mvuEnabled;

  /// 是否在条目中使用 EJS 模板（只生成文本，不执行）。
  final bool ejsEnabled;

  /// 整卡字数预算（0 = 不限制）。
  final int targetWordCount;

  /// 期望的世界书条目条数。
  final int worldbookTarget;

  /// 单条生成的详细程度。
  final EntryLength length;

  /// 输出语言。
  final OutputLanguage language;

  /// 规划时勾选的角色卡字段。
  final Set<String> plannedFieldKeys;

  CreationPlan copyWith({
    String? summary,
    bool? mvuEnabled,
    bool? ejsEnabled,
    int? targetWordCount,
    int? worldbookTarget,
    EntryLength? length,
    OutputLanguage? language,
    Set<String>? plannedFieldKeys,
  }) {
    return CreationPlan(
      summary: summary ?? this.summary,
      mvuEnabled: mvuEnabled ?? this.mvuEnabled,
      ejsEnabled: ejsEnabled ?? this.ejsEnabled,
      targetWordCount: targetWordCount ?? this.targetWordCount,
      worldbookTarget: worldbookTarget ?? this.worldbookTarget,
      length: length ?? this.length,
      language: language ?? this.language,
      plannedFieldKeys: plannedFieldKeys ?? this.plannedFieldKeys,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'summary': summary,
      'mvuEnabled': mvuEnabled,
      'ejsEnabled': ejsEnabled,
      'targetWordCount': targetWordCount,
      'worldbookTarget': worldbookTarget,
      'length': length.name,
      'language': language.name,
      'plannedFieldKeys': plannedFieldKeys.toList(),
    };
  }

  factory CreationPlan.fromJson(Map<String, dynamic> json) {
    EntryLength readLength(dynamic value) {
      for (final item in EntryLength.values) {
        if (item.name == value?.toString()) {
          return item;
        }
      }
      return EntryLength.standard;
    }

    OutputLanguage readLanguage(dynamic value) {
      for (final item in OutputLanguage.values) {
        if (item.name == value?.toString()) {
          return item;
        }
      }
      return OutputLanguage.zh;
    }

    Set<String> readFieldKeys(dynamic value) {
      if (value is List) {
        final keys = value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toSet();
        if (keys.isNotEmpty) {
          return keys;
        }
      }
      return kDefaultCardFieldKeys;
    }

    return CreationPlan(
      summary: json['summary']?.toString() ?? '',
      mvuEnabled: json['mvuEnabled'] == true,
      ejsEnabled: json['ejsEnabled'] == true,
      targetWordCount: json['targetWordCount'] is int
          ? json['targetWordCount'] as int
          : 0,
      worldbookTarget: json['worldbookTarget'] is int
          ? json['worldbookTarget'] as int
          : 8,
      length: readLength(json['length']),
      language: readLanguage(json['language']),
      plannedFieldKeys: readFieldKeys(json['plannedFieldKeys']),
    );
  }
}
