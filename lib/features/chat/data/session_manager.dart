import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../character/data/character_provider.dart';
import 'session_provider.dart';
import 'chat_provider.dart';
import '../domain/models/session.dart';

final sessionManagerProvider = Provider((ref) {
  return SessionManager(ref);
});

class SessionManager {
  final Ref _ref;

  SessionManager(this._ref) {
    _init();
  }

  void _init() {
    // Listen for character changes to switch sessions
    _ref.listen<String?>(activeCharacterIdProvider, (previous, next) async {
      if (previous != next && next != null) {
        // We do NOT stop generation here. Background generation is desired.
        
        final sessions = _ref.read(sessionProvider);
        // Sort order in sessionProvider is already by updatedAt desc, but let's be safe if we need specific logic
        final charSessions = sessions.where((s) => s.characterId == next).toList();

        if (charSessions.isNotEmpty) {
          _ref.read(activeSessionIdProvider.notifier).setActive(charSessions.first.id);
        } else {
          // Attempt to claim an unbound session (legacy data migration)
          Session? unboundSession;
          try {
            unboundSession = sessions.firstWhere((s) => s.characterId.isEmpty);
          } catch (_) {}

          if (unboundSession != null && unboundSession.messages.isNotEmpty) {
             // Claim it!
             final updatedSession = unboundSession.copyWith(characterId: next);
             await _ref.read(sessionProvider.notifier).updateSession(updatedSession);
             _ref.read(activeSessionIdProvider.notifier).setActive(updatedSession.id);
          } else {
             // Create new session
             await _ref.read(sessionProvider.notifier).createSession('New Chat', characterId: next);
             // Get the newly created session (it should be first)
             final updatedSessions = _ref.read(sessionProvider);
             if (updatedSessions.isNotEmpty) {
                _ref.read(activeSessionIdProvider.notifier).setActive(updatedSessions.first.id);
             }
          }
        }
      }
    });
  }
}
