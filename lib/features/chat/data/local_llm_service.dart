import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final localLlmServiceProvider = Provider((ref) => LocalLlmService());

class LocalLlmService {
  Llama? _llama;
  String? _currentModelPath;
  
  /// Stream response from local model
  Stream<String> streamResponse({
    required String modelPath,
    required String prompt,
    Map<String, dynamic>? parameters,
  }) async* {
    // 1. Check/Load Model
    if (modelPath != _currentModelPath || _llama == null) {
      _unloadModel();
      
      if (!File(modelPath).existsSync()) {
        yield "Error: Local model file not found at $modelPath";
        return;
      }

      try {
        final contextParams = ContextParams();
        
        // Load optimization settings
        if (parameters != null) {
          if (parameters.containsKey('context_size')) {
            contextParams.nCtx = (parameters['context_size'] as num).toInt();
          } else {
            contextParams.nCtx = 2048;
          }
          
          if (parameters.containsKey('n_threads')) {
            contextParams.nThreads = (parameters['n_threads'] as num).toInt();
            contextParams.nThreadsBatch = (parameters['n_threads'] as num).toInt();
          } else {
            contextParams.nThreads = 4;
            contextParams.nThreadsBatch = 4;
          }
          
          if (parameters.containsKey('n_batch')) {
            contextParams.nBatch = (parameters['n_batch'] as num).toInt();
          }

          if (parameters.containsKey('flash_attn') && parameters['flash_attn'] == true) {
            contextParams.flashAttention = LlamaFlashAttnType.enabled;
          }
        } else {
          contextParams.nCtx = 2048;
          contextParams.nThreads = 4;
        }
        
        // Initialize Llama
        _llama = Llama(
          modelPath,
          contextParams: contextParams,
        );
        _currentModelPath = modelPath;
      } catch (e) {
        _unloadModel();
        yield "Error initializing local model: $e";
        return;
      }
    }

    if (_llama == null) return;

    // 2. Generate
    try {
      _llama!.setPrompt(prompt);
      
      // Use the built-in generateText stream
      yield* _llama!.generateText();
      
    } catch (e) {
      yield "Error during generation: $e";
    }
  }

  void stop() {
    // Llama-cpp-dart doesn't have an explicit interrupt, so we might have to unload
    _unloadModel();
  }

  void _unloadModel() {
    try {
      _llama?.dispose();
    } catch (e) {
      // Ignore unload errors
    }
    _llama = null;
    _currentModelPath = null;
  }
}
