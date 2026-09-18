import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/regex_script.dart';

final regexScriptsProvider = StateNotifierProvider<RegexScriptsNotifier, List<RegexScript>>((ref) => RegexScriptsNotifier());
final activeRegexScriptIdsProvider = StateNotifierProvider<ActiveRegexIdsNotifier, List<String>>((ref) => ActiveRegexIdsNotifier());

class RegexScriptsNotifier extends StateNotifier<List<RegexScript>> {
  RegexScriptsNotifier() : super([]) { _load(); }
  static const _boxName = 'regex_scripts';
  Box? _box;

  void _load() {
    _box = Hive.box(_boxName);
    final List<RegexScript> loaded = [];
    for (final e in _box!.values) {
      try {
        loaded.add(RegexScript.fromJson(Map<String, dynamic>.from(e)));
      } catch (e) {
        print('Error loading regex script: $e');
      }
    }
    state = loaded;
  }

  Future<void> save(RegexScript item) async {
    _box ??= Hive.box(_boxName);
    final index = state.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      final newState = [...state];
      newState[index] = item;
      state = newState;
    } else {
      state = [...state, item];
    }
    await _box!.put(item.id, item.toJson());
  }

  Future<void> delete(String id) async {
    _box ??= Hive.box(_boxName);
    state = state.where((e) => e.id != id).toList();
    await _box!.delete(id);
  }
}

class ActiveRegexIdsNotifier extends StateNotifier<List<String>> {
  ActiveRegexIdsNotifier() : super([]) { _load(); }

  static const _settingsKey = 'active_regex_ids';

  void _load() {
    final box = Hive.box('settings');
    final List<dynamic>? raw = box.get(_settingsKey);
    if (raw != null) {
      state = raw.cast<String>();
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

  /// 显式设置某个脚本的「全局生效」状态。
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
