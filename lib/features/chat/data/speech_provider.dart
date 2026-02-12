import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

final speechToTextProvider = Provider((ref) => SpeechToText());

final isListeningProvider = StateProvider<bool>((ref) => false);

final speechProvider = Provider((ref) => SpeechService(ref));

class SpeechService {
  final Ref _ref;
  bool _isInitialized = false;

  SpeechService(this._ref);

  Future<bool> init() async {
    if (_isInitialized) return true;
    
    final stt = _ref.read(speechToTextProvider);
    try {
      _isInitialized = await stt.initialize(
        onStatus: (status) {
          if (status == 'listening') {
            _ref.read(isListeningProvider.notifier).state = true;
          } else if (status == 'notListening' || status == 'done') {
            _ref.read(isListeningProvider.notifier).state = false;
          }
        },
        onError: (errorNotification) {
          _ref.read(isListeningProvider.notifier).state = false;
          print('Speech Error: ${errorNotification.errorMsg}');
        },
      );
    } catch (e) {
      print("Speech init error: $e");
      _isInitialized = false;
    }
    return _isInitialized;
  }

  Future<void> startListening(Function(String) onResult) async {
    final stt = _ref.read(speechToTextProvider);
    if (!_isInitialized) {
      final available = await init();
      if (!available) {
        print("Speech recognition not available");
        return;
      }
    }

    if (stt.isListening) {
      await stopListening();
      return; // Toggle behavior handled by UI usually, but good to be safe
    }

    await stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
      },
      localeId: 'zh_CN', // Default to Chinese as requested, or make configurable
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> stopListening() async {
    final stt = _ref.read(speechToTextProvider);
    await stt.stop();
    _ref.read(isListeningProvider.notifier).state = false;
  }
}
