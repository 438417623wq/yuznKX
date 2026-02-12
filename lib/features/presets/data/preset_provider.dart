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

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box!.values;
    state = raw.map((e) => Preset.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> save(Preset item) async {
    _box ??= await Hive.openBox(_boxName);
    
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
    _box ??= await Hive.openBox(_boxName);
    state = state.where((e) => e.id != id).toList();
    await _box!.delete(id);
  }
}

class ActivePresetIdNotifier extends StateNotifier<String?> {
  ActivePresetIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    state = box.get('active_preset_id');
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = await Hive.openBox('settings');
    if (id == null) {
      await box.delete('active_preset_id');
    } else {
      await box.put('active_preset_id', id);
    }
  }
}
