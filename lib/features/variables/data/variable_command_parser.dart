import 'dart:convert';

import '../domain/models/variable_update.dart';
import '../domain/variable_path.dart';

/// 从模型输出里解析变量更新指令块。
///
/// **为什么需要「宽松降级链」**：模型不一定听话。同一个需求，强模型会吐标准
/// `<UpdateVariable>` 块，弱模型可能吐裸 JSON、中文标签、甚至只吐变量宏。
/// 只认一种格式的话，「变量不更新」会变成用户查不出原因的黑洞。
///
/// 降级顺序（**命中即停**，避免同一轮重复应用）：
/// 1. `<UpdateVariable>…</UpdateVariable>` 里的 `<JSONPatch>` 数组（主格式）
/// 2. `<变量更新>…</变量更新>` 中文标签
/// 3. 回复里任意位置的裸 JSON Patch 数组
/// 4. 变量宏 `{{setvar::k::v}}` / `{{addvar::k::v}}` / `{{incvar::k}}` / `{{decvar::k}}`
///
/// ⛔ **本解析器绝不抛异常**。模型吐半截 JSON 是常态，解析失败必须静默降级，
/// 不能因此中断生成或弹错误。
class VariableCommandParser {
  const VariableCommandParser._();

  /// 主格式：`<UpdateVariable>…</UpdateVariable>`
  static final RegExp _updateVariableBlock = RegExp(
    r'<\s*UpdateVariable\s*>(.*?)<\s*/\s*UpdateVariable\s*>',
    caseSensitive: false,
    dotAll: true,
  );

  /// 中文标签：`<变量更新>…</变量更新>`
  static final RegExp _chineseBlock = RegExp(
    r'<\s*变量更新\s*>(.*?)<\s*/\s*变量更新\s*>',
    dotAll: true,
  );

  static final RegExp _jsonPatchBlock = RegExp(
    r'<\s*JSONPatch\s*>(.*?)<\s*/\s*JSONPatch\s*>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _analysisBlock = RegExp(
    r'<\s*Analysis\s*>(.*?)<\s*/\s*Analysis\s*>',
    caseSensitive: false,
    dotAll: true,
  );

  /// 裸 JSON 数组（至少含一个对象）。
  static final RegExp _bareJsonArray = RegExp(r'\[\s*\{[\s\S]*?\}\s*\]');

  /// 单个 JSON 对象。
  static final RegExp _jsonObject = RegExp(r'\{[^{}]*\}');

  /// 变量宏。**不含 `getvar`** —— 读取不该被剥离也不产生操作。
  static final RegExp _macro = RegExp(
    r'\{\{\s*(setvar|addvar|incvar|decvar)::([^}:]+?)(?:::(.*?))?\}\}',
    caseSensitive: false,
  );

  /// 解析一段模型输出。
  static VariableParseResult parse(String content) {
    try {
      if (content.trim().isEmpty) {
        return VariableParseResult.empty;
      }

      final primary = _parseTaggedBlock(
        content,
        _updateVariableBlock,
        format: 'json_patch',
      );
      if (primary != null) {
        return primary;
      }

      final chinese = _parseTaggedBlock(
        content,
        _chineseBlock,
        format: 'cn_tag',
      );
      if (chinese != null) {
        return chinese;
      }

      final bare = _parseBareJsonArray(content);
      if (bare != null) {
        return bare;
      }

      return _parseMacros(content);
    } catch (_) {
      // 解析器永远不向外抛。
      return VariableParseResult.empty;
    }
  }

  /// 只判断「有没有指令块」，不做完整解析。用于轻量探测。
  static bool looksLikeCommandBlock(String content) {
    if (content.trim().isEmpty) {
      return false;
    }
    return _updateVariableBlock.hasMatch(content) ||
        _chineseBlock.hasMatch(content) ||
        _macro.hasMatch(content);
  }

  static VariableParseResult? _parseTaggedBlock(
    String content,
    RegExp blockPattern, {
    required String format,
  }) {
    final matches = blockPattern.allMatches(content).toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }

    final ops = <VariableOp>[];
    final spans = <String>[];
    var analysis = '';

    for (final match in matches) {
      final whole = match.group(0) ?? '';
      if (whole.trim().isEmpty) {
        continue;
      }
      spans.add(whole);

      final body = match.group(1) ?? '';
      if (analysis.isEmpty) {
        final analysisMatch = _analysisBlock.firstMatch(body);
        if (analysisMatch != null) {
          final text = (analysisMatch.group(1) ?? '').trim();
          if (text.isNotEmpty) {
            analysis = text;
          }
        }
      }

      // 有 <JSONPatch> 子块就只认它；没有就把整块内容当 payload 试。
      final patchMatch = _jsonPatchBlock.firstMatch(body);
      final payload = patchMatch != null ? (patchMatch.group(1) ?? '') : body;
      ops.addAll(_parseOpsPayload(payload));
    }

    return VariableParseResult(
      update: VariableUpdate(ops: ops, analysis: analysis, format: format),
      spans: spans,
    );
  }

  static VariableParseResult? _parseBareJsonArray(String content) {
    final match = _bareJsonArray.firstMatch(content);
    if (match == null) {
      return null;
    }
    final raw = match.group(0) ?? '';
    final ops = _parseOpsPayload(raw);
    if (ops.isEmpty) {
      // 裸数组里没有可识别的操作 —— 不要剥掉它，那可能是正文里的正常 JSON。
      return null;
    }
    return VariableParseResult(
      update: VariableUpdate(ops: ops, format: 'json_array'),
      spans: <String>[raw],
    );
  }

  static VariableParseResult _parseMacros(String content) {
    final ops = <VariableOp>[];
    final spans = <String>[];

    for (final match in _macro.allMatches(content)) {
      final command = (match.group(1) ?? '').toLowerCase();
      final rawKey = (match.group(2) ?? '').trim();
      final payload = (match.group(3) ?? '').trim();
      if (rawKey.isEmpty) {
        continue;
      }
      final path = VariablePath.normalizeAny(rawKey);
      if (path.isEmpty) {
        continue;
      }

      if (command.startsWith('set')) {
        ops.add(
          VariableOp(
            type: VariableOpType.set,
            path: path,
            value: num.tryParse(payload) ?? payload,
          ),
        );
      } else if (command.startsWith('add')) {
        ops.add(
          VariableOp(
            type: VariableOpType.add,
            path: path,
            value: num.tryParse(payload) ?? 0,
          ),
        );
      } else if (command.startsWith('inc')) {
        ops.add(VariableOp(type: VariableOpType.add, path: path, value: 1));
      } else if (command.startsWith('dec')) {
        ops.add(VariableOp(type: VariableOpType.add, path: path, value: -1));
      } else {
        continue;
      }
      spans.add(match.group(0) ?? '');
    }

    if (ops.isEmpty) {
      return VariableParseResult.empty;
    }
    return VariableParseResult(
      update: VariableUpdate(ops: ops, format: 'macro'),
      spans: spans,
    );
  }

  /// 把一段 payload（数组 / 单对象 / 文本行）解析成操作列表。
  ///
  /// 三级尝试：严格 JSON → 宽松修补后的 JSON → 逐对象 / 逐行兜底。
  static List<VariableOp> _parseOpsPayload(String payload) {
    final text = payload.trim();
    if (text.isEmpty) {
      return const <VariableOp>[];
    }

    final decoded = _tryDecode(text);
    if (decoded is List) {
      return _opsFromList(decoded);
    }
    if (decoded is Map) {
      return _opsFromList(<dynamic>[decoded]);
    }

    // 宽松兜底：逐个抽 JSON 对象。
    final ops = <VariableOp>[];
    for (final match in _jsonObject.allMatches(text)) {
      final raw = match.group(0);
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final obj = _tryDecode(raw);
      if (obj is Map) {
        ops.addAll(_opsFromList(<dynamic>[obj]));
      }
    }
    if (ops.isNotEmpty) {
      return ops;
    }

    // 再不行：按「键: 值」行解析（中文标签块的常见形态）。
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final op = VariableOp.fromTextLine(line);
      if (op != null) {
        ops.add(op);
      }
    }
    return ops;
  }

  static List<VariableOp> _opsFromList(List<dynamic> items) {
    final ops = <VariableOp>[];
    for (final item in items) {
      if (item is Map) {
        final op = VariableOp.fromJsonPatch(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (op != null) {
          ops.add(op);
        }
        continue;
      }
      // 数组里混了字符串？试一下「键: 值」行。
      if (item is String) {
        final op = VariableOp.fromTextLine(item);
        if (op != null) {
          ops.add(op);
        }
      }
    }
    return ops;
  }

  /// 严格解码失败时做**保守**修补后再试。
  ///
  /// 只做三种安全修补：去注释、去尾随逗号、在**完全没有双引号**时把单引号换成
  /// 双引号。⛔ 不做「混合引号替换」—— 那会破坏正文里的撇号。
  static dynamic _tryDecode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(text);
    } catch (_) {
      // 继续修补。
    }

    try {
      return jsonDecode(_relaxJson(text));
    } catch (_) {
      return null;
    }
  }

  static String _relaxJson(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    text = text.replaceAll(RegExp(r',\s*([\]}])'), r'$1');
    if (!text.contains('"')) {
      text = text.replaceAll("'", '"');
    }
    return text.trim();
  }
}
