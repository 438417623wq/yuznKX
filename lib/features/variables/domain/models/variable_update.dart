import '../variable_path.dart';

/// 变量更新操作的种类。
///
/// 只有三种 —— 它们是 JSON Patch 与 MVU 约定的最小公共集：
/// - [set]：把变量设为给定值（`replace` / `set`）
/// - [add]：在当前值基础上增减（`increment` / `delta` / 带数值的 `add`）
/// - [delete]：删除变量（`remove` / `delete`）
///
/// ⛔ [add] 与 [set] 的区别是**重放安全性**：`set` 幂等，`add` 不是。
/// 同一轮回复被处理两次，`add` 会让数值翻倍 —— 所以运行时必须做轮次去重
/// （见 `variable_runtime.dart`）。
enum VariableOpType {
  set('set', '设为'),
  add('add', '增减'),
  delete('delete', '删除');

  const VariableOpType(this.key, this.label);

  final String key;
  final String label;

  static VariableOpType fromKey(String? key) {
    for (final value in VariableOpType.values) {
      if (value.key == key) {
        return value;
      }
    }
    return VariableOpType.set;
  }
}

/// 一次变量更新的原子操作。
class VariableOp {
  const VariableOp({
    required this.type,
    required this.path,
    this.value,
  });

  final VariableOpType type;

  /// 平铺键形式的路径（`角色.好感度`）。
  final String path;

  /// 目标值（[VariableOpType.delete] 时为 null）。
  final dynamic value;

  bool get isValid => VariablePath.isValid(path);

  /// 从一条 JSON Patch 项解析。
  ///
  /// **宽松**：字段名接受 `op`/`type`/`操作`、`path`/`key`/`键`/`变量`、
  /// `value`/`val`/`值`。`op` 缺失时按「有 value 就 set，没 value 就删」推断。
  ///
  /// 操作映射：
  /// | 输入 op | 结果 |
  /// |---|---|
  /// | `remove` / `delete` / `del` / `删除` | [VariableOpType.delete] |
  /// | `increment` / `inc` / `delta` / `add` / `+` / `累加` / `增加` | [VariableOpType.add]（值非数字则退化为 set） |
  /// | 其它 / 缺失 | [VariableOpType.set] |
  static VariableOp? fromJsonPatch(Map<String, dynamic> json) {
    final rawPath = _firstString(json, const ['path', 'key', 'name', '变量', '键', '路径']);
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }
    final path = VariablePath.normalizeAny(rawPath);
    if (path.isEmpty) {
      return null;
    }

    final hasValue = _hasAnyKey(json, const ['value', 'val', 'v', '值']);
    final value = _firstValue(json, const ['value', 'val', 'v', '值']);

    final rawOp = (_firstString(json, const ['op', 'type', 'operation', '操作']) ?? '')
        .toLowerCase()
        .trim();

    if (rawOp == 'remove' || rawOp == 'delete' || rawOp == 'del' || rawOp == '删除') {
      return VariableOp(type: VariableOpType.delete, path: path);
    }

    if (!hasValue) {
      // 没给值又没说删 —— 无法执行，跳过。
      return null;
    }

    const additiveOps = <String>{
      'increment',
      'inc',
      'delta',
      'add',
      '+',
      '累加',
      '增加',
      '增减',
    };
    if (additiveOps.contains(rawOp)) {
      // `add` 在 JSON Patch 标准里是「插入/替换」，在 MVU 社区卡里常被当成累加。
      // 折中：值能转成数字就按累加（这正是模型想表达「+5」的场景），
      // 否则退化为 set。目标键不存在时，累加从 0 起算，等价于 set 数值。
      final asNumber = _tryNumber(value);
      if (asNumber != null) {
        return VariableOp(type: VariableOpType.add, path: path, value: asNumber);
      }
      return VariableOp(type: VariableOpType.set, path: path, value: value);
    }

    return VariableOp(type: VariableOpType.set, path: path, value: value);
  }

  /// 从「键: 值」文本行解析（中文标签格式的降级路径）。
  ///
  /// 支持 `角色.好感度: 35`、`角色.好感度 = 35`、`角色.好感度：+5`。
  /// 值前带 `+`/`-` 时按 [VariableOpType.add] 处理。
  static VariableOp? fromTextLine(String line) {
    final text = line.trim();
    if (text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(.+?)\s*[:：=]\s*(.+)$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final path = VariablePath.normalizeAny(match.group(1) ?? '');
    if (path.isEmpty) {
      return null;
    }
    var rawValue = (match.group(2) ?? '').trim();
    if (rawValue.isEmpty) {
      return VariableOp(type: VariableOpType.delete, path: path);
    }

    var additive = false;
    if (rawValue.startsWith('+') || rawValue.startsWith('－') || rawValue.startsWith('-')) {
      // `-5` 是「减 5」还是「设为 -5」？文本行里前者更常见（配合 `+` 的对称写法）。
      if (rawValue.startsWith('+') || rawValue.startsWith('－')) {
        additive = true;
      }
      if (rawValue.startsWith('+')) {
        rawValue = rawValue.substring(1).trim();
      }
    }

    final asNumber = _tryNumber(rawValue);
    if (asNumber != null && additive) {
      return VariableOp(type: VariableOpType.add, path: path, value: asNumber);
    }
    return VariableOp(
      type: VariableOpType.set,
      path: path,
      value: asNumber ?? _unquote(rawValue),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'op': type.key,
        'path': path,
        if (value != null) 'value': value,
      };

  @override
  String toString() {
    if (type == VariableOpType.delete) {
      return 'del $path';
    }
    return '${type.key} $path = $value';
  }

  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) {
        final text = value.toString();
        if (text.trim().isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  static bool _hasAnyKey(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  static dynamic _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        return json[key];
      }
    }
    return null;
  }

  static num? _tryNumber(dynamic value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) {
        return null;
      }
      return num.tryParse(text);
    }
    return null;
  }

  static String _unquote(String raw) {
    var text = raw.trim();
    if (text.length >= 2) {
      final first = text[0];
      final last = text[text.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        text = text.substring(1, text.length - 1);
      }
    }
    return text;
  }
}

/// 一批变量更新（= 模型一次回复里要求的所有改动）。
class VariableUpdate {
  const VariableUpdate({
    this.ops = const <VariableOp>[],
    this.analysis = '',
    this.format = '',
  });

  final List<VariableOp> ops;

  /// 模型给出的变化原因（`<Analysis>` 内容，仅用于诊断/展示）。
  final String analysis;

  /// 命中的格式名（`json_patch` / `json_array` / `cn_tag` / `macro`）。
  final String format;

  bool get isEmpty => ops.isEmpty;

  bool get isNotEmpty => ops.isNotEmpty;

  int get length => ops.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ops': ops.map((op) => op.toJson()).toList(),
        if (analysis.isNotEmpty) 'analysis': analysis,
        if (format.isNotEmpty) 'format': format,
      };

  @override
  String toString() => 'VariableUpdate($format, ${ops.length} ops)';
}

/// 解析结果：更新内容 + 需要从**显示内容**里剥掉的原文片段。
///
/// 指令块是给机器看的，不该出现在聊天气泡里 —— 所以解析器顺手把命中的
/// 原文区间带出来，由调用方从消息内容里删除（照搬记忆模块 `<tableEdit>` 的做法）。
class VariableParseResult {
  const VariableParseResult({
    this.update,
    this.spans = const <String>[],
  });

  /// 没解析到任何更新时为 null。
  final VariableUpdate? update;

  /// 需要从显示内容里删除的原文片段（按出现顺序）。
  final List<String> spans;

  bool get hasUpdate => update != null && update!.isNotEmpty;

  bool get hasSpans => spans.isNotEmpty;

  /// 解析器是否**命中过格式**（哪怕 ops 为空，比如空数组）。
  ///
  /// 兜底提取的触发条件用这个：命中了格式就不必再发一次提取请求。
  bool get matched => update != null;

  static const VariableParseResult empty = VariableParseResult();

  /// 从 [content] 中剥掉所有 [spans]。
  ///
  /// 逐段 `replaceFirst` 而不是 `replaceAll` —— 同一段文本在一轮回复里
  /// 出现两次的概率很低，但真出现时按顺序各剥一次才对得上。
  String stripFrom(String content) {
    if (spans.isEmpty) {
      return content;
    }
    var result = content;
    for (final span in spans) {
      if (span.isEmpty) {
        continue;
      }
      result = result.replaceFirst(span, '');
    }
    return _tidy(result);
  }

  /// 剥掉指令块之后常留下多余空行，收一下。
  static String _tidy(String content) {
    var result = content.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }
}
