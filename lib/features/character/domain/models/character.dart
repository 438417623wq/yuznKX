import 'package:uuid/uuid.dart';

class Character {
  final String id;
  final String name;
  final String description;
  final String avatarPath;
  final List<String> tags;
  final String creator;
  final String version;
  
  // Personality
  final String systemInstruction;
  final String scenario;
  final String authorsNote;
  final int authorsNoteDepth;
  final int authorsNoteFrequency;

  // Greetings
  final String firstMessage;
  final List<String> alternateGreetings;

  // Advanced
  final String? boundModelId; // For specific API config binding if needed
  final String? preferredModelName; // e.g. "gpt-4", "claude-3"
  final List<String> worldInfoIds;
  final List<String> regexScriptIds;

  Character({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarPath = '',
    this.tags = const [],
    this.creator = '',
    this.version = '1.0',
    this.systemInstruction = '',
    this.scenario = '',
    this.authorsNote = '',
    this.authorsNoteDepth = 4,
    this.authorsNoteFrequency = 0,
    this.firstMessage = '',
    this.alternateGreetings = const [],
    this.boundModelId,
    this.preferredModelName,
    this.worldInfoIds = const [],
    this.regexScriptIds = const [],
  });

  Character copyWith({
    String? name,
    String? description,
    String? avatarPath,
    List<String>? tags,
    String? creator,
    String? version,
    String? systemInstruction,
    String? scenario,
    String? authorsNote,
    int? authorsNoteDepth,
    int? authorsNoteFrequency,
    String? firstMessage,
    List<String>? alternateGreetings,
    String? boundModelId,
    String? preferredModelName,
    List<String>? worldInfoIds,
    List<String>? regexScriptIds,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarPath: avatarPath ?? this.avatarPath,
      tags: tags ?? this.tags,
      creator: creator ?? this.creator,
      version: version ?? this.version,
      systemInstruction: systemInstruction ?? this.systemInstruction,
      scenario: scenario ?? this.scenario,
      authorsNote: authorsNote ?? this.authorsNote,
      authorsNoteDepth: authorsNoteDepth ?? this.authorsNoteDepth,
      authorsNoteFrequency: authorsNoteFrequency ?? this.authorsNoteFrequency,
      firstMessage: firstMessage ?? this.firstMessage,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      boundModelId: boundModelId ?? this.boundModelId,
      preferredModelName: preferredModelName ?? this.preferredModelName,
      worldInfoIds: worldInfoIds ?? this.worldInfoIds,
      regexScriptIds: regexScriptIds ?? this.regexScriptIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatarPath': avatarPath,
      'tags': tags,
      'creator': creator,
      'version': version,
      'systemInstruction': systemInstruction,
      'scenario': scenario,
      'authorsNote': authorsNote,
      'authorsNoteDepth': authorsNoteDepth,
      'authorsNoteFrequency': authorsNoteFrequency,
      'firstMessage': firstMessage,
      'alternateGreetings': alternateGreetings,
      'boundModelId': boundModelId,
      'preferredModelName': preferredModelName,
      'worldInfoIds': worldInfoIds,
      'regexScriptIds': regexScriptIds,
    };
  }

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'New Character',
      description: json['description'] ?? '',
      avatarPath: json['avatarPath'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      creator: json['creator'] ?? '',
      version: json['version'] ?? '1.0',
      systemInstruction: json['systemInstruction'] ?? '',
      scenario: json['scenario'] ?? '',
      authorsNote: json['authorsNote'] ?? '',
      authorsNoteDepth: json['authorsNoteDepth'] ?? 4,
      authorsNoteFrequency: json['authorsNoteFrequency'] ?? 0,
      firstMessage: json['firstMessage'] ?? '',
      alternateGreetings: List<String>.from(json['alternateGreetings'] ?? []),
      boundModelId: json['boundModelId'],
      preferredModelName: json['preferredModelName'],
      worldInfoIds: List<String>.from(json['worldInfoIds'] ?? []),
      regexScriptIds: List<String>.from(json['regexScriptIds'] ?? []),
    );
  }
}
