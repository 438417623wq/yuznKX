import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/world_info.dart';

final worldInfoProvider = StateNotifierProvider<WorldInfoNotifier, List<WorldInfo>>((ref) => WorldInfoNotifier());
final activeWorldInfoIdsProvider = StateNotifierProvider<ActiveWorldInfoIdsNotifier, List<String>>((ref) => ActiveWorldInfoIdsNotifier());
final worldInfoSettingsProvider =
    StateNotifierProvider<WorldInfoSettingsNotifier, WorldInfoScanSettings>(
        (ref) => WorldInfoSettingsNotifier());

enum WorldInfoCharacterStrategy {
  evenly,
  characterFirst,
  globalFirst,
}

class WorldInfoScanSettings {
  final int scanDepth;
  final int minActivations;
  final int minActivationsDepthMax;
  final int budgetPercentage;
  final bool recursive;
  final WorldInfoCharacterStrategy characterStrategy;
  final int budgetCap;
  final bool includeNames;

  const WorldInfoScanSettings({
    this.scanDepth = 2,
    this.minActivations = 0,
    this.minActivationsDepthMax = 0,
    this.budgetPercentage = 25,
    this.recursive = false,
    this.characterStrategy = WorldInfoCharacterStrategy.characterFirst,
    this.budgetCap = 0,
    this.includeNames = true,
  });

  WorldInfoScanSettings copyWith({
    int? scanDepth,
    int? minActivations,
    int? minActivationsDepthMax,
    int? budgetPercentage,
    bool? recursive,
    WorldInfoCharacterStrategy? characterStrategy,
    int? budgetCap,
    bool? includeNames,
  }) {
    return WorldInfoScanSettings(
      scanDepth: scanDepth ?? this.scanDepth,
      minActivations: minActivations ?? this.minActivations,
      minActivationsDepthMax:
          minActivationsDepthMax ?? this.minActivationsDepthMax,
      budgetPercentage: budgetPercentage ?? this.budgetPercentage,
      recursive: recursive ?? this.recursive,
      characterStrategy: characterStrategy ?? this.characterStrategy,
      budgetCap: budgetCap ?? this.budgetCap,
      includeNames: includeNames ?? this.includeNames,
    );
  }

  factory WorldInfoScanSettings.fromHive(Box box) {
    int readInt(String key, int fallback) {
      final raw = box.get(key);
      if (raw is int) {
        return raw;
      }
      if (raw is num) {
        return raw.toInt();
      }
      if (raw is String) {
        return int.tryParse(raw.trim()) ?? fallback;
      }
      return fallback;
    }

    bool readBool(String key, bool fallback) {
      final raw = box.get(key);
      if (raw is bool) {
        return raw;
      }
      if (raw is num) {
        return raw != 0;
      }
      if (raw is String) {
        final normalized = raw.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') {
          return true;
        }
        if (normalized == 'false' || normalized == '0') {
          return false;
        }
      }
      return fallback;
    }

    WorldInfoCharacterStrategy readStrategy() {
      final raw = readInt(
        'world_info_character_strategy',
        WorldInfoCharacterStrategy.characterFirst.index,
      );
      if (raw == WorldInfoCharacterStrategy.evenly.index) {
        return WorldInfoCharacterStrategy.evenly;
      }
      if (raw == WorldInfoCharacterStrategy.globalFirst.index) {
        return WorldInfoCharacterStrategy.globalFirst;
      }
      return WorldInfoCharacterStrategy.characterFirst;
    }

    return WorldInfoScanSettings(
      scanDepth: readInt('world_info_depth', 2).clamp(0, 1000),
      minActivations:
          readInt('world_info_min_activations', 0).clamp(0, 1000),
      minActivationsDepthMax:
          readInt('world_info_min_activations_depth_max', 0)
              .clamp(0, 1000),
      budgetPercentage: readInt('world_info_budget', 25).clamp(0, 100),
      recursive: readBool('world_info_recursive', false),
      characterStrategy: readStrategy(),
      budgetCap: readInt('world_info_budget_cap', 0).clamp(0, 1 << 20),
      includeNames: readBool('world_info_include_names', true),
    );
  }
}

class WorldInfoNotifier extends StateNotifier<List<WorldInfo>> {
  WorldInfoNotifier() : super([]) { _load(); }
  static const _boxName = 'world_info';
  Box? _box;

  void _load() {
    _box = Hive.box(_boxName);
    if (_box!.isNotEmpty) {
      final List<WorldInfo> loaded = [];
      for (final e in _box!.values) {
        try {
          loaded.add(WorldInfo.fromJson(Map<String, dynamic>.from(e)));
        } catch (e) {
          print('Error loading world info: $e');
        }
      }
      state = loaded;
    }
  }

  Future<void> save(WorldInfo item) async {
    _box ??= Hive.box(_boxName);
    
    await _box!.put(item.id, item.toJson());
    
    final index = state.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      final newState = [...state];
      newState[index] = item;
      state = newState;
    } else {
      state = [...state, item];
    }
  }

  Future<void> delete(String id) async {
    _box ??= Hive.box(_boxName);
    state = state.where((e) => e.id != id).toList();
    await _box!.delete(id);
  }
}

class ActiveWorldInfoIdsNotifier extends StateNotifier<List<String>> {
  ActiveWorldInfoIdsNotifier() : super([]) { _load(); }

  static const _settingsKey = 'active_world_info_ids';

  void _load() {
    final box = Hive.box('settings');
    final raw = box.get(_settingsKey);
    if (raw != null) {
      if (raw is List) {
        state = raw.cast<String>();
      } else if (raw is String) {
        // Migration from old single ID if exists
        state = [raw];
      }
    }
  }

  Future<void> _persist(List<String> next) async {
    state = next;
    final box = Hive.box('settings');
    await box.put(_settingsKey, next);
  }

  Future<void> toggle(String id) async {
    if (state.contains(id)) {
      await _persist(state.where((e) => e != id).toList());
    } else {
      await _persist([...state, id]);
    }
  }

  /// 显式设置某本世界书的「全局生效」状态。
  ///
  /// 相比 [toggle]，本方法幂等：重复设为同一状态不会来回翻转，
  /// 适合绑定到开关控件。
  Future<void> setActive(String id, bool active) async {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    final next = state.toSet();
    if (active) {
      next.add(normalized);
    } else {
      next.remove(normalized);
    }
    await _persist(next.toList());
  }

  /// 批量设置「全局生效」状态，用于分组级别的全选 / 全不选。
  Future<void> setMany(Iterable<String> ids, bool active) async {
    final next = state.toSet();
    var changed = false;
    for (final raw in ids) {
      final normalized = raw.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (active) {
        if (next.add(normalized)) {
          changed = true;
        }
      } else {
        if (next.remove(normalized)) {
          changed = true;
        }
      }
    }
    if (!changed) {
      return;
    }
    await _persist(next.toList());
  }
}

class WorldInfoSettingsNotifier extends StateNotifier<WorldInfoScanSettings> {
  WorldInfoSettingsNotifier() : super(const WorldInfoScanSettings()) {
    _load();
  }

  void _load() {
    final box = Hive.box('settings');
    state = WorldInfoScanSettings.fromHive(box);
  }

  Future<void> update(WorldInfoScanSettings settings) async {
    state = settings;
    final box = Hive.box('settings');
    await box.put('world_info_depth', settings.scanDepth);
    await box.put('world_info_min_activations', settings.minActivations);
    await box.put(
      'world_info_min_activations_depth_max',
      settings.minActivationsDepthMax,
    );
    await box.put('world_info_budget', settings.budgetPercentage);
    await box.put('world_info_recursive', settings.recursive);
    await box.put(
      'world_info_character_strategy',
      settings.characterStrategy.index,
    );
    await box.put('world_info_budget_cap', settings.budgetCap);
    await box.put('world_info_include_names', settings.includeNames);
  }
}
