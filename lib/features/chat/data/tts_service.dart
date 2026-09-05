import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TtsNotifier extends StateNotifier<bool> {
  final FlutterTts flutterTts = FlutterTts();

  TtsNotifier() : super(false) {
    _init();
  }

  void _init() async {
    // await flutterTts.setLanguage("zh-CN"); // Default to Chinese
    // await flutterTts.setLanguage("en-US"); 
    
    await flutterTts.awaitSpeakCompletion(true);

    flutterTts.setStartHandler(() {
      state = true;
    });

    flutterTts.setCompletionHandler(() {
      state = false;
    });

    flutterTts.setCancelHandler(() {
      state = false;
    });

    flutterTts.setErrorHandler((msg) {
      state = false;
      print("TTS Error: $msg");
    });
  }

  Future<void> speak(String text) async {
    if (state) {
      await stop();
    }
    
    if (text.isEmpty) return;
    
    // Clean markdown?
    // Usually TTS reads markdown poorly.
    // Simple strip:
    String cleanText = text.replaceAll(RegExp(r'\*.*?\*'), ''); // Remove actions between asterisks
    cleanText = cleanText.replaceAll(RegExp(r'```.*?```', dotAll: true), 'Code Block'); // Remove code blocks
    // Remove other markdown symbols
    cleanText = cleanText.replaceAll(RegExp(r'[#*_~`>]'), '');
    
    if (cleanText.trim().isEmpty) return;

    await flutterTts.speak(cleanText);
  }

  Future<void> stop() async {
    await flutterTts.stop();
    state = false;
  }
}

final ttsProvider = StateNotifierProvider<TtsNotifier, bool>((ref) => TtsNotifier());
