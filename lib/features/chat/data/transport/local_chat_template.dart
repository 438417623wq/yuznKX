import '../../domain/models/chat_message.dart';

/// 本地 GGUF 模型的对话模板。
///
/// llama.cpp 不会替我们套用模型的 chat template，若直接拼
/// `User: ...\nAssistant:`，对 ChatML / Llama3 / Gemma 等模型会显著掉质量。
/// 这里按模型名自动推断模板，也允许用户在连接参数里用 `chat_template` 覆盖。
enum LocalChatTemplate {
  auto('auto', '自动识别 (Auto)'),
  chatml('chatml', 'ChatML (Qwen / Yi / 通用)'),
  llama3('llama3', 'Llama 3 / 3.1'),
  gemma('gemma', 'Gemma / Gemma 2'),
  mistral('mistral', 'Mistral / Mixtral'),
  alpaca('alpaca', 'Alpaca'),
  vicuna('vicuna', 'Vicuna'),
  plain('plain', '纯文本 (Plain)');

  final String id;
  final String label;

  const LocalChatTemplate(this.id, this.label);

  static LocalChatTemplate fromId(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    for (final template in LocalChatTemplate.values) {
      if (template.id == value) {
        return template;
      }
    }
    return LocalChatTemplate.auto;
  }

  /// 根据模型文件名 / 路径推断模板。
  static LocalChatTemplate detectFromModelName(String modelPath) {
    final name = modelPath.toLowerCase();
    bool has(List<String> keywords) => keywords.any(name.contains);

    if (has(const ['llama-3', 'llama3', 'llama_3', 'hermes-3', 'hermes3'])) {
      return LocalChatTemplate.llama3;
    }
    if (has(const ['gemma'])) {
      return LocalChatTemplate.gemma;
    }
    if (has(const ['mixtral', 'mistral', 'zephyr', 'openchat'])) {
      return LocalChatTemplate.mistral;
    }
    if (has(const ['vicuna', 'wizardlm', 'wizard-lm'])) {
      return LocalChatTemplate.vicuna;
    }
    if (has(const ['alpaca'])) {
      return LocalChatTemplate.alpaca;
    }
    if (has(const [
      'qwen',
      'yi-',
      'chatglm',
      'internlm',
      'deepseek',
      'smollm',
      'phi-3',
      'phi3',
    ])) {
      return LocalChatTemplate.chatml;
    }
    return LocalChatTemplate.chatml;
  }
}

/// 把消息列表渲染成单个 prompt 字符串。
String buildLocalChatPrompt({
  required List<ChatMessage> messages,
  required LocalChatTemplate template,
  String? systemFallback,
}) {
  final normalized = <_LocalTurn>[];
  for (final message in messages) {
    final content = message.content;
    if (content.trim().isEmpty) {
      continue;
    }
    final role = message.role.trim().toLowerCase();
    final resolved = role == 'assistant'
        ? 'assistant'
        : (role == 'system' ? 'system' : 'user');
    normalized.add(_LocalTurn(role: resolved, content: content));
  }

  if (normalized.isEmpty) {
    normalized.add(
      _LocalTurn(
        role: 'user',
        content: (systemFallback?.trim().isNotEmpty ?? false)
            ? systemFallback!.trim()
            : '[Start of conversation]',
      ),
    );
  }

  switch (template) {
    case LocalChatTemplate.chatml:
      return _renderChatml(normalized);
    case LocalChatTemplate.llama3:
      return _renderLlama3(normalized);
    case LocalChatTemplate.gemma:
      return _renderGemma(normalized);
    case LocalChatTemplate.mistral:
      return _renderMistral(normalized);
    case LocalChatTemplate.alpaca:
      return _renderAlpaca(normalized);
    case LocalChatTemplate.vicuna:
      return _renderVicuna(normalized);
    case LocalChatTemplate.plain:
    case LocalChatTemplate.auto:
      return _renderPlain(normalized);
  }
}

class _LocalTurn {
  final String role;
  final String content;
  const _LocalTurn({required this.role, required this.content});
}

String _renderChatml(List<_LocalTurn> turns) {
  final buffer = StringBuffer();
  for (final turn in turns) {
    buffer.write('<|im_start|>${turn.role}\n${turn.content}<|im_end|>\n');
  }
  buffer.write('<|im_start|>assistant\n');
  return buffer.toString();
}

String _renderLlama3(List<_LocalTurn> turns) {
  final buffer = StringBuffer('<|begin_of_text|>');
  for (final turn in turns) {
    buffer.write(
      '<|start_header_id|>${turn.role}<|end_header_id|>\n\n'
      '${turn.content}<|eot_id|>',
    );
  }
  buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
  return buffer.toString();
}

String _renderGemma(List<_LocalTurn> turns) {
  final buffer = StringBuffer();
  for (final turn in turns) {
    final role = turn.role == 'assistant' ? 'model' : 'user';
    buffer.write('<start_of_turn>$role\n${turn.content}<end_of_turn>\n');
  }
  buffer.write('<start_of_turn>model\n');
  return buffer.toString();
}

String _renderMistral(List<_LocalTurn> turns) {
  final buffer = StringBuffer('<s>');
  final pendingUser = StringBuffer();
  var hasAssistantTurn = false;

  void flushUser() {
    if (pendingUser.isEmpty) {
      return;
    }
    buffer.write('[INST] ${pendingUser.toString()} [/INST]');
    pendingUser.clear();
  }

  for (final turn in turns) {
    if (turn.role == 'system') {
      if (pendingUser.isNotEmpty) {
        pendingUser.write('\n\n');
      }
      pendingUser.write(turn.content);
      continue;
    }
    if (turn.role == 'user') {
      if (hasAssistantTurn) {
        buffer.write('</s>');
        hasAssistantTurn = false;
      }
      if (pendingUser.isNotEmpty) {
        pendingUser.write('\n\n');
      }
      pendingUser.write(turn.content);
      continue;
    }
    flushUser();
    buffer.write(' ${turn.content}');
    hasAssistantTurn = true;
  }

  if (pendingUser.isNotEmpty || !hasAssistantTurn) {
    flushUser();
  }
  return buffer.toString();
}

String _renderAlpaca(List<_LocalTurn> turns) {
  final systemParts = <String>[];
  final instruction = StringBuffer();
  final response = StringBuffer();
  var inResponse = false;

  for (final turn in turns) {
    if (turn.role == 'system') {
      systemParts.add(turn.content);
      continue;
    }
    if (turn.role == 'user') {
      inResponse = false;
      if (instruction.isNotEmpty) {
        instruction.write('\n\n');
      }
      instruction.write(turn.content);
      continue;
    }
    inResponse = true;
    if (response.isNotEmpty) {
      response.write('\n\n');
    }
    response.write(turn.content);
  }

  final buffer = StringBuffer();
  final system = systemParts.join('\n\n').trim();
  if (system.isNotEmpty) {
    buffer.write('$system\n\n');
  }
  buffer.write('### Instruction:\n$instruction\n\n### Response:\n');
  if (inResponse && response.isNotEmpty) {
    buffer.write('$response\n\n### Instruction:\n\n### Response:\n');
  }
  return buffer.toString();
}

String _renderVicuna(List<_LocalTurn> turns) {
  final buffer = StringBuffer();
  for (final turn in turns) {
    if (turn.role == 'system') {
      buffer.write('${turn.content}\n');
      continue;
    }
    final label = turn.role == 'assistant' ? 'ASSISTANT' : 'USER';
    buffer.write('$label: ${turn.content}\n');
  }
  buffer.write('ASSISTANT:');
  return buffer.toString();
}

String _renderPlain(List<_LocalTurn> turns) {
  final buffer = StringBuffer();
  for (final turn in turns) {
    final label = switch (turn.role) {
      'assistant' => 'Assistant',
      'system' => 'System',
      _ => 'User',
    };
    buffer.writeln('$label: ${turn.content}');
  }
  buffer.write('Assistant:');
  return buffer.toString();
}
