/// 预设诊断的结果模型。
///
/// 诊断只作用于**工坊自己产出的预设**（按需求：不做预设列表里的通用体检）。
library;

/// 问题严重程度。
enum PresetIssueLevel {
  /// 会导致预设跑不起来或静默失效 —— 导出前必须修。
  error('error', '错误'),

  /// 可能出问题，取决于渠道 —— 建议修。
  warning('warning', '警告'),

  /// 只是提示，不影响可用性。
  info('info', '提示');

  const PresetIssueLevel(this.key, this.label);

  final String key;
  final String label;

  static PresetIssueLevel fromKey(String? key) {
    for (final value in PresetIssueLevel.values) {
      if (value.key == key) {
        return value;
      }
    }
    return PresetIssueLevel.info;
  }
}

/// 问题来源。
enum PresetIssueSource {
  /// 本地规则，0 token，自动跑。
  local('local', '本地'),

  /// AI 复核，手动触发（省 token）。
  ai('ai', 'AI');

  const PresetIssueSource(this.key, this.label);

  final String key;
  final String label;

  static PresetIssueSource fromKey(String? key) {
    for (final value in PresetIssueSource.values) {
      if (value.key == key) {
        return value;
      }
    }
    return PresetIssueSource.local;
  }
}

/// 一条诊断问题。
class PresetDiagnosisIssue {
  const PresetDiagnosisIssue({
    required this.id,
    required this.title,
    required this.detail,
    required this.level,
    this.source = PresetIssueSource.local,
    this.slotIdentifier,
    this.repairable,
    this.suggestion = '',
  });

  final String id;

  /// 一句话说清问题（列表标题）。
  final String title;

  /// 为什么是问题 + 怎么改。
  final String detail;

  final PresetIssueLevel level;

  final PresetIssueSource source;

  /// 关联槽位的 identifier；为空表示这是整体性问题。
  final String? slotIdentifier;

  /// 能否让 AI 逐条修复。null = 按来源推断（本地问题默认不可修）。
  final bool? repairable;

  /// 本地规则给出的具体建议（喂给 AI 当修复依据）。
  final String suggestion;

  bool get isError => level == PresetIssueLevel.error;

  bool get isWarning => level == PresetIssueLevel.warning;

  /// 本地结构问题大多是「配置问题」而不是「文字问题」，AI 改不了 —— 只能给操作建议。
  bool get canRepair => repairable ?? (source == PresetIssueSource.ai);

  PresetDiagnosisIssue copyWith({
    String? id,
    String? title,
    String? detail,
    PresetIssueLevel? level,
    PresetIssueSource? source,
    Object? slotIdentifier = _unset,
    Object? repairable = _unset,
    String? suggestion,
  }) {
    return PresetDiagnosisIssue(
      id: id ?? this.id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      level: level ?? this.level,
      source: source ?? this.source,
      slotIdentifier: identical(slotIdentifier, _unset)
          ? this.slotIdentifier
          : slotIdentifier as String?,
      repairable:
          identical(repairable, _unset) ? this.repairable : repairable as bool?,
      suggestion: suggestion ?? this.suggestion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'detail': detail,
        'level': level.key,
        'source': source.key,
        'slotIdentifier': slotIdentifier,
        'repairable': repairable,
        'suggestion': suggestion,
      };

  factory PresetDiagnosisIssue.fromJson(Map<String, dynamic> json) {
    return PresetDiagnosisIssue(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      level: PresetIssueLevel.fromKey(json['level']?.toString()),
      source: PresetIssueSource.fromKey(json['source']?.toString()),
      slotIdentifier: json['slotIdentifier']?.toString(),
      repairable: json['repairable'] is bool ? json['repairable'] as bool : null,
      suggestion: json['suggestion']?.toString() ?? '',
    );
  }
}

/// 诊断报告。
class PresetDiagnosisReport {
  const PresetDiagnosisReport({
    this.issues = const <PresetDiagnosisIssue>[],
    this.ranAt,
    this.aiReviewRequested = false,
  });

  final List<PresetDiagnosisIssue> issues;

  final DateTime? ranAt;

  /// 这一版是否跑过 AI 复核（决定「让 AI 复核」按钮的状态）。
  final bool aiReviewRequested;

  bool get isEmpty => issues.isEmpty;

  int get errorCount =>
      issues.where((issue) => issue.level == PresetIssueLevel.error).length;

  int get warningCount =>
      issues.where((issue) => issue.level == PresetIssueLevel.warning).length;

  int get infoCount =>
      issues.where((issue) => issue.level == PresetIssueLevel.info).length;

  /// 有错误级问题 —— 导出前应该拦一下。
  bool get hasBlockingIssue => errorCount > 0;

  /// 按「错误 → 警告 → 提示」排序。
  List<PresetDiagnosisIssue> get sortedIssues {
    final list = List<PresetDiagnosisIssue>.from(issues);
    list.sort((a, b) => a.level.index.compareTo(b.level.index));
    return list;
  }

  /// 一句话摘要。
  String summaryLine() {
    if (issues.isEmpty) {
      return '没有发现问题';
    }
    final parts = <String>[];
    if (errorCount > 0) {
      parts.add('$errorCount 个错误');
    }
    if (warningCount > 0) {
      parts.add('$warningCount 个警告');
    }
    if (infoCount > 0) {
      parts.add('$infoCount 条提示');
    }
    return parts.join(' · ');
  }

  static const PresetDiagnosisReport empty = PresetDiagnosisReport();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'issues': issues.map((issue) => issue.toJson()).toList(),
        'ranAt': ranAt?.millisecondsSinceEpoch,
        'aiReviewRequested': aiReviewRequested,
      };

  factory PresetDiagnosisReport.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'];
    return PresetDiagnosisReport(
      issues: rawIssues is List
          ? rawIssues
              .whereType<Map>()
              .map((item) =>
                  PresetDiagnosisIssue.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <PresetDiagnosisIssue>[],
      ranAt: json['ranAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['ranAt'] as int)
          : null,
      aiReviewRequested: json['aiReviewRequested'] == true,
    );
  }
}

/// 一条「修这条」的结果：某个槽位内容的 before → after。
///
/// 照搬角色工坊 `IssueRepair` 的形状，好复用同一套 diff 预览弹窗。
class PresetSlotRepair {
  const PresetSlotRepair({
    required this.issue,
    required this.slotIdentifier,
    required this.slotLabel,
    required this.before,
    required this.after,
  });

  final PresetDiagnosisIssue issue;
  final String slotIdentifier;
  final String slotLabel;
  final String before;
  final String after;

  /// 模型没有实际改动内容 —— UI 应提示「建议放弃这一版」。
  bool get changed => before.trim() != after.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'issue': issue.toJson(),
        'slotIdentifier': slotIdentifier,
        'slotLabel': slotLabel,
        'before': before,
        'after': after,
      };

  factory PresetSlotRepair.fromJson(Map<String, dynamic> json) {
    return PresetSlotRepair(
      issue: PresetDiagnosisIssue.fromJson(
        json['issue'] is Map
            ? Map<String, dynamic>.from(json['issue'] as Map)
            : const <String, dynamic>{},
      ),
      slotIdentifier: json['slotIdentifier']?.toString() ?? '',
      slotLabel: json['slotLabel']?.toString() ?? '',
      before: json['before']?.toString() ?? '',
      after: json['after']?.toString() ?? '',
    );
  }
}

const Object _unset = Object();
