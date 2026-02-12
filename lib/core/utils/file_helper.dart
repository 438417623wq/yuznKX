import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class FileHelper {
  static Future<({String name, dynamic data})?> pickJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Important for Web and simplifies logic
      );

      if (result != null) {
        String content;
        final fileData = result.files.single;

        if (fileData.bytes != null) {
          content = utf8.decode(fileData.bytes!);
        } else if (fileData.path != null) {
          File file = File(fileData.path!);
          content = await file.readAsString();
        } else {
          return null;
        }

        String name = fileData.name;
        // Remove extension
        if (name.contains('.')) {
          name = name.substring(0, name.lastIndexOf('.'));
        }
        return (name: name, data: jsonDecode(content));
      }
    } catch (e) {
      print('Error picking/reading file: $e');
      // rethrow; // Don't crash the UI, just print
    }
    return null;
  }

  static Future<void> exportJson(dynamic data, String fileName) async {
    try {
      final String jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      
      // Use XFile.fromData for better cross-platform support (including Web)
      final XFile xFile = XFile.fromData(
        utf8.encode(jsonStr),
        mimeType: 'application/json',
        name: '$fileName.json',
      );

      await Share.shareXFiles([xFile], text: 'Exported $fileName');
    } catch (e) {
      print('Error exporting file: $e');
    }
  }
}
