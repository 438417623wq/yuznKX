import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/preset.dart';

// Providers
final presetsProvider = StateNotifierProvider<PresetsNotifier, List<Preset>>((ref) => PresetsNotifier());
final activePresetIdProvider = StateNotifierProvider<ActivePresetIdNotifier, String?>((ref) => ActivePresetIdNotifier());

final activePresetProvider = Provider<Preset?>((ref) {
  final id = ref.watch(activePresetIdProvider);
  final list = ref.watch(presetsProvider);
  if (id == null) return null;
  try {
    return list.firstWhere((e) => e.id == id);
  } catch (_) {
    return null;
  }
});

class PresetsNotifier extends StateNotifier<List<Preset>> {
  PresetsNotifier() : super([]) {
    _load();
  }

  static const _boxName = 'presets';
  Box? _box;

  void _load() {
    _box = Hive.box(_boxName);
    final raw = _box!.values;
    final List<Preset> loaded = [];
    for (final e in raw) {
      try {
        loaded.add(Preset.fromJson(Map<String, dynamic>.from(e)));
      } catch (e) {
        print('Error loading preset: $e');
      }
    }
    state = loaded;
  }

  Future<void> save(Preset item) async {
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
    await _box!.flush();
  }

  Future<void> delete(String id) async {
    _box ??= Hive.box(_boxName);
    state = state.where((e) => e.id != id).toList();
    await _box!.delete(id);
    await _box!.flush();
  }
}

class ActivePresetIdNotifier extends StateNotifier<String?> {
  ActivePresetIdNotifier() : super(null) {
    _load();
  }

  void _load() {
    final box = Hive.box('settings');
    state = box.get('active_preset_id');
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = Hive.box('settings');
    if (id == null) {
      await box.delete('active_preset_id');
    } else {
      await box.put('active_preset_id', id);
    }
  }
}
