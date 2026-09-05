import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/chat/data/world_info_runtime.dart';
import 'package:silly_tavern_flutter/features/world_info/data/world_info_provider.dart';
import 'package:silly_tavern_flutter/features/world_info/domain/models/world_info.dart';

void main() {
  group('World info runtime logic', () {
    test('keeps auxiliary scan sources active when scan depth is zero', () {
      final source = buildWorldInfoScanSource(
        requestedDepth: 0,
        historyBuffer: const ['recent chat line'],
        injectionTexts: const ['authors note'],
        recursionBuffer: const ['recursive lore'],
        includeRecursionBuffer: true,
      );

      expect(source, contains('authors note'));
      expect(source, contains('recursive lore'));
      expect(source, isNot(contains('recent chat line')));
    });

    test('prioritizes constant entries before normal triggered entries', () {
      final constantEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 1,
          keys: const [],
          content: 'constant',
          constant: true,
          order: 0,
        ),
        sourceKind: 'global',
        sourceOrder: 1,
      );
      final normalEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 2,
          keys: const ['hero'],
          content: 'normal',
          order: 999,
        ),
        sourceKind: 'global',
        sourceOrder: 0,
      );

      final ordered = [normalEntry, constantEntry]
        ..sort((a, b) => compareWorldInfoActivationOrder(
              a,
              b,
              WorldInfoCharacterStrategy.characterFirst,
            ));

      expect(ordered.first.entry.uid, 1);
    });

    test('treats character and global lore as one pool in evenly mode', () {
      final sessionEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 1,
          keys: const ['session'],
          content: 'session',
          position: 4,
          depth: 4,
          order: 300,
        ),
        sourceKind: 'session',
        sourceOrder: 0,
      );
      final globalEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 2,
          keys: const ['global'],
          content: 'global',
          position: 4,
          depth: 4,
          order: 10,
        ),
        sourceKind: 'global',
        sourceOrder: 1,
      );
      final characterEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 3,
          keys: const ['character'],
          content: 'character',
          position: 4,
          depth: 4,
          order: 200,
        ),
        sourceKind: 'character',
        sourceOrder: 0,
      );

      final ordered = [characterEntry, globalEntry, sessionEntry]
        ..sort((a, b) => compareWorldInfoPromptOrder(
              a,
              b,
              WorldInfoCharacterStrategy.evenly,
            ));

      expect(
        ordered.map((item) => item.entry.uid).toList(),
        [1, 2, 3],
      );
    });

    test('puts character lore before global lore in character-first mode', () {
      final globalEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 2,
          keys: const ['global'],
          content: 'global',
          position: 4,
          depth: 4,
          order: 10,
        ),
        sourceKind: 'global',
        sourceOrder: 0,
      );
      final characterEntry = WorldInfoOrderingEntry(
        entry: WorldInfoEntry(
          uid: 3,
          keys: const ['character'],
          content: 'character',
          position: 4,
          depth: 4,
          order: 200,
        ),
        sourceKind: 'character',
        sourceOrder: 0,
      );

      final ordered = [globalEntry, characterEntry]
        ..sort((a, b) => compareWorldInfoPromptOrder(
              a,
              b,
              WorldInfoCharacterStrategy.characterFirst,
            ));

      expect(
        ordered.map((item) => item.entry.uid).toList(),
        [3, 2],
      );
    });
  });
}
