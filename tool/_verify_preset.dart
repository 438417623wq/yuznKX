// P1 数据层验收（纯 Dart，可 `dart run` 直接跑）。
//
// ⚠️ **这是「独立 oracle」，不是主力测试** —— 主力是
// `test/preset_workshop_test.dart`（78 用例），沙箱内用
// `bash .workbuddy-ai/scripts/dart_test.sh test/preset_workshop_test.dart` 跑。
//
// 两者覆盖同一批断言，分工：
// - 正式测试：随代码演进的**唯一维护点**（改 `PresetPackager` 先改它）。
// - 本脚本：**不依赖 `tool/_shim`** 的第二意见。替身坏了/改动过时用它交叉验证。
//
// 因此本脚本**不需要跟着业务演进** —— 它红了只说明「兼容性被破坏」，
// 先确认正式测试是否也红，再决定是改脚本还是改代码。
//
// 用法：dart run tool/_verify_preset.dart
import 'package:silly_tavern_flutter/features/preset_workshop/data/preset_packager.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_brief.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_project.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_slot.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/preset_slot_catalog.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/preset_structure_templates.dart';
import 'package:silly_tavern_flutter/features/presets/domain/models/preset.dart';

int _pass = 0;
final List<String> _failures = <String>[];

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _pass++;
  } else {
    _failures.add('$name${detail == null ? "" : "  → $detail"}');
  }
}

void checkEq(String name, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _pass++;
  } else {
    _failures.add('$name\n     actual   = $actual\n     expected = $expected');
  }
}

PresetProject _project({
  required PresetStructureKind kind,
  PresetBrief brief = const PresetBrief(),
  List<PresetSlot>? slots,
}) {
  return PresetProject(
    id: 'p1',
    name: '验收项目',
    structureKind: kind,
    brief: brief,
    slots: slots ?? PresetStructureTemplates.build(kind: kind, brief: brief),
  );
}

void main() {
  // ── 0. 引擎规范顺序 oracle ─────────────────────────────────────────
  // 空预设存盘读回后，引擎会补齐它自己的 21 个默认 prompt，
  // 顺序即 `_defaultPromptOrderIdentifiers`。拿它当 oracle 比对目录。
  final oracle = Preset.fromJson(
    Preset(id: 'oracle', name: 'oracle', prompts: const <PresetPrompt>[]).toJson(),
  );
  final oracleIds =
      oracle.prompts.map((prompt) => prompt.identifier).toList(growable: false);

  checkEq('0.1 引擎默认 prompt 数量 = 21', oracleIds.length, 21);
  checkEq('0.2 目录顺序 == 引擎规范顺序', kEngineSlotIdentifiers, oracleIds);
  checkEq('0.3 目录数量 = 21', kEngineSlotIdentifiers.length, 21);

  // ── 1. 两种模板的槽位完整性 ────────────────────────────────────────
  for (final kind in PresetStructureKind.values) {
    final slots = PresetStructureTemplates.build(
      kind: kind,
      brief: const PresetBrief(),
    );
    final ids = slots.map((slot) => slot.identifier).toList(growable: false);

    final wantedCustom = _customIdsFor(kind);
    checkEq('1.${kind.key} 槽位总数 = 21 引擎 + 该结构的自定义',
        ids.length, 21 + wantedCustom.length);
    checkEq('1.${kind.key} 无重复 identifier', ids.toSet().length, ids.length);

    final missing = oracleIds.where((id) => !ids.contains(id)).toList();
    checkEq('1.${kind.key} 21 个引擎 identifier 一个不漏', missing, <String>[]);

    // 自定义槽位必须在
    final customMissing =
        wantedCustom.where((id) => !ids.contains(id)).toList();
    checkEq('1.${kind.key} 该结构需要的自定义槽位都在', customMissing, <String>[]);

    // 不该出现的自定义槽位也不许混进来
    final extraCustom = ids
        .where((id) => id.startsWith('ykx') && !wantedCustom.contains(id))
        .toList();
    checkEq('1.${kind.key} 没有多出不该有的自定义槽位', extraCustom, <String>[]);
  }

  // ── 2. role 排布 ──────────────────────────────────────────────────
  final multi = _project(kind: PresetStructureKind.multiTurn);
  final single = _project(kind: PresetStructureKind.singleBlock);

  checkEq('2.1 多轮版末条启用槽位 = nsfw(assistant)',
      multi.enabledSlots.last.identifier, 'nsfw');
  checkEq('2.2 多轮版末条启用 role = assistant',
      multi.enabledSlots.last.role, 'assistant');
  checkEq('2.3 单块版末条启用 role = system（不做 prefill）',
      single.enabledSlots.last.role, 'system');

  final multiIds = multi.enabledSlots.map((s) => s.identifier).toList();
  checkEq('2.4 多轮版整个列表第一条是 ykxReset',
      multi.slots.first.identifier, 'ykxReset');
  // 默认 brief 是「破限=不设」，此时 ykxReset 关闭，所以启用列表第一条是 main。
  checkEq('2.4b 默认破限档位下 ykxReset 是关的，首个启用槽位 = main',
      multiIds.first, 'main');
  final jbFirst = PresetStructureTemplates.build(
    kind: PresetStructureKind.multiTurn,
    brief: const PresetBrief(jailbreakLevel: JailbreakLevel.heavy),
  );
  checkEq('2.4c 破限档位=重 → 首个启用槽位 = ykxReset',
      jbFirst.firstWhere((s) => s.enabled).identifier, 'ykxReset');
  checkEq('2.5 多轮版 ykxFakeCot 在最后（关闭时不占位）',
      multiIds.contains('ykxFakeCot'), false);
  checkEq('2.6 多轮版 main 的 role 被改成 user',
      multi.slotOf('main')!.role, 'user');
  checkEq('2.7 单块版 main 的 role 仍是 system',
      single.slotOf('main')!.role, 'system');
  checkEq('2.8 多轮版 chatHistory 夹在两个 user 之间',
      <String>[
        multi.slotOf('ykxHistoryOpen')!.role,
        multi.slotOf('chatHistory')!.role,
        multi.slotOf('ykxHistoryClose')!.role,
      ],
      <String>['user', 'system', 'user']);

  // ── 3. 破限档位 / COT 影响默认开关 ────────────────────────────────
  final noJb = PresetStructureTemplates.build(
    kind: PresetStructureKind.multiTurn,
    brief: const PresetBrief(jailbreakLevel: JailbreakLevel.none),
  );
  checkEq('3.1 破限档位=不设 → ykxReset 关闭',
      noJb.firstWhere((s) => s.identifier == 'ykxReset').enabled, false);

  final withJb = PresetStructureTemplates.build(
    kind: PresetStructureKind.multiTurn,
    brief: const PresetBrief(jailbreakLevel: JailbreakLevel.medium, wantCot: true),
  );
  checkEq('3.2 破限档位=中 → ykxReset 开启',
      withJb.firstWhere((s) => s.identifier == 'ykxReset').enabled, true);
  checkEq('3.3 wantCot → ykxFakeCot 开启',
      withJb.firstWhere((s) => s.identifier == 'ykxFakeCot').enabled, true);

  // ── 4. 结构切换不丢内容 ───────────────────────────────────────────
  final seeded = multi.copyWith(
    slots: multi.slots
        .map((slot) => slot.identifier == 'main'
            ? slot.copyWith(content: '顶部声明正文')
            : slot)
        .toList(),
  );
  final switched = PresetStructureTemplates.build(
    kind: PresetStructureKind.singleBlock,
    brief: const PresetBrief(),
    previous: seeded.slots,
  );
  checkEq('4.1 切到单块版后 main 内容保留',
      switched.firstWhere((s) => s.identifier == 'main').content, '顶部声明正文');
  checkEq('4.2 切到单块版后仍含 21 个引擎槽位',
      kEngineSlotIdentifiers
          .where((id) => !switched.map((s) => s.identifier).contains(id))
          .toList(),
      <String>[]);

  // ── 5. ★核心★ 存盘读回自检 ───────────────────────────────────────
  for (final kind in PresetStructureKind.values) {
    for (final channel in TargetChannel.values) {
      final project = _project(
        kind: kind,
        brief: PresetBrief(
          channel: channel,
          jailbreakLevel: channel.suggestedLevel,
          wantCot: channel == TargetChannel.local,
        ),
      );
      final packed = PresetPackager.build(project: project);
      final report = PresetPackager.verifyRoundTrip(packed.preset);

      check('5.${kind.key}/${channel.key} 打包无缺失 identifier',
          packed.isClean, packed.missingIdentifiers.join('、'));
      check('5.${kind.key}/${channel.key} 存盘读回顺序与开关一致',
          report.isHealthy,
          '${report.describe()}  (total ${report.totalBefore} → ${report.totalAfter})');
    }
  }

  // 反向导入再打包，也应健康
  final imported = PresetPackager.toSlots(packedOf(single));
  final importedPacked = PresetPackager.build(
    project: _project(kind: single.structureKind, slots: imported),
  );
  check('5.9 反向导入后重新打包仍然健康',
      PresetPackager.verifyRoundTrip(importedPacked.preset).isHealthy,
      PresetPackager.verifyRoundTrip(importedPacked.preset).describe());

  // ── 6. 内容与 role 在往返后保持 ───────────────────────────────────
  final contentProject = _project(
    kind: PresetStructureKind.multiTurn,
    slots: multi.slots
        .map((slot) => slot.copyWith(
              content: slot.identifier == 'chatHistory'
                  ? ''
                  : '「${slot.identifier}」的正文内容',
            ))
        .toList(),
  );
  final packedContent = PresetPackager.build(project: contentProject);
  final reloaded = Preset.fromJson(packedContent.preset.toJson());
  final reloadedMap = <String, PresetPrompt>{
    for (final prompt in reloaded.prompts) prompt.identifier: prompt,
  };

  checkEq('6.1 main 内容往返保持',
      reloadedMap['main']!.content, '「main」的正文内容');
  checkEq('6.2 main role 往返保持', reloadedMap['main']!.role, 'user');
  checkEq('6.3 nsfw role 往返保持', reloadedMap['nsfw']!.role, 'assistant');
  checkEq('6.4 自定义槽位 ykxReset 内容往返保持',
      reloadedMap['ykxReset']!.content, '「ykxReset」的正文内容');
  checkEq('6.5 自定义槽位 ykxFakeCot 仍在',
      reloadedMap.containsKey('ykxFakeCot'), true);
  checkEq('6.6 启用槽位顺序往返保持',
      reloaded.prompts.where((p) => p.enabled).map((p) => p.identifier).toList(),
      contentProject.enabledSlots.map((s) => s.identifier).toList());
  checkEq('6.7 关闭的槽位不会被偷偷打开',
      reloaded.prompts.where((p) => !p.enabled).length,
      contentProject.slots.where((s) => !s.enabled).length);

  // ── 7. 去重 ───────────────────────────────────────────────────────
  final dupSlots = <PresetSlot>[
    ...multi.slots,
    multi.slotOf('chatHistory')!.copyWith(content: '重复的历史标记'),
    multi.slotOf('main')!.copyWith(content: '重复的 main'),
  ];
  final dedupPacked = PresetPackager.build(
    project: _project(kind: PresetStructureKind.multiTurn, slots: dupSlots),
  );
  final dedupIds =
      dedupPacked.preset.prompts.map((p) => p.identifier).toList(growable: false);
  checkEq('7.1 重复 identifier 被去重', dedupIds.toSet().length, dedupIds.length);
  checkEq('7.2 chatHistory 只出现一次',
      dedupIds.where((id) => id == 'chatHistory').length, 1);
  checkEq('7.3 去重保留第一条（不是后者覆盖）',
      dedupPacked.preset.prompts
          .firstWhere((p) => p.identifier == 'main')
          .content,
      multi.slotOf('main')!.content);

  // ── 8. 反向导入 ───────────────────────────────────────────────────
  final roundTripped = PresetPackager.toSlots(packedOf(multi));
  checkEq('8.1 反向导入保持数量', roundTripped.length, multi.slots.length);
  checkEq('8.2 导出→反向导入 顺序完全一致（幂等）',
      roundTripped.map((s) => s.identifier).toList(),
      multi.slots.map((s) => s.identifier).toList());
  checkEq('8.2b 导出两次得到完全相同的槽位顺序',
      PresetPackager.toSlots(packedOf(multi))
          .map((s) => s.identifier)
          .toList(),
      PresetPackager.toSlots(packedOf(multi))
          .map((s) => s.identifier)
          .toList());
  checkEq('8.2c 反向导入的内容不丢',
      roundTripped.map((s) => s.content).toList(),
      multi.slots.map((s) => s.content).toList());
  checkEq('8.3 反向导入推断出多轮结构',
      PresetPackager.inferStructureKind(roundTripped),
      PresetStructureKind.multiTurn);
  checkEq('8.4 反向导入推断出单块结构',
      PresetPackager.inferStructureKind(PresetPackager.toSlots(packedOf(single))),
      PresetStructureKind.singleBlock);

  // 引擎不认识的 identifier 也不能丢
  final foreign = Preset(
    id: 'f',
    name: 'foreign',
    prompts: const <PresetPrompt>[
      PresetPrompt(
        identifier: 'someOtherToolBlock',
        name: '外部槽位',
        role: 'user',
        content: '外部工具的正文',
      ),
    ],
  );
  final foreignSlots = PresetPackager.toSlots(foreign);
  check('8.5 引擎不认识的 identifier 被保留',
      foreignSlots.any((s) => s.identifier == 'someOtherToolBlock'),
      foreignSlots.map((s) => s.identifier).join('、'));

  // ── 9. 渠道参数 ───────────────────────────────────────────────────
  final localPacked = PresetPackager.applyBriefParameters(
    packedOf(multi),
    const PresetBrief(channel: TargetChannel.local),
  );
  checkEq('9.1 本地模型 temperature=0.8', localPacked.temperature, 0.8);
  checkEq('9.2 本地模型 repetitionPenalty=1.1',
      localPacked.repetitionPenalty, 1.1);

  final openaiPacked = PresetPackager.applyBriefParameters(
    packedOf(multi),
    const PresetBrief(channel: TargetChannel.openai),
  );
  checkEq('9.3 OpenAI 用引擎默认 temperature',
      openaiPacked.temperature, Preset.defaultTemperature);
  checkEq('9.4 渠道建议破限档位',
      <int>[
        TargetChannel.gemini.suggestedLevel.value,
        TargetChannel.claude.suggestedLevel.value,
        TargetChannel.local.suggestedLevel.value,
      ],
      <int>[2, 1, 0]);

  // ── 10. 项目派生状态与落库 ────────────────────────────────────────
  checkEq('10.1 historyMarkerCount = 1', multi.historyMarkerCount, 1);
  final projectJson = multi.toJson();
  checkEq('10.2 运行态字段不落库',
      <bool>[
        projectJson.containsKey('busyStage'),
        projectJson.containsKey('streamPreview'),
        projectJson.containsKey('error'),
      ],
      <bool>[false, false, false]);

  final restored = PresetProject.fromJson(projectJson);
  checkEq('10.3 项目存盘读回槽位数量一致', restored.slots.length, multi.slots.length);
  checkEq('10.4 项目存盘读回结构一致', restored.structureKind, multi.structureKind);
  checkEq('10.5 项目存盘读回 stage 一致', restored.stage, multi.stage);
  checkEq('10.6 项目存盘读回 brief 一致', restored.brief.toJson(), multi.brief.toJson());

  // ── 11. 空项目不炸 ────────────────────────────────────────────────
  final emptyPacked = PresetPackager.build(
    project: PresetProject(id: 'e', name: '空项目'),
  );
  checkEq('11.1 空项目被补齐 21 个引擎槽位',
      emptyPacked.preset.prompts.length, 21);
  checkEq('11.2 空项目无缺失', emptyPacked.missingIdentifiers, <String>[]);
  check('11.3 空项目往返健康',
      PresetPackager.verifyRoundTrip(emptyPacked.preset).isHealthy);

  // ── 12. 异常输入 ──────────────────────────────────────────────────
  final weirdPacked = PresetPackager.build(
    project: _project(
      kind: PresetStructureKind.multiTurn,
      slots: <PresetSlot>[
        const PresetSlot(identifier: '', label: '空标识', role: 'system'),
        const PresetSlot(identifier: 'main', label: 'main', role: '  USER  '),
        const PresetSlot(identifier: 'zzzCustom', label: '未知', role: 'nonsense'),
      ],
    ),
  );
  check('12.1 空 identifier 被丢弃',
      !weirdPacked.preset.prompts.any((p) => p.identifier.isEmpty));
  checkEq('12.2 role 被规范化（大写 + 空格）',
      weirdPacked.preset.prompts.firstWhere((p) => p.identifier == 'main').role,
      'user');
  checkEq('12.3 非法 role 退回 system',
      weirdPacked.preset.prompts.firstWhere((p) => p.identifier == 'zzzCustom').role,
      'system');
  // main 本身就在 21 个引擎槽位里，所以只多出 zzzCustom 这一个。
  checkEq('12.4 未知 identifier 也补齐了 21 个引擎槽位',
      weirdPacked.preset.prompts.length, 21 + 1);
  checkEq('12.5 首尾空白被裁掉（main 不被当成新槽位）',
      weirdPacked.preset.prompts
          .where((p) => p.identifier.trim() == 'main')
          .length,
      1);

  // ── 输出 ──────────────────────────────────────────────────────────
  print('');
  print('通过 $_pass 条，失败 ${_failures.length} 条');
  if (_failures.isNotEmpty) {
    print('');
    for (var i = 0; i < _failures.length; i++) {
      print('  [${i + 1}] ${_failures[i]}');
    }
    print('');
    print('P1 验收：FAIL');
  } else {
    print('P1 验收：PASS');
  }
}

/// 便捷：把项目打包成 Preset。
Preset packedOf(PresetProject project) =>
    PresetPackager.build(project: project).preset;

/// 某个结构模板应当包含的自定义槽位。
List<String> _customIdsFor(PresetStructureKind kind) {
  // 单块版按设计不带「定义模型身份 / 定义用户身份 / 伪造思考」——
  // 那三条本身就是多轮伪造的产物。
  const singleBlockCustom = <String>[
    'ykxReset',
    'ykxHistoryOpen',
    'ykxHistoryClose',
  ];
  return kCustomSlotSpecs
      .map((spec) => spec.identifier)
      .where((id) =>
          kind == PresetStructureKind.multiTurn || singleBlockCustom.contains(id))
      .toList(growable: false);
}
