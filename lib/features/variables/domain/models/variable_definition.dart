import 'dart:convert';

import '../variable_path.dart';

/// 角色卡上携带的变量定义。
///
/// **存放位置**：`extensions.ykx_variables`，跟着卡走，导出时随 `extensions`
/// 一起进 chara_card_v2，再导入时原样回来。
///
/// **向后兼容的关键**：老卡没有这个字段 → [isActive] 为 false →
/// 变量功能整体不激活，聊天行为与加这个功能之前完全一致。
///
/// ```json
/// {
///   "version": 1,
///   "init": { "角色.好感度": 30, "角色.生命值": 82 },
///   "rules": "变量更新规则（自然语言，喂给模型看）",
///   "instruction": "追加给模型的更新指令（可空，空则由 rules 生成）"
/// }
/// ```
class VariableDefinition {
  const VariableDefinition({
    this.version = 1,
    this.init = const <String, dynamic>{},
    this.rules = '',
    this.instruction = '',
  });

  final int version;

  /// 初始值表。**始终是平铺键**（`角色.好感度`），嵌套结构在解析时会被展平。
  final Map<String, dynamic> init;

  /// 变量更新规则（自然语言）。
  final String rules;

  /// 完整的更新指令。为空时由 [buildInstruction] 按 [rules] 生成。
  final String instruction;

  /// 在 `extensions` 里的键名。
  static const String extensionsKey = 'ykx_variables';

  static const VariableDefinition empty = VariableDefinition();

  /// 是否激活变量功能。
  ///
  /// 三者全空 = 这张卡不玩变量 → 所有变量逻辑短路。
  bool get isActive =>
      init.isNotEmpty || rules.trim().isNotEmpty || instruction.trim().isNotEmpty;

  bool get hasInit => init.isNotEmpty;

  /// 变量路径清单（按插入顺序）。
  List<String> get paths => init.keys.toList(growable: false);

  static VariableDefinition? fromExtensions(Map<String, dynamic>? extensions) {
    if (extensions == null) {
      return null;
    }
    final raw = extensions[extensionsKey];
    if (raw is Map) {
      return VariableDefinition.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    // 也接受直接存 JSON 字符串的写法（手改卡 / 外部工具导出）。
    // ⛔ 这里原先两个分支都 `return null`，等于「注释说支持、实际不支持」的死分支。
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return VariableDefinition.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (_) {
        // 不是合法 JSON —— 当作「没有定义」，不影响其它逻辑。
      }
    }
    return null;
  }

  /// 便捷取定义（没有时返回 [empty]，不会返回 null）。
  static VariableDefinition of(Map<String, dynamic>? extensions) =>
      fromExtensions(extensions) ?? empty;

  /// 把定义写进一份 `extensions` 拷贝（不修改入参）。
  static Map<String, dynamic> attach(
    Map<String, dynamic>? extensions,
    VariableDefinition definition,
  ) {
    final next = <String, dynamic>{
      ...?extensions?.map((key, value) => MapEntry(key.toString(), value)),
    };
    if (!definition.isActive) {
      next.remove(extensionsKey);
    } else {
      next[extensionsKey] = definition.toJson();
    }
    return next;
  }

  VariableDefinition copyWith({
    int? version,
    Map<String, dynamic>? init,
    String? rules,
    String? instruction,
  }) {
    return VariableDefinition(
      version: version ?? this.version,
      init: init ?? this.init,
      rules: rules ?? this.rules,
      instruction: instruction ?? this.instruction,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'init': init,
        if (rules.trim().isNotEmpty) 'rules': rules,
        if (instruction.trim().isNotEmpty) 'instruction': instruction,
      };

  factory VariableDefinition.fromJson(Map<String, dynamic> json) {
    return VariableDefinition(
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '') ?? 1,
      init: flattenInit(json['init'] ?? json['variables'] ?? json['初始值']),
      rules: (json['rules'] ?? json['规则'] ?? '').toString().trim(),
      instruction: (json['instruction'] ?? json['指令'] ?? '').toString().trim(),
    );
  }

  /// 把任意形状的初始值结构**展平成平铺键**。
  ///
  /// MVU 的 `[InitVar]` 是 YAML 嵌套结构（`角色:\n  好感度: 30`），
  /// 而我们的存储是平铺的（`角色.好感度`）。这里统一转换，让两种来源都能用。
  ///
  /// 已经是平铺键的（键里带 `.`）原样保留，不重复展开。
  static Map<String, dynamic> flattenInit(dynamic raw) {
    final result = <String, dynamic>{};
    if (raw is! Map) {
      return result;
    }
    void walk(Map<dynamic, dynamic> node, String prefix) {
      node.forEach((key, value) {
        final name = key.toString().trim();
        if (name.isEmpty) {
          return;
        }
        final path = prefix.isEmpty ? name : '$prefix.$name';
        if (value is Map && value.isNotEmpty) {
          walk(value, path);
          return;
        }
        result[VariablePath.normalize(path)] = value;
      });
    }

    walk(raw, '');
    result.remove('');
    return result;
  }

  /// 生成给模型的变量更新指令。
  ///
  /// [currentValues] 是当前会话里的实际值 —— 把它一并喂进去，
  /// 模型才知道「现在是多少」从而算出正确的新值。
  ///
  /// [withValues] 为 false 时只给路径不给值（省 token）。
  String buildInstruction({
    Map<String, dynamic> currentValues = const <String, dynamic>{},
    bool withValues = true,
  }) {
    final explicit = instruction.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    if (!isActive) {
      return '';
    }

    final buffer = StringBuffer()
      ..writeln('【变量更新】')
      ..writeln('每次回复的**最末尾**必须输出一个变量更新块（不要放进代码块、不要省略）：')
      ..writeln()
      ..writeln('<UpdateVariable>')
      ..writeln('<Analysis>本次变化的一句话原因</Analysis>')
      ..writeln('<JSONPatch>')
      ..writeln('[{"op":"replace","path":"/路径/子路径","value":新值}]')
      ..writeln('</JSONPatch>')
      ..writeln('</UpdateVariable>')
      ..writeln()
      ..writeln('可用操作：')
      ..writeln('- replace：把变量设为指定值')
      ..writeln('- increment：在当前值上增减（value 为增量，可为负数）')
      ..writeln('- remove：删除变量')
      ..writeln('path 用 JSON Pointer 写法（以 / 分隔）；没有变化时输出空数组 []。');

    final paths = init.keys.toList(growable: false);
    if (paths.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('可更新的变量：');
      for (final path in paths) {
        if (!withValues) {
          buffer.writeln('- $path');
          continue;
        }
        final hasCurrent = VariablePath.containsFlat(currentValues, path);
        final current = hasCurrent
            ? VariablePath.readFlat(currentValues, path)
            : init[path];
        buffer.writeln('- $path（当前：${_display(current)}）');
      }
    }

    final rulesText = rules.trim();
    if (rulesText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('更新规则：')
        ..writeln(rulesText);
    }

    return buffer.toString().trim();
  }

  static String _display(dynamic value) {
    if (value == null) {
      return '未设置';
    }
    if (value is String) {
      return value.length > 40 ? '${value.substring(0, 40)}…' : value;
    }
    return value.toString();
  }

  @override
  String toString() =>
      'VariableDefinition(v$version, ${init.length} vars, rules=${rules.length}B)';
}
