import 'package:uuid/uuid.dart';
import '../../../regex/domain/models/regex_script.dart';

class Preset {
  final String id;
  final String name;
  final double temperature;
  final double frequencyPenalty;
  final double presencePenalty;
  final double topP;
  final int topK;
  final double repetitionPenalty;
  final int maxTokens;
  final List<PresetPrompt> prompts;
  final List<RegexScript> regexScripts;

  // Function Tab Fields
  final String impersonationPrompt;
  final String newChatPrompt;
  final String continueNudge;
  final String groupChatPrompt;

  final String systemPrompt; // Default system prompt override if not using 'prompts' list logic or simplified

  Preset({
    required this.id,
    required this.name,
    this.temperature = 1.0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.topP = 1.0,
    this.topK = 0,
    this.repetitionPenalty = 1.0,
    this.maxTokens = 2000,
    this.prompts = const [],
    this.regexScripts = const [],
    this.impersonationPrompt = '',
    this.newChatPrompt = '',
    this.continueNudge = '',
    this.groupChatPrompt = '',
    this.systemPrompt = '',
  });

  factory Preset.fromJson(Map<String, dynamic> json) {
    // Handle SillyTavern format
    List<PresetPrompt> loadedPrompts = [];
    if (json['prompts'] != null) {
      for (var p in json['prompts']) {
        loadedPrompts.add(PresetPrompt.fromJson(p));
      }
    }

    // Handle prompt_order to set enabled state
    if (json['prompt_order'] != null && (json['prompt_order'] as List).isNotEmpty) {
      // Use the first order found (usually default/global or specific character)
      // In a full implementation we might want to let user choose, but for now take the first one
      final orderList = json['prompt_order'][0]['order'] as List?;
      if (orderList != null) {
        // Create a map of identifier -> enabled
        final enabledMap = <String, bool>{};
        for (var item in orderList) {
          if (item['identifier'] != null && item['enabled'] != null) {
            enabledMap[item['identifier']] = item['enabled'];
          }
        }

        // Update loaded prompts
        for (var i = 0; i < loadedPrompts.length; i++) {
          final prompt = loadedPrompts[i];
          if (enabledMap.containsKey(prompt.identifier)) {
             loadedPrompts[i] = PresetPrompt(
              identifier: prompt.identifier,
              name: prompt.name,
              role: prompt.role,
              content: prompt.content,
              injectionPosition: prompt.injectionPosition,
              injectionDepth: prompt.injectionDepth,
              enabled: enabledMap[prompt.identifier]!,
            );
          }
        }
      }
    }

    List<RegexScript> loadedRegex = [];
    var regexList = json['regex_scripts'] ?? json['regex'];

    // Check extensions if root list is null or empty
    if (regexList == null || (regexList is List && regexList.isEmpty)) {
       // Attempt to access extensions as a Map safely
       try {
         final extensions = json['extensions'] as Map?;
         if (extensions != null) {
            // Path 1: extensions -> regex_scripts
            final extList = extensions['regex_scripts'];
            if (extList is List && extList.isNotEmpty) {
              regexList = extList;
            } else {
              // Path 2: extensions -> SPreset -> RegexBinding -> regexes
              final sPreset = extensions['SPreset'] as Map?;
              if (sPreset != null) {
                final regexBinding = sPreset['RegexBinding'] as Map?;
                if (regexBinding != null) {
                  final bindingList = regexBinding['regexes'];
                  if (bindingList is List && bindingList.isNotEmpty) {
                    regexList = bindingList;
                  }
                }
              }
            }
         }
       } catch (e) {
         print('Error parsing extensions: $e');
       }
    }

    if (regexList != null && regexList is List) {
      for (var r in regexList) {
        try {
          if (r is Map) {
            loadedRegex.add(RegexScript.fromJson(Map<String, dynamic>.from(r)));
          }
        } catch (e) {
          print('Error parsing regex script: $e');
        }
      }
    }

    return Preset(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Imported Preset',
      temperature: (json['temperature'] ?? 1.0).toDouble(),
      frequencyPenalty: (json['frequency_penalty'] ?? 0.0).toDouble(),
      presencePenalty: (json['presence_penalty'] ?? 0.0).toDouble(),
      topP: (json['top_p'] ?? 1.0).toDouble(),
      topK: (json['top_k'] ?? 0).toInt(),
      repetitionPenalty: (json['repetition_penalty'] ?? 1.0).toDouble(),
      maxTokens: (json['openai_max_tokens'] ?? 2000).toInt(),
      prompts: loadedPrompts,
      regexScripts: loadedRegex,
      impersonationPrompt: json['impersonation_prompt'] ?? '',
      newChatPrompt: json['new_chat_prompt'] ?? '',
      continueNudge: json['continue_nudge'] ?? '',
      groupChatPrompt: json['group_chat_prompt'] ?? '',
      systemPrompt: json['system_prompt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'temperature': temperature,
      'frequency_penalty': frequencyPenalty,
      'presence_penalty': presencePenalty,
      'top_p': topP,
      'top_k': topK,
      'repetition_penalty': repetitionPenalty,
      'openai_max_tokens': maxTokens,
      'prompts': prompts.map((e) => e.toJson()).toList(),
      'regex_scripts': regexScripts.map((e) => e.toJson()).toList(),
      'impersonation_prompt': impersonationPrompt,
      'new_chat_prompt': newChatPrompt,
      'continue_nudge': continueNudge,
      'group_chat_prompt': groupChatPrompt,
      'system_prompt': systemPrompt,
    };
  }

  Preset copyWith({
    String? name,
    double? temperature,
    double? frequencyPenalty,
    double? presencePenalty,
    double? topP,
    int? topK,
    double? repetitionPenalty,
    int? maxTokens,
    List<PresetPrompt>? prompts,
    List<RegexScript>? regexScripts,
    String? impersonationPrompt,
    String? newChatPrompt,
    String? continueNudge,
    String? groupChatPrompt,
    String? systemPrompt,
  }) {
    return Preset(
      id: id,
      name: name ?? this.name,
      temperature: temperature ?? this.temperature,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      prompts: prompts ?? this.prompts,
      regexScripts: regexScripts ?? this.regexScripts,
      impersonationPrompt: impersonationPrompt ?? this.impersonationPrompt,
      newChatPrompt: newChatPrompt ?? this.newChatPrompt,
      continueNudge: continueNudge ?? this.continueNudge,
      groupChatPrompt: groupChatPrompt ?? this.groupChatPrompt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
}

class PresetPrompt {
  final String identifier;
  final String name;
  final String role; // system, user, assistant
  final String content;
  final int injectionPosition; // 0 = absolute top, etc.
  final int injectionDepth; 
  final bool enabled;
  
  PresetPrompt({
    required this.identifier,
    required this.name,
    required this.role,
    required this.content,
    this.injectionPosition = 0,
    this.injectionDepth = 0,
    this.enabled = true,
  });

  factory PresetPrompt.fromJson(Map<String, dynamic> json) {
    return PresetPrompt(
      identifier: json['identifier'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Untitled',
      role: json['role'] ?? 'system',
      content: json['content'] ?? '',
      injectionPosition: json['injection_position'] ?? 0,
      injectionDepth: json['injection_depth'] ?? 0,
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'identifier': identifier,
      'name': name,
      'role': role,
      'content': content,
      'injection_position': injectionPosition,
      'injection_depth': injectionDepth,
      'enabled': enabled,
    };
  }

  PresetPrompt copyWith({
    String? identifier,
    String? name,
    String? role,
    String? content,
    int? injectionPosition,
    int? injectionDepth,
    bool? enabled,
  }) {
    return PresetPrompt(
      identifier: identifier ?? this.identifier,
      name: name ?? this.name,
      role: role ?? this.role,
      content: content ?? this.content,
      injectionPosition: injectionPosition ?? this.injectionPosition,
      injectionDepth: injectionDepth ?? this.injectionDepth,
      enabled: enabled ?? this.enabled,
    );
  }
}
