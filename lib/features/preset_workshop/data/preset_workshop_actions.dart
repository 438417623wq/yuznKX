import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../character/data/character_provider.dart';
import '../../presets/data/preset_provider.dart';
import '../../presets/domain/models/preset.dart';
import '../../regex/data/regex_provider.dart';
import '../../world_info/data/world_info_provider.dart';
import '../domain/models/preset_diagnosis.dart';
import '../domain/models/preset_project.dart';
import '../domain/preset_local_diagnosis.dart';
import '../domain/preset_slot_catalog.dart';
import 'preset_packager.dart';
import 'preset_project_provider.dart';
import 'preset_prompt_builder.dart';
import 'preset_workshop_service.dart';

final presetWorkshopActionsProvider =
    Provider<PresetWorkshopActions>((ref) => PresetWorkshopActions(ref));

/// 预设工坊的编排层：把「服务层（AI 调用）」和「状态层（provider）」缝起来。
///
/// 界面只调这里的方法，不直接碰 service 或 provider 的写操作 ——
/// 这样 busy / 流式 / 错误处理只有一处实现。
class PresetWorkshopActions {
  PresetWorkshopActions(this._ref);

  final Ref _ref;

  PresetWorkshopService get _service =>
      _ref.read(presetWorkshopServiceProvider);

  PresetProjectNotifier get _projects =>
      _ref.read(presetProjectProvider.notifier);

  PresetProject? _project(String id) => _ref.read(presetProjectByIdProvider(id));

  // ============================================================
  // 填充内容
  // ============================================================

  /// 生成全部可写槽位的内容。
  ///
  /// 返回是否成功。失败信息已写进 state.error，界面直接展示即可。
  Future<bool> generateSlots(String projectId) async {
    final project = _project(projectId);
    if (project == null) {
      return false;
    }
    final targets = PresetPromptBuilder.editableSlots(project);
    if (targets.isEmpty) {
      _projects.failBusy('没有需要生成的槽位 —— 它们要么是引擎填充的，要么由你自己写。');
      return false;
    }

    _projects.beginBusy('正在写各槽位的提示词…');
    try {
      final contents = await _service.generateSlots(
        project: project,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );

      // ⛔ 只写「本次让它写的那些槽位」—— 模型偶尔会自作主张多给几个，
      // 多出来的如果恰好是引擎 marker 槽或用户自填槽，会把结构弄坏。
      final allowed = targets.map((slot) => slot.identifier).toSet();
      _projects.applyContents(projectId, contents, onlyIdentifiers: allowed);

      final missing = allowed
          .where((identifier) => !contents.containsKey(identifier))
          .toList(growable: false);
      _projects.endBusy();

      // 生成完就该在「填充内容」阶段了。
      if (project.stage == PresetStage.brief ||
          project.stage == PresetStage.structure) {
        _projects.setStage(projectId, PresetStage.slots);
      }

      if (missing.isNotEmpty) {
        _projects.failBusy(
          '有 ${missing.length} 个槽位没拿到内容，可以单独重新生成：'
          '${missing.map(slotLabelOf).join("、")}',
        );
        return false;
      }
      return true;
    } catch (error) {
      _fail(error);
      return false;
    }
  }

  /// 重写单个槽位。
  Future<bool> regenerateSlot(
    String projectId,
    String identifier, {
    String userHint = '',
  }) async {
    final project = _project(projectId);
    final slot = project?.slotOf(identifier);
    if (project == null || slot == null) {
      return false;
    }
    if (slot.userOwned) {
      _projects.failBusy('「${slot.label}」是你自己填的槽位，AI 不会代写。');
      return false;
    }
    if (slot.marker) {
      _projects.failBusy('「${slot.label}」的内容由引擎填充，不需要写。');
      return false;
    }

    _projects.beginBusy('正在重写「${slot.label}」…');
    try {
      final content = await _service.regenerateSlot(
        project: project,
        slot: slot,
        userHint: userHint,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );
      _projects.applyContents(
        projectId,
        <String, String>{identifier: content},
        onlyIdentifiers: <String>{identifier},
      );
      _projects.endBusy();
      return true;
    } catch (error) {
      _fail(error);
      return false;
    }
  }

  // ============================================================
  // 对话式微调
  // ============================================================

  /// 按自然语言要求改预设。
  ///
  /// 返回模型的一句话说明（界面拿去显示），失败返回 null。
  Future<PresetRefineResult?> refine(
    String projectId,
    String instruction, {
    String? focusSlotIdentifier,
  }) async {
    final project = _project(projectId);
    if (project == null || instruction.trim().isEmpty) {
      return null;
    }

    _projects.beginBusy('正在按你的要求修改…');
    try {
      final result = await _service.refine(
        project: project,
        instruction: instruction,
        focusSlotIdentifier: focusSlotIdentifier,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );

      // 模型说改了但实际一个槽位都没给 —— 提示一下，别让用户以为成功了。
      if (result.slots.isEmpty) {
        _projects.endBusy();
        _projects.failBusy(
          result.reply.isEmpty
              ? '模型没有改动任何槽位。可以把要求说得更具体一些。'
              : '模型回复：${result.reply}\n（但没有改动任何槽位）',
        );
        return result;
      }

      // 同样只允许它改「可写槽位」。
      final allowed = PresetPromptBuilder.editableSlots(project)
          .map((slot) => slot.identifier)
          .toSet();
      _projects.applyContents(projectId, result.slots, onlyIdentifiers: allowed);
      _projects.endBusy();
      return result;
    } catch (error) {
      _fail(error);
      return null;
    }
  }

  // ============================================================
  // 诊断
  // ============================================================

  /// 跑诊断。[withAi] 为真时先跑本地规则、再叠加 AI 复核。
  Future<void> runDiagnosis(String projectId, {bool withAi = false}) async {
    final project = _project(projectId);
    if (project == null) {
      return;
    }

    final context = diagnosisContext();
    final local = PresetLocalDiagnosis.run(project: project, context: context);

    if (!withAi) {
      _projects.setDiagnosis(projectId, local);
      return;
    }

    _projects.beginBusy('正在让 AI 复核语义层…');
    try {
      final aiIssues = await _service.review(
        project: project,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );
      _projects.setDiagnosis(
        projectId,
        PresetDiagnosisReport(
          issues: <PresetDiagnosisIssue>[...local.issues, ...aiIssues],
          ranAt: DateTime.now(),
          aiReviewRequested: true,
        ),
      );
      _projects.endBusy();
    } catch (error) {
      // AI 复核失败不该让本地诊断结果也丢掉。
      _projects.setDiagnosis(
        projectId,
        PresetDiagnosisReport(
          issues: local.issues,
          ranAt: local.ranAt,
          aiReviewRequested: false,
        ),
      );
      _fail(error);
    }
  }

  /// 让 AI 修一条问题，返回 diff（不落盘 —— 等用户确认）。
  Future<PresetSlotRepair?> repairIssue(
    String projectId,
    PresetDiagnosisIssue issue,
  ) async {
    final project = _project(projectId);
    if (project == null) {
      return null;
    }

    // 整体性问题（没挂到具体槽位）AI 改不了 —— 只能给操作建议。
    final identifier = issue.slotIdentifier;
    if (identifier == null || identifier.trim().isEmpty) {
      _projects.failBusy('这条问题是结构层的，需要你在结构排布里手动调整，AI 改不了。');
      return null;
    }

    final slot = project.slotOf(identifier);
    if (slot == null) {
      _projects.failBusy('找不到槽位「$identifier」，可能已经被删掉了。');
      return null;
    }
    if (slot.userOwned) {
      _projects.failBusy('「${slot.label}」是你自己填的槽位，AI 不会代写。');
      return null;
    }
    if (slot.marker) {
      _projects.failBusy('「${slot.label}」的内容由引擎填充，改这里没有意义。');
      return null;
    }

    _projects.beginBusy('正在修「${slot.label}」…');
    try {
      final after = await _service.repairSlot(
        project: project,
        slot: slot,
        issue: issue,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );
      _projects.endBusy();
      return PresetSlotRepair(
        issue: issue,
        slotIdentifier: slot.identifier,
        slotLabel: slot.label,
        before: slot.content,
        after: after,
      );
    } catch (error) {
      _fail(error);
      return null;
    }
  }

  /// 应用一条修复（用户已在 diff 弹窗里确认）。
  void applyRepair(String projectId, PresetSlotRepair repair) {
    _projects.applyContents(
      projectId,
      <String, String>{repair.slotIdentifier: repair.after},
      onlyIdentifiers: <String>{repair.slotIdentifier},
    );
  }

  /// 诊断需要的外部上下文（世界书 / 正则的启用情况）。
  ///
  /// 读失败一律当 0 —— 诊断是辅助功能，不该因为读不到数据就崩。
  PresetDiagnosisContext diagnosisContext() {
    var characterWorldInfoCount = 0;
    try {
      final character = _ref.read(activeCharacterProvider);
      final bookId = character?.characterBookId;
      if (bookId != null && bookId.isNotEmpty) {
        final books = _ref.read(worldInfoProvider);
        for (final book in books) {
          if (book.id == bookId && !book.disabled) {
            characterWorldInfoCount = book.entries.length;
            break;
          }
        }
      }
    } catch (_) {
      // 忽略。
    }

    var globalWorldInfoCount = 0;
    try {
      globalWorldInfoCount = _ref.read(activeWorldInfoIdsProvider).length;
    } catch (_) {
      // 忽略。
    }

    var activeGlobalRegexCount = 0;
    try {
      activeGlobalRegexCount = _ref.read(activeRegexScriptIdsProvider).length;
    } catch (_) {
      // 忽略。
    }

    return PresetDiagnosisContext(
      characterWorldInfoCount: characterWorldInfoCount,
      globalWorldInfoCount: globalWorldInfoCount,
      activeGlobalRegexCount: activeGlobalRegexCount,
    );
  }

  // ============================================================
  // 导出
  // ============================================================

  /// 打包并写入预设列表。
  ///
  /// **不会自动启用** —— 用户正在聊天时把预设换掉太突兀，
  /// 界面负责提示「已导出，去预设列表启用」。
  ///
  /// 重复导出是幂等的：会覆盖同一个 [Preset.id]。
  Future<Preset?> export(String projectId) async {
    final project = _project(projectId);
    if (project == null) {
      return null;
    }

    final packed = PresetPackager.build(
      project: project,
      presetId: project.exportedPresetId,
      name: project.name,
    );
    final preset = PresetPackager.applyBriefParameters(
      packed.preset,
      project.brief,
    );

    await _ref.read(presetsProvider.notifier).save(preset);
    _projects.markExported(projectId, preset.id);
    _projects.setStage(projectId, PresetStage.done);

    if (!packed.isClean) {
      _projects.failBusy(
        '已导出，但有 ${packed.missingIdentifiers.length} 个引擎槽位是自动补的'
        '（已设为关闭）：${packed.missingIdentifiers.join("、")}',
      );
    }
    return preset;
  }

  /// 导出自检 —— 模拟「存盘 → 读回」，确认顺序与开关没被引擎改掉。
  PresetRoundTripReport verifyExport(String projectId) {
    final project = _project(projectId);
    if (project == null) {
      return const PresetRoundTripReport(
        addedIdentifiers: <String>[],
        orderPreserved: false,
        enabledBefore: <String>[],
        enabledAfter: <String>[],
        totalBefore: 0,
        totalAfter: 0,
      );
    }
    final packed = PresetPackager.build(project: project);
    return PresetPackager.verifyRoundTrip(packed.preset);
  }

  // ============================================================
  // 反向导入
  // ============================================================

  /// 从已有预设建一个工坊项目。
  Future<PresetProject> importFromPreset(Preset preset) async {
    final slots = PresetPackager.toSlots(preset);
    final project = PresetProject(
      id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
      name: preset.name.trim().isEmpty ? '导入的预设' : preset.name.trim(),
      stage: PresetStage.slots,
      structureKind: PresetPackager.inferStructureKind(slots),
      slots: slots,
      importedFromPresetId: preset.id,
    );
    _projects.addProject(project);
    return project;
  }

  // ============================================================

  void _fail(Object error) {
    if (error is PresetWorkshopException) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return;
    }
    _projects.failBusy(error.toString());
  }
}
