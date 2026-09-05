import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class FileHelper {
  static Future<({String name, dynamic data})?> pickJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null) {
      return null;
    }

    final fileData = result.files.single;
    final content = await _readFileText(fileData);
    final decoded = _decodeFlexibleJson(content);

    var name = fileData.name;
    if (name.contains('.')) {
      name = name.substring(0, name.lastIndexOf('.'));
    }

    return (name: name, data: decoded);
  }

  static Future<String> _readFileText(PlatformFile fileData) async {
    if (fileData.bytes != null) {
      try {
        return utf8.decode(fileData.bytes!);
      } on FormatException {
        return utf8.decode(fileData.bytes!, allowMalformed: true);
      }
    }

    if (fileData.path != null) {
      final file = File(fileData.path!);
      return file.readAsString();
    }

    throw const FormatException('无法读取文件内容。');
  }

  static dynamic _decodeFlexibleJson(String raw) {
    final normalized = _stripBom(raw);

    try {
      return jsonDecode(normalized);
    } catch (_) {
      // fallback below
    }

    final escapedControls = _escapeControlCharsInStrings(normalized);
    try {
      return jsonDecode(escapedControls);
    } catch (_) {
      // fallback below
    }

    final noTrailingCommas = _stripTrailingCommas(escapedControls);
    try {
      return jsonDecode(noTrailingCommas);
    } catch (e) {
      throw FormatException('无法解析 JSON 文件，请确认文件格式正确。原始错误：$e');
    }
  }

  static String _stripBom(String input) {
    if (input.startsWith('\uFEFF')) {
      return input.substring(1);
    }
    return input;
  }

  static String _escapeControlCharsInStrings(String input) {
    final output = StringBuffer();
    var inString = false;
    var escaping = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (inString) {
        if (escaping) {
          output.write(char);
          escaping = false;
          continue;
        }

        if (char == r'\') {
          output.write(char);
          escaping = true;
          continue;
        }

        if (char == '"') {
          output.write(char);
          inString = false;
          continue;
        }

        if (char == '\n') {
          output.write(r'\n');
          continue;
        }
        if (char == '\r') {
          output.write(r'\r');
          continue;
        }
        if (char == '\t') {
          output.write(r'\t');
          continue;
        }

        final code = char.codeUnitAt(0);
        if (code < 0x20) {
          output.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
          continue;
        }

        output.write(char);
        continue;
      }

      output.write(char);
      if (char == '"') {
        inString = true;
      }
    }

    return output.toString();
  }

  static String _stripTrailingCommas(String input) {
    final output = StringBuffer();
    var inString = false;
    var escaping = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (inString) {
        output.write(char);
        if (escaping) {
          escaping = false;
          continue;
        }
        if (char == r'\') {
          escaping = true;
          continue;
        }
        if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        output.write(char);
        inString = true;
        continue;
      }

      if (char == ',') {
        final nextIndex = _nextNonWhitespaceIndex(input, i + 1);
        if (nextIndex != -1) {
          final nextChar = input[nextIndex];
          if (nextChar == '}' || nextChar == ']') {
            continue;
          }
        }
      }

      output.write(char);
    }

    return output.toString();
  }

  static int _nextNonWhitespaceIndex(String input, int start) {
    for (var i = start; i < input.length; i++) {
      if (input[i].trim().isNotEmpty) {
        return i;
      }
    }
    return -1;
  }

  static Future<void> exportJson(dynamic data, String fileName) async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final xFile = XFile.fromData(
        utf8.encode(jsonStr),
        mimeType: 'application/json',
        name: '$fileName.json',
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: 'Exported $fileName',
        ),
      );
    } catch (e) {
      debugPrint('Error exporting file: $e');
    }
  }
}
