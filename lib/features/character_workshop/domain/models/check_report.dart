/// 质检阶段（S4）的数据模型。
///
/// 质检**全部在本地完成**，不消耗任何 API 额度 —— 参照参考项目里 `check-agent`
/// 子代理的职责，但改成纯 Dart 规则扫描：手机上更快、更省、也更容易单测。

/// 问题严重级别。
enum CheckSeverity {
  error('error', '错误'),
  warning('warning', '警告'),
  info('info', '提示');

  const CheckSeverity(this.key, this.label);

  final String key;
  final String label;

  static CheckSeverity fromKey(String? key) {
    for (final value in CheckSeverity.values) {
      if (value.key == key) {
        return value;
      }
    }
    return CheckSeverity.info;
  }
}

/// 问题分类。
enum CheckCategory {
  structure('structure', '结构完整性'),
  consistency('consistency', '设定一致性'),
  text('text', '文本质量');

  const CheckCategory(this.key, this.label);

  final String key;
  final String label;

  static CheckCategory fromKey(String? key) {
    for (final value in CheckCategory.values) {
      if (value.key == key) {
        return value;
      }
    }
    return CheckCategory.structure;
  }
}

/// 问题的来源。
///
/// 两段式质检的产物：本地规则秒出、0 token，但读不懂设定语义；
/// AI 复核能读出人设走形与前后矛盾，但要花 token。UI 按来源分组显示，
/// 让用户清楚哪些是「机器查的」、哪些是「AI 读出来的」。
enum CheckSource {
  local('local', '本地规则'),
  ai('ai', 'AI 复核');

  const CheckSource(this.key, this.label);

  final String key;
  final String label;

  static CheckSource fromKey(String? key) {
    for (final value in CheckSource.values) {
      if (value.key == key) {
        return value;
      }
    }
    return CheckSource.local;
  }
}

/// 单条质检问题。
class CheckIssue {
  CheckIssue({
    required this.id,
    required this.category,
    required this.severity,
    required this.message,
    this.entryId,
    this.entryTitle,
    this.suggestion,
    this.source = CheckSource.local,
    this.repairable,
  });

  final String id;
  final CheckCategory category;
  final CheckSeverity severity;
  final String message;

  /// 关联的条目 ID（可点击跳转）。
  final String? entryId;
  final String? entryTitle;

  /// 修复建议。
  final String? suggestion;

  /// 这条问题是本地规则查出来的，还是 AI 复核读出来的。
  final CheckSource source;

  /// 显式指定的「可修」标记。null 表示按 [source] 推断。
  ///
  /// 本地规则里也有可修的（比如「世界书条目缺关键词」），
  /// 所以不能简单地「本地一律不可修」。
  final bool? repairable;

  /// 是否显示「修这条」按钮。
  ///
  /// AI 复核出的问题默认可修（模型能给出改写后的内容）；
  /// 本地问题要显式标 `repairable: true` 才算。
  bool get canRepair => repairable ?? (source == CheckSource.ai);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'category': category.key,
      'severity': severity.key,
      'message': message,
      'entryId': entryId,
      'entryTitle': entryTitle,
      'suggestion': suggestion,
      'source': source.key,
      if (repairable != null) 'repairable': repairable,
    };
  }

  factory CheckIssue.fromJson(Map<String, dynamic> json) {
    return CheckIssue(
      id: json['id']?.toString() ?? '',
      category: CheckCategory.fromKey(json['category']?.toString()),
      severity: CheckSeverity.fromKey(json['severity']?.toString()),
      message: json['message']?.toString() ?? '',
      entryId: json['entryId']?.toString(),
      entryTitle: json['entryTitle']?.toString(),
      suggestion: json['suggestion']?.toString(),
      source: CheckSource.fromKey(json['source']?.toString()),
      repairable: json['repairable'] is bool ? json['repairable'] as bool : null,
    );
  }
}

/// 一次质检的完整报告。
class CheckReport {
  CheckReport({
    required this.issues,
    required this.createdAt,
  });

  final List<CheckIssue> issues;
  final DateTime createdAt;

  int countOf(CheckSeverity severity) =>
      issues.where((issue) => issue.severity == severity).length;

  int get errorCount => countOf(CheckSeverity.error);
  int get warningCount => countOf(CheckSeverity.warning);
  int get infoCount => countOf(CheckSeverity.info);

  bool get isClean => issues.isEmpty;

  List<CheckIssue> issuesOf(CheckCategory category) =>
      issues.where((issue) => issue.category == category).toList();

  /// 一句话摘要。
  String get summary {
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'createdAt': createdAt.millisecondsSinceEpoch,
      'issues': issues.map((issue) => issue.toJson()).toList(),
    };
  }

  factory CheckReport.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'];
    final issues = <CheckIssue>[];
    if (rawIssues is List) {
      for (final item in rawIssues) {
        if (item is Map) {
          issues.add(CheckIssue.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return CheckReport(
      issues: issues,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] is int
            ? json['createdAt'] as int
            : DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
