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
  
  void _load() {
    final box = Hive.box('settings');
    final List<dynamic>? raw = box.get('active_regex_ids');
    if (raw != null) {
      state = raw.cast<String>();
    }
  }

  Future<void> toggle(String id) async {
    if (state.contains(id)) {
      state = state.where((e) => e != id).toList();
    } else {
      state = [...state, id];
    }
    final box = Hive.box('settings');
    await box.put('active_regex_ids', state);
  }
}
