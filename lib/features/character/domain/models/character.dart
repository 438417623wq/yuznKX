import 'package:uuid/uuid.dart';

class Character {
  final String id;
  final String name;
  final String description;
  final String personality;
  final String systemPrompt;
  final String creatorNotes;
  final String avatarPath;
  final List<String> tags;
  final String creator;
  final String version;

  // Legacy mirror kept for older UI/data paths.
  final String systemInstruction;
  final String scenario;
  final String authorsNote;
  final int authorsNoteDepth;
  final int authorsNoteFrequency;

  // Greetings
  final String firstMessage;
  final List<String> alternateGreetings;
  final String exampleDialogue;

  // Advanced
  final String? boundModelId; // For specific API config binding if needed
  final String? preferredModelName; // e.g. "gpt-4", "claude-3"
  final String? characterBookId;
  final List<String> worldInfoIds;
  final List<String> regexScriptIds;
  final bool isGroup;
  final List<String> groupMemberIds;

  // Raw character-card data for lossless roundtrip (unknown fields preserved).
  final String cardSpec;
  final String cardSpecVersion;
  final Map<String, dynamic> rawCardData;
  final Map<String, dynamic> rawExtensions;
  final Map<String, dynamic>? rawCharacterBook;

  Character({
    required this.id,
    required this.name,
    this.description = '',
    this.personality = '',
    this.systemPrompt = '',
    this.creatorNotes = '',
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
    this.exampleDialogue = '',
    this.boundModelId,
    this.preferredModelName,
    this.characterBookId,
    this.worldInfoIds = const [],
    this.regexScriptIds = const [],
    this.isGroup = false,
    this.groupMemberIds = const [],
    this.cardSpec = 'chara_card_v2',
    this.cardSpecVersion = '2.0',
    this.rawCardData = const {},
    this.rawExtensions = const {},
    this.rawCharacterBook,
  });

  Character copyWith({
    String? name,
    String? description,
    String? personality,
    String? systemPrompt,
    String? creatorNotes,
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
    String? exampleDialogue,
    String? boundModelId,
    String? preferredModelName,
    String? characterBookId,
    List<String>? worldInfoIds,
    List<String>? regexScriptIds,
    bool? isGroup,
    List<String>? groupMemberIds,
    String? cardSpec,
    String? cardSpecVersion,
    Map<String, dynamic>? rawCardData,
    Map<String, dynamic>? rawExtensions,
    Map<String, dynamic>? rawCharacterBook,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      creatorNotes: creatorNotes ?? this.creatorNotes,
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
      exampleDialogue: exampleDialogue ?? this.exampleDialogue,
      boundModelId: boundModelId ?? this.boundModelId,
      preferredModelName: preferredModelName ?? this.preferredModelName,
      characterBookId: characterBookId ?? this.characterBookId,
      worldInfoIds: worldInfoIds ?? this.worldInfoIds,
      regexScriptIds: regexScriptIds ?? this.regexScriptIds,
      isGroup: isGroup ?? this.isGroup,
      groupMemberIds: groupMemberIds ?? this.groupMemberIds,
      cardSpec: cardSpec ?? this.cardSpec,
      cardSpecVersion: cardSpecVersion ?? this.cardSpecVersion,
      rawCardData: rawCardData ?? this.rawCardData,
      rawExtensions: rawExtensions ?? this.rawExtensions,
      rawCharacterBook: rawCharacterBook ?? this.rawCharacterBook,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'personality': personality,
      'systemPrompt': systemPrompt,
      'creatorNotes': creatorNotes,
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
      'exampleDialogue': exampleDialogue,
      'boundModelId': boundModelId,
      'preferredModelName': preferredModelName,
      'characterBookId': characterBookId,
      'worldInfoIds': worldInfoIds,
      'regexScriptIds': regexScriptIds,
      'isGroup': isGroup,
      'groupMemberIds': groupMemberIds,
      'cardSpec': cardSpec,
      'cardSpecVersion': cardSpecVersion,
      'rawCardData': rawCardData,
      'rawExtensions': rawExtensions,
      'rawCharacterBook': rawCharacterBook,
    };
  }

  static Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  factory Character.fromJson(Map<String, dynamic> json) {
    final personality = json['personality']?.toString() ??
        json['systemInstruction']?.toString() ??
        '';
    final systemPrompt = json['systemPrompt']?.toString() ??
        json['system_prompt']?.toString() ??
        '';
    final creatorNotes = json['creatorNotes']?.toString() ??
        json['creator_notes']?.toString() ??
        '';
    final rawCharacterBook = _safeMap(json['rawCharacterBook']);
    final characterBookId = json['characterBookId']?.toString().trim() ?? '';

    return Character(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'New Character',
      description: json['description'] ?? '',
      personality: personality,
      systemPrompt: systemPrompt,
      creatorNotes: creatorNotes,
      avatarPath: json['avatarPath'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      creator: json['creator'] ?? '',
      version: json['version'] ?? '1.0',
      systemInstruction: json['systemInstruction']?.toString() ??
          (personality.isNotEmpty ? personality : systemPrompt),
      scenario: json['scenario'] ?? '',
      authorsNote: json['authorsNote'] ?? '',
      authorsNoteDepth: json['authorsNoteDepth'] ?? 4,
      authorsNoteFrequency: json['authorsNoteFrequency'] ?? 0,
      firstMessage: json['firstMessage'] ?? '',
      alternateGreetings: List<String>.from(json['alternateGreetings'] ?? []),
      exampleDialogue: json['exampleDialogue'] ?? '',
      boundModelId: json['boundModelId'],
      preferredModelName: json['preferredModelName'],
      characterBookId: characterBookId.isEmpty ? null : characterBookId,
      worldInfoIds: List<String>.from(json['worldInfoIds'] ?? []),
      regexScriptIds: List<String>.from(json['regexScriptIds'] ?? []),
      isGroup: json['isGroup'] ?? false,
      groupMemberIds: List<String>.from(json['groupMemberIds'] ?? []),
      cardSpec: json['cardSpec']?.toString() ?? 'chara_card_v2',
      cardSpecVersion: json['cardSpecVersion']?.toString() ?? '2.0',
      rawCardData: _safeMap(json['rawCardData']),
      rawExtensions: _safeMap(json['rawExtensions']),
      rawCharacterBook: rawCharacterBook.isEmpty ? null : rawCharacterBook,
    );
  }
}
