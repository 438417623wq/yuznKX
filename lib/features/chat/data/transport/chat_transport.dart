import 'dart:convert';

import '../../../api_connection/domain/models/api_connection.dart';
import '../../domain/models/chat_message.dart';

/// ===========================================================================
/// 传输层（Transport Layer）
///
/// 目标：把「用哪个协议说话」从 ChatService 的 HTTP 流程里剥离出来。
/// 每个 Adapter 负责：
///   1. endpoint 拼接
///   2. headers / 鉴权
///   3. 请求体构造（含参数映射）
///   4. 流式 payload 解析
///   5. 非流式响应解析
///
/// ChatService 只负责：重试、取消、SSE 分行、错误格式化。
/// ===========================================================================

/// 服务端返回的 token 用量。
class ChatUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const ChatUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  static ChatUsage? fromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(raw);

    int? read(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is num) {
          return value.toInt();
        }
      }
      return null;
    }

    final prompt = read(
      const ['prompt_tokens', 'promptTokenCount', 'input_tokens'],
    );
    final completion = read(
      const ['completion_tokens', 'candidatesTokenCount', 'output_tokens'],
    );
    final total = read(
      const ['total_tokens', 'totalTokenCount'],
    );

    if (prompt == null && completion == null && total == null) {
      return null;
    }

    return ChatUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total ?? ((prompt ?? 0) + (completion ?? 0)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (completionTokens != null) 'completion_tokens': completionTokens,
        if (totalTokens != null) 'total_tokens': totalTokens,
      };

  /// 流式累加：把后续 chunk 的用量合并进来（Anthropic/Gemini 分多次下发）。
  ChatUsage merge(ChatUsage? other) {
    if (other == null) {
      return this;
    }
    return ChatUsage(
      promptTokens: other.promptTokens ?? promptTokens,
      completionTokens: other.completionTokens ?? completionTokens,
      totalTokens: other.totalTokens ?? totalTokens,
    );
  }
}

/// 流式增量事件。
class ChatStreamEvent {
  final String? text;
  final ChatUsage? usage;
  final String? finishReason;

  const ChatStreamEvent({
    this.text,
    this.usage,
    this.finishReason,
  });

  bool get isEmpty =>
      (text == null || text!.isEmpty) && usage == null && finishReason == null;
}

/// 非流式结果。
class ChatCompletionResult {
  final String text;
  final ChatUsage? usage;
  final String? finishReason;

  const ChatCompletionResult({
    required this.text,
    this.usage,
    this.finishReason,
  });
}

/// 从任意错误响应体里抽出可读错误信息。
String? extractApiErrorMessage(Map<String, dynamic> map) {
  final error = map['error'];
  if (error is String && error.trim().isNotEmpty) {
    return error.trim();
  }
  if (error is Map) {
    final errorMap = Map<String, dynamic>.from(error);
    final message = errorMap['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    final type = errorMap['type'];
    if (type is String && type.trim().isNotEmpty) {
      return type.trim();
    }
  }

  final message = map['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message.trim();
  }
  return null;
}

/// 把任意 content 形态（string / list / map）拍平成文本。
String contentToText(dynamic content) {
  if (content == null) {
    return '';
  }
  if (content is String) {
    return content;
  }
  if (content is num || content is bool) {
    return content.toString();
  }
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is String) {
        buffer.write(item);
        continue;
      }
      if (item is Map) {
        final mapItem = Map<String, dynamic>.from(item);
        final text = mapItem['text'];
        if (text != null) {
          buffer.write(text.toString());
          continue;
        }
        final nested = mapItem['content'];
        if (nested != null) {
          buffer.write(contentToText(nested));
        }
      }
    }
    return buffer.toString();
  }
  if (content is Map) {
    final mapContent = Map<String, dynamic>.from(content);
    if (mapContent['text'] != null) {
      return mapContent['text'].toString();
    }
    if (mapContent['content'] != null) {
      return contentToText(mapContent['content']);
    }
  }
  return '';
}

/// ---------------------------------------------------------------------------
/// Adapter 基类
/// ---------------------------------------------------------------------------
abstract class ChatProtocolAdapter {
  const ChatProtocolAdapter();

  /// 调试用标识。
  String get id;

  /// 本地推理（不走 HTTP）。
  bool get isLocal => false;

  /// 是否走 SSE 流式。
  bool get supportsStreaming => true;

  /// 该协议的默认上下文窗口（连接未显式配置时使用）。
  int get defaultContextSize;

  Uri buildUri(
    ApiConnection connection, {
    required bool stream,
    String? model,
  });

  Map<String, String> buildHeaders(
    ApiConnection connection, {
    required bool stream,
  });

  Map<String, dynamic> buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  });

  /// 解析一条 SSE `data:` 负载。允许返回多条事件（Anthropic 会一条带多个字段）。
  List<ChatStreamEvent> parseStreamPayload(String payload);

  /// 解析非流式响应体。
  ChatCompletionResult parseResponse(dynamic data);

  /// 从流式/非流式负载里抽取 usage（部分协议 usage 在独立事件里）。
  ChatUsage? extractUsage(dynamic payload) => null;
}

/// ---------------------------------------------------------------------------
/// 公共工具
/// ---------------------------------------------------------------------------
String normalizeBaseUrl(String rawBaseUrl) {
  var baseUrl = rawBaseUrl.trim();
  if (baseUrl.isEmpty) {
    throw Exception('Base URL is empty.');
  }
  while (baseUrl.endsWith('/')) {
    baseUrl = baseUrl.substring(0, baseUrl.length - 1);
  }
  if (baseUrl.isEmpty) {
    throw Exception('Base URL is empty.');
  }
  return baseUrl;
}

double? _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

List<String>? _asStringList(dynamic value) {
  if (value is List) {
    final items = <String>[];
    for (final item in value) {
      final text = item?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        items.add(text);
      }
    }
    return items.isEmpty ? null : items;
  }
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return null;
}

/// 本地推理专属参数，任何远程协议都不应收到。
const Set<String> localOnlyParameterKeys = <String>{
  'context_size',
  'n_threads',
  'n_batch',
  'flash_attn',
  'n_ctx',
  'n_gpu_layers',
};

/// Gemini 安全阈值：全类目关闭拦截，与酒馆一致。
///
/// 若某个自定义 Gemini 端点报 `Invalid value at safety_settings[...]`
/// （多为老版本 v1beta 不认 `HARM_CATEGORY_CIVIC_INTEGRITY`），
/// 删掉最后一条即可。
const List<Map<String, String>> geminiSafetySettings = <Map<String, String>>[
  <String, String>{
    'category': 'HARM_CATEGORY_HARASSMENT',
    'threshold': 'BLOCK_NONE',
  },
  <String, String>{
    'category': 'HARM_CATEGORY_HATE_SPEECH',
    'threshold': 'BLOCK_NONE',
  },
  <String, String>{
    'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    'threshold': 'BLOCK_NONE',
  },
  <String, String>{
    'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
    'threshold': 'BLOCK_NONE',
  },
  <String, String>{
    'category': 'HARM_CATEGORY_CIVIC_INTEGRITY',
    'threshold': 'BLOCK_NONE',
  },
];

/// ---------------------------------------------------------------------------
/// 1) OpenAI 兼容（/chat/completions）
/// ---------------------------------------------------------------------------
class OpenAiChatCompletionsAdapter extends ChatProtocolAdapter {
  const OpenAiChatCompletionsAdapter();

  @override
  String get id => 'openai.chat_completions';

  @override
  int get defaultContextSize => 8192;

  @override
  Uri buildUri(
    ApiConnection connection, {
    required bool stream,
    String? model,
  }) {
    final baseUrl = normalizeBaseUrl(connection.baseUrl);
    return Uri.parse('$baseUrl/chat/completions');
  }

  @override
  Map<String, String> buildHeaders(
    ApiConnection connection, {
    required bool stream,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (stream) {
      headers['Accept'] = 'text/event-stream';
    }
    final key = connection.apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }
    return headers;
  }

  @override
  Map<String, dynamic> buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'messages': serializeChatMessages(messages),
      'stream': stream,
    };

    final params = parameters ?? const <String, dynamic>{};
    final includeUsage = params['include_usage'] != false;

    for (final entry in params.entries) {
      final key = entry.key;
      if (entry.value == null ||
          localOnlyParameterKeys.contains(key) ||
          key == 'include_usage') {
        continue;
      }
      if (key == 'stop') {
        final stops = _asStringList(entry.value);
        if (stops != null) {
          body['stop'] = stops;
        }
        continue;
      }
      body[key] = entry.value;
    }

    if (stream && includeUsage) {
      body['stream_options'] = <String, dynamic>{'include_usage': true};
    }

    return body;
  }

  @override
  List<ChatStreamEvent> parseStreamPayload(String payload) {
    final parsed = _tryDecode(payload);
    if (parsed == null) {
      return const <ChatStreamEvent>[];
    }

    final errorMessage = extractApiErrorMessage(parsed);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final events = <ChatStreamEvent>[];

    final choices = parsed['choices'];
    if (choices is List && choices.isNotEmpty) {
      final firstChoice = choices.first;
      if (firstChoice is Map) {
        final firstMap = Map<String, dynamic>.from(firstChoice);
        final delta = firstMap['delta'];
        if (delta is Map) {
          final deltaMap = Map<String, dynamic>.from(delta);
          final deltaText = contentToText(deltaMap['content']);
          if (deltaText.isNotEmpty) {
            events.add(ChatStreamEvent(text: deltaText));
          }
          final reasoning = contentToText(
            deltaMap['reasoning_content'] ?? deltaMap['reasoning'],
          );
          if (reasoning.isNotEmpty) {
            events.add(
              ChatStreamEvent(text: reasoning),
            );
          }
          final directDeltaText = contentToText(deltaMap['text']);
          if (directDeltaText.isNotEmpty) {
            events.add(ChatStreamEvent(text: directDeltaText));
          }
        }

        final text = contentToText(firstMap['text']);
        if (text.isNotEmpty) {
          events.add(ChatStreamEvent(text: text));
        }

        final message = firstMap['message'];
        if (message is Map) {
          final messageText = contentToText(
            Map<String, dynamic>.from(message)['content'],
          );
          if (messageText.isNotEmpty) {
            events.add(ChatStreamEvent(text: messageText));
          }
        }

        final finishReason = firstMap['finish_reason'];
        if (finishReason is String && finishReason.trim().isNotEmpty) {
          events.add(ChatStreamEvent(finishReason: finishReason.trim()));
        }
      }
    }

    final topDelta = parsed['delta'];
    if (topDelta is Map) {
      final deltaText = contentToText(
        Map<String, dynamic>.from(topDelta)['text'],
      );
      if (deltaText.isNotEmpty) {
        events.add(ChatStreamEvent(text: deltaText));
      }
    }

    final usage = ChatUsage.fromJson(parsed['usage']);
    if (usage != null) {
      events.add(ChatStreamEvent(usage: usage));
    }

    return events;
  }

  @override
  ChatCompletionResult parseResponse(dynamic data) {
    if (data is! Map) {
      return const ChatCompletionResult(text: '');
    }
    final map = Map<String, dynamic>.from(data);

    final errorMessage = extractApiErrorMessage(map);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final usage = ChatUsage.fromJson(map['usage']);
    String? finishReason;
    var text = '';

    final choices = map['choices'];
    if (choices is List && choices.isNotEmpty) {
      final firstChoice = choices.first;
      if (firstChoice is Map) {
        final choiceMap = Map<String, dynamic>.from(firstChoice);
        final rawFinish = choiceMap['finish_reason'];
        if (rawFinish is String && rawFinish.trim().isNotEmpty) {
          finishReason = rawFinish.trim();
        }

        final message = choiceMap['message'];
        if (message is Map) {
          text = contentToText(
            Map<String, dynamic>.from(message)['content'],
          );
        }
        if (text.isEmpty) {
          text = contentToText(choiceMap['text']);
        }
      }
    }

    if (text.isEmpty) {
      text = contentToText(map['content']);
    }

    if (text.isEmpty) {
      text = _extractGeminiLikeText(map);
    }

    return ChatCompletionResult(
      text: text,
      usage: usage,
      finishReason: finishReason,
    );
  }

  @override
  ChatUsage? extractUsage(dynamic payload) {
    if (payload is Map) {
      return ChatUsage.fromJson(Map<String, dynamic>.from(payload)['usage']);
    }
    return null;
  }
}

/// ---------------------------------------------------------------------------
/// 2) Anthropic Messages（/v1/messages）
/// ---------------------------------------------------------------------------
class AnthropicMessagesAdapter extends ChatProtocolAdapter {
  const AnthropicMessagesAdapter();

  static const String _apiVersion = '2023-06-01';

  @override
  String get id => 'anthropic.messages';

  @override
  int get defaultContextSize => 200000;

  @override
  Uri buildUri(
    ApiConnection connection, {
    required bool stream,
    String? model,
  }) {
    final baseUrl = normalizeBaseUrl(connection.baseUrl);
    final resolved = baseUrl.endsWith('/v1') ? baseUrl : '$baseUrl/v1';
    return Uri.parse('$resolved/messages');
  }

  @override
  Map<String, String> buildHeaders(
    ApiConnection connection, {
    required bool stream,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'anthropic-version': _apiVersion,
    };
    if (stream) {
      headers['Accept'] = 'text/event-stream';
    }
    final key = connection.apiKey.trim();
    if (key.isNotEmpty) {
      headers['x-api-key'] = key;
    }
    return headers;
  }

  @override
  Map<String, dynamic> buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  }) {
    final params = parameters ?? const <String, dynamic>{};

    final systemBuffer = StringBuffer();
    final chatMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      final role = message.role.trim().toLowerCase();
      final content = message.content;
      if (content.trim().isEmpty) {
        continue;
      }

      if (role == 'system') {
        if (systemBuffer.isNotEmpty) {
          systemBuffer.write('\n\n');
        }
        systemBuffer.write(content);
        continue;
      }

      final anthropicRole = role == 'assistant' ? 'assistant' : 'user';
      if (chatMessages.isNotEmpty &&
          chatMessages.last['role'] == anthropicRole) {
        chatMessages.last['content'] =
            '${chatMessages.last['content']}\n\n$content';
        continue;
      }

      chatMessages.add(<String, dynamic>{
        'role': anthropicRole,
        'content': content,
      });
    }

    // Anthropic 要求首条消息必须是 user。旧实现把开场的 assistant 问候语
    // 整条丢掉，模型因此看不到角色的开场白 —— 新会话里这会明显表现为
    // 「没按角色设定来」。改为在前面补一个占位 user 轮次，把问候语原样保留。
    if (chatMessages.isNotEmpty && chatMessages.first['role'] != 'user') {
      chatMessages.insert(0, <String, dynamic>{
        'role': 'user',
        'content': '[Start of conversation]',
      });
    }
    if (chatMessages.isEmpty) {
      chatMessages.add(<String, dynamic>{
        'role': 'user',
        'content': '[Start of conversation]',
      });
    }

    final maxTokens = _asInt(params['max_tokens']) ?? 2048;

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens.clamp(1, 64000),
      'messages': chatMessages,
      'stream': stream,
    };

    final system = systemBuffer.toString().trim();
    if (system.isNotEmpty) {
      body['system'] = system;
    }

    final temperature = _asDouble(params['temperature']);
    if (temperature != null) {
      body['temperature'] = temperature.clamp(0.0, 1.0);
    }

    final topP = _asDouble(params['top_p']);
    if (topP != null) {
      body['top_p'] = topP.clamp(0.0, 1.0);
    }

    final topK = _asInt(params['top_k']);
    if (topK != null && topK > 0) {
      body['top_k'] = topK;
    }

    final stops = _asStringList(params['stop']);
    if (stops != null) {
      body['stop_sequences'] = stops;
    }

    // frequency_penalty / presence_penalty / repetition_penalty 为 OpenAI 专有，
    // Anthropic 不支持，直接忽略。
    return body;
  }

  @override
  List<ChatStreamEvent> parseStreamPayload(String payload) {
    final parsed = _tryDecode(payload);
    if (parsed == null) {
      return const <ChatStreamEvent>[];
    }

    final type = parsed['type']?.toString() ?? '';
    final events = <ChatStreamEvent>[];

    switch (type) {
      case 'error':
        final error = parsed['error'];
        if (error is Map) {
          final message =
              Map<String, dynamic>.from(error)['message']?.toString() ?? '';
          throw Exception(
            message.trim().isEmpty ? 'Anthropic stream error.' : message,
          );
        }
        throw Exception('Anthropic stream error.');

      case 'content_block_delta':
        final delta = parsed['delta'];
        if (delta is Map) {
          final deltaMap = Map<String, dynamic>.from(delta);
          final text = contentToText(
            deltaMap['text'] ?? deltaMap['partial_json'],
          );
          if (text.isNotEmpty) {
            events.add(ChatStreamEvent(text: text));
          }
        }
        break;

      case 'message_start':
        final message = parsed['message'];
        if (message is Map) {
          final usage = ChatUsage.fromJson(
            Map<String, dynamic>.from(message)['usage'],
          );
          if (usage != null) {
            events.add(ChatStreamEvent(usage: usage));
          }
        }
        break;

      case 'message_delta':
        final delta = parsed['delta'];
        if (delta is Map) {
          final stopReason =
              Map<String, dynamic>.from(delta)['stop_reason']?.toString() ?? '';
          if (stopReason.trim().isNotEmpty) {
            events.add(ChatStreamEvent(finishReason: stopReason.trim()));
          }
        }
        final usage = ChatUsage.fromJson(parsed['usage']);
        if (usage != null) {
          events.add(ChatStreamEvent(usage: usage));
        }
        break;

      default:
        break;
    }

    return events;
  }

  @override
  ChatCompletionResult parseResponse(dynamic data) {
    if (data is! Map) {
      return const ChatCompletionResult(text: '');
    }
    final map = Map<String, dynamic>.from(data);

    final type = map['type']?.toString() ?? '';
    if (type == 'error') {
      final message = extractApiErrorMessage(map) ?? 'Anthropic request failed.';
      throw Exception(message);
    }

    final errorMessage = extractApiErrorMessage(map);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final buffer = StringBuffer();
    final content = map['content'];
    if (content is List) {
      for (final block in content) {
        if (block is Map) {
          final blockMap = Map<String, dynamic>.from(block);
          if (blockMap['type']?.toString() == 'text') {
            buffer.write(blockMap['text']?.toString() ?? '');
          }
        }
      }
    }
    if (buffer.isEmpty) {
      buffer.write(contentToText(map['content']));
    }

    return ChatCompletionResult(
      text: buffer.toString(),
      usage: ChatUsage.fromJson(map['usage']),
      finishReason: map['stop_reason']?.toString(),
    );
  }

  @override
  ChatUsage? extractUsage(dynamic payload) {
    if (payload is Map) {
      return ChatUsage.fromJson(Map<String, dynamic>.from(payload)['usage']);
    }
    return null;
  }
}

/// ---------------------------------------------------------------------------
/// 3) Google Gemini（generateContent / streamGenerateContent）
/// ---------------------------------------------------------------------------
class GeminiGenerateContentAdapter extends ChatProtocolAdapter {
  const GeminiGenerateContentAdapter();

  @override
  String get id => 'google.gemini_generate_content';

  @override
  int get defaultContextSize => 32768;

  String _resolveModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return 'gemini-1.5-flash';
    }
    return trimmed.startsWith('models/')
        ? trimmed.substring('models/'.length)
        : trimmed;
  }

  @override
  Uri buildUri(
    ApiConnection connection, {
    required bool stream,
    String? model,
  }) {
    final baseUrl = normalizeBaseUrl(connection.baseUrl);
    final resolved = baseUrl.endsWith('/v1beta') || baseUrl.endsWith('/v1')
        ? baseUrl
        : '$baseUrl/v1beta';
    final resolvedModel = _resolveModel(model ?? connection.model);
    if (stream) {
      return Uri.parse(
        '$resolved/models/$resolvedModel:streamGenerateContent?alt=sse',
      );
    }
    return Uri.parse('$resolved/models/$resolvedModel:generateContent');
  }

  @override
  Map<String, String> buildHeaders(
    ApiConnection connection, {
    required bool stream,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (stream) {
      headers['Accept'] = 'text/event-stream';
    }
    final key = connection.apiKey.trim();
    if (key.isNotEmpty) {
      headers['x-goog-api-key'] = key;
    }
    return headers;
  }

  @override
  Map<String, dynamic> buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  }) {
    final params = parameters ?? const <String, dynamic>{};

    final contents = <Map<String, dynamic>>[];
    final systemBuffer = StringBuffer();

    for (final message in messages) {
      final role = message.role.trim().toLowerCase();
      final content = message.content;
      if (content.trim().isEmpty) {
        continue;
      }

      if (role == 'system') {
        if (systemBuffer.isNotEmpty) {
          systemBuffer.write('\n\n');
        }
        systemBuffer.write(content);
        continue;
      }

      final geminiRole = role == 'assistant' ? 'model' : 'user';
      if (contents.isNotEmpty && contents.last['role'] == geminiRole) {
        final parts = contents.last['parts'] as List<dynamic>;
        parts.add(<String, dynamic>{'text': content});
        continue;
      }

      contents.add(<String, dynamic>{
        'role': geminiRole,
        'parts': <dynamic>[
          <String, dynamic>{'text': content},
        ],
      });
    }

    if (contents.isEmpty) {
      contents.add(<String, dynamic>{
        'role': 'user',
        'parts': <dynamic>[
          <String, dynamic>{'text': '[Start of conversation]'},
        ],
      });
    }

    final generationConfig = <String, dynamic>{};

    final temperature = _asDouble(params['temperature']);
    if (temperature != null) {
      generationConfig['temperature'] = temperature.clamp(0.0, 2.0);
    }

    final topP = _asDouble(params['top_p']);
    if (topP != null) {
      generationConfig['topP'] = topP.clamp(0.0, 1.0);
    }

    final topK = _asInt(params['top_k']);
    if (topK != null && topK > 0) {
      generationConfig['topK'] = topK;
    }

    final maxTokens = _asInt(params['max_tokens']);
    if (maxTokens != null && maxTokens > 0) {
      generationConfig['maxOutputTokens'] = maxTokens.clamp(1, 65536);
    }

    final stops = _asStringList(params['stop']);
    if (stops != null) {
      generationConfig['stopSequences'] = stops;
    }

    final body = <String, dynamic>{
      'contents': contents,
      // 不显式下发安全阈值时，Gemini 会套用默认过滤（骚扰/色情/危险内容
      // 中等以上即拦截），角色扮演内容很容易被截断甚至整条拦掉，
      // 表现为「AI 吐字很少」。这里对齐酒馆，全类目关闭拦截。
      'safetySettings': geminiSafetySettings,
    };

    final system = systemBuffer.toString().trim();
    if (system.isNotEmpty) {
      body['systemInstruction'] = <String, dynamic>{
        'parts': <dynamic>[
          <String, dynamic>{'text': system},
        ],
      };
    }

    if (generationConfig.isNotEmpty) {
      body['generationConfig'] = generationConfig;
    }

    return body;
  }

  @override
  List<ChatStreamEvent> parseStreamPayload(String payload) {
    final parsed = _tryDecode(payload);
    if (parsed == null) {
      return const <ChatStreamEvent>[];
    }

    final errorMessage = extractApiErrorMessage(parsed);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final events = <ChatStreamEvent>[];

    final text = _extractGeminiLikeText(parsed);
    if (text.isNotEmpty) {
      events.add(ChatStreamEvent(text: text));
    }

    final finishReason = _firstFinishReason(parsed);
    if (finishReason != null) {
      events.add(ChatStreamEvent(finishReason: finishReason));
    }

    final usage = ChatUsage.fromJson(parsed['usageMetadata']);
    if (usage != null) {
      events.add(ChatStreamEvent(usage: usage));
    }

    return events;
  }

  @override
  ChatCompletionResult parseResponse(dynamic data) {
    if (data is! Map) {
      return const ChatCompletionResult(text: '');
    }
    final map = Map<String, dynamic>.from(data);

    final errorMessage = extractApiErrorMessage(map);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    return ChatCompletionResult(
      text: _extractGeminiLikeText(map),
      usage: ChatUsage.fromJson(map['usageMetadata']),
      finishReason: _firstFinishReason(map),
    );
  }

  @override
  ChatUsage? extractUsage(dynamic payload) {
    if (payload is Map) {
      return ChatUsage.fromJson(
        Map<String, dynamic>.from(payload)['usageMetadata'],
      );
    }
    return null;
  }
}

/// ---------------------------------------------------------------------------
/// 4) 本地 GGUF（不经过 HTTP，仅作为协议占位）
/// ---------------------------------------------------------------------------
class LocalLlamaAdapter extends ChatProtocolAdapter {
  const LocalLlamaAdapter();

  @override
  String get id => 'local.gguf';

  @override
  bool get isLocal => true;

  @override
  bool get supportsStreaming => true;

  @override
  int get defaultContextSize => 4096;

  @override
  Uri buildUri(
    ApiConnection connection, {
    required bool stream,
    String? model,
  }) {
    throw UnsupportedError('Local GGUF does not use HTTP.');
  }

  @override
  Map<String, String> buildHeaders(
    ApiConnection connection, {
    required bool stream,
  }) {
    return const <String, String>{};
  }

  @override
  Map<String, dynamic> buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  }) {
    return const <String, dynamic>{};
  }

  @override
  List<ChatStreamEvent> parseStreamPayload(String payload) {
    return const <ChatStreamEvent>[];
  }

  @override
  ChatCompletionResult parseResponse(dynamic data) {
    return const ChatCompletionResult(text: '');
  }
}

/// ---------------------------------------------------------------------------
/// 工厂 & 公共工具
/// ---------------------------------------------------------------------------
ChatProtocolAdapter resolveChatAdapter(String platform) {
  if (platform == ApiPlatform.claude.label) {
    return const AnthropicMessagesAdapter();
  }
  if (platform == ApiPlatform.customGemini.label) {
    return const GeminiGenerateContentAdapter();
  }
  if (platform == ApiPlatform.local.label) {
    return const LocalLlamaAdapter();
  }
  return const OpenAiChatCompletionsAdapter();
}

/// 把 ChatMessage 序列化成 OpenAI 风格的 role/content。
List<Map<String, dynamic>> serializeChatMessages(List<ChatMessage> messages) {
  return <Map<String, dynamic>>[
    for (final message in messages) serializeChatMessage(message),
  ];
}

Map<String, dynamic> serializeChatMessage(ChatMessage message) {
  final payload = <String, dynamic>{
    'role': message.role,
    'content': message.content,
  };

  final rawName = message.metadata?['name']?.toString().trim() ?? '';
  if (rawName.isNotEmpty) {
    payload['name'] = rawName;
  }

  return payload;
}

Map<String, dynamic>? _tryDecode(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _extractGeminiLikeText(Map<String, dynamic> map) {
  final candidates = map['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (final candidate in candidates) {
    if (candidate is! Map) {
      continue;
    }
    final candidateMap = Map<String, dynamic>.from(candidate);
    final content = candidateMap['content'];
    if (content is! Map) {
      continue;
    }
    final parts = Map<String, dynamic>.from(content)['parts'];
    if (parts is! List) {
      continue;
    }
    for (final part in parts) {
      if (part is Map) {
        final text = Map<String, dynamic>.from(part)['text'];
        if (text != null) {
          buffer.write(text.toString());
        }
      }
    }
    if (buffer.isNotEmpty) {
      // 只取第一个候选，与酒馆行为一致。
      break;
    }
  }
  return buffer.toString();
}

String? _firstFinishReason(Map<String, dynamic> map) {
  final candidates = map['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final first = candidates.first;
    if (first is Map) {
      final reason =
          Map<String, dynamic>.from(first)['finishReason']?.toString() ?? '';
      if (reason.trim().isNotEmpty) {
        return reason.trim();
      }
    }
  }
  return null;
}
