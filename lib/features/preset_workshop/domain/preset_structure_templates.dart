import 'models/preset_brief.dart';
import 'models/preset_project.dart';
import 'models/preset_slot.dart';
import 'preset_slot_catalog.dart';

/// 结构模板：按「扮演需求 + 结构类型」生成槽位骨架。
///
/// **这是思路文档方法论的直接落地** —— 文档的核心是
/// 「先设定 role，然后调整 role 的位置与优先级关系，调好之后这就是你的预设结构，
/// 最后围绕结构编辑提示词」。
///
/// 所以本文件只决定**有哪些槽位、各自什么 role、谁在前谁在后**，
/// 一个字的提示词都不写（那是 `slots` 阶段的事）。
class PresetStructureTemplates {
  const PresetStructureTemplates._();

  /// 两种结构共用的「数据槽位」骨架（这些槽位的内容由引擎填充）。
  ///
  /// 顺序：世界书（前）→ 角色设定 → 性格 → 场景 → 用户人设 → 世界书（后）
  /// → 示例对话 → 记忆。
  static const List<String> _dataSlots = <String>[
    'worldInfoBefore',
    'charDescription',
    'charPersonality',
    'scenario',
    'personaDescription',
    'worldInfoAfter',
    'dialogueExamples',
    'vectorsMemory',
  ];

  /// 单块版：所有内容都走 `system`，兼容性最好。
  static const List<String> _singleBlockOrder = <String>[
    'ykxReset',
    'main',
    ..._dataSlots,
    'ykxHistoryOpen',
    'chatHistory',
    'ykxHistoryClose',
    'jailbreak',
    'nsfw',
  ];

  /// 伪造多轮版：按思路文档的 user / model 交替排布，末尾以 assistant 收尾。
  ///
  /// 关键的三处 role 覆盖（相对单块版）：
  /// - `main` → `user`：文档第一段 user 块（【重置】+【顶部声明】）
  /// - `ykxHistoryOpen` → `user`、`ykxHistoryClose` → `user`：
  ///   历史包裹写在 user 轮里，闭标签之后紧跟同一轮的底部指令
  /// - `jailbreak` → `user`、`nsfw` → `assistant`：
  ///   指令留在 user 轮，末条 assistant 用来做 prefill
  static const List<String> _multiTurnOrder = <String>[
    'ykxReset',
    'main',
    'ykxAssistantDeclare',
    'ykxUserDeclare',
    ..._dataSlots,
    'ykxHistoryOpen',
    'chatHistory',
    'ykxHistoryClose',
    'jailbreak',
    'nsfw',
    'ykxFakeCot',
  ];

  /// 伪造多轮版里的 role 覆盖表。
  static const Map<String, String> _multiTurnRoles = <String, String>{
    'main': 'user',
    'ykxHistoryOpen': 'user',
    'ykxHistoryClose': 'user',
    'jailbreak': 'user',
    'nsfw': 'assistant',
  };

  /// 生成骨架。
  ///
  /// [previous] 非空时按 identifier 把已有内容带过来（切换结构时不会丢内容）。
  static List<PresetSlot> build({
    required PresetStructureKind kind,
    required PresetBrief brief,
    List<PresetSlot> previous = const <PresetSlot>[],
  }) {
    final activeOrder = kind == PresetStructureKind.multiTurn
        ? _multiTurnOrder
        : _singleBlockOrder;

    final existing = <String, PresetSlot>{
      for (final slot in previous) slot.identifier: slot,
    };

    final result = <PresetSlot>[];
    final used = <String>{};

    for (final identifier in activeOrder) {
      used.add(identifier);
      final spec = slotSpecOf(identifier);
      if (spec == null) {
        continue;
      }
      final role = kind == PresetStructureKind.multiTurn
          ? (_multiTurnRoles[identifier] ?? spec.role)
          : spec.role;

      // 结构切换时优先沿用旧槽位的内容与用户自己的开关状态。
      final old = existing[identifier];
      if (old != null) {
        result.add(
          old.copyWith(
            label: spec.label,
            role: role,
            marker: spec.marker,
            systemPrompt: spec.systemPrompt,
            position: spec.position,
            legacyPositioning: spec.legacyPositioning,
            userOwned: spec.userOwned,
            locked: spec.locked,
            intent: spec.intent,
            enabled: _defaultEnabled(identifier, brief),
          ),
        );
        continue;
      }

      result.add(
        spec.toSlot(
          role: role,
          enabled: _defaultEnabled(identifier, brief),
        ),
      );
    }

    // 其余引擎槽位：全部禁用，但**必须留在列表里**。
    // 漏掉任何一个，存盘读回时都会被 `_mergeWithDefaultPromptManagerPrompts`
    // 以 enabled=true 追加到末尾 —— 那会毁掉 prefill。
    for (final spec in kEngineSlotSpecs) {
      if (used.contains(spec.identifier)) {
        continue;
      }
      final old = existing[spec.identifier];
      result.add(
        (old ?? spec.toSlot()).copyWith(
          label: spec.label,
          marker: spec.marker,
          systemPrompt: spec.systemPrompt,
          position: spec.position,
          legacyPositioning: spec.legacyPositioning,
          intent: spec.intent,
          enabled: false,
        ),
      );
    }

    return result;
  }

  /// 某个槽位在该需求下的默认开关。
  static bool _defaultEnabled(String identifier, PresetBrief brief) {
    switch (identifier) {
      case 'ykxReset':
        // 【重置】本身就是破限手段，档位为「不设」时不占用位置。
        return brief.jailbreakLevel != JailbreakLevel.none;
      case 'ykxFakeCot':
        // 伪造思考块按需求决定。
        return brief.wantCot;
      case 'ykxAssistantDeclare':
      case 'ykxUserDeclare':
      case 'ykxHistoryOpen':
      case 'ykxHistoryClose':
        return true;
      case 'nsfw':
        // 破限槽：默认开启，让用户看得见该往哪填；留空也无害。
        return true;
      default:
        return true;
    }
  }

  /// 某个结构下的「数据槽位」顺序（给 UI 展示用）。
  static List<String> dataSlotIdentifiers(PresetStructureKind kind) =>
      List<String>.from(_dataSlots);

  /// 结构里是否包含某个槽位（用于判断切换结构后会多/少什么）。
  static bool includesSlot(PresetStructureKind kind, String identifier) {
    final order = kind == PresetStructureKind.multiTurn
        ? _multiTurnOrder
        : _singleBlockOrder;
    return order.contains(identifier);
  }

  /// 切换结构时会新增的槽位（给确认弹窗用）。
  static List<String> addedBySwitch(
    PresetStructureKind from,
    PresetStructureKind to,
  ) {
    final fromOrder =
        from == PresetStructureKind.multiTurn ? _multiTurnOrder : _singleBlockOrder;
    final toOrder =
        to == PresetStructureKind.multiTurn ? _multiTurnOrder : _singleBlockOrder;
    return toOrder
        .where((identifier) => !fromOrder.contains(identifier))
        .toList(growable: false);
  }

  /// 切换结构时会变成「禁用」的槽位。
  static List<String> disabledBySwitch(
    PresetStructureKind from,
    PresetStructureKind to,
  ) {
    final fromOrder =
        from == PresetStructureKind.multiTurn ? _multiTurnOrder : _singleBlockOrder;
    final toOrder =
        to == PresetStructureKind.multiTurn ? _multiTurnOrder : _singleBlockOrder;
    return fromOrder
        .where((identifier) => !toOrder.contains(identifier))
        .toList(growable: false);
  }
}
