import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/persona.dart';

final personaProvider = StateNotifierProvider<PersonaNotifier, Persona>((ref) {
  return PersonaNotifier();
});

class PersonaNotifier extends StateNotifier<Persona> {
  PersonaNotifier() : super(Persona.createDefault()) {
    _loadPersona();
  }

  Future<void> _loadPersona() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('user_persona');
    if (jsonString != null) {
      try {
        state = Persona.fromJson(jsonDecode(jsonString));
      } catch (e) {
        print("Error loading persona: $e");
      }
    }
  }

  Future<void> updatePersona(Persona persona) async {
    state = persona;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_persona', jsonEncode(persona.toJson()));
  }

  Future<void> updateName(String name) async {
    final updated = state.copyWith(name: name);
    await updatePersona(updated);
  }

  Future<void> updateDescription(String description) async {
    final updated = state.copyWith(description: description);
    await updatePersona(updated);
  }

  Future<void> updateAvatar(String path) async {
    final updated = state.copyWith(avatarPath: path);
    await updatePersona(updated);
  }
}
