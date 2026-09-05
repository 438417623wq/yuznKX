import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_chunks;
import 'package:path_provider/path_provider.dart';
import '../domain/models/character.dart';
import '../../regex/data/regex_provider.dart';
import '../../regex/domain/models/regex_script.dart';
import '../../world_info/data/world_info_provider.dart';
import '../../world_info/domain/models/world_info.dart';

dynamic _deepCopyDynamic(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(
          key.toString(),
          _deepCopyDynamic(val),
        ));
  }
  if (value is List) {
    return value.map(_deepCopyDynamic).toList();
  }
  return value;
}

Map<String, dynamic> _safeMap(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(
          key.toString(),
          _deepCopyDynamic(val),
        ));
  }
  return <String, dynamic>{};
}

final characterListProvider =
    StateNotifierProvider<CharacterListNotifier, List<Character>>((ref) {
  return CharacterListNotifier(ref);
});

final activeCharacterIdProvider =
    StateNotifierProvider<ActiveCharacterIdNotifier, String?>((ref) {
  return ActiveCharacterIdNotifier();
});

class ActiveCharacterIdNotifier extends StateNotifier<String?> {
  ActiveCharacterIdNotifier() : super(null) {
    _load();
  }

  void _load() {
    final box = Hive.box('settings');
    state = box.get('active_character_id');
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = Hive.box('settings');
    if (id == null) {
      await box.delete('active_character_id');
    } else {
      await box.put('active_character_id', id);
    }
  }
}

final activeCharacterProvider = Provider<Character?>((ref) {
  final id = ref.watch(activeCharacterIdProvider);
  final list = ref.watch(characterListProvider);
  if (id == null) return null;
  try {
    return list.firstWhere((c) => c.id == id);
  } catch (_) {
    return null;
  }
});

class CharacterListNotifier extends StateNotifier<List<Character>> {
  final Ref ref;
  late Box _box;

  CharacterListNotifier(this.ref) : super([]) {
    _init();
  }

  void _init() {
    _box = Hive.box('characters');
    _load();
  }

  void _load() {
    final data = _box.values.toList();
    final List<Character> loadedCharacters = [];
    for (final e in data) {
      try {
        loadedCharacters.add(Character.fromJson(Map<String, dynamic>.from(e)));
      } catch (e) {
        print('Error loading character: $e');
      }
    }
    state = loadedCharacters;
  }

  Future<void> save(Character character) async {
    await _box.put(character.id, character.toJson());
    if (state.any((c) => c.id == character.id)) {
      state = state.map((c) => c.id == character.id ? character : c).toList();
    } else {
      state = [...state, character];
    }
  }

  Future<void> delete(String id) async {
    final character = state.firstWhere(
      (c) => c.id == id,
      orElse: () => Character(
          id: '',
          name: '',
          description: '',
          avatarPath: '',
          systemInstruction: '',
          firstMessage: ''),
    );

    if (character.id.isNotEmpty && character.characterBookId != null) {
      await ref
          .read(worldInfoProvider.notifier)
          .delete(character.characterBookId!);
    }

    await _box.delete(id);
    state = state.where((c) => c.id != id).toList();

    // Check if the deleted character was active
    final activeId = ref.read(activeCharacterIdProvider);
    if (activeId == id) {
      ref.read(activeCharacterIdProvider.notifier).setActive(null);
    }
  }

  // --- Import Logic ---

  Future<void> importCharacter() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'png'],
      withData: true,
    );

    if (result == null) {
      return;
    }

    final pickedFile = result.files.single;
    final extension = pickedFile.extension?.toLowerCase();

    try {
      Character? character;
      if (extension == 'json') {
        character = await _importJson(pickedFile);
      } else if (extension == 'png') {
        character = await _importPng(pickedFile);
      }

      if (character != null) {
        await save(character);
      }
    } catch (e) {
      print('Import Error: $e');
      // Ideally show error via a provider or callback
    }
  }

  Future<Character> _importJson(PlatformFile file) async {
    final content = await _readFileText(file);
    final decoded = jsonDecode(content);
    return await _parseV2Spec(
      _safeMap(decoded),
      file.path ?? file.name,
      avatarPath: '',
    );
  }

  Future<Character?> _importPng(PlatformFile file) async {
    final bytes = await _readFileBytes(file);
    final chunks = png_chunks.extractChunks(bytes);
    final textChunks = <String, String>{};

    for (final chunk in chunks) {
      final name = chunk['name']?.toString();
      if (name == 'tEXt') {
        final data = chunk['data'] as List<int>;
        final entry = _parseTextChunk(data);
        if (entry != null) {
          textChunks[entry.$1] = entry.$2;
        }
      } else if (name == 'iTXt') {
        final data = chunk['data'] as List<int>;
        final entry = _parseInternationalTextChunk(data);
        if (entry != null) {
          textChunks[entry.$1] = entry.$2;
        }
      }
    }

    final candidates = <String>[
      if (textChunks['chara'] != null) textChunks['chara']!,
      if (textChunks['ccv3'] != null) textChunks['ccv3']!,
      ...textChunks.entries
          .where((entry) => entry.value.trim().length > 100)
          .map((entry) => entry.value),
    ];

    for (final candidate in candidates) {
      final json = _decodeCharacterPayload(candidate);
      if (json == null) {
        continue;
      }

      final avatarPath = await _persistImportedAvatar(bytes);
      return _parseV2Spec(
        json,
        file.path ?? file.name,
        avatarPath: avatarPath,
      );
    }

    return null;
  }

  Future<String> _readFileText(PlatformFile file) async {
    if (file.bytes != null) {
      try {
        return utf8.decode(file.bytes!);
      } on FormatException {
        return utf8.decode(file.bytes!, allowMalformed: true);
      }
    }

    if (file.path != null) {
      return File(file.path!).readAsString();
    }

    throw const FormatException('Unable to read imported file text.');
  }

  Future<Uint8List> _readFileBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return Uint8List.fromList(file.bytes!);
    }

    if (file.path != null) {
      return File(file.path!).readAsBytes();
    }

    throw const FormatException('Unable to read imported file bytes.');
  }

  (String, String)? _parseTextChunk(List<int> data) {
    final nullIndex = data.indexOf(0);
    if (nullIndex <= 0) {
      return null;
    }

    final keyword =
        utf8.decode(data.sublist(0, nullIndex), allowMalformed: true);
    final value =
        utf8.decode(data.sublist(nullIndex + 1), allowMalformed: true);
    return (keyword, value);
  }

  (String, String)? _parseInternationalTextChunk(List<int> data) {
    var pointer = 0;
    while (pointer < data.length && data[pointer] != 0) {
      pointer++;
    }
    if (pointer <= 0 || pointer >= data.length) {
      return null;
    }

    final keyword = utf8.decode(data.sublist(0, pointer), allowMalformed: true);
    pointer++;

    if (pointer + 2 > data.length) {
      return null;
    }

    final compressionFlag = data[pointer];
    pointer += 2; // compression method

    while (pointer < data.length && data[pointer] != 0) {
      pointer++;
    }
    pointer++;

    while (pointer < data.length && data[pointer] != 0) {
      pointer++;
    }
    pointer++;

    if (pointer > data.length || compressionFlag != 0) {
      return null;
    }

    final value = utf8.decode(data.sublist(pointer), allowMalformed: true);
    return (keyword, value);
  }

  Map<String, dynamic>? _decodeCharacterPayload(String rawPayload) {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final candidates = <String>{trimmed};
    final commaIndex = trimmed.indexOf(',');
    if (trimmed.startsWith('data:') && commaIndex != -1) {
      candidates.add(trimmed.substring(commaIndex + 1).trim());
    }

    for (final candidate in candidates.toList()) {
      final decoded = _tryDecodeBase64(candidate);
      if (decoded != null && decoded.trim().isNotEmpty) {
        candidates.add(decoded.trim());
      }
    }

    for (final candidate in candidates) {
      try {
        final parsed = jsonDecode(candidate);
        if (parsed is Map) {
          return _safeMap(parsed);
        }
      } catch (_) {
        // Try next candidate.
      }
    }

    return null;
  }

  String? _tryDecodeBase64(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty || normalized.startsWith('{')) {
      return null;
    }

    final padding = normalized.length % 4;
    final padded = padding == 0
        ? normalized
        : normalized.padRight(normalized.length + (4 - padding), '=');

    try {
      return utf8.decode(base64Decode(padded), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<String> _persistImportedAvatar(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(
      '${directory.path}${Platform.pathSeparator}character_avatars',
    );
    if (!avatarDir.existsSync()) {
      await avatarDir.create(recursive: true);
    }

    final file = File(
      '${avatarDir.path}${Platform.pathSeparator}${const Uuid().v4()}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Character> _parseV2Spec(
    Map<String, dynamic> json,
    String sourcePath, {
    required String avatarPath,
  }) async {
    // Handle V1/V2 differences
    // V2 Spec: https://github.com/SillyTavern/SillyTavern/blob/release/docs/character_card_v2.md

    // "spec": "chara_card_v2", "data": { ... }
    // Or legacy format directly in root.

    final rawRoot = _safeMap(json);
    final spec = json['spec']?.toString() ?? 'chara_card_v2';
    final specVersion = json['spec_version']?.toString() ?? '2.0';

    Map<String, dynamic> data = json;
    if (json.containsKey('spec') &&
        (json['spec'] == 'chara_card_v2' || json['spec'] == 'chara_card_v3')) {
      data = _safeMap(json['data']);
    }

    // Extract World Info
    String? characterBookId;
    List<String> worldInfoIds = [];
    dynamic bookData;
    if (data.containsKey('character_book')) {
      bookData = data['character_book'];
    } else if (json.containsKey('character_book')) {
      bookData = json['character_book'];
    }

    final rawCharacterBook = _safeMap(bookData);
    if (bookData != null) {
      try {
        final wi =
            WorldInfo.fromJson(Map<String, dynamic>.from(rawCharacterBook));
        await ref.read(worldInfoProvider.notifier).save(wi);
        characterBookId = wi.id;
      } catch (e) {
        print('Error importing World Info: $e');
      }
    }

    // Extract Regex Scripts
    List<String> regexScriptIds = [];
    dynamic extensions;
    if (data.containsKey('extensions')) {
      extensions = data['extensions'];
    } else if (json.containsKey('extensions')) {
      extensions = json['extensions'];
    }

    final rawExtensions = _safeMap(extensions);
    if (rawExtensions.containsKey('regex_scripts')) {
      final scripts = rawExtensions['regex_scripts'];
      if (scripts is List) {
        for (var scriptData in scripts) {
          try {
            final script =
                RegexScript.fromJson(Map<String, dynamic>.from(scriptData));
            await ref.read(regexScriptsProvider.notifier).save(script);
            regexScriptIds.add(script.id);
          } catch (e) {
            print('Error importing Regex Script: $e');
          }
        }
      }
    }

    String parsedAuthorsNote =
        data['post_history_instructions']?.toString() ?? '';
    int parsedAuthorsNoteDepth = 4;
    final depthPrompt = _safeMap(rawExtensions['depth_prompt']);
    if (depthPrompt.isNotEmpty) {
      final extPrompt = depthPrompt['prompt']?.toString() ?? '';
      if (parsedAuthorsNote.isEmpty && extPrompt.isNotEmpty) {
        parsedAuthorsNote = extPrompt;
      }
      final depthRaw = depthPrompt['depth'];
      if (depthRaw is int) {
        parsedAuthorsNoteDepth = depthRaw;
      } else if (depthRaw is num) {
        parsedAuthorsNoteDepth = depthRaw.toInt();
      } else if (depthRaw is String) {
        parsedAuthorsNoteDepth = int.tryParse(depthRaw) ?? 4;
      }
    }

    return Character(
      id: const Uuid().v4(),
      name: data['name'] ?? 'Imported Character',
      description: data['description'] ?? '',
      personality: data['personality']?.toString() ?? '',
      systemPrompt: data['system_prompt']?.toString() ?? '',
      creatorNotes: data['creator_notes']?.toString() ??
          data['creatorNotes']?.toString() ??
          '',
      avatarPath: avatarPath,
      tags: List<String>.from(data['tags'] ?? []),
      creator: data['creator'] ?? '',
      version: data['character_version'] ?? '1.0',
      systemInstruction:
          (data['system_prompt']?.toString().trim().isNotEmpty ?? false)
              ? data['system_prompt'].toString()
              : data['personality']?.toString() ?? '',
      scenario: data['scenario'] ?? '',
      authorsNote: parsedAuthorsNote,
      authorsNoteDepth: parsedAuthorsNoteDepth,
      firstMessage: data['first_mes'] ?? '',
      alternateGreetings: List<String>.from(data['alternate_greetings'] ?? []),
      exampleDialogue: data['mes_example']?.toString() ?? '',
      characterBookId: characterBookId,
      worldInfoIds: worldInfoIds,
      regexScriptIds: regexScriptIds,
      cardSpec: spec,
      cardSpecVersion: specVersion,
      rawCardData: rawRoot,
      rawExtensions: rawExtensions,
      rawCharacterBook: rawCharacterBook.isEmpty ? null : rawCharacterBook,
    );
  }
}
