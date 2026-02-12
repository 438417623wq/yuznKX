import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/world_info.dart';

final worldInfoProvider = StateNotifierProvider<WorldInfoNotifier, List<WorldInfo>>((ref) => WorldInfoNotifier());
final activeWorldInfoIdsProvider = StateNotifierProvider<ActiveWorldInfoIdsNotifier, List<String>>((ref) => ActiveWorldInfoIdsNotifier());

class WorldInfoNotifier extends StateNotifier<List<WorldInfo>> {
  WorldInfoNotifier() : super([]) { _load(); }
  static const _boxName = 'world_info';
  Box? _box;

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    // Don't overwrite if state was already populated by save() unless box has more
    if (state.isEmpty && _box!.isNotEmpty) {
       state = _box!.values.map((e) => WorldInfo.fromJson(Map<String, dynamic>.from(e))).toList();
    } else if (_box!.isNotEmpty) {
      // Merge strategy?
      // Simple strategy: trust the box.
      // But if save() ran before _load(), box should have the new item.
      // So trusting the box is correct.
      state = _box!.values.map((e) => WorldInfo.fromJson(Map<String, dynamic>.from(e))).toList();
    }
  }

  Future<void> save(WorldInfo item) async {
    _box ??= await Hive.openBox(_boxName);
    
    // Ensure we are up to date with the box before saving, 
    // BUT we must not lose the current state if it's ahead of the box (unlikely here).
    // The main issue was _load overwriting state.
    // Since save writes to box, if _load runs after save, it reads from box, which includes the new item.
    // If _load runs before save, it sets state. Then save updates state.
    // The only danger is if _load reads (snapshot), then save writes, then _load sets state.
    
    // To avoid this, we can just rely on state manipulation being atomic relative to the box write?
    // No.
    
    // Let's just write to box first.
    await _box!.put(item.id, item.toJson());
    
    // Then update state from memory (optimistic update)
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
    _box ??= await Hive.openBox(_boxName);
    state = state.where((e) => e.id != id).toList();
    await _box!.delete(id);
  }
}

class ActiveWorldInfoIdsNotifier extends StateNotifier<List<String>> {
  ActiveWorldInfoIdsNotifier() : super([]) { _load(); }
  
  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    final raw = box.get('active_world_info_ids');
    if (raw != null) {
      if (raw is List) {
        state = raw.cast<String>();
      } else if (raw is String) {
        // Migration from old single ID if exists
        state = [raw];
      }
    }
  }

  Future<void> toggle(String id) async {
    if (state.contains(id)) {
      state = state.where((e) => e != id).toList();
    } else {
      state = [...state, id];
    }
    final box = await Hive.openBox('settings');
    await box.put('active_world_info_ids', state);
  }
}
