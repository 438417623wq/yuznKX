import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/session.dart';
import '../domain/models/chat_message.dart';

final sessionProvider = StateNotifierProvider<SessionNotifier, List<Session>>((ref) {
  return SessionNotifier();
});

final activeSessionIdProvider = StateNotifierProvider<ActiveSessionIdNotifier, String?>((ref) {
  return ActiveSessionIdNotifier();
});

class ActiveSessionIdNotifier extends StateNotifier<String?> {
  ActiveSessionIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    state = box.get('active_session_id');
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = await Hive.openBox('settings');
    if (id == null) {
      await box.delete('active_session_id');
    } else {
      await box.put('active_session_id', id);
    }
  }
}

class SessionNotifier extends StateNotifier<List<Session>> {
  late Box _box;

  SessionNotifier() : super([]) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox('sessions');
    _loadSessions();
  }

  void _loadSessions() {
    final data = _box.values.toList();
    state = data.map((e) => Session.fromJson(Map<String, dynamic>.from(e))).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Sort by recent
  }

  Future<void> createSession(String name, {String? characterId}) async {
    final newSession = Session(
      id: const Uuid().v4(),
      name: name,
      characterId: characterId ?? '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [],
    );
    await _box.put(newSession.id, newSession.toJson());
    state = [newSession, ...state];
  }

  Future<void> updateSession(Session session) async {
    await _box.put(session.id, session.toJson());
    
    final index = state.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      final newState = [...state];
      newState[index] = session;
      newState.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = newState;
    } else {
      // Should not happen for update, but if so, add it
      state = [session, ...state];
    }
  }

  Future<void> updateSessionMessages(String sessionId, List<ChatMessage> messages) async {
    final index = state.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      final updatedSession = state[index].copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      
      await _box.put(sessionId, updatedSession.toJson());
      
      // Update state
      final newState = [...state];
      newState[index] = updatedSession;
      newState.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = newState;
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _box.delete(sessionId);
    state = state.where((s) => s.id != sessionId).toList();
  }
}
