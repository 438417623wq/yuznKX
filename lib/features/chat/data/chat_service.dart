import 'dart:convert';
import 'package:dio/dio.dart';
import '../../api_connection/domain/models/api_connection.dart';
import '../domain/models/chat_message.dart';

class ChatService {
  final Dio _dio = Dio();

  // Keep the future-based one for non-streaming compatibility if needed, 
  // but we will primarily add the streaming one.
  
  Stream<String> streamMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters,
    String? overrideModel, // Add override model
  }) async* {
    String baseUrl = connection.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final String url = '$baseUrl/chat/completions';

    final body = <String, dynamic>{
      'model': overrideModel ?? connection.model, // Use override if available
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true, 
    };

    if (parameters != null) {
      body.addAll(parameters);
    }

    try {
      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${connection.apiKey}',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        data: body,
      );

      final stream = response.data.stream;
      // Buffer for handling split chunks
      String buffer = '';

      await for (final chunk in stream) {
        final String s = String.fromCharCodes(chunk as List<int>);
        buffer += s;
        
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') return;
            
            try {
              final json = jsonDecode(data);
              final content = json['choices']?[0]?['delta']?['content'];
              if (content != null) {
                yield content.toString();
              }
            } catch (e) {
              // Partial JSON or other error, might need more sophisticated buffering if JSON is split
            }
          }
        }
      }
    } catch (e) {
      throw Exception('API Stream Error: $e');
    }
  }

  Future<String> sendMessage({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    Map<String, dynamic>? parameters, // Add parameters support
  }) async {
    // Determine the correct endpoint
    String baseUrl = connection.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final String url = '$baseUrl/chat/completions';

    try {
      final body = <String, dynamic>{
        'model': connection.model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': false, 
      };

      // Merge preset parameters if provided
      if (parameters != null) {
        body.addAll(parameters);
      }

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${connection.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: body,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          return data['choices'][0]['message']['content'] ?? '';
        }
      }
      throw Exception('Failed to get response: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }
}
