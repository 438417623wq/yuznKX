import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/chat/data/rp_hub_context_builder.dart';
import 'package:silly_tavern_flutter/features/chat/domain/models/chat_message.dart';

void main() {
  group('buildRpHubStyleContext', () {
    test(
        'assembles system, preset prehistory, user-top and assistant-top in order',
        () {
      final result = buildRpHubStyleContext(
        RpHubContextBuildInput(
          history: [
            ChatMessage(
              role: 'user',
              content: 'Who are you?',
              timestamp: DateTime(2026, 1, 1, 12),
            ),
            ChatMessage(
              role: 'assistant',
              content: 'I am the guide.',
              timestamp: DateTime(2026, 1, 1, 12, 1),
            ),
          ],
          topSystemPrompt: 'Base system',
          systemPrompts: const [
            RpHubContextPrompt(
              name: 'Style',
              role: 'system',
              content: 'Speak vividly.',
            ),
          ],
          preHistoryPrompts: const [
            RpHubContextPrompt(
              name: 'Bias',
              role: 'assistant',
              content: 'Stay warm and direct.',
            ),
          ],
          characterBlock: '[Character]\nName: Echo',
          userBlock: '[User Info]\nName: User',
          userTopWorldInfo: '[Hint]\nRemember the secret.',
          assistantTopWorldInfo: '[Goal]\nAdvance the scene.',
          isNewChat: false,
          generationType: RpHubContextGenerationType.normal,
        ),
      );

      expect(result.messages.length, 5);
      expect(result.messages[0].role, 'system');
      expect(result.messages[0].content, contains('Base system'));
      expect(result.messages[0].content, contains('Speak vividly.'));
      expect(result.messages[1].role, 'assistant');
      expect(result.messages[1].content, 'Stay warm and direct.');
      expect(result.messages[2].role, 'user');
      expect(result.messages[2].content,
          startsWith('[Hint]\nRemember the secret.'));
      expect(result.messages[3].role, 'assistant');
      expect(result.messages[3].content, 'I am the guide.');
      expect(result.messages[4].role, 'system');
      expect(result.messages[4].content,
          contains('[Instructions for next message]'));
      expect(
          result.messages[4].content, contains('[Goal]\nAdvance the scene.'));
    });

    test('inserts depth prompts and continue controls at expected positions',
        () {
      final result = buildRpHubStyleContext(
        RpHubContextBuildInput(
          history: [
            ChatMessage(
              role: 'user',
              content: 'Turn one',
              timestamp: DateTime(2026, 1, 1, 12),
            ),
            ChatMessage(
              role: 'assistant',
              content: 'Reply one',
              timestamp: DateTime(2026, 1, 1, 12, 1),
            ),
            ChatMessage(
              role: 'user',
              content: 'Turn two',
              timestamp: DateTime(2026, 1, 1, 12, 2),
            ),
          ],
          topSystemPrompt: 'Base system',
          depthInjections: const [
            RpHubContextDepthInjection(
              title: 'Author Note',
              role: 'system',
              content: 'Protect continuity.',
              depth: 1,
              order: 1,
              sourceKey: 'authors_note',
              sourceLabel: 'Author Note',
            ),
          ],
          continuedMessage: ChatMessage(
            role: 'assistant',
            content: 'Partial reply...',
            timestamp: DateTime(2026, 1, 1, 12, 3),
          ),
          continueNudge: 'Continue naturally.',
          generationType: RpHubContextGenerationType.continueMode,
        ),
      );

      expect(result.messages.map((m) => m.content).toList(), [
        'Base system',
        'Turn one',
        'Reply one',
        'Protect continuity.',
        'Turn two',
        'Partial reply...',
        'Continue naturally.',
      ]);
      expect(result.messages[3].role, 'system');
      expect(result.messages[5].role, 'assistant');
      expect(result.messages[6].role, 'system');
    });
  });
}
