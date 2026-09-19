import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api_connection/data/api_connection_provider.dart';
import '../../api_connection/domain/models/api_connection.dart';
import '../../chat/data/chat_provider.dart';
import '../../chat/domain/models/chat_message.dart';
import '../domain/models/preset_diagnosis.dart';
import '../domain/models/preset_project.dart';
import '../domain/models/preset_slot.dart';
import 'preset_prompt_builder.dart';

/// 工坊异常：`message` 直接面向用户，`rawOutput` 用于排查。
///
/// 与 `WorkshopException`（角色工坊）同名同形但各自独立 ——
/// 两边都不依赖对方，复制一份比互相 import 更省事。
class PresetWorkshopException implements Exception {
  PresetWorkshopException(this.message, {this.rawOutput});

  final String message;
  final String? rawOutput;

  @override
  String toString() => message;
}

/// 对话式微调的结果。
class PresetRefineResult {
  const PresetRefineResult({required this.reply, required this.slots});

  /// 模型对自己改了什么的一句话说明。
  final String reply;

  /// identifier → 改后的完整正文。**只含真正改动过的槽位。**
  final Map<String, String> slots;
}

final presetWorkshopServiceProvider =
    Provider<PresetWorkshopService>((ref) => PresetWorkshopService(ref));

/// 预设工坊的 AI 服务层。
///
/// 只做「拼提示词 → 调模型 → 解析 JSON」，不持有任何 UI 状态。
/// 五个阶段的输出都统一成单个 JSON 对象，因此共用同一套解析容错。
class PresetWorkshopService {
  PresetWorkshopService(this._ref);

  final Ref _ref;

  /// 格式失败时最多再让模型重发几次。
  static const int _maxRepairAttempts = 2;

  // 采样温度：写指令要稳，微调要听话，质检要可复现。
  static const double _tempGenerate = 0.75;
  static const double _tempRegenerate = 0.85;
  static const double _tempRefine = 0.6;
  static const double _tempReview = 0.2;
  static const double _tempRepair = 0.5;

  // ============================================================
  // 填充内容
  // ============================================================

  /// 一次生成全部可写槽位。
  ///
  /// 之所以**一次生成全部**而不是逐槽位生成：预设里的各条指令互相引用
  /// （顶部声明里提到的名词，底部指令要用同一个），分开生成会自相矛盾。
  Future<Map<String, String>> generateSlots({
    required PresetProject project,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: PresetPromptBuilder.buildGenerateSlots(project: project),
      temperature: _tempGenerate,
      maxTokens: 8000,
      stageText: '正在写各槽位的提示词…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final result = _readSlotContents(parsed['slots']);
    if (result.isEmpty) {
      throw PresetWorkshopException('模型没有返回任何槽位内容，请重试。');
    }
    return result;
  }

  /// 重写单个槽位。
  Future<String> regenerateSlot({
    required PresetProject project,
    required PresetSlot slot,
    String userHint = '',
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: PresetPromptBuilder.buildRegenerateSlot(
        project: project,
        slot: slot,
        userHint: userHint,
      ),
      temperature: _tempRegenerate,
      maxTokens: 2000,
      stageText: '正在重写「${slot.label}」…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final content = _readContent(parsed);
    if (content == null) {
      throw PresetWorkshopException('模型没有返回内容，请重试。');
    }
    return content;
  }

  // ============================================================
  // 对话式微调
  // ============================================================

  Future<PresetRefineResult> refine({
    required PresetProject project,
    required String instruction,
    String? focusSlotIdentifier,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: PresetPromptBuilder.buildRefine(
        project: project,
        instruction: instruction,
        focusSlotIdentifier: focusSlotIdentifier,
      ),
      temperature: _tempRefine,
      maxTokens: 6000,
      stageText: '正在按你的要求修改…',
      onDelta: onDelta,
      onStage: onStage,
    );

    return PresetRefineResult(
      reply: parsed['reply']?.toString().trim() ?? '',
      slots: _readSlotContents(parsed['slots']),
    );
  }

  // ============================================================
  // AI 复核
  // ============================================================

  Future<List<PresetDiagnosisIssue>> review({
    required PresetProject project,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: PresetPromptBuilder.buildReview(project: project),
      temperature: _tempReview,
      maxTokens: 3000,
      stageText: '正在让 AI 复核语义层…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final raw = parsed['issues'];
    if (raw is! List) {
      // 没问题是合法结果，不是错误。
      return const <PresetDiagnosisIssue>[];
    }

    final issues = <PresetDiagnosisIssue>[];
    var index = 0;
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final title = map['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        continue;
      }
      final slotIdentifier = map['slotIdentifier']?.toString().trim() ?? '';
      issues.add(
        PresetDiagnosisIssue(
          id: 'ai.${index++}',
          title: title,
          detail: map['detail']?.toString().trim() ?? '',
          level: _readLevel(map['level']),
          source: PresetIssueSource.ai,
          slotIdentifier: slotIdentifier.isEmpty ? null : slotIdentifier,
          suggestion: map['suggestion']?.toString().trim() ?? '',
        ),
      );
    }
    return issues;
  }

  // ============================================================
  // 逐条修复
  // ============================================================

  Future<String> repairSlot({
    required PresetProject project,
    required PresetSlot slot,
    required PresetDiagnosisIssue issue,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final parsed = await _run(
      messages: PresetPromptBuilder.buildRepairSlot(
        project: project,
        slot: slot,
        issue: issue,
      ),
      temperature: _tempRepair,
      maxTokens: 3000,
      stageText: '正在修「${slot.label}」…',
      onDelta: onDelta,
      onStage: onStage,
    );

    final content = _readContent(parsed);
    if (content == null) {
      throw PresetWorkshopException('模型没有返回修复后的内容，请重试。');
    }
    return content;
  }

  // ============================================================
  // 调用骨架（与 CardProjectService 一致）
  // ============================================================

  Future<Map<String, dynamic>> _run({
    required List<ChatMessage> messages,
    required double temperature,
    required int maxTokens,
    required String stageText,
    void Function(String delta)? onDelta,
    void Function(String stage)? onStage,
  }) async {
    final connection = _requireConnection();
    var currentMessages = messages;
    String? lastRaw;
    String? lastError;

    for (var attempt = 0; attempt <= _maxRepairAttempts; attempt++) {
      final isRepair = attempt > 0;
      onStage?.call(
        isRepair ? '输出格式有误，正在重试（$attempt/$_maxRepairAttempts）…' : stageText,
      );

      final raw = await _requestText(
        connection: connection,
        messages: currentMessages,
        temperature: temperature,
        maxTokens: maxTokens,
        // 修复重试不推流，避免预览里出现半截的错误输出。
        onDelta: isRepair ? null : onDelta,
      );
      lastRaw = raw;

      try {
        final parsed = _parseJsonObject(raw);
        if (parsed.isEmpty) {
          throw PresetWorkshopException('模型返回了空对象。');
        }
        return parsed;
      } catch (error) {
        lastError = error is PresetWorkshopException
            ? error.message
            : error.toString();
        final repairMessages = List<ChatMessage>.from(messages);
        final note = StringBuffer()
          ..write('\n\n${PresetPromptBuilder.repairNote}')
          ..write('\n失败原因：${_shorten(lastError, 160)}');
        for (var i = repairMessages.length - 1; i >= 0; i--) {
          if (repairMessages[i].role == 'user') {
            repairMessages[i] = repairMessages[i]
                .copyWith(content: '${repairMessages[i].content}$note');
            break;
          }
        }
        currentMessages = repairMessages;
      }
    }

    throw PresetWorkshopException(
      '生成失败：模型连续 ${_maxRepairAttempts + 1} 次都没有返回合法 JSON。'
      '${lastError == null ? '' : '\n最后原因：$lastError'}',
      rawOutput: lastRaw,
    );
  }

  ApiConnection _requireConnection() {
    final connection = _ref.read(activeApiConnectionProvider);
    if (connection == null) {
      throw PresetWorkshopException(
        '还没有可用的 API 连接，请先到「设置 → API 连接」里添加并选中一个。',
      );
    }
    return connection;
  }

  Future<String> _requestText({
    required ApiConnection connection,
    required List<ChatMessage> messages,
    required double temperature,
    required int maxTokens,
    void Function(String delta)? onDelta,
  }) async {
    final service = _ref.read(chatServiceProvider);

    // 工坊是独立的一次性请求：不读聊天记录、不注入记忆与世界书。
    final parameters = <String, dynamic>{
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    final buffer = StringBuffer();
    await for (final event in service.streamMessage(
      connection: connection,
      messages: messages,
      parameters: parameters,
    )) {
      final text = event.text;
      if (text == null || text.isEmpty) {
        continue;
      }
      buffer.write(text);
      onDelta?.call(text);
    }

    final result = buffer.toString();
    if (result.trim().isEmpty) {
      throw PresetWorkshopException('模型没有返回任何内容，请检查 API 连接与模型名是否正确。');
    }
    return result;
  }

  /// 三级容错：去代码围栏 → 截取首尾大括号 → 修掉尾随逗号与裸换行后重试解析。
  Map<String, dynamic> _parseJsonObject(String raw) {
    final candidate = _extractJsonObject(raw);
    if (candidate == null) {
      throw PresetWorkshopException('模型输出里找不到 JSON 对象。');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (firstError) {
      // 模型最常见的两种手滑：对象/数组末尾多一个逗号；长文本里漏写 \n 转义。
      final repaired = _escapeRawNewlinesInStrings(
        candidate.replaceAllMapped(
          RegExp(r',\s*([}\]])'),
          (match) => match.group(1) ?? '',
        ),
      );
      try {
        decoded = jsonDecode(repaired);
      } catch (_) {
        throw PresetWorkshopException(
          '模型输出的 JSON 无法解析：${_shorten(firstError.toString(), 120)}',
        );
      }
    }

    if (decoded is! Map) {
      throw PresetWorkshopException('模型输出的不是一个 JSON 对象。');
    }

    var map = decoded.map((key, value) => MapEntry(key.toString(), value));

    // 有些模型会自作主张套一层 {"data": {...}} / {"result": {...}}。
    for (final wrapper in const <String>['data', 'result', 'preset', 'output']) {
      final inner = map[wrapper];
      if (inner is Map &&
          (inner.containsKey('slots') ||
              inner.containsKey('issues') ||
              inner.containsKey('content') ||
              inner.containsKey('reply'))) {
        map = inner.map((key, value) => MapEntry(key.toString(), value));
        break;
      }
    }
    return map;
  }

  /// 逐字符扫描，把字符串字面量内部的裸换行补成 `\n`。
  ///
  /// 中文模型写长文本时经常忘记转义换行，这是 JSON 解析失败的头号原因。
  String _escapeRawNewlinesInStrings(String input) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (!inString) {
        if (char == '"') {
          inString = true;
        }
        buffer.write(char);
        continue;
      }

      if (escaped) {
        escaped = false;
        buffer.write(char);
        continue;
      }

      if (char == '\\') {
        escaped = true;
        buffer.write(char);
        continue;
      }

      if (char == '"') {
        inString = false;
        buffer.write(char);
        continue;
      }

      if (char == '\n') {
        buffer.write(r'\n');
        continue;
      }

      if (char == '\r') {
        continue;
      }

      if (char == '\t') {
        buffer.write(r'\t');
        continue;
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  String? _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final fenced = RegExp(r'```[a-zA-Z]*\s*([\s\S]*?)```').firstMatch(text);
    if (fenced != null) {
      text = (fenced.group(1) ?? '').trim();
    } else if (text.contains('```')) {
      text = text.replaceAll('```', '').trim();
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return text.substring(start, end + 1);
  }

  // ============================================================
  // 读取容错
  // ============================================================

  /// 读 `{"slots": [...]}` / `{"slots": {...}}` 两种写法。
  ///
  /// 模型有时会写成数组、有时写成对象映射，都接受。
  Map<String, String> _readSlotContents(dynamic value) {
    final result = <String, String>{};

    if (value is List) {
      for (final item in value) {
        if (item is! Map) {
          continue;
        }
        final map = item.map((key, key2) => MapEntry(key.toString(), key2));
        final identifier = map['identifier']?.toString().trim() ?? '';
        final content = map['content']?.toString() ?? '';
        if (identifier.isEmpty || content.trim().isEmpty) {
          continue;
        }
        result[identifier] = content;
      }
      return result;
    }

    if (value is Map) {
      for (final entry in value.entries) {
        final identifier = entry.key.toString().trim();
        final content = entry.value?.toString() ?? '';
        if (identifier.isEmpty || content.trim().isEmpty) {
          continue;
        }
        result[identifier] = content;
      }
    }

    return result;
  }

  /// 读 `{"content": "..."}`，也接受裸字符串。
  String? _readContent(Map<String, dynamic> parsed) {
    final raw = parsed['content'] ?? parsed['text'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw;
    }
    return null;
  }

  PresetIssueLevel _readLevel(dynamic value) {
    final key = value?.toString().trim().toLowerCase() ?? '';
    switch (key) {
      case 'error':
      case '错误':
        return PresetIssueLevel.error;
      case 'warning':
      case 'warn':
      case '警告':
        return PresetIssueLevel.warning;
      default:
        return PresetIssueLevel.info;
    }
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }
}
