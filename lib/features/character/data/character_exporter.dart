import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:png_chunks_encode/png_chunks_encode.dart' as png_enc;
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_ext;
import 'package:share_plus/share_plus.dart';
import '../domain/models/character.dart';

class CharacterExporter {
  static dynamic _deepCopyDynamic(dynamic value) {
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

  static Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(
            key.toString(),
            _deepCopyDynamic(val),
          ));
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _toRoot(Character character) {
    final base = character.rawCardData.isNotEmpty
        ? _safeMap(character.rawCardData)
        : <String, dynamic>{};

    final root = _safeMap(base);
    root['spec'] = character.cardSpec.isNotEmpty
        ? character.cardSpec
        : (root['spec']?.toString() ?? 'chara_card_v2');
    root['spec_version'] = character.cardSpecVersion.isNotEmpty
        ? character.cardSpecVersion
        : (root['spec_version']?.toString() ?? '2.0');
    return root;
  }

  static Map<String, dynamic> _toV2Json(Character character) {
    final root = _toRoot(character);
    final data = _safeMap(root['data']);
    root['data'] = data;

    data['name'] = character.name;
    data['description'] = character.description;
    data['personality'] = character.personality;
    data['system_prompt'] = character.systemPrompt;
    data['scenario'] = character.scenario;
    data['first_mes'] = character.firstMessage;
    data['mes_example'] = character.exampleDialogue;
    data['post_history_instructions'] = character.authorsNote;
    data['creator_notes'] = character.creatorNotes;
    data['alternate_greetings'] = character.alternateGreetings;
    data['tags'] = character.tags;
    data['creator'] = character.creator;
    data['character_version'] = character.version;

    if (character.rawCharacterBook != null &&
        character.rawCharacterBook!.isNotEmpty) {
      data['character_book'] = _deepCopyDynamic(character.rawCharacterBook);
    } else if (!data.containsKey('character_book')) {
      data['character_book'] = null;
    }

    final extensions = _safeMap(data['extensions']).isNotEmpty
        ? _safeMap(data['extensions'])
        : _safeMap(character.rawExtensions);
    final depthPrompt = _safeMap(extensions['depth_prompt']);
    depthPrompt['prompt'] = character.authorsNote;
    depthPrompt['depth'] = character.authorsNoteDepth;
    depthPrompt['role'] = depthPrompt['role']?.toString().isNotEmpty == true
        ? depthPrompt['role'].toString()
        : 'system';
    extensions['depth_prompt'] = depthPrompt;

    if (extensions.isNotEmpty) {
      data['extensions'] = extensions;
    }

    return root;
  }

  static Future<void> exportAsJson(Character character) async {
    try {
      final jsonMap = _toV2Json(character);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);

      final fileName =
          '${character.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.json';

      final XFile xFile = XFile.fromData(
        utf8.encode(jsonStr),
        mimeType: 'application/json',
        name: fileName,
      );

      await Share.shareXFiles([xFile],
          text: 'Exported Character: ${character.name}');
    } catch (e) {
      print('Error exporting JSON: $e');
      rethrow;
    }
  }

  static Future<void> exportAsPng(Character character) async {
    try {
      // 1. Get image bytes
      Uint8List imageBytes;
      if (character.avatarPath.isNotEmpty &&
          File(character.avatarPath).existsSync()) {
        imageBytes = await File(character.avatarPath).readAsBytes();
      } else {
        // Fallback to a default 1x1 transparent PNG if no avatar
        // This is a minimal valid PNG
        imageBytes = Uint8List.fromList([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82
        ]);
      }

      // 2. Prepare JSON data
      final jsonMap = _toV2Json(character);
      final jsonStr = jsonEncode(jsonMap);
      final base64Json = base64Encode(utf8.encode(jsonStr));

      // 3. Extract chunks from existing image
      final chunks = png_ext.extractChunks(imageBytes);

      // 4. Remove existing 'chara' chunks to avoid duplicates
      chunks.removeWhere(
          (chunk) => chunk['name'] == 'tEXt' && _isCharaChunk(chunk['data']));

      // 5. Add new 'chara' chunk
      // tEXt chunk format: keyword + null separator + text
      final keyword = 'chara';
      final keywordBytes = utf8.encode(keyword);
      final textBytes = utf8.encode(base64Json);
      final chunkData = Uint8List(keywordBytes.length + 1 + textBytes.length);

      chunkData.setAll(0, keywordBytes);
      chunkData[keywordBytes.length] = 0; // Null separator
      chunkData.setAll(keywordBytes.length + 1, textBytes);

      chunks.add({
        'name': 'tEXt',
        'data': chunkData,
      });

      // 6. Encode back to PNG
      final newImageBytes = png_enc.encodeChunks(chunks);

      // 7. Share/Save
      final fileName =
          '${character.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.png';

      final XFile xFile = XFile.fromData(
        newImageBytes,
        mimeType: 'image/png',
        name: fileName,
      );

      await Share.shareXFiles([xFile],
          text: 'Exported Character: ${character.name}');
    } catch (e) {
      print('Error exporting PNG: $e');
      rethrow;
    }
  }

  static bool _isCharaChunk(List<int> data) {
    // Check if the chunk data starts with "chara\0"
    final keyword = 'chara';
    final keywordBytes = utf8.encode(keyword);
    if (data.length <= keywordBytes.length) return false;

    for (int i = 0; i < keywordBytes.length; i++) {
      if (data[i] != keywordBytes[i]) return false;
    }
    return data[keywordBytes.length] == 0;
  }
}
