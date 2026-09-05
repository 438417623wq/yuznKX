import '../domain/models/chat_message.dart';

const Object _continuedMessageSentinel = Object();

enum RpHubContextGenerationType {
  normal,
  continueMode,
  impersonate,
  quiet,
}

class RpHubContextBlock {
  final String title;
  final String content;

  const RpHubContextBlock({
    required this.title,
    required this.content,
  });
}

class RpHubContextPrompt {
  final String name;
  final String role;
  final String content;

  const RpHubContextPrompt({
    required this.name,
    required this.role,
    required this.content,
  });
}

class RpHubContextDepthInjection {
  final String title;
  final String role;
  final String content;
  final int depth;
  final int order;
  final String sourceKey;
  final String sourceLabel;

  const RpHubContextDepthInjection({
    required this.title,
    required this.role,
    required this.content,
    required this.depth,
    required this.order,
    required this.sourceKey,
    required this.sourceLabel,
  });
}

class RpHubContextAssemblyMessage {
  final ChatMessage message;
  final String sourceKey;
  final String sourceLabel;
  final List<RpHubContextBlock> blocks;

  const RpHubContextAssemblyMessage({
    required this.message,
    required this.sourceKey,
    required this.sourceLabel,
    this.blocks = const [],
  });

  RpHubContextAssemblyMessage copyWith({
    ChatMessage? message,
    String? sourceKey,
    String? sourceLabel,
    List<RpHubContextBlock>? blocks,
  }) {
    return RpHubContextAssemblyMessage(
      message: message ?? this.message,
      sourceKey: sourceKey ?? this.sourceKey,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      blocks: blocks ?? this.blocks,
    );
  }
}

class RpHubContextBuildInput {
  final List<ChatMessage> history;
  final String topSystemPrompt;
  final List<RpHubContextPrompt> systemPrompts;
  final List<RpHubContextPrompt> preHistoryPrompts;
  final List<RpHubContextDepthInjection> depthInjections;
  final String beforeCharacterWorldInfo;
  final String afterCharacterWorldInfo;
  final String beforeExamplesWorldInfo;
  final String afterExamplesWorldInfo;
  final String characterBlock;
  final String exampleDialogueBlock;
  final String userBlock;
  final String memoryBlock;
  final String newChatPrompt;
  final String groupNudgePrompt;
  final String assistantTopWorldInfo;
  final String userTopWorldInfo;
  final ChatMessage? continuedMessage;
  final String continueNudge;
  final String impersonationPrompt;
  final String quietPrompt;
  final bool isGroupChat;
  final bool isNewChat;
  final RpHubContextGenerationType generationType;

  const RpHubContextBuildInput({
    required this.history,
    required this.topSystemPrompt,
    this.systemPrompts = const [],
    this.preHistoryPrompts = const [],
    this.depthInjections = const [],
    this.beforeCharacterWorldInfo = '',
    this.afterCharacterWorldInfo = '',
    this.beforeExamplesWorldInfo = '',
    this.afterExamplesWorldInfo = '',
    this.characterBlock = '',
    this.exampleDialogueBlock = '',
    this.userBlock = '',
    this.memoryBlock = '',
    this.newChatPrompt = '',
    this.groupNudgePrompt = '',
    this.assistantTopWorldInfo = '',
    this.userTopWorldInfo = '',
    this.continuedMessage,
    this.continueNudge = '',
    this.impersonationPrompt = '',
    this.quietPrompt = '',
    this.isGroupChat = false,
    this.isNewChat = false,
    this.generationType = RpHubContextGenerationType.normal,
  });

  RpHubContextBuildInput copyWith({
    List<ChatMessage>? history,
    Object? continuedMessage = _continuedMessageSentinel,
  }) {
    return RpHubContextBuildInput(
      history: history ?? this.history,
      topSystemPrompt: topSystemPrompt,
      systemPrompts: systemPrompts,
      preHistoryPrompts: preHistoryPrompts,
      depthInjections: depthInjections,
      beforeCharacterWorldInfo: beforeCharacterWorldInfo,
      afterCharacterWorldInfo: afterCharacterWorldInfo,
      beforeExamplesWorldInfo: beforeExamplesWorldInfo,
      afterExamplesWorldInfo: afterExamplesWorldInfo,
      characterBlock: characterBlock,
      exampleDialogueBlock: exampleDialogueBlock,
      userBlock: userBlock,
      memoryBlock: memoryBlock,
      newChatPrompt: newChatPrompt,
      groupNudgePrompt: groupNudgePrompt,
      assistantTopWorldInfo: assistantTopWorldInfo,
      userTopWorldInfo: userTopWorldInfo,
      continuedMessage: continuedMessage == _continuedMessageSentinel
          ? this.continuedMessage
          : continuedMessage as ChatMessage?,
      continueNudge: continueNudge,
      impersonationPrompt: impersonationPrompt,
      quietPrompt: quietPrompt,
      isGroupChat: isGroupChat,
      isNewChat: isNewChat,
      generationType: generationType,
    );
  }
}

class RpHubContextBuildResult {
  final List<RpHubContextAssemblyMessage> assemblyMessages;

  const RpHubContextBuildResult({
    required this.assemblyMessages,
  });

  List<ChatMessage> get messages =>
      assemblyMessages.map((entry) => entry.message).toList(growable: false);
}

RpHubContextBuildResult buildRpHubStyleContext(
  RpHubContextBuildInput input,
) {
  final assembly = <RpHubContextAssemblyMessage>[];
  final now = DateTime.now();

  final systemBlocks = <RpHubContextBlock>[
    if (input.topSystemPrompt.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'System Prompt',
        content: input.topSystemPrompt.trim(),
      ),
    for (final prompt in input.systemPrompts)
      if (prompt.content.trim().isNotEmpty)
        RpHubContextBlock(
          title: prompt.name,
          content: prompt.content.trim(),
        ),
    if (input.beforeCharacterWorldInfo.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'World Info Before Character',
        content: input.beforeCharacterWorldInfo.trim(),
      ),
    if (input.characterBlock.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'Character Card',
        content: input.characterBlock.trim(),
      ),
    if (input.afterCharacterWorldInfo.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'World Info After Character',
        content: input.afterCharacterWorldInfo.trim(),
      ),
    if (input.beforeExamplesWorldInfo.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'World Info Before Examples',
        content: input.beforeExamplesWorldInfo.trim(),
      ),
    if (input.exampleDialogueBlock.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'Example Dialogue',
        content: input.exampleDialogueBlock.trim(),
      ),
    if (input.afterExamplesWorldInfo.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'World Info After Examples',
        content: input.afterExamplesWorldInfo.trim(),
      ),
    if (input.userBlock.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'User Info',
        content: input.userBlock.trim(),
      ),
    if (input.memoryBlock.trim().isNotEmpty)
      RpHubContextBlock(
        title: 'Memory',
        content: input.memoryBlock.trim(),
      ),
  ];

  if (systemBlocks.isNotEmpty) {
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: systemBlocks.map((block) => block.content).join('\n\n'),
          timestamp: now,
        ),
        sourceKey: 'system_setup',
        sourceLabel: 'System Setup',
        blocks: systemBlocks,
      ),
    );
  }

  if (input.isNewChat && input.newChatPrompt.trim().isNotEmpty) {
    final content = input.newChatPrompt.trim();
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: content,
          timestamp: now,
        ),
        sourceKey: 'new_chat',
        sourceLabel: 'New Chat Prompt',
        blocks: [
          RpHubContextBlock(
            title: 'New Chat Prompt',
            content: content,
          ),
        ],
      ),
    );
  }

  for (final prompt in input.preHistoryPrompts) {
    final content = prompt.content.trim();
    if (content.isEmpty) {
      continue;
    }
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: _normalizeRole(prompt.role),
          content: content,
          timestamp: now,
        ),
        sourceKey: 'preset_prompt',
        sourceLabel: prompt.name,
        blocks: [
          RpHubContextBlock(
            title: prompt.name,
            content: content,
          ),
        ],
      ),
    );
  }

  for (final message in input.history) {
    assembly.add(
      RpHubContextAssemblyMessage(
        message: message,
        sourceKey: 'history',
        sourceLabel: 'Chat History',
        blocks: [
          RpHubContextBlock(
            title:
                message.role == 'user' ? 'User History' : 'Assistant History',
            content: message.content,
          ),
        ],
      ),
    );
  }

  final userTopContent = input.userTopWorldInfo.trim();
  if (userTopContent.isNotEmpty) {
    var injected = false;
    for (var i = assembly.length - 1; i >= 0; i--) {
      final item = assembly[i];
      if (item.sourceKey != 'history' || item.message.role != 'user') {
        continue;
      }
      final mergedContent = [
        userTopContent,
        item.message.content.trim(),
      ].where((value) => value.isNotEmpty).join('\n\n');
      assembly[i] = item.copyWith(
        message: item.message.copyWith(content: mergedContent),
        blocks: [
          RpHubContextBlock(
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
        RpHubContextAssemblyMessage(
          message: ChatMessage(
            role: 'system',
            content: userTopContent,
            timestamp: now,
          ),
          sourceKey: 'world_info_user_top',
          sourceLabel: 'World Info User Top',
          blocks: [
            RpHubContextBlock(
              title: 'World Info User Top',
              content: userTopContent,
            ),
          ],
        ),
      );
    }
  }

  final sortedDepthInjections = input.depthInjections.toList(growable: false)
    ..sort((a, b) {
      final depthCmp = a.depth.compareTo(b.depth);
      if (depthCmp != 0) {
        return depthCmp;
      }
      final orderCmp = a.order.compareTo(b.order);
      if (orderCmp != 0) {
        return orderCmp;
      }
      final roleCmp = _roleInjectionPriority(a.role)
          .compareTo(_roleInjectionPriority(b.role));
      if (roleCmp != 0) {
        return roleCmp;
      }
      return a.title.compareTo(b.title);
    });

  for (final injection in sortedDepthInjections) {
    final content = injection.content.trim();
    if (content.isEmpty) {
      continue;
    }

    _insertAssemblyMessageAtDepth(
      assembly,
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: _normalizeRole(injection.role),
          content: content,
          timestamp: now,
        ),
        sourceKey: injection.sourceKey,
        sourceLabel: injection.sourceLabel,
        blocks: [
          RpHubContextBlock(
            title: injection.title,
            content: content,
          ),
        ],
      ),
      depth: injection.depth,
    );
  }

  if (input.isGroupChat &&
      input.generationType != RpHubContextGenerationType.impersonate &&
      input.groupNudgePrompt.trim().isNotEmpty) {
    final content = input.groupNudgePrompt.trim();
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: content,
          timestamp: now,
        ),
        sourceKey: 'group_nudge',
        sourceLabel: 'Group Nudge',
        blocks: [
          RpHubContextBlock(
            title: 'Group Nudge',
            content: content,
          ),
        ],
      ),
    );
  }

  if (input.assistantTopWorldInfo.trim().isNotEmpty) {
    final content =
        '[Instructions for next message]\n${input.assistantTopWorldInfo.trim()}';
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: content,
          timestamp: now,
        ),
        sourceKey: 'world_info_assistant_top',
        sourceLabel: 'World Info Assistant Top',
        blocks: [
          RpHubContextBlock(
            title: 'World Info Assistant Top',
            content: content,
          ),
        ],
      ),
    );
  }

  if (input.generationType == RpHubContextGenerationType.continueMode &&
      input.continuedMessage != null) {
    assembly.add(
      RpHubContextAssemblyMessage(
        message: input.continuedMessage!,
        sourceKey: 'continue_message',
        sourceLabel: 'Continue Message',
        blocks: [
          RpHubContextBlock(
            title: 'Continue Message',
            content: input.continuedMessage!.content,
          ),
        ],
      ),
    );

    if (input.continueNudge.trim().isNotEmpty) {
      final content = input.continueNudge.trim();
      assembly.add(
        RpHubContextAssemblyMessage(
          message: ChatMessage(
            role: 'system',
            content: content,
            timestamp: now,
          ),
          sourceKey: 'continue_nudge',
          sourceLabel: 'Continue Nudge',
          blocks: [
            RpHubContextBlock(
              title: 'Continue Nudge',
              content: content,
            ),
          ],
        ),
      );
    }
  }

  if (input.generationType == RpHubContextGenerationType.impersonate &&
      input.impersonationPrompt.trim().isNotEmpty) {
    final content = input.impersonationPrompt.trim();
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: content,
          timestamp: now,
        ),
        sourceKey: 'impersonation_prompt',
        sourceLabel: 'Impersonation Prompt',
        blocks: [
          RpHubContextBlock(
            title: 'Impersonation Prompt',
            content: content,
          ),
        ],
      ),
    );
  }

  if (input.generationType == RpHubContextGenerationType.quiet &&
      input.quietPrompt.trim().isNotEmpty) {
    final content = input.quietPrompt.trim();
    assembly.add(
      RpHubContextAssemblyMessage(
        message: ChatMessage(
          role: 'system',
          content: content,
          timestamp: now,
        ),
        sourceKey: 'quiet_prompt',
        sourceLabel: 'Quiet Prompt',
        blocks: [
          RpHubContextBlock(
            title: 'Quiet Prompt',
            content: content,
          ),
        ],
      ),
    );
  }

  return RpHubContextBuildResult(assemblyMessages: assembly);
}

void _insertAssemblyMessageAtDepth(
  List<RpHubContextAssemblyMessage> messages,
  RpHubContextAssemblyMessage message, {
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
  final targetConversationIndex = (conversationCount - depth).clamp(
    0,
    conversationCount,
  );

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

int _roleInjectionPriority(String role) {
  switch (_normalizeRole(role)) {
    case 'user':
      return 0;
    case 'assistant':
      return 1;
    default:
      return 2;
  }
}

String _normalizeRole(String role) {
  final value = role.trim().toLowerCase();
  if (value == 'user' || value == 'assistant' || value == 'system') {
    return value;
  }
  if (value == 'ai' || value == 'bot' || value == 'model') {
    return 'assistant';
  }
  if (value == 'human') {
    return 'user';
  }
  return 'system';
}
