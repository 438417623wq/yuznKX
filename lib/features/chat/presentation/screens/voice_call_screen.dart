import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:silly_tavern_flutter/features/chat/data/chat_provider.dart';
import 'package:silly_tavern_flutter/features/chat/data/session_provider.dart';
import 'package:silly_tavern_flutter/features/chat/data/speech_provider.dart';
import 'package:silly_tavern_flutter/features/chat/data/tts_service.dart';
import 'package:silly_tavern_flutter/features/character/data/character_provider.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  String _statusText = "Initializing...";
  String _userTranscript = "";
  bool _isCallActive = true;
  bool _isProcessing = false;
  
  // For pulsing animation
  bool _isAiSpeaking = false;

  @override
  void initState() {
    super.initState();
    // Delay start to allow build to finish
    Future.delayed(Duration.zero, _startCallLoop);
  }

  @override
  void dispose() {
    _isCallActive = false;
    // Stop any ongoing speech or listening
    // We can't await here, so we fire and forget
    ref.read(ttsProvider.notifier).stop();
    ref.read(speechProvider).stopListening();
    super.dispose();
  }

  Future<void> _startCallLoop() async {
    final speechService = ref.read(speechProvider);
    final initSuccess = await speechService.init();

    if (!initSuccess) {
      if (mounted) setState(() => _statusText = "Microphone init failed");
      return;
    }

    if (mounted) setState(() => _statusText = "Listening...");

    while (mounted && _isCallActive) {
      try {
        // 1. Listen for user input
        if (mounted) setState(() {
           _statusText = "Listening...";
           _userTranscript = "";
           _isAiSpeaking = false;
        });

        final userText = await _listenOneShot();
        
        if (!mounted || !_isCallActive) break;

        if (userText.trim().isEmpty) {
          // No speech detected, maybe loop again or wait?
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        // 2. Send to Chat & Process
        if (mounted) setState(() {
          _statusText = "Thinking...";
          _userTranscript = userText;
          _isProcessing = true;
        });

        final sessionId = ref.read(activeSessionIdProvider);
        if (sessionId == null) {
          if (mounted) setState(() => _statusText = "No active session");
          break;
        }

        await ref.read(chatSessionProvider(sessionId).notifier).sendMessage(userText);

        if (!mounted || !_isCallActive) break;

        // 3. Speak AI Response
        if (mounted) setState(() {
          _statusText = "Speaking...";
          _isProcessing = false;
          _isAiSpeaking = true;
        });

        final messages = ref.read(chatSessionProvider(sessionId));
        if (messages.isNotEmpty) {
          final lastMsg = messages.last;
          if (lastMsg.role != 'user') { // Ensure it's not the user's message
             await _speakAndWait(lastMsg.content);
          }
        }

      } catch (e) {
        print("Voice loop error: $e");
        if (mounted) setState(() => _statusText = "Error: $e");
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<String> _listenOneShot() async {
    final completer = Completer<String>();
    final speechService = ref.read(speechProvider);
    String partialResult = "";
    bool isCompleted = false;

    Timer? silenceTimer;

    void complete(String result) {
      if (isCompleted) return;
      isCompleted = true;
      silenceTimer?.cancel();
      speechService.stopListening();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    // Watch for "not listening" state to detect unexpected stops
    // Note: We use read to get the notifier, but we need to listen to changes.
    // In a StatefulWidget, we can't easily add a listener dynamically that cleans up 
    // without using a wrapper or managing the subscription manually.
    // Simpler approach: check isListening periodically or trust the callback/timer.
    
    // Actually, speech_to_text's onStatus callback in SpeechService updates isListeningProvider.
    // We can just rely on the timer for now, as it covers the most common case (user stops speaking).
    // If the system stops listening (e.g. timeout), onStatus -> notListening.
    // We can poll isListeningProvider in a loop? No, that's ugly.
    
    // Let's stick to the timer + safety timeout.

    try {
      await speechService.startListening((text) {
        if (!mounted) return;
        setState(() => _userTranscript = text);
        partialResult = text;
        
        silenceTimer?.cancel();
        silenceTimer = Timer(const Duration(milliseconds: 1500), () {
          complete(partialResult);
        });
      });
    } catch (e) {
      print("Listen error: $e");
      complete("");
    }

    // Safety timeout (10 seconds of no speech start, or 30s total)
    Future.delayed(const Duration(seconds: 30), () {
      if (!isCompleted && mounted) {
        complete(partialResult);
      }
    });

    return completer.future;
  }

  Future<void> _speakAndWait(String text) async {
    final tts = ref.read(ttsProvider.notifier);
    await tts.speak(text);
    
    // Wait while TTS is active
    // TtsNotifier updates state to true on start, false on complete.
    // We need to poll or wait for state change.
    
    // Simple polling
    while (mounted && ref.read(ttsProvider)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = ref.watch(activeCharacterProvider);
    final avatarPath = character?.avatarPath;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          // Background Avatar (Blurred)
          if (avatarPath != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.3,
                child: Image.file(
                  File(avatarPath), // Assuming File import needed
                  fit: BoxFit.cover,
                ),
              ),
            ),
          
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text(
                        character?.name ?? "Unknown",
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 48), // Spacer
                    ],
                  ),
                ),

                const Spacer(),

                // Avatar Circle
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 4),
                      image: avatarPath != null 
                        ? DecorationImage(image: FileImage(File(avatarPath)), fit: BoxFit.cover)
                        : null,
                    ),
                  ).animate(
                    target: _isAiSpeaking ? 1 : 0,
                    onPlay: (controller) => controller.repeat(reverse: true),
                  ).scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.1, 1.1),
                    duration: 600.ms,
                    curve: Curves.easeInOut,
                  ).boxShadow(
                    begin: BoxShadow(color: Colors.blue.withOpacity(0), blurRadius: 0, spreadRadius: 0),
                    end: BoxShadow(color: Colors.blue.withOpacity(0.6), blurRadius: 30, spreadRadius: 10),
                  ),
                ),

                const SizedBox(height: 40),

                // Status & Transcript
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    children: [
                      Text(
                        _statusText,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _userTranscript,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Controls
                Padding(
                  padding: const EdgeInsets.only(bottom: 48.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Mute Button (Placeholder logic)
                      IconButton(
                        icon: Icon(Icons.mic_off, color: Colors.white.withOpacity(0.5), size: 32),
                        onPressed: () {
                          // TODO: Implement mute
                        },
                      ),
                      const SizedBox(width: 40),
                      
                      // End Call Button
                      FloatingActionButton(
                        backgroundColor: Colors.red,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.call_end, size: 32),
                      ),
                      
                      const SizedBox(width: 40),
                      
                      // Manual Send / Skip
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 32),
                        onPressed: () {
                          // Force send current transcript if stuck?
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
