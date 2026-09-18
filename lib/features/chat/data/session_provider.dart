import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../memory/data/memory_provider.dart';
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

  /// 删除一条会话，并**级联清理**它独占的所有数据。
  ///
  /// 清理范围：
  /// - `sessions` box 本身
  /// - 会话级记忆（`memory_tables_v3` / `memory_plugin_settings_v3`）
  /// - 会话级变量（`settings` box 的 `chat_variables[sessionId]`）
  ///
  /// 不清理的后果不只是留下孤儿数据：sessionId 一旦被复用（导入备份、
  /// 恢复数据等场景），旧记忆会串到新会话上。
  ///
  /// 删除「当前活跃会话」后不需要在这里做切换 —— `SessionManager._reconcile`
  /// 监听了 `sessionProvider`，会自动切到该角色的下一条会话（没有则新建一条）。
  Future<void> deleteSession(String sessionId) async {
    await _box.delete(sessionId);
    state = state.where((s) => s.id != sessionId).toList();

    // 会话级记忆
    await purgeSessionScopedMemory(sessionId);

    // 会话级变量
    try {
      final settings = await Hive.openBox('settings');
      final rawChatVariables = settings.get('chat_variables');
      if (rawChatVariables is Map && rawChatVariables.containsKey(sessionId)) {
        final next = Map<String, dynamic>.from(rawChatVariables)
          ..remove(sessionId);
        await settings.put('chat_variables', next);
      }
    } catch (error) {
      print('Failed to clean up chat variables for $sessionId: $error');
    }
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
