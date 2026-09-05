import 'package:uuid/uuid.dart';
import '../../../regex/domain/models/regex_script.dart';

class PresetImportResult {
  final Preset preset;
  final PresetImportReport report;

  const PresetImportResult({
    required this.preset,
    required this.report,
  });
}

class PresetImportReport {
  final int promptsParsed;
  final int promptsSkipped;
  final int regexParsed;
  final int regexSkipped;
  final int promptOrderEntries;
  final List<String> warnings;

  const PresetImportReport({
    required this.promptsParsed,
    required this.promptsSkipped,
    required this.regexParsed,
    required this.regexSkipped,
    required this.promptOrderEntries,
    required this.warnings,
  });

  bool get hasWarnings => warnings.isNotEmpty;

  String summaryLine() {
    final promptTotal = promptsParsed + promptsSkipped;
    final regexTotal = regexParsed + regexSkipped;
    final buffer = StringBuffer(
      'Prompts: $promptsParsed/$promptTotal, Regex: $regexParsed/$regexTotal',
    );
    if (promptOrderEntries > 0) {
      buffer.write(', Order: $promptOrderEntries');
    }
    if (warnings.isNotEmpty) {
      buffer.write(', Warnings: ${warnings.length}');
    }
    return buffer.toString();
  }
}

class Preset {
  static const double defaultTemperature = 0.7;
  static const double defaultFrequencyPenalty = 0.0;
  static const double defaultPresencePenalty = 0.0;
  static const double defaultTopP = 0.95;
  static const int defaultTopK = 40;
  static const double defaultRepetitionPenalty = 1.05;
  static const int defaultMaxTokens = 2000;

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
  final String newGroupChatPrompt;
  final String continueNudge;
  final String groupNudgePrompt;

  // Default system prompt override.
  final String systemPrompt;

  static const int relativeInjectionPosition = 0;
  static const int absoluteInjectionPosition = 1;
  static const int attachExistingInjectionPosition = 2;

  static const List<String> _defaultPromptOrderIdentifiers = [
    'worldInfoBefore',
    'main',
    'worldInfoAfter',
    'charDescription',
    'charPersonality',
    'scenario',
    'personaDescription',
    'nsfw',
    'jailbreak',
    'enhanceDefinitions',
    'bias',
    'dialogueExamples',
    'chatHistory',
    'impersonate',
    'quietPrompt',
    'groupNudge',
    'summary',
    'authorsNote',
    'vectorsMemory',
    'vectorsDataBank',
    'smartContext',
  ];

  Preset({
    required this.id,
    required this.name,
    this.temperature = defaultTemperature,
    this.frequencyPenalty = defaultFrequencyPenalty,
    this.presencePenalty = defaultPresencePenalty,
    this.topP = defaultTopP,
    this.topK = defaultTopK,
    this.repetitionPenalty = defaultRepetitionPenalty,
    this.maxTokens = defaultMaxTokens,
    this.prompts = const [],
    this.regexScripts = const [],
    this.impersonationPrompt = '',
    this.newChatPrompt = '',
    this.newGroupChatPrompt = '',
    this.continueNudge = '',
    this.groupNudgePrompt = '',
    this.systemPrompt = '',
  });

  @Deprecated('Use newGroupChatPrompt instead.')
  String get groupChatPrompt => newGroupChatPrompt;

  factory Preset.fromJson(Map<String, dynamic> json) {
    return Preset.parseWithReport(json).preset;
  }

  static PresetImportResult parseWithReport(
    Map<String, dynamic> json, {
    String? fallbackName,
  }) {
    final source = _asStringDynamicMap(json) ?? <String, dynamic>{};
    final reportBuilder = _PresetImportReportBuilder();

    final name = _firstNonEmptyString([
          _readAny(source, ['name', 'preset_name', 'presetName', 'title']),
          fallbackName,
        ]) ??
        'Imported Preset';
    final id = _firstNonEmptyString([
          _readAny(source, ['id', 'uid', 'preset_id', 'presetId']),
        ]) ??
        const Uuid().v4();

    final numericScopes = _collectNumericScopes(source);

    double parseClampedDouble({
      required List<String> keys,
      required double defaultValue,
      required double min,
      required double max,
      required String label,
    }) {
      final raw = _readAnyFromMaps(numericScopes, keys);
      final value = _parseDouble(raw, defaultValue: defaultValue);
      final clamped = _clampDouble(value, min, max);
      if (raw != null && clamped != value) {
        reportBuilder.warn('$label out of range. Using $clamped.');
      }
      return clamped;
    }

    int parseClampedInt({
      required List<String> keys,
      required int defaultValue,
      required int min,
      required int max,
      required String label,
    }) {
      final raw = _readAnyFromMaps(numericScopes, keys);
      final value = _parseInt(raw, defaultValue: defaultValue);
      final clamped = _clampInt(value, min, max);
      if (raw != null && clamped != value) {
        reportBuilder.warn('$label out of range. Using $clamped.');
      }
      return clamped;
    }

    final temperature = parseClampedDouble(
      keys: const ['temperature', 'temp'],
      defaultValue: defaultTemperature,
      min: 0.0,
      max: 2.0,
      label: 'temperature',
    );
    final frequencyPenalty = parseClampedDouble(
      keys: const [
        'frequency_penalty',
        'frequencyPenalty',
        'freq_penalty',
        'freqPenalty'
      ],
      defaultValue: defaultFrequencyPenalty,
      min: -2.0,
      max: 2.0,
      label: 'frequency_penalty',
    );
    final presencePenalty = parseClampedDouble(
      keys: const ['presence_penalty', 'presencePenalty'],
      defaultValue: defaultPresencePenalty,
      min: -2.0,
      max: 2.0,
      label: 'presence_penalty',
    );
    final topP = parseClampedDouble(
      keys: const ['top_p', 'topP'],
      defaultValue: defaultTopP,
      min: 0.0,
      max: 1.0,
      label: 'top_p',
    );
    final topK = parseClampedInt(
      keys: const ['top_k', 'topK'],
      defaultValue: defaultTopK,
      min: 0,
      max: 1000,
      label: 'top_k',
    );
    final repetitionPenalty = parseClampedDouble(
      keys: const [
        'repetition_penalty',
        'repetitionPenalty',
        'rep_penalty',
        'repPenalty'
      ],
      defaultValue: defaultRepetitionPenalty,
      min: 0.5,
      max: 2.0,
      label: 'repetition_penalty',
    );

    int maxTokens = parseClampedInt(
      keys: const [
        'max_tokens',
        'openai_max_tokens',
        'maxTokens',
        'max_new_tokens',
        'response_tokens'
      ],
      defaultValue: defaultMaxTokens,
      min: 1,
      max: 131072,
      label: 'max_tokens',
    );
    if (maxTokens <= 0) {
      maxTokens = defaultMaxTokens;
      reportBuilder.warn('max_tokens invalid. Using $defaultMaxTokens.');
    }

    final promptEntries = _extractPromptEntries(source);
    final promptOrderContexts = _extractPromptOrderContexts(source);
    final usePromptManagerSemantics = _shouldUsePromptManagerSemantics(
      source,
      promptEntries: promptEntries,
      promptOrderContexts: promptOrderContexts,
    );
    final parsedPrompts = <PresetPrompt>[];
    for (final rawPrompt in promptEntries) {
      final prompt = _parsePrompt(
        rawPrompt,
        preferPromptManagerSemantics: usePromptManagerSemantics,
      );
      if (prompt == null) {
        reportBuilder.promptsSkipped++;
        continue;
      }
      parsedPrompts.add(prompt);
      reportBuilder.promptsParsed++;
    }

    final orderedPrompts = _applyPromptOrder(
      prompts: _mergeWithDefaultPromptManagerPrompts(parsedPrompts),
      contexts: promptOrderContexts.isEmpty
          ? [_defaultPromptOrderContext()]
          : promptOrderContexts,
      reportBuilder: reportBuilder,
    );

    final regexEntries = _extractRegexEntries(source);
    final parsedRegexScripts = <RegexScript>[];
    for (final rawRegex in regexEntries) {
      final regexMap = _asStringDynamicMap(rawRegex);
      if (regexMap == null) {
        reportBuilder.regexSkipped++;
        continue;
      }

      try {
        parsedRegexScripts.add(RegexScript.fromJson(regexMap));
        reportBuilder.regexParsed++;
      } catch (_) {
        reportBuilder.regexSkipped++;
      }
    }

    final textScopes = _collectTextScopes(source);

    final preset = Preset(
      id: id,
      name: name,
      temperature: temperature,
      frequencyPenalty: frequencyPenalty,
      presencePenalty: presencePenalty,
      topP: topP,
      topK: topK,
      repetitionPenalty: repetitionPenalty,
      maxTokens: maxTokens,
      prompts: orderedPrompts,
      regexScripts: parsedRegexScripts,
      impersonationPrompt: _readStringFromMaps(textScopes, const [
        'impersonation_prompt',
        'impersonationPrompt',
        'impersonation'
      ]),
      newChatPrompt: _readStringFromMaps(
          textScopes, const ['new_chat_prompt', 'newChatPrompt']),
      newGroupChatPrompt: _readStringFromMaps(
        textScopes,
        const [
          'new_group_chat_prompt',
          'newGroupChatPrompt',
          'group_chat_prompt',
          'groupChatPrompt',
        ],
      ),
      continueNudge: _readStringFromMaps(
        textScopes,
        const [
          'continue_nudge',
          'continueNudge',
          'continue_nudge_prompt',
          'continue_prompt',
          'continuePrompt'
        ],
      ),
      groupNudgePrompt: _readStringFromMaps(
        textScopes,
        const [
          'group_nudge_prompt',
          'groupNudgePrompt',
          'group_prompt',
          'groupPrompt'
        ],
      ),
      systemPrompt: _readStringFromMaps(
          textScopes, const ['system_prompt', 'systemPrompt']),
    );

    if (promptEntries.isNotEmpty && parsedPrompts.isEmpty) {
      reportBuilder.warn(
          'Prompt list was found but no valid prompt entries were imported.');
    }
    if (regexEntries.isNotEmpty && parsedRegexScripts.isEmpty) {
      reportBuilder.warn(
          'Regex list was found but no valid regex entries were imported.');
    }

    return PresetImportResult(
      preset: preset,
      report: reportBuilder.build(),
    );
  }

  Map<String, dynamic> toJson() {
    final promptOrder = prompts
        .map(
          (p) => {
            'identifier': p.identifier,
            'enabled': p.enabled,
            'injection_position': p.injectionPosition,
            'injection_depth': p.injectionDepth,
          },
        )
        .toList();

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
      'max_tokens': maxTokens,
      'prompts': prompts.map((e) => e.toJson()).toList(),
      'prompt_order': [
        {
          'character_id': 0,
          'order': promptOrder,
        }
      ],
      'regex_scripts': regexScripts.map((e) => e.toJson()).toList(),
      'impersonation_prompt': impersonationPrompt,
      'new_chat_prompt': newChatPrompt,
      'new_group_chat_prompt': newGroupChatPrompt,
      'continue_nudge': continueNudge,
      'group_nudge_prompt': groupNudgePrompt,
      'group_chat_prompt': newGroupChatPrompt,
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
    String? newGroupChatPrompt,
    String? continueNudge,
    String? groupNudgePrompt,
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
      newGroupChatPrompt: newGroupChatPrompt ?? this.newGroupChatPrompt,
      continueNudge: continueNudge ?? this.continueNudge,
      groupNudgePrompt: groupNudgePrompt ?? this.groupNudgePrompt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }

  static List<Map<String, dynamic>> _collectNumericScopes(
      Map<String, dynamic> source) {
    final scopes = <Map<String, dynamic>>[source];
    for (final key in const [
      'params',
      'parameters',
      'sampling',
      'completion',
      'openai',
      'gen_config'
    ]) {
      final nested = _asStringDynamicMap(source[key]);
      if (nested != null) {
        scopes.add(nested);
      }
    }
    return scopes;
  }

  static List<Map<String, dynamic>> _collectTextScopes(
      Map<String, dynamic> source) {
    final scopes = <Map<String, dynamic>>[source];
    final promptManager = _asStringDynamicMap(source['prompt_manager']);
    if (promptManager != null) {
      scopes.add(promptManager);
    }
    final promptManagerCamel = _asStringDynamicMap(source['promptManager']);
    if (promptManagerCamel != null) {
      scopes.add(promptManagerCamel);
    }
    final extensions = _asStringDynamicMap(source['extensions']);
    if (extensions != null) {
      scopes.add(extensions);
    }
    return scopes;
  }

  static dynamic _readAny(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  static dynamic _readAnyFromMaps(
      List<Map<String, dynamic>> maps, List<String> keys) {
    for (final map in maps) {
      final value = _readAny(map, keys);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static String _readStringFromMaps(
      List<Map<String, dynamic>> maps, List<String> keys) {
    final value = _readAnyFromMaps(maps, keys);
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  static List<dynamic> _extractPromptEntries(Map<String, dynamic> source) {
    final promptSources = <dynamic>[
      source['prompts'],
      _asStringDynamicMap(source['prompt_manager'])?['prompts'],
      _asStringDynamicMap(source['promptManager'])?['prompts'],
      _asStringDynamicMap(source['extensions'])?['prompts'],
    ];

    for (final promptSource in promptSources) {
      final entries = _toCollection(promptSource);
      if (entries.isNotEmpty) {
        return entries;
      }
    }

    return const [];
  }

  static PresetPrompt? _parsePrompt(
    dynamic rawPrompt, {
    required bool preferPromptManagerSemantics,
  }) {
    final map = _asStringDynamicMap(rawPrompt);
    if (map == null) {
      return null;
    }

    final identifier = _firstNonEmptyString([
          _readAny(map, const ['identifier', 'id', 'uid', 'key']),
        ]) ??
        const Uuid().v4();
    final name = _firstNonEmptyString([
          _readAny(map, const ['name', 'title']),
          identifier,
        ]) ??
        'Prompt';
    final role = _normalizeRole(
      _firstNonEmptyString([
            _readAny(map, const ['role', 'type']),
          ]) ??
          'system',
    );
    final content =
        (_readAny(map, const ['content', 'prompt', 'text', 'value']) ?? '')
            .toString();

    final disabled = _readAny(map, const ['disabled']);
    final enabledValue = _readAny(map, const ['enabled', 'active']);
    final enabled = disabled != null
        ? !_parseBool(disabled, defaultValue: false)
        : _parseBool(enabledValue, defaultValue: true);

    final injectionPosition = _parseInjectionPosition(
      _readAny(
        map,
        const [
          'injection_position',
          'injectionPosition',
          'inject_position',
          'position'
        ],
      ),
    );
    final injectionDepth = _parseInt(
      _readAny(
        map,
        const ['injection_depth', 'injectionDepth', 'depth'],
      ),
      defaultValue: 0,
    );
    final injectionOrder = _parseInt(
      _readAny(
        map,
        const ['injection_order', 'injectionOrder', 'order'],
      ),
      defaultValue: PresetPrompt.defaultInjectionOrder,
    );
    final systemPrompt = _parseBool(
      _readAny(map, const ['system_prompt', 'systemPrompt']),
      defaultValue: false,
    );
    final marker = _parseBool(
      _readAny(map, const ['marker']),
      defaultValue: false,
    );
    final relativePosition = _parseRelativePosition(
      _readAny(map, const ['position', 'relative_position', 'relativePosition']),
    );
    final explicitLegacyPositioning =
        _parseOptionalBool(_readAny(map, const ['legacy_positioning']));
    final legacyPositioning = explicitLegacyPositioning ??
        (!preferPromptManagerSemantics &&
            injectionPosition != attachExistingInjectionPosition);

    return PresetPrompt(
      identifier: identifier,
      name: name,
      role: role,
      content: content,
      injectionPosition: injectionPosition,
      injectionDepth: injectionDepth,
      injectionOrder: injectionOrder,
      enabled: enabled,
      systemPrompt: systemPrompt,
      marker: marker,
      position: relativePosition,
      attachRole: _firstNonEmptyString(
        [_readAny(map, const ['attach_role', 'attachRole'])],
      ),
      attachIndex: _parseOptionalInt(
        _readAny(map, const ['attach_index', 'attachIndex']),
      ),
      attachSide: _firstNonEmptyString(
        [_readAny(map, const ['attach_side', 'attachSide'])],
      ),
      legacyPositioning: legacyPositioning,
    );
  }

  static List<_PromptOrderContext> _extractPromptOrderContexts(
      Map<String, dynamic> source) {
    final rawSources = <dynamic>[
      source['prompt_order'],
      source['promptOrder'],
      _asStringDynamicMap(source['prompt_manager'])?['prompt_order'],
      _asStringDynamicMap(source['prompt_manager'])?['promptOrder'],
      _asStringDynamicMap(source['promptManager'])?['prompt_order'],
      _asStringDynamicMap(source['promptManager'])?['promptOrder'],
    ];

    final contexts = <_PromptOrderContext>[];
    for (final rawSource in rawSources) {
      contexts.addAll(_parsePromptOrderSource(rawSource));
    }
    return contexts;
  }

  static List<_PromptOrderContext> _parsePromptOrderSource(dynamic rawSource) {
    if (rawSource == null) {
      return const [];
    }

    if (rawSource is List) {
      if (rawSource.isEmpty) {
        return const [];
      }

      if (rawSource.any(
          (item) => _asStringDynamicMap(item)?.containsKey('order') == true)) {
        final contexts = <_PromptOrderContext>[];
        for (final item in rawSource) {
          final context = _PromptOrderContext.tryParse(item);
          if (context != null) {
            contexts.add(context);
          }
        }
        return contexts;
      }

      final items = _parsePromptOrderItems(rawSource);
      if (items.isEmpty) {
        return const [];
      }
      return [_PromptOrderContext(priority: 0, items: items)];
    }

    final sourceMap = _asStringDynamicMap(rawSource);
    if (sourceMap == null) {
      return const [];
    }

    if (sourceMap.containsKey('order')) {
      final context = _PromptOrderContext.tryParse(sourceMap);
      return context == null ? const [] : [context];
    }

    final contexts = <_PromptOrderContext>[];
    for (final entry in sourceMap.entries) {
      final context =
          _PromptOrderContext.tryParse(entry.value, contextTag: entry.key);
      if (context != null) {
        contexts.add(context);
      }
    }
    if (contexts.isNotEmpty) {
      return contexts;
    }

    final fallbackItems = _parsePromptOrderItems(sourceMap.values.toList());
    if (fallbackItems.isEmpty) {
      return const [];
    }
    return [_PromptOrderContext(priority: 0, items: fallbackItems)];
  }

  static List<_PromptOrderItem> _parsePromptOrderItems(dynamic rawOrder) {
    final entries = _toCollection(rawOrder);
    final items = <_PromptOrderItem>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is String) {
        final identifier = entry.trim();
        if (identifier.isEmpty) {
          continue;
        }
        items.add(
          _PromptOrderItem(
            identifier: identifier,
            orderIndex: i,
            enabled: null,
            injectionDepth: null,
            injectionPosition: null,
            injectionOrder: null,
            role: null,
            attachRole: null,
            attachIndex: null,
            attachSide: null,
          ),
        );
        continue;
      }

      final map = _asStringDynamicMap(entry);
      if (map == null) {
        continue;
      }

      final identifier = _firstNonEmptyString([
        _readAny(map, const ['identifier', 'id', 'uid', 'key']),
      ]);
      if (identifier == null || identifier.isEmpty) {
        continue;
      }

      final disabled = _readAny(map, const ['disabled']);
      final enabledRaw = _readAny(map, const ['enabled', 'active']);
      bool? enabled;
      if (disabled != null) {
        enabled = !_parseBool(disabled, defaultValue: false);
      } else if (enabledRaw != null) {
        enabled = _parseBool(enabledRaw, defaultValue: true);
      }

      final injectionDepthRaw = _readAny(
        map,
        const ['injection_depth', 'injectionDepth', 'depth'],
      );
      final injectionPositionRaw = _readAny(
        map,
        const [
          'injection_position',
          'injectionPosition',
          'inject_position',
          'position'
        ],
      );

      final orderIndex = _parseInt(
        _readAny(map, const ['order', 'index']),
        defaultValue: i,
      );
      final injectionOrderRaw = _readAny(
        map,
        const ['injection_order', 'injectionOrder'],
      );
      final roleRaw = _readAny(map, const ['role', 'type']);
      final attachRoleRaw = _readAny(map, const ['attach_role', 'attachRole']);
      final attachIndexRaw =
          _readAny(map, const ['attach_index', 'attachIndex']);
      final attachSideRaw = _readAny(map, const ['attach_side', 'attachSide']);

      items.add(
        _PromptOrderItem(
          identifier: identifier,
          orderIndex: orderIndex,
          enabled: enabled,
          injectionDepth: injectionDepthRaw == null
              ? null
              : _parseInt(injectionDepthRaw, defaultValue: 0),
          injectionPosition: injectionPositionRaw == null
              ? null
              : _parseInjectionPosition(injectionPositionRaw),
          injectionOrder: injectionOrderRaw == null
              ? null
              : _parseInt(
                  injectionOrderRaw,
                  defaultValue: PresetPrompt.defaultInjectionOrder,
                ),
          role: roleRaw == null ? null : _normalizeRole(roleRaw.toString()),
          attachRole:
              attachRoleRaw == null ? null : attachRoleRaw.toString().trim(),
          attachIndex: _parseOptionalInt(attachIndexRaw),
          attachSide:
              attachSideRaw == null ? null : attachSideRaw.toString().trim(),
        ),
      );
    }

    return items;
  }

  static List<PresetPrompt> _applyPromptOrder({
    required List<PresetPrompt> prompts,
    required List<_PromptOrderContext> contexts,
    required _PresetImportReportBuilder reportBuilder,
  }) {
    if (prompts.isEmpty || contexts.isEmpty) {
      return prompts;
    }

    final bestOrderMap = <String, _PromptOrderItem>{};
    final bestPriorityMap = <String, int>{};

    for (final context in contexts) {
      for (final item in context.items) {
        final existingPriority = bestPriorityMap[item.identifier];
        final existingItem = bestOrderMap[item.identifier];

        final shouldReplace = existingPriority == null ||
            context.priority > existingPriority ||
            (context.priority == existingPriority &&
                existingItem != null &&
                item.orderIndex < existingItem.orderIndex);

        if (shouldReplace) {
          bestPriorityMap[item.identifier] = context.priority;
          bestOrderMap[item.identifier] = item;
        }
      }
    }

    reportBuilder.promptOrderEntries = bestOrderMap.length;

    final indexed = <_IndexedPrompt>[];
    for (var i = 0; i < prompts.length; i++) {
      final prompt = prompts[i];
      final orderItem = bestOrderMap[prompt.identifier];
      if (orderItem == null) {
        indexed.add(_IndexedPrompt(prompt: prompt, originalIndex: i));
        continue;
      }

      indexed.add(
        _IndexedPrompt(
          prompt: prompt.copyWith(
            enabled: orderItem.enabled ?? prompt.enabled,
            injectionDepth: orderItem.injectionDepth ?? prompt.injectionDepth,
            injectionPosition:
                orderItem.injectionPosition ?? prompt.injectionPosition,
            injectionOrder:
                orderItem.injectionOrder ?? prompt.injectionOrder,
            role: orderItem.role ?? prompt.role,
            attachRole: orderItem.attachRole ?? prompt.attachRole,
            attachIndex: orderItem.attachIndex ?? prompt.attachIndex,
            attachSide: orderItem.attachSide ?? prompt.attachSide,
          ),
          originalIndex: i,
        ),
      );
    }

    final promptIds = prompts.map((prompt) => prompt.identifier).toSet();
    for (final orderItem in bestOrderMap.values) {
      if (promptIds.contains(orderItem.identifier)) {
        continue;
      }

      indexed.add(
        _IndexedPrompt(
          prompt: _createPromptPlaceholderForIdentifier(orderItem),
          originalIndex: prompts.length + indexed.length,
        ),
      );
    }

    indexed.sort((a, b) {
      final aOrder = bestOrderMap[a.prompt.identifier]?.orderIndex;
      final bOrder = bestOrderMap[b.prompt.identifier]?.orderIndex;

      if (aOrder != null && bOrder != null && aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null && bOrder == null) {
        return -1;
      }
      if (aOrder == null && bOrder != null) {
        return 1;
      }

      final posCmp =
          a.prompt.injectionPosition.compareTo(b.prompt.injectionPosition);
      if (posCmp != 0) {
        return posCmp;
      }

      final depthCmp =
          a.prompt.injectionDepth.compareTo(b.prompt.injectionDepth);
      if (depthCmp != 0) {
        return depthCmp;
      }

      final orderCmp =
          a.prompt.injectionOrder.compareTo(b.prompt.injectionOrder);
      if (orderCmp != 0) {
        return orderCmp;
      }

      return a.originalIndex.compareTo(b.originalIndex);
    });

    return indexed.map((entry) => entry.prompt).toList();
  }

  static List<PresetPrompt> _mergeWithDefaultPromptManagerPrompts(
    List<PresetPrompt> prompts,
  ) {
    final merged = <String, PresetPrompt>{
      for (final prompt in _defaultPromptManagerPrompts()) prompt.identifier: prompt,
    };

    for (final prompt in prompts) {
      final defaultPrompt = merged[prompt.identifier];
      if (defaultPrompt == null) {
        merged[prompt.identifier] = prompt;
        continue;
      }

      merged[prompt.identifier] = defaultPrompt.copyWith(
        name: prompt.name,
        role: prompt.role,
        content: prompt.content,
        injectionPosition: prompt.injectionPosition,
        injectionDepth: prompt.injectionDepth,
        injectionOrder: prompt.injectionOrder,
        enabled: prompt.enabled,
        systemPrompt: prompt.systemPrompt,
        marker: prompt.marker,
        position: prompt.position,
        attachRole: prompt.attachRole,
        attachIndex: prompt.attachIndex,
        attachSide: prompt.attachSide,
        legacyPositioning: prompt.legacyPositioning,
      );
    }

    return merged.values.toList(growable: false);
  }

  static List<PresetPrompt> _defaultPromptManagerPrompts() {
    return const [
      PresetPrompt(
        identifier: 'main',
        name: 'Main Prompt',
        role: 'system',
        content:
            'Write {{char}}\'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'impersonate',
        name: 'Impersonation Prompt',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'quietPrompt',
        name: 'Quiet Prompt',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'groupNudge',
        name: 'Group Nudge',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'bias',
        name: 'Bias',
        role: 'assistant',
        content: '',
        enabled: true,
        systemPrompt: false,
      ),
      PresetPrompt(
        identifier: 'summary',
        name: 'Summary',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        position: 'start',
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'authorsNote',
        name: 'Author\'s Note',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        position: 'end',
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'vectorsMemory',
        name: 'Vectors Memory',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        position: 'end',
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'vectorsDataBank',
        name: 'Vectors Data Bank',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        position: 'end',
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'smartContext',
        name: 'Smart Context',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        position: 'end',
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'nsfw',
        name: 'Auxiliary Prompt',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'dialogueExamples',
        name: 'Chat Examples',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'jailbreak',
        name: 'Post-History Instructions',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'chatHistory',
        name: 'Chat History',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'worldInfoAfter',
        name: 'World Info (after)',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'worldInfoBefore',
        name: 'World Info (before)',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'enhanceDefinitions',
        name: 'Enhance Definitions',
        role: 'system',
        content:
            'If you have more knowledge of {{char}}, add to the character\'s lore and personality to enhance them but keep the Character Sheet\'s definitions absolute.',
        enabled: false,
        systemPrompt: true,
      ),
      PresetPrompt(
        identifier: 'charDescription',
        name: 'Char Description',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'charPersonality',
        name: 'Char Personality',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'scenario',
        name: 'Scenario',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
      PresetPrompt(
        identifier: 'personaDescription',
        name: 'Persona Description',
        role: 'system',
        content: '',
        enabled: true,
        systemPrompt: true,
        marker: true,
        legacyPositioning: false,
      ),
    ];
  }

  static _PromptOrderContext _defaultPromptOrderContext() {
    return _PromptOrderContext(
      priority: 0,
      items: [
        for (var i = 0; i < _defaultPromptOrderIdentifiers.length; i++)
          _PromptOrderItem(
            identifier: _defaultPromptOrderIdentifiers[i],
            orderIndex: i,
            enabled: _defaultPromptOrderIdentifiers[i] != 'enhanceDefinitions',
            injectionDepth: null,
            injectionPosition: null,
            injectionOrder: null,
            role: null,
            attachRole: null,
            attachIndex: null,
            attachSide: null,
          ),
      ],
    );
  }

  static bool _shouldUsePromptManagerSemantics(
    Map<String, dynamic> source, {
    required List<dynamic> promptEntries,
    required List<_PromptOrderContext> promptOrderContexts,
  }) {
    if (promptOrderContexts.isNotEmpty ||
        source.containsKey('prompt_manager') ||
        source.containsKey('promptManager')) {
      return true;
    }

    for (final rawPrompt in promptEntries) {
      final map = _asStringDynamicMap(rawPrompt);
      if (map == null) {
        continue;
      }

      if (const [
        'system_prompt',
        'systemPrompt',
        'marker',
        'injection_order',
        'injectionOrder',
        'attach_role',
        'attachRole',
        'attach_index',
        'attachIndex',
        'attach_side',
        'attachSide',
      ].any(map.containsKey)) {
        return true;
      }
    }

    return false;
  }

  static PresetPrompt _createPromptPlaceholderForIdentifier(
    _PromptOrderItem item,
  ) {
    final defaults = {
      for (final prompt in _defaultPromptManagerPrompts()) prompt.identifier: prompt,
    };
    final prompt = defaults[item.identifier];
    if (prompt != null) {
      return prompt.copyWith(
        enabled: item.enabled ?? prompt.enabled,
        injectionDepth: item.injectionDepth ?? prompt.injectionDepth,
        injectionPosition: item.injectionPosition ?? prompt.injectionPosition,
        injectionOrder: item.injectionOrder ?? prompt.injectionOrder,
        role: item.role ?? prompt.role,
        attachRole: item.attachRole ?? prompt.attachRole,
        attachIndex: item.attachIndex ?? prompt.attachIndex,
        attachSide: item.attachSide ?? prompt.attachSide,
      );
    }

    return PresetPrompt(
      identifier: item.identifier,
      name: item.identifier,
      role: item.role ?? 'system',
      content: '',
      injectionPosition: item.injectionPosition ?? relativeInjectionPosition,
      injectionDepth: item.injectionDepth ?? 0,
      injectionOrder: item.injectionOrder ?? PresetPrompt.defaultInjectionOrder,
      enabled: item.enabled ?? true,
      systemPrompt: true,
      attachRole: item.attachRole,
      attachIndex: item.attachIndex,
      attachSide: item.attachSide,
      legacyPositioning: false,
    );
  }

  static List<dynamic> _extractRegexEntries(Map<String, dynamic> source) {
    final extensions = _asStringDynamicMap(source['extensions']);
    final sPreset = _asStringDynamicMap(extensions?['SPreset']);
    final regexBinding = _asStringDynamicMap(sPreset?['RegexBinding']);

    final regexSources = <dynamic>[
      source['regex_scripts'],
      source['regexScripts'],
      source['regex'],
      extensions?['regex_scripts'],
      extensions?['regexScripts'],
      extensions?['regex'],
      regexBinding?['regexes'],
    ];

    for (final regexSource in regexSources) {
      final entries = _toCollection(regexSource);
      if (entries.isNotEmpty) {
        return entries;
      }
    }

    return const [];
  }

  static Map<String, dynamic>? _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key?.toString();
        if (key == null || key.isEmpty) {
          continue;
        }
        result[key] = entry.value;
      }
      return result;
    }
    return null;
  }

  static List<dynamic> _toCollection(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }

    final map = _asStringDynamicMap(value);
    if (map != null) {
      if (map['items'] is List) {
        return List<dynamic>.from(map['items'] as List);
      }
      if (map['list'] is List) {
        return List<dynamic>.from(map['list'] as List);
      }
      return map.entries
          .map((entry) {
            final nested = _asStringDynamicMap(entry.value);
            if (nested == null) {
              return null;
            }
            nested.putIfAbsent('identifier', () => entry.key);
            return nested;
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    return const [];
  }

  static bool _parseBool(dynamic value, {required bool defaultValue}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) {
        return defaultValue;
      }
      if (const {'true', '1', 'yes', 'y', 'on', 'enabled'}
          .contains(normalized)) {
        return true;
      }
      if (const {'false', '0', 'no', 'n', 'off', 'disabled'}
          .contains(normalized)) {
        return false;
      }
    }
    return defaultValue;
  }

  static int _parseInt(dynamic value, {required int defaultValue}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return defaultValue;
      }
      final parsedInt = int.tryParse(normalized);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDouble = double.tryParse(normalized);
      if (parsedDouble != null) {
        return parsedDouble.toInt();
      }
    }
    return defaultValue;
  }

  static double _parseDouble(dynamic value, {required double defaultValue}) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return defaultValue;
      }
      final parsed = double.tryParse(normalized);
      if (parsed != null) {
        return parsed;
      }
    }
    return defaultValue;
  }

  static int _parseInjectionPosition(dynamic value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'relative' ||
          normalized == 'before' ||
          normalized == 'before_char' ||
          normalized == 'top') {
        return relativeInjectionPosition;
      }
      if (normalized == 'absolute' ||
          normalized == 'in_chat' ||
          normalized == 'in-chat' ||
          normalized == 'depth' ||
          normalized == 'after' ||
          normalized == 'after_char' ||
          normalized == 'bottom') {
        return absoluteInjectionPosition;
      }
      if (normalized == 'attach_existing' ||
          normalized == 'attach-existing' ||
          normalized == 'attach') {
        return attachExistingInjectionPosition;
      }
    }
    return _parseInt(value, defaultValue: relativeInjectionPosition);
  }

  static String? _parseRelativePosition(dynamic value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'start' || normalized == 'before') {
      return 'start';
    }
    if (normalized == 'end' || normalized == 'after') {
      return 'end';
    }
    return null;
  }

  static bool? _parseOptionalBool(dynamic value) {
    if (value == null) {
      return null;
    }
    return _parseBool(value, defaultValue: false);
  }

  static int? _parseOptionalInt(dynamic value) {
    if (value == null) {
      return null;
    }
    return _parseInt(value, defaultValue: 0);
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  static double _clampDouble(double value, double min, double max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static bool _isCharacterSpecificContext(
      dynamic characterId, String? contextTag) {
    if (contextTag != null && contextTag.toLowerCase().contains('char')) {
      return true;
    }

    if (characterId == null) {
      return false;
    }

    if (characterId is num) {
      final value = characterId.toInt();
      return !(value == 0 || value == -1 || value >= 100000);
    }

    final text = characterId.toString().trim().toLowerCase();
    if (text.isEmpty ||
        text == 'global' ||
        text == 'default' ||
        text == 'null') {
      return false;
    }

    final parsed = int.tryParse(text);
    if (parsed != null && (parsed == 0 || parsed == -1 || parsed >= 100000)) {
      return false;
    }

    return true;
  }

  static String _normalizeRole(String rawRole) {
    final role = rawRole.trim().toLowerCase();
    if (role == 'system' || role == 'assistant' || role == 'user') {
      return role;
    }
    if (role == 'ai' || role == 'bot' || role == 'model') {
      return 'assistant';
    }
    if (role == 'human') {
      return 'user';
    }
    return 'system';
  }
}

class PresetPrompt {
  static const int defaultInjectionOrder = 100;

  final String identifier;
  final String name;
  final String role; // system, user, assistant
  final String content;
  final int injectionPosition; // relative / absolute / attach-existing
  final int injectionDepth;
  final int injectionOrder;
  final bool enabled;
  final bool systemPrompt;
  final bool marker;
  final String? position; // relative insertion around main: start / end
  final String? attachRole;
  final int? attachIndex;
  final String? attachSide;
  final bool legacyPositioning;

  const PresetPrompt({
    required this.identifier,
    required this.name,
    required this.role,
    required this.content,
    this.injectionPosition = 0,
    this.injectionDepth = 0,
    this.injectionOrder = defaultInjectionOrder,
    this.enabled = true,
    this.systemPrompt = false,
    this.marker = false,
    this.position,
    this.attachRole,
    this.attachIndex,
    this.attachSide,
    this.legacyPositioning = true,
  });

  factory PresetPrompt.fromJson(Map<String, dynamic> json) {
    final id = Preset._firstNonEmptyString([
          Preset._readAny(json, const ['identifier', 'id', 'uid', 'key']),
        ]) ??
        const Uuid().v4();
    final name = Preset._firstNonEmptyString([
          Preset._readAny(json, const ['name', 'title']),
          id,
        ]) ??
        'Prompt';

    final disabled = Preset._readAny(json, const ['disabled']);
    final enabledRaw = Preset._readAny(json, const ['enabled', 'active']);
    final enabled = disabled != null
        ? !Preset._parseBool(disabled, defaultValue: false)
        : Preset._parseBool(enabledRaw, defaultValue: true);

    return PresetPrompt(
      identifier: id,
      name: name,
      role: Preset._normalizeRole(
        (Preset._readAny(json, const ['role', 'type']) ?? 'system').toString(),
      ),
      content: (Preset._readAny(
                  json, const ['content', 'prompt', 'text', 'value']) ??
              '')
          .toString(),
      injectionPosition: Preset._parseInjectionPosition(
        Preset._readAny(
          json,
          const [
            'injection_position',
            'injectionPosition',
            'inject_position',
            'position'
          ],
        ),
      ),
      injectionDepth: Preset._parseInt(
        Preset._readAny(
          json,
          const ['injection_depth', 'injectionDepth', 'depth'],
        ),
        defaultValue: 0,
      ),
      injectionOrder: Preset._parseInt(
        Preset._readAny(
          json,
          const ['injection_order', 'injectionOrder', 'order'],
        ),
        defaultValue: defaultInjectionOrder,
      ),
      enabled: enabled,
      systemPrompt: Preset._parseBool(
        Preset._readAny(json, const ['system_prompt', 'systemPrompt']),
        defaultValue: false,
      ),
      marker: Preset._parseBool(
        Preset._readAny(json, const ['marker']),
        defaultValue: false,
      ),
      position: Preset._parseRelativePosition(
        Preset._readAny(
          json,
          const ['position', 'relative_position', 'relativePosition'],
        ),
      ),
      attachRole: Preset._readAny(
        json,
        const ['attach_role', 'attachRole'],
      )?.toString(),
      attachIndex: Preset._parseOptionalInt(
        Preset._readAny(
          json,
          const ['attach_index', 'attachIndex'],
        ),
      ),
      attachSide: Preset._readAny(
        json,
        const ['attach_side', 'attachSide'],
      )?.toString(),
      legacyPositioning: Preset._parseOptionalBool(
            Preset._readAny(json, const ['legacy_positioning']),
          ) ??
          true,
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
      'injection_order': injectionOrder,
      'enabled': enabled,
      'system_prompt': systemPrompt,
      'marker': marker,
      'position': position,
      'attach_role': attachRole,
      'attach_index': attachIndex,
      'attach_side': attachSide,
      'legacy_positioning': legacyPositioning,
    };
  }

  PresetPrompt copyWith({
    String? identifier,
    String? name,
    String? role,
    String? content,
    int? injectionPosition,
    int? injectionDepth,
    int? injectionOrder,
    bool? enabled,
    bool? systemPrompt,
    bool? marker,
    String? position,
    String? attachRole,
    int? attachIndex,
    String? attachSide,
    bool? legacyPositioning,
  }) {
    return PresetPrompt(
      identifier: identifier ?? this.identifier,
      name: name ?? this.name,
      role: role ?? this.role,
      content: content ?? this.content,
      injectionPosition: injectionPosition ?? this.injectionPosition,
      injectionDepth: injectionDepth ?? this.injectionDepth,
      injectionOrder: injectionOrder ?? this.injectionOrder,
      enabled: enabled ?? this.enabled,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      marker: marker ?? this.marker,
      position: position ?? this.position,
      attachRole: attachRole ?? this.attachRole,
      attachIndex: attachIndex ?? this.attachIndex,
      attachSide: attachSide ?? this.attachSide,
      legacyPositioning: legacyPositioning ?? this.legacyPositioning,
    );
  }
}

class _PromptOrderContext {
  final int priority;
  final List<_PromptOrderItem> items;

  const _PromptOrderContext({
    required this.priority,
    required this.items,
  });

  static _PromptOrderContext? tryParse(dynamic rawContext,
      {String? contextTag}) {
    final contextMap = Preset._asStringDynamicMap(rawContext);
    if (contextMap == null) {
      final items = Preset._parsePromptOrderItems(rawContext);
      if (items.isEmpty) {
        return null;
      }
      return _PromptOrderContext(priority: 0, items: items);
    }

    final rawOrder =
        contextMap['order'] ?? contextMap['items'] ?? contextMap['prompts'];
    final items = Preset._parsePromptOrderItems(rawOrder);
    if (items.isEmpty) {
      return null;
    }

    final isCharacterSpecific = Preset._isCharacterSpecificContext(
      contextMap['character_id'] ??
          contextMap['characterId'] ??
          contextMap['character'],
      contextTag,
    );

    return _PromptOrderContext(
      priority: isCharacterSpecific ? 1 : 0,
      items: items,
    );
  }
}

class _PromptOrderItem {
  final String identifier;
  final int orderIndex;
  final bool? enabled;
  final int? injectionDepth;
  final int? injectionPosition;
  final int? injectionOrder;
  final String? role;
  final String? attachRole;
  final int? attachIndex;
  final String? attachSide;

  const _PromptOrderItem({
    required this.identifier,
    required this.orderIndex,
    required this.enabled,
    required this.injectionDepth,
    required this.injectionPosition,
    required this.injectionOrder,
    required this.role,
    required this.attachRole,
    required this.attachIndex,
    required this.attachSide,
  });
}

class _IndexedPrompt {
  final PresetPrompt prompt;
  final int originalIndex;

  const _IndexedPrompt({
    required this.prompt,
    required this.originalIndex,
  });
}

class _PresetImportReportBuilder {
  int promptsParsed = 0;
  int promptsSkipped = 0;
  int regexParsed = 0;
  int regexSkipped = 0;
  int promptOrderEntries = 0;
  final List<String> _warnings = [];

  void warn(String warning) {
    if (warning.trim().isEmpty) {
      return;
    }
    if (!_warnings.contains(warning)) {
      _warnings.add(warning);
    }
  }

  PresetImportReport build() {
    return PresetImportReport(
      promptsParsed: promptsParsed,
      promptsSkipped: promptsSkipped,
      regexParsed: regexParsed,
      regexSkipped: regexSkipped,
      promptOrderEntries: promptOrderEntries,
      warnings: List.unmodifiable(_warnings),
    );
  }
}
