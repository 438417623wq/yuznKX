import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../api_connection/data/api_connection_provider.dart';
import '../../presets/data/preset_provider.dart';
import '../../presets/domain/models/preset.dart';
import '../../world_info/data/world_info_provider.dart';
import '../../regex/data/regex_provider.dart';
import '../../regex/domain/models/regex_script.dart';
import '../../character/data/character_provider.dart';
import '../../character/domain/models/character.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/session.dart';
import 'chat_service.dart';
import 'session_provider.dart';

import 'dart:async';

final chatServiceProvider = Provider((ref) => ChatService());

// Family provider for chat sessions
final chatSessionProvider = StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>((ref, sessionId) {
  return ChatNotifier(ref, sessionId);
});

// Family providers for status
final chatLoadingProviderFamily = StateProvider.family<bool, String>((ref, sessionId) => false);
final isGeneratingProviderFamily = StateProvider.family<bool, String>((ref, sessionId) => false);

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  final String sessionId;
  StreamSubscription? _generationSubscription;

  ChatNotifier(this._ref, this.sessionId) : super([]) {
    _loadSession();
  }

  Character? _getCharacter() {
    try {
      final sessions = _ref.read(sessionProvider);
      final session = sessions.firstWhere((s) => s.id == sessionId);
      final characterId = session.characterId;
      if (characterId.isEmpty) return null;
      
      final characters = _ref.read(characterListProvider);
      return characters.firstWhere((c) => c.id == characterId);
    } catch (e) {
      return null;
    }
  }

  String _replaceMacros(String text, Character? character) {
    if (character == null) return text;
    return text
      .replaceAll('{{char}}', character.name)
      .replaceAll('{{user}}', 'User'); // TODO: Get from settings
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
          final firstMsgContent = _replaceMacros(character.firstMessage, character);
          state = [
            ChatMessage(
              role: 'assistant', 
              content: firstMsgContent, 
              timestamp: DateTime.now(),
              swipes: [firstMsgContent],
              currentIndex: 0
            )
          ];
          _persistMessages();
       }
    }
  }

  Future<void> clearHistory() async {
    state = [];
    checkEmptyState();
    await _persistMessages();
  }

  Future<void> stopGeneration() async {
    if (_generationSubscription != null) {
      _generationSubscription!.cancel();
      _generationSubscription = null;
      _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
      _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;
      await _persistMessages();
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    // Note: session creation is now handled by SessionManager or ensuring valid ID before calling this.
    // If sessionId refers to a non-existent session, we might have issues.
    // But typically ChatNotifier is created with a valid ID.

    String processedContent = _applyRegex(content, 1);

    final userMsg = ChatMessage(role: 'user', content: processedContent, timestamp: DateTime.now(), swipes: [processedContent], currentIndex: 0);
    state = [...state, userMsg];
    
    _persistMessages();

    await _processResponse();
  }

  Future<void> continueGeneration() async {
    if (state.isEmpty) return;
    
    final lastMsg = state.last;
    if (lastMsg.role == 'assistant') {
      await _processResponse(continueLast: true);
    } else {
      await _processResponse();
    }
  }

  Future<void> regenerateLast() async {
    if (state.isEmpty) return;
    final lastIndex = state.length - 1;
    final lastMsg = state[lastIndex];
    if (lastMsg.role == 'assistant') {
      await _processResponse(regenerate: true, overrideTargetIndex: lastIndex);
    }
  }

  Future<void> regenerateMessage(int index) async {
    if (index < 0 || index >= state.length) return;
    
    final msg = state[index];
    if (msg.role == 'assistant') {
       await _processResponse(regenerate: true, overrideTargetIndex: index);
    }
  }

  Future<void> _processResponse({bool continueLast = false, bool regenerate = false, int? overrideTargetIndex}) async {
    final connection = _ref.read(activeApiConnectionProvider);
    if (connection == null) {
      state = [...state, ChatMessage(role: 'system', content: '错误：未选择 API 连接。', timestamp: DateTime.now(), swipes: ['错误：未选择 API 连接。'], currentIndex: 0)];
      _persistMessages();
      return;
    }

    _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = true;
    _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = true;

    try {
      int targetIndex = -1;
      ChatMessage? targetMsg;
      String initialContent = '';

      if (regenerate && overrideTargetIndex != null) {
        targetIndex = overrideTargetIndex;
        final oldMsg = state[targetIndex];
        final newSwipes = List<String>.from(oldMsg.swipes)..add('');
        targetMsg = oldMsg.copyWith(
          swipes: newSwipes,
          currentIndex: newSwipes.length - 1,
          content: '',
        );
      } else if (continueLast) {
         targetIndex = state.length - 1;
         targetMsg = state[targetIndex];
         initialContent = targetMsg.content;
      } else {
         targetMsg = ChatMessage(
           role: 'assistant',
           content: '',
           timestamp: DateTime.now(),
           swipes: [''],
           currentIndex: 0,
         );
         state = [...state, targetMsg];
         targetIndex = state.length - 1;
      }

      if (targetMsg != null) {
        final List<ChatMessage> newState = List.from(state);
        newState[targetIndex] = targetMsg;
        state = newState;
      }

      List<ChatMessage> history;
      if (regenerate) {
        history = state.sublist(0, targetIndex);
      } else if (continueLast) {
        history = state.sublist(0, targetIndex); 
        history = [...history, targetMsg!]; 
      } else {
        history = state.sublist(0, targetIndex);
      }

      // Capture context for background generation
      final activeRegexIds = _ref.read(activeRegexScriptIdsProvider);
      final activeWiIds = _ref.read(activeWorldInfoIdsProvider);
      final activePreset = _ref.read(activePresetProvider);
      final character = _getCharacter(); // This is already session-specific
      final preferredModel = character?.preferredModelName;

      final recentHistory = history.reversed.take(5).map((e) => e.content).join('\n');
      final injectedWorldInfo = _scanWorldInfo(recentHistory, overrideWorldInfoIds: activeWiIds);
      final messagesToSend = _constructPrompt(history, injectedWorldInfo, overridePreset: activePreset);

      final service = _ref.read(chatServiceProvider);
      // Use captured preset
      final preset = activePreset; 

      final params = <String, dynamic>{};
      if (preset != null) {
        params['temperature'] = preset.temperature;
        params['frequency_penalty'] = preset.frequencyPenalty;
        params['presence_penalty'] = preset.presencePenalty;
        params['top_p'] = preset.topP;
        params['max_tokens'] = preset.maxTokens;
        if (preset.repetitionPenalty != 1.0) {
           params['repetition_penalty'] = preset.repetitionPenalty;
        }
      }

      final stream = service.streamMessage(
        connection: connection,
        messages: messagesToSend,
        parameters: params,
        overrideModel: preferredModel,
      );
      
      int chunkCount = 0;

      _generationSubscription = stream.listen(
        (chunk) {
          if (targetIndex >= state.length) return;

          final currentMsg = state[targetIndex];
          final currentSwipes = List<String>.from(currentMsg.swipes);
          final currentIndex = currentMsg.currentIndex;
          
          String newContent = currentSwipes[currentIndex] + chunk;
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
           _generationSubscription = null;
           _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
           _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;
           _persistMessages();
           
           final finalMsg = state[targetIndex];
           final content = finalMsg.content;
           // Use captured activeRegexIds and activePreset
           final processed = _applyRegex(content, 2, overrideRegexIds: activeRegexIds, overridePreset: activePreset);
           if (processed != content) {
             final swipes = List<String>.from(finalMsg.swipes);
             swipes[finalMsg.currentIndex] = processed;
             final processedMsg = finalMsg.copyWith(content: processed, swipes: swipes);
             final newState = List<ChatMessage>.from(state);
             newState[targetIndex] = processedMsg;
             state = newState;
             _persistMessages();
           }
        },
        onError: (e) {
           _generationSubscription = null;
           _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
           _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;
           print("Generation error: $e");
        }
      );

    } catch (e) {
      _ref.read(chatLoadingProviderFamily(sessionId).notifier).state = false;
      _ref.read(isGeneratingProviderFamily(sessionId).notifier).state = false;
      print("Start generation error: $e");
    }
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
    if (newSwipes.isNotEmpty && msg.currentIndex >= 0 && msg.currentIndex < newSwipes.length) {
      newSwipes[msg.currentIndex] = newContent;
    } else {
      newSwipes = [newContent];
    }
    
    final updatedMsg = msg.copyWith(
      content: newContent,
      swipes: newSwipes
    );
    
    final newState = [...state];
    newState[index] = updatedMsg;
    state = newState;
    _persistMessages();
  }

  Future<void> _persistMessages() async {
    await _ref.read(sessionProvider.notifier).updateSessionMessages(sessionId, state);
  }


  String _applyRegex(String text, int placement, {List<String>? overrideRegexIds, Preset? overridePreset}) {
    String result = text;

    // 2. Preset Regex
    final preset = overridePreset ?? _ref.read(activePresetProvider);
    if (preset != null) {
      final activePresetRegex = preset.regexScripts.where((r) => !r.disabled).toList();
      for (final script in activePresetRegex) {
        if (script.placement.contains(placement)) {
          result = _runScript(result, script);
        }
      }
    }

    return result;
  }

  String _runScript(String input, RegexScript script) {
    try {
      // JavaScript style regex flags are not fully supported in Dart directly.
      // We assume standard Dart RegExp.
      // If script.findRegex starts with /, we might need to parse flags.
      // For now, let's treat findRegex as the pattern directly.
      // TODO: Implement proper JS regex parsing if needed.
      
      String pattern = script.findRegex;
      bool caseSensitive = true;
      bool multiLine = false;
      bool dotAll = false;

      // Simple heuristic for JS style /pattern/flags
      if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
        final lastSlash = pattern.lastIndexOf('/');
        final flags = pattern.substring(lastSlash + 1);
        pattern = pattern.substring(1, lastSlash);

        if (flags.contains('i')) caseSensitive = false;
        if (flags.contains('m')) multiLine = true;
        if (flags.contains('s')) dotAll = true;
      }

      final regExp = RegExp(
        pattern, 
        caseSensitive: caseSensitive, 
        multiLine: multiLine, 
        dotAll: dotAll
      );

      return input.replaceAll(regExp, script.replaceString);
    } catch (e) {
      print('Regex Error (${script.scriptName}): $e');
      return input;
    }
  }

  List<String> _scanWorldInfo(String text, {List<String>? overrideWorldInfoIds}) {
    final List<String> activeWiIds = overrideWorldInfoIds ?? _ref.read(activeWorldInfoIdsProvider);
    final allWi = _ref.read(worldInfoProvider);
    final activeWi = allWi.where((w) => activeWiIds.contains(w.id)).toList();
    
    List<String> triggeredContent = [];

    for (final wi in activeWi) {
      for (final entry in wi.entries) {
        if (entry.disable) continue;
        
        bool triggered = false;
        
        // Check primary keys
        for (final key in entry.keys) {
          if (text.contains(key)) {
            triggered = true;
            break;
          }
        }

        // Logic Combination (Simplified)
        if (triggered && entry.selective) {
          // Check secondary keys (AND logic default)
          // TODO: Implement full selective logic (AND/OR/NOT)
          bool secondaryTriggered = false;
          for (final key in entry.secondaryKeys) {
            if (text.contains(key)) {
              secondaryTriggered = true;
              break;
            }
          }
          if (!secondaryTriggered) triggered = false;
        }

        if (triggered) {
          triggeredContent.add(entry.content);
        }
      }
    }
    return triggeredContent;
  }

  List<ChatMessage> _constructPrompt(List<ChatMessage> history, List<String> worldInfo, {Preset? overridePreset}) {
    final preset = overridePreset ?? _ref.read(activePresetProvider);
    final activeCharacter = _getCharacter();
    List<ChatMessage> finalMessages = [];

    // 1. System Prompt (Main)
    String systemContent = '';
    
    if (activeCharacter != null) {
      // Character Mode
      systemContent = _replaceMacros(activeCharacter.systemInstruction, activeCharacter); // Description/Personality
      if (activeCharacter.scenario.isNotEmpty) {
        systemContent += '\n\n[Scenario: ${_replaceMacros(activeCharacter.scenario, activeCharacter)}]';
      }
      // TODO: Add example dialogues, etc.
    } else {
      // Default Assistant Mode
      systemContent = "You are a helpful AI assistant.";
    }

    if (preset != null && preset.impersonationPrompt.isNotEmpty) {
       // Impersonation prompt is usually appended to system or user?
       // Let's use it as system for now.
       systemContent += '\n\n${preset.impersonationPrompt}';
    }

    // Add World Info to System (Simplified: Just add to top)
    if (worldInfo.isNotEmpty) {
      systemContent += "\n\n[World Info]\n${worldInfo.join('\n')}";
    }

    finalMessages.add(ChatMessage(role: 'system', content: systemContent, timestamp: DateTime.now()));

    // 2. Chat History (excluding internal system messages from UI)
    final validHistory = history.where((m) => m.role != 'system').toList();
    finalMessages.addAll(validHistory);

    // 3. Inject Preset Prompts (Post-History / Depth injection)
    if (preset != null) {
      // Sort prompts by depth/order?
      // For now, let's just append 'system' prompts to the end (Depth 0)
      for (final prompt in preset.prompts) {
        if (prompt.enabled && prompt.role == 'system') {
           // If depth is 0, append to end
           if (prompt.injectionDepth == 0) {
             finalMessages.add(ChatMessage(role: 'system', content: prompt.content, timestamp: DateTime.now()));
           } else {
             // Inject at depth (from bottom)
             int insertIndex = finalMessages.length - prompt.injectionDepth;
             if (insertIndex < 1) insertIndex = 1; // Keep at least the first system message
             if (insertIndex > finalMessages.length) insertIndex = finalMessages.length;
             finalMessages.insert(insertIndex, ChatMessage(role: 'system', content: prompt.content, timestamp: DateTime.now()));
           }
        }
      }
    }

    return finalMessages;
  }
}
