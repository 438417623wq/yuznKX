import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/persona.dart';

// 1. List of Personas
final personaListProvider = StateNotifierProvider<PersonaListNotifier, List<Persona>>((ref) {
  return PersonaListNotifier();
});

class PersonaListNotifier extends StateNotifier<List<Persona>> {
  PersonaListNotifier() : super([]) {
    _init();
  }

  Box? _box;

  Future<void> _init() async {
    _box = await Hive.openBox('personas');
    _load();
  }

  void _load() {
    if (_box == null) return;
    final data = _box!.values.toList();
    if (data.isEmpty) {
      // Create default if empty
      final defaultPersona = Persona.createDefault();
      save(defaultPersona);
    } else {
      state = data.map((e) => Persona.fromJson(Map<String, dynamic>.from(e))).toList();
    }
  }

  Future<void> save(Persona persona) async {
    if (_box == null) await _init();
    await _box!.put(persona.id, persona.toJson());
    
    // Update state
    final index = state.indexWhere((p) => p.id == persona.id);
    if (index >= 0) {
      final newState = [...state];
      newState[index] = persona;
      state = newState;
    } else {
      state = [...state, persona];
    }
  }

  Future<void> delete(String id) async {
    if (_box == null) await _init();
    await _box!.delete(id);
    state = state.where((p) => p.id != id).toList();
  }
}

// 2. Active Persona ID
final activePersonaIdProvider = StateNotifierProvider<ActivePersonaIdNotifier, String?>((ref) {
  return ActivePersonaIdNotifier();
});

class ActivePersonaIdNotifier extends StateNotifier<String?> {
  ActivePersonaIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    state = box.get('active_persona_id');
  }

  Future<void> setActive(String id) async {
    state = id;
    final box = await Hive.openBox('settings');
    await box.put('active_persona_id', id);
  }
}

// 3. Active Persona Object (Derived)
final personaProvider = Provider<Persona>((ref) {
  final list = ref.watch(personaListProvider);
  final activeId = ref.watch(activePersonaIdProvider);
  
  if (list.isEmpty) return Persona.createDefault();
  
  if (activeId != null) {
    try {
      return list.firstWhere((p) => p.id == activeId);
    } catch (_) {}
  }
  
  // Fallback to first
  return list.first;
});
