import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api_connection/data/api_connection_provider.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/domain/models/chat_message.dart';
import '../domain/models/variable_definition.dart';
import '../domain/models/variable_update.dart';
import 'variable_command_parser.dart';

/// 兜底变量提取。
///
/// **为什么需要它**：主路径靠模型每轮自觉输出 `<UpdateVariable>` 块。
/// 强模型没问题，弱模型经常忘、或者格式写不对。用户选的是「两者都要」——
/// 所以本轮没解析到指令块时，额外发一次「只看变量变化」的小请求兜住。
///
/// ⛔ 三条硬约束：
/// 1. **异步、不阻塞**消息落库（调用方 fire-and-forget）；
/// 2. **失败只记日志**，绝不弹错误 —— 否则每轮都可能骚扰用户；
/// 3. 输出用 `_temperature = 0.3`，与材料拆解同一档（要的是稳定抽取，不是创作）。
class VariableExtractService {
  VariableExtractService(this._ref);

  final Ref _ref;

  static const double _temperature = 0.3;
  static const int _maxTokens = 900;

  /// 是否具备发起请求的条件（有 API 连接 + 卡上有变量定义）。
  bool canExtract(VariableDefinition definition) {
    if (!definition.isActive) {
      return false;
    }
    return _ref.read(activeApiConnectionProvider) != null;
  }

  /// 发起一次提取。返回识别到的操作（失败返回空列表，不抛异常）。
  ///
  /// [chatService] 由调用方传入 —— `chatServiceProvider` 定义在
  /// `chat_provider.dart`，从本文件引用它会形成循环 import。
  Future<List<VariableOp>> extract({
    required ChatService chatService,
    required String assistantReply,
    required VariableDefinition definition,
    required Map<String, dynamic> currentValues,
    String characterName = '',
  }) async {
    try {
      if (!definition.isActive || assistantReply.trim().isEmpty) {
        return const <VariableOp>[];
      }
      final connection = _ref.read(activeApiConnectionProvider);
      if (connection == null) {
        return const <VariableOp>[];
      }

      final prompt = buildPrompt(
        assistantReply: assistantReply,
        definition: definition,
        currentValues: currentValues,
        characterName: characterName,
      );

      final buffer = StringBuffer();

      await for (final event in chatService.streamMessage(
        connection: connection,
        messages: <ChatMessage>[
          ChatMessage(
            role: 'user',
            content: prompt,
            timestamp: DateTime.now(),
          ),
        ],
        parameters: <String, dynamic>{
          'temperature': _temperature,
          'max_tokens': _maxTokens,
        },
      )) {
        final text = event.text;
        if (text == null || text.isEmpty) {
          continue;
        }
        buffer.write(text);
      }

      return parseReply(buffer.toString());
    } catch (e) {
      // 静默 —— 提取失败不该让用户看见任何东西。
      print('Variable extract failed: $e');
      return const <VariableOp>[];
    }
  }

  /// 从模型回复里取出操作列表（复用主解析器的宽松降级链）。
  List<VariableOp> parseReply(String raw) {
    if (raw.trim().isEmpty) {
      return const <VariableOp>[];
    }
    final parsed = VariableCommandParser.parse(raw);
    return parsed.update?.ops ?? const <VariableOp>[];
  }

  /// 构造提取提示词。
  String buildPrompt({
    required String assistantReply,
    required VariableDefinition definition,
    required Map<String, dynamic> currentValues,
    String characterName = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('你是一个变量状态提取器。下面是一段角色扮演的回复，')
      ..writeln('请只提取这段回复**实际导致**的变量变化，不要补充、不要推测未发生的变化。')
      ..writeln();

    final paths = definition.init.keys.toList(growable: false);
    if (paths.isNotEmpty) {
      buffer.writeln('可更新的变量（当前值）：');
      for (final path in paths) {
        final hasCurrent = currentValues.containsKey(path);
        final value = hasCurrent ? currentValues[path] : definition.init[path];
        buffer.writeln('- $path = ${value ?? '未设置'}');
      }
      buffer.writeln();
    }

    final rules = definition.rules.trim();
    if (rules.isNotEmpty) {
      buffer
        ..writeln('变量更新规则：')
        ..writeln(rules)
        ..writeln();
    }

    buffer
      ..writeln('回复内容：')
      ..writeln('<<<')
      ..writeln(assistantReply.trim())
      ..writeln('>>>')
      ..writeln()
      ..writeln('只输出一个 JSON 数组，不要任何解释、不要代码块：')
      ..writeln('[{"op":"replace","path":"/角色/好感度","value":35}]')
      ..writeln()
      ..writeln('op 只能是 replace（设为）、increment（增减，value 为增量）、remove（删除）。')
      ..writeln('path 用 JSON Pointer 写法（以 / 分隔）。')
      ..writeln('这段回复没有造成任何变量变化时，输出 []。');

    return buffer.toString();
  }
}

/// 兜底提取服务 provider。
final variableExtractServiceProvider = Provider<VariableExtractService>(
  (ref) => VariableExtractService(ref),
);
