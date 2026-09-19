import 'dart:convert';

import '../../variables/domain/models/variable_definition.dart';
import '../../variables/domain/variable_path.dart';
import '../domain/models/card_project.dart';

/// 打包结果。
class PackedVariables {
  const PackedVariables({
    required this.definition,
    required this.source,
    required this.initCount,
  });

  final VariableDefinition definition;

  /// 初值的来源：`variables_json` / `initvar_yaml` / `rules_only`。
  final String source;

  final int initCount;
}

/// 把工坊项目里的 MVU 产物组装成**运行时可用**的 `extensions.ykx_variables`。
///
/// **这是修掉当前最大漏洞的地方。**
/// 在此之前，`mvuSchemaText` / `mvuInitvarText` / `mvuUpdateRulesText` /
/// `mvuVariablesJson` 全项目只有三个消费方：喂给 AI 当上下文、本地质检比对、
/// 导出页展示 —— ⛔ **`worldbook_packager.dart` 里根本没有它们，
/// MVU 三件套从来没进过角色卡。** 所以导出的卡在聊天里读不到任何变量，
/// 前端面板永远显示兜底 0。
///
/// 组装策略（**不要求用户重新生成 MVU**）：
/// 1. `mvuInitvarText`（YAML）先铺底 —— 它是最完整的初始值来源；
/// 2. `mvuVariablesJson`（结构化表）覆盖上去 —— 它的 `path`/`initial` 更规范；
/// 3. `mvuUpdateRulesText` 直接作为 `rules` 喂给模型看。
class VariablePackager {
  const VariablePackager._();

  /// 组装。项目里没有任何变量信息时返回 null（不进卡 → 变量功能不激活）。
  static PackedVariables? build(CardProject project) {
    final fromYaml = parseInitvarYaml(project.mvuInitvarText);
    final fromJson = parseVariablesJson(project.mvuVariablesJson);

    // YAML 铺底，结构化表覆盖。
    final init = <String, dynamic>{...fromYaml, ...fromJson};
    final rules = project.mvuUpdateRulesText.trim();

    if (init.isEmpty && rules.isEmpty) {
      return null;
    }

    final source = fromJson.isNotEmpty
        ? 'variables_json'
        : (fromYaml.isNotEmpty ? 'initvar_yaml' : 'rules_only');

    return PackedVariables(
      definition: VariableDefinition(
        init: init,
        rules: rules,
      ),
      source: source,
      initCount: init.length,
    );
  }

  /// 解析结构化变量表（`mvuVariablesJson`）。
  ///
  /// 期望形如：
  /// ```json
  /// [{"path":"角色.好感度","type":"number","range":"0~100","initial":"35"}]
  /// ```
  static Map<String, dynamic> parseVariablesJson(String raw) {
    final result = <String, dynamic>{};
    final text = raw.trim();
    if (text.isEmpty || text == '[]') {
      return result;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return result;
    }
    if (decoded is! List) {
      return result;
    }

    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final path = (item['path'] ?? item['key'] ?? item['变量'] ?? '')
          .toString()
          .trim();
      if (path.isEmpty) {
        continue;
      }
      final initial = item['initial'] ?? item['value'] ?? item['default'] ??
          item['初始值'];
      if (initial == null) {
        continue;
      }
      final normalized = VariablePath.normalizeAny(path);
      if (normalized.isEmpty) {
        continue;
      }
      result[normalized] = coerce(initial);
    }
    return result;
  }

  /// 解析 `initvar.yaml`（轻量 YAML，只支持嵌套映射）。
  ///
  /// ```yaml
  /// 角色:
  ///   好感度: 30
  ///   生命值: 82
  /// 关系:
  ///   林昭:
  ///     好感度: 62
  /// ```
  ///
  /// ⛔ 只支持「缩进 + `键: 值`」这一种形态。列表、锚点、多行字符串都不认 ——
  /// 认不出来就跳过那一行，不抛异常。真实 MVU 卡用的就是这种简单结构。
  static Map<String, dynamic> parseInitvarYaml(String raw) {
    final result = <String, dynamic>{};
    final text = raw.trim();
    if (text.isEmpty) {
      return result;
    }

    final indents = <int>[];
    final keys = <String>[];

    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) {
        continue;
      }
      // 注释行整行跳过。
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        continue;
      }

      final indent = line.length - line.trimLeft().length;
      final colon = trimmed.indexOf(':');
      if (colon <= 0) {
        continue;
      }

      var key = trimmed.substring(0, colon).trim();
      key = _stripQuotes(key);
      if (key.isEmpty) {
        continue;
      }

      var valueText = trimmed.substring(colon + 1).trim();
      // 值里的行内注释（只在没被引号包住时才剥）。
      if (!valueText.startsWith('"') && !valueText.startsWith("'")) {
        final hash = valueText.indexOf(' #');
        if (hash > 0) {
          valueText = valueText.substring(0, hash).trim();
        }
      }

      // 回退到当前缩进对应的父级。
      while (indents.isNotEmpty && indents.last >= indent) {
        indents.removeLast();
        keys.removeLast();
      }

      final path = keys.isEmpty ? key : '${keys.join('.')}.$key';

      if (valueText.isEmpty) {
        // 是个父节点，压栈等子项。
        indents.add(indent);
        keys.add(key);
        continue;
      }

      final normalized = VariablePath.normalizeAny(path);
      if (normalized.isEmpty) {
        continue;
      }
      result[normalized] = coerce(_stripQuotes(valueText));
    }

    return result;
  }

  /// 把文本值转成合适的 Dart 类型。
  ///
  /// 数字字符串要变成数字 —— 否则 `add` 操作会从 0 起算而不是从当前值累加。
  static dynamic coerce(dynamic raw) {
    if (raw is num || raw is bool) {
      return raw;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) {
        return '';
      }
      final lower = text.toLowerCase();
      if (lower == 'true') {
        return true;
      }
      if (lower == 'false') {
        return false;
      }
      if (lower == 'null' || lower == '~') {
        return null;
      }
      final number = num.tryParse(text);
      if (number != null) {
        return number;
      }
      return text;
    }
    return raw;
  }

  static String _stripQuotes(String raw) {
    var text = raw.trim();
    if (text.length >= 2) {
      final first = text[0];
      final last = text[text.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        text = text.substring(1, text.length - 1);
      }
    }
    return text.trim();
  }
}
