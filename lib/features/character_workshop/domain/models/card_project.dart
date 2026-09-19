import 'check_report.dart';
import 'creation_plan.dart';
import 'design_spec.dart';
import 'project_entry.dart';
import 'source_material.dart';

/// 创作项目的六个阶段。
///
/// 阶段是**单向推进 + 允许回退**的：可以退回上一阶段重做，但 UI 上主操作永远指向
/// 「下一个该做的事」。
///
/// ⛔ 阶段按 [key] 持久化（`stage.key` / `fromKey`），**不要靠下标**。
/// 往中间插阶段不会破坏已有项目。
enum ProjectStage {
  design('design', '需求对齐', '对齐六个维度，确认这张卡要做成什么样'),
  plan('plan', '创作规划', '列出要写哪些条目，每条负责什么'),
  writing('writing', '逐条产出', '一次写一条，随时可以停'),
  frontend('frontend', '前端面板', '设计状态面板，可在工坊内交互预览'),
  checking('checking', '质检', '本地扫描结构、一致性、文本质量'),
  done('done', '导出', '打包成角色卡与世界书');

  const ProjectStage(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static ProjectStage fromKey(String? key) {
    for (final value in ProjectStage.values) {
      if (value.key == key) {
        return value;
      }
    }
    return ProjectStage.design;
  }

  int get index0 => ProjectStage.values.indexOf(this);
}

/// 一个完整的角色卡创作项目。
///
/// 这是整个工坊的**唯一真相源**：所有阶段状态、条目、材料、质检结果都在这里，
/// 持久化到 Hive box `card_projects`（键 = [id]）。杀掉进程重进能原样恢复，
/// 这就是「断点续接」在 App 里的实现方式 —— 不靠对话上下文，靠落库。
class CardProject {
  CardProject({
    required this.id,
    required this.name,
    this.stage = ProjectStage.design,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.designSpec = const DesignSpec(),
    this.plan = const CreationPlan(),
    this.entries = const <ProjectEntry>[],
    this.sources = const <SourceMaterial>[],
    this.lastCheck,
    this.exportedCharacterId,
    this.isLegacy = false,
    this.mvuSchemaText = '',
    this.mvuInitvarText = '',
    this.mvuUpdateRulesText = '',
    this.mvuVariablesJson = '',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  ProjectStage stage;
  final DateTime createdAt;
  DateTime updatedAt;

  DesignSpec designSpec;
  CreationPlan plan;

  /// 条目清单（规划阶段建骨架，写作阶段填内容）。
  List<ProjectEntry> entries;

  List<SourceMaterial> sources;

  CheckReport? lastCheck;

  /// 导出后落库的 [Character] ID。
  ///
  /// 有这个字段，重复导出就是幂等的（更新同一张卡），而不是每次新建一张重复卡。
  String? exportedCharacterId;

  /// 由旧版「一键生成」的历史记录迁移而来，只读。
  bool isLegacy;

  // --- MVU 动态变量 ---
  //
  // 参照 ai4rpg/tavern-cards 的约定，MVU 有三个「作者手写」的核心产物：
  //   schema.ts（Zod 变量结构）/ initvar.yaml（初始值）/ 变量更新规则.yaml（更新规则）
  // 这三份在 App 里以文本形式生成并存下来（可查看、可复制），
  // 由 forge CLI 在写卡工作区里完成脚本注入与打包。
  //
  // 另外把变量解析成结构化列表（[mvuVariablesJson]），用于表格展示、
  // 以及质检阶段的「变量取值 ↔ 世界书条目」一致性检查。

  /// Zod 变量结构（schema.ts 内容）。
  String mvuSchemaText;

  /// 变量初始值（initvar.yaml 内容）。
  String mvuInitvarText;

  /// 变量更新规则（变量更新规则.yaml 内容）。
  String mvuUpdateRulesText;

  /// 结构化变量表：`[{"path":"角色.好感度","type":"number","range":"0~100","initial":"35"}]`。
  String mvuVariablesJson;

  // --- 派生状态 ---

  int get doneCount =>
      entries.where((entry) => entry.status == EntryStatus.done).length;

  int get settledCount =>
      entries.where((entry) => entry.status.isSettled).length;

  int get totalCount => entries.length;

  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;

  bool get hasEntries => entries.isNotEmpty;

  /// 第一条还没写完的条目 —— 「该继续的地方」。
  ///
  /// **跳过 [EntryKind.frontend]**：前端面板有自己的阶段（[ProjectStage.frontend]），
  /// 要是算进来，「逐条产出」就永远写不完了。
  ProjectEntry? get firstUnsettled {
    for (final entry in entries) {
      if (entry.kind == EntryKind.frontend) {
        continue;
      }
      if (!entry.status.isSettled) {
        return entry;
      }
    }
    return null;
  }

  bool get isAllWritten => hasEntries && firstUnsettled == null;

  /// 前端面板条目（没有则 null）。
  ///
  /// 前端产物存成条目，是为了跟着项目一起落库、一起进进度统计，
  /// AI 生成也能复用条目那套流式与错误处理。
  ProjectEntry? get frontendEntry {
    for (final entry in entries) {
      if (entry.kind == EntryKind.frontend) {
        return entry;
      }
    }
    return null;
  }

  /// 前端面板 HTML（自包含的 HTML + CSS + JS），没有则空串。
  String get frontendHtml => frontendEntry?.content.trim() ?? '';

  bool get hasFrontend => frontendHtml.isNotEmpty;

  /// 「逐条产出」阶段要写的条目（不含前端面板）。
  List<ProjectEntry> get writingEntries => entries
      .where((entry) => entry.kind != EntryKind.frontend)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  /// 世界书类条目（会打包进 character_book）。
  List<ProjectEntry> get worldbookEntries => entries
      .where((entry) => entry.goesToWorldbook && entry.hasContent)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  /// 角色卡字段类条目。
  List<ProjectEntry> get characterFieldEntries => entries
      .where((entry) => entry.kind == EntryKind.characterCard)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  ProjectEntry? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  /// 角色卡名称：优先取 `name` 字段条目，否则用项目名。
  String get characterName {
    for (final entry in characterFieldEntries) {
      if (entry.fieldKey == 'name' && entry.hasContent) {
        return entry.content.trim();
      }
    }
    return name;
  }

  CardProject copyWith({
    String? name,
    ProjectStage? stage,
    DateTime? updatedAt,
    DesignSpec? designSpec,
    CreationPlan? plan,
    List<ProjectEntry>? entries,
    List<SourceMaterial>? sources,
    Object? lastCheck = _unset,
    Object? exportedCharacterId = _unset,
    bool? isLegacy,
    String? mvuSchemaText,
    String? mvuInitvarText,
    String? mvuUpdateRulesText,
    String? mvuVariablesJson,
  }) {
    return CardProject(
      id: id,
      name: name ?? this.name,
      stage: stage ?? this.stage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      designSpec: designSpec ?? this.designSpec,
      plan: plan ?? this.plan,
      entries: entries ?? this.entries,
      sources: sources ?? this.sources,
      lastCheck: identical(lastCheck, _unset)
          ? this.lastCheck
          : lastCheck as CheckReport?,
      exportedCharacterId: identical(exportedCharacterId, _unset)
          ? this.exportedCharacterId
          : exportedCharacterId as String?,
      isLegacy: isLegacy ?? this.isLegacy,
      mvuSchemaText: mvuSchemaText ?? this.mvuSchemaText,
      mvuInitvarText: mvuInitvarText ?? this.mvuInitvarText,
      mvuUpdateRulesText: mvuUpdateRulesText ?? this.mvuUpdateRulesText,
      mvuVariablesJson: mvuVariablesJson ?? this.mvuVariablesJson,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'stage': stage.key,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'designSpec': designSpec.toJson(),
      'plan': plan.toJson(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'sources': sources.map((source) => source.toJson()).toList(),
      'lastCheck': lastCheck?.toJson(),
      'exportedCharacterId': exportedCharacterId,
      'isLegacy': isLegacy,
      'mvuSchemaText': mvuSchemaText,
      'mvuInitvarText': mvuInitvarText,
      'mvuUpdateRulesText': mvuUpdateRulesText,
      'mvuVariablesJson': mvuVariablesJson,
    };
  }

  factory CardProject.fromJson(Map<String, dynamic> json) {
    List<T> readList<T>(dynamic value, T Function(Map<String, dynamic>) build) {
      final result = <T>[];
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            result.add(build(Map<String, dynamic>.from(item)));
          }
        }
      }
      return result;
    }

    return CardProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名项目',
      stage: ProjectStage.fromKey(json['stage']?.toString()),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] is int
            ? json['createdAt'] as int
            : DateTime.now().millisecondsSinceEpoch,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] is int
            ? json['updatedAt'] as int
            : DateTime.now().millisecondsSinceEpoch,
      ),
      designSpec: json['designSpec'] is Map
          ? DesignSpec.fromJson(
              Map<String, dynamic>.from(json['designSpec'] as Map))
          : const DesignSpec(),
      plan: json['plan'] is Map
          ? CreationPlan.fromJson(Map<String, dynamic>.from(json['plan'] as Map))
          : const CreationPlan(),
      entries: readList<ProjectEntry>(json['entries'], ProjectEntry.fromJson),
      sources:
          readList<SourceMaterial>(json['sources'], SourceMaterial.fromJson),
      lastCheck: json['lastCheck'] is Map
          ? CheckReport.fromJson(
              Map<String, dynamic>.from(json['lastCheck'] as Map))
          : null,
      exportedCharacterId: json['exportedCharacterId']?.toString(),
      isLegacy: json['isLegacy'] == true,
      mvuSchemaText: json['mvuSchemaText']?.toString() ?? '',
      mvuInitvarText: json['mvuInitvarText']?.toString() ?? '',
      mvuUpdateRulesText: json['mvuUpdateRulesText']?.toString() ?? '',
      mvuVariablesJson: json['mvuVariablesJson']?.toString() ?? '',
    );
  }
}

const Object _unset = Object();
