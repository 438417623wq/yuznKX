import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/world_info/domain/models/world_info.dart';

void main() {
  group('WorldInfoEntry position parsing', () {
    test('parses before_examples and after_examples into dedicated slots', () {
      final beforeExamples = WorldInfoEntry.fromJson({
        'uid': 1,
        'key': ['alpha'],
        'content': 'before examples',
        'position': 'before_examples',
      });
      final afterExamples = WorldInfoEntry.fromJson({
        'uid': 2,
        'key': ['beta'],
        'content': 'after examples',
        'position': 'after_examples',
      });

      expect(beforeExamples.position, 5);
      expect(afterExamples.position, 6);
    });

    test('keeps at_depth alias compatible with existing imports', () {
      final atDepth = WorldInfoEntry.fromJson({
        'uid': 3,
        'key': ['gamma'],
        'content': 'depth prompt',
        'position': 'at_depth',
      });

      expect(atDepth.position, 4);
    });

    test('defaults missing position to at_depth like RP-Hub', () {
      final entry = WorldInfoEntry.fromJson({
        'uid': 33,
        'key': ['gamma'],
        'content': 'default depth prompt',
      });

      expect(entry.position, 4);
    });

    test('parses user_top and assistant_top into dedicated slots', () {
      final userTop = WorldInfoEntry.fromJson({
        'uid': 31,
        'key': ['gamma'],
        'content': 'user top prompt',
        'position': 'user_top',
      });
      final assistantTop = WorldInfoEntry.fromJson({
        'uid': 32,
        'key': ['delta'],
        'content': 'assistant top prompt',
        'position': 'assistant_top',
      });

      expect(userTop.position, 7);
      expect(assistantTop.position, 8);
    });

    test('parses SillyTavern snake_case fields and depth role', () {
      final entry = WorldInfoEntry.fromJson({
        'uid': 4,
        'key': ['delta'],
        'keysecondary': ['omega'],
        'content': 'entry content',
        'position': 'at_depth',
        'case_sensitive': true,
        'match_whole_words': true,
        'selective': true,
        'selective_logic': 3,
        'use_regex': true,
        'role': 2,
      });

      expect(entry.caseSensitive, isTrue);
      expect(entry.matchWholeWords, isTrue);
      expect(entry.selective, isTrue);
      expect(entry.selectiveLogic, 3);
      expect(entry.useRegex, isTrue);
      expect(entry.role, 'assistant');
    });

    test('parses character_book extensions fields', () {
      final entry = WorldInfoEntry.fromJson({
        'id': 9,
        'keys': ['alpha'],
        'secondary_keys': ['beta'],
        'content': 'entry content',
        'enabled': true,
        'insertion_order': 321,
        'extensions': {
          'position': 'at_depth',
          'depth': 7,
          'probability': 55,
          'useProbability': false,
          'group': 'grp',
          'group_override': true,
          'group_weight': 777,
          'exclude_recursion': true,
          'prevent_recursion': true,
          'delay_until_recursion': 2,
          'scan_depth': 3,
          'match_persona_description': true,
          'match_character_description': true,
          'match_character_personality': true,
          'match_character_depth_prompt': true,
          'match_scenario': true,
          'match_creator_notes': true,
          'ignore_budget': true,
        },
      });

      expect(entry.position, 4);
      expect(entry.depth, 7);
      expect(entry.order, 321);
      expect(entry.probability, 55);
      expect(entry.useProbability, isFalse);
      expect(entry.group, 'grp');
      expect(entry.groupOverride, isTrue);
      expect(entry.groupWeight, 777);
      expect(entry.excludeRecursion, isTrue);
      expect(entry.preventRecursion, isTrue);
      expect(entry.delayUntilRecursion, 2);
      expect(entry.scanDepth, 3);
      expect(entry.matchPersonaDescription, isTrue);
      expect(entry.matchCharacterDescription, isTrue);
      expect(entry.matchCharacterPersonality, isTrue);
      expect(entry.matchCharacterDepthPrompt, isTrue);
      expect(entry.matchScenario, isTrue);
      expect(entry.matchCreatorNotes, isTrue);
      expect(entry.ignoreBudget, isTrue);
    });

    test('uses RP-Hub defaults for whole-word and order semantics', () {
      final entry = WorldInfoEntry.fromJson({
        'id': 91,
        'keys': ['alpha'],
        'content': 'entry content',
      });

      expect(entry.matchWholeWords, isTrue);
      expect(entry.order, 0);
    });

    test('parses RP-Hub preferential and use_probability aliases', () {
      final entry = WorldInfoEntry.fromJson({
        'id': 92,
        'keys': ['alpha'],
        'content': 'entry content',
        'preferential': true,
        'use_probability': false,
      });

      expect(entry.groupOverride, isTrue);
      expect(entry.useProbability, isFalse);
    });

    test('uses character_book id as uid and falls back to extension triggers',
        () {
      final entry = WorldInfoEntry.fromJson({
        'id': 42,
        'content': 'entry content',
        'extensions': {
          'triggers': ['alpha', 'beta'],
        },
      });

      expect(entry.uid, 42);
      expect(entry.keys, ['alpha', 'beta']);
    });

    test('preserves distinct character_book entry ids across imports', () {
      final worldInfo = WorldInfo.fromJson({
        'name': 'Character Book',
        'entries': [
          {
            'id': 101,
            'content': 'entry A',
            'constant': true,
            'enabled': true,
          },
          {
            'id': 102,
            'content': 'entry B',
            'constant': true,
            'enabled': true,
          },
        ],
      });

      expect(worldInfo.entries.map((entry) => entry.uid).toList(), [101, 102]);
      expect(worldInfo.entries.map((entry) => entry.disable).toList(),
          [false, false]);
    });

    test('repairs duplicate entry uids when loading existing world info data',
        () {
      final worldInfo = WorldInfo.fromJson({
        'name': 'Legacy Character Book',
        'entries': [
          {
            'uid': 7,
            'content': 'entry A',
          },
          {
            'uid': 7,
            'content': 'entry B',
          },
        ],
      });

      final uids = worldInfo.entries.map((entry) => entry.uid).toList();
      expect(uids.first, 7);
      expect(uids.last, isNot(7));
      expect(uids.toSet().length, 2);
    });
  });
}
