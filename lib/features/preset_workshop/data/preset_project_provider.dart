import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/preset_brief.dart';
import '../domain/models/preset_diagnosis.dart';
import '../domain/models/preset_project.dart';
import '../domain/models/preset_slot.dart';
import '../domain/preset_slot_catalog.dart';
import '../domain/preset_structure_templates.dart';

/// 预设项目的持久化 box。
const String kPresetProjectBoxName = 'preset_projects';

/// 界面状态。
class PresetProjectState {
  const PresetProjectState({
    this.projects = const <PresetProject>[],
    this.loaded = false,
    this.busy = false,
    this.busyStage = '',
    this.streamPreview = '',
    this.error,
    this.errorRaw,
  });

  /// 全部项目，按 `updatedAt` 降序。
  final List<PresetProject> projects;

  final bool loaded;

  /// 是否有 AI 任务在跑。
  final bool busy;

  /// 进度文案（「正在重写「顶部声明」…」）。
  final String busyStage;

  /// 流式返回的实时片段（只保留尾部）。
  final String streamPreview;

  final String? error;
  final String? errorRaw;

  PresetProjectState copyWith({
    List<PresetProject>? projects,
    bool? loaded,
    bool? busy,
    String? busyStage,
    String? streamPreview,
    Object? error = _unset,
    Object? errorRaw = _unset,
  }) {
    return PresetProjectState(
      projects: projects ?? this.projects,
      loaded: loaded ?? this.loaded,
      busy: busy ?? this.busy,
      busyStage: busyStage ?? this.busyStage,
      streamPreview: streamPreview ?? this.streamPreview,
      error: identical(error, _unset) ? this.error : error as String?,
      errorRaw: identical(errorRaw, _unset) ? this.errorRaw : errorRaw as String?,
    );
  }
}

const Object _unset = Object();

final presetProjectProvider =
    StateNotifierProvider<PresetProjectNotifier, PresetProjectState>((ref) {
  return PresetProjectNotifier();
});

/// 按 ID 取单个项目。
///
/// 与角色工坊同理：工作台直接用它取数据，不依赖「当前打开的项目」这种全局状态。
final presetProjectByIdProvider =
    Provider.family<PresetProject?, String>((ref, id) {
  final projects = ref.watch(presetProjectProvider).projects;
  for (final project in projects) {
    if (project.id == id) {
      return project;
    }
  }
  return null;
});

/// 预设项目的中枢：CRUD、阶段流转、槽位编排、持久化。
///
/// **断点续接**：任何改动都立即（或 400ms 内）落进 Hive box。
/// 杀掉进程重进时 `_restore()` 会原样读回来。
class PresetProjectNotifier extends StateNotifier<PresetProjectState> {
  PresetProjectNotifier() : super(const PresetProjectState()) {
    unawaited(_restore());
  }

  /// 本 notifier 只读写自己的 box，不需要 `Ref` ——
  /// 导出预设、读世界书/正则这些跨模块动作都在 actions 层做。
  Box? _box;

  /// 每个项目一个防抖定时器，避免编辑正文时每个按键都写磁盘。
  final Map<String, Timer> _persistTimers = <String, Timer>{};

  // --- 初始化 ---

  Future<Box?> _ensureBox() async {
    if (_box != null && _box!.isOpen) {
      return _box;
    }
    try {
      if (Hive.isBoxOpen(kPresetProjectBoxName)) {
        _box = Hive.box(kPresetProjectBoxName);
      } else {
        _box = await Hive.openBox(kPresetProjectBoxName);
      }
    } catch (_) {
      _box = null;
    }
    return _box;
  }

  Future<void> _restore() async {
    final box = await _ensureBox();
    if (box == null) {
      state = state.copyWith(loaded: true);
      return;
    }

    final projects = <PresetProject>[];
    for (final value in box.values) {
      try {
        if (value is Map) {
          final project =
              PresetProject.fromJson(Map<String, dynamic>.from(value));
          if (project.id.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // 单条损坏不影响其它项目。
      }
    }

    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: projects, loaded: true);
  }

  // --- 持久化 ---

  void _persist(PresetProject project, {bool immediate = false}) {
    final box = _box;
    if (box == null) {
      return;
    }
    _persistTimers[project.id]?.cancel();
    if (immediate) {
      _persistTimers.remove(project.id);
      unawaited(box.put(project.id, project.toJson()));
      return;
    }
    _persistTimers[project.id] = Timer(const Duration(milliseconds: 400), () {
      _persistTimers.remove(project.id);
      unawaited(box.put(project.id, project.toJson()));
    });
  }

  /// 把还没落盘的防抖任务立刻写掉（离开项目 / 退出页面前调用）。
  void flushPendingWrites() {
    final box = _box;
    if (box == null) {
      return;
    }
    final pending = Map<String, Timer>.from(_persistTimers);
    _persistTimers.clear();
    for (final entry in pending.entries) {
      entry.value.cancel();
      for (final project in state.projects) {
        if (project.id == entry.key) {
          unawaited(box.put(project.id, project.toJson()));
          break;
        }
      }
    }
  }

  /// 通用变更入口：改内存 + 落盘。
  void _mutate(
    String id,
    PresetProject Function(PresetProject project) transform, {
    bool immediate = false,
  }) {
    final index = state.projects.indexWhere((project) => project.id == id);
    if (index < 0) {
      return;
    }
    final next = transform(state.projects[index]);
    final list = List<PresetProject>.from(state.projects);
    list[index] = next;
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: list);
    _persist(next, immediate: immediate);
  }

  // --- 项目 CRUD ---

  PresetProject createProject({String name = '', PresetBrief? brief}) {
    final project = PresetProject(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? '未命名预设' : name.trim(),
      brief: brief ?? const PresetBrief(),
    );
    final list = <PresetProject>[project, ...state.projects];
    state = state.copyWith(projects: list);
    _persist(project, immediate: true);
    return project;
  }

  /// 直接插入一个已构造好的项目（反向导入用）。
  PresetProject addProject(PresetProject project) {
    final list = <PresetProject>[project, ...state.projects];
    state = state.copyWith(projects: list);
    _persist(project, immediate: true);
    return project;
  }

  void deleteProject(String id) {
    _persistTimers.remove(id)?.cancel();
    unawaited(_box?.delete(id));
    final list = state.projects.where((project) => project.id != id).toList();
    state = state.copyWith(projects: list);
  }

  void renameProject(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _mutate(id, (project) => project.copyWith(name: trimmed), immediate: true);
  }

  void setStage(String id, PresetStage stage) {
    _mutate(id, (project) => project.copyWith(stage: stage), immediate: true);
  }

  /// 推进到下一个阶段（已是最后一阶段则不动）。
  void advanceStage(String id) {
    final project = _projectById(id);
    if (project == null) {
      return;
    }
    final next = project.stage.index0 + 1;
    if (next >= PresetStage.values.length) {
      return;
    }
    setStage(id, PresetStage.values[next]);
  }

  // --- 需求 ---

  void updateBrief(String id, PresetBrief brief) {
    _mutate(id, (project) => project.copyWith(brief: brief));
  }

  // --- 结构 ---

  /// 切换结构类型并重建骨架。
  ///
  /// 已有内容按 identifier 沿用 —— 切结构不该让用户白写一遍。
  /// 切之前会压一版历史快照，方便反悔。
  void setStructure(String id, PresetStructureKind kind) {
    _mutate(id, (project) {
      final slots = PresetStructureTemplates.build(
        kind: kind,
        brief: project.brief,
        previous: project.slots,
      );
      return project.copyWith(
        structureKind: kind,
        slots: slots,
        history: _pushHistory(project, '切换为「${kind.label}」前'),
      );
    }, immediate: true);
  }

  /// 按当前需求重新生成骨架（会保留已有内容）。
  void rebuildStructure(String id) {
    _mutate(id, (project) {
      final slots = PresetStructureTemplates.build(
        kind: project.structureKind,
        brief: project.brief,
        previous: project.slots,
      );
      return project.copyWith(slots: slots);
    }, immediate: true);
  }

  // --- 槽位 ---

  void setSlots(String id, List<PresetSlot> slots, {bool snapshot = false}) {
    _mutate(id, (project) {
      return project.copyWith(
        slots: slots,
        history: snapshot ? _pushHistory(project, '批量改写前') : null,
      );
    }, immediate: true);
  }

  /// 用 AI 产出的内容批量覆盖槽位（只覆盖给了内容的那些）。
  ///
  /// [onlyIdentifiers] 非空时只写这些槽位 —— 微调时用来防止模型越界改别的槽位。
  void applyContents(
    String id,
    Map<String, String> contents, {
    Set<String>? onlyIdentifiers,
    bool snapshot = true,
  }) {
    if (contents.isEmpty) {
      return;
    }
    _mutate(id, (project) {
      final next = project.slots.map((slot) {
        if (onlyIdentifiers != null &&
            !onlyIdentifiers.contains(slot.identifier)) {
          return slot;
        }
        final content = contents[slot.identifier];
        if (content == null) {
          return slot;
        }
        // 用户自填槽（破限）与 marker 槽不被 AI 覆盖。
        if (slot.userOwned || slot.marker) {
          return slot;
        }
        return slot.copyWith(content: content);
      }).toList();
      return project.copyWith(
        slots: next,
        history: snapshot ? _pushHistory(project, 'AI 改写前') : null,
      );
    });
  }

  /// 写入单个槽位内容（用户在编辑器里改）。
  void setSlotContent(String id, String identifier, String content) {
    _mutate(id, (project) {
      final next = project.slots
          .map((slot) => slot.identifier == identifier
              ? slot.copyWith(content: content)
              : slot)
          .toList();
      return project.copyWith(slots: next);
    });
  }

  void setSlotEnabled(String id, String identifier, bool enabled) {
    _mutate(id, (project) {
      // `chatHistory` 是位置标记，关掉等于历史进不了 prompt —— 不允许。
      if (identifier == 'chatHistory' && !enabled) {
        return project;
      }
      final next = project.slots
          .map((slot) => slot.identifier == identifier
              ? slot.copyWith(enabled: enabled)
              : slot)
          .toList();
      return project.copyWith(slots: next);
    }, immediate: true);
  }

  /// 改槽位 role。
  ///
  /// 锁定槽位（`chatHistory`）不允许改 —— 它的 role 不影响插入点，
  /// 改了只会让结构表看起来和实际不一致。
  void setSlotRole(String id, String identifier, String role) {
    _mutate(id, (project) {
      final next = project.slots
          .map((slot) => slot.identifier == identifier && !slot.locked
              ? slot.copyWith(role: role)
              : slot)
          .toList();
      return project.copyWith(slots: next);
    }, immediate: true);
  }

  void setSlotLabel(String id, String identifier, String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _mutate(id, (project) {
      final next = project.slots
          .map((slot) => slot.identifier == identifier
              ? slot.copyWith(label: trimmed)
              : slot)
          .toList();
      return project.copyWith(slots: next);
    });
  }

  void clearSlotContent(String id, String identifier) {
    setSlotContent(id, identifier, '');
  }

  /// 上移 / 下移槽位（[delta] 为 -1 / 1）。
  void moveSlot(String id, String identifier, int delta) {
    _mutate(id, (project) {
      final list = List<PresetSlot>.from(project.slots);
      final index = list.indexWhere((slot) => slot.identifier == identifier);
      if (index < 0) {
        return project;
      }
      final target = index + delta;
      if (target < 0 || target >= list.length) {
        return project;
      }
      final slot = list.removeAt(index);
      list.insert(target, slot);
      return project.copyWith(slots: list);
    }, immediate: true);
  }

  /// 拖拽排序：把 [identifier] 挪到 [newIndex]。
  void reorderSlot(String id, String identifier, int newIndex) {
    _mutate(id, (project) {
      final list = List<PresetSlot>.from(project.slots);
      final index = list.indexWhere((slot) => slot.identifier == identifier);
      if (index < 0) {
        return project;
      }
      final clamped = newIndex.clamp(0, list.length - 1);
      if (clamped == index) {
        return project;
      }
      final slot = list.removeAt(index);
      list.insert(clamped, slot);
      return project.copyWith(slots: list);
    }, immediate: true);
  }

  /// 删除槽位。
  ///
  /// ⛔ 引擎的 21 个槽位**不允许删** —— 删了存盘读回时会被引擎
  /// 以「默认开启」补回来，反而破坏 prefill。只能禁用。
  bool removeSlot(String id, String identifier) {
    final project = _projectById(id);
    if (project == null) {
      return false;
    }
    if (isEngineSlot(identifier)) {
      return false;
    }
    _mutate(id, (project) {
      final next =
          project.slots.where((slot) => slot.identifier != identifier).toList();
      return project.copyWith(slots: next);
    }, immediate: true);
    return true;
  }

  /// 新增一个自定义槽位，插在 [afterIdentifier] 之后（为空则插到末尾）。
  String addCustomSlot(
    String id, {
    String label = '自定义槽位',
    String role = 'system',
    String content = '',
    String? afterIdentifier,
  }) {
    final identifier = 'ykxCustom_${DateTime.now().microsecondsSinceEpoch}';
    _mutate(id, (project) {
      final list = List<PresetSlot>.from(project.slots);
      final index = afterIdentifier == null
          ? -1
          : list.indexWhere((slot) => slot.identifier == afterIdentifier);
      final slot = PresetSlot(
        identifier: identifier,
        label: label,
        role: role,
        content: content,
        intent: '用户自建槽位。',
      );
      if (index < 0) {
        list.add(slot);
      } else {
        list.insert(index + 1, slot);
      }
      return project.copyWith(slots: list);
    }, immediate: true);
    return identifier;
  }

  // --- 历史快照 ---

  List<PresetVersion> _pushHistory(PresetProject project, String label) {
    final version = PresetVersion(
      slots: project.slots
          .map((slot) => slot.copyWith())
          .toList(growable: false),
      label: label,
      at: DateTime.now(),
    );
    return <PresetVersion>[version, ...project.history]
        .take(PresetProject.maxHistory)
        .toList(growable: false);
  }

  /// 回滚到某一版快照（回滚本身也会压一版，免得回滚没法撤销）。
  void restoreVersion(String id, int historyIndex) {
    _mutate(id, (project) {
      if (historyIndex < 0 || historyIndex >= project.history.length) {
        return project;
      }
      final target = project.history[historyIndex];
      return project.copyWith(
        slots: target.slots,
        history: _pushHistory(project, '回滚到「${target.label}」前'),
      );
    }, immediate: true);
  }

  void dropHistory(String id, int historyIndex) {
    _mutate(id, (project) {
      if (historyIndex < 0 || historyIndex >= project.history.length) {
        return project;
      }
      final next = List<PresetVersion>.from(project.history)
        ..removeAt(historyIndex);
      return project.copyWith(history: next);
    });
  }

  // --- 诊断 ---

  void setDiagnosis(String id, PresetDiagnosisReport report) {
    _mutate(id, (project) => project.copyWith(diagnosis: report),
        immediate: true);
  }

  // --- 导出 ---

  void markExported(String id, String presetId) {
    _mutate(id, (project) => project.copyWith(exportedPresetId: presetId),
        immediate: true);
  }

  // --- 运行态（busy / 流式 / 错误）---

  void beginBusy(String stageText) {
    state = state.copyWith(
      busy: true,
      busyStage: stageText,
      streamPreview: '',
      error: null,
      errorRaw: null,
    );
  }

  void setBusyStage(String stageText) {
    if (!state.busy) {
      return;
    }
    state = state.copyWith(busyStage: stageText);
  }

  void pushStreamPreview(String delta) {
    if (!state.busy) {
      return;
    }
    final merged = state.streamPreview + delta;
    state = state.copyWith(
      streamPreview: merged.length > 1500
          ? merged.substring(merged.length - 1500)
          : merged,
    );
  }

  void endBusy() {
    state = state.copyWith(busy: false, busyStage: '', streamPreview: '');
  }

  void failBusy(String message, {String? raw}) {
    state = state.copyWith(
      busy: false,
      busyStage: '',
      streamPreview: '',
      error: message,
      errorRaw: raw,
    );
  }

  void clearError() {
    state = state.copyWith(error: null, errorRaw: null);
  }

  // --- 工具 ---

  PresetProject? _projectById(String id) {
    for (final project in state.projects) {
      if (project.id == id) {
        return project;
      }
    }
    return null;
  }

  @override
  void dispose() {
    flushPendingWrites();
    for (final timer in _persistTimers.values) {
      timer.cancel();
    }
    _persistTimers.clear();
    super.dispose();
  }
}
