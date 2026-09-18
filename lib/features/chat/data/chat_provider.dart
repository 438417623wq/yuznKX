import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../api_connection/data/api_connection_provider.dart';
import '../../presets/data/preset_provider.dart';
import '../../presets/domain/models/preset.dart';
import '../../world_info/data/world_info_provider.dart';
import '../../world_info/domain/models/world_info.dart';
import '../../memory/data/memory_provider.dart';
import '../../regex/data/regex_provider.dart';
import '../../regex/domain/models/regex_script.dart';
import '../../character/data/character_provider.dart';
import '../../character/domain/models/character.dart';
import '../../variables/data/variable_provider.dart';
import '../../user/data/persona_provider.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/session.dart';
import 'chat_service.dart';
import 'local_llm_service.dart';
import 'rp_hub_context_builder.dart';
import 'session_provider.dart';
import 'transport/chat_transport.dart';
import 'world_info_runtime.dart';

import 'dart:async';
import 'dart:math' as math;

final chatServiceProvider = Provider((ref) => ChatService(ref));

// Global Stream Toggle
final isStreamEnabledProvider = StateProvider<bool>((ref) => true);

// Frontend Rendering State (Dynamic Styles)
final activeRenderStylesProvider =
    StateProvider<Map<String, dynamic>>((ref) => {});

// Family provider for chat sessions
final chatSessionProvider =
    StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>(
        (ref, sessionId) {
  return ChatNotifier(ref, sessionId);
});

// Family providers for status
final chatLoadingProviderFamily =
    StateProvider.family<bool, String>((ref, sessionId) => false);
final isGeneratingProviderFamily =
    StateProvider.family<bool, String>((ref, sessionId) => false);

/// 世界书 Token 预算溢出提示。
///
/// 只有在「全局世界信息/知识书激活设置」里打开「溢出警报」时才会被赋值；
/// 聊天页 `ref.listen` 到之后弹一次 SnackBar，然后立刻清空。
final worldInfoOverflowNoticeProvider = StateProvider<String?>((ref) => null);

enum _GenerationType {
  normal,
  continueMode,
  impersonate,
  quiet,
}

enum _WorldInfoScanState {
  initial,
  recursion,
  minActivations,
  none,
}

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  final String sessionId;
  static const int _defaultMaxContextTokens = 4096;
  static const int _defaultResponseReserve = 320;
  StreamSubscription<ChatStreamEvent>? _generationSubscription;
  int _generationSerial = 0;
  int? _activeGenerationId;
  Completer<void>? _generationCompleter;
  CancelToken? _generationCancelToken;
  DateTime? _rateLimitBlockUntil;

  /// 最近一次世界书扫描是否因 Token 预算溢出而丢弃了条目。
  bool _lastWorldInfoOverflowed = false;

  ChatNotifier(this._ref, this.sessionId) : super([]) {
    _loadSession();
  }

  Session? _getSession() {
    try {
      return _ref.read(sessionProvider).firstWhere((s) => s.id == sessionId);
    } catch (_) {
      return null;
    }
  }

  Character? _getCharacter() {
    final session = _getSession();
    if (session == null || session.characterId.isEmpty) {
      return null;
    }

    try {
      final characters = _ref.read(characterListProvider);
      return characters.firstWhere((c) => c.id == session.characterId);
    } catch (_) {
      return null;
    }
  }

  List<Character> _getSessionCharacters() {
    final session = _getSession();
    final characters = _ref.read(characterListProvider);
    if (session == null) {
      return const [];
    }

    if (session.isGroup) {
      final byId = {
        for (final character in characters) character.id: character,
      };
      return [
        for (final id in session.groupCharacterIds)
          if (byId.containsKey(id)) byId[id]!,
      ];
    }

    final single = _getCharacter();
    return single == null ? const [] : [single];
  }

  String _getGroupMemberNames() {
    final names = _getSessionCharacters()
        .map((character) => character.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return names.join(', ');
  }

  String _replaceMacros(
    String text,
    Character? character, {
    Map<String, String> extraMacros = const <String, String>{},
  }) {
    final replacements = <String, String>{
      'user': _getUserName(),
      'char': character?.name ?? '',
      'charIfNotGroup':
          (_getSession()?.isGroup ?? false) ? '' : (character?.name ?? ''),
      'group': _getGroupMemberNames(),
      ...extraMacros,
    };

    var result = text;
    for (final entry in replacements.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }

    return _resolveVariableMacros(result);
  }

  String _resolveVariableMacros(String input) {
    if (input.isEmpty || !input.contains('{{')) {
      return input;
    }

    var output = input;
    final standardPattern = RegExp(
      r'\{\{(get|set|add|inc|dec)_(global|chat)_variable::([^}:]+?)(?:::(.*?))?\}\}',
      caseSensitive: false,
    );

    output = output.replaceAllMapped(standardPattern, (match) {
      final action = (match.group(1) ?? '').toLowerCase();
      final scope = (match.group(2) ?? '').toLowerCase();
      final key = (match.group(3) ?? '').trim();
      final payload = match.group(4) ?? '';
      return _executeVariableMacro(action, scope, key, payload);
    });

    final shorthandPattern = RegExp(
      r'\{\{(getvar|setvar|addvar|incvar|decvar|getglobalvar|setglobalvar|addglobalvar|incglobalvar|decglobalvar)::([^}:]+?)(?:::(.*?))?\}\}',
      caseSensitive: false,
    );

    output = output.replaceAllMapped(shorthandPattern, (match) {
      final command = (match.group(1) ?? '').toLowerCase();
      final key = (match.group(2) ?? '').trim();
      final payload = match.group(3) ?? '';

      late String action;
      late String scope;
      if (command == 'getvar' || command == 'setvar' || command == 'addvar') {
        scope = 'chat';
      } else {
        scope = 'global';
      }
      if (command.startsWith('get')) {
        action = 'get';
      } else if (command.startsWith('set')) {
        action = 'set';
      } else if (command.startsWith('inc')) {
        action = 'inc';
      } else if (command.startsWith('dec')) {
        action = 'dec';
      } else {
        action = 'add';
      }

      return _executeVariableMacro(action, scope, key, payload);
    });

    final getterAliasPattern = RegExp(
      r'\{\{(var|chatvar|globalvar)::([^}:]+?)\}\}',
      caseSensitive: false,
    );

    output = output.replaceAllMapped(getterAliasPattern, (match) {
      final command = (match.group(1) ?? '').toLowerCase();
      final key = (match.group(2) ?? '').trim();
      final scope = command == 'globalvar' ? 'global' : 'chat';
      return _executeVariableMacro('get', scope, key, '');
    });

    return output;
  }

  String _executeVariableMacro(
    String action,
    String scope,
    String key,
    String payload,
  ) {
    if (key.isEmpty) {
      return '';
    }

    final isGlobal = scope == 'global';
    if (isGlobal) {
      final notifier = _ref.read(globalVariablesProvider.notifier);
      final value = _executeVariableAction(action, notifier, key, payload);
      return value?.toString() ?? '';
    }

    final notifier = _ref.read(chatVariablesProvider(sessionId).notifier);
    final value = _executeVariableAction(action, notifier, key, payload);
    return value?.toString() ?? '';
  }

  dynamic _executeVariableAction(
    String action,
    dynamic notifier,
    String key,
    String payload,
  ) {
    if (action == 'get') {
      return notifier.getValue(key) ?? '';
    }

    if (action == 'set') {
      notifier.setValue(key, payload);
      return '';
    }

    if (action == 'add') {
      notifier.addValue(key, payload);
      return '';
    }

    if (action == 'inc') {
      return notifier.addValue(key, 1) ?? '';
    }

    if (action == 'dec') {
      return notifier.addValue(key, -1) ?? '';
    }

    return '';
  }

  String _getUserName() {
    try {
      final persona = _ref.read(personaProvider);
      final name = persona.name.trim();
      if (name.isNotEmpty) {
        return name;
      }
    } catch (_) {}
    return 'User';
  }

  String _getUserDescription() {
    try {
      final persona = _ref.read(personaProvider);
      return persona.description.trim();
    } catch (_) {
      return '';
    }
  }

  void _loadSession() {
    final sessions = _ref.read(sessionProvider);
    try {
      final session = sessions.firstWhere((s) => s.id == sessionId);
      state = session.messages;
    } catch (_) {
      state = [];
    }
    checkEmptyState();
  }

  void checkEmptyState() {
    if (state.isEmpty) {
      final character = _getCharacter();
      if (character != null && character.firstMessage.isNotEmpty) {
        final firstMsgContent = _prepareGreeting(character.firstMessage);
        state = [
          ChatMessage(
              role: 'assistant',
              content: firstMsgContent,
              timestamp: DateTime.now(),
              swipes: [firstMsgContent],
              currentIndex: 0,
              metadata: {
                'characterId': character.id,
                'name': character.name,
              })
        ];
        _persistMessages();
      }
    }
  }

  Future<void> clearHistory({String? customGreeting}) async {
    state = [];
    if (customGreeting != null && customGreeting.isNotEmpty) {
      final character = _getCharacter();
      final firstMsgContent = _prepareGreeting(customGreeting);
      state = [
        ChatMessage(
            role: 'assistant',
            content: firstMsgContent,
            timestamp: DateTime.now(),
            swipes: [firstMsgContent],
            currentIndex: 0,
            metadata: character == null
                ? null
                : {
                    'characterId': character.id,
                    'name': character.name,
                  })
      ];
      await _persistMessages();
    } else {
      checkEmptyState();
      await _persistMessages();
    }
  }

  String _prepareGreeting(String rawGreeting) {
    final character = _getCharacter();
    final macroExpanded = _replaceMacros(rawGreeting, character);
    return _applyRegex(
      macroExpanded,
      2,
      includePromptOnly: false,
      messageDepth: 1,
      preventEmptyResult: true,
    );
  }

  int _startGeneration() {
    final generationId = ++_generationSerial;
    _generationCancelToken = CancelToken();
    _activeGenerationId = generationId;
    _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = true;
    _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = true;
    return generationId;
  }

  bool _isGenerationActive(int generationId) {
    return _activeGenerationId == generationId;
  }

  void _finishGeneration(int generationId) {
    if (_activeGenerationId != generationId) {
      return;
    }
    _activeGenerationId = null;
    _generationSubscription = null;
    _generationCompleter = null;
    _generationCancelToken = null;
    _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
    _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;
  }

  Future<void> stopGeneration() async {
    if (_activeGenerationId == null) {
      return;
    }

    _activeGenerationId = null;
    _generationCancelToken?.cancel('generation stopped by user');
    _generationCancelToken = null;
    final sub = _generationSubscription;
    _generationSubscription = null;

    final completer = _generationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _generationCompleter = null;

    _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
    _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;

    if (sub != null) {
      unawaited(sub.cancel());
    }
    _ref.read(localLlmServiceProvider).stop();

    await _persistMessages();
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    if (_activeGenerationId != null) {
      await stopGeneration();
    }

    // Note: session creation is now handled by SessionManager or ensuring valid ID before calling this.
    // If sessionId refers to a non-existent session, we might have issues.
    // But typically ChatNotifier is created with a valid ID.

    final character = _getCharacter();
    final macroExpandedContent = _replaceMacros(content, character);
    final processedContent = _applyRegex(
      macroExpandedContent,
      1,
      includePromptOnly: false,
      messageDepth: 1,
    );

    final userMsg = ChatMessage(
        role: 'user',
        content: processedContent,
        timestamp: DateTime.now(),
        swipes: [processedContent],
        currentIndex: 0,
        metadata: {
          'name': _getUserName(),
        });
    state = [...state, userMsg];

    await _persistMessages();

    // Check for Group Chat
    final sessions = _ref.read(sessionProvider);
    try {
      final session = sessions.firstWhere((s) => s.id == sessionId);
      if (session.isGroup) {
        for (final charId in session.groupCharacterIds) {
          await _processResponse(characterId: charId);
        }
      } else {
        await _processResponse();
      }
    } catch (_) {
      await _processResponse();
    }
  }

  Future<void> continueGeneration() async {
    if (state.isEmpty) return;

    if (_activeGenerationId != null) {
      await stopGeneration();
    }

    final lastMsg = state.last;
    if (lastMsg.role == 'assistant') {
      await _processResponse(continueLast: true);
    } else {
      await _processResponse();
    }
  }

  Future<void> generateImpersonationReply() async {
    if (_activeGenerationId != null) {
      await stopGeneration();
    }
    await _processResponse(generationType: _GenerationType.impersonate);
  }

  Future<void> generateQuietPrompt(String quietPrompt) async {
    if (quietPrompt.trim().isEmpty) {
      return;
    }
    if (_activeGenerationId != null) {
      await stopGeneration();
    }
    await _processResponse(
      generationType: _GenerationType.quiet,
      quietPrompt: quietPrompt,
    );
  }

  Future<void> regenerateLast() async {
    if (state.isEmpty) return;

    if (_activeGenerationId != null) {
      await stopGeneration();
    }

    final lastIndex = state.length - 1;
    final lastMsg = state[lastIndex];
    if (lastMsg.role == 'assistant') {
      await _processResponse(regenerate: true, overrideTargetIndex: lastIndex);
    }
  }

  Future<void> regenerateMessage(int index) async {
    if (index < 0 || index >= state.length) return;

    if (_activeGenerationId != null) {
      await stopGeneration();
    }

    final msg = state[index];
    if (msg.role == 'assistant') {
      await _processResponse(regenerate: true, overrideTargetIndex: index);
    }
  }

  Future<void> _processResponse({
    bool continueLast = false,
    bool regenerate = false,
    int? overrideTargetIndex,
    String? characterId,
    _GenerationType generationType = _GenerationType.normal,
    String quietPrompt = '',
  }) async {
    final connection = _ref.read(activeApiConnectionProvider);
    if (connection == null) {
      const errorText = 'Error: no API connection selected.';
      state = [
        ...state,
        ChatMessage(
          role: 'system',
          content: errorText,
          timestamp: DateTime.now(),
          swipes: const [errorText],
          currentIndex: 0,
        ),
      ];
      await _persistMessages();
      return;
    }

    if (_rateLimitBlockUntil != null &&
        DateTime.now().isBefore(_rateLimitBlockUntil!)) {
      final remainingSeconds =
          _rateLimitBlockUntil!.difference(DateTime.now()).inSeconds + 1;
      final waitText = '请求过于频繁，请约 $remainingSeconds 秒后再试。';
      state = [
        ...state,
        ChatMessage(
          role: 'system',
          content: waitText,
          timestamp: DateTime.now(),
          swipes: [waitText],
          currentIndex: 0,
        ),
      ];
      await _persistMessages();
      return;
    }

    final generationId = _startGeneration();
    final cancelToken = _generationCancelToken;
    final effectiveGenerationType =
        continueLast ? _GenerationType.continueMode : generationType;

    try {
      Character? character;
      if (characterId != null) {
        try {
          character = _ref
              .read(characterListProvider)
              .firstWhere((c) => c.id == characterId);
        } catch (_) {
          character = null;
        }
      } else {
        character = _getCharacter();
      }

      int targetIndex = -1;
      late ChatMessage targetMsg;

      if (regenerate && overrideTargetIndex != null) {
        if (overrideTargetIndex < 0 || overrideTargetIndex >= state.length) {
          return;
        }

        targetIndex = overrideTargetIndex;
        final oldMsg = state[targetIndex];
        final newSwipes = List<String>.from(oldMsg.swipes)..add('');
        targetMsg = oldMsg.copyWith(
          swipes: newSwipes,
          currentIndex: newSwipes.length - 1,
          content: '',
        );
      } else if (continueLast) {
        if (state.isEmpty) {
          return;
        }

        targetIndex = state.length - 1;
        targetMsg = state[targetIndex];
      } else {
        targetMsg = ChatMessage(
          role: 'assistant',
          content: '',
          timestamp: DateTime.now(),
          swipes: const [''],
          currentIndex: 0,
          metadata: character != null
              ? {'characterId': character.id, 'name': character.name}
              : null,
        );
        state = [...state, targetMsg];
        targetIndex = state.length - 1;
      }

      if (!_isGenerationActive(generationId) || targetIndex < 0) {
        return;
      }

      final List<ChatMessage> newState = List.from(state);
      newState[targetIndex] = targetMsg;
      state = newState;

      List<ChatMessage> history;
      if (regenerate) {
        history = state.sublist(0, targetIndex);
      } else if (continueLast) {
        history = state.sublist(0, targetIndex);
        history = [...history, targetMsg];
      } else {
        history = state.sublist(0, targetIndex);
      }
      history = _applyChatVisibilityRange(history);

      final session = _getSession();
      final activeWiIds = _collectOrderedActiveWorldInfoIds(
        session: session,
        character: character,
      );
      final worldInfoSourceKindById = _buildWorldInfoSourceKindById(
        session: session,
        character: character,
      );

      final activePreset = _ref.read(activePresetProvider);
      final preferredModel = character?.preferredModelName;

      final scanContext = _buildWorldInfoScanContext(
        history,
        character: character,
      );
      final injectedWorldInfoItems = _scanWorldInfo(
        scanContext,
        overrideWorldInfoIds: activeWiIds,
        worldInfoSourceKindById: worldInfoSourceKindById,
      );
      final injectedWorldInfo = [
        for (final item in injectedWorldInfoItems) item.entry,
      ];

      if (injectedWorldInfo.isNotEmpty) {
        print(
            '=== World Info Injected (${injectedWorldInfo.length} entries) ===');
        injectedWorldInfo.forEach((e) => print(
            '- ${e.content.length > 50 ? e.content.substring(0, 50) + "..." : e.content}'));
      } else {
        print('=== No World Info Triggered ===');
      }

      final constructedPrompt = _constructPrompt(
        history,
        injectedWorldInfo,
        overridePreset: activePreset,
        activeCharacter: character,
        generationType: effectiveGenerationType,
        quietPrompt: quietPrompt,
      );
      final effectiveMessagesToSend = _applyPromptOnlyRegexToMessages(
        constructedPrompt.messages,
        overridePreset: activePreset,
      );

      final preset = activePreset;
      final presetParams = <String, dynamic>{};
      if (preset != null) {
        presetParams['temperature'] = preset.temperature.clamp(0.0, 2.0);
        presetParams['frequency_penalty'] =
            preset.frequencyPenalty.clamp(-2.0, 2.0);
        presetParams['presence_penalty'] =
            preset.presencePenalty.clamp(-2.0, 2.0);
        presetParams['top_p'] = preset.topP.clamp(0.0, 1.0);

        // max_tokens 必须与上下文预算里预留的空间一致，否则请求可能直接超窗。
        final safeMaxTokens = constructedPrompt.responseReserveTokens > 0
            ? constructedPrompt.responseReserveTokens
            : preset.maxTokens;
        presetParams['max_tokens'] = safeMaxTokens.clamp(1, 131072);

        if (preset.topK > 0) {
          presetParams['top_k'] = preset.topK.clamp(1, 1000);
        }
        if (preset.repetitionPenalty != 1.0) {
          presetParams['repetition_penalty'] =
              preset.repetitionPenalty.clamp(0.5, 2.0);
        }

        // 停止序列必须先过一遍宏替换：酒馆会把 `{{user}}` / `{{char}}`
        // 换成实际名字再下发，否则 `\n{{user}}:` 这类停止串永远匹配不上。
        // 同时过滤掉长度 ≤1 的项 —— 单个字符（换行、句号、空格）会让生成
        // 刚开始就被截断，这是「AI 吐字很少」最常见的元凶。
        final stops = preset.stopStrings
            .map((value) => _replaceMacros(value.trim(), character))
            .where((value) => value.trim().length > 1)
            .toSet()
            .toList(growable: false);
        if (stops.isNotEmpty) {
          presetParams['stop'] = stops;
        }
      }

      // 连接级参数（本地模型线程/上下文、chat 模板、include_usage 等）合并进来，
      // 预设里的采样参数优先级更高。本地专属键由协议适配层过滤，不会外泄给远程 API。
      final params = <String, dynamic>{
        ...connection.parameters,
        ...presetParams,
      };

      final service = _ref.read(chatServiceProvider);

      final metadata = {
        'model': preferredModel ?? connection.model,
        'params': params,
        'context_size': constructedPrompt.maxContextTokens,
        'response_reserve': constructedPrompt.responseReserveTokens,
        'protocol': service.adapterFor(connection).id,
        'prompt': ChatService.serializeMessagesForApi(effectiveMessagesToSend),
        'prompt_preview': _buildPromptPreviewPayload(
          constructedPrompt.assemblyMessages,
          effectiveMessagesToSend,
        ),
        'timestamp': DateTime.now().toIso8601String(),
        'pipeline': {
          'mode': 'frontend_prompt_assembly',
          'generationType': effectiveGenerationType.name,
          'historyCount': history.length,
          'activeWorldInfoIds': activeWiIds,
          'worldInfoCount': injectedWorldInfoItems.length,
          'worldInfoOverflowed': _lastWorldInfoOverflowed,
          'worldInfo': injectedWorldInfoItems
              .map((item) => {
                    'uid': item.entry.uid,
                    'comment': item.entry.comment,
                    'depth': item.entry.depth,
                    'position': item.entry.position,
                    'activation_key': _buildWorldInfoActivationKey(item.entry),
                    'world_info_id': item.worldInfoId,
                    'world_info_name': item.worldInfoName,
                    'source': item.sourceKind,
                    'source_order': item.sourceOrder,
                  })
              .toList(),
          // 记忆注入概况。过去调试面板只暴露世界书，记忆出了问题是黑盒：
          // 槽位被关掉、走了兜底、或压根没内容，用户都无从判断。
          'memory': _buildMemoryPipelineInfo(constructedPrompt),
        },
      };
      targetMsg = targetMsg.copyWith(metadata: metadata);

      final List<ChatMessage> newStateWithMeta = List.from(state);
      if (targetIndex >= 0 && targetIndex < newStateWithMeta.length) {
        newStateWithMeta[targetIndex] = targetMsg;
        state = newStateWithMeta;
      }

      final isStreamEnabled = _ref.read(isStreamEnabledProvider);

      if (!_isGenerationActive(generationId)) {
        return;
      }

      if (isStreamEnabled) {
        final stream = service.streamMessage(
          connection: connection,
          messages: effectiveMessagesToSend,
          parameters: params,
          overrideModel: preferredModel,
          cancelToken: cancelToken,
        );
        await _handleStream(stream, targetIndex, generationId);
      } else {
        final future = service.sendMessage(
          connection: connection,
          messages: effectiveMessagesToSend,
          parameters: params,
          overrideModel: preferredModel,
          cancelToken: cancelToken,
        );
        await _handleNonStream(future, targetIndex, generationId);
      }
    } catch (e) {
      print("Start generation error: $e");
      final errorText = 'Error: ${_formatErrorMessage(e)}';
      state = [
        ...state,
        ChatMessage(
          role: 'system',
          content: errorText,
          timestamp: DateTime.now(),
          swipes: [errorText],
          currentIndex: 0,
        ),
      ];
      await _persistMessages();
    } finally {
      _finishGeneration(generationId);
    }
  }

  @override
  void dispose() {
    _activeGenerationId = null;
    _generationCancelToken?.cancel('chat notifier disposed');
    _generationCancelToken = null;

    final sub = _generationSubscription;
    _generationSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    final completer = _generationCompleter;
    _generationCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    super.dispose();
  }

  void _postProcessMessage(int targetIndex, String sessionId) {
    try {
      final finalMsg = state[targetIndex];
      final content = finalMsg.content;
      // Use captured activeRegexIds and activePreset
      final activeRegexIds = _ref.read(activeRegexScriptIdsProvider);
      final activePreset = _ref.read(activePresetProvider);

      final processed = _applyRegex(
        content,
        2,
        overrideRegexIds: activeRegexIds,
        overridePreset: activePreset,
        includePromptOnly: false,
        messageDepth: 1,
        preventEmptyResult: true,
      );

      // Extract <think> content if present
      String finalContent = processed;
      String? thoughtContent;

      // Process Memory Commands
      try {
        final memorySettings = _ref.read(memoryPluginSettingsProvider);
        final memoryEnabled = memorySettings.isPluginEnabled;
        // 记忆是**会话级**的。用户可能在生成期间切换了对话，此时
        // memoryProvider 已指向另一条会话 —— 若照旧写回，这张表格的内容
        // 会被串到别的对话里。因此只在「生成时的会话仍是当前活跃会话」时落库。
        // 注意：下面剥离 <tableEdit> 标签的逻辑不受影响，那是显示层的事。
        final isSameSession = _ref.read(activeSessionIdProvider) == sessionId;
        _ref.read(memoryProvider.notifier).processCommands(
              finalContent,
              allowWrites: isSameSession &&
                  memoryEnabled &&
                  memorySettings.isAiWriteTable,
            );
        if (memoryEnabled) {
          final contentBeforeStrip = finalContent;
          var strippedContent = finalContent
              .replaceAll(
                RegExp(r'<tableEdit>.*?</tableEdit>', dotAll: true),
                '',
              )
              .replaceAll(
                RegExp(r'<tableThink>.*?</tableThink>', dotAll: true),
                '',
              )
              .trim();

          // Avoid stripping away image markdown/html when table tags wrap output.
          if (_containsImageMarkup(contentBeforeStrip) &&
              !_containsImageMarkup(strippedContent)) {
            strippedContent = contentBeforeStrip
                .replaceAll(RegExp(r'</?tableEdit>', caseSensitive: false), '')
                .replaceAll(RegExp(r'</?tableThink>', caseSensitive: false), '')
                .trim();
          }
          finalContent = strippedContent;
        }
      } catch (e) {
        print('Error processing memory commands in chat: $e');
      }

      // Simple regex for <think>...</think> (dotAll)
      final thinkRegex = RegExp(r'<think>(.*?)</think>', dotAll: true);
      final match = thinkRegex.firstMatch(finalContent);
      if (match != null) {
        thoughtContent = match.group(1)?.trim();
        // Remove the think tag from the displayed content
        finalContent = finalContent.replaceAll(thinkRegex, '').trim();
      }

      if (finalContent != content || thoughtContent != null) {
        final swipes = List<String>.from(finalMsg.swipes);
        swipes[finalMsg.currentIndex] = finalContent;

        // Update metadata with thought
        Map<String, dynamic>? newMetadata = finalMsg.metadata;
        if (thoughtContent != null) {
          newMetadata = Map<String, dynamic>.from(newMetadata ?? {});
          newMetadata['thought'] = thoughtContent;
        }

        final processedMsg = finalMsg.copyWith(
            content: finalContent, swipes: swipes, metadata: newMetadata);

        final newState = List<ChatMessage>.from(state);
        newState[targetIndex] = processedMsg;
        state = newState;
        _persistMessages();
      }
    } catch (e) {
      print('Error post-processing message: $e');
    }
  }

  bool _containsImageMarkup(String content) {
    if (content.isEmpty) {
      return false;
    }
    final markdownImage = RegExp(r'!\[[^\]]*\]\([^)]+\)', multiLine: true);
    final imageLabelBlock = RegExp(
      r'(^|\n)\s*Image\s*\n\s*https?://\S+',
      caseSensitive: false,
      multiLine: true,
    );
    final htmlImage = RegExp(
      r'''<img\b[^>]*\bsrc\s*=\s*['"][^'"]+['"][^>]*>''',
      caseSensitive: false,
      multiLine: true,
    );
    final directImageUrl = RegExp(
      r'https?://\S+',
      caseSensitive: false,
      multiLine: true,
    );
    final hasDirectImageUrl = directImageUrl.allMatches(content).any((match) {
      final url = (match.group(0) ?? '').toLowerCase();
      if (url.contains('image.pollinations.ai')) {
        return true;
      }
      return url.endsWith('.png') ||
          url.endsWith('.jpg') ||
          url.endsWith('.jpeg') ||
          url.endsWith('.webp') ||
          url.endsWith('.gif') ||
          url.endsWith('.bmp');
    });

    return markdownImage.hasMatch(content) ||
        htmlImage.hasMatch(content) ||
        imageLabelBlock.hasMatch(content) ||
        hasDirectImageUrl;
  }

  void _analyzeSentiment(String text) {
    final lower = text.toLowerCase();
    String? expression;
    // Simple keyword matching for demo purposes
    if (lower.contains('smile') ||
        lower.contains('laugh') ||
        lower.contains('grin') ||
        lower.contains('happy'))
      expression = 'joy';
    else if (lower.contains('cry') ||
        lower.contains('sob') ||
        lower.contains('tear') ||
        lower.contains('sad'))
      expression = 'sadness';
    else if (lower.contains('angry') ||
        lower.contains('rage') ||
        lower.contains('furious') ||
        lower.contains('hate'))
      expression = 'anger';
    else if (lower.contains('blush') ||
        lower.contains('shy') ||
        lower.contains('love'))
      expression = 'shyness';
    else if (lower.contains('scared') ||
        lower.contains('fear') ||
        lower.contains('afraid'))
      expression = 'fear';
    else if (lower.contains('surprised') || lower.contains('shocked'))
      expression = 'surprise';

    if (expression != null) {
      // Update state only if changed to avoid rebuilds
      final current = _ref.read(activeRenderStylesProvider)['expression'];
      if (current != expression) {
        _ref.read(activeRenderStylesProvider.notifier).state = {
          ..._ref.read(activeRenderStylesProvider),
          'expression': expression
        };
      }
    }
  }

  Future<void> _handleStream(Stream<ChatStreamEvent> stream, int targetIndex,
      int generationId) async {
    final completer = Completer<void>();
    _generationCompleter = completer;
    int chunkCount = 0;
    ChatUsage? usage;
    String? finishReason;

    _generationSubscription = stream.listen(
      (event) {
        if (event.usage != null) {
          usage = usage?.merge(event.usage) ?? event.usage;
        }
        if (event.finishReason != null) {
          finishReason = event.finishReason;
        }

        final chunk = event.text;
        if (chunk == null || chunk.isEmpty) {
          return;
        }

        if (!_isGenerationActive(generationId)) {
          return;
        }
        if (targetIndex < 0 || targetIndex >= state.length) {
          return;
        }

        _analyzeSentiment(chunk);

        final currentMsg = state[targetIndex];
        final currentSwipes = List<String>.from(currentMsg.swipes);
        final currentIndex = currentMsg.currentIndex;

        final newContent = currentSwipes[currentIndex] + chunk;
        currentSwipes[currentIndex] = newContent;

        final updatedMsg = currentMsg.copyWith(
          content: newContent,
          swipes: currentSwipes,
        );

        final newState = List<ChatMessage>.from(state);
        newState[targetIndex] = updatedMsg;
        state = newState;

        chunkCount++;
        if (chunkCount % 20 == 0) {
          _persistMessages();
        }
      },
      onDone: () {
        if (_isGenerationActive(generationId)) {
          _attachGenerationStats(
            targetIndex,
            usage: usage,
            finishReason: finishReason,
          );
          _persistMessages();
          _postProcessMessage(targetIndex, sessionId);
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (e) async {
        if (_isGenerationActive(generationId)) {
          print("Generation error: $e");
          await _applyGenerationError(targetIndex, e);
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  /// 把服务端返回的 usage / finish_reason 写进消息 metadata，便于调试与统计。
  void _attachGenerationStats(
    int targetIndex, {
    ChatUsage? usage,
    String? finishReason,
  }) {
    if (usage == null && finishReason == null) {
      return;
    }
    if (targetIndex < 0 || targetIndex >= state.length) {
      return;
    }

    final msg = state[targetIndex];
    final metadata = <String, dynamic>{...?msg.metadata};
    if (usage != null) {
      metadata['usage'] = usage.toJson();
    }
    if (finishReason != null) {
      metadata['finish_reason'] = finishReason;
    }

    final newState = List<ChatMessage>.from(state);
    newState[targetIndex] = msg.copyWith(metadata: metadata);
    state = newState;
  }

  Future<void> _handleNonStream(Future<ChatCompletionResult> future,
      int targetIndex, int generationId) async {
    final completer = Completer<void>();
    _generationCompleter = completer;

    future.then((result) async {
      if (!_isGenerationActive(generationId)) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      if (targetIndex < 0 || targetIndex >= state.length) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final content = result.text;
      _analyzeSentiment(content);

      final currentMsg = state[targetIndex];
      final currentSwipes = List<String>.from(currentMsg.swipes);
      final currentIndex = currentMsg.currentIndex;

      currentSwipes[currentIndex] = content;

      final updatedMsg = currentMsg.copyWith(
        content: content,
        swipes: currentSwipes,
      );

      final newState = List<ChatMessage>.from(state);
      newState[targetIndex] = updatedMsg;
      state = newState;

      _attachGenerationStats(
        targetIndex,
        usage: result.usage,
        finishReason: result.finishReason,
      );

      await _persistMessages();
      _postProcessMessage(targetIndex, sessionId);

      if (!completer.isCompleted) {
        completer.complete();
      }
    }).catchError((e) async {
      if (_isGenerationActive(generationId)) {
        print("Non-stream generation error: $e");
        await _applyGenerationError(targetIndex, e);
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;
  }

  Future<void> _applyGenerationError(int targetIndex, Object error) async {
    final errorText = 'Error: ${_formatErrorMessage(error)}';
    _updateRateLimitState(errorText);

    if (targetIndex >= 0 && targetIndex < state.length) {
      final currentMsg = state[targetIndex];
      final currentSwipes = List<String>.from(currentMsg.swipes);
      if (currentSwipes.isEmpty) {
        currentSwipes.add(errorText);
      } else {
        final index =
            currentMsg.currentIndex.clamp(0, currentSwipes.length - 1).toInt();
        currentSwipes[index] = errorText;
      }

      final updatedMsg = currentMsg.copyWith(
        content: errorText,
        swipes: currentSwipes,
      );
      final newState = List<ChatMessage>.from(state);
      newState[targetIndex] = updatedMsg;
      state = newState;
    } else {
      state = [
        ...state,
        ChatMessage(
          role: 'system',
          content: errorText,
          timestamp: DateTime.now(),
          swipes: [errorText],
          currentIndex: 0,
        ),
      ];
    }

    await _persistMessages();
  }

  void _updateRateLimitState(String errorText) {
    if (!errorText.contains('HTTP 429')) {
      return;
    }
    final seconds = _extractRetrySeconds(errorText);
    final waitSeconds = (seconds ?? 20).clamp(3, 120);
    _rateLimitBlockUntil = DateTime.now().add(Duration(seconds: waitSeconds));
  }

  int? _extractRetrySeconds(String text) {
    final zh = RegExp(r'约\s*(\d+)\s*秒').firstMatch(text);
    if (zh != null) {
      return int.tryParse(zh.group(1)!);
    }
    final en =
        RegExp(r'(\d+)\s*seconds?', caseSensitive: false).firstMatch(text);
    if (en != null) {
      return int.tryParse(en.group(1)!);
    }
    return null;
  }

  String _formatErrorMessage(Object error) {
    var text = error.toString().trim();
    if (text.startsWith('Exception:')) {
      text = text.substring('Exception:'.length).trim();
    }
    final line = text.split('\n').first.trim();
    if (line.isEmpty) {
      return 'unknown error';
    }
    if (line.length > 260) {
      return '${line.substring(0, 260)}...';
    }
    return line;
  }

  void swipeMessage(int index, int swipeIndex) {
    if (index < 0 || index >= state.length) return;

    final msg = state[index];
    if (swipeIndex < 0 || swipeIndex >= msg.swipes.length) return;

    final updatedMsg = msg.copyWith(
      content: msg.swipes[swipeIndex],
      currentIndex: swipeIndex,
    );

    final newState = [...state];
    newState[index] = updatedMsg;
    state = newState;
    _persistMessages();
  }

  void addSwipe(int index, String newContent) {
    if (index < 0 || index >= state.length) return;

    final msg = state[index];
    final newSwipes = [...msg.swipes, newContent];
    final updatedMsg = msg.copyWith(
      swipes: newSwipes,
      currentIndex: newSwipes.length - 1,
      content: newContent,
    );

    final newState = [...state];
    newState[index] = updatedMsg;
    state = newState;
    _persistMessages();
  }

  void editMessage(int index, String newContent) {
    if (index < 0 || index >= state.length) return;

    final msg = state[index];

    List<String> newSwipes = [...msg.swipes];
    if (newSwipes.isNotEmpty &&
        msg.currentIndex >= 0 &&
        msg.currentIndex < newSwipes.length) {
      newSwipes[msg.currentIndex] = newContent;
    } else {
      newSwipes = [newContent];
    }

    final updatedMsg = msg.copyWith(content: newContent, swipes: newSwipes);

    final newState = [...state];
    newState[index] = updatedMsg;
    state = newState;
    _persistMessages();
  }

  Future<void> _persistMessages() async {
    final session = _getSession();
    await _ref.read(sessionProvider.notifier).updateSessionMessages(
          sessionId,
          state,
          fallbackCharacterId: session?.characterId,
          fallbackName: session?.name,
          fallbackGroupCharacterIds: session?.groupCharacterIds,
          fallbackWorldInfoIds: session?.worldInfoIds,
        );
  }

  String _applyRegex(
    String text,
    int placement, {
    List<String>? overrideRegexIds,
    Preset? overridePreset,
    bool includePromptOnly = false,
    bool promptOnlyOnly = false,
    int? messageDepth,
    bool preventEmptyResult = false,
  }) {
    if (text.isEmpty) {
      return text;
    }

    var result = text;
    final activeScripts = _collectActiveRegexScripts(
      overrideRegexIds: overrideRegexIds,
      overridePreset: overridePreset,
    );

    for (final script in activeScripts) {
      if (!script.placement.contains(placement)) {
        continue;
      }
      if (promptOnlyOnly && !script.promptOnly) {
        continue;
      }
      if (!promptOnlyOnly && !includePromptOnly && script.promptOnly) {
        continue;
      }
      if (!_isDepthMatched(script, messageDepth)) {
        continue;
      }

      result = _runScript(result, script);
    }

    if (preventEmptyResult && text.trim().isNotEmpty && result.trim().isEmpty) {
      print('Regex safeguard: prevented empty output after regex chain.');
      return text;
    }
    return result;
  }

  List<RegexScript> _collectActiveRegexScripts({
    List<String>? overrideRegexIds,
    Preset? overridePreset,
  }) {
    final activeIds = <String>{};
    if (overrideRegexIds != null) {
      activeIds.addAll(overrideRegexIds);
    } else {
      activeIds.addAll(_ref.read(activeRegexScriptIdsProvider));
    }

    final character = _getCharacter();
    if (character != null) {
      // 角色自带正则（随卡导入，extensions.regex_scripts）。
      activeIds.addAll(character.regexScriptIds);
      // 角色额外引用的全局正则（来自设置板块的全局正则池）。
      //
      // 语义上与「全局生效」相互独立：
      // - 全局生效（activeRegexScriptIdsProvider）：对所有角色卡生效
      // - globalRegexIds：仅本卡引用，不要求该脚本处于全局生效状态
      //
      // 若某脚本同时出现在两处，activeIds 是 Set，会自动去重，不会重复执行。
      for (final globalRegexId in character.globalRegexIds) {
        final normalized = globalRegexId.trim();
        if (normalized.isNotEmpty) {
          activeIds.add(normalized);
        }
      }
    }

    final dedupe = <String>{};
    final collected = <RegexScript>[];

    void append(RegexScript script) {
      if (script.disabled) {
        return;
      }
      final key = script.id.trim().isNotEmpty
          ? script.id.trim()
          : '${script.scriptName}|${script.findRegex}|${script.replaceString}|${script.placement.join(",")}';
      if (dedupe.add(key)) {
        collected.add(script);
      }
    }

    final allScripts = _ref.read(regexScriptsProvider);
    for (final script in allScripts) {
      if (activeIds.contains(script.id)) {
        append(script);
      }
    }

    final preset = overridePreset ?? _ref.read(activePresetProvider);
    if (preset != null) {
      for (final script in preset.regexScripts) {
        append(script);
      }
    }

    return collected;
  }

  bool _isDepthMatched(RegexScript script, int? depth) {
    if (depth == null) {
      return true;
    }
    if (script.minDepth != null && depth < script.minDepth!) {
      return false;
    }
    if (script.maxDepth != null && depth > script.maxDepth!) {
      return false;
    }
    return true;
  }

  List<String> _normalizeTrimStrings(RegexScript script) {
    final values = <String>{};

    for (final item in script.trimStrings) {
      final normalized = item.trim();
      if (normalized.isNotEmpty) {
        values.add(normalized);
      }
    }

    final legacyTrim = script.trimString.trim();
    if (legacyTrim.isNotEmpty) {
      for (final line in legacyTrim.split(RegExp(r'[\r\n]+'))) {
        final normalized = line.trim();
        if (normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    }

    return values.toList();
  }

  String _runScript(String input, RegexScript script) {
    try {
      var working = input;

      final trimItems = _normalizeTrimStrings(script);
      for (final trimItem in trimItems) {
        final protectTrimTargets = _shouldProtectRegexTargets(trimItem, script);
        working = _transformRegexEligibleSegments(
          working,
          protectTargets: protectTrimTargets,
          transform: (segment) => segment.replaceAll(trimItem, ''),
        );
      }

      final parsed = _parseRegexPattern(script.findRegex);
      if (parsed == null || parsed.sourcePattern.isEmpty) {
        return working;
      }

      final protectTargets =
          _shouldProtectRegexTargets(parsed.sourcePattern, script);

      return _transformRegexEligibleSegments(
        working,
        protectTargets: protectTargets,
        transform: (segment) => segment.replaceAllMapped(
          parsed.regExp,
          (match) => _expandRegexReplacement(
            script.replaceString,
            match,
            segment,
          ),
        ),
      );
    } catch (e) {
      print('Regex Error (${script.scriptName}): $e');
      return input;
    }
  }

  _ParsedRegexPattern? _parseRegexPattern(String rawPattern) {
    var pattern = rawPattern;
    var flags = '';

    if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
      final lastSlash = pattern.lastIndexOf('/');
      final potentialFlags = pattern.substring(lastSlash + 1);
      if (RegExp(r'^[gimsuy]*$').hasMatch(potentialFlags)) {
        flags = potentialFlags;
        pattern = pattern.substring(1, lastSlash);
      }
    }

    if (pattern.contains('(?s)')) {
      pattern = pattern.replaceAll('(?s)', '');
      if (!flags.contains('s')) {
        flags += 's';
      }
    }
    if (pattern.contains('(?i)')) {
      pattern = pattern.replaceAll('(?i)', '');
      if (!flags.contains('i')) {
        flags += 'i';
      }
    }
    if (pattern.contains('(?m)')) {
      pattern = pattern.replaceAll('(?m)', '');
      if (!flags.contains('m')) {
        flags += 'm';
      }
    }

    if (pattern.isEmpty) {
      return null;
    }

    return _ParsedRegexPattern(
      sourcePattern: pattern,
      regExp: RegExp(
        pattern,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        dotAll: flags.contains('s'),
      ),
    );
  }

  bool _shouldProtectRegexTargets(String pattern, RegexScript script) {
    if (script.scriptName == 'Auto Replace {{user}}') {
      return false;
    }
    return !pattern.contains('<') &&
        !pattern.contains('>') &&
        !pattern.contains('```');
  }

  String _transformRegexEligibleSegments(
    String input, {
    required bool protectTargets,
    required String Function(String segment) transform,
  }) {
    if (!protectTargets) {
      return transform(input);
    }

    final segments = _splitProtectedRegexSegments(input);
    final buffer = StringBuffer();
    for (final segment in segments) {
      buffer.write(
        segment.isProtected ? segment.text : transform(segment.text),
      );
    }
    return buffer.toString();
  }

  List<_ProtectedRegexSegment> _splitProtectedRegexSegments(String input) {
    if (input.isEmpty) {
      return const [];
    }

    final segments = <_ProtectedRegexSegment>[];
    var cursor = 0;
    for (final match in _regexProtectedBlockPattern.allMatches(input)) {
      if (match.start > cursor) {
        segments.add(
          _ProtectedRegexSegment(
            input.substring(cursor, match.start),
            false,
          ),
        );
      }

      final protectedText = match.group(0);
      if (protectedText != null && protectedText.isNotEmpty) {
        segments.add(_ProtectedRegexSegment(protectedText, true));
      }
      cursor = match.end;
    }

    if (cursor < input.length) {
      segments.add(_ProtectedRegexSegment(input.substring(cursor), false));
    }

    return segments;
  }

  String _expandRegexReplacement(
    String template,
    Match match,
    String source,
  ) {
    if (template.isEmpty) {
      return '';
    }

    final output = StringBuffer();
    var index = 0;

    while (index < template.length) {
      final char = template[index];
      if (char != r'$' || index + 1 >= template.length) {
        output.write(char);
        index++;
        continue;
      }

      final next = template[index + 1];
      if (next == r'$') {
        output.write(r'$');
        index += 2;
        continue;
      }
      if (next == '&') {
        output.write(match.group(0) ?? '');
        index += 2;
        continue;
      }
      if (next == '`') {
        output.write(source.substring(0, match.start));
        index += 2;
        continue;
      }
      if (next == "'") {
        output.write(source.substring(match.end));
        index += 2;
        continue;
      }
      if (next == '<') {
        final closeIndex = template.indexOf('>', index + 2);
        if (closeIndex != -1) {
          final groupName = template.substring(index + 2, closeIndex);
          if (match is RegExpMatch) {
            try {
              output.write(match.namedGroup(groupName) ?? '');
              index = closeIndex + 1;
              continue;
            } catch (_) {}
          }
        }
      }
      if (_isAsciiDigit(next)) {
        final firstDigit = int.parse(next);
        var consumed = 2;
        var groupIndex = firstDigit;

        if (index + 2 < template.length && _isAsciiDigit(template[index + 2])) {
          final secondDigit = int.parse(template[index + 2]);
          final twoDigitIndex = (firstDigit * 10) + secondDigit;
          if (twoDigitIndex <= match.groupCount) {
            groupIndex = twoDigitIndex;
            consumed = 3;
          }
        }

        if (groupIndex > 0 && groupIndex <= match.groupCount) {
          output.write(match.group(groupIndex) ?? '');
          index += consumed;
          continue;
        }
      }

      output.write(char);
      index++;
    }

    return output.toString();
  }

  bool _isAsciiDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  List<ChatMessage> _applyPromptOnlyRegexToMessages(
    List<ChatMessage> messages, {
    List<String>? overrideRegexIds,
    Preset? overridePreset,
  }) {
    if (messages.isEmpty) {
      return messages;
    }

    final transformed = List<ChatMessage>.from(messages);
    var userDepth = 0;
    var assistantDepth = 0;

    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      int? placement;
      int? depth;

      if (msg.role == 'user') {
        placement = 1;
        depth = ++userDepth;
      } else if (msg.role == 'assistant') {
        placement = 2;
        depth = ++assistantDepth;
      } else {
        continue;
      }

      final transformedContent = _applyRegex(
        msg.content,
        placement,
        overrideRegexIds: overrideRegexIds,
        overridePreset: overridePreset,
        includePromptOnly: true,
        promptOnlyOnly: true,
        messageDepth: depth,
      );

      if (transformedContent != msg.content) {
        transformed[i] = msg.copyWith(content: transformedContent);
      }
    }

    return transformed;
  }

  // --- Token Estimation ---
  //
  // 旧的 `text.length / 2.5` 对纯英文明显高估、对纯中文又严重低估，
  // 导致上下文预算算不准。这里按字符类型加权：
  //   CJK / 假名 / 谚文  ≈ 0.6 token/字
  //   拉丁字母与其它      ≈ 1 token / 4 字符
  //
  // 系数取 0.6 而不是 0.9：主流中文模型（Qwen / DeepSeek / GLM 等）的
  // BPE 词表对常用汉字多为 1 字 ≈ 0.5~0.7 token，按 0.9 估算会把预算
  // 高估约 50%，直接导致历史被过早截断、世界书条目挤不进预算。
  int _estimateTokens(String text) {
    if (text.isEmpty) {
      return 0;
    }

    var cjkCount = 0;
    var otherCount = 0;
    for (final rune in text.runes) {
      if (_isCjkRune(rune)) {
        cjkCount++;
      } else {
        otherCount++;
      }
    }

    final estimate = cjkCount * 0.6 + otherCount / 4.0;
    return estimate <= 0 ? 0 : estimate.ceil();
  }

  bool _isCjkRune(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK 统一表意
        (rune >= 0x3400 && rune <= 0x4DBF) || // CJK 扩展 A
        (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容表意
        (rune >= 0x3000 && rune <= 0x303F) || // CJK 标点
        (rune >= 0xFF00 && rune <= 0xFFEF) || // 全角字符
        (rune >= 0x3040 && rune <= 0x30FF) || // 平假名 / 片假名
        (rune >= 0xAC00 && rune <= 0xD7AF); // 谚文
  }

  List<_TriggeredWorldInfoEntry> _scanWorldInfo(
    _WorldInfoScanContext scanContext, {
    List<String>? overrideWorldInfoIds,
    Map<String, String>? worldInfoSourceKindById,
  }) {
    final settings = _ref.read(worldInfoSettingsProvider);
    final List<String> requestedWiIds =
        overrideWorldInfoIds ?? _ref.read(activeWorldInfoIdsProvider);
    final allWi = _ref.read(worldInfoProvider);
    final allWiById = {
      for (final worldInfo in allWi) worldInfo.id: worldInfo,
    };
    final seenIds = <String>{};
    final requestedOrderByWorldInfoId = <String, int>{
      for (var i = 0; i < requestedWiIds.length; i++)
        requestedWiIds[i].trim(): i,
    };
    final activeWi = <WorldInfo>[
      for (final id in requestedWiIds)
        if (id.trim().isNotEmpty && seenIds.add(id.trim()))
          ...() {
            final normalizedId = id.trim();
            final worldInfo = allWiById[normalizedId];
            if (worldInfo == null) {
              return const <WorldInfo>[];
            }

            // 「自身已禁用」只对全局池（global）来源生效。
            //
            // 角色卡绑定的世界书（character）与会话级世界书（session）是用
            // 户显式挂到这张卡 / 这个会话上的，语义上等同于在酒馆里直接选中
            // 该世界书，不应再被自身开关二次拦截。历史上这里曾收紧为「一律
            // 遵守 disabled」，导致带 `enabled:false` 的卡内嵌书静默失效、
            // 用户又找不到任何开关可以恢复 —— 现在恢复旧语义。
            final sourceKind =
                worldInfoSourceKindById?[normalizedId]?.trim() ?? 'global';
            final isCharacterScoped =
                sourceKind == 'character' || sourceKind == 'session';
            if (worldInfo.disabled && !isCharacterScoped) {
              return const <WorldInfo>[];
            }

            return <WorldInfo>[worldInfo];
          }(),
    ];
    bool checkKey(
      String key,
      bool caseSensitive,
      bool useRegex,
      bool matchWholeWords,
      String source,
      String sourceLower,
    ) {
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty) {
        return false;
      }

      // 全局激活设置里的「区分大小写 / 匹配整个单词」是总开关，
      // 与条目自身的同名开关取「或」：任一为真即按该规则匹配。
      final effectiveCaseSensitive = caseSensitive || settings.caseSensitive;
      final effectiveWholeWords = matchWholeWords || settings.matchWholeWords;

      final parsedRegex = _tryParseWorldInfoKeyRegex(
        trimmedKey,
        caseSensitive: effectiveCaseSensitive,
      );
      if (useRegex || parsedRegex != null) {
        try {
          return (parsedRegex ??
                  RegExp(trimmedKey, caseSensitive: effectiveCaseSensitive))
              .hasMatch(source);
        } catch (_) {
          return false;
        }
      }

      if (effectiveWholeWords) {
        final normalizedKey =
            effectiveCaseSensitive ? trimmedKey : trimmedKey.toLowerCase();
        final haystack = effectiveCaseSensitive ? source : sourceLower;
        final startsWithWordChar = RegExp(r'^\w').hasMatch(normalizedKey);
        final endsWithWordChar = RegExp(r'\w$').hasMatch(normalizedKey);
        var pattern = RegExp.escape(normalizedKey);
        if (startsWithWordChar) {
          pattern = '\\b$pattern';
        }
        if (endsWithWordChar) {
          pattern = '$pattern\\b';
        }
        return RegExp(pattern).hasMatch(haystack);
      }

      if (effectiveCaseSensitive) {
        return source.contains(trimmedKey);
      }
      return sourceLower.contains(trimmedKey.toLowerCase());
    }

    /// 返回命中得分：0 表示未命中；>0 为命中的关键词数量，
    /// 供「使用群组评分」时在同一群组内比较优先级。
    int scoreEntry(WorldInfoEntry entry, String source) {
      if (entry.constant) {
        // 常驻条目不依赖关键词，给一个基础分保证能进入候选。
        return 1;
      }

      final sourceLower = source.toLowerCase();
      var score = 0;
      for (final key in entry.keys) {
        if (checkKey(key, entry.caseSensitive, entry.useRegex,
            entry.matchWholeWords, source, sourceLower)) {
          score++;
        }
      }
      if (score == 0) {
        return 0;
      }

      final secondaryKeys = entry.secondaryKeys
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty)
          .toList(growable: false);
      if (!entry.selective || secondaryKeys.isEmpty) {
        return score;
      }

      var secondaryAny = false;
      var secondaryAll = true;
      var secondaryScore = 0;
      for (final key in secondaryKeys) {
        final matched = checkKey(key, entry.caseSensitive, entry.useRegex,
            entry.matchWholeWords, source, sourceLower);
        if (matched) {
          secondaryAny = true;
          secondaryScore++;
        } else {
          secondaryAll = false;
        }
      }

      final passed = switch (entry.selectiveLogic) {
        0 => secondaryAny,
        1 => secondaryAll,
        2 => !secondaryAny,
        3 => !secondaryAll,
        _ => secondaryAny,
      };
      if (!passed) {
        return 0;
      }
      return score + secondaryScore;
    }

    final triggered = <String, _TriggeredWorldInfoEntry>{};
    final activationState =
        _buildWorldInfoActivationState(scanContext.historyMessages);
    final probabilityRejected = <String>{};
    final activeGroups = <String>{};
    final recursionBuffer = <String>[];
    final budget = _getWorldInfoTokenBudget(
      _getConfiguredContextSize(),
      settings,
    );
    var usedBudget = 0;
    var depthSkew = 0;
    var loopCount = 0;
    var recursionSteps = 0;
    var tokenBudgetOverflowed = false;
    var scanState = _WorldInfoScanState.initial;
    final delayedRecursionLevels = <int>{
      for (final wi in activeWi)
        for (final entry in wi.entries)
          if (entry.delayUntilRecursion > 0) entry.delayUntilRecursion,
    }.toList()
      ..sort();
    var currentRecursionDelayLevel = delayedRecursionLevels.isNotEmpty
        ? delayedRecursionLevels.removeAt(0)
        : 0;

    while (scanState != _WorldInfoScanState.none && loopCount < 64) {
      loopCount++;
      final candidates = <_WorldInfoCandidate>[];

      for (final wi in activeWi) {
        for (final entry in wi.entries) {
          final triggerKey = '${wi.id}:${entry.uid}';
          if (entry.disable ||
              triggered.containsKey(triggerKey) ||
              probabilityRejected.contains(triggerKey)) {
            continue;
          }

          final entryGroups = _extractWorldInfoGroupNames(entry);
          if (entryGroups.isNotEmpty &&
              entryGroups.any((group) => activeGroups.contains(group))) {
            continue;
          }

          final effectState =
              _resolveWorldInfoEffectState(entry, activationState);
          if (effectState.isSticky) {
            candidates.add(
              _WorldInfoCandidate(
                triggerKey: triggerKey,
                entry: entry,
                worldInfoId: wi.id,
                worldInfoName: wi.name,
                sourceKind:
                    worldInfoSourceKindById?[wi.id]?.trim().isNotEmpty == true
                        ? worldInfoSourceKindById![wi.id]!
                        : 'global',
                sourceOrder: requestedOrderByWorldInfoId[wi.id] ?? (1 << 20),
              ),
            );
            continue;
          }
          if (effectState.inCooldown || effectState.inDelayWindow) {
            continue;
          }
          if (scanState != _WorldInfoScanState.recursion &&
              entry.delayUntilRecursion > 0 &&
              !effectState.isSticky) {
            continue;
          }
          if (scanState == _WorldInfoScanState.recursion &&
              settings.recursive &&
              entry.excludeRecursion &&
              !effectState.isSticky) {
            continue;
          }
          if (scanState == _WorldInfoScanState.recursion &&
              entry.delayUntilRecursion > 0 &&
              entry.delayUntilRecursion > currentRecursionDelayLevel &&
              !effectState.isSticky) {
            continue;
          }

          final source = _buildWorldInfoEntryScanSource(
            scanContext,
            entry,
            recursionBuffer: recursionBuffer,
            depthSkew: depthSkew,
            scanState: scanState,
            settings: settings,
          );
          final score = scoreEntry(entry, source);
          if (score == 0) {
            continue;
          }

          candidates.add(
            _WorldInfoCandidate(
              triggerKey: triggerKey,
              entry: entry,
              worldInfoId: wi.id,
              worldInfoName: wi.name,
              sourceKind:
                  worldInfoSourceKindById?[wi.id]?.trim().isNotEmpty == true
                      ? worldInfoSourceKindById![wi.id]!
                      : 'global',
              sourceOrder: requestedOrderByWorldInfoId[wi.id] ?? (1 << 20),
              score: score,
            ),
          );
        }
      }

      final filteredCandidates = _applyWorldInfoGroupSelection(
        candidates,
        activationState,
        useGroupScoring: settings.useGroupScoring,
      );
      filteredCandidates.sort((a, b) {
        final aEffectState = _resolveWorldInfoEffectState(
          a.entry,
          activationState,
        );
        final bEffectState = _resolveWorldInfoEffectState(
          b.entry,
          activationState,
        );

        return compareWorldInfoActivationOrder(
          WorldInfoOrderingEntry(
            entry: a.entry,
            sourceKind: a.sourceKind,
            sourceOrder: a.sourceOrder,
            isSticky: aEffectState.isSticky,
          ),
          WorldInfoOrderingEntry(
            entry: b.entry,
            sourceKind: b.sourceKind,
            sourceOrder: b.sourceOrder,
            isSticky: bEffectState.isSticky,
          ),
          settings.characterStrategy,
        );
      });

      final recursionAdds = <String>[];
      final successfulNewEntries = <_WorldInfoCandidate>[];

      for (final candidate in filteredCandidates) {
        final entry = candidate.entry;
        final content =
            _replaceMacros(entry.content.trim(), scanContext.character);
        if (content.isEmpty) {
          continue;
        }

        if (!_passesWorldInfoProbability(entry)) {
          probabilityRejected.add(candidate.triggerKey);
          continue;
        }

        final contentTokens = _estimateTokens(content);
        if (!entry.ignoreBudget && usedBudget + contentTokens > budget) {
          tokenBudgetOverflowed = true;
          continue;
        }

        usedBudget += entry.ignoreBudget ? 0 : contentTokens;
        triggered[candidate.triggerKey] = _TriggeredWorldInfoEntry(
          entry: entry,
          worldInfoId: candidate.worldInfoId,
          worldInfoName: candidate.worldInfoName,
          sourceKind: candidate.sourceKind,
          sourceOrder: candidate.sourceOrder,
        );
        for (final group in _extractWorldInfoGroupNames(entry)) {
          activeGroups.add(group);
        }
        if (!entry.preventRecursion) {
          recursionAdds.add(content);
        }
        successfulNewEntries.add(candidate);
      }

      final successfulNewEntriesForRecursion = successfulNewEntries
          .where((candidate) => !candidate.entry.preventRecursion)
          .toList(growable: false);

      var nextScanState = _WorldInfoScanState.none;
      if (settings.recursive &&
          !tokenBudgetOverflowed &&
          successfulNewEntriesForRecursion.isNotEmpty) {
        nextScanState = _WorldInfoScanState.recursion;
      }

      if (settings.recursive &&
          !tokenBudgetOverflowed &&
          scanState == _WorldInfoScanState.minActivations &&
          recursionBuffer.isNotEmpty) {
        nextScanState = _WorldInfoScanState.recursion;
      }

      final minActivationsNotSatisfied = settings.minActivations > 0 &&
          triggered.length < settings.minActivations;
      if (nextScanState == _WorldInfoScanState.none &&
          !tokenBudgetOverflowed &&
          minActivationsNotSatisfied) {
        final currentDepth = settings.scanDepth + depthSkew;
        final overMaxDepth = (settings.minActivationsDepthMax > 0 &&
                currentDepth > settings.minActivationsDepthMax) ||
            currentDepth > scanContext.historyMessages.length;
        if (!overMaxDepth) {
          depthSkew++;
          nextScanState = _WorldInfoScanState.minActivations;
        }
      }

      if (nextScanState == _WorldInfoScanState.none &&
          delayedRecursionLevels.isNotEmpty) {
        currentRecursionDelayLevel = delayedRecursionLevels.removeAt(0);
        nextScanState = _WorldInfoScanState.recursion;
      }

      if (nextScanState != _WorldInfoScanState.none &&
          recursionAdds.isNotEmpty) {
        recursionBuffer.addAll(recursionAdds);
      }

      // 最大递归深度：0 表示不限制（仍受循环自身 64 次的上限约束）。
      if (nextScanState == _WorldInfoScanState.recursion) {
        if (settings.maxRecursionDepth > 0 &&
            recursionSteps >= settings.maxRecursionDepth) {
          nextScanState = _WorldInfoScanState.none;
        } else {
          recursionSteps++;
        }
      }

      if (filteredCandidates.isEmpty &&
          nextScanState == _WorldInfoScanState.none) {
        break;
      }

      scanState = nextScanState;
    }

    final entries = triggered.values.toList();
    entries.sort((a, b) => compareWorldInfoPromptOrder(
          WorldInfoOrderingEntry(
            entry: a.entry,
            sourceKind: a.sourceKind,
            sourceOrder: a.sourceOrder,
          ),
          WorldInfoOrderingEntry(
            entry: b.entry,
            sourceKind: b.sourceKind,
            sourceOrder: b.sourceOrder,
          ),
          settings.characterStrategy,
        ));

    _lastWorldInfoOverflowed = tokenBudgetOverflowed;

    if (tokenBudgetOverflowed && settings.alertOnOverflow) {
      _ref.read(worldInfoOverflowNoticeProvider.notifier).state =
          '世界书 Token 预算已溢出，部分条目未能注入。'
          '可在「全局世界信息/知识书激活设置」里调高「上下文百分比」。';
    }

    return entries;
  }

  List<String> _collectOrderedActiveWorldInfoIds({
    Session? session,
    Character? character,
  }) {
    final settings = _ref.read(worldInfoSettingsProvider);
    final globalIds = _ref.read(activeWorldInfoIdsProvider);
    final characterIds = _collectCharacterScopedWorldInfoIds(
      session: session,
      character: character,
    );
    final sessionIds = session?.worldInfoIds ?? const <String>[];
    final sessionOnlyIds = sessionIds.where((id) => !characterIds.contains(id));
    final mergedCharacterAndGlobal = switch (settings.characterStrategy) {
      WorldInfoCharacterStrategy.characterFirst => [
          ...characterIds,
          ...globalIds,
        ],
      WorldInfoCharacterStrategy.globalFirst => [
          ...globalIds,
          ...characterIds,
        ],
      WorldInfoCharacterStrategy.evenly =>
        _interleaveWorldInfoIds(characterIds, globalIds),
    };

    final ordered = <String>[];
    final seen = <String>{};

    void appendAll(Iterable<String> ids) {
      for (final id in ids) {
        final normalized = id.trim();
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        ordered.add(normalized);
      }
    }

    appendAll(sessionOnlyIds);
    appendAll(mergedCharacterAndGlobal);

    return ordered;
  }

  Map<String, String> _buildWorldInfoSourceKindById({
    Session? session,
    Character? character,
  }) {
    final globalIds = _ref.read(activeWorldInfoIdsProvider);
    final characterIds = _collectCharacterScopedWorldInfoIds(
      session: session,
      character: character,
    );
    final sessionIds = session?.worldInfoIds ?? const <String>[];
    final sourceById = <String, String>{};

    for (final id in globalIds) {
      final normalized = id.trim();
      if (normalized.isNotEmpty) {
        sourceById[normalized] = 'global';
      }
    }
    for (final id in characterIds) {
      final normalized = id.trim();
      if (normalized.isNotEmpty) {
        sourceById[normalized] = 'character';
      }
    }
    for (final id in sessionIds) {
      final normalized = id.trim();
      if (normalized.isNotEmpty && !characterIds.contains(normalized)) {
        sourceById[normalized] = 'session';
      }
    }

    return sourceById;
  }

  List<String> _collectCharacterScopedWorldInfoIds({
    Session? session,
    Character? character,
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void appendAll(Iterable<String> ids) {
      for (final id in ids) {
        final normalized = id.trim();
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        ordered.add(normalized);
      }
    }

    if (character?.characterBookId?.trim().isNotEmpty == true) {
      appendAll([character!.characterBookId!]);
    }
    appendAll(character?.worldInfoIds ?? const <String>[]);

    final isGroupChat =
        (session?.isGroup ?? false) || (character?.isGroup ?? false);
    if (!isGroupChat) {
      return ordered;
    }

    final memberIds = session?.groupCharacterIds.isNotEmpty == true
        ? session!.groupCharacterIds
        : (character?.groupMemberIds ?? const <String>[]);
    if (memberIds.isEmpty) {
      return ordered;
    }

    final charactersById = {
      for (final item in _ref.read(characterListProvider)) item.id: item,
    };
    for (final memberId in memberIds) {
      final member = charactersById[memberId];
      if (member == null) {
        continue;
      }
      if (member.characterBookId?.trim().isNotEmpty == true) {
        appendAll([member.characterBookId!]);
      }
      appendAll(member.worldInfoIds);
    }

    return ordered;
  }

  _WorldInfoEffectState _resolveWorldInfoEffectState(
    WorldInfoEntry entry,
    _WorldInfoActivationState activationState,
  ) {
    final activationKey = _buildWorldInfoActivationKey(entry);
    final turnsSinceActivation = activationState.turnsSinceLastActivationFor(
      activationKey,
      fallbackUid: entry.uid,
    );
    if (turnsSinceActivation == null) {
      return const _WorldInfoEffectState();
    }

    final stickyActive =
        entry.sticky > 0 && turnsSinceActivation <= entry.sticky;
    final cooldownActive =
        entry.cooldown > 0 && turnsSinceActivation <= entry.cooldown;
    final delayActive = entry.delay > 0 && turnsSinceActivation <= entry.delay;

    return _WorldInfoEffectState(
      isSticky: stickyActive,
      inCooldown: cooldownActive && !stickyActive,
      inDelayWindow: delayActive && !stickyActive,
    );
  }

  bool _passesWorldInfoProbability(WorldInfoEntry entry) {
    if (!entry.useProbability || entry.probability >= 100) {
      return true;
    }
    if (entry.probability <= 0) {
      return false;
    }
    return (math.Random().nextDouble() * 100) <= entry.probability;
  }

  List<_WorldInfoCandidate> _applyWorldInfoGroupSelection(
    List<_WorldInfoCandidate> candidates,
    _WorldInfoActivationState activationState, {
    bool useGroupScoring = false,
  }) {
    final result = <_WorldInfoCandidate>[];
    final grouped = <String, List<_WorldInfoCandidate>>{};

    for (final candidate in candidates) {
      final groups = _extractWorldInfoGroupNames(candidate.entry);
      if (groups.isEmpty) {
        result.add(candidate);
        continue;
      }
      for (final group in groups) {
        grouped
            .putIfAbsent(group, () => <_WorldInfoCandidate>[])
            .add(candidate);
      }
    }

    final selectedByTriggerKey = <String, _WorldInfoCandidate>{};
    final rejectedTriggerKeys = <String>{};
    final random = math.Random();
    for (final group in grouped.values) {
      var eligible = group
          .where((item) => !rejectedTriggerKeys.contains(item.triggerKey))
          .toList();
      if (eligible.isEmpty) {
        continue;
      }
      if (eligible.length == 1) {
        selectedByTriggerKey[eligible.first.triggerKey] = eligible.first;
        continue;
      }

      final stickyEligible = eligible
          .where(
            (item) => _resolveWorldInfoEffectState(item.entry, activationState)
                .isSticky,
          )
          .toList();
      if (stickyEligible.isNotEmpty) {
        eligible = stickyEligible;
      }

      eligible.sort((a, b) {
        final orderCmp = b.entry.order.compareTo(a.entry.order);
        if (orderCmp != 0) {
          return orderCmp;
        }
        final sourceCmp = a.sourceOrder.compareTo(b.sourceOrder);
        if (sourceCmp != 0) {
          return sourceCmp;
        }
        return a.entry.uid.compareTo(b.entry.uid);
      });

      final overrides =
          eligible.where((item) => item.entry.groupOverride).toList();
      _WorldInfoCandidate winner;
      if (overrides.isNotEmpty) {
        winner = overrides.first;
      } else if (useGroupScoring) {
        // 群组评分：命中关键词更多的条目优先，不再做权重随机。
        final scored = [...eligible]..sort((a, b) {
            final scoreCmp = b.score.compareTo(a.score);
            if (scoreCmp != 0) {
              return scoreCmp;
            }
            final weightCmp = b.entry.groupWeight
                .clamp(1, 10000)
                .compareTo(a.entry.groupWeight.clamp(1, 10000));
            if (weightCmp != 0) {
              return weightCmp;
            }
            return a.entry.uid.compareTo(b.entry.uid);
          });
        winner = scored.first;
      } else {
        final totalWeight = eligible.fold<int>(
          0,
          (sum, item) => sum + item.entry.groupWeight.clamp(1, 10000),
        );
        var roll = random.nextInt(totalWeight);
        winner = eligible.first;
        for (final item in eligible) {
          roll -= item.entry.groupWeight.clamp(1, 10000);
          if (roll < 0) {
            winner = item;
            break;
          }
        }
      }

      selectedByTriggerKey[winner.triggerKey] = winner;
      for (final item in eligible) {
        if (item.triggerKey == winner.triggerKey) {
          continue;
        }
        rejectedTriggerKeys.add(item.triggerKey);
        selectedByTriggerKey.remove(item.triggerKey);
      }
    }

    result.addAll(selectedByTriggerKey.values);
    return result;
  }

  List<String> _extractWorldInfoGroupNames(WorldInfoEntry entry) {
    return entry.group
        .split(',')
        .map((group) => group.trim())
        .where((group) => group.isNotEmpty)
        .toList(growable: false);
  }

  int _getWorldInfoTokenBudget(
    int contextSize,
    WorldInfoScanSettings settings,
  ) {
    var budget = ((settings.budgetPercentage * contextSize) / 100).round();
    if (settings.budgetCap > 0 && budget > settings.budgetCap) {
      budget = settings.budgetCap;
    }
    return budget <= 0 ? 1 : budget;
  }

  _ConstructedPromptResult _constructPrompt(
    List<ChatMessage> history,
    List<WorldInfoEntry> worldInfo, {
    Preset? overridePreset,
    Character? activeCharacter,
    _GenerationType generationType = _GenerationType.normal,
    String quietPrompt = '',
  }) {
    final preset = overridePreset ?? _ref.read(activePresetProvider);
    final character = activeCharacter ?? _getCharacter();
    final groupedWorldInfo = _groupWorldInfoByPosition(worldInfo);
    final conversationalHistory =
        history.where((msg) => msg.role != 'system').toList(growable: false);
    final isGroupChat = _getSession()?.isGroup ?? false;
    final isNewChat =
        !conversationalHistory.any((message) => message.role == 'user');

    final depthInjections = <RpHubContextDepthInjection>[];

    for (final entry in groupedWorldInfo.atDepth) {
      final content = _buildSingleWorldInfoEntry(entry, character).trim();
      if (content.isEmpty) {
        continue;
      }
      depthInjections.add(
        RpHubContextDepthInjection(
          title: entry.comment.trim().isNotEmpty
              ? entry.comment.trim()
              : 'World Info ${entry.uid}',
          role: _normalizeWorldInfoRole(entry.role),
          content: content,
          depth: entry.depth,
          order: entry.order,
          sourceKey: 'world_info_depth',
          sourceLabel: 'World Info @ Depth',
        ),
      );
    }

    final authorsNoteSegments = <String>[
      _buildWorldInfoBlock(groupedWorldInfo.beforeAuthorsNote, character),
      if (_shouldInjectAuthorsNote(character, conversationalHistory))
        _buildAuthorsNoteBlock(character),
      _buildWorldInfoBlock(groupedWorldInfo.afterAuthorsNote, character),
    ].where((segment) => segment.trim().isNotEmpty).toList(growable: false);
    final authorsNotePrompt = _findPresetPrompt(preset, 'authorsNote');
    final authorsNoteLiteral = authorsNotePrompt == null
        ? ''
        : _replaceMacros(authorsNotePrompt.content.trim(), character);
    final authorsNoteContent = [
      if (authorsNoteLiteral.isNotEmpty) authorsNoteLiteral,
      ...authorsNoteSegments,
    ].join('\n\n');

    if (_isPresetPromptEnabled(preset, 'authorsNote') &&
        authorsNoteContent.trim().isNotEmpty) {
      depthInjections.add(
        RpHubContextDepthInjection(
          title: 'Author\'s Note',
          role: _getCharacterDepthPromptRole(character),
          content: authorsNoteContent,
          depth: (character?.authorsNoteDepth ?? 4) <= 0
              ? 4
              : (character?.authorsNoteDepth ?? 4),
          order: 1 << 20,
          sourceKey: 'authors_note',
          sourceLabel: 'Author\'s Note Injection',
        ),
      );
    }

    ChatMessage? continuedMessage;
    var historyForBudget = List<ChatMessage>.from(conversationalHistory);
    if (generationType == _GenerationType.continueMode &&
        historyForBudget.isNotEmpty &&
        historyForBudget.last.role == 'assistant') {
      continuedMessage = historyForBudget.removeLast();
    }

    final newChatPrompt = isNewChat
        ? _replaceMacros(
            (isGroupChat ? preset?.newGroupChatPrompt : preset?.newChatPrompt)
                    ?.trim() ??
                '',
            character,
          )
        : '';

    final continueNudge = continuedMessage == null
        ? ''
        : _replaceMacros(
            preset?.continueNudge.trim() ?? '',
            character,
            extraMacros: {
              'lastChatMessage': continuedMessage.content.trim(),
            },
          );

    final beforeCharacterWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.beforeCharacter, character);
    final afterCharacterWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.afterCharacter, character);
    final beforeExamplesWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.beforeExamples, character);
    final afterExamplesWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.afterExamples, character);
    final assistantTopWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.assistantTop, character);
    final userTopWorldInfo =
        _buildWorldInfoBlock(groupedWorldInfo.userTop, character);
    final topSystemPrompt =
        _replaceMacros(_buildTopSystemPrompt(preset), character);
    final characterSystemPrompt =
        _replaceMacros(_getCharacterSystemPrompt(character), character);
    final exampleDialogueBlock = _buildRpHubExampleDialogueBlock(character);
    final characterDescription =
        _replaceMacros(_getCharacterDescription(character), character);
    final characterPersonality =
        _replaceMacros(_getCharacterPersonality(character), character);
    final characterScenario =
        _replaceMacros(_getCharacterScenario(character), character);
    final personaDescription = _getUserDescription().trim();
    final memoryBlock = _buildMemoryBlock().trim();

    final skeletonResult = _assemblePromptMessages(
      preset: preset,
      history: const <ChatMessage>[],
      topSystemPrompt: topSystemPrompt,
      characterSystemPrompt: characterSystemPrompt,
      depthInjections: depthInjections,
      beforeCharacterWorldInfo: beforeCharacterWorldInfo,
      afterCharacterWorldInfo: afterCharacterWorldInfo,
      beforeExamplesWorldInfo: beforeExamplesWorldInfo,
      afterExamplesWorldInfo: afterExamplesWorldInfo,
      assistantTopWorldInfo: assistantTopWorldInfo,
      userTopWorldInfo: userTopWorldInfo,
      characterDescription: characterDescription,
      characterPersonality: characterPersonality,
      characterScenario: characterScenario,
      personaDescription: personaDescription,
      exampleDialogueBlock: exampleDialogueBlock,
      memoryBlock: memoryBlock,
      newChatPrompt: newChatPrompt,
      groupNudgePrompt:
          _replaceMacros(preset?.groupNudgePrompt.trim() ?? '', character),
      continuedMessage: continuedMessage,
      continueNudge: continueNudge,
      impersonationPrompt:
          _replaceMacros(preset?.impersonationPrompt.trim() ?? '', character),
      quietPrompt: _replaceMacros(quietPrompt.trim(), character),
      isGroupChat: isGroupChat,
      isNewChat: isNewChat,
      generationType: generationType,
      character: character,
    );
    final nonHistoryTokens = skeletonResult.messages.fold<int>(
      0,
      (sum, message) => sum + _estimateTokens(message.content),
    );
    final maxContextTokens = _getConfiguredContextSize();
    final responseReserve = _getResponseReserveTokens(preset, maxContextTokens);
    final historyBudget =
        (maxContextTokens - responseReserve - nonHistoryTokens)
            .clamp(0, 1 << 30)
            .toInt();
    final visibleHistory =
        _collectHistoryWithinBudget(historyForBudget, historyBudget);

    final assembled = _assemblePromptMessages(
      preset: preset,
      history: visibleHistory,
      topSystemPrompt: topSystemPrompt,
      characterSystemPrompt: characterSystemPrompt,
      depthInjections: depthInjections,
      beforeCharacterWorldInfo: beforeCharacterWorldInfo,
      afterCharacterWorldInfo: afterCharacterWorldInfo,
      beforeExamplesWorldInfo: beforeExamplesWorldInfo,
      afterExamplesWorldInfo: afterExamplesWorldInfo,
      assistantTopWorldInfo: assistantTopWorldInfo,
      userTopWorldInfo: userTopWorldInfo,
      characterDescription: characterDescription,
      characterPersonality: characterPersonality,
      characterScenario: characterScenario,
      personaDescription: personaDescription,
      exampleDialogueBlock: exampleDialogueBlock,
      memoryBlock: memoryBlock,
      newChatPrompt: newChatPrompt,
      groupNudgePrompt:
          _replaceMacros(preset?.groupNudgePrompt.trim() ?? '', character),
      continuedMessage: continuedMessage,
      continueNudge: continueNudge,
      impersonationPrompt:
          _replaceMacros(preset?.impersonationPrompt.trim() ?? '', character),
      quietPrompt: _replaceMacros(quietPrompt.trim(), character),
      isGroupChat: isGroupChat,
      isNewChat: isNewChat,
      generationType: generationType,
      character: character,
    );

    return _ConstructedPromptResult(
      assemblyMessages: assembled.assemblyMessages,
      maxContextTokens: maxContextTokens,
      responseReserveTokens: responseReserve,
    );
  }

  _ConstructedPromptResult _assemblePromptMessages({
    required Preset? preset,
    required List<ChatMessage> history,
    required String topSystemPrompt,
    required String characterSystemPrompt,
    required List<RpHubContextDepthInjection> depthInjections,
    required String beforeCharacterWorldInfo,
    required String afterCharacterWorldInfo,
    required String beforeExamplesWorldInfo,
    required String afterExamplesWorldInfo,
    required String assistantTopWorldInfo,
    required String userTopWorldInfo,
    required String characterDescription,
    required String characterPersonality,
    required String characterScenario,
    required String personaDescription,
    required String exampleDialogueBlock,
    required String memoryBlock,
    required String newChatPrompt,
    required String groupNudgePrompt,
    required ChatMessage? continuedMessage,
    required String continueNudge,
    required String impersonationPrompt,
    required String quietPrompt,
    required bool isGroupChat,
    required bool isNewChat,
    required _GenerationType generationType,
    required Character? character,
  }) {
    final now = DateTime.now();
    // 没有预设（或预设没有 prompt 列表）时，退化为酒馆默认 Prompt Manager 顺序，
    // 保证角色描述 / 性格 / 场景 / 人设 / 示例对话 / 记忆表 / 历史都能进 prompt。
    final prompts = preset?.prompts.isNotEmpty == true
        ? preset!.prompts
        : _defaultPromptManagerPrompts();

    final plannedEntries = <_PromptPlanEntry>[];
    final attachmentPrompts = <_AssemblyAttachmentPrompt>[];
    final promptDepthInjections = <RpHubContextDepthInjection>[
      ...depthInjections,
    ];

    void addMessageEntry({
      required String role,
      required String content,
      required String sourceKey,
      required String sourceLabel,
      required String title,
    }) {
      final trimmed = content.trim();
      if (trimmed.isEmpty) {
        return;
      }
      plannedEntries.add(
        _PromptPlanEntry.message(
          _PromptAssemblyMessage(
            message: ChatMessage(
              role: role,
              content: trimmed,
              timestamp: now,
            ),
            sourceKey: sourceKey,
            sourceLabel: sourceLabel,
            blocks: [
              _PromptAssemblyBlock(
                title: title,
                content: trimmed,
              ),
            ],
          ),
        ),
      );
    }

    final presetSystemPrompt = topSystemPrompt.trim();
    if (presetSystemPrompt.isNotEmpty) {
      addMessageEntry(
        role: 'system',
        content: presetSystemPrompt,
        sourceKey: 'preset_system_prompt',
        sourceLabel: 'Preset System Prompt',
        title: 'System Prompt',
      );
    }

    // 角色卡自带的 system_prompt 独立注入，不再冒充 personality。
    final cardSystemPrompt = characterSystemPrompt.trim();
    if (cardSystemPrompt.isNotEmpty &&
        cardSystemPrompt != presetSystemPrompt) {
      addMessageEntry(
        role: 'system',
        content: cardSystemPrompt,
        sourceKey: 'character_system_prompt',
        sourceLabel: 'Character System Prompt',
        title: 'Character System Prompt',
      );
    }

    if (isNewChat && newChatPrompt.trim().isNotEmpty) {
      addMessageEntry(
        role: 'system',
        content: newChatPrompt.trim(),
        sourceKey: 'new_chat',
        sourceLabel: 'New Chat Prompt',
        title: 'New Chat Prompt',
      );
    }

    var hasHistoryMarker = false;
    for (final prompt in prompts) {
      if (!prompt.enabled) {
        continue;
      }

      if (prompt.identifier == 'chatHistory') {
        hasHistoryMarker = true;
        plannedEntries.add(const _PromptPlanEntry.historyMarker());
        continue;
      }

      if (prompt.identifier == 'authorsNote') {
        continue;
      }

      final resolved = _resolvePresetPromptContent(
        prompt,
        character: character,
        beforeCharacterWorldInfo: beforeCharacterWorldInfo,
        afterCharacterWorldInfo: afterCharacterWorldInfo,
        beforeExamplesWorldInfo: beforeExamplesWorldInfo,
        afterExamplesWorldInfo: afterExamplesWorldInfo,
        characterDescription: characterDescription,
        characterPersonality: characterPersonality,
        characterScenario: characterScenario,
        personaDescription: personaDescription,
        exampleDialogueBlock: exampleDialogueBlock,
        memoryBlock: memoryBlock,
        groupNudgePrompt: groupNudgePrompt,
        impersonationPrompt: impersonationPrompt,
        quietPrompt: quietPrompt,
        isGroupChat: isGroupChat,
        generationType: generationType,
      );

      final trimmed = resolved.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final normalizedRole = _normalizeRole(prompt.role);
      if (prompt.injectionPosition == Preset.attachExistingInjectionPosition) {
        attachmentPrompts.add(
          _AssemblyAttachmentPrompt(
            role: normalizedRole,
            content: trimmed,
            sourceKey: 'preset_attach',
            sourceLabel: prompt.name,
            title: prompt.name,
            attachRole: _normalizeRole(prompt.attachRole ?? normalizedRole),
            attachIndex: prompt.attachIndex,
            attachSide: prompt.attachSide?.trim().toLowerCase() ?? 'end',
            order: prompt.injectionOrder,
          ),
        );
        continue;
      }

      if (prompt.injectionDepth > 0 ||
          prompt.injectionPosition == Preset.absoluteInjectionPosition) {
        promptDepthInjections.add(
          RpHubContextDepthInjection(
            title: prompt.name,
            role: normalizedRole,
            content: trimmed,
            depth: prompt.injectionDepth <= 0 ? 1 : prompt.injectionDepth,
            order: prompt.injectionOrder,
            sourceKey: 'preset_depth',
            sourceLabel: prompt.name,
          ),
        );
        continue;
      }

      addMessageEntry(
        role: normalizedRole,
        content: trimmed,
        sourceKey: 'preset_prompt',
        sourceLabel: prompt.name,
        title: prompt.name,
      );
    }

    if (!hasHistoryMarker) {
      plannedEntries.add(const _PromptPlanEntry.historyMarker());
    }

    final assembly = <_PromptAssemblyMessage>[];
    for (final entry in plannedEntries) {
      if (entry.isHistoryMarker) {
        for (final message in history) {
          assembly.add(
            _PromptAssemblyMessage(
              message: message,
              sourceKey: 'history',
              sourceLabel: 'Chat History',
              blocks: [
                _PromptAssemblyBlock(
                  title: message.role == 'user'
                      ? 'User History'
                      : 'Assistant History',
                  content: message.content,
                ),
              ],
            ),
          );
        }
        continue;
      }

      if (entry.message != null) {
        assembly.add(entry.message!);
      }
    }

    if (attachmentPrompts.isNotEmpty) {
      final orderedAttachments = [...attachmentPrompts]
        ..sort((a, b) => a.order.compareTo(b.order));
      for (final attachment in orderedAttachments) {
        _applyAssemblyAttachmentPrompt(assembly, attachment, now);
      }
    }

    final userTopContent = userTopWorldInfo.trim();
    if (userTopContent.isNotEmpty) {
      var injected = false;
      for (var i = assembly.length - 1; i >= 0; i--) {
        final item = assembly[i];
        if (item.sourceKey != 'history' || item.message.role != 'user') {
          continue;
        }

        assembly[i] = item.copyWith(
          message: item.message.copyWith(
            content: [
              userTopContent,
              item.message.content.trim(),
            ].where((value) => value.isNotEmpty).join('\n\n'),
          ),
          blocks: [
            _PromptAssemblyBlock(
              title: 'World Info User Top',
              content: userTopContent,
            ),
            ...item.blocks,
          ],
        );
        injected = true;
        break;
      }

      if (!injected) {
        assembly.add(
          _PromptAssemblyMessage(
            message: ChatMessage(
              role: 'system',
              content: userTopContent,
              timestamp: now,
            ),
            sourceKey: 'world_info_user_top',
            sourceLabel: 'World Info User Top',
            blocks: [
              _PromptAssemblyBlock(
                title: 'World Info User Top',
                content: userTopContent,
              ),
            ],
          ),
        );
      }
    }

    final orderedDepthInjections = [...promptDepthInjections]..sort((a, b) {
        final depthCmp = a.depth.compareTo(b.depth);
        if (depthCmp != 0) {
          return depthCmp;
        }
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) {
          return orderCmp;
        }
        return _depthRolePriority(a.role).compareTo(_depthRolePriority(b.role));
      });
    for (final injection in orderedDepthInjections) {
      final content = injection.content.trim();
      if (content.isEmpty) {
        continue;
      }

      _insertPromptAssemblyMessageAtDepth(
        assembly,
        _PromptAssemblyMessage(
          message: ChatMessage(
            role: _normalizeRole(injection.role),
            content: content,
            timestamp: now,
          ),
          sourceKey: injection.sourceKey,
          sourceLabel: injection.sourceLabel,
          blocks: [
            _PromptAssemblyBlock(
              title: injection.title,
              content: content,
            ),
          ],
        ),
        depth: injection.depth,
      );
    }

    if (assistantTopWorldInfo.trim().isNotEmpty) {
      final content =
          '[Instructions for next message]\n${assistantTopWorldInfo.trim()}';
      assembly.add(
        _PromptAssemblyMessage(
          message: ChatMessage(
            role: 'system',
            content: content,
            timestamp: now,
          ),
          sourceKey: 'world_info_assistant_top',
          sourceLabel: 'World Info Assistant Top',
          blocks: [
            _PromptAssemblyBlock(
              title: 'World Info Assistant Top',
              content: content,
            ),
          ],
        ),
      );
    }

    if (generationType == _GenerationType.continueMode &&
        continuedMessage != null) {
      assembly.add(
        _PromptAssemblyMessage(
          message: continuedMessage,
          sourceKey: 'continue_message',
          sourceLabel: 'Continue Message',
          blocks: [
            _PromptAssemblyBlock(
              title: 'Continue Message',
              content: continuedMessage.content,
            ),
          ],
        ),
      );
      if (continueNudge.trim().isNotEmpty) {
        assembly.add(
          _PromptAssemblyMessage(
            message: ChatMessage(
              role: 'system',
              content: continueNudge.trim(),
              timestamp: now,
            ),
            sourceKey: 'continue_nudge',
            sourceLabel: 'Continue Nudge',
            blocks: [
              _PromptAssemblyBlock(
                title: 'Continue Nudge',
                content: continueNudge.trim(),
              ),
            ],
          ),
        );
      }
    }

    // 兜底：世界书里位置为「角色前 / 角色后」的条目，只会经由预设的
    // `worldInfoBefore` / `worldInfoAfter` 槽位进入 prompt。预设若把这两个
    // 槽位关掉（prompt_order 里 enabled=false），这批世界书会整批静默丢失。
    // 这里在缺失时统一补一条 system 消息，保证设定一定能送到模型。
    final enabledIdentifiers = <String>{
      for (final prompt in prompts)
        if (prompt.enabled) prompt.identifier,
    };
    final missingWorldInfoSegments = <String>[
      if (!enabledIdentifiers.contains('worldInfoBefore'))
        beforeCharacterWorldInfo.trim(),
      if (!enabledIdentifiers.contains('worldInfoAfter'))
        afterCharacterWorldInfo.trim(),
    ].where((segment) => segment.isNotEmpty).toList(growable: false);

    if (missingWorldInfoSegments.isNotEmpty) {
      final fallbackContent = missingWorldInfoSegments.join('\n\n');
      assembly.insert(
        0,
        _PromptAssemblyMessage(
          message: ChatMessage(
            role: 'system',
            content: fallbackContent,
            timestamp: now,
          ),
          sourceKey: 'world_info_fallback',
          sourceLabel: 'World Info (fallback)',
          blocks: [
            _PromptAssemblyBlock(
              title: 'World Info (Fallback)',
              content: fallbackContent,
            ),
          ],
        ),
      );
    }

    // 兜底：记忆块只会经由预设的 `vectorsMemory` 槽位进入 prompt。预设若把该
    // 槽位关掉（prompt_order 里 enabled=false）或根本没有这个槽位，整块记忆会
    // **静默丢失** —— 用户侧表现为「记忆完全不起作用」，且没有任何提示。
    // 这里在缺失时按「注入深度」补一条 system 消息：既保证记忆一定能送到模型，
    // 也让记忆设置页的深度滑块真正生效。
    final memoryFallback = memoryBlock.trim();
    if (memoryFallback.isNotEmpty &&
        !enabledIdentifiers.contains('vectorsMemory')) {
      final memorySettings = _ref.read(memoryPluginSettingsProvider);
      _insertPromptAssemblyMessageAtDepth(
        assembly,
        _PromptAssemblyMessage(
          message: ChatMessage(
            role: 'system',
            content: memoryFallback,
            timestamp: now,
          ),
          sourceKey: 'memory_fallback',
          sourceLabel: 'Memory (fallback)',
          blocks: [
            _PromptAssemblyBlock(
              title: 'Memory (Fallback)',
              content: memoryFallback,
            ),
          ],
        ),
        // 0 会让记忆块落到历史之后，语义上「不再靠近最近消息」，因此下限取 1。
        depth: memorySettings.deep < 1 ? 1 : memorySettings.deep,
      );
    }

    return _ConstructedPromptResult(assemblyMessages: assembly);
  }

  /// 无预设时使用的默认 Prompt Manager 顺序（对齐酒馆默认预设）。
  ///
  /// 这些 identifier 由 [_resolvePresetPromptContent] 解析成实际内容，
  /// 内容为空时会被自动跳过，因此这里只声明顺序与角色。
  List<PresetPrompt> _defaultPromptManagerPrompts() {
    return const <PresetPrompt>[
      PresetPrompt(
        identifier: 'worldInfoBefore',
        name: 'World Info (Before)',
        role: 'system',
        content: '',
        enabled: true,
      ),
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
        identifier: 'worldInfoAfter',
        name: 'World Info (After)',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'charDescription',
        name: 'Char Description',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'charPersonality',
        name: 'Char Personality',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'scenario',
        name: 'Scenario',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'personaDescription',
        name: 'Persona Description',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'dialogueExamples',
        name: 'Chat Examples',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'vectorsMemory',
        name: 'Memory',
        role: 'system',
        content: '',
        enabled: true,
      ),
      PresetPrompt(
        identifier: 'chatHistory',
        name: 'Chat History',
        role: 'system',
        content: '',
        enabled: true,
        marker: true,
        legacyPositioning: false,
      ),
    ];
  }

  String _resolvePresetPromptContent(
    PresetPrompt prompt, {
    required Character? character,
    required String beforeCharacterWorldInfo,
    required String afterCharacterWorldInfo,
    required String beforeExamplesWorldInfo,
    required String afterExamplesWorldInfo,
    required String characterDescription,
    required String characterPersonality,
    required String characterScenario,
    required String personaDescription,
    required String exampleDialogueBlock,
    required String memoryBlock,
    required String groupNudgePrompt,
    required String impersonationPrompt,
    required String quietPrompt,
    required bool isGroupChat,
    required _GenerationType generationType,
  }) {
    final literal = _replaceMacros(prompt.content.trim(), character);

    String builtIn = '';
    switch (prompt.identifier) {
      case 'worldInfoBefore':
        builtIn = beforeCharacterWorldInfo.trim();
        break;
      case 'worldInfoAfter':
        builtIn = afterCharacterWorldInfo.trim();
        break;
      case 'charDescription':
        builtIn = characterDescription.trim();
        break;
      case 'charPersonality':
        builtIn = characterPersonality.trim();
        break;
      case 'scenario':
        builtIn = characterScenario.trim();
        break;
      case 'personaDescription':
        builtIn = personaDescription;
        break;
      case 'dialogueExamples':
        builtIn = [
          beforeExamplesWorldInfo.trim(),
          exampleDialogueBlock.trim(),
          afterExamplesWorldInfo.trim(),
        ].where((value) => value.isNotEmpty).join('\n\n');
        break;
      case 'vectorsMemory':
        builtIn = memoryBlock.trim();
        break;
      case 'groupNudge':
        builtIn = isGroupChat && generationType != _GenerationType.impersonate
            ? groupNudgePrompt.trim()
            : '';
        break;
      case 'impersonate':
        builtIn = generationType == _GenerationType.impersonate
            ? impersonationPrompt.trim()
            : '';
        break;
      case 'quietPrompt':
        builtIn =
            generationType == _GenerationType.quiet ? quietPrompt.trim() : '';
        break;
    }

    if (builtIn.isEmpty) {
      return literal;
    }
    if (literal.isEmpty) {
      return builtIn;
    }
    return '$literal\n\n$builtIn';
  }

  void _applyAssemblyAttachmentPrompt(
    List<_PromptAssemblyMessage> assembly,
    _AssemblyAttachmentPrompt attachment,
    DateTime timestamp,
  ) {
    final matchingIndices = <int>[];
    for (var i = 0; i < assembly.length; i++) {
      if (assembly[i].message.role == attachment.attachRole) {
        matchingIndices.add(i);
      }
    }

    if (matchingIndices.isEmpty) {
      assembly.add(
        _PromptAssemblyMessage(
          message: ChatMessage(
            role: attachment.role,
            content: attachment.content,
            timestamp: timestamp,
          ),
          sourceKey: attachment.sourceKey,
          sourceLabel: attachment.sourceLabel,
          blocks: [
            _PromptAssemblyBlock(
              title: attachment.title,
              content: attachment.content,
            ),
          ],
        ),
      );
      return;
    }

    final targetIndex = attachment.attachIndex == null
        ? matchingIndices.last
        : matchingIndices[attachment.attachIndex!
            .clamp(0, matchingIndices.length - 1)
            .toInt()];
    final target = assembly[targetIndex];
    final shouldAppend = attachment.attachSide != 'start';
    final mergedContent = shouldAppend
        ? [
            target.message.content.trim(),
            attachment.content,
          ].where((value) => value.isNotEmpty).join('\n\n')
        : [
            attachment.content,
            target.message.content.trim(),
          ].where((value) => value.isNotEmpty).join('\n\n');

    final newBlocks = shouldAppend
        ? [
            ...target.blocks,
            _PromptAssemblyBlock(
              title: attachment.title,
              content: attachment.content,
            ),
          ]
        : [
            _PromptAssemblyBlock(
              title: attachment.title,
              content: attachment.content,
            ),
            ...target.blocks,
          ];

    assembly[targetIndex] = target.copyWith(
      message: target.message.copyWith(content: mergedContent),
      blocks: newBlocks,
    );
  }

  void _insertPromptAssemblyMessageAtDepth(
    List<_PromptAssemblyMessage> messages,
    _PromptAssemblyMessage message, {
    required int depth,
  }) {
    final normalizedContent = message.message.content.trim();
    if (normalizedContent.isEmpty) {
      return;
    }

    if (depth <= 0) {
      messages.add(
        message.copyWith(
          message: message.message.copyWith(content: normalizedContent),
        ),
      );
      return;
    }

    final conversationIndices = <int>[];
    for (var i = 0; i < messages.length; i++) {
      final role = messages[i].message.role;
      if (role == 'user' || role == 'assistant') {
        conversationIndices.add(i);
      }
    }

    if (conversationIndices.isEmpty) {
      messages.add(
        message.copyWith(
          message: message.message.copyWith(content: normalizedContent),
        ),
      );
      return;
    }

    final conversationCount = conversationIndices.length;
    final targetConversationIndex =
        (conversationCount - depth).clamp(0, conversationCount);

    if (targetConversationIndex >= conversationCount) {
      messages.add(
        message.copyWith(
          message: message.message.copyWith(content: normalizedContent),
        ),
      );
      return;
    }

    final insertIndex = conversationIndices[targetConversationIndex];
    messages.insert(
      insertIndex,
      message.copyWith(
        message: message.message.copyWith(content: normalizedContent),
      ),
    );
  }

  int _depthRolePriority(String role) {
    switch (_normalizeRole(role)) {
      case 'user':
        return 0;
      case 'assistant':
        return 1;
      default:
        return 2;
    }
  }

  bool _isPresetPromptEnabled(Preset? preset, String identifier) {
    if (preset == null || preset.prompts.isEmpty) {
      return true;
    }
    for (final prompt in preset.prompts) {
      if (prompt.identifier == identifier) {
        return prompt.enabled;
      }
    }
    return false;
  }

  PresetPrompt? _findPresetPrompt(Preset? preset, String identifier) {
    if (preset == null) {
      return null;
    }
    for (final prompt in preset.prompts) {
      if (prompt.identifier == identifier) {
        return prompt;
      }
    }
    return null;
  }

  List<ChatMessage> _collectHistoryWithinBudget(
      List<ChatMessage> history, int budget) {
    final originalHistory = history.where((m) => m.role != 'system').toList();
    if (originalHistory.isEmpty) {
      return const [];
    }

    final latestUserMessage = originalHistory.lastWhere(
      (message) => message.role == 'user',
      orElse: () => originalHistory.last,
    );

    if (budget <= 0) {
      return [latestUserMessage];
    }

    final validHistory = originalHistory.reversed.toList();
    final collected = <ChatMessage>[];
    int usedTokens = 0;

    for (final msg in validHistory) {
      final msgTokens = _estimateTokens(msg.content);
      if (usedTokens + msgTokens > budget) {
        break;
      }
      collected.add(msg);
      usedTokens += msgTokens;
    }

    final result = collected.reversed.toList();
    if (!result.contains(latestUserMessage)) {
      final latestUserTokens = _estimateTokens(latestUserMessage.content);
      final adjusted = List<ChatMessage>.from(result);
      var adjustedTokens = usedTokens;

      while (
          adjusted.isNotEmpty && adjustedTokens + latestUserTokens > budget) {
        adjustedTokens -= _estimateTokens(adjusted.first.content);
        adjusted.removeAt(0);
      }

      if (!adjusted.contains(latestUserMessage)) {
        adjusted.add(latestUserMessage);
      }

      return adjusted;
    }

    if (originalHistory.isNotEmpty) {
      final firstMessage = originalHistory.first;
      final shouldKeepGreeting =
          firstMessage.role == 'assistant' && !result.contains(firstMessage);
      if (shouldKeepGreeting) {
        final greetingTokens = _estimateTokens(firstMessage.content);
        if (usedTokens + greetingTokens <= budget) {
          return [firstMessage, ...result];
        }

        final adjusted = List<ChatMessage>.from(result);
        var adjustedTokens = usedTokens;
        while (adjusted.isNotEmpty &&
            adjustedTokens + greetingTokens > budget &&
            adjusted.first != firstMessage) {
          adjustedTokens -= _estimateTokens(adjusted.first.content);
          adjusted.removeAt(0);
        }
        if (adjustedTokens + greetingTokens <= budget) {
          return [firstMessage, ...adjusted];
        }
      }
    }

    return result;
  }

  List<ChatMessage> _applyChatVisibilityRange(List<ChatMessage> history) {
    final settings = _ref.read(memoryPluginSettingsProvider);
    if (!settings.isPluginEnabled ||
        (!settings.isHistoryRangeLimitEnabled &&
            !settings.isKeepLatestEnabled)) {
      return history;
    }

    final chatHistory = history.where((msg) => msg.role != 'system').toList();
    if (chatHistory.isEmpty) {
      return const [];
    }

    List<ChatMessage> visible = chatHistory;

    if (settings.isKeepLatestEnabled) {
      final keepCount =
          settings.keepLatestFloors <= 0 ? 1 : settings.keepLatestFloors;
      final startIndex = (visible.length - keepCount).clamp(0, visible.length);
      visible = visible.sublist(startIndex);
    } else if (settings.isHistoryRangeLimitEnabled) {
      final totalFloors = chatHistory.length;
      var startFloor =
          _normalizeFloorIndex(settings.historyRangeStartFloor, totalFloors);
      var endFloor =
          _normalizeFloorIndex(settings.historyRangeEndFloor, totalFloors);

      if (startFloor > endFloor) {
        final temp = startFloor;
        startFloor = endFloor;
        endFloor = temp;
      }

      visible = [
        for (final entry in chatHistory.asMap().entries)
          if (entry.key >= startFloor && entry.key <= endFloor) entry.value,
      ];
    }

    final visibleSet = <ChatMessage>{...visible};

    for (var i = chatHistory.length - 1; i >= 0; i--) {
      final msg = chatHistory[i];
      if (msg.role == 'user') {
        visibleSet.add(msg);
        break;
      }
    }

    return chatHistory.where((msg) => visibleSet.contains(msg)).toList();
  }

  int _normalizeFloorIndex(int floor, int totalFloors) {
    if (totalFloors <= 0) {
      return 0;
    }
    final raw = floor < 0 ? totalFloors + floor : floor;
    return raw.clamp(0, totalFloors - 1).toInt();
  }

  Map<String, dynamic> _getCharacterCardData(Character? character) {
    if (character == null) {
      return const <String, dynamic>{};
    }

    final root = character.rawCardData;
    final nested = root['data'];
    if (nested is Map) {
      return nested.map((key, value) => MapEntry(key.toString(), value));
    }
    return root;
  }

  String _readCharacterCardString(
    Character? character,
    List<String> keys, {
    String fallback = '',
  }) {
    final data = _getCharacterCardData(character);
    for (final key in keys) {
      final value = data[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return fallback;
  }

  String _buildTopSystemPrompt(Preset? preset) {
    final presetSystem = preset?.systemPrompt.trim() ?? '';
    return presetSystem;
  }

  String _getCharacterDescription(Character? character) {
    return _readCharacterCardString(
      character,
      const ['description'],
      fallback: character?.description.trim() ?? '',
    );
  }

  String _getCharacterPersonality(Character? character) {
    final rawPersonality = _readCharacterCardString(
      character,
      const ['personality', 'tavern_personality'],
    );
    if (rawPersonality.isNotEmpty) {
      return rawPersonality;
    }

    // 只取「性格」语义的字段。system_prompt 属于独立的系统提示词槽位，
    // 由 _getCharacterSystemPrompt 负责，不能在这里兜底，否则会被重复注入。
    return character?.personality.trim() ?? '';
  }

  /// 角色卡自带的系统提示词（chara_card_v2 的 `system_prompt` 字段）。
  String _getCharacterSystemPrompt(Character? character) {
    if (character == null) {
      return '';
    }

    final rawSystemPrompt = _readCharacterCardString(
      character,
      const ['system_prompt', 'systemPrompt'],
    );
    if (rawSystemPrompt.isNotEmpty) {
      return rawSystemPrompt;
    }

    return character.systemInstruction.trim();
  }

  String _getCharacterScenario(Character? character) {
    return _readCharacterCardString(
      character,
      const ['scenario', 'world_scenario'],
      fallback: character?.scenario.trim() ?? '',
    );
  }

  String _getCharacterCreatorNotes(Character? character) {
    final raw = _readCharacterCardString(
      character,
      const ['creator_notes', 'creatorNotes'],
    );
    if (raw.isNotEmpty) {
      return raw;
    }
    return character?.creatorNotes.trim() ?? '';
  }

  String _getCharacterDepthPrompt(Character? character) {
    final extensionPrompt =
        character?.rawExtensions['depth_prompt'] is Map<String, dynamic>
            ? (character!.rawExtensions['depth_prompt']
                        as Map<String, dynamic>)['prompt']
                    ?.toString()
                    .trim() ??
                ''
            : '';
    if (extensionPrompt.isNotEmpty) {
      return extensionPrompt;
    }

    final postHistory = _readCharacterCardString(
      character,
      const ['post_history_instructions', 'postHistoryInstructions'],
    );
    if (postHistory.isNotEmpty) {
      return postHistory;
    }

    return character?.authorsNote.trim() ?? '';
  }

  String _getCharacterDepthPromptRole(Character? character) {
    final rawDepthPrompt = character?.rawExtensions['depth_prompt'];
    if (rawDepthPrompt is Map) {
      final role = rawDepthPrompt['role']?.toString().trim() ?? '';
      if (role.isNotEmpty) {
        return _normalizeRole(role);
      }
    }
    return 'system';
  }

  _WorldInfoScanContext _buildWorldInfoScanContext(
    List<ChatMessage> history, {
    Character? character,
  }) {
    final visibleHistory =
        history.where((msg) => msg.role != 'system').toList();
    final memoryBlock = _buildMemoryBlock().trim();
    final authorsNoteBlock = _buildAuthorsNoteBlock(character).trim();

    return _WorldInfoScanContext(
      historyMessages: visibleHistory,
      character: character,
      personaDescription: _getUserDescription(),
      characterDescription: _getCharacterDescription(character),
      characterPersonality: _getCharacterPersonality(character),
      characterDepthPrompt: _getCharacterDepthPrompt(character),
      scenario: _getCharacterScenario(character),
      creatorNotes: _getCharacterCreatorNotes(character),
      injectionTexts: [
        if (memoryBlock.isNotEmpty) memoryBlock,
        if (_shouldInjectAuthorsNote(character, visibleHistory) &&
            authorsNoteBlock.isNotEmpty)
          authorsNoteBlock,
      ],
    );
  }

  String _buildWorldInfoEntryScanSource(
    _WorldInfoScanContext context,
    WorldInfoEntry entry, {
    required List<String> recursionBuffer,
    required int depthSkew,
    required _WorldInfoScanState scanState,
    required WorldInfoScanSettings settings,
  }) {
    final requestedDepth =
        entry.scanDepth ?? (settings.scanDepth + depthSkew).clamp(0, 1000);
    final historyBuffer = _buildWorldInfoHistoryScanBuffer(
      context.historyMessages,
      character: context.character,
      includeNames: settings.includeNames,
    );

    return buildWorldInfoScanSource(
      requestedDepth: requestedDepth,
      historyBuffer: historyBuffer,
      personaDescription:
          entry.matchPersonaDescription ? context.personaDescription : '',
      characterDescription: entry.matchCharacterDescription &&
              context.characterDescription.isNotEmpty
          ? _replaceMacros(context.characterDescription, context.character)
          : '',
      characterPersonality: entry.matchCharacterPersonality &&
              context.characterPersonality.isNotEmpty
          ? _replaceMacros(context.characterPersonality, context.character)
          : '',
      characterDepthPrompt: entry.matchCharacterDepthPrompt &&
              context.characterDepthPrompt.isNotEmpty
          ? _replaceMacros(context.characterDepthPrompt, context.character)
          : '',
      scenario: entry.matchScenario && context.scenario.isNotEmpty
          ? _replaceMacros(context.scenario, context.character)
          : '',
      creatorNotes: entry.matchCreatorNotes ? context.creatorNotes : '',
      injectionTexts: context.injectionTexts,
      recursionBuffer: recursionBuffer,
      includeRecursionBuffer: scanState != _WorldInfoScanState.minActivations,
    );
  }

  List<String> _buildWorldInfoHistoryScanBuffer(
    List<ChatMessage> historyMessages, {
    required Character? character,
    required bool includeNames,
  }) {
    final formatted = <String>[
      for (final message in historyMessages)
        _formatWorldInfoHistoryMessage(
          message,
          character: character,
          includeNames: includeNames,
        ),
    ].where((message) => message.trim().isNotEmpty).toList(growable: false);
    return formatted.reversed.toList(growable: false);
  }

  String _formatWorldInfoHistoryMessage(
    ChatMessage message, {
    required Character? character,
    required bool includeNames,
  }) {
    final content = message.content.trim();
    if (content.isEmpty) {
      return '';
    }
    if (!includeNames) {
      return content;
    }

    final metadataName = message.metadata?['name']?.toString().trim() ?? '';
    final speakerName = metadataName.isNotEmpty
        ? metadataName
        : switch (message.role) {
            'user' => _getUserName(),
            'assistant' => character?.name.trim() ?? 'Assistant',
            _ => '',
          };
    if (speakerName.isEmpty) {
      return content;
    }
    return '$speakerName: $content';
  }

  List<String> _interleaveWorldInfoIds(
    List<String> first,
    List<String> second,
  ) {
    final result = <String>[];
    final maxLength = math.max(first.length, second.length);
    for (var i = 0; i < maxLength; i++) {
      if (i < first.length) {
        result.add(first[i]);
      }
      if (i < second.length) {
        result.add(second[i]);
      }
    }
    return result;
  }

  RegExp? _tryParseWorldInfoKeyRegex(
    String value, {
    required bool caseSensitive,
  }) {
    if (value.length < 2 || !value.startsWith('/')) {
      return null;
    }
    final lastSlash = value.lastIndexOf('/');
    if (lastSlash <= 0) {
      return null;
    }

    final pattern = value.substring(1, lastSlash);
    final flags = value.substring(lastSlash + 1);
    var unicode = false;
    var multiLine = false;
    var dotAll = false;
    var effectiveCaseSensitive = caseSensitive;

    for (final flag in flags.split('')) {
      switch (flag) {
        case 'i':
          effectiveCaseSensitive = false;
          break;
        case 'm':
          multiLine = true;
          break;
        case 's':
          dotAll = true;
          break;
        case 'u':
          unicode = true;
          break;
        case '':
          break;
        default:
          return null;
      }
    }

    try {
      return RegExp(
        pattern,
        caseSensitive: effectiveCaseSensitive,
        multiLine: multiLine,
        dotAll: dotAll,
        unicode: unicode,
      );
    } catch (_) {
      return null;
    }
  }

  _WorldInfoActivationState _buildWorldInfoActivationState(
    List<ChatMessage> historyMessages,
  ) {
    final assistantMessages = historyMessages
        .where((message) => message.role == 'assistant')
        .toList();
    final turnsByKey = <String, int>{};
    final turnsByUid = <int, int>{};

    for (var i = 0; i < assistantMessages.length; i++) {
      final message = assistantMessages[i];
      final currentTurn = i + 1;
      final pipeline = message.metadata?['pipeline'];
      final rawWorldInfo = pipeline is Map ? pipeline['worldInfo'] : null;
      if (rawWorldInfo is! List) {
        continue;
      }

      for (final item in rawWorldInfo) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final activationKey = map['activation_key']?.toString().trim() ?? '';
        if (activationKey.isNotEmpty) {
          turnsByKey[activationKey] = currentTurn;
        }

        final uidRaw = map['uid'];
        final uid = uidRaw is num
            ? uidRaw.toInt()
            : int.tryParse(uidRaw?.toString() ?? '');
        if (uid != null) {
          turnsByUid[uid] = currentTurn;
        }
      }
    }

    return _WorldInfoActivationState(
      currentAssistantTurn: assistantMessages.length + 1,
      lastTurnByActivationKey: turnsByKey,
      lastTurnByUid: turnsByUid,
    );
  }

  String _buildWorldInfoActivationKey(WorldInfoEntry entry) {
    final comment = entry.comment.trim();
    final contentHash = entry.content.trim().hashCode;
    return '${entry.uid}|$comment|${entry.position}|${entry.depth}|$contentHash';
  }

  Map<String, dynamic> _buildPromptPreviewPayload(
    List<_PromptAssemblyMessage> assemblyMessages,
    List<ChatMessage> effectiveMessages,
  ) {
    final items = <Map<String, dynamic>>[];
    final count = math.min(assemblyMessages.length, effectiveMessages.length);

    for (var i = 0; i < count; i++) {
      final assembly = assemblyMessages[i];
      final effective = effectiveMessages[i];
      items.add({
        'index': i + 1,
        'role': effective.role,
        'source_key': assembly.sourceKey,
        'source_label': assembly.sourceLabel,
        'content': effective.content,
        'estimated_tokens': _estimateTokens(effective.content),
        'blocks': [
          for (final block in assembly.blocks)
            {
              'title': block.title,
              'content': block.content,
            }
        ],
      });
    }

    return {
      'message_count': effectiveMessages.length,
      'estimated_tokens': effectiveMessages.fold<int>(
        0,
        (sum, message) => sum + _estimateTokens(message.content),
      ),
      'messages': items,
    };
  }

  String _buildRpHubExampleDialogueBlock(Character? character) {
    if (character == null || character.exampleDialogue.trim().isEmpty) {
      return '';
    }

    final content =
        _replaceMacros(character.exampleDialogue.trim(), character).trim();
    if (content.isEmpty) {
      return '';
    }

    return 'Example Dialogue:\n$content';
  }

  String _buildWorldInfoBlock(
    List<WorldInfoEntry> entries,
    Character? character,
  ) {
    if (entries.isEmpty) {
      return '';
    }

    final lines = [
      for (final entry in entries)
        _buildSingleWorldInfoEntry(entry, character).trim(),
    ].where((line) => line.isNotEmpty).toList();
    return lines.join('\n\n');
  }

  String _buildSingleWorldInfoEntry(
    WorldInfoEntry entry,
    Character? character,
  ) {
    // 世界书的 `comment` 只是条目标题（给用户看的），酒馆不会把它写进 prompt。
    // 之前拼成 `[comment]\ncontent` 会把标题一起送给模型，属于多余 token 与噪音。
    return _replaceMacros(entry.content.trim(), character);
  }

  String _buildMemoryBlock() {
    final settings = _ref.read(memoryPluginSettingsProvider);
    if (!settings.isPluginEnabled || !settings.isAiReadTable) {
      return '';
    }

    final memoryTables = _ref.read(memoryProvider);
    if (memoryTables.isEmpty || !memoryTables.any((t) => t.isEnabled)) {
      return '';
    }
    return _ref
        .read(memoryProvider.notifier)
        .getFormattedMemory(settings: settings);
  }

  /// 组装记忆注入的调试信息，供聊天页调试面板展示。
  ///
  /// `fallbackUsed` 尤其重要：记忆块正常应经预设的 `vectorsMemory` 槽位注入，
  /// 槽位缺失时才走 `memory_fallback` 兜底。用户能直接看到「走的是哪条路」，
  /// 就不必再靠猜判断记忆为什么没生效。
  Map<String, dynamic> _buildMemoryPipelineInfo(
    _ConstructedPromptResult constructedPrompt,
  ) {
    final settings = _ref.read(memoryPluginSettingsProvider);
    final tables = _ref.read(memoryProvider);

    final injectedTables =
        tables.where((t) => t.isEnabled && t.behavior.toChat).toList();
    final rowCount =
        injectedTables.fold<int>(0, (sum, t) => sum + t.rows.length);

    final block = settings.isPluginEnabled && settings.isAiReadTable
        ? _ref.read(memoryProvider.notifier).getFormattedMemory(settings: settings)
        : '';

    // ⚠️ 不能用 `sourceKey == 'vectorsMemory'` 判断槽位是否生效：
    // 预设里的 prompt 一律以 `sourceKey: 'preset_prompt'` 入队（见上方
    // addMessageEntry 调用处），槽位标识只保留在 `PresetPrompt.identifier`，
    // 不会透出到 assembly。因此这里改为**按内容比对**：如果没有走兜底，
    // 但 assembly 里确实存在承载记忆正文的那条消息，就说明槽位生效了。
    final fallbackUsed = constructedPrompt.assemblyMessages
        .any((m) => m.sourceKey == 'memory_fallback');
    final slotUsed = !fallbackUsed &&
        block.isNotEmpty &&
        constructedPrompt.assemblyMessages
            .any((m) => m.message.content.contains(block));

    return {
      'enabled': settings.isPluginEnabled,
      'readEnabled': settings.isAiReadTable,
      'writeEnabled': settings.isAiWriteTable,
      'injectedTableCount': injectedTables.length,
      'totalTableCount': tables.length,
      'rowCount': rowCount,
      'injectedChars': block.length,
      'injected': block.isNotEmpty,
      'usedSlot': slotUsed,
      'fallbackUsed': fallbackUsed,
      'fallbackDepth': settings.deep,
      'tableNames': injectedTables.map((t) => t.name).toList(),
    };
  }

  String _buildAuthorsNoteBlock(Character? character) {
    final authorsNote = _getCharacterDepthPrompt(character);
    if (character == null || authorsNote.isEmpty) {
      return '';
    }

    return [
      'Author\'s Note:',
      _replaceMacros(authorsNote, character),
    ].join('\n');
  }

  bool _shouldInjectAuthorsNote(
      Character? character, List<ChatMessage> history) {
    if (character == null || _getCharacterDepthPrompt(character).isEmpty) {
      return false;
    }

    final frequency = character.authorsNoteFrequency;
    if (frequency <= 1) {
      return true;
    }

    final assistantTurns =
        history.where((msg) => msg.role == 'assistant').length;
    if (assistantTurns == 0) {
      return true;
    }

    return assistantTurns % frequency == 0;
  }

  int _getConfiguredContextSize() {
    final connection = _ref.read(activeApiConnectionProvider);

    // 1) 连接上显式配置的上下文窗口优先。
    final explicit = _readPositiveInt(connection?.parameters['context_size']);
    if (explicit != null) {
      return explicit.clamp(512, 1 << 21);
    }

    // 2) 按协议给出合理默认值（OpenAI 兼容 8k / Claude 200k / Gemini 32k / 本地 4k）。
    //    旧实现恒返回 4096，导致长上下文模型被白白浪费。
    if (connection != null) {
      return resolveChatAdapter(connection.platform)
          .defaultContextSize
          .clamp(512, 1 << 21);
    }

    return _defaultMaxContextTokens;
  }

  int? _readPositiveInt(dynamic raw) {
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  /// 为模型回复预留的 token 数（同时也是请求里的 `max_tokens`）。
  ///
  /// 直接采用预设里的 `max_tokens`，只做两个保护性收敛：下限 128；
  /// 上限不超过上下文窗口本身（留 512 token 给提示词，避免空窗）。
  ///
  /// 注意：这里曾经额外用 `contextSize / 3` 封顶，导致本地模型
  /// （`context_size` 默认 2048）的 max_tokens 被从 2000 压到 682，
  /// 回复长度肉眼可见地变短。上下文不足的问题由 `historyBudget`
  /// 那一侧收缩历史来处理，不该牺牲回复长度。
  int _getResponseReserveTokens(Preset? preset, int contextSize) {
    final configured = preset?.maxTokens ?? _defaultResponseReserve;
    final maxReserve = math.max(
      128,
      contextSize <= 640 ? contextSize : contextSize - 512,
    );
    return configured.clamp(128, maxReserve).toInt();
  }

  _PromptWorldInfoGroups _groupWorldInfoByPosition(
      List<WorldInfoEntry> entries) {
    final beforeCharacter = <WorldInfoEntry>[];
    final afterCharacter = <WorldInfoEntry>[];
    final beforeAuthorsNote = <WorldInfoEntry>[];
    final afterAuthorsNote = <WorldInfoEntry>[];
    final beforeExamples = <WorldInfoEntry>[];
    final afterExamples = <WorldInfoEntry>[];
    final atDepth = <WorldInfoEntry>[];
    final userTop = <WorldInfoEntry>[];
    final assistantTop = <WorldInfoEntry>[];

    for (final entry in entries) {
      switch (entry.position) {
        case _WorldInfoPosition.beforeCharacter:
          beforeCharacter.add(entry);
          break;
        case _WorldInfoPosition.afterCharacter:
          afterCharacter.add(entry);
          break;
        case _WorldInfoPosition.beforeAuthorsNote:
          beforeAuthorsNote.add(entry);
          break;
        case _WorldInfoPosition.afterAuthorsNote:
          afterAuthorsNote.add(entry);
          break;
        case _WorldInfoPosition.atDepth:
          atDepth.add(entry);
          break;
        case _WorldInfoPosition.beforeExamples:
          beforeExamples.add(entry);
          break;
        case _WorldInfoPosition.afterExamples:
          afterExamples.add(entry);
          break;
        case _WorldInfoPosition.userTop:
          userTop.add(entry);
          break;
        case _WorldInfoPosition.assistantTop:
          assistantTop.add(entry);
          break;
        default:
          atDepth.add(entry);
          break;
      }
    }

    return _PromptWorldInfoGroups(
      beforeCharacter: beforeCharacter,
      afterCharacter: afterCharacter,
      beforeAuthorsNote: beforeAuthorsNote,
      afterAuthorsNote: afterAuthorsNote,
      beforeExamples: beforeExamples,
      afterExamples: afterExamples,
      atDepth: atDepth,
      userTop: userTop,
      assistantTop: assistantTop,
    );
  }

  /// 规范化角色名。酒馆生态里 preset / 世界书的 role 字段写法很杂
  /// （`ai` / `bot` / `char` / `human` / `sys`），统一收敛到 OpenAI 的三种角色。
  String _normalizeRole(String role) {
    switch (role.trim().toLowerCase()) {
      case 'assistant':
      case 'ai':
      case 'bot':
      case 'char':
      case 'character':
        return 'assistant';
      case 'user':
      case 'human':
      case 'me':
        return 'user';
      case 'system':
      case 'sys':
        return 'system';
      default:
        return 'system';
    }
  }

  String _normalizeWorldInfoRole(String role) {
    final normalized = _normalizeRole(role);
    if (normalized == 'user' || normalized == 'assistant') {
      return normalized;
    }
    return 'system';
  }
}

final RegExp _regexProtectedBlockPattern = RegExp(
  r'(<!DOCTYPE html>[\s\S]*?</html>|<html\b[^>]*>[\s\S]*?</html>|<script\b[^>]*>[\s\S]*?</script>|<style\b[^>]*>[\s\S]*?</style>|<(?:cot|think)>[\s\S]*?(?:</(?:cot|think)>|<(?:cot|think)>|$)|```[\s\S]*?```|`[^`]+`|</?[a-zA-Z][\w:-]*[^>]*>)',
  caseSensitive: false,
  multiLine: true,
);

class _WorldInfoPosition {
  static const int beforeCharacter = 0;
  static const int afterCharacter = 1;
  static const int beforeAuthorsNote = 2;
  static const int afterAuthorsNote = 3;
  static const int atDepth = 4;
  static const int beforeExamples = 5;
  static const int afterExamples = 6;
  static const int userTop = 7;
  static const int assistantTop = 8;
}

class _PromptWorldInfoGroups {
  final List<WorldInfoEntry> beforeCharacter;
  final List<WorldInfoEntry> afterCharacter;
  final List<WorldInfoEntry> beforeAuthorsNote;
  final List<WorldInfoEntry> afterAuthorsNote;
  final List<WorldInfoEntry> beforeExamples;
  final List<WorldInfoEntry> afterExamples;
  final List<WorldInfoEntry> atDepth;
  final List<WorldInfoEntry> userTop;
  final List<WorldInfoEntry> assistantTop;

  const _PromptWorldInfoGroups({
    required this.beforeCharacter,
    required this.afterCharacter,
    required this.beforeAuthorsNote,
    required this.afterAuthorsNote,
    required this.beforeExamples,
    required this.afterExamples,
    required this.atDepth,
    required this.userTop,
    required this.assistantTop,
  });
}

class _WorldInfoScanContext {
  final List<ChatMessage> historyMessages;
  final Character? character;
  final String personaDescription;
  final String characterDescription;
  final String characterPersonality;
  final String characterDepthPrompt;
  final String scenario;
  final String creatorNotes;
  final List<String> injectionTexts;

  const _WorldInfoScanContext({
    required this.historyMessages,
    required this.character,
    required this.personaDescription,
    required this.characterDescription,
    required this.characterPersonality,
    required this.characterDepthPrompt,
    required this.scenario,
    required this.creatorNotes,
    required this.injectionTexts,
  });
}

class _WorldInfoActivationState {
  final int currentAssistantTurn;
  final Map<String, int> lastTurnByActivationKey;
  final Map<int, int> lastTurnByUid;

  const _WorldInfoActivationState({
    required this.currentAssistantTurn,
    required this.lastTurnByActivationKey,
    required this.lastTurnByUid,
  });

  int? turnsSinceLastActivationFor(
    String activationKey, {
    required int fallbackUid,
  }) {
    final turn =
        lastTurnByActivationKey[activationKey] ?? lastTurnByUid[fallbackUid];
    if (turn == null) {
      return null;
    }
    return currentAssistantTurn - turn;
  }
}

class _WorldInfoEffectState {
  final bool isSticky;
  final bool inCooldown;
  final bool inDelayWindow;

  const _WorldInfoEffectState({
    this.isSticky = false,
    this.inCooldown = false,
    this.inDelayWindow = false,
  });
}

class _WorldInfoCandidate {
  final String triggerKey;
  final WorldInfoEntry entry;
  final String worldInfoId;
  final String worldInfoName;
  final String sourceKind;
  final int sourceOrder;

  /// 命中关键词的计数（至少为 1）。供「使用群组评分」时在同一群组内排序。
  final int score;

  const _WorldInfoCandidate({
    required this.triggerKey,
    required this.entry,
    required this.worldInfoId,
    required this.worldInfoName,
    required this.sourceKind,
    required this.sourceOrder,
    this.score = 1,
  });
}

class _TriggeredWorldInfoEntry {
  final WorldInfoEntry entry;
  final String worldInfoId;
  final String worldInfoName;
  final String sourceKind;
  final int sourceOrder;

  const _TriggeredWorldInfoEntry({
    required this.entry,
    required this.worldInfoId,
    required this.worldInfoName,
    required this.sourceKind,
    required this.sourceOrder,
  });
}

class _ConstructedPromptResult {
  final List<_PromptAssemblyMessage> assemblyMessages;

  /// 本次装配使用的上下文窗口。
  final int maxContextTokens;

  /// 为模型回复预留的 token 数（同时也是请求里的 max_tokens）。
  final int responseReserveTokens;

  const _ConstructedPromptResult({
    required this.assemblyMessages,
    this.maxContextTokens = 0,
    this.responseReserveTokens = 0,
  });

  List<ChatMessage> get messages =>
      assemblyMessages.map((entry) => entry.message).toList(growable: false);
}

class _PromptAssemblyBlock {
  final String title;
  final String content;

  const _PromptAssemblyBlock({
    required this.title,
    required this.content,
  });
}

class _PromptAssemblyMessage {
  final ChatMessage message;
  final String sourceKey;
  final String sourceLabel;
  final List<_PromptAssemblyBlock> blocks;

  const _PromptAssemblyMessage({
    required this.message,
    required this.sourceKey,
    required this.sourceLabel,
    this.blocks = const [],
  });

  _PromptAssemblyMessage copyWith({
    ChatMessage? message,
    String? sourceKey,
    String? sourceLabel,
    List<_PromptAssemblyBlock>? blocks,
  }) {
    return _PromptAssemblyMessage(
      message: message ?? this.message,
      sourceKey: sourceKey ?? this.sourceKey,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      blocks: blocks ?? this.blocks,
    );
  }
}

class _PromptPlanEntry {
  final _PromptAssemblyMessage? message;
  final bool isHistoryMarker;

  const _PromptPlanEntry._({
    required this.message,
    required this.isHistoryMarker,
  });

  const _PromptPlanEntry.message(_PromptAssemblyMessage message)
      : this._(message: message, isHistoryMarker: false);

  const _PromptPlanEntry.historyMarker()
      : this._(message: null, isHistoryMarker: true);
}

class _AssemblyAttachmentPrompt {
  final String role;
  final String content;
  final String sourceKey;
  final String sourceLabel;
  final String title;
  final String attachRole;
  final int? attachIndex;
  final String attachSide;
  final int order;

  const _AssemblyAttachmentPrompt({
    required this.role,
    required this.content,
    required this.sourceKey,
    required this.sourceLabel,
    required this.title,
    required this.attachRole,
    required this.attachIndex,
    required this.attachSide,
    required this.order,
  });
}

class _ProtectedRegexSegment {
  final String text;
  final bool isProtected;

  const _ProtectedRegexSegment(this.text, this.isProtected);
}

class _ParsedRegexPattern {
  final String sourcePattern;
  final RegExp regExp;

  const _ParsedRegexPattern({
    required this.sourcePattern,
    required this.regExp,
  });
}
