import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/source_material.dart';

/// 材料导入服务：把设定文档 / 人设稿 / 世界观笔记 / 长篇小说读成纯文本。
///
/// 支持 txt / md / docx：
/// - txt、md 直接按 UTF-8 解码；
/// - docx 用 `archive` 解出 `word/document.xml`，再从 OOXML 里抽文本
///   （不引入新的解析依赖）。
///
/// PDF 有意不支持 —— 中文 PDF 的文本提取质量不稳定，与其给一个会出错的结果，
/// 不如明确让用户先转成文本。
class MaterialIngestService {
  const MaterialIngestService();

  /// 允许的扩展名。
  static const List<String> allowedExtensions = <String>[
    'txt',
    'md',
    'markdown',
    'docx',
  ];

  /// 打开文件选择器并解析成材料。用户取消时返回 null。
  Future<SourceMaterial?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final name = file.name;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception('读不到文件内容（$name）。请换一个文件试试。');
    }

    final text = parseBytes(name, bytes);
    if (text.trim().isEmpty) {
      throw Exception('从「$name」里没有提取到任何文字。');
    }

    return SourceMaterial(
      id: const Uuid().v4(),
      fileName: name,
      text: text,
      importedAt: DateTime.now(),
      status: MaterialStatus.pending,
    );
  }

  /// 按扩展名分派解析。
  String parseBytes(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.docx')) {
      return extractDocxText(bytes);
    }
    // txt / md / markdown：按 UTF-8 解码，容错处理非法字节。
    return _normalize(utf8.decode(bytes, allowMalformed: true));
  }

  /// 从 docx 的 zip 里抽出正文文本。
  static String extractDocxText(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw Exception('这个 docx 打不开，可能不是标准的 Office 文档。');
    }

    final file = archive.findFile('word/document.xml');
    if (file == null) {
      throw Exception('这个 docx 里找不到正文（word/document.xml）。');
    }

    final xml = utf8.decode(file.content, allowMalformed: true);
    return _normalize(_docxXmlToText(xml));
  }

  /// 把 OOXML 转成纯文本。
  ///
  /// 只关心四种标记：`<w:p>` 段落、`</w:p>` 段落结束、`<w:br/>` 换行、
  /// `<w:tab/>` 制表符，以及 `<w:t>` 里的实际文字。其余标记一律丢弃。
  static String _docxXmlToText(String xml) {
    final buffer = StringBuffer();
    final pattern = RegExp(
      r'<w:tab\b[^>]*/?>|<w:br\b[^>]*/?>|<w:p\b[^>]*>|</w:p>|<w:t\b[^>]*>([\s\S]*?)</w:t>',
    );

    for (final match in pattern.allMatches(xml)) {
      final token = match.group(0) ?? '';
      if (token.startsWith('<w:tab')) {
        buffer.write('\t');
      } else if (token.startsWith('<w:br')) {
        buffer.write('\n');
      } else if (token == '</w:p>') {
        buffer.write('\n');
      } else if (token.startsWith('<w:t')) {
        buffer.write(_unescapeXml(match.group(1) ?? ''));
      }
      // `<w:p ...>` 开标签本身不产出内容，段落结束由 `</w:p>` 处理。
    }

    return buffer.toString();
  }

  /// 还原 XML 实体。
  static String _unescapeXml(String value) {
    var text = value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');

    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code == null || code <= 0) {
        return match.group(0) ?? '';
      }
      return String.fromCharCode(code);
    });
    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code == null || code <= 0) {
        return match.group(0) ?? '';
      }
      return String.fromCharCode(code);
    });
    return text;
  }

  /// 统一空白：去掉行尾空格、压掉 3 个以上连续换行。
  static String _normalize(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// 把多个分片提取结果合并去重。
  ///
  /// 长文会切成多片分别提取，同一维度可能被多片都填了值 —— 这里合并：
  /// 短的片段如果是长的片段的子串就丢弃，否则用换行拼接。
  static Map<String, String> mergeExtractions(
    List<Map<String, String>> results,
  ) {
    final merged = <String, String>{};

    for (final result in results) {
      result.forEach((key, value) {
        final incoming = value.trim();
        if (incoming.isEmpty) {
          return;
        }
        final existing = merged[key];
        if (existing == null || existing.isEmpty) {
          merged[key] = incoming;
          return;
        }
        if (existing.contains(incoming)) {
          return;
        }
        if (incoming.contains(existing)) {
          merged[key] = incoming;
          return;
        }
        merged[key] = '$existing\n$incoming';
      });
    }

    return merged;
  }
}
