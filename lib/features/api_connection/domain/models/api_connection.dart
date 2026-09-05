import 'package:uuid/uuid.dart';

class ApiConnection {
  final String id;
  final String name;
  final String platform;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String? localModelPath;
  final Map<String, dynamic> parameters;

  ApiConnection({
    required this.id,
    required this.name,
    required this.platform,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.localModelPath,
    this.parameters = const {},
  });

  factory ApiConnection.create({
    required String name,
    required String platform,
    String baseUrl = '',
    String apiKey = '',
    String model = '',
    String? localModelPath,
  }) {
    return ApiConnection(
      id: const Uuid().v4(),
      name: name,
      platform: platform,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      localModelPath: localModelPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platform': platform,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'localModelPath': localModelPath,
      'parameters': parameters,
    };
  }

  factory ApiConnection.fromJson(Map<String, dynamic> json) {
    return ApiConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      localModelPath: json['localModelPath'] as String?,
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
    );
  }

  ApiConnection copyWith({
    String? name,
    String? platform,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? localModelPath,
    Map<String, dynamic>? parameters,
  }) {
    return ApiConnection(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      localModelPath: localModelPath ?? this.localModelPath,
      parameters: parameters ?? this.parameters,
    );
  }
}

enum ApiPlatform {
  openai('OpenAI', 'https://api.openai.com/v1'),
  claude('Claude (Anthropic)', 'https://api.anthropic.com'),
  deepseek('DeepSeek', 'https://api.deepseek.com'),
  customOpenAi('自定义 (OpenAI 协议)', ''),
  customGemini('自定义 (Gemini 协议)', ''),
  local('Local GGUF (本地模型)', '');

  final String label;
  final String defaultBaseUrl;

  const ApiPlatform(this.label, this.defaultBaseUrl);
}
