import 'preset_brief.dart';
import 'preset_diagnosis.dart';
import 'preset_slot.dart';

/// 预设工坊的五个阶段。
///
/// ⛔ 按 [key] 持久化，**不要靠下标**（往中间插阶段不会破坏已有项目）。
enum PresetStage {
  brief('brief', '需求对齐', '定下扮演方式、目标渠道、文风与破限档位'),
  structure('structure', '结构排布', '决定有哪些槽位、各自的 role 与先后顺序'),
  slots('slots', '填充内容', '逐个槽位生成提示词，再对话式微调'),
  diagnose('diagnose', '结构诊断', '检查 role 交替、历史标记、注意力分布'),
  done('done', '导出', '写入预设列表并启用');

  const PresetStage(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PresetStage fromKey(String? key) {
    for (final value in PresetStage.values) {
      if (value.key == key) {
        return value;
      }
    }
    return PresetStage.brief;
  }

  int get index0 => PresetStage.values.indexOf(this);
}

/// 两种结构模板。
///
/// 差别只在 **role 怎么排**：单块版全部走 system（渠道兼容性最好），
/// 伪造多轮按 user / assistant 交替、末尾以 assistant 收尾做 prefill。
enum PresetStructureKind {
  singleBlock(
    'single_block',
    '单块版',
    '所有内容都走 system。兼容性最好 —— 渠道不认多轮伪造时用这个',
  ),
  multiTurn(
    'multi_turn',
    '伪造多轮',
    'user / assistant 交替，末尾以 assistant 收尾。能让模型直接接着写（prefill），'
        '但部分渠道会拒绝连续同 role',
  );

  const PresetStructureKind(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PresetStructureKind fromKey(String? key) {
    for (final value in PresetStructureKind.values) {
      if (value.key == key) {
        return value;
      }
    }
    // 按需求：默认「伪造多轮」。
    return PresetStructureKind.multiTurn;
  }
}

/// 一次版本快照（用于「回滚到上一版」）。
class PresetVersion {
  const PresetVersion({
    required this.slots,
    required this.label,
    required this.at,
  });

  final List<PresetSlot> slots;

  /// 这一版的由来（「AI 生成前」「微调前」…）。
  final String label;

  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'slots': slots.map((slot) => slot.toJson()).toList(),
        'label': label,
        'at': at.millisecondsSinceEpoch,
      };

  factory PresetVersion.fromJson(Map<String, dynamic> json) {
    final raw = json['slots'];
    return PresetVersion(
      slots: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => PresetSlot.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <PresetSlot>[],
      label: json['label']?.toString() ?? '',
      at: json['at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['at'] as int)
          : DateTime.now(),
    );
  }
}

/// 一个预设创作项目。
///
/// 唯一真相源：需求、结构、槽位、诊断结果都在这里，持久化到 Hive box
/// `preset_projects`（键 = [id]）。杀进程重进能原样恢复。
class PresetProject {
  PresetProject({
    required this.id,
    required this.name,
    this.stage = PresetStage.brief,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.brief = const PresetBrief(),
    this.structureKind = PresetStructureKind.multiTurn,
    this.slots = const <PresetSlot>[],
    this.diagnosis = PresetDiagnosisReport.empty,
    this.history = const <PresetVersion>[],
    this.exportedPresetId,
    this.importedFromPresetId,
    this.busyStage = '',
    this.streamPreview = '',
    this.error,
    this.errorRaw,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  PresetStage stage;
  final DateTime createdAt;
  DateTime updatedAt;

  PresetBrief brief;

  PresetStructureKind structureKind;

  /// 槽位列表 —— **顺序就是最终消息顺序**。
  List<PresetSlot> slots;

  PresetDiagnosisReport diagnosis;

  /// 版本快照，最新的在前，限长 [maxHistory]。
  List<PresetVersion> history;

  /// 导出后写入预设列表的 [Preset] id。有它重复导出就是幂等的。
  String? exportedPresetId;

  /// 由已有预设反向导入而来时，记下来源。
  String? importedFromPresetId;

  // --- 运行态（不落库，只给界面用） ---

  String busyStage;
  String streamPreview;
  String? error;
  String? errorRaw;

  static const int maxHistory = 5;

  // --- 派生状态 ---

  bool get hasSlots => slots.isNotEmpty;

  List<PresetSlot> get enabledSlots =>
      slots.where((slot) => slot.enabled).toList(growable: false);

  PresetSlot? slotOf(String identifier) {
    for (final slot in slots) {
      if (slot.identifier == identifier) {
        return slot;
      }
    }
    return null;
  }

  /// 历史标记（`chatHistory`）的出现次数。
  ///
  /// 必须恰好 1 —— 0 次历史无处插入，多次会重复插入。
  int get historyMarkerCount =>
      slots.where((slot) => slot.identifier == 'chatHistory' && slot.enabled).length;

  /// 启用槽位里内容为空、且不是 marker 的数量。
  int get emptyEnabledCount => enabledSlots
      .where((slot) => !slot.marker && !slot.hasContent)
      .length;

  /// 按顺序取出**启用**槽位的 role 序列（用于诊断 role 交替）。
  List<String> get enabledRoleSequence =>
      enabledSlots.map((slot) => slot.role).toList(growable: false);

  /// 内容总长度（估算注意力占用）。
  int get contentLength =>
      slots.fold<int>(0, (sum, slot) => sum + slot.content.length);

  PresetProject copyWith({
    String? name,
    PresetStage? stage,
    DateTime? updatedAt,
    PresetBrief? brief,
    PresetStructureKind? structureKind,
    List<PresetSlot>? slots,
    PresetDiagnosisReport? diagnosis,
    List<PresetVersion>? history,
    Object? exportedPresetId = _unset,
    Object? importedFromPresetId = _unset,
    String? busyStage,
    String? streamPreview,
    Object? error = _unset,
    Object? errorRaw = _unset,
  }) {
    return PresetProject(
      id: id,
      name: name ?? this.name,
      stage: stage ?? this.stage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      brief: brief ?? this.brief,
      structureKind: structureKind ?? this.structureKind,
      slots: slots ?? this.slots,
      diagnosis: diagnosis ?? this.diagnosis,
      history: history ?? this.history,
      exportedPresetId: identical(exportedPresetId, _unset)
          ? this.exportedPresetId
          : exportedPresetId as String?,
      importedFromPresetId: identical(importedFromPresetId, _unset)
          ? this.importedFromPresetId
          : importedFromPresetId as String?,
      busyStage: busyStage ?? this.busyStage,
      streamPreview: streamPreview ?? this.streamPreview,
      error: identical(error, _unset) ? this.error : error as String?,
      errorRaw: identical(errorRaw, _unset) ? this.errorRaw : errorRaw as String?,
    );
  }

  /// 落库用 —— 运行态字段不写盘。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'stage': stage.key,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'brief': brief.toJson(),
        'structureKind': structureKind.key,
        'slots': slots.map((slot) => slot.toJson()).toList(),
        'diagnosis': diagnosis.toJson(),
        'history': history.map((version) => version.toJson()).toList(),
        'exportedPresetId': exportedPresetId,
        'importedFromPresetId': importedFromPresetId,
      };

  factory PresetProject.fromJson(Map<String, dynamic> json) {
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

    return PresetProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名预设',
      stage: PresetStage.fromKey(json['stage']?.toString()),
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
      brief: json['brief'] is Map
          ? PresetBrief.fromJson(Map<String, dynamic>.from(json['brief'] as Map))
          : const PresetBrief(),
      structureKind: PresetStructureKind.fromKey(
        json['structureKind']?.toString(),
      ),
      slots: readList<PresetSlot>(json['slots'], PresetSlot.fromJson),
      diagnosis: json['diagnosis'] is Map
          ? PresetDiagnosisReport.fromJson(
              Map<String, dynamic>.from(json['diagnosis'] as Map))
          : PresetDiagnosisReport.empty,
      history: readList<PresetVersion>(json['history'], PresetVersion.fromJson),
      exportedPresetId: json['exportedPresetId']?.toString(),
      importedFromPresetId: json['importedFromPresetId']?.toString(),
    );
  }

  @override
  String toString() =>
      'PresetProject($name, ${stage.key}, ${slots.length} slots)';
}

const Object _unset = Object();
