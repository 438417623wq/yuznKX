import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_chunks;
import '../domain/models/character.dart';
import '../../regex/data/regex_provider.dart';
import '../../regex/domain/models/regex_script.dart';
import '../../world_info/data/world_info_provider.dart';
import '../../world_info/domain/models/world_info.dart';

final characterListProvider = StateNotifierProvider<CharacterListNotifier, List<Character>>((ref) {
  return CharacterListNotifier(ref);
});

final activeCharacterIdProvider = StateNotifierProvider<ActiveCharacterIdNotifier, String?>((ref) {
  return ActiveCharacterIdNotifier();
});

class ActiveCharacterIdNotifier extends StateNotifier<String?> {
  ActiveCharacterIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    state = box.get('active_character_id');
  }

  Future<void> setActive(String? id) async {
    state = id;
    final box = await Hive.openBox('settings');
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

  Future<void> _init() async {
    if (!Hive.isBoxOpen('characters')) {
      _box = await Hive.openBox('characters');
    } else {
      _box = Hive.box('characters');
    }
    _load();
  }

  void _load() {
    final data = _box.values.toList();
    state = data.map((e) => Character.fromJson(Map<String, dynamic>.from(e))).toList();
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
    // Find the character to be deleted to access its linked assets
    final character = state.firstWhere(
      (c) => c.id == id,
      orElse: () => Character(
        id: '', 
        name: '', 
        description: '', 
        avatarPath: '', 
        systemInstruction: '', 
        firstMessage: ''
      ),
    );

    if (character.id.isNotEmpty) {
       // Delete linked World Info
       for (final wiId in character.worldInfoIds) {
          await ref.read(worldInfoProvider.notifier).delete(wiId);
       }
       
       // Delete linked Regex Scripts
       for (final rsId in character.regexScriptIds) {
          await ref.read(regexScriptsProvider.notifier).delete(rsId);
       }
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
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final extension = result.files.single.extension?.toLowerCase();

      try {
        Character? character;
        if (extension == 'json') {
          character = await _importJson(file);
        } else if (extension == 'png') {
          character = await _importPng(file);
        }

        if (character != null) {
          await save(character);
        }
      } catch (e) {
        print('Import Error: $e');
        // Ideally show error via a provider or callback
      }
    }
  }

  Future<Character> _importJson(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content);
    return await _parseV2Spec(json, file.path); // Assume JSON is V2 or V1 compatible
  }

  Future<Character?> _importPng(File file) async {
    final bytes = await file.readAsBytes();
    
    // Extract tEXt chunks using png_chunks_encode (or manual parsing)
    // SillyTavern embeds JSON in a 'chara' tEXt chunk (CCV3) or base64 string in 'chara'
    // V2 spec uses 'ccv2'? Actually usually 'chara' key with base64 encoded content.
    
    // Let's implement a simple chunk reader
    final chunks = png_chunks.extractChunks(bytes);
    String? charaContent;

    for (final chunk in chunks) {
      if (chunk['name'] == 'tEXt') {
        final data = chunk['data'] as List<int>;
        // tEXt format: keyword + null + text
        int nullIndex = data.indexOf(0);
        if (nullIndex != -1) {
          final keyword = String.fromCharCodes(data.sublist(0, nullIndex));
          if (keyword == 'chara') {
             // Found character data
             final textData = String.fromCharCodes(data.sublist(nullIndex + 1));
             // It's usually base64 encoded JSON
             try {
               final decoded = utf8.decode(base64Decode(textData));
               charaContent = decoded;
             } catch (e) {
               // Maybe plain text JSON? (Rare)
               charaContent = textData;
             }
             break;
          }
        }
      }
    }

    if (charaContent != null) {
      final json = jsonDecode(charaContent);
      return await _parseV2Spec(json, file.path); // Use PNG path as avatar
    }
    
    return null;
  }

  Future<Character> _parseV2Spec(Map<String, dynamic> json, String sourcePath) async {
    // Handle V1/V2 differences
    // V2 Spec: https://github.com/SillyTavern/SillyTavern/blob/release/docs/character_card_v2.md
    
    // "spec": "chara_card_v2", "data": { ... }
    // Or legacy format directly in root.
    
    Map<String, dynamic> data = json;
    if (json.containsKey('spec') && (json['spec'] == 'chara_card_v2' || json['spec'] == 'chara_card_v3')) {
      data = json['data'];
    }

    // Extract World Info
    List<String> worldInfoIds = [];
    dynamic bookData;
    if (data.containsKey('character_book')) {
      bookData = data['character_book'];
    } else if (json.containsKey('character_book')) {
      bookData = json['character_book'];
    }

    if (bookData != null) {
      try {
        final wi = WorldInfo.fromJson(Map<String, dynamic>.from(bookData));
        await ref.read(worldInfoProvider.notifier).save(wi);
        worldInfoIds.add(wi.id);
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

    if (extensions != null && extensions is Map && extensions.containsKey('regex_scripts')) {
      final scripts = extensions['regex_scripts'];
      if (scripts is List) {
        for (var scriptData in scripts) {
           try {
             final script = RegexScript.fromJson(Map<String, dynamic>.from(scriptData));
             await ref.read(regexScriptsProvider.notifier).save(script);
             regexScriptIds.add(script.id);
           } catch (e) {
             print('Error importing Regex Script: $e');
           }
        }
      }
    }

    return Character(
      id: const Uuid().v4(),
      name: data['name'] ?? 'Imported Character',
      description: data['description'] ?? '',
      avatarPath: sourcePath, // Use the file path as avatar
      tags: List<String>.from(data['tags'] ?? []),
      creator: data['creator'] ?? '',
      version: data['character_version'] ?? '1.0',
      systemInstruction: data['system_prompt'] ?? data['personality'] ?? '', // Fallback
      scenario: data['scenario'] ?? '',
      authorsNote: data['post_history_instructions'] ?? '', // Author's Note mapping
      firstMessage: data['first_mes'] ?? '',
      alternateGreetings: List<String>.from(data['alternate_greetings'] ?? []),
      worldInfoIds: worldInfoIds,
      regexScriptIds: regexScriptIds,
    );
  }
}
