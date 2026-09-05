import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../character/data/character_provider.dart';
import '../../character/domain/models/character.dart';
import '../domain/models/session.dart';
import 'session_provider.dart';

final sessionManagerProvider = Provider((ref) {
  return SessionManager(ref);
});

class SessionManager {
  final Ref _ref;
  bool _isReconciling = false;

  SessionManager(this._ref) {
    _init();
  }

  void _init() {
    _reconcile();

    _ref.listen<String?>(activeCharacterIdProvider, (previous, next) {
      if (previous != next) {
        _reconcile();
      }
    });

    _ref.listen<String?>(activeSessionIdProvider, (previous, next) {
      if (previous != next) {
        _reconcile();
      }
    });

    _ref.listen<List<Session>>(sessionProvider, (previous, next) {
      _reconcile();
    });

    _ref.listen<List<Character>>(characterListProvider, (previous, next) {
      _reconcile();
    });
  }

  Future<void> _reconcile() async {
    if (_isReconciling) {
      return;
    }
    _isReconciling = true;

    try {
      final sessions = _ref.read(sessionProvider);
      final activeCharacterId = _ref.read(activeCharacterIdProvider);
      final activeSessionId = _ref.read(activeSessionIdProvider);
      final activeSessionNotifier = _ref.read(activeSessionIdProvider.notifier);

      if (activeCharacterId == null || activeCharacterId.isEmpty) {
        if (activeSessionId != null &&
            !sessions.any((s) => s.id == activeSessionId)) {
          await activeSessionNotifier.setActive(null);
        }
        return;
      }

      if (activeSessionId != null) {
        final current = _findSessionById(sessions, activeSessionId);
        if (current != null && current.characterId == activeCharacterId) {
          final ensuredSession =
              await ensureSessionForCharacter(activeCharacterId);
          if (ensuredSession != null && ensuredSession.id != activeSessionId) {
            await activeSessionNotifier.setActive(ensuredSession.id);
          }
          return;
        }
      }

      final ensuredSession = await ensureSessionForCharacter(activeCharacterId);
      if (ensuredSession != null && ensuredSession.id != activeSessionId) {
        await activeSessionNotifier.setActive(ensuredSession.id);
      }
    } finally {
      _isReconciling = false;
    }
  }

  Future<Session?> ensureSessionForCharacter(String characterId) async {
    final sessions = _ref.read(sessionProvider);
    final character = _findCharacter(characterId);
    final shouldKeepSessionWorldInfo = character?.isGroup ?? false;

    final characterSessions =
        sessions.where((s) => s.characterId == characterId).toList();
    if (characterSessions.isNotEmpty) {
      final existing = characterSessions.first;
      final sanitizedWorldInfoIds = shouldKeepSessionWorldInfo
          ? _normalizeWorldInfoIds(existing.worldInfoIds)
          : const <String>[];
      if (!_sameStringSet(existing.worldInfoIds, sanitizedWorldInfoIds)) {
        final updated = existing.copyWith(worldInfoIds: sanitizedWorldInfoIds);
        await _ref.read(sessionProvider.notifier).updateSession(updated);
        return updated;
      }
      return existing;
    }

    Session? claimable;
    for (final session in sessions) {
      if (session.characterId.isEmpty && session.messages.isNotEmpty) {
        claimable = session;
        break;
      }
    }
    if (claimable != null) {
      final updated = claimable.copyWith(
        characterId: characterId,
        worldInfoIds: shouldKeepSessionWorldInfo
            ? _normalizeWorldInfoIds(claimable.worldInfoIds)
            : const <String>[],
      );
      await _ref.read(sessionProvider.notifier).updateSession(updated);
      return updated;
    }

    final created = await _ref.read(sessionProvider.notifier).createSession(
          'New Chat',
          characterId: characterId,
          worldInfoIds: shouldKeepSessionWorldInfo
              ? character?.worldInfoIds ?? const []
              : const [],
        );
    return created;
  }

  List<String> _normalizeWorldInfoIds(List<String> ids) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }

  bool _sameStringSet(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.toSet().containsAll(b) && b.toSet().containsAll(a);
  }

  Session? _findSessionById(List<Session> sessions, String id) {
    for (final session in sessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  Character? _findCharacter(String id) {
    final characters = _ref.read(characterListProvider);
    for (final c in characters) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }
}
