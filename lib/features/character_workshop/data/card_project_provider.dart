import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../character/data/character_provider.dart';
import '../../character/domain/models/character.dart';
import '../../regex/data/regex_provider.dart';
import '../../world_info/data/world_info_provider.dart';
import '../domain/models/card_project.dart';
import '../domain/models/check_report.dart';
import '../domain/models/creation_plan.dart';
import '../domain/models/design_spec.dart';
import '../domain/models/project_entry.dart';
import '../domain/models/source_material.dart';
import '../domain/models/card_field.dart';
import '../domain/models/workshop_record.dart';
import 'card_avatar_factory.dart';
import 'worldbook_packager.dart';

/// 创作项目的持久化 box。
const String kCardProjectBoxName = 'card_projects';

/// 旧版「一键生成」历史所在的 box（只读，用于一次性迁移）。
const String kLegacyWorkshopBoxName = 'character_workshop';

/// 迁移标记所在的 box。
const String kSettingsBoxName = 'settings';

/// 迁移一次性标记键。
const String kLegacyMigratedKey = 'card_projects_legacy_migrated';

/// 界面状态。
class CardProjectState {
  const CardProjectState({
    this.projects = const <CardProject>[],
    this.loaded = false,
    this.busy = false,
    this.busyStage = '',
    this.streamPreview = '',
    this.error,
    this.errorRaw,
  });

  /// 全部项目，按 `updatedAt` 降序。
  final List<CardProject> projects;

  final bool loaded;

  /// 是否有 AI 任务在跑。
  final bool busy;

  /// 进度文案（「正在写「铁匠铺」…」）。
  final String busyStage;

  /// 流式返回的实时片段（只保留尾部）。
  final String streamPreview;

  final String? error;
  final String? errorRaw;

  CardProjectState copyWith({
    List<CardProject>? projects,
    bool? loaded,
    bool? busy,
    String? busyStage,
    String? streamPreview,
    Object? error = _unset,
    Object? errorRaw = _unset,
  }) {
    return CardProjectState(
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

final cardProjectProvider =
    StateNotifierProvider<CardProjectNotifier, CardProjectState>((ref) {
  return CardProjectNotifier(ref);
});

/// 按 ID 取单个项目。
///
/// 工作台直接用它取数据，而不依赖「当前打开的项目」这种全局状态 ——
/// 这样同一时刻看多个项目也不会互相干扰。
final cardProjectByIdProvider =
    Provider.family<CardProject?, String>((ref, id) {
  final projects = ref.watch(cardProjectProvider).projects;
  for (final project in projects) {
    if (project.id == id) {
      return project;
    }
  }
  return null;
});

/// 创作项目的中枢：CRUD、阶段流转、条目管理、持久化、旧数据迁移。
///
/// **断点续接的实现方式**：任何改动都立即（或 400ms 内）落进 Hive box。
/// 杀掉进程重进时 `_restore()` 会原样读回来，并自动定位到第一条未完成的条目。
/// 不依赖任何对话上下文。
class CardProjectNotifier extends StateNotifier<CardProjectState> {
  CardProjectNotifier(this._ref) : super(const CardProjectState()) {
    unawaited(_restore());
  }

  final Ref _ref;
  Box? _box;

  /// 每个项目一个防抖定时器，避免编辑正文时每个按键都写磁盘。
  final Map<String, Timer> _persistTimers = <String, Timer>{};

  // --- 初始化 ---

  Future<Box?> _ensureBox() async {
    if (_box != null && _box!.isOpen) {
      return _box;
    }
    try {
      if (Hive.isBoxOpen(kCardProjectBoxName)) {
        _box = Hive.box(kCardProjectBoxName);
      } else {
        _box = await Hive.openBox(kCardProjectBoxName);
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

    final projects = <CardProject>[];
    for (final value in box.values) {
      try {
        if (value is Map) {
          final project =
              CardProject.fromJson(Map<String, dynamic>.from(value));
          if (project.id.isNotEmpty) {
            projects.add(project);
          }
        }
      } catch (_) {
        // 单条损坏不影响其它项目。
      }
    }

    await _migrateLegacyHistoryOnce(projects);

    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: projects, loaded: true);
  }

  /// 把旧版「一键生成」的历史记录迁移成只读项目。
  ///
  /// 照 `_migrateMemoryToSessionKeyOnce()` 的模式，用 settings box 的标记位保证只跑一次。
  /// 迁移失败不抛异常 —— 旧数据丢了也不该阻塞新功能。
  Future<void> _migrateLegacyHistoryOnce(List<CardProject> projects) async {
    try {
      if (!Hive.isBoxOpen(kSettingsBoxName)) {
        return;
      }
      final settings = Hive.box(kSettingsBoxName);
      if (settings.get(kLegacyMigratedKey) == true) {
        return;
      }

      if (Hive.isBoxOpen(kLegacyWorkshopBoxName)) {
        final legacyBox = Hive.box(kLegacyWorkshopBoxName);
        final rawHistory = legacyBox.get('history');
        if (rawHistory is List) {
          for (final item in rawHistory) {
            if (item is! Map) {
              continue;
            }
            try {
              final record =
                  WorkshopRecord.fromJson(Map<String, dynamic>.from(item));
              final project = _legacyRecordToProject(record);
              projects.add(project);
              await _box?.put(project.id, project.toJson());
            } catch (_) {
              // 单条迁移失败就跳过。
            }
          }
        }
      }

      await settings.put(kLegacyMigratedKey, true);
    } catch (_) {
      // 迁移是尽力而为，失败静默。
    }
  }

  CardProject _legacyRecordToProject(WorkshopRecord record) {
    final data = record.data;
    final entries = <ProjectEntry>[];

    void addEntry(String key, dynamic value, int order) {
      final text = _stringify(value);
      if (text.isEmpty) {
        return;
      }
      entries.add(
        ProjectEntry(
          id: const Uuid().v4(),
          title: cardFieldLabel(key),
          kind: EntryKind.characterCard,
          fieldKey: key,
          brief: cardFieldByKey(key)?.instruction ?? '',
          content: text,
          order: order,
          status: EntryStatus.done,
          updatedAt: record.createdAt,
        ),
      );
    }

    var order = 0;
    addEntry(kNameFieldKey, data['name'], order++);
    for (final field in kCardFields) {
      if (data.containsKey(field.key)) {
        addEntry(field.key, data[field.key], order++);
      }
    }

    final name = record.title;

    return CardProject(
      id: record.id.isEmpty ? const Uuid().v4() : record.id,
      name: name,
      stage: ProjectStage.done,
      createdAt: record.createdAt,
      updatedAt: record.createdAt,
      designSpec: DesignSpec(
        answers: <String, String>{
          SpecDimension.positioning.key: record.prompt,
        },
        confirmed: record.prompt.trim().isEmpty
            ? const <String>{}
            : <String>{SpecDimension.positioning.key},
      ),
      entries: entries,
      isLegacy: true,
    );
  }

  static String _stringify(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    return value.toString().trim();
  }

  // --- 持久化 ---

  void _persist(CardProject project, {bool immediate = false}) {
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
    CardProject Function(CardProject project) transform, {
    bool immediate = false,
  }) {
    final index = state.projects.indexWhere((project) => project.id == id);
    if (index < 0) {
      return;
    }
    final next = transform(state.projects[index]);
    final list = List<CardProject>.from(state.projects);
    list[index] = next;
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: list);
    _persist(next, immediate: immediate);
  }

  // --- 项目 CRUD ---

  CardProject createProject({String name = ''}) {
    final project = CardProject(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? '未命名项目' : name.trim(),
    );
    final list = <CardProject>[project, ...state.projects];
    state = state.copyWith(projects: list);
    _persist(project, immediate: true);
    return project;
  }

  void deleteProject(String id) {
    _persistTimers.remove(id)?.cancel();
    unawaited(_box?.delete(id));
    final list =
        state.projects.where((project) => project.id != id).toList();
    state = state.copyWith(projects: list);
  }

  void renameProject(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _mutate(id, (project) => project.copyWith(name: trimmed), immediate: true);
  }

  void setStage(String id, ProjectStage stage) {
    _mutate(id, (project) => project.copyWith(stage: stage), immediate: true);
  }

  /// 推进到下一个阶段（已是最后一阶段则不动）。
  void advanceStage(String id) {
    final project = _projectById(id);
    if (project == null) {
      return;
    }
    final next = project.stage.index0 + 1;
    if (next >= ProjectStage.values.length) {
      return;
    }
    setStage(id, ProjectStage.values[next]);
  }

  // --- 需求对齐 ---

  void updateDesignSpec(String id, DesignSpec spec) {
    _mutate(id, (project) => project.copyWith(designSpec: spec));
  }

  // --- 创作规划 ---

  void updatePlan(String id, CreationPlan plan) {
    _mutate(id, (project) => project.copyWith(plan: plan));
  }

  // --- 条目 ---

  void setEntries(String id, List<ProjectEntry> entries) {
    _mutate(
      id,
      (project) => project.copyWith(
        entries: _sorted(entries),
      ),
      immediate: true,
    );
  }

  void addEntry(String id, ProjectEntry entry) {
    _mutate(id, (project) {
      final next = List<ProjectEntry>.from(project.entries)..add(entry);
      return project.copyWith(entries: _sorted(next));
    }, immediate: true);
  }

  void updateEntry(String id, ProjectEntry entry) {
    _mutate(id, (project) {
      final next = project.entries
          .map((item) => item.id == entry.id ? entry : item)
          .toList();
      return project.copyWith(entries: _sorted(next));
    });
  }

  void removeEntry(String id, String entryId) {
    _mutate(id, (project) {
      final next =
          project.entries.where((item) => item.id != entryId).toList();
      return project.copyWith(entries: next);
    }, immediate: true);
  }

  /// 上下移动条目（[delta] 为 -1 / 1）。
  void moveEntry(String id, String entryId, int delta) {
    _mutate(id, (project) {
      final list = _sorted(List<ProjectEntry>.from(project.entries));
      final index = list.indexWhere((item) => item.id == entryId);
      if (index < 0) {
        return project;
      }
      final target = index + delta;
      if (target < 0 || target >= list.length) {
        return project;
      }
      final item = list.removeAt(index);
      list.insert(target, item);
      // 重排 order，保证落库后顺序稳定。
      final reordered = <ProjectEntry>[];
      for (var i = 0; i < list.length; i++) {
        reordered.add(list[i].copyWith(order: (i + 1) * 10));
      }
      return project.copyWith(entries: reordered);
    }, immediate: true);
  }

  void setEntryStatus(
    String id,
    String entryId,
    EntryStatus status, {
    String? error,
  }) {
    _mutate(id, (project) {
      final next = project.entries.map((item) {
        if (item.id != entryId) {
          return item;
        }
        return item.copyWith(
          status: status,
          error: error,
          updatedAt: DateTime.now(),
        );
      }).toList();
      return project.copyWith(entries: next);
    }, immediate: true);
  }

  /// 更新条目正文（编辑时高频调用，走防抖落盘）。
  void setEntryContent(String id, String entryId, String content) {
    _mutate(id, (project) {
      final next = project.entries.map((item) {
        if (item.id != entryId) {
          return item;
        }
        return item.copyWith(
          content: content,
          status: content.trim().isEmpty ? EntryStatus.pending : item.status,
          updatedAt: DateTime.now(),
        );
      }).toList();
      return project.copyWith(entries: next);
    });
  }

  /// 把条目的 `revision`（被改写过几次）+1。
  ///
  /// 这个字段在数据模型里躺了很久从来没被写过 ——
  /// 「按质检意见逐条修复」是它的第一个真实用途。
  void bumpEntryRevision(String id, String entryId) {
    _mutate(id, (project) {
      final next = project.entries.map((item) {
        if (item.id != entryId) {
          return item;
        }
        return item.copyWith(revision: item.revision + 1);
      }).toList();
      return project.copyWith(entries: next);
    });
  }

  // --- 材料 ---

  void setSources(String id, List<SourceMaterial> sources) {
    _mutate(id, (project) => project.copyWith(sources: sources));
  }

  void addSource(String id, SourceMaterial source) {
    _mutate(id, (project) {
      final next = List<SourceMaterial>.from(project.sources)..add(source);
      return project.copyWith(sources: next);
    }, immediate: true);
  }

  void updateSource(String id, SourceMaterial source) {
    _mutate(id, (project) {
      final next = project.sources
          .map((item) => item.id == source.id ? source : item)
          .toList();
      return project.copyWith(sources: next);
    });
  }

  void removeSource(String id, String sourceId) {
    _mutate(id, (project) {
      final next =
          project.sources.where((item) => item.id != sourceId).toList();
      return project.copyWith(sources: next);
    }, immediate: true);
  }

  // --- 质检 ---

  void setCheckReport(String id, CheckReport? report) {
    _mutate(
      id,
      (project) => project.copyWith(lastCheck: report),
      immediate: true,
    );
  }

  // --- MVU ---

  void setMvu(
    String id, {
    String? schemaText,
    String? initvarText,
    String? updateRulesText,
    String? variablesJson,
  }) {
    _mutate(
      id,
      (project) => project.copyWith(
        mvuSchemaText: schemaText,
        mvuInitvarText: initvarText,
        mvuUpdateRulesText: updateRulesText,
        mvuVariablesJson: variablesJson,
      ),
      immediate: true,
    );
  }

  // --- 前端面板 ---

  /// 写入 / 更新前端面板 HTML（upsert）。
  ///
  /// 面板在 [CardProject.entries] 里以 [EntryKind.frontend] 条目存在，但
  /// [CardProject.firstUnsettled] 会跳过它，所以不会卡住「逐条产出」。
  /// 内容为空时把状态退回 [EntryStatus.pending]，让进度统计如实反映。
  void setFrontendHtml(String id, String html) {
    _mutate(id, (project) {
      final existing = project.frontendEntry;
      final trimmed = html.trim();

      if (existing == null) {
        if (trimmed.isEmpty) {
          return project;
        }
        final entry = ProjectEntry(
          id: 'frontend_${DateTime.now().microsecondsSinceEpoch}',
          title: '前端面板',
          kind: EntryKind.frontend,
          brief: '带交互的状态面板（HTML/CSS/JS）',
          content: html,
          // 排到最后，免得插进写作阶段的列表中间。
          order: 900,
          status: EntryStatus.done,
          updatedAt: DateTime.now(),
        );
        return project.copyWith(entries: _sorted([...project.entries, entry]));
      }

      final next = existing.copyWith(
        content: html,
        status: trimmed.isEmpty ? EntryStatus.pending : EntryStatus.done,
        updatedAt: DateTime.now(),
      );
      return project.copyWith(
        entries: _sorted(
          project.entries
              .map((item) => item.id == next.id ? next : item)
              .toList(),
        ),
      );
    });
  }

  // --- 导出 ---

  void markExported(String id, String characterId) {
    _mutate(
      id,
      (project) => project.copyWith(exportedCharacterId: characterId),
      immediate: true,
    );
  }

  /// 把项目落库成角色卡 + 世界书。重复调用是幂等的（更新同一张卡）。
  Future<Character?> exportToCharacter(String id) async {
    final project = _projectById(id);
    if (project == null) {
      return null;
    }

    final packed = WorldbookPackager.pack(
      project,
      existingCharacterId: project.exportedCharacterId,
    );
    // 工坊产出的卡没有立绘，补一张占位头像，否则在列表和酒馆里都是一片空白。
    final character =
        await CardAvatarFactory.withPlaceholderAvatar(packed.character);
    // 先落世界书，再落角色卡 —— 角色卡上的 characterBookId 才有意义。
    if (packed.worldbook != null) {
      await _ref.read(worldInfoProvider.notifier).save(packed.worldbook!);
    }
    // 前端面板的挂载点正则也要落进池子。
    //
    // 不落的话，刚导出的卡在 App 内**立刻**用不了前端面板 —— 得等一次重新导入，
    // `_parseV2Spec()` 才会把 `extensions.regex_scripts` 写进池子。
    if (packed.mountScript != null) {
      await _ref.read(regexScriptsProvider.notifier).save(packed.mountScript!);
    }
    await _ref.read(characterListProvider.notifier).save(character);
    markExported(id, character.id);
    return character;
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

  CardProject? _projectById(String id) {
    for (final project in state.projects) {
      if (project.id == id) {
        return project;
      }
    }
    return null;
  }

  static List<ProjectEntry> _sorted(List<ProjectEntry> entries) {
    final list = List<ProjectEntry>.from(entries);
    list.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) {
        return byOrder;
      }
      return a.title.compareTo(b.title);
    });
    return list;
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
