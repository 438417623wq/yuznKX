import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api_connection/domain/models/api_connection.dart';
import '../domain/models/chat_message.dart';
import 'local_llm_service.dart';
import 'transport/chat_transport.dart';
import 'transport/local_chat_template.dart';

/// HTTP 传输层。
///
/// 本类只负责：重试、取消、SSE 分行、错误格式化。
/// 「用哪个协议说话」由 [ChatProtocolAdapter] 决定。
class ChatService {
  final Dio _dio = Dio();
  final Ref ref;
  final Random _random = Random();

  static const int _maxRequestAttempts = 3;
  static const Set<int> _retryableStatusCodes = {
    408,
    409,
    425,
    429,
    500,
    502,
    503,
    504,
  };

  ChatService(this.ref) {
    _dio.options
      ..connectTimeout = const Duration(seconds: 30)
      ..sendTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 90);
  }

  /// 兼容旧调用点。
  static List<Map<String, dynamic>> serializeMessagesForApi(
    List<ChatMessage> messages,
  ) {
    return serializeChatMessages(messages);
  }

  ChatProtocolAdapter adapterFor(ApiConnection connection) {
    return resolveChatAdapter(connection.platform);
  }

  Future<ChatCompletionResult> sendMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
    String? overrideModel,
    CancelToken? cancelToken,
  }) async {
    final adapter = adapterFor(connection);

    if (adapter.isLocal) {
      final buffer = StringBuffer();
      ChatUsage? usage;
      String? finishReason;

      await for (final event in streamMessage(
        connection: connection,
        messages: messages,
        parameters: parameters,
        overrideModel: overrideModel,
        cancelToken: cancelToken,
      )) {
        if (event.text != null && event.text!.isNotEmpty) {
          buffer.write(event.text);
        }
        if (event.usage != null) {
          usage = usage?.merge(event.usage) ?? event.usage;
        }
        finishReason = event.finishReason ?? finishReason;
      }

      return ChatCompletionResult(
        text: buffer.toString(),
        usage: usage,
        finishReason: finishReason,
      );
    }

    final model = overrideModel ?? connection.model;
    final uri = adapter.buildUri(connection, stream: false);
    final body = adapter.buildRequestBody(
      model: model,
      messages: messages,
      stream: false,
      parameters: parameters,
    );

    try {
      final response = await _postWithRetry(
        url: uri.toString(),
        options: Options(
          headers: adapter.buildHeaders(connection, stream: false),
        ),
        data: body,
        cancelToken: cancelToken,
      );
      final result = adapter.parseResponse(response.data);
      if (result.text.isNotEmpty) {
        return result;
      }
      throw Exception('Invalid response format: no text content.');
    } on DioException catch (e) {
      throw Exception(_formatDioException(e));
    }
  }

  Stream<ChatStreamEvent> streamMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
    String? overrideModel,
    CancelToken? cancelToken,
  }) async* {
    final adapter = adapterFor(connection);

    if (adapter.isLocal) {
      yield* _streamLocal(connection, messages, parameters);
      return;
    }

    final model = overrideModel ?? connection.model;
    var requestParameters = parameters;
    var streamOptionsDropped = false;

    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      var hasYielded = false;
      try {
        final uri = adapter.buildUri(connection, stream: true, model: model);
        final body = adapter.buildRequestBody(
          model: model,
          messages: messages,
          stream: true,
          parameters: requestParameters,
        );

        final response = await _dio.post(
          uri.toString(),
          options: Options(
            headers: adapter.buildHeaders(connection, stream: true),
            responseType: ResponseType.stream,
          ),
          data: body,
          cancelToken: cancelToken,
        );

        final stream =
            response.data.stream.cast<List<int>>().transform(utf8.decoder);
        String buffer = '';

        await for (final chunk in stream) {
          buffer += chunk;

          while (true) {
            final index = buffer.indexOf('\n');
            if (index < 0) {
              break;
            }

            final line = buffer.substring(0, index).trimRight();
            buffer = buffer.substring(index + 1);

            final events = _parseSseLine(adapter, line);
            for (final event in events) {
              if (event.isEmpty) {
                continue;
              }
              if (event.text != null && event.text!.isNotEmpty) {
                hasYielded = true;
              }
              yield event;
            }
          }
        }

        final tailEvents = _parseSseLine(adapter, buffer.trim());
        for (final event in tailEvents) {
          if (event.isEmpty) {
            continue;
          }
          if (event.text != null && event.text!.isNotEmpty) {
            hasYielded = true;
          }
          yield event;
        }
        return;
      } on DioException catch (e) {
        // 部分 OpenAI 兼容服务端不认 `stream_options`，做一次性兼容回退。
        if (!hasYielded &&
            !streamOptionsDropped &&
            _isStreamOptionsRejection(e)) {
          streamOptionsDropped = true;
          requestParameters = <String, dynamic>{
            ...?parameters,
            'include_usage': false,
          };
          attempt--;
          continue;
        }

        final shouldRetry =
            !hasYielded && attempt < _maxRequestAttempts && _isRetryable(e);
        if (!shouldRetry) {
          throw Exception(_formatDioException(e));
        }
        await Future.delayed(_computeRetryDelay(e, attempt));
      } on Exception {
        rethrow;
      }
    }
  }

  /// 解析一行 SSE 文本（可能不是 `data:` 行）。
  List<ChatStreamEvent> _parseSseLine(ChatProtocolAdapter adapter, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
      return const <ChatStreamEvent>[];
    }

    final data = trimmed.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') {
      return const <ChatStreamEvent>[];
    }

    return adapter.parseStreamPayload(data);
  }

  Stream<ChatStreamEvent> _streamLocal(
    ApiConnection connection,
    List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
  ) async* {
    final modelPath = connection.localModelPath;
    if (modelPath == null || modelPath.isEmpty) {
      throw Exception('Local model path is not set.');
    }

    final template = LocalChatTemplate.fromId(
      parameters?['chat_template']?.toString(),
    );
    final resolvedTemplate = template == LocalChatTemplate.auto
        ? LocalChatTemplate.detectFromModelName(modelPath)
        : template;

    final prompt = buildLocalChatPrompt(
      messages: messages,
      template: resolvedTemplate,
    );

    final localService = ref.read(localLlmServiceProvider);
    await for (final chunk in localService.streamResponse(
      modelPath: modelPath,
      prompt: prompt,
      parameters: parameters,
    )) {
      if (chunk.isEmpty) {
        continue;
      }
      yield ChatStreamEvent(text: chunk);
    }
  }

  bool _isStreamOptionsRejection(DioException exception) {
    if (exception.response?.statusCode != 400) {
      return false;
    }

    final data = exception.response?.data;
    String text = '';
    if (data is String) {
      text = data;
    } else if (data is Map) {
      text = jsonEncode(data);
    }

    if (text.isEmpty) {
      // 流式响应下 Dio 不把 body 交给我们，无法判定 400 的原因。
      // 保守地做一次「去掉 stream_options」的重试（有 flag 保护，只发生一次）。
      return true;
    }

    final lowered = text.toLowerCase();
    return lowered.contains('stream_options') ||
        lowered.contains('include_usage');
  }

  Future<Response<dynamic>> _postWithRetry({
    required String url,
    required Options options,
    required dynamic data,
    CancelToken? cancelToken,
    int maxAttempts = _maxRequestAttempts,
  }) async {
    DioException? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _dio.post(
          url,
          options: options,
          data: data,
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        lastError = e;
        final shouldRetry = attempt < maxAttempts && _isRetryable(e);
        if (!shouldRetry) {
          rethrow;
        }
        await Future.delayed(_computeRetryDelay(e, attempt));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw Exception('Unknown request error.');
  }

  bool _isRetryable(DioException exception) {
    final statusCode = exception.response?.statusCode;
    if (statusCode != null && _retryableStatusCodes.contains(statusCode)) {
      return true;
    }

    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      default:
        return false;
    }
  }

  Duration _computeRetryDelay(DioException exception, int attempt) {
    final statusCode = exception.response?.statusCode;
    final retryAfter = _extractRetryAfter(exception);
    if (statusCode == 429 && retryAfter != null) {
      return retryAfter +
          Duration(
            milliseconds: _random.nextInt(200).clamp(80, 200).toInt(),
          );
    }

    final baseMs = statusCode == 429 ? 1800 : 800;
    final expo = pow(2, attempt - 1).toDouble();
    final jitter = _random.nextInt(350);
    final millis = (baseMs * expo).toInt() + jitter;
    return Duration(milliseconds: millis.clamp(600, 12000));
  }

  Duration? _extractRetryAfter(DioException exception) {
    final retryAfterRaw = exception.response?.headers.value('retry-after');
    if (retryAfterRaw == null || retryAfterRaw.trim().isEmpty) {
      return null;
    }

    final asSeconds = int.tryParse(retryAfterRaw.trim());
    if (asSeconds != null) {
      return Duration(seconds: asSeconds.clamp(1, 60));
    }

    final asDate = DateTime.tryParse(retryAfterRaw.trim());
    if (asDate != null) {
      final diff = asDate.difference(DateTime.now());
      if (diff.inMilliseconds > 0) {
        return diff;
      }
    }
    return null;
  }

  String _formatDioException(DioException exception) {
    final statusCode = exception.response?.statusCode;
    final data = exception.response?.data;

    String details = '';
    if (data is Map) {
      final message = extractApiErrorMessage(Map<String, dynamic>.from(data));
      if (message != null && message.isNotEmpty) {
        details = message;
      }
    } else if (data is String && data.trim().isNotEmpty) {
      details = data.trim();
    }

    if (details.isEmpty && statusCode != null) {
      if (statusCode == 429) {
        final retryAfter = _extractRetryAfter(exception);
        if (retryAfter != null) {
          details = '请求过于频繁，请约 ${retryAfter.inSeconds} 秒后重试。';
        } else {
          details = '请求过于频繁或额度不足，请稍后重试或更换 API 节点。';
        }
      } else if (statusCode == 401 || statusCode == 403) {
        details = '鉴权失败，请检查 API Key 是否正确、是否有权限访问该模型。';
      } else if (statusCode == 404) {
        details = '接口地址不正确，请确认 Base URL 是否包含正确的 /v1。';
      } else if (statusCode >= 500) {
        details = '服务端暂时不可用，请稍后重试。';
      }
    }

    if (details.isEmpty && statusCode == null) {
      if (exception.type == DioExceptionType.connectionTimeout ||
          exception.type == DioExceptionType.sendTimeout ||
          exception.type == DioExceptionType.receiveTimeout) {
        details = '连接超时，请检查网络或 API 线路稳定性。';
      } else if (exception.type == DioExceptionType.connectionError) {
        details = '网络连接失败，请检查 Base URL、DNS、代理或当前网络。';
      } else {
        details = '请求失败，请检查网络与接口配置。';
      }
    }

    final endpoint = exception.requestOptions.uri.toString();
    final statusPart =
        statusCode != null ? 'HTTP $statusCode' : 'Network error';
    if (details.isNotEmpty) {
      return '$statusPart at $endpoint: $details';
    }
    return '$statusPart at $endpoint: ${exception.message ?? 'request failed'}';
  }
}
