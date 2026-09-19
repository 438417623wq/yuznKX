/// 变量路径工具：路径 ↔ JSON Pointer 互转 + 平铺/嵌套读取。
///
/// **存储形态是平铺 `Map<String, dynamic>`** —— 键就是路径字符串
/// （`角色.好感度`），Dart 与 JS 之间不做结构转换。
///
/// ⛔ 本文件的 `readFlat` 必须与前端卡 JS 垫片
/// （`frontend_card_shim.dart` 里的 `readPath`）**行为一致**：
/// 先查平铺键，查不到再按 `.` 逐层下钻。改一处就要改另一处。
library;

/// 变量路径（MVU 风格的点分路径）工具集。
class VariablePath {
  const VariablePath._();

  /// 路径分隔符。
  static const String separator = '.';

  /// 规范化：去掉首尾空白与首尾多余的分隔符。
  static String normalize(String path) {
    var result = path.trim();
    while (result.startsWith(separator)) {
      result = result.substring(1);
    }
    while (result.endsWith(separator)) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 路径是否可用（非空）。
  static bool isValid(String path) => normalize(path).isNotEmpty;

  /// 把任意写法统一成平铺键形式。
  ///
  /// 以 `/` 开头按 JSON Pointer 解，否则按点分路径规范化。
  static String normalizeAny(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return '';
    }
    if (text.startsWith('/')) {
      return fromPointer(text);
    }
    return normalize(text);
  }

  /// `角色.好感度` → `/角色/好感度`
  ///
  /// 转义遵循 RFC 6901：`~` → `~0`，`/` → `~1`。
  static String toPointer(String path) {
    final normalized = normalize(path);
    if (normalized.isEmpty) {
      return '';
    }
    final segments = normalized
        .split(separator)
        .map(_escapeSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return '';
    }
    return '/${segments.join('/')}';
  }

  /// `/角色/好感度` → `角色.好感度`
  ///
  /// 不带前导 `/` 的写法（`角色/好感度`）也接受。
  static String fromPointer(String pointer) {
    var text = pointer.trim();
    if (text.isEmpty) {
      return '';
    }
    if (!text.startsWith('/')) {
      text = '/$text';
    }
    final segments = text
        .split('/')
        .skip(1)
        .map(_unescapeSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.join(separator);
  }

  /// 取父路径。`角色.好感度` → `角色`；顶层路径返回空串。
  static String parentOf(String path) {
    final normalized = normalize(path);
    final index = normalized.lastIndexOf(separator);
    if (index <= 0) {
      return '';
    }
    return normalized.substring(0, index);
  }

  /// 取末段。`角色.好感度` → `好感度`。
  static String leafOf(String path) {
    final normalized = normalize(path);
    final index = normalized.lastIndexOf(separator);
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  /// 拼子路径。
  static String join(String parent, String child) {
    final left = normalize(parent);
    final right = normalize(child);
    if (left.isEmpty) {
      return right;
    }
    if (right.isEmpty) {
      return left;
    }
    return '$left$separator$right';
  }

  /// 先查平铺键，再按 `.` 逐层下钻。与 JS 垫片 `readPath` 行为一致。
  static dynamic readFlat(Map<String, dynamic> variables, String path) {
    final key = path.trim();
    if (key.isEmpty) {
      return null;
    }
    if (variables.containsKey(key)) {
      return variables[key];
    }
    final normalized = normalize(key);
    if (normalized != key && variables.containsKey(normalized)) {
      return variables[normalized];
    }
    if (normalized.isEmpty) {
      return null;
    }
    // 逐层下钻：兼容卡片自己塞的嵌套对象。
    dynamic node = variables;
    for (final segment in normalized.split(separator)) {
      if (node is Map) {
        node = node[segment];
      } else {
        return null;
      }
    }
    return node;
  }

  /// 平铺键是否**直接**存在（不做下钻）。
  static bool containsFlat(Map<String, dynamic> variables, String path) {
    final key = path.trim();
    if (key.isEmpty) {
      return false;
    }
    if (variables.containsKey(key)) {
      return true;
    }
    final normalized = normalize(key);
    return normalized != key && variables.containsKey(normalized);
  }

  /// 把值转成数字。非数字返回 [fallback]。
  ///
  /// 与 `variable_provider.dart` 的 `_toNumber` 语义一致（解析失败 → 0），
  /// 但这里允许指定兜底值，因为「当前值不存在」和「当前值是 0」要区分开。
  static num toNumber(dynamic value, {num fallback = 0}) {
    if (value is num) {
      return value;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is String) {
      return num.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  static String _escapeSegment(String segment) {
    return segment.replaceAll('~', '~0').replaceAll('/', '~1');
  }

  static String _unescapeSegment(String segment) {
    return segment.replaceAll('~1', '/').replaceAll('~0', '~');
  }
}
