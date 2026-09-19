import 'package:uuid/uuid.dart';

import '../../presets/domain/models/preset.dart';
import '../domain/models/preset_brief.dart';
import '../domain/models/preset_project.dart';
import '../domain/models/preset_slot.dart';
import '../domain/preset_slot_catalog.dart';

/// 打包结果。
class PackedPreset {
  const PackedPreset({
    required this.preset,
    required this.missingIdentifiers,
  });

  final Preset preset;

  /// 打包时发现缺失、被自动补成「禁用」的引擎 identifier。
  ///
  /// 正常情况下应该是空的 —— 非空说明上游（模板 / 反向导入）漏了槽位。
  final List<String> missingIdentifiers;

  bool get isClean => missingIdentifiers.isEmpty;
}

/// 把工坊的槽位列表打包成引擎能用的 [Preset]。
///
/// ⛔ **本文件最重要的职责：保证 21 个引擎 identifier 一个不漏。**
///
/// 原因：预设存进 Hive 后再读回来，会走
/// `Preset.fromJson` → `parseWithReport` → `_mergeWithDefaultPromptManagerPrompts`，
/// 那里是「**缺哪个 identifier 就补哪个，且默认 `enabled: true`**」。
/// 漏掉的那几个会被追加到列表末尾 ——
/// 既稀释底部注意力，又让最后一条消息不再是 assistant，**prefill 直接失效**。
///
/// 所以这里做两道防线：
/// 1. 按 `kEngineSlotSpecs` 逐项核对，缺的补成禁用；
/// 2. [verifyRoundTrip] 提供「存盘读回后顺序与开关是否一致」的自检。
class PresetPackager {
  const PresetPackager._();

  /// 打包成 [Preset]。
  ///
  /// [presetId] 为空时新建（导出新预设）；传入已有 id 时覆盖（重复导出幂等）。
  static PackedPreset build({
    required PresetProject project,
    String? presetId,
    String? name,
  }) {
    final ordered = _normalize(project.slots);

    final prompts = <PresetPrompt>[];
    for (var i = 0; i < ordered.length; i++) {
      final slot = ordered[i];
      prompts.add(
        PresetPrompt(
          identifier: slot.identifier,
          name: slot.label.isEmpty ? slot.identifier : slot.label,
          role: _normalizeRole(slot.role),
          // marker 槽位的内容由引擎填充，但预设自己的文本会被前置 —— 所以照传。
          content: slot.content,
          injectionPosition: Preset.relativeInjectionPosition,
          injectionDepth: 0,
          injectionOrder: 100 + i,
          enabled: slot.enabled,
          systemPrompt: slot.systemPrompt,
          marker: slot.marker,
          position: slot.position,
          legacyPositioning: slot.legacyPositioning,
        ),
      );
    }

    final preset = Preset(
      id: presetId ?? const Uuid().v4(),
      name: name ?? project.name,
      prompts: prompts,
    );

    return PackedPreset(
      preset: preset,
      missingIdentifiers: _missingEngineIdentifiers(ordered),
    );
  }

  /// 去重（保留第一条）+ 末尾补齐缺失的引擎槽位（禁用）。**不重排。**
  ///
  /// ⛔ 曾经这里把「禁用的槽位」统一挪到列表末尾，图个清爽。那是错的：
  /// - 禁用槽位虽然会被 `if (!prompt.enabled) continue;` 跳过、不影响消息顺序，
  ///   但**位置是用户排的**。挪走之后「导出 → 反向导入」不再幂等 ——
  ///   用户第二次打开工坊看到的是另一套顺序；而某个禁用槽位一旦被重新启用，
  ///   它就落在了一个自己从没选过的位置上。
  /// - 非引擎槽位（`ykx*`）的排序权重相同，`List.sort` 又不保证稳定，
  ///   于是**同一个项目导出两次可能得到顺序不同的文件**，diff 会无故飘动。
  ///
  /// 所以这里只做两件有明确收益的事：去重、补缺。
  static List<PresetSlot> _normalize(List<PresetSlot> slots) {
    final result = <PresetSlot>[];
    final seen = <String>{};

    for (final slot in slots) {
      final identifier = slot.identifier.trim();
      if (identifier.isEmpty) {
        continue;
      }
      // 同 identifier 只保留第一条（重复的 chatHistory 会让历史插入多次）。
      if (!seen.add(identifier)) {
        continue;
      }
      // identifier 是引擎匹配槽位的唯一凭据，顺手去掉首尾空白，
      // 否则 `main ` 和 `main` 会被当成两个槽位。
      result.add(
        identifier == slot.identifier ? slot : slot.copyWith(identifier: identifier),
      );
    }

    // 补齐缺失的引擎槽位（禁用）。
    for (final spec in kEngineSlotSpecs) {
      if (seen.contains(spec.identifier)) {
        continue;
      }
      result.add(spec.toSlot(enabled: false));
    }

    return result;
  }

  /// 找出缺失的引擎 identifier（用于自检与诊断）。
  static List<String> _missingEngineIdentifiers(List<PresetSlot> ordered) {
    final present = ordered.map((slot) => slot.identifier).toSet();
    return kEngineSlotIdentifiers
        .where((identifier) => !present.contains(identifier))
        .toList(growable: false);
  }

  /// 打包结果的自检：走一遍「存盘 → 读回」，检查顺序与开关是否原样保留。
  ///
  /// 这是对 `_mergeWithDefaultPromptManagerPrompts` 那个坑的**回归测试钩子** ——
  /// 单元测试与诊断都用它。
  static PresetRoundTripReport verifyRoundTrip(Preset preset) {
    // 模拟 preset_provider 的读回路径。
    final reloaded = Preset.fromJson(preset.toJson());

    final before = preset.prompts
        .map((prompt) => '${prompt.identifier}|${prompt.enabled}|${prompt.role}')
        .toList(growable: false);
    final after = reloaded.prompts
        .map((prompt) => '${prompt.identifier}|${prompt.enabled}|${prompt.role}')
        .toList(growable: false);

    final added = <String>[];
    final beforeIds = preset.prompts.map((p) => p.identifier).toSet();
    for (final prompt in reloaded.prompts) {
      if (!beforeIds.contains(prompt.identifier)) {
        added.add(prompt.identifier);
      }
    }

    // 顺序比对：只比「启用」的那部分 —— 禁用槽位排哪不影响组装。
    final beforeEnabled = preset.prompts
        .where((prompt) => prompt.enabled)
        .map((prompt) => prompt.identifier)
        .toList(growable: false);
    final afterEnabled = reloaded.prompts
        .where((prompt) => prompt.enabled)
        .map((prompt) => prompt.identifier)
        .toList(growable: false);

    var orderPreserved = beforeEnabled.length == afterEnabled.length;
    if (orderPreserved) {
      for (var i = 0; i < beforeEnabled.length; i++) {
        if (beforeEnabled[i] != afterEnabled[i]) {
          orderPreserved = false;
          break;
        }
      }
    }

    return PresetRoundTripReport(
      addedIdentifiers: added,
      orderPreserved: orderPreserved,
      enabledBefore: beforeEnabled,
      enabledAfter: afterEnabled,
      totalBefore: before.length,
      totalAfter: after.length,
    );
  }

  /// 反向：把已有预设拆成工坊槽位。
  ///
  /// 用于「从已有预设导入成工坊项目」。
  /// 引擎不认识的 identifier 也保留（不丢内容）。
  static List<PresetSlot> toSlots(Preset preset) {
    final slots = <PresetSlot>[];
    for (final prompt in preset.prompts) {
      final spec = slotSpecOf(prompt.identifier);
      slots.add(
        PresetSlot(
          identifier: prompt.identifier,
          label: spec?.label ??
              (prompt.name.trim().isEmpty ? prompt.identifier : prompt.name),
          role: _normalizeRole(prompt.role),
          content: prompt.content,
          enabled: prompt.enabled,
          marker: prompt.marker,
          systemPrompt: prompt.systemPrompt,
          position: prompt.position,
          legacyPositioning: prompt.legacyPositioning,
          userOwned: spec?.userOwned ?? false,
          locked: spec?.locked ?? false,
          intent: spec?.intent ?? '',
        ),
      );
    }
    return slots;
  }

  /// 推断导入的预设属于哪种结构（末条是否 assistant → 伪造多轮）。
  static PresetStructureKind inferStructureKind(List<PresetSlot> slots) {
    final enabled = slots.where((slot) => slot.enabled).toList(growable: false);
    if (enabled.isEmpty) {
      return PresetStructureKind.singleBlock;
    }
    final hasAssistant = enabled.any((slot) => slot.role == 'assistant');
    final hasUser = enabled.any((slot) => slot.role == 'user');
    if (hasAssistant && hasUser && enabled.last.role == 'assistant') {
      return PresetStructureKind.multiTurn;
    }
    return PresetStructureKind.singleBlock;
  }

  /// 预设参数的默认值（按渠道给一点差异，其余用引擎默认）。
  static Preset applyBriefParameters(Preset preset, PresetBrief brief) {
    // 本地模型上下文小、容易跑飞，温度和重复惩罚收一点。
    final isLocal = brief.channel == TargetChannel.local;
    return preset.copyWith(
      temperature: isLocal ? 0.8 : Preset.defaultTemperature,
      repetitionPenalty:
          isLocal ? 1.1 : Preset.defaultRepetitionPenalty,
    );
  }

  static String _normalizeRole(String role) {
    final value = role.trim().toLowerCase();
    if (value == 'user' || value == 'assistant' || value == 'system') {
      return value;
    }
    return 'system';
  }
}

/// 存盘读回的自检报告。
class PresetRoundTripReport {
  const PresetRoundTripReport({
    required this.addedIdentifiers,
    required this.orderPreserved,
    required this.enabledBefore,
    required this.enabledAfter,
    required this.totalBefore,
    required this.totalAfter,
  });

  /// 读回后多出来的 identifier（应为空；非空 = 打包时漏了槽位）。
  final List<String> addedIdentifiers;

  /// 启用槽位的顺序是否原样保留。
  final bool orderPreserved;

  final List<String> enabledBefore;
  final List<String> enabledAfter;
  final int totalBefore;
  final int totalAfter;

  bool get isHealthy => addedIdentifiers.isEmpty && orderPreserved;

  String describe() {
    if (isHealthy) {
      return '存盘读回后顺序与开关完全一致（${enabledBefore.length} 个启用槽位）';
    }
    final parts = <String>[];
    if (addedIdentifiers.isNotEmpty) {
      parts.add('读回后多出 ${addedIdentifiers.length} 个槽位：'
          '${addedIdentifiers.join("、")}');
    }
    if (!orderPreserved) {
      parts.add('顺序发生变化\n  打包时：${enabledBefore.join(" → ")}\n'
          '  读回后：${enabledAfter.join(" → ")}');
    }
    return parts.join('\n');
  }
}
