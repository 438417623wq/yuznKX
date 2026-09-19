import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart'; // Import flutter_animate
import 'dart:io';
import 'dart:ui';
import '../../data/chat_provider.dart';
import '../../data/session_provider.dart';
import '../../data/session_manager.dart'; // Import SessionManager
import '../../data/tts_service.dart';
import '../../data/speech_provider.dart';
import '../../domain/models/session.dart'; // Import Session
import '../widgets/session_list_drawer.dart';
import '../widgets/session_history_sheet.dart';
import '../../../settings/presentation/widgets/character_settings_drawer.dart';
import '../widgets/chat_bubble.dart';
import 'voice_call_screen.dart';
import 'group_manager_screen.dart'; // Import GroupManagerScreen
import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart'; // Import Character
import '../../../settings/data/theme_provider.dart';
import '../../../user/data/persona_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId != null) {
      ref.read(chatSessionProvider(sessionId).notifier).sendMessage(text);
      _textController.clear();
    }
  }

  void _sendQuietPrompt() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _textController.text = '旁白：';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
      return;
    }

    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId != null) {
      ref.read(chatSessionProvider(sessionId).notifier).generateQuietPrompt(text);
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize SessionManager
    ref.watch(sessionManagerProvider);

    // 世界书 Token 预算溢出提示（仅在激活设置里打开「溢出警报」时触发）。
    ref.listen<String?>(worldInfoOverflowNoticeProvider, (previous, next) {
      if (next == null || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next),
          duration: const Duration(seconds: 5),
        ),
      );
      ref.read(worldInfoOverflowNoticeProvider.notifier).state = null;
    });

    final sessionId = ref.watch(activeSessionIdProvider);
    final activeCharacter = ref.watch(activeCharacterProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    final currentPersona = ref.watch(personaProvider);
    final isTtsPlaying = ref.watch(ttsProvider);
    final characters = ref.watch(characterListProvider);
    final sessions = ref.watch(sessionProvider);

    Session? activeSession;
    if (sessionId != null) {
      try {
        activeSession = sessions.firstWhere((s) => s.id == sessionId);
      } catch (_) {}
    }

    // 当前对话名：AppBar 副标题展示用，同时用于判断是否显示会话入口。
    final activeSessionName = activeSession?.name ?? '';

    if (sessionId == null && activeCharacter == null) {
       // If both are null, it's likely initial load or no data. 
       // Show a non-blocking UI to allow accessing settings.
    }

    final messages = sessionId != null ? ref.watch(chatSessionProvider(sessionId)) : [];
    final isLoading = sessionId != null ? ref.watch(chatLoadingProviderFamily(sessionId)) : false;
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: themeSettings.chatBackgroundColor,
      extendBodyBehindAppBar: themeSettings.backgroundImagePath != null,
      appBar: AppBar(
        backgroundColor: themeSettings.backgroundImagePath != null 
            ? Colors.black.withOpacity(0.5) 
            : themeSettings.uiBackgroundColor,
        elevation: themeSettings.backgroundImagePath != null ? 0 : 4,
        title: InkWell(
          onTap: activeCharacter == null
              ? null
              : () => showSessionHistorySheet(context),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              if (activeSession?.isGroup == true)
                const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: Icon(Icons.groups, size: 28),
                )
              else
                CircleAvatar(
                  backgroundImage: (activeCharacter?.avatarPath != null &&
                          activeCharacter!.avatarPath.isNotEmpty)
                      ? FileImage(File(activeCharacter.avatarPath))
                          as ImageProvider
                      : const NetworkImage('https://via.placeholder.com/150'),
                  radius: 16,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeCharacter?.name ?? "未选择角色",
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 副标题显示当前对话名 —— 同一角色的多条对话靠它区分，
                    // 也是「点这里切换对话」的视觉提示。
                    if (activeSessionName.isNotEmpty)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              activeSessionName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.expand_more,
                            size: 13,
                            color: Colors.white60,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (activeSession?.isGroup == true)
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: '管理群聊',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => GroupManagerScreen(session: activeSession)));
              },
            ),
          if (isTtsPlaying)
             IconButton(
               icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
               onPressed: () {
                 ref.read(ttsProvider.notifier).stop();
               },
               tooltip: '停止朗读',
             ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
               Navigator.of(context).push(
                 MaterialPageRoute(builder: (context) => const VoiceCallScreen()),
               );
            },
            tooltip: '语音通话',
          ),
          Consumer(
            builder: (context, ref, child) {
              final isStream = ref.watch(isStreamEnabledProvider);
              return IconButton(
                icon: Icon(isStream ? Icons.bolt : Icons.hourglass_empty),
                color: isStream ? Colors.yellowAccent : Colors.white70,
                onPressed: () {
                  ref.read(isStreamEnabledProvider.notifier).state = !isStream;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isStream ? '已切换至: 非流式模式' : '已切换至: 流式模式 (Streaming)')),
                  );
                },
                tooltip: isStream ? '流式生成 (开启)' : '流式生成 (关闭)',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: '更多设置',
          ),
        ],
      ),
      drawer: const SessionListDrawer(),
      endDrawer: const CharacterSettingsDrawer(),
      body: Stack(
        children: [
          // Background Image Layer
          if (themeSettings.backgroundImagePath != null)
            Positioned.fill(
              child: Image.file(
                File(themeSettings.backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          
          // Blur and Dim Layer
          if (themeSettings.backgroundImagePath != null)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: themeSettings.backgroundBlur,
                  sigmaY: themeSettings.backgroundBlur,
                ),
                child: Container(
                  color: Colors.black.withOpacity(themeSettings.backgroundOpacity),
                ),
              ),
            ),

          // Dynamic Style Layer (Sentiment / Expression)
          Consumer(
            builder: (context, ref, _) {
               final styles = ref.watch(activeRenderStylesProvider);
               final expression = styles['expression'];
               
               if (expression == null) return const SizedBox.shrink();
               
               Color? tintColor;
               IconData? feedbackIcon;
               
               switch (expression) {
                 case 'anger': 
                   tintColor = Colors.red.withOpacity(0.2);
                   feedbackIcon = Icons.local_fire_department;
                   break;
                 case 'sadness': 
                   tintColor = Colors.blue.withOpacity(0.2);
                   feedbackIcon = Icons.water_drop;
                   break;
                 case 'joy': 
                   tintColor = Colors.yellow.withOpacity(0.15);
                   feedbackIcon = Icons.sentiment_satisfied_alt;
                   break;
                 case 'fear': 
                   tintColor = Colors.purple.withOpacity(0.2);
                   feedbackIcon = Icons.visibility;
                   break;
                 case 'shyness': 
                   tintColor = Colors.pink.withOpacity(0.15);
                   feedbackIcon = Icons.favorite;
                   break;
                 case 'surprise': 
                   tintColor = Colors.orange.withOpacity(0.15);
                   feedbackIcon = Icons.bolt;
                   break;
               }
               
               if (tintColor == null) return const SizedBox.shrink();
               
               return Positioned.fill(
                 child: IgnorePointer( // Don't block interactions
                   child: AnimatedContainer(
                     duration: const Duration(milliseconds: 800),
                     decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.5,
                          colors: [
                            Colors.transparent,
                            tintColor,
                          ],
                          stops: const [0.5, 1.0],
                        ),
                     ),
                     child: feedbackIcon != null ? Stack(
                        children: [
                           Positioned(
                             bottom: 20,
                             right: 20,
                             child: Icon(feedbackIcon, size: 80, color: tintColor.withOpacity(0.5))
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scale(begin: const Offset(1,1), end: const Offset(1.1, 1.1), duration: 2.seconds)
                                .fade(begin: 0.3, end: 0.6),
                           )
                        ],
                     ) : null,
                   ),
                 ),
               );
            },
          ),

          // Chat Content
          if (sessionId == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    '请选择一个角色以开始聊天',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _scaffoldKey.currentState?.openEndDrawer();
                    },
                    icon: const Icon(Icons.people),
                    label: const Text('打开角色列表'),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                // Spacer for AppBar if extending body
                if (themeSettings.backgroundImagePath != null)
                   SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    reverse: true, // List starts from bottom
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // In reverse mode, index 0 is at the bottom.
                      // We want to show the latest message (end of list) at the bottom.
                      final realIndex = messages.length - 1 - index;
                      final msg = messages[realIndex];
                      
                      Character? msgCharacter;
                      if (msg.role == 'assistant' && msg.metadata != null && msg.metadata!['characterId'] != null) {
                         try {
                           msgCharacter = characters.firstWhere((c) => c.id == msg.metadata!['characterId']);
                         } catch (_) {}
                      }

                      final displayAiName = msgCharacter?.name ?? activeCharacter?.name ?? '助手';
                      final displayAiAvatar = msgCharacter?.avatarPath ?? activeCharacter?.avatarPath;
                      final isLastMessage = realIndex == messages.length - 1;

                      return ChatBubble(
                        content: msg.content,
                        isUser: msg.role == 'user',
                        name: msg.role == 'user' ? (currentPersona?.name ?? 'User') : displayAiName,
                        avatarPath: msg.role == 'user' ? (currentPersona?.avatarPath) : displayAiAvatar,
                        swipeIndex: msg.currentIndex,
                        swipeCount: msg.swipes.length,
                        metadata: msg.metadata, // Pass metadata
                        isGenerating: isLastMessage && ref.watch(isGeneratingProviderFamily(sessionId)),
                        // 前端卡挂载点每轮都会出现在消息里，但只有最新一条助手
                        // 消息才真正渲染面板 —— 否则 50 轮对话就是 50 个活
                        // WebView，安卓上直接吃光内存。
                        isLatestAssistant:
                            isLastMessage && msg.role == 'assistant',
                        onSwipe: (newIndex) {
                          ref.read(chatSessionProvider(sessionId).notifier).swipeMessage(realIndex, newIndex);
                        },
                        onRegenerate: () {
                          if (realIndex == messages.length - 1) {
                            ref.read(chatSessionProvider(sessionId).notifier).regenerateLast();
                          } else {
                            ref.read(chatSessionProvider(sessionId).notifier).regenerateMessage(realIndex);
                          }
                        },
                        onEdit: (newContent) {
                          ref.read(chatSessionProvider(sessionId).notifier).editMessage(realIndex, newContent);
                        },
                        onTts: () {
                          ref.read(ttsProvider.notifier).speak(msg.content);
                        },
                      );
                    },
                  ),
                ),
                // Removed LinearProgressIndicator to use bubble typing indicator
                _buildInputArea(sessionId),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea(String sessionId) {
    final isListening = ref.watch(isListeningProvider);
    final isGenerating = ref.watch(isGeneratingProviderFamily(sessionId));
    final themeSettings = ref.watch(themeSettingsProvider);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: themeSettings.uiBackgroundColor,
        border: Border(
          top: BorderSide(color: themeSettings.uiBorderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Quick Actions
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (isGenerating)
                   ElevatedButton.icon(
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.redAccent,
                       foregroundColor: Colors.white,
                     ),
                     icon: const Icon(Icons.stop),
                     label: const Text('停止生成'),
                     onPressed: () {
                       ref.read(chatSessionProvider(sessionId).notifier).stopGeneration();
                     },
                   ),

                _buildQuickAction(Icons.play_arrow, '继续', () {
                  ref.read(chatSessionProvider(sessionId).notifier).continueGeneration();
                }),
                _buildQuickAction(Icons.refresh, '重试', () {
                  ref.read(chatSessionProvider(sessionId).notifier).regenerateLast();
                }),
                _buildQuickAction(Icons.person, '扮演', () {
                  // Pre-fill input with user name or specific instruction
                  ref.read(chatSessionProvider(sessionId).notifier).generateImpersonationReply();
                }),
                _buildQuickAction(Icons.comment, '旁白', () {
                  // Pre-fill input for impersonation
                  _sendQuietPrompt();
                }),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.add, color: Colors.white70), onPressed: () {}),
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: isListening ? '正在聆听...' : '发送消息...',
                    hintStyle: TextStyle(color: isListening ? Colors.greenAccent : Colors.white38),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  color: isListening ? Colors.redAccent : Colors.white70,
                ),
                onPressed: () async {
                  final speechService = ref.read(speechProvider);
                  if (isListening) {
                    await speechService.stopListening();
                  } else {
                    final currentText = _textController.text;
                    await speechService.startListening((text) {
                      if (currentText.isEmpty) {
                         _textController.text = text;
                      } else {
                         _textController.text = "$currentText $text";
                      }
                      _textController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _textController.text.length)
                      );
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.indigoAccent),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
