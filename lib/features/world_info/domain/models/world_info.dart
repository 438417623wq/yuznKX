import 'package:uuid/uuid.dart';

class WorldInfo {
  final String id;
  final String name;
  final bool disabled;
  final List<WorldInfoEntry> entries;

  WorldInfo({
    required this.id,
    required this.name,
    this.disabled = false,
    required this.entries,
  });

  factory WorldInfo.fromJson(Map<String, dynamic> json) {
    List<WorldInfoEntry> entries = [];
    if (json['entries'] != null) {
      if (json['entries'] is Map) {
        final entriesMap = json['entries'] as Map;
        entriesMap.forEach((k, v) {
          entries.add(WorldInfoEntry.fromJson(Map<String, dynamic>.from(v)));
        });
      } else if (json['entries'] is List) {
        final entriesList = json['entries'] as List;
        for (var v in entriesList) {
          entries.add(WorldInfoEntry.fromJson(Map<String, dynamic>.from(v)));
        }
      }
    }

    final normalizedEntries = <WorldInfoEntry>[];
    final usedEntryUids = <int>{};
    var nextGeneratedUid = DateTime.now().microsecondsSinceEpoch;
    for (final entry in entries) {
      var effectiveUid = entry.uid;
      if (!usedEntryUids.add(effectiveUid)) {
        while (!usedEntryUids.add(nextGeneratedUid)) {
          nextGeneratedUid++;
        }
        effectiveUid = nextGeneratedUid;
      }

      normalizedEntries.add(
        effectiveUid == entry.uid ? entry : entry.copyWith(uid: effectiveUid),
      );
    }

    return WorldInfo(
      id: json['id'] != null ? json['id'].toString() : const Uuid().v4(),
      name: json['name'] ?? 'Imported World Info',
      disabled: json['disabled'] == true ||
          (json.containsKey('enabled') && json['enabled'] == false),
      entries: normalizedEntries,
    );
  }

  Map<String, dynamic> toJson() {
    // SillyTavern expects "entries" as a map "0":{}, "1":{}
    Map<String, dynamic> entriesMap = {};
    for (int i = 0; i < entries.length; i++) {
      entriesMap[i.toString()] = entries[i].toJson();
    }

    return {
      'id': id,
      'name': name,
      'disabled': disabled,
      'entries': entriesMap,
    };
  }

  WorldInfo copyWith({
    String? id,
    String? name,
    bool? disabled,
    List<WorldInfoEntry>? entries,
  }) {
    return WorldInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      disabled: disabled ?? this.disabled,
      entries: entries ?? this.entries,
    );
  }
}

class WorldInfoEntry {
  final int uid;
  final List<String> keys;
  final List<String> secondaryKeys;
  final String comment; // Name/Note
  final String content;
  final String role;
  final bool constant;
  final bool disable;
  final bool useRegex;
  final bool caseSensitive;
  final bool matchWholeWords;
  final bool selective; // Secondary-key filtering
  final int selectiveLogic; // 0=AND ANY, 1=AND ALL, 2=NOT ANY, 3=NOT ALL
  final int position; // Injection position
  final int depth;
  final int order;
  final int probability;
  final bool useProbability;
  final int sticky;
  final int cooldown;
  final int delay;
  final String group;
  final bool groupOverride;
  final int groupWeight;
  final bool excludeRecursion;
  final bool preventRecursion;
  final int delayUntilRecursion;
  final int? scanDepth;
  final bool matchPersonaDescription;
  final bool matchCharacterDescription;
  final bool matchCharacterPersonality;
  final bool matchCharacterDepthPrompt;
  final bool matchScenario;
  final bool matchCreatorNotes;
  final bool ignoreBudget;

  WorldInfoEntry({
    required this.uid,
    required this.keys,
    this.secondaryKeys = const [],
    this.comment = '',
    required this.content,
    this.role = 'system',
    this.constant = false,
    this.disable = false,
    this.useRegex = false,
    this.caseSensitive = false,
    this.matchWholeWords = true,
    this.selective = false,
    this.selectiveLogic = 0,
    this.position = 4,
    this.depth = 4,
    this.order = 0,
    this.probability = 100,
    this.useProbability = true,
    this.sticky = 0,
    this.cooldown = 0,
    this.delay = 0,
    this.group = '',
    this.groupOverride = false,
    this.groupWeight = 100,
    this.excludeRecursion = false,
    this.preventRecursion = false,
    this.delayUntilRecursion = 0,
    this.scanDepth,
    this.matchPersonaDescription = false,
    this.matchCharacterDescription = false,
    this.matchCharacterPersonality = false,
    this.matchCharacterDepthPrompt = false,
    this.matchScenario = false,
    this.matchCreatorNotes = false,
    this.ignoreBudget = false,
  });

  factory WorldInfoEntry.fromJson(Map<String, dynamic> json) {
    final extensions = json['extensions'] is Map
        ? Map<String, dynamic>.from(json['extensions'] as Map)
        : const <String, dynamic>{};

    bool parseBool(List<String> keys, {bool defaultValue = false}) {
      for (final key in keys) {
        final hasRoot = json.containsKey(key);
        final hasExt = extensions.containsKey(key);
        if (!hasRoot && !hasExt) {
          continue;
        }

        final value = hasRoot ? json[key] : extensions[key];
        if (value is bool) {
          return value;
        }
        if (value is num) {
          return value != 0;
        }
        if (value is String) {
          final normalized = value.trim().toLowerCase();
          if (normalized == 'true' || normalized == '1') {
            return true;
          }
          if (normalized == 'false' || normalized == '0') {
            return false;
          }
        }
      }
      return defaultValue;
    }

    int parseInt(List<String> keys, {int defaultValue = 0}) {
      for (final key in keys) {
        final hasRoot = json.containsKey(key);
        final hasExt = extensions.containsKey(key);
        if (!hasRoot && !hasExt) {
          continue;
        }

        final value = hasRoot ? json[key] : extensions[key];
        if (value is int) {
          return value;
        }
        if (value is num) {
          return value.toInt();
        }
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) {
            return parsed;
          }
        }
      }
      return defaultValue;
    }

    int? parseNullableInt(List<String> keys) {
      for (final key in keys) {
        final hasRoot = json.containsKey(key);
        final hasExt = extensions.containsKey(key);
        if (!hasRoot && !hasExt) {
          continue;
        }

        final value = hasRoot ? json[key] : extensions[key];
        if (value == null) {
          return null;
        }
        if (value is int) {
          return value;
        }
        if (value is num) {
          return value.toInt();
        }
        if (value is String) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            return null;
          }
          final parsed = int.tryParse(trimmed);
          if (parsed != null) {
            return parsed;
          }
        }
      }
      return null;
    }

    List<String> parseKeys(dynamic keyData) {
      if (keyData == null) return [];
      if (keyData is List) {
        return keyData
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
      if (keyData is String) {
        return keyData
            .split(',')
            .map((e) => e.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
      return [];
    }

    List<String> mergeKeys(List<String> primary, List<String> fallback) {
      final merged = <String>[];
      final seen = <String>{};

      void appendAll(Iterable<String> values) {
        for (final value in values) {
          final normalized = value.trim();
          if (normalized.isEmpty || !seen.add(normalized)) {
            continue;
          }
          merged.add(normalized);
        }
      }

      appendAll(primary);
      appendAll(fallback);
      return merged;
    }

    final primaryKeys = mergeKeys(
      parseKeys(json['keys'] ?? json['key']),
      parseKeys(extensions['triggers']),
    );
    final secondaryKeys = mergeKeys(
      parseKeys(json['keysecondary'] ?? json['secondary_keys']),
      parseKeys(extensions['secondary_keys']),
    );

    String parseRole(dynamic rawRole) {
      if (rawRole is num) {
        switch (rawRole.toInt()) {
          case 1:
            return 'user';
          case 2:
            return 'assistant';
          default:
            return 'system';
        }
      }

      final normalized = rawRole?.toString().trim().toLowerCase() ?? '';
      switch (normalized) {
        case '1':
        case 'user':
          return 'user';
        case '2':
        case 'assistant':
          return 'assistant';
        case '0':
        case 'system':
        default:
          return 'system';
      }
    }

    int parsePosition(dynamic pos) {
      if (pos is int) return pos;
      if (pos is String) {
        final normalized = pos.trim().toLowerCase().replaceAll(' ', '_');
        switch (normalized) {
          case 'before_char':
          case 'before_character':
          case 'character_top':
          case 'system_top':
          case 'global_note':
            return 0;
          case 'after_char':
          case 'after_character':
          case 'character_bottom':
            return 1;
          case 'before_an':
          case 'an_top':
          case 'author_note':
            return 2;
          case 'after_an':
          case 'an_bottom':
            return 3;
          case 'at_depth':
            return 4;
          case 'before_examples':
            return 5;
          case 'after_examples':
            return 6;
          case 'user_top':
            return 7;
          case 'assistant_top':
            return 8;
          default:
            final numeric = int.tryParse(normalized);
            if (numeric != null) {
              return numeric;
            }
            return 4;
        }
      }
      return 4;
    }

    return WorldInfoEntry(
      uid: parseInt(
        ['uid', 'id'],
        defaultValue: DateTime.now().microsecondsSinceEpoch,
      ),
      keys: primaryKeys,
      secondaryKeys: secondaryKeys,
      comment: json['comment'] ?? '',
      content: json['content'] ?? '',
      role: parseRole(json['role'] ?? extensions['role']),
      constant: parseBool(['constant']),
      disable: parseBool(['disable'], defaultValue: false) ||
          (json.containsKey('enabled') &&
              !parseBool(['enabled'], defaultValue: true)),
      useRegex: parseBool(['use_regex', 'useRegex']),
      caseSensitive: parseBool(['caseSensitive', 'case_sensitive']),
      matchWholeWords: parseBool(
        ['matchWholeWords', 'match_whole_words'],
        defaultValue: true,
      ),
      selective: parseBool(['selective']),
      selectiveLogic: parseInt(['selectiveLogic', 'selective_logic']),
      position: parsePosition(extensions['position'] ?? json['position']),
      depth: parseInt(['depth'], defaultValue: 4),
      order: parseInt(['order', 'insertion_order'], defaultValue: 0),
      probability: parseInt(['probability'], defaultValue: 100),
      useProbability: parseBool(
        ['useProbability', 'use_probability'],
        defaultValue: true,
      ),
      sticky: parseInt(['sticky'], defaultValue: 0),
      cooldown: parseInt(['cooldown'], defaultValue: 0),
      delay: parseInt(['delay'], defaultValue: 0),
      group: (json['group'] ?? extensions['group'] ?? '').toString(),
      groupOverride: parseBool([
        'groupOverride',
        'group_override',
        'preferential',
        'preferential_inclusion',
      ]),
      groupWeight: parseInt(['groupWeight', 'group_weight'], defaultValue: 100),
      excludeRecursion: parseBool(['excludeRecursion', 'exclude_recursion']),
      preventRecursion: parseBool(['preventRecursion', 'prevent_recursion']),
      delayUntilRecursion: parseInt(
        ['delayUntilRecursion', 'delay_until_recursion'],
        defaultValue: 0,
      ),
      scanDepth: parseNullableInt(['scanDepth', 'scan_depth']),
      matchPersonaDescription: parseBool(
        ['matchPersonaDescription', 'match_persona_description'],
      ),
      matchCharacterDescription: parseBool(
        ['matchCharacterDescription', 'match_character_description'],
      ),
      matchCharacterPersonality: parseBool(
        ['matchCharacterPersonality', 'match_character_personality'],
      ),
      matchCharacterDepthPrompt: parseBool(
        ['matchCharacterDepthPrompt', 'match_character_depth_prompt'],
      ),
      matchScenario: parseBool(['matchScenario', 'match_scenario']),
      matchCreatorNotes:
          parseBool(['matchCreatorNotes', 'match_creator_notes']),
      ignoreBudget: parseBool(['ignoreBudget', 'ignore_budget']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'key': keys,
      'keysecondary': secondaryKeys,
      'comment': comment,
      'content': content,
      'role': role,
      'constant': constant,
      'disable': disable,
      'use_regex': useRegex,
      'caseSensitive': caseSensitive,
      'matchWholeWords': matchWholeWords,
      'selective': selective,
      'selectiveLogic': selectiveLogic,
      'position': position,
      'depth': depth,
      'order': order,
      'probability': probability,
      'useProbability': useProbability,
      'sticky': sticky,
      'cooldown': cooldown,
      'delay': delay,
      'group': group,
      'groupOverride': groupOverride,
      'groupWeight': groupWeight,
      'excludeRecursion': excludeRecursion,
      'preventRecursion': preventRecursion,
      'delayUntilRecursion': delayUntilRecursion,
      'scanDepth': scanDepth,
      'matchPersonaDescription': matchPersonaDescription,
      'matchCharacterDescription': matchCharacterDescription,
      'matchCharacterPersonality': matchCharacterPersonality,
      'matchCharacterDepthPrompt': matchCharacterDepthPrompt,
      'matchScenario': matchScenario,
      'matchCreatorNotes': matchCreatorNotes,
      'ignoreBudget': ignoreBudget,
    };
  }

  WorldInfoEntry copyWith({
    int? uid,
    List<String>? keys,
    List<String>? secondaryKeys,
    String? comment,
    String? content,
    String? role,
    bool? constant,
    bool? disable,
    bool? useRegex,
    bool? caseSensitive,
    bool? matchWholeWords,
    bool? selective,
    int? selectiveLogic,
    int? position,
    int? depth,
    int? order,
    int? probability,
    bool? useProbability,
    int? sticky,
    int? cooldown,
    int? delay,
    String? group,
    bool? groupOverride,
    int? groupWeight,
    bool? excludeRecursion,
    bool? preventRecursion,
    int? delayUntilRecursion,
    int? scanDepth,
    bool clearScanDepth = false,
    bool? matchPersonaDescription,
    bool? matchCharacterDescription,
    bool? matchCharacterPersonality,
    bool? matchCharacterDepthPrompt,
    bool? matchScenario,
    bool? matchCreatorNotes,
    bool? ignoreBudget,
  }) {
    return WorldInfoEntry(
      uid: uid ?? this.uid,
      keys: keys ?? this.keys,
      secondaryKeys: secondaryKeys ?? this.secondaryKeys,
      comment: comment ?? this.comment,
      content: content ?? this.content,
      role: role ?? this.role,
      constant: constant ?? this.constant,
      disable: disable ?? this.disable,
      useRegex: useRegex ?? this.useRegex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      matchWholeWords: matchWholeWords ?? this.matchWholeWords,
      selective: selective ?? this.selective,
      selectiveLogic: selectiveLogic ?? this.selectiveLogic,
      position: position ?? this.position,
      depth: depth ?? this.depth,
      order: order ?? this.order,
      probability: probability ?? this.probability,
      useProbability: useProbability ?? this.useProbability,
      sticky: sticky ?? this.sticky,
      cooldown: cooldown ?? this.cooldown,
      delay: delay ?? this.delay,
      group: group ?? this.group,
      groupOverride: groupOverride ?? this.groupOverride,
      groupWeight: groupWeight ?? this.groupWeight,
      excludeRecursion: excludeRecursion ?? this.excludeRecursion,
      preventRecursion: preventRecursion ?? this.preventRecursion,
      delayUntilRecursion: delayUntilRecursion ?? this.delayUntilRecursion,
      scanDepth: clearScanDepth ? null : (scanDepth ?? this.scanDepth),
      matchPersonaDescription:
          matchPersonaDescription ?? this.matchPersonaDescription,
      matchCharacterDescription:
          matchCharacterDescription ?? this.matchCharacterDescription,
      matchCharacterPersonality:
          matchCharacterPersonality ?? this.matchCharacterPersonality,
      matchCharacterDepthPrompt:
          matchCharacterDepthPrompt ?? this.matchCharacterDepthPrompt,
      matchScenario: matchScenario ?? this.matchScenario,
      matchCreatorNotes: matchCreatorNotes ?? this.matchCreatorNotes,
      ignoreBudget: ignoreBudget ?? this.ignoreBudget,
    );
  }
}
