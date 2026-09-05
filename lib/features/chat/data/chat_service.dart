import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api_connection/domain/models/api_connection.dart';
import '../domain/models/chat_message.dart';
import 'local_llm_service.dart';

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

  static List<Map<String, dynamic>> serializeMessagesForApi(
    List<ChatMessage> messages,
  ) {
    return [
      for (final message in messages) _serializeMessageForApi(message),
    ];
  }

  static const Set<String> _openAiCompatibleParameterKeys = <String>{
    'temperature',
    'top_p',
    'presence_penalty',
    'frequency_penalty',
    'max_tokens',
    'max_completion_tokens',
    'stop',
    'n',
    'seed',
    'logit_bias',
    'response_format',
    'tools',
    'tool_choice',
    'user',
    'metadata',
  };

  Future<String> sendMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
    String? overrideModel,
    CancelToken? cancelToken,
  }) async {
    if (connection.platform == ApiPlatform.local.label) {
      final stream = streamMessage(
        connection: connection,
        messages: messages,
        parameters: parameters,
        overrideModel: overrideModel,
        cancelToken: cancelToken,
      );
      return stream.join();
    }

    final baseUrl = _normalizeBaseUrl(connection.baseUrl);
    final url = '$baseUrl/chat/completions';
    final body = _buildRequestBody(
      model: overrideModel ?? connection.model,
      messages: messages,
      stream: false,
      parameters: parameters,
    );

    try {
      final response = await _postWithRetry(
        url: url,
        options: Options(headers: _buildHeaders(connection)),
        data: body,
        cancelToken: cancelToken,
      );
      final content = _extractTextFromResponseJson(response.data);
      if (content.isNotEmpty) {
        return content;
      }
      throw Exception('Invalid response format: no text content.');
    } on DioException catch (e) {
      throw Exception(_formatDioException(e));
    }
  }

  Stream<String> streamMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
    String? overrideModel,
    CancelToken? cancelToken,
  }) async* {
    if (connection.platform == ApiPlatform.local.label) {
      if (connection.localModelPath == null ||
          connection.localModelPath!.isEmpty) {
        throw Exception('Local model path is not set.');
      }

      final localService = ref.read(localLlmServiceProvider);

      final StringBuffer promptBuilder = StringBuffer();
      for (final msg in messages) {
        final apiMessage = _serializeMessageForApi(msg);
        final role = apiMessage['role']?.toString() ?? 'user';
        final content = apiMessage['content']?.toString() ?? '';
        if (content.trim().isEmpty) {
          continue;
        }

        final explicitName = apiMessage['name']?.toString().trim() ?? '';
        final label = explicitName.isNotEmpty
            ? explicitName
            : switch (role) {
                'assistant' => 'Assistant',
                'system' => 'System',
                _ => 'User',
              };

        promptBuilder.writeln('$label: $content');
      }
      promptBuilder.write('Assistant:');

      yield* localService.streamResponse(
        modelPath: connection.localModelPath!,
        prompt: promptBuilder.toString(),
        parameters: parameters,
      );
      return;
    }

    final baseUrl = _normalizeBaseUrl(connection.baseUrl);
    final url = '$baseUrl/chat/completions';
    final body = _buildRequestBody(
      model: overrideModel ?? connection.model,
      messages: messages,
      stream: true,
      parameters: parameters,
    );

    for (var attempt = 1; attempt <= _maxRequestAttempts; attempt++) {
      var hasYielded = false;
      try {
        final response = await _dio.post(
          url,
          options: Options(
            headers: _buildHeaders(connection, stream: true),
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
            final trimmed = line.trim();

            if (!trimmed.startsWith('data:')) {
              continue;
            }

            final data = trimmed.substring(5).trim();
            if (data.isEmpty) {
              continue;
            }
            if (data == '[DONE]') {
              return;
            }

            final chunks = _extractTextChunksFromSsePayload(data);
            for (final text in chunks) {
              if (text.isNotEmpty) {
                hasYielded = true;
                yield text;
              }
            }
          }
        }

        final tail = buffer.trim();
        if (tail.startsWith('data:')) {
          final data = tail.substring(5).trim();
          if (data.isNotEmpty && data != '[DONE]') {
            final chunks = _extractTextChunksFromSsePayload(data);
            for (final text in chunks) {
              if (text.isNotEmpty) {
                hasYielded = true;
                yield text;
              }
            }
          }
        }
        return;
      } on DioException catch (e) {
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

  String _normalizeBaseUrl(String rawBaseUrl) {
    final baseUrl = rawBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw Exception('Base URL is empty.');
    }
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Map<String, dynamic> _buildRequestBody({
    required String model,
    required List<ChatMessage> messages,
    required bool stream,
    Map<String, dynamic>? parameters,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'messages': serializeMessagesForApi(messages),
      'stream': stream,
    };

    if (parameters != null && parameters.isNotEmpty) {
      body.addAll(_sanitizeParameters(parameters));
    }

    return body;
  }

  static Map<String, dynamic> _serializeMessageForApi(ChatMessage message) {
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

  Map<String, dynamic> _sanitizeParameters(Map<String, dynamic> parameters) {
    final sanitized = <String, dynamic>{};
    for (final entry in parameters.entries) {
      if (entry.value == null) {
        continue;
      }
      if (_openAiCompatibleParameterKeys.contains(entry.key)) {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  Map<String, String> _buildHeaders(ApiConnection connection,
      {bool stream = false}) {
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

  List<String> _extractTextChunksFromSsePayload(String payload) {
    dynamic parsed;
    try {
      parsed = jsonDecode(payload);
    } catch (_) {
      return const <String>[];
    }

    if (parsed is! Map) {
      return const <String>[];
    }

    final map = Map<String, dynamic>.from(parsed);
    final errorMessage = _extractErrorMessage(map);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final chunks = <String>[];

    final choices = map['choices'];
    if (choices is List && choices.isNotEmpty) {
      final firstChoice = choices.first;
      if (firstChoice is Map) {
        final firstMap = Map<String, dynamic>.from(firstChoice);
        final delta = firstMap['delta'];
        if (delta is Map) {
          final deltaText = _contentToText(delta['content']);
          if (deltaText.isNotEmpty) {
            chunks.add(deltaText);
          }
          final directDeltaText = _contentToText(delta['text']);
          if (directDeltaText.isNotEmpty) {
            chunks.add(directDeltaText);
          }
        }

        final text = _contentToText(firstMap['text']);
        if (text.isNotEmpty) {
          chunks.add(text);
        }

        final message = firstMap['message'];
        if (message is Map) {
          final messageText = _contentToText(message['content']);
          if (messageText.isNotEmpty) {
            chunks.add(messageText);
          }
        }
      }
    }

    final delta = map['delta'];
    if (delta is Map) {
      final deltaText = _contentToText(delta['text']);
      if (deltaText.isNotEmpty) {
        chunks.add(deltaText);
      }
    }

    return chunks;
  }

  String _extractTextFromResponseJson(dynamic data) {
    if (data is! Map) {
      return '';
    }
    final map = Map<String, dynamic>.from(data);

    final errorMessage = _extractErrorMessage(map);
    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    final choices = map['choices'];
    if (choices is List && choices.isNotEmpty) {
      final firstChoice = choices.first;
      if (firstChoice is Map) {
        final choiceMap = Map<String, dynamic>.from(firstChoice);

        final message = choiceMap['message'];
        if (message is Map) {
          final text = _contentToText(message['content']);
          if (text.isNotEmpty) {
            return text;
          }
        }

        final text = _contentToText(choiceMap['text']);
        if (text.isNotEmpty) {
          return text;
        }
      }
    }

    final content = _contentToText(map['content']);
    if (content.isNotEmpty) {
      return content;
    }

    final candidates = map['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final firstCandidate = candidates.first;
      if (firstCandidate is Map) {
        final candidateContent = firstCandidate['content'];
        if (candidateContent is Map) {
          final parts = candidateContent['parts'];
          if (parts is List && parts.isNotEmpty) {
            final buffer = StringBuffer();
            for (final part in parts) {
              if (part is Map) {
                final text = _contentToText(part['text']);
                if (text.isNotEmpty) {
                  buffer.write(text);
                }
              }
            }
            if (buffer.isNotEmpty) {
              return buffer.toString();
            }
          }
        }
      }
    }

    return '';
  }

  String _contentToText(dynamic content) {
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
            buffer.write(_contentToText(nested));
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
        return _contentToText(mapContent['content']);
      }
    }
    return '';
  }

  String? _extractErrorMessage(Map<String, dynamic> map) {
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
      final message = _extractErrorMessage(Map<String, dynamic>.from(data));
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
