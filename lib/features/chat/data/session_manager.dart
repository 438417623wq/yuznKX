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
          // 当前会话已经是该角色的一条合法会话 —— 到此为止，不要做任何「纠正」。
          //
          // 历史实现会在这里调 ensureSessionForCharacter()，而后者返回的是该角色
          // 「最近更新」的那条会话。于是当用户手动切到一条较早的对话时，
          // 最新会话 != 当前会话，下面就会 setActive(...) 把用户弹回最新那条，
          // 表现为「会话列表点了没反应 / 一闪就跳回去」。
          //
          // 用户显式选定的会话必须被尊重：只要它合法且属于当前角色，就直接返回。
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

  /// 保证某个角色至少有一条会话，并返回「切到该角色时应当打开的那条」。
  ///
  /// 语义边界（重要）：本方法只在**切换角色**或**当前没有可用会话**时调用。
  /// 它返回该角色最近更新的会话 —— 这是「切角色」场景下的合理默认值，
  /// 但**绝不能**用它覆盖用户已显式选定的会话，否则会话列表会点不动。
  /// 该约束由 [_reconcile] 保证。
  Future<Session?> ensureSessionForCharacter(String characterId) async {
    final sessions = _ref.read(sessionProvider);
    final character = _findCharacter(characterId);
    final shouldKeepSessionWorldInfo = character?.isGroup ?? false;

    final characterSessions =
        sessions.where((s) => s.characterId == characterId).toList();
    if (characterSessions.isNotEmpty) {
      // sessionProvider 已按 updatedAt 降序排列，first 即「最近在聊的那条」。
      final existing = characterSessions.first;
      // 会话级世界书按原样保留（仅做去空 + 去重），不再对单角色强制清空。
      // 历史实现对非群聊角色一律置为 const []，等于让「会话级世界书」在
      // 单角色路径上彻底失效，而且会静默抹掉会话上已有的绑定数据。
      final sanitizedWorldInfoIds = _normalizeWorldInfoIds(existing.worldInfoIds);
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
          '新对话 (New Chat)',
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
