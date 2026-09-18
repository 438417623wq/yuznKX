import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final localLlmServiceProvider = Provider((ref) => LocalLlmService());

class LocalLlmService {
  Llama? _llama;
  String? _currentModelPath;
  String? _currentSamplerSignature;

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static List<String> _asStops(dynamic value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item?.toString().trim().isNotEmpty ?? false)
            item.toString().trim(),
      ];
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const <String>[];
  }

  /// Stream response from local model
  Stream<String> streamResponse({
    required String modelPath,
    required String prompt,
    Map<String, dynamic>? parameters,
  }) async* {
    final params = parameters ?? const <String, dynamic>{};

    // 1. Check/Load Model
    if (modelPath != _currentModelPath || _llama == null) {
      _unloadModel();

      if (!File(modelPath).existsSync()) {
        yield "Error: Local model file not found at $modelPath";
        return;
      }

      try {
        final contextParams = ContextParams()
          ..nCtx = _asInt(params['context_size']) ?? 4096
          ..nThreads = _asInt(params['n_threads']) ?? 4
          ..nThreadsBatch = _asInt(params['n_threads']) ?? 4
          ..nBatch = _asInt(params['n_batch']) ?? 512
          // 超长 prompt 时自动裁剪，避免直接抛 "Context limit exceeded"。
          ..autoTrimContext = true;

        if (params['flash_attn'] == true) {
          contextParams.flashAttention = LlamaFlashAttnType.enabled;
        }

        // 采样参数：之前完全没有透传给本地模型，导致预设里的温度 / top_p / 惩罚项全部失效。
        final samplerParams = _buildSamplerParams(params);

        final maxTokens = _asInt(params['max_tokens']);
        if (maxTokens != null && maxTokens > 0) {
          contextParams.nPredict = maxTokens;
        }

        _llama = Llama(
          modelPath,
          contextParams: contextParams,
          samplerParams: samplerParams,
        );
        _currentModelPath = modelPath;
        _currentSamplerSignature = _samplerSignature(params);
      } catch (e) {
        _unloadModel();
        yield "Error initializing local model: $e";
        return;
      }
    } else if (_currentSamplerSignature != _samplerSignature(params)) {
      // 采样参数变了但模型没变：重建 sampler 需要重载上下文，这里直接重载模型。
      _unloadModel();
      yield* streamResponse(
        modelPath: modelPath,
        prompt: prompt,
        parameters: parameters,
      );
      return;
    }

    if (_llama == null) {
      return;
    }

    // 2. Generate
    final stops = _asStops(params['stop']);
    try {
      _llama!.setPrompt(prompt);

      if (stops.isEmpty) {
        yield* _llama!.generateText();
        return;
      }

      yield* _applyStopStrings(_llama!.generateText(), stops);
    } catch (e) {
      yield "Error during generation: $e";
    }
  }

  /// 本地推理的停止序列：逐段累积，命中后截断并结束流。
  Stream<String> _applyStopStrings(
    Stream<String> source,
    List<String> stops,
  ) async* {
    final buffer = StringBuffer();
    var emitted = 0;
    var finished = false;

    await for (final chunk in source) {
      buffer.write(chunk);
      final full = buffer.toString();

      var cutIndex = -1;
      for (final stop in stops) {
        final index = full.indexOf(stop);
        if (index >= 0 && (cutIndex < 0 || index < cutIndex)) {
          cutIndex = index;
        }
      }

      if (cutIndex >= 0) {
        if (cutIndex > emitted) {
          yield full.substring(emitted, cutIndex);
        }
        finished = true;
        break;
      }

      // 只有当缓冲内容不可能再拼出停止序列时，才安全地把内容吐出去。
      final safeLength = _safeEmitLength(full, stops);
      if (safeLength > emitted) {
        yield full.substring(emitted, safeLength);
        emitted = safeLength;
      }
    }

    if (!finished) {
      final full = buffer.toString();
      if (full.length > emitted) {
        yield full.substring(emitted);
      }
    }
  }

  /// 计算可以安全输出的前缀长度（不会被后续 chunk 补成停止序列）。
  int _safeEmitLength(String text, List<String> stops) {
    var keep = 0;
    for (final stop in stops) {
      final maxSuffix = stop.length - 1;
      final limit = maxSuffix < text.length ? maxSuffix : text.length;
      for (var length = limit; length > keep; length--) {
        if (text.endsWith(stop.substring(0, length))) {
          keep = length;
          break;
        }
      }
    }
    return text.length - keep;
  }

  SamplerParams _buildSamplerParams(Map<String, dynamic> params) {
    final sampler = SamplerParams();

    final temperature = _asDouble(params['temperature']);
    if (temperature != null) {
      sampler.temp = temperature.clamp(0.0, 2.0);
    }

    final topP = _asDouble(params['top_p']);
    if (topP != null && topP > 0) {
      sampler.topP = topP.clamp(0.0, 1.0);
    }

    final topK = _asInt(params['top_k']);
    if (topK != null && topK > 0) {
      sampler.topK = topK;
    }

    final repeatPenalty = _asDouble(params['repetition_penalty']);
    if (repeatPenalty != null) {
      sampler.penaltyRepeat = repeatPenalty.clamp(0.5, 2.0);
    }

    final freqPenalty = _asDouble(params['frequency_penalty']);
    if (freqPenalty != null) {
      sampler.penaltyFreq = freqPenalty.clamp(-2.0, 2.0);
    }

    final presPenalty = _asDouble(params['presence_penalty']);
    if (presPenalty != null) {
      sampler.penaltyPresent = presPenalty.clamp(-2.0, 2.0);
    }

    final seed = _asInt(params['seed']);
    if (seed != null && seed > 0) {
      sampler.seed = seed;
    }

    return sampler;
  }

  String _samplerSignature(Map<String, dynamic> params) {
    return [
      params['temperature'],
      params['top_p'],
      params['top_k'],
      params['repetition_penalty'],
      params['frequency_penalty'],
      params['presence_penalty'],
      params['seed'],
      params['max_tokens'],
    ].join('|');
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
    _currentSamplerSignature = null;
  }
}
