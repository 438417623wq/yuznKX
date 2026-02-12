import 'package:uuid/uuid.dart';

class WorldInfo {
  final String id;
  final String name;
  final List<WorldInfoEntry> entries;

  WorldInfo({
    required this.id,
    required this.name,
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

    return WorldInfo(
      id: json['id'] != null ? json['id'].toString() : const Uuid().v4(),
      name: json['name'] ?? 'Imported World Info',
      entries: entries,
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
      'entries': entriesMap,
    };
  }
}

class WorldInfoEntry {
  final int uid;
  final List<String> keys;
  final List<String> secondaryKeys;
  final String comment; // Name/Note
  final String content;
  final bool constant;
  final bool disable;
  final bool useRegex;
  final bool caseSensitive;
  final bool matchWholeWords;
  final bool selective; // Logic combination
  final int selectiveLogic; // 0=AND, 1=OR...
  final int position; // Injection position
  final int depth;
  final int order;
  final int probability;
  final int sticky;
  final int cooldown;
  final int delay;
  final String group;

  WorldInfoEntry({
    required this.uid,
    required this.keys,
    this.secondaryKeys = const [],
    this.comment = '',
    required this.content,
    this.constant = false,
    this.disable = false,
    this.useRegex = false,
    this.caseSensitive = false,
    this.matchWholeWords = false,
    this.selective = false,
    this.selectiveLogic = 0,
    this.position = 0,
    this.depth = 4,
    this.order = 100,
    this.probability = 100,
    this.sticky = 0,
    this.cooldown = 0,
    this.delay = 0,
    this.group = '',
  });

  factory WorldInfoEntry.fromJson(Map<String, dynamic> json) {
    List<String> parseKeys(dynamic keyData) {
      if (keyData == null) return [];
      if (keyData is List) return List<String>.from(keyData);
      if (keyData is String) return keyData.split(',').map((e) => e.trim()).toList();
      return [];
    }

    int parsePosition(dynamic pos) {
      if (pos is int) return pos;
      if (pos is String) {
        switch (pos) {
          case 'before_char': return 0;
          case 'after_char': return 1;
          case 'before_an': return 2;
          case 'after_an': return 3;
          default: return 0;
        }
      }
      return 0;
    }

    return WorldInfoEntry(
      uid: json['uid'] ?? DateTime.now().millisecondsSinceEpoch,
      keys: parseKeys(json['keys'] ?? json['key']),
      secondaryKeys: parseKeys(json['keysecondary'] ?? json['secondary_keys']),
      comment: json['comment'] ?? '',
      content: json['content'] ?? '',
      constant: json['constant'] ?? false,
      disable: json['disable'] ?? false,
      useRegex: json['use_regex'] ?? false,
      caseSensitive: json['caseSensitive'] ?? false,
      matchWholeWords: json['matchWholeWords'] ?? false,
      selective: json['selective'] ?? false,
      selectiveLogic: json['selectiveLogic'] ?? 0,
      position: parsePosition(json['position']),
      depth: json['depth'] ?? 4,
      order: json['order'] ?? 100,
      probability: json['probability'] ?? 100,
      sticky: json['sticky'] ?? 0,
      cooldown: json['cooldown'] ?? 0,
      delay: json['delay'] ?? 0,
      group: json['group'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'key': keys,
      'keysecondary': secondaryKeys,
      'comment': comment,
      'content': content,
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
      'sticky': sticky,
      'cooldown': cooldown,
      'delay': delay,
      'group': group,
    };
  }
}
