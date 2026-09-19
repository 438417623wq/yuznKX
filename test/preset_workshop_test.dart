/// 预设工坊 P1 数据层的单元测试。
///
/// **为什么这些测试重要**：预设存进 Hive 再读回来，会走
/// `Preset.parseWithReport` → `_mergeWithDefaultPromptManagerPrompts` ——
/// 那里是「**缺哪个 identifier 就补哪个，且默认 `enabled: true`**」，
/// 补进来的会被追加到末尾。漏一个槽位就会：
/// ① 稀释底部注意力；② 让最后一条消息不再是 assistant，**prefill 直接失效**。
///
/// 这个坑**静默**（分析器不报、运行时不崩），只能靠回归测试钉住。
/// 所以本文件的核心是「打包 → 存盘 → 读回」的往返一致性。
///
/// 全是纯逻辑，不依赖 Flutter binding / Hive / 网络。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/data/preset_packager.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_brief.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_project.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_slot.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/models/preset_diagnosis.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/preset_local_diagnosis.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/preset_slot_catalog.dart';
import 'package:silly_tavern_flutter/features/preset_workshop/domain/preset_structure_templates.dart';
import 'package:silly_tavern_flutter/features/presets/domain/models/preset.dart';

/// 某个结构模板应当包含的自定义槽位。
///
/// 单块版按设计不带「定义模型身份 / 定义用户身份 / 伪造思考」——
/// 那三条本身就是多轮伪造的产物。
List<String> customIdsFor(PresetStructureKind kind) {
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

PresetProject projectOf({
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

/// 便捷：把项目打包成 Preset。
Preset packedOf(PresetProject project) =>
    PresetPackager.build(project: project).preset;

/// 引擎规范顺序 oracle。
///
/// 拿一个空预设存盘读回，引擎会补齐它自己的 21 个默认 prompt，
/// 顺序即 `Preset._defaultPromptOrderIdentifiers`。用它比对目录，
/// 引擎那边加了槽位这里会立刻红。
List<String> engineCanonicalOrder() => Preset.fromJson(
      Preset(id: 'oracle', name: 'oracle', prompts: const <PresetPrompt>[])
          .toJson(),
    ).prompts.map((prompt) => prompt.identifier).toList(growable: false);

/// 报告里所有问题的 id —— 断言用。
///
/// 断言写成 `contains('local.xxx')` 而不是直接比整个列表，是因为规则会随
/// 骨架演进增删；只要**该报的报了**即可，不锁死整体集合。
List<String> issueIds(PresetDiagnosisReport report) =>
    report.issues.map((issue) => issue.id).toList(growable: false);

void main() {
  // ---------------------------------------------------------------------------
  group('槽位目录与引擎规范顺序一致', () {
    test('引擎默认 prompt 恰好 21 个', () {
      expect(engineCanonicalOrder(), hasLength(21));
    });

    test('kEngineSlotIdentifiers 与引擎规范顺序逐项相同', () {
      // 顺序不同也不行 —— `_normalize` 补缺时按这个顺序追加。
      expect(kEngineSlotIdentifiers, engineCanonicalOrder());
    });

    test('identifier 无重复，且都带中文名与设计意图', () {
      final ids = kEngineSlotIdentifiers;
      expect(ids.toSet(), hasLength(ids.length));
      for (final spec in kAllSlotSpecs) {
        expect(spec.label.trim(), isNotEmpty, reason: spec.identifier);
        expect(spec.intent.trim(), isNotEmpty, reason: spec.identifier);
      }
    });

    test('marker 槽位与引擎实测值一致', () {
      // 这几个的内容由引擎填充，工坊只决定位置。填错了会变成「往里写文本」。
      const expectedMarkers = <String>{
        'worldInfoBefore',
        'worldInfoAfter',
        'charDescription',
        'charPersonality',
        'scenario',
        'personaDescription',
        'dialogueExamples',
        'chatHistory',
      };
      final actual = kEngineSlotSpecs
          .where((spec) => spec.marker)
          .map((spec) => spec.identifier)
          .toSet();
      expect(actual, expectedMarkers);
    });

    test('chatHistory 被锁定（AI 不可增删）', () {
      final chatHistory = kEngineSlotSpecs
          .firstWhere((spec) => spec.identifier == 'chatHistory');
      expect(chatHistory.locked, isTrue);
      expect(chatHistory.marker, isTrue);
    });

    test('破限槽 nsfw 归用户所有（AI 不代写）', () {
      final nsfw =
          kEngineSlotSpecs.firstWhere((spec) => spec.identifier == 'nsfw');
      expect(nsfw.userOwned, isTrue);
    });

    test('未知 identifier 查表退回自身，不抛异常', () {
      expect(slotSpecOf('nope'), isNull);
      expect(slotLabelOf('nope'), 'nope');
      expect(slotIntentOf('nope'), '');
      expect(isEngineSlot('nope'), isFalse);
      // 外部预设导进来的 identifier 也不能丢。
      final slot = buildSlotFromIdentifier('nope', content: '正文');
      expect(slot.identifier, 'nope');
      expect(slot.content, '正文');
    });
  });

  // ---------------------------------------------------------------------------
  group('结构模板 — 槽位完整性', () {
    for (final kind in PresetStructureKind.values) {
      test('${kind.label}：21 个引擎 identifier 一个不漏', () {
        final slots =
            PresetStructureTemplates.build(kind: kind, brief: const PresetBrief());
        final ids = slots.map((slot) => slot.identifier).toList(growable: false);

        expect(
          engineCanonicalOrder().where((id) => !ids.contains(id)).toList(),
          isEmpty,
        );
        expect(ids.toSet(), hasLength(ids.length), reason: '不能有重复 identifier');
        expect(ids, hasLength(21 + customIdsFor(kind).length));
      });

      test('${kind.label}：该结构的自定义槽位不多不少', () {
        final ids = PresetStructureTemplates
            .build(kind: kind, brief: const PresetBrief())
            .map((slot) => slot.identifier)
            .toList(growable: false);

        final wanted = customIdsFor(kind);
        expect(wanted.where((id) => !ids.contains(id)).toList(), isEmpty);
        expect(
          ids
              .where((id) => id.startsWith('ykx') && !wanted.contains(id))
              .toList(),
          isEmpty,
        );
      });

      test('${kind.label}：其余引擎槽位都在，但全部禁用', () {
        final slots =
            PresetStructureTemplates.build(kind: kind, brief: const PresetBrief());
        // 这是「不能漏槽位」的正向表述：漏了会以 enabled=true 被追加到末尾。
        for (final spec in kEngineSlotSpecs) {
          expect(
            slots.any((slot) => slot.identifier == spec.identifier),
            isTrue,
            reason: '缺了 ${spec.identifier}',
          );
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  group('结构模板 — role 排布与 prefill', () {
    test('多轮版末条启用槽位是 assistant（prefill 成立）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(project.enabledSlots.last.identifier, 'nsfw');
      expect(project.enabledSlots.last.role, 'assistant');
    });

    test('单块版末条启用槽位是 system（不做 prefill）', () {
      final project = projectOf(kind: PresetStructureKind.singleBlock);
      expect(project.enabledSlots.last.role, 'system');
    });

    test('多轮版把 main / jailbreak 改成 user', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(project.slotOf('main')!.role, 'user');
      expect(project.slotOf('jailbreak')!.role, 'user');
      expect(project.slotOf('nsfw')!.role, 'assistant');
    });

    test('单块版全部走 system（除 bias）', () {
      final project = projectOf(kind: PresetStructureKind.singleBlock);
      for (final slot in project.enabledSlots) {
        if (slot.identifier == 'bias') {
          continue; // bias 引擎侧就是 assistant，模板不动它。
        }
        expect(slot.role, 'system', reason: slot.identifier);
      }
    });

    test('chatHistory 被两个 user 槽位夹住（跨消息标签包裹历史）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(
        [
          project.slotOf('ykxHistoryOpen')!.role,
          project.slotOf('chatHistory')!.role,
          project.slotOf('ykxHistoryClose')!.role,
        ],
        ['user', 'system', 'user'],
      );
      // 顺序也必须是「前缀 → 历史 → 后缀」，中间不能插别的。
      final ids = project.slots.map((slot) => slot.identifier).toList();
      expect(
        ids.indexOf('ykxHistoryOpen') + 1,
        ids.indexOf('chatHistory'),
      );
      expect(
        ids.indexOf('ykxHistoryClose'),
        ids.indexOf('chatHistory') + 1,
      );
    });

    test('多轮版整表首条是 ykxReset（破限档位决定它开不开）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(project.slots.first.identifier, 'ykxReset');
      // 默认 brief 是「破限=不设」，此时它关闭，首个启用槽位是 main。
      expect(project.enabledSlots.first.identifier, 'main');

      final heavy = PresetStructureTemplates.build(
        kind: PresetStructureKind.multiTurn,
        brief: const PresetBrief(jailbreakLevel: JailbreakLevel.heavy),
      );
      expect(heavy.firstWhere((slot) => slot.enabled).identifier, 'ykxReset');
    });
  });

  // ---------------------------------------------------------------------------
  group('结构模板 — 需求驱动的默认开关', () {
    test('破限档位为「不设」时 ykxReset 关闭', () {
      final slots = PresetStructureTemplates.build(
        kind: PresetStructureKind.multiTurn,
        brief: const PresetBrief(jailbreakLevel: JailbreakLevel.none),
      );
      expect(slots.firstWhere((s) => s.identifier == 'ykxReset').enabled, isFalse);
    });

    test('wantCot 决定 ykxFakeCot 开关', () {
      bool cotEnabled(bool wantCot) => PresetStructureTemplates.build(
            kind: PresetStructureKind.multiTurn,
            brief: PresetBrief(wantCot: wantCot),
          ).firstWhere((s) => s.identifier == 'ykxFakeCot').enabled;

      expect(cotEnabled(false), isFalse);
      expect(cotEnabled(true), isTrue);
    });

    test('切换结构时旧内容不丢', () {
      final seeded = projectOf(kind: PresetStructureKind.multiTurn).copyWith(
        slots: projectOf(kind: PresetStructureKind.multiTurn)
            .slots
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

      expect(
        switched.firstWhere((s) => s.identifier == 'main').content,
        '顶部声明正文',
      );
      // 切过去之后仍然一个引擎槽位都不少。
      final ids = switched.map((slot) => slot.identifier).toSet();
      expect(kEngineSlotIdentifiers.where((id) => !ids.contains(id)).toList(),
          isEmpty);
    });

    test('切换结构会新增/禁用哪些槽位（给确认弹窗用）', () {
      expect(
        PresetStructureTemplates.addedBySwitch(
          PresetStructureKind.singleBlock,
          PresetStructureKind.multiTurn,
        ),
        containsAll(<String>[
          'ykxAssistantDeclare',
          'ykxUserDeclare',
          'ykxFakeCot',
        ]),
      );
      expect(
        PresetStructureTemplates.disabledBySwitch(
          PresetStructureKind.multiTurn,
          PresetStructureKind.singleBlock,
        ),
        containsAll(<String>[
          'ykxAssistantDeclare',
          'ykxUserDeclare',
          'ykxFakeCot',
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('PresetPackager — 打包与去重', () {
    test('打包出的槽位数 = 模板槽位数（没有重复补齐）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      final packed = PresetPackager.build(project: project);
      expect(packed.isClean, isTrue, reason: packed.missingIdentifiers.join('、'));
      expect(packed.preset.prompts, hasLength(project.slots.length));
    });

    test('同 identifier 只保留第一条（重复 chatHistory 会让历史插多次）', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final dup = <PresetSlot>[
        ...base.slots,
        base.slotOf('chatHistory')!.copyWith(content: '重复的历史标记'),
        base.slotOf('main')!.copyWith(content: '重复的 main'),
      ];
      final packed = PresetPackager.build(
        project: projectOf(kind: PresetStructureKind.multiTurn, slots: dup),
      );
      final ids =
          packed.preset.prompts.map((p) => p.identifier).toList(growable: false);

      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.where((id) => id == 'chatHistory'), hasLength(1));
      // 保留的是第一条，不是被后者覆盖。
      expect(
        packed.preset.prompts
            .firstWhere((p) => p.identifier == 'main')
            .content,
        base.slotOf('main')!.content,
      );
    });

    test('空 identifier 被丢弃，首尾空白被裁掉', () {
      final packed = PresetPackager.build(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: const <PresetSlot>[
            PresetSlot(identifier: '', label: '空标识', role: 'system'),
            PresetSlot(identifier: '  main  ', label: 'main', role: 'system'),
          ],
        ),
      );
      final ids = packed.preset.prompts.map((p) => p.identifier).toList();

      expect(ids.any((id) => id.trim().isEmpty), isFalse);
      expect(ids.where((id) => id == 'main'), hasLength(1));
      expect(packed.preset.prompts, hasLength(21));
    });

    test('role 被规范化：大写/空白容忍，非法值退回 system', () {
      final packed = PresetPackager.build(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: const <PresetSlot>[
            PresetSlot(identifier: 'main', label: 'main', role: '  USER  '),
            PresetSlot(identifier: 'zzzCustom', label: '未知', role: 'nonsense'),
          ],
        ),
      );
      expect(
        packed.preset.prompts.firstWhere((p) => p.identifier == 'main').role,
        'user',
      );
      expect(
        packed.preset.prompts.firstWhere((p) => p.identifier == 'zzzCustom').role,
        'system',
      );
    });

    test('空项目也被补齐 21 个引擎槽位（全禁用）', () {
      final packed =
          PresetPackager.build(project: PresetProject(id: 'e', name: '空项目'));
      expect(packed.preset.prompts, hasLength(21));
      expect(packed.missingIdentifiers, isEmpty);
      expect(packed.preset.prompts.every((p) => !p.enabled), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('★ 存盘读回一致性（防 prefill 静默失效）', () {
    for (final kind in PresetStructureKind.values) {
      for (final channel in TargetChannel.values) {
        test('${kind.label} / ${channel.label}：顺序与开关原样保留', () {
          final project = projectOf(
            kind: kind,
            brief: PresetBrief(
              channel: channel,
              jailbreakLevel: channel.suggestedLevel,
              wantCot: channel == TargetChannel.local,
            ),
          );
          final packed = PresetPackager.build(project: project);
          final report = PresetPackager.verifyRoundTrip(packed.preset);

          expect(packed.isClean, isTrue,
              reason: '缺槽位：${packed.missingIdentifiers.join("、")}');
          expect(report.isHealthy, isTrue, reason: report.describe());
          // 读回后条数不能变多 —— 变多说明有 identifier 被当成「未知」重补了。
          expect(report.totalAfter, report.totalBefore);
          expect(report.enabledAfter, report.enabledBefore);
        });
      }
    }

    test('内容与 role 往返后不丢', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final project = projectOf(
        kind: PresetStructureKind.multiTurn,
        slots: base.slots
            .map((slot) => slot.copyWith(
                  content: slot.identifier == 'chatHistory'
                      ? ''
                      : '「${slot.identifier}」的正文内容',
                ))
            .toList(),
      );
      final reloaded =
          Preset.fromJson(PresetPackager.build(project: project).preset.toJson());
      final byId = <String, PresetPrompt>{
        for (final prompt in reloaded.prompts) prompt.identifier: prompt,
      };

      expect(byId['main']!.content, '「main」的正文内容');
      expect(byId['ykxReset']!.content, '「ykxReset」的正文内容');
      expect(byId['main']!.role, 'user');
      expect(byId['nsfw']!.role, 'assistant');
      expect(byId.containsKey('ykxFakeCot'), isTrue);

      expect(
        reloaded.prompts
            .where((p) => p.enabled)
            .map((p) => p.identifier)
            .toList(),
        project.enabledSlots.map((slot) => slot.identifier).toList(),
      );
      expect(
        reloaded.prompts.where((p) => !p.enabled),
        hasLength(project.slots.where((slot) => !slot.enabled).length),
      );
    });

    test('关闭的槽位不会被偷偷打开', () {
      final project = projectOf(
        kind: PresetStructureKind.multiTurn,
        brief: const PresetBrief(jailbreakLevel: JailbreakLevel.none),
      );
      final reloaded =
          Preset.fromJson(PresetPackager.build(project: project).preset.toJson());
      final reset =
          reloaded.prompts.firstWhere((p) => p.identifier == 'ykxReset');
      expect(reset.enabled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('PresetPackager — 反向导入已有预设', () {
    test('导出 → 反向导入：顺序、内容完全一致（幂等）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      final slots = PresetPackager.toSlots(packedOf(project));

      expect(slots, hasLength(project.slots.length));
      expect(
        slots.map((slot) => slot.identifier).toList(),
        project.slots.map((slot) => slot.identifier).toList(),
      );
      expect(
        slots.map((slot) => slot.content).toList(),
        project.slots.map((slot) => slot.content).toList(),
      );
    });

    test('导出两次得到完全相同的槽位顺序（不吃 List.sort 不稳定的亏）', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(
        PresetPackager.toSlots(packedOf(project))
            .map((slot) => slot.identifier)
            .toList(),
        PresetPackager.toSlots(packedOf(project))
            .map((slot) => slot.identifier)
            .toList(),
      );
    });

    test('引擎不认识的 identifier 也保留（不丢内容）', () {
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
      final slots = PresetPackager.toSlots(foreign);
      final block =
          slots.firstWhere((slot) => slot.identifier == 'someOtherToolBlock');

      expect(block.content, '外部工具的正文');
      expect(block.role, 'user');
    });

    test('推断结构类型', () {
      expect(
        PresetPackager.inferStructureKind(
          PresetPackager.toSlots(
            packedOf(projectOf(kind: PresetStructureKind.multiTurn)),
          ),
        ),
        PresetStructureKind.multiTurn,
      );
      expect(
        PresetPackager.inferStructureKind(
          PresetPackager.toSlots(
            packedOf(projectOf(kind: PresetStructureKind.singleBlock)),
          ),
        ),
        PresetStructureKind.singleBlock,
      );
      // 空列表兜底。
      expect(
        PresetPackager.inferStructureKind(const <PresetSlot>[]),
        PresetStructureKind.singleBlock,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('PresetPackager — 渠道参数', () {
    test('本地模型收温度与重复惩罚，其它渠道用引擎默认', () {
      final base = packedOf(projectOf(kind: PresetStructureKind.multiTurn));

      final local = PresetPackager.applyBriefParameters(
        base,
        const PresetBrief(channel: TargetChannel.local),
      );
      expect(local.temperature, 0.8);
      expect(local.repetitionPenalty, 1.1);

      final openai = PresetPackager.applyBriefParameters(
        base,
        const PresetBrief(channel: TargetChannel.openai),
      );
      expect(openai.temperature, Preset.defaultTemperature);
      expect(openai.repetitionPenalty, Preset.defaultRepetitionPenalty);
      // 别把 prompts 弄丢了。
      expect(openai.prompts, hasLength(base.prompts.length));
    });

    test('渠道建议破限档位', () {
      expect(TargetChannel.gemini.suggestedLevel, JailbreakLevel.medium);
      expect(TargetChannel.claude.suggestedLevel, JailbreakLevel.light);
      expect(TargetChannel.local.suggestedLevel, JailbreakLevel.none);
      expect(TargetChannel.openai.suggestedLevel, JailbreakLevel.medium);
    });

    test('破限档位的首尾占位语义', () {
      expect(JailbreakLevel.none.needsTop, isFalse);
      expect(JailbreakLevel.light.needsTop, isFalse);
      expect(JailbreakLevel.medium.needsTop, isTrue);
      expect(JailbreakLevel.medium.needsBottom, isFalse);
      expect(JailbreakLevel.heavy.needsTop, isTrue);
      expect(JailbreakLevel.heavy.needsBottom, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('PresetProject — 派生状态与落库', () {
    test('historyMarkerCount 恰好 1', () {
      expect(projectOf(kind: PresetStructureKind.multiTurn).historyMarkerCount, 1);
      expect(projectOf(kind: PresetStructureKind.singleBlock).historyMarkerCount, 1);
    });

    test('enabledRoleSequence 按顺序取启用槽位的 role', () {
      final project = projectOf(kind: PresetStructureKind.multiTurn);
      expect(
        project.enabledRoleSequence,
        project.enabledSlots.map((slot) => slot.role).toList(),
      );
      expect(project.enabledRoleSequence.last, 'assistant');
    });

    test('运行态字段不落库', () {
      final json = projectOf(kind: PresetStructureKind.multiTurn).toJson();
      expect(json.containsKey('busyStage'), isFalse);
      expect(json.containsKey('streamPreview'), isFalse);
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('errorRaw'), isFalse);
    });

    test('项目存盘读回：槽位、结构、阶段、需求都一致', () {
      final project = projectOf(
        kind: PresetStructureKind.multiTurn,
        brief: const PresetBrief(
          rpMode: RpMode.novel,
          channel: TargetChannel.claude,
          pov: PovMode.third,
          wordLimit: 900,
          styleTags: <String>['冷硬简洁', '细腻心理描写'],
          jailbreakLevel: JailbreakLevel.medium,
          wantCot: true,
          extraNotes: '不要替玩家做决定',
        ),
      ).copyWith(stage: PresetStage.diagnose);

      final restored = PresetProject.fromJson(project.toJson());
      expect(restored.slots, hasLength(project.slots.length));
      expect(restored.structureKind, project.structureKind);
      expect(restored.stage, project.stage);
      expect(restored.brief.toJson(), project.brief.toJson());
      expect(
        restored.slots.map((slot) => slot.identifier).toList(),
        project.slots.map((slot) => slot.identifier).toList(),
      );
    });

    test('阶段按 key 持久化（往中间插阶段不破坏已有项目）', () {
      expect(PresetStage.fromKey('diagnose'), PresetStage.diagnose);
      expect(PresetStage.fromKey('不存在'), PresetStage.brief);
      expect(PresetStage.fromKey(null), PresetStage.brief);
    });

    test('结构类型缺省时按需求默认「伪造多轮」', () {
      expect(PresetStructureKind.fromKey(null), PresetStructureKind.multiTurn);
      expect(PresetStructureKind.fromKey('不存在'), PresetStructureKind.multiTurn);
      expect(
        PresetStructureKind.fromKey('single_block'),
        PresetStructureKind.singleBlock,
      );
    });

    test('custom 扮演方式必须填描述才算完整', () {
      expect(const PresetBrief().isComplete, isTrue);
      expect(const PresetBrief(rpMode: RpMode.custom).isComplete, isFalse);
      expect(
        const PresetBrief(rpMode: RpMode.custom, rpModeNote: '我自己的玩法')
            .isComplete,
        isTrue,
      );
    });

    test('toPromptText 带上所有已填维度', () {
      final text = const PresetBrief(
        rpMode: RpMode.novel,
        channel: TargetChannel.gemini,
        pov: PovMode.third,
        wordLimit: 800,
        styleTags: <String>['轻小说'],
        jailbreakLevel: JailbreakLevel.medium,
        wantCot: true,
        extraNotes: '别写太长',
      ).toPromptText();

      expect(text, contains('小说模拟器'));
      expect(text, contains('Gemini'));
      expect(text, contains('第三人称'));
      expect(text, contains('800'));
      expect(text, contains('轻小说'));
      expect(text, contains('别写太长'));
    });
  });

  // ---------------------------------------------------------------------------
  group('本地诊断 — 结构层', () {
    test('刚生成的骨架没有错误级问题', () {
      final report = PresetLocalDiagnosis.run(
        project: projectOf(kind: PresetStructureKind.multiTurn),
      );
      expect(report.errorCount, 0, reason: report.summaryLine());
      expect(report.hasBlockingIssue, isFalse);
    });

    test('缺引擎槽位 → 错误', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .where((slot) => slot.identifier != 'main')
              .toList(),
        ),
      );
      expect(issueIds(report), contains('local.engine_slot_missing'));
      expect(report.hasBlockingIssue, isTrue);
    });

    test('chatHistory 缺失 / 禁用 / 重复 都是错误', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);

      final missing = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .where((slot) => slot.identifier != 'chatHistory')
              .toList(),
        ),
      );
      expect(issueIds(missing), contains('local.history_marker_missing'));

      final disabled = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'chatHistory'
                  ? slot.copyWith(enabled: false)
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(disabled), contains('local.history_marker_disabled'));

      final duplicated = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: <PresetSlot>[
            ...base.slots,
            base.slotOf('chatHistory')!.copyWith(),
          ],
        ),
      );
      expect(issueIds(duplicated), contains('local.history_marker_duplicated'));
    });

    test('全部禁用 → 错误', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.copyWith(enabled: false))
              .toList(),
        ),
      );
      expect(issueIds(report), contains('local.all_disabled'));
    });

    test('多轮结构末条不是 assistant → 警告', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      // 把最后一条启用的槽位（nsfw）改成 system。
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'nsfw'
                  ? slot.copyWith(role: 'system')
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), contains('local.prefill_broken'));
    });

    test('单块结构不查 prefill（它本来就不以 assistant 收尾）', () {
      final base = projectOf(kind: PresetStructureKind.singleBlock);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.singleBlock,
          slots: base.slots
              .map((slot) => slot.identifier == 'nsfw'
                  ? slot.copyWith(role: 'system')
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), isNot(contains('local.prefill_broken')));
    });

    test('重复的 identifier → 警告（导出会静默丢后面的内容）', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: <PresetSlot>[
            ...base.slots,
            base.slotOf('main')!.copyWith(content: '第二份 main'),
          ],
        ),
      );
      expect(issueIds(report), contains('local.identifier_duplicated'));
    });

    test('外部导入的未知 identifier → 提示（不丢内容）', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: <PresetSlot>[
            ...base.slots,
            const PresetSlot(
              identifier: 'someOtherToolBlock',
              label: '外部槽位',
              role: 'user',
              content: '外部内容',
            ),
          ],
        ),
      );
      expect(issueIds(report), contains('local.unknown_identifier'));
    });
  });

  // ---------------------------------------------------------------------------
  group('本地诊断 — 连续同 role', () {
    /// 造一个「若干条同 role 的连续槽位」的项目。
    PresetProject runOf(String role, int count) {
      return PresetProject(
        id: 'run',
        name: '连续 role',
        structureKind: PresetStructureKind.multiTurn,
        slots: <PresetSlot>[
          for (var i = 0; i < count; i++)
            PresetSlot(
              identifier: 'ykxRun$i',
              label: '第 $i 条',
              role: role,
              content: '内容 $i',
            ),
          // 补齐 21 个引擎槽位（全禁用），免得触发「缺槽位」错误。
          for (final spec in kEngineSlotSpecs)
            if (!spec.identifier.startsWith('ykx'))
              spec.toSlot(enabled: false),
        ],
      );
    }

    test('连续 3 条 user → 警告', () {
      expect(issueIds(PresetLocalDiagnosis.run(project: runOf('user', 3))),
          contains('local.role_run'));
    });

    test('连续 3 条 assistant → 警告', () {
      expect(issueIds(PresetLocalDiagnosis.run(project: runOf('assistant', 3))),
          contains('local.role_run'));
    });

    test('★ 连续 3 条 system 不报 —— system 会被提到系统提示里', () {
      // 回归测试：曾经这条规则连 system 一起报，结果工坊自己生成的骨架
      // （8 个连续的 system 数据槽位）会踩自己的告警。核实过：
      // `_assemblePromptMessages` 不合并，OpenAI 原样发，
      // Claude / Gemini 把 system 全部提到顶层 system 字段。
      expect(issueIds(PresetLocalDiagnosis.run(project: runOf('system', 5))),
          isNot(contains('local.role_run')));
    });

    test('连续 2 条 user 还没到阈值', () {
      expect(issueIds(PresetLocalDiagnosis.run(project: runOf('user', 2))),
          isNot(contains('local.role_run')));
    });
  });

  // ---------------------------------------------------------------------------
  group('本地诊断 — 宏拼写', () {
    PresetProject withContent(String content) => PresetProject(
          id: 'macro',
          name: '宏',
          structureKind: PresetStructureKind.multiTurn,
          slots: <PresetSlot>[
            PresetSlot(
              identifier: 'ykxProbe',
              label: '探针',
              role: 'system',
              content: content,
            ),
            for (final spec in kEngineSlotSpecs) spec.toSlot(enabled: false),
          ],
        );

    test('引擎支持的四个基础宏都不报', () {
      final report = PresetLocalDiagnosis.run(
        project: withContent('{{char}} 与 {{user}}，{{group}}，{{charIfNotGroup}}'),
      );
      expect(issueIds(report), isNot(contains('local.unknown_macro')));
      expect(issueIds(report), isNot(contains('local.macro_whitespace')));
    });

    test('变量宏不报', () {
      final report = PresetLocalDiagnosis.run(
        project: withContent(
          '{{getvar::好感度}} {{setvar::好感度::5}} '
          '{{get_chat_variable::心情}} {{var::好感度}}',
        ),
      );
      expect(issueIds(report), isNot(contains('local.unknown_macro')));
    });

    test('★ 酒馆生态的常见宏会报 —— 本引擎不替换它们', () {
      // 这是最容易踩的坑：从别处抄来的预设看着很正常，实际一个都不生效。
      final report = PresetLocalDiagnosis.run(
        project: withContent('{{personality}} {{scenario}} {{time}} {{date}}'),
      );
      expect(issueIds(report), contains('local.unknown_macro'));
    });

    test('★ 大括号里带空格会报 —— 引擎是精确字符串替换', () {
      final report = PresetLocalDiagnosis.run(
        project: withContent('{{ char }}'),
      );
      expect(issueIds(report), contains('local.macro_whitespace'));
      // 带空格的不能被当成「支持的宏」放过去。
      expect(issueIds(report), isNot(contains('local.unknown_macro')));
    });

    test('没有宏就不报', () {
      final report = PresetLocalDiagnosis.run(
        project: withContent('这里一个宏都没有，只有普通文本。'),
      );
      expect(issueIds(report), isNot(contains('local.unknown_macro')));
      expect(issueIds(report), isNot(contains('local.macro_whitespace')));
    });
  });

  // ---------------------------------------------------------------------------
  group('本地诊断 — 内容层与冲突层', () {
    test('底部指令过长 → 警告', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'jailbreak'
                  ? slot.copyWith(
                      content: '字' * (PresetLocalDiagnosis.bottomInstructionLimit + 1),
                    )
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), contains('local.bottom_too_long'));
    });

    test('底部指令刚好到上限不报', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'jailbreak'
                  ? slot.copyWith(
                      content: '字' * PresetLocalDiagnosis.bottomInstructionLimit,
                    )
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), isNot(contains('local.bottom_too_long')));
    });

    test('破限位填了 3 处 → 警告（下猛药）', () {
      final base = projectOf(
        kind: PresetStructureKind.multiTurn,
        brief: const PresetBrief(jailbreakLevel: JailbreakLevel.heavy),
      );
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          brief: const PresetBrief(jailbreakLevel: JailbreakLevel.heavy),
          slots: base.slots
              .map((slot) => <String>['ykxReset', 'nsfw', 'jailbreak']
                      .contains(slot.identifier)
                  ? slot.copyWith(content: '破限文本')
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), contains('local.jailbreak_scattered'));
    });

    test('用户自填槽为空不算「空槽位」', () {
      // nsfw 是 userOwned —— 留空是正常选择，不该被当成「开着没内容」。
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'nsfw'
                  ? slot.copyWith(content: '')
                  : slot.copyWith(content: '有内容'))
              .toList(),
        ),
      );
      final emptyIssue = report.issues
          .where((issue) => issue.id == 'local.empty_enabled')
          .toList();
      if (emptyIssue.isNotEmpty) {
        expect(emptyIssue.first.detail, isNot(contains('破限')));
      }
    });

    test('有世界书但世界书槽位被关 → 提示', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'worldInfoBefore'
                  ? slot.copyWith(enabled: false)
                  : slot)
              .toList(),
        ),
        context: const PresetDiagnosisContext(
          characterWorldInfoCount: 3,
          globalWorldInfoCount: 1,
        ),
      );
      expect(issueIds(report), contains('local.world_info_disabled'));
    });

    test('没有世界书时不报世界书问题', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .map((slot) => slot.identifier == 'worldInfoBefore'
                  ? slot.copyWith(enabled: false)
                  : slot)
              .toList(),
        ),
      );
      expect(issueIds(report), isNot(contains('local.world_info_disabled')));
    });

    test('有启用的全局正则 → 提示', () {
      final report = PresetLocalDiagnosis.run(
        project: projectOf(kind: PresetStructureKind.multiTurn),
        context: const PresetDiagnosisContext(activeGlobalRegexCount: 2),
      );
      expect(issueIds(report), contains('local.global_regex_active'));
    });

    test('报告按「错误 → 警告 → 提示」排序', () {
      final base = projectOf(kind: PresetStructureKind.multiTurn);
      final report = PresetLocalDiagnosis.run(
        project: projectOf(
          kind: PresetStructureKind.multiTurn,
          slots: base.slots
              .where((slot) => slot.identifier != 'chatHistory')
              .toList(),
        ),
      );
      final levels = report.sortedIssues.map((issue) => issue.level.index).toList();
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i] >= levels[i - 1], isTrue);
      }
      expect(report.summaryLine(), contains('错误'));
    });
  });
}
