import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:ui';
import '../../data/chat_provider.dart';
import '../../data/session_provider.dart';
import '../../data/session_manager.dart'; // Import SessionManager
import '../../data/tts_service.dart';
import '../../data/speech_provider.dart';
import '../widgets/session_list_drawer.dart';
import '../../../settings/presentation/widgets/character_settings_drawer.dart';
import '../widgets/chat_bubble.dart';
import '../../../character/data/character_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    // Initialize SessionManager
    ref.watch(sessionManagerProvider);

    final sessionId = ref.watch(activeSessionIdProvider);
    final activeCharacter = ref.watch(activeCharacterProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    final currentPersona = ref.watch(personaProvider);
    final isTtsPlaying = ref.watch(ttsProvider);

    if (sessionId == null && activeCharacter == null) {
       // If both are null, it's likely initial load or no data. 
       // Show a non-blocking UI to allow accessing settings.
    }

    final messages = sessionId != null ? ref.watch(chatSessionProvider(sessionId)) : [];
    final isLoading = sessionId != null ? ref.watch(chatLoadingProviderFamily(sessionId)) : false;
    
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: themeSettings.backgroundImagePath != null,
      appBar: AppBar(
        backgroundColor: themeSettings.backgroundImagePath != null ? Colors.black.withOpacity(0.5) : null,
        elevation: themeSettings.backgroundImagePath != null ? 0 : 4,
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: (activeCharacter?.avatarPath != null && activeCharacter!.avatarPath.isNotEmpty)
                  ? FileImage(File(activeCharacter.avatarPath)) as ImageProvider
                  : const NetworkImage('https://via.placeholder.com/150'),
              radius: 16,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                activeCharacter?.name ?? "未选择角色",
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (isTtsPlaying)
             IconButton(
               icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
               onPressed: () {
                 ref.read(ttsProvider.notifier).stop();
               },
               tooltip: '停止朗读',
             ),
          IconButton(
            icon: const Icon(Icons.token),
            onPressed: () {},
            tooltip: 'Token 统计',
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
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // In reverse mode, index 0 is at the bottom.
                      // We want to show the latest message (end of list) at the bottom.
                      final realIndex = messages.length - 1 - index;
                      final msg = messages[realIndex];
                      
                      return ChatBubble(
                        content: msg.content,
                        isUser: msg.role == 'user',
                        name: msg.role == 'user' ? (currentPersona?.name ?? 'User') : (activeCharacter?.name ?? '助手'),
                        avatarPath: msg.role == 'user' ? (currentPersona?.avatarPath) : activeCharacter?.avatarPath,
                        swipeIndex: msg.currentIndex,
                        swipeCount: msg.swipes.length,
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
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(),
                  ),
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

    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF1a1b26),
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
                  _textController.text = "*actions*"; 
                }),
                _buildQuickAction(Icons.comment, '旁白', () {
                  // Pre-fill input for impersonation
                  _textController.text = "System: "; 
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
