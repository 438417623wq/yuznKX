import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/chat/data/chat_service.dart';
import 'package:silly_tavern_flutter/features/chat/domain/models/chat_message.dart';

void main() {
  test('serializeMessagesForApi strips local-only fields and lifts name', () {
    final messages = [
      ChatMessage(
        role: 'system',
        content: 'System prompt',
        timestamp: DateTime(2026, 1, 1, 12),
        swipes: const ['System prompt'],
        currentIndex: 0,
        metadata: const {
          'name': 'Narrator',
          'debug': true,
        },
      ),
      ChatMessage(
        role: 'assistant',
        content: 'Hello there',
        timestamp: DateTime(2026, 1, 1, 12, 1),
        metadata: const {
          'name': 'Echo',
          'characterId': 'char-1',
        },
      ),
    ];

    expect(ChatService.serializeMessagesForApi(messages), [
      {
        'role': 'system',
        'content': 'System prompt',
        'name': 'Narrator',
      },
      {
        'role': 'assistant',
        'content': 'Hello there',
        'name': 'Echo',
      },
    ]);
  });
}
