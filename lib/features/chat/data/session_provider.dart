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

  void _load() {
    final box = Hive.box('settings');
    state = box.get('active_session_id') as String?;
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = Hive.box('settings');
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

  void _init() {
    _box = Hive.box('sessions');
    _loadSessions();
  }

  void _loadSessions() {
    final data = _box.values.toList();
    final List<Session> loadedSessions = [];
    for (final e in data) {
      try {
        loadedSessions.add(Session.fromJson(Map<String, dynamic>.from(e)));
      } catch (e) {
        print('Error loading session: $e');
      }
    }
    loadedSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = loadedSessions;
  }

  Future<Session> createSession(
    String name, {
    String? characterId,
    List<String>? groupCharacterIds,
    List<String>? worldInfoIds,
  }) async {
    final now = DateTime.now();
    final newSession = Session(
      id: const Uuid().v4(),
      name: name,
      characterId: characterId ?? '',
      groupCharacterIds: groupCharacterIds ?? [],
      worldInfoIds: worldInfoIds ?? [],
      createdAt: now,
      updatedAt: now,
      messages: [],
    );
    await _box.put(newSession.id, newSession.toJson());
    _upsertInState(newSession);
    return newSession;
  }

  Future<void> updateSession(Session session) async {
    final touchedSession = session.copyWith(updatedAt: DateTime.now());
    await _box.put(touchedSession.id, touchedSession.toJson());
    _upsertInState(touchedSession);
  }

  Future<void> updateSessionMessages(
    String sessionId,
    List<ChatMessage> messages, {
    String? fallbackCharacterId,
    String? fallbackName,
    List<String>? fallbackGroupCharacterIds,
    List<String>? fallbackWorldInfoIds,
    bool createIfMissing = true,
  }) async {
    final index = state.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      final updatedSession = state[index].copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      
      await _box.put(sessionId, updatedSession.toJson());
      await _box.flush(); // Ensure data is persisted
      _upsertInState(updatedSession);
      return;
    }

    if (!createIfMissing) {
      return;
    }

    final now = DateTime.now();
    final newSession = Session(
      id: sessionId,
      name: fallbackName ?? 'Recovered Chat',
      characterId: fallbackCharacterId ?? '',
      groupCharacterIds: fallbackGroupCharacterIds ?? const [],
      worldInfoIds: fallbackWorldInfoIds ?? const [],
      createdAt: now,
      updatedAt: now,
      messages: messages,
    );

    await _box.put(sessionId, newSession.toJson());
    await _box.flush();
    _upsertInState(newSession);
  }

  Future<void> deleteSession(String sessionId) async {
    await _box.delete(sessionId);
    state = state.where((s) => s.id != sessionId).toList();
  }

  void _upsertInState(Session session) {
    final index = state.indexWhere((s) => s.id == session.id);
    final newState = [...state];
    if (index == -1) {
      newState.add(session);
    } else {
      newState[index] = session;
    }
    newState.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = newState;
  }
}
