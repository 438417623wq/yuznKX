import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/presets/domain/models/preset.dart';

void main() {
  test('Preset should parse regex_scripts from extensions', () {
    final json = {
      'id': '123',
      'name': 'Test Preset',
      'extensions': {
        'regex_scripts': [
          {'scriptName': 'Test Regex 1', 'regex': 'foo', 'replacement': 'bar'}
        ]
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, 'Test Regex 1');
    expect(preset.regexScripts.first.findRegex, 'foo');
    expect(preset.regexScripts.first.replaceString, 'bar');
  });

  test('Preset should parse regexes from SPreset.RegexBinding', () {
    final json = {
      'id': '123',
      'name': 'Test Preset',
      'extensions': {
        'SPreset': {
          'RegexBinding': {
            'regexes': [
              {
                'scriptName': 'Test Regex 2',
                'regex': 'baz',
                'replacement': 'qux'
              }
            ]
          }
        }
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, 'Test Regex 2');
    expect(preset.regexScripts.first.findRegex, 'baz');
    expect(preset.regexScripts.first.replaceString, 'qux');
  });

  test('Preset should prefer root regex_scripts if present', () {
    final json = {
      'id': '123',
      'name': 'Test Preset',
      'regex_scripts': [
        {'scriptName': 'Root Regex', 'regex': 'root', 'replacement': 'root'}
      ],
      'extensions': {
        'regex_scripts': [
          {'scriptName': 'Ext Regex', 'regex': 'ext', 'replacement': 'ext'}
        ]
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, 'Root Regex');
  });

  test('Preset should parse aliases and clamp out-of-range sampling params',
      () {
    final json = {
      'name': 'Alias Preset',
      'temp': '1.8',
      'frequencyPenalty': '3.0',
      'presence_penalty': '-4',
      'topP': '1.2',
      'topK': '1200',
      'rep_penalty': '2.5',
      'max_tokens': '0',
    };

    final preset = Preset.fromJson(json);
    expect(preset.temperature, 1.8);
    expect(preset.frequencyPenalty, 2.0);
    expect(preset.presencePenalty, -2.0);
    expect(preset.topP, 1.0);
    expect(preset.topK, 1000);
    expect(preset.repetitionPenalty, 2.0);
    expect(preset.maxTokens, 1);
  });

  test('Preset should apply prompt_order enabled state and ordering', () {
    final json = {
      'name': 'Prompt Order Test',
      'prompts': [
        {
          'identifier': 'a',
          'name': 'A',
          'role': 'system',
          'content': 'A',
          'enabled': true
        },
        {
          'identifier': 'b',
          'name': 'B',
          'role': 'system',
          'content': 'B',
          'enabled': false
        },
      ],
      'prompt_order': [
        {
          'character_id': 0,
          'order': [
            {'identifier': 'b', 'enabled': true, 'injection_depth': 2},
            {'identifier': 'a', 'enabled': false, 'position': 'after'},
          ]
        }
      ]
    };

    final preset = Preset.fromJson(json);

    final promptIds = preset.prompts.map((prompt) => prompt.identifier).toList();
    final promptA = preset.prompts.firstWhere((prompt) => prompt.identifier == 'a');
    final promptB = preset.prompts.firstWhere((prompt) => prompt.identifier == 'b');

    expect(promptIds.indexOf('b'), lessThan(promptIds.indexOf('a')));
    expect(promptB.enabled, isTrue);
    expect(promptB.injectionDepth, 2);
    expect(promptA.enabled, isFalse);
    expect(promptA.injectionPosition, 1);
    expect(promptIds, containsAll(['main', 'chatHistory', 'dialogueExamples']));
  });

  test('Preset should parse prompt_manager prompts map and fallback name', () {
    final result = Preset.parseWithReport(
      {
        'prompt_manager': {
          'prompts': {
            'main': {
              'name': 'Main Prompt',
              'role': 'system',
              'content': 'Main Content'
            },
          }
        }
      },
      fallbackName: 'Fallback Name',
    );

    expect(result.preset.name, 'Fallback Name');
    expect(result.preset.prompts, isNotEmpty);
    final mainPrompt =
        result.preset.prompts.firstWhere((prompt) => prompt.identifier == 'main');
    expect(mainPrompt.content, 'Main Content');
    expect(
      result.preset.prompts.map((prompt) => prompt.identifier),
      containsAll(['chatHistory', 'dialogueExamples']),
    );
  });

  test('Preset parse report should include skipped malformed prompts', () {
    final result = Preset.parseWithReport(
      {
        'name': 'Malformed Prompt Preset',
        'prompts': ['invalid entry', 123],
      },
    );

    expect(result.preset.prompts, isNotEmpty);
    expect(
      result.preset.prompts.map((prompt) => prompt.identifier),
      containsAll(['main', 'chatHistory', 'dialogueExamples']),
    );
    expect(result.report.promptsSkipped, 2);
    expect(result.report.hasWarnings, isTrue);
  });

  test('Preset should parse continue/group prompt aliases', () {
    final preset = Preset.fromJson({
      'name': 'Alias Prompt Preset',
      'continue_nudge_prompt': 'CONTINUE_ALIAS',
      'group_nudge_prompt': 'GROUP_ALIAS',
      'new_group_chat_prompt': 'GROUP_NEW_CHAT_ALIAS',
    });

    expect(preset.continueNudge, 'CONTINUE_ALIAS');
    expect(preset.groupNudgePrompt, 'GROUP_ALIAS');
    expect(preset.newGroupChatPrompt, 'GROUP_NEW_CHAT_ALIAS');
  });

  test('Preset default prompt order should match tavern standalone flow', () {
    final preset = Preset.fromJson({
      'name': 'Default Order Preset',
    });

    final promptIds = preset.prompts.map((prompt) => prompt.identifier).toList();

    expect(
      promptIds.indexOf('worldInfoBefore'),
      lessThan(promptIds.indexOf('main')),
    );
    expect(
      promptIds.indexOf('main'),
      lessThan(promptIds.indexOf('worldInfoAfter')),
    );
    expect(
      promptIds.indexOf('worldInfoAfter'),
      lessThan(promptIds.indexOf('charDescription')),
    );
    expect(
      promptIds.indexOf('scenario'),
      lessThan(promptIds.indexOf('personaDescription')),
    );
    expect(
      promptIds,
      containsAll([
        'impersonate',
        'quietPrompt',
        'groupNudge',
        'bias',
        'summary',
        'authorsNote',
      ]),
    );
  });

  test('Character-specific prompt_order should override global order entries',
      () {
    final preset = Preset.fromJson({
      'name': 'Prompt Context Priority',
      'prompts': [
        {
          'identifier': 'main',
          'name': 'Main',
          'role': 'system',
          'content': 'Main prompt',
          'enabled': true,
        }
      ],
      'prompt_order': [
        {
          'character_id': 0,
          'order': [
            {
              'identifier': 'main',
              'enabled': false,
              'injection_depth': 1,
            }
          ]
        },
        {
          'character_id': 7,
          'order': [
            {
              'identifier': 'main',
              'enabled': true,
              'injection_depth': 3,
            }
          ]
        }
      ]
    });

    final mainPrompt =
        preset.prompts.firstWhere((prompt) => prompt.identifier == 'main');
    expect(mainPrompt.enabled, isTrue);
    expect(mainPrompt.injectionDepth, 3);
    expect(
      preset.prompts.map((prompt) => prompt.identifier),
      containsAll(['chatHistory', 'dialogueExamples']),
    );
  });
}
