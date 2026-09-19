import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../character/domain/models/character.dart';
import '../domain/models/variable_definition.dart';
import '../domain/models/variable_update.dart';
import '../domain/variable_path.dart';
import 'variable_command_parser.dart';
import 'variable_provider.dart';

/// 变量管道的运行时。
///
/// **这是整个变量功能的地基** —— 在这之前，模型输出里的变量指令块没有任何
/// 运行时消费方（`_replaceMacros` 只在**输入侧**执行，模型自己吐的
/// `{{setvar::...}}` 只会原样显示）。本类补上「模型输出 → 解析 → 写库 →
/// 从显示剥离」这条管道，做法照搬记忆模块的 `processCommands`。
///
/// 三件事：
/// 1. [ensureInitialized]：会话变量为空时，用卡上的 `init` 灌初值
/// 2. [processCommands]：解析模型输出里的指令块 → 应用 → 返回剥离后的内容
/// 3. [buildInstruction]：生成给模型的更新指令（含当前值，供深度注入）
class VariableRuntime {
  VariableRuntime(this._ref);

  final Ref _ref;

  /// 已应用过的轮次，用于 [VariableOpType.add] / [VariableOpType.delete] 的去重。
  ///
  /// ⛔ `set` 幂等，`add` / `delete` **不是** —— 同一轮回复被处理两次会让
  /// 数值翻倍、或删掉本不该删的键。所以必须按轮次去重。
  final Set<String> _appliedTurns = <String>{};

  /// 去重键的插入顺序，用于把集合限制在有限大小内。
  final List<String> _appliedTurnOrder = <String>[];

  static const int _maxTrackedTurns = 200;

  /// 取角色卡上的变量定义（没有则返回 [VariableDefinition.empty]）。
  VariableDefinition definitionOf(Character? character) =>
      VariableDefinition.of(character?.rawExtensions);

  /// 该角色卡是否启用了变量功能。
  bool isActive(Character? character) => definitionOf(character).isActive;

  /// 会话变量为空时，用卡上的 `init` 灌入初始值。
  ///
  /// **只在为空时执行** —— 否则每次进入会话都会覆盖用户 / AI 已经改过的值。
  /// 返回写入的条数（0 表示没动）。
  int ensureInitialized({
    required String sessionId,
    required Character? character,
  }) {
    final definition = definitionOf(character);
    if (!definition.hasInit) {
      return 0;
    }
    final current = _ref.read(chatVariablesProvider(sessionId));
    if (current.isNotEmpty) {
      return 0;
    }
    final notifier = _ref.read(chatVariablesProvider(sessionId).notifier);
    for (final entry in definition.init.entries) {
      notifier.setValue(entry.key, entry.value);
    }
    return definition.init.length;
  }

  /// 强制把会话变量重置为角色卡上的初值（清空 + 灌入）。
  ///
  /// 与 [ensureInitialized] 的区别：那个是「只在为空时」自动执行，这个是
  /// 用户在变量管理页**主动点按钮**时用的 —— 他就是要推倒重来。
  int resetToCardInitial({
    required String sessionId,
    required Character? character,
  }) {
    final definition = definitionOf(character);
    if (!definition.hasInit) {
      return 0;
    }
    final notifier = _ref.read(chatVariablesProvider(sessionId).notifier);
    notifier.clearAll();
    for (final entry in definition.init.entries) {
      notifier.setValue(entry.key, entry.value);
    }
    return definition.init.length;
  }

  /// 把一批操作应用到会话变量。返回实际应用的条数。
  ///
  /// [VariableOpType.add] 作用在**不存在的键**上时，等价于「设为该数值」
  /// （`addValue` 从 0 起算），这正是新建变量的期望行为。
  int applyOps(String sessionId, List<VariableOp> ops) {
    if (ops.isEmpty) {
      return 0;
    }
    final notifier = _ref.read(chatVariablesProvider(sessionId).notifier);
    var applied = 0;

    for (final op in ops) {
      if (!op.isValid) {
        continue;
      }
      switch (op.type) {
        case VariableOpType.set:
          notifier.setValue(op.path, op.value);
          applied++;
        case VariableOpType.add:
          final delta = VariablePath.toNumber(op.value);
          if (delta == 0) {
            // 增量为 0 是无意义操作，跳过（也避免把「未设置」误写成 0）。
            continue;
          }
          notifier.addValue(op.path, delta);
          applied++;
        case VariableOpType.delete:
          notifier.deleteValue(op.path);
          applied++;
      }
    }
    return applied;
  }

  /// 解析 [content] 里的变量指令块，应用并返回剥离后的内容。
  ///
  /// [allowWrites] 为 false 时**只剥离不落库**（会话已切换 / 开关关闭）——
  /// 剥离是显示层的事，与是否写库无关。
  VariableProcessResult processCommands(
    String content, {
    required String sessionId,
    required Character? character,
    required bool allowWrites,
    int? messageIndex,
  }) {
    try {
      final definition = definitionOf(character);
      if (!definition.isActive) {
        return VariableProcessResult.untouched(content);
      }

      final parsed = VariableCommandParser.parse(content);
      if (!parsed.matched) {
        return VariableProcessResult.untouched(content);
      }

      final stripped = parsed.stripFrom(content);
      final format = parsed.update?.format ?? '';

      if (!allowWrites) {
        return VariableProcessResult(
          content: stripped,
          applied: 0,
          matched: true,
          format: format,
          strippedOnly: true,
        );
      }

      final turnKey = _turnKey(sessionId, messageIndex, content);
      if (_appliedTurns.contains(turnKey)) {
        return VariableProcessResult(
          content: stripped,
          applied: 0,
          matched: true,
          format: format,
          duplicate: true,
        );
      }
      _rememberTurn(turnKey);

      final applied = applyOps(sessionId, parsed.update?.ops ?? const <VariableOp>[]);
      return VariableProcessResult(
        content: stripped,
        applied: applied,
        matched: true,
        format: format,
      );
    } catch (_) {
      // 变量处理出问题不该影响聊天 —— 原样返回。
      return VariableProcessResult.untouched(content);
    }
  }

  /// 生成给模型的变量更新指令（含当前值）。
  ///
  /// 卡上没有变量定义时返回空串 —— 调用方据此跳过注入。
  String buildInstruction({
    required String sessionId,
    required Character? character,
  }) {
    final definition = definitionOf(character);
    if (!definition.isActive) {
      return '';
    }
    final current = _ref.read(chatVariablesProvider(sessionId));
    return definition.buildInstruction(currentValues: current);
  }

  /// 当前会话的变量快照（只读）。
  Map<String, dynamic> snapshotOf(String sessionId) =>
      _ref.read(chatVariablesProvider(sessionId));

  /// 清空去重记录。手动「重新处理本轮」之类的高级操作会用上。
  void resetDeduplication() {
    _appliedTurns.clear();
    _appliedTurnOrder.clear();
  }

  String _turnKey(String sessionId, int? messageIndex, String content) {
    // 内容哈希让「同一轮被重复处理」能被识别出来，同时避免把不同轮次
    // 里内容恰好相同的两条消息误判为重复（messageIndex 参与了键）。
    return '$sessionId|${messageIndex ?? -1}|${content.hashCode}';
  }

  void _rememberTurn(String key) {
    _appliedTurns.add(key);
    _appliedTurnOrder.add(key);
    while (_appliedTurnOrder.length > _maxTrackedTurns) {
      final oldest = _appliedTurnOrder.removeAt(0);
      _appliedTurns.remove(oldest);
    }
  }
}

/// 一次变量处理的结果。
class VariableProcessResult {
  const VariableProcessResult({
    required this.content,
    required this.applied,
    required this.matched,
    required this.format,
    this.duplicate = false,
    this.strippedOnly = false,
  });

  /// 处理后的内容（指令块已剥离）。
  final String content;

  /// 实际写入的变量条数。
  final int applied;

  /// 是否命中过指令块格式。
  ///
  /// 兜底提取的触发条件用这个：命中了（哪怕是空数组）就不必再发提取请求。
  final bool matched;

  /// 命中的格式名（`json_patch` / `cn_tag` / `json_array` / `macro`）。
  final String format;

  /// 是否因轮次去重而跳过写入。
  final bool duplicate;

  /// 是否只剥离、未写入（会话已切换或开关关闭）。
  final bool strippedOnly;

  /// 内容完全没被动过。
  bool get untouchedContent => !matched;

  bool get didWrite => applied > 0;

  const VariableProcessResult.untouched(this.content)
      : applied = 0,
        matched = false,
        format = '',
        duplicate = false,
        strippedOnly = false;

  @override
  String toString() => 'VariableProcessResult(applied=$applied, '
      'format=$format, duplicate=$duplicate, strippedOnly=$strippedOnly)';
}

/// 变量运行时 provider。
final variableRuntimeProvider = Provider<VariableRuntime>(
  (ref) => VariableRuntime(ref),
);
