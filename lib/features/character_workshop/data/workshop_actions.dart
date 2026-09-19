import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/card_project.dart';
import '../domain/models/check_report.dart';
import '../domain/models/design_spec.dart';
import '../domain/models/project_entry.dart';
import '../domain/models/source_material.dart';
import 'card_project_provider.dart';
import 'card_project_service.dart';
import 'material_ingest_service.dart';
import 'text_quality_scanner.dart';
import 'worldbook_packager.dart';

final workshopActionsProvider =
    Provider<WorkshopActions>((ref) => WorkshopActions(ref));

/// 工坊的动作编排层。
///
/// 把「状态机」（[CardProjectNotifier]）与「AI 调用」（[CardProjectService]）串起来，
/// 并统一管理 busy / 错误 / 流式预览。UI 只调这里的方法，不直接碰 service。
class WorkshopActions {
  WorkshopActions(this._ref);

  final Ref _ref;

  CardProjectNotifier get _projects =>
      _ref.read(cardProjectProvider.notifier);

  CardProjectService get _service =>
      _ref.read(cardProjectServiceProvider);

  MaterialIngestService get _materials => const MaterialIngestService();

  CardProject? projectOf(String id) {
    for (final project in _ref.read(cardProjectProvider).projects) {
      if (project.id == id) {
        return project;
      }
    }
    return null;
  }

  // ============================================================
  // 阶段一：需求对齐
  // ============================================================

  /// 为某个维度生成候选方案，并写进项目的 `designSpec.candidates`。
  Future<bool> generateDesignCandidates(
    String projectId,
    SpecDimension dimension, {
    String userHint = '',
  }) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }

    _projects.beginBusy('正在为「${dimension.label}」想方案…');
    try {
      final candidates = await _service.generateDesignCandidates(
        project: project,
        dimension: dimension,
        language: project.plan.language,
        userHint: userHint,
      );
      _projects.updateDesignSpec(
        projectId,
        project.designSpec.withCandidates(dimension, candidates),
      );
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.failBusy('生成失败：$error');
      return false;
    }
  }

  // ============================================================
  // 阶段二：创作规划
  // ============================================================

  /// 生成条目清单。默认**追加**到已有条目后面（不清空用户手改过的内容）。
  Future<bool> generatePlan(
    String projectId, {
    required bool replaceExisting,
    String userHint = '',
  }) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }

    _projects.beginBusy('正在制定创作规划…');
    try {
      final result = await _service.generatePlan(
        project: project,
        fieldKeys: project.plan.plannedFieldKeys,
        worldbookTarget: project.plan.worldbookTarget,
        mvuEnabled: project.plan.mvuEnabled,
        ejsEnabled: project.plan.ejsEnabled,
        language: project.plan.language,
        userHint: userHint,
      );

      var entries = replaceExisting
          ? result.entries
          : <ProjectEntry>[...project.entries, ...result.entries];

      // 保证「名称」条目一定存在 —— 它是必填项。
      final hasName = entries.any((entry) =>
          entry.kind == EntryKind.characterCard &&
          entry.fieldKey == 'name');
      if (!hasName) {
        entries = <ProjectEntry>[
          ProjectEntry(
            id: 'name_${DateTime.now().microsecondsSinceEpoch}',
            title: '名称',
            kind: EntryKind.characterCard,
            fieldKey: 'name',
            brief: '角色的名字，2~8 个字，有记忆点',
            order: 5,
          ),
          ...entries,
        ];
      }

      _projects.setEntries(projectId, entries);
      _projects.updatePlan(
        projectId,
        project.plan.copyWith(summary: result.summary),
      );
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.failBusy('生成失败：$error');
      return false;
    }
  }

  // ============================================================
  // 阶段三：逐条产出
  // ============================================================

  /// 写单条。成功返回 true。
  Future<bool> writeEntry(
    String projectId,
    String entryId, {
    String userHint = '',
  }) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }
    final entry = project.entryById(entryId);
    if (entry == null) {
      return false;
    }

    // 上下文只带已完成条目的标题与摘要（由 prompt builder 截断），不带全文。
    final completed = project.entries
        .where((item) =>
            item.id != entryId &&
            item.status == EntryStatus.done &&
            item.hasContent)
        .toList();

    _projects.setEntryStatus(projectId, entryId, EntryStatus.generating);
    _projects.beginBusy('正在写「${entry.title}」…');

    try {
      final content = await _service.writeEntry(
        project: project,
        entry: entry,
        completed: completed,
        length: project.plan.length,
        language: project.plan.language,
        userHint: userHint,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );

      _projects.setEntryContent(projectId, entryId, content);
      _projects.setEntryStatus(projectId, entryId, EntryStatus.done);
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.setEntryStatus(
        projectId,
        entryId,
        EntryStatus.failed,
        error: error.message,
      );
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.setEntryStatus(
        projectId,
        entryId,
        EntryStatus.failed,
        error: '$error',
      );
      _projects.failBusy('生成失败：$error');
      return false;
    }
  }

  /// 连续写完全部未完成的条目。
  ///
  /// 一条失败就停下（保留失败状态），用户可以单条重试 —— 不阻塞、不丢进度。
  Future<void> writeAllPending(String projectId) async {
    // 上限保护：避免条目状态异常时死循环。
    var guard = 0;
    while (guard < 500) {
      guard++;
      final project = projectOf(projectId);
      if (project == null) {
        return;
      }
      final next = project.firstUnsettled;
      if (next == null) {
        return;
      }
      final ok = await writeEntry(projectId, next.id);
      if (!ok) {
        return;
      }
    }
  }

  /// 跳过一条。
  void skipEntry(String projectId, String entryId) {
    _projects.setEntryStatus(projectId, entryId, EntryStatus.skipped);
  }

  /// 把一条重新标记为待生成（用于「重写」）。
  void resetEntry(String projectId, String entryId) {
    _projects.setEntryStatus(projectId, entryId, EntryStatus.pending);
  }

  // ============================================================
  // 阶段四：MVU 动态变量
  // ============================================================

  Future<bool> generateMvu(String projectId) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }

    _projects.beginBusy('正在设计动态变量…');
    try {
      final result = await _service.generateMvu(
        project: project,
        language: project.plan.language,
      );
      _projects.setMvu(
        projectId,
        schemaText: result.schema,
        initvarText: result.initvar,
        updateRulesText: result.updateRules,
        variablesJson: result.variablesJson,
      );
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.failBusy('生成失败：$error');
      return false;
    }
  }

  // ============================================================
  // 阶段四·五：前端面板
  // ============================================================

  /// 生成前端面板并写进项目。成功返回 true。
  Future<bool> generateFrontend(
    String projectId, {
    String userHint = '',
  }) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }

    _projects.beginBusy('正在设计前端面板…');
    try {
      final html = await _service.generateFrontend(
        project: project,
        language: project.plan.language,
        userHint: userHint,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );
      _projects.setFrontendHtml(projectId, html);
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.failBusy('生成失败：$error');
      return false;
    }
  }

  /// 按用户的一句话要求修改现有面板（对话式迭代）。
  ///
  /// ⛔ **不落库** —— 返回新的 HTML，由 UI 决定「预览 / 应用 / 放弃」。
  /// 直接覆盖的话，用户一句话说歪了就把好面板冲掉了。
  /// 返回 null 表示失败（错误已通过 `failBusy` 呈现）。
  Future<String?> refineFrontend(String projectId, String instruction) async {
    final project = projectOf(projectId);
    if (project == null) {
      return null;
    }
    final currentHtml = project.frontendHtml.trim();
    if (currentHtml.isEmpty || instruction.trim().isEmpty) {
      return null;
    }

    _projects.beginBusy('正在按你的要求修改面板…');
    try {
      final html = await _service.refineFrontend(
        project: project,
        language: project.plan.language,
        currentHtml: currentHtml,
        instruction: instruction,
        onDelta: _projects.pushStreamPreview,
        onStage: _projects.setBusyStage,
      );
      _projects.endBusy();
      return html;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return null;
    } catch (error) {
      _projects.failBusy('修改失败：$error');
      return null;
    }
  }

  // ============================================================
  // 材料导入
  // ============================================================

  /// 选文件并导入为材料。返回错误信息（成功时返回 null）。
  Future<String?> importMaterial(String projectId) async {
    try {
      final material = await _materials.pickAndParse();
      if (material == null) {
        return null; // 用户取消
      }
      _projects.addSource(projectId, material);
      return null;
    } catch (error) {
      return '$error';
    }
  }

  /// 把一份材料拆解成六个维度，合并进 `designSpec`。
  ///
  /// **只填空着的维度** —— 用户自己写过的答案优先级更高，不被覆盖。
  Future<String?> extractMaterial(String projectId, String sourceId) async {
    final project = projectOf(projectId);
    if (project == null) {
      return '项目不存在';
    }
    SourceMaterial? source;
    for (final item in project.sources) {
      if (item.id == sourceId) {
        source = item;
        break;
      }
    }
    if (source == null) {
      return '找不到这份材料';
    }

    final chunks = source.chunk();
    if (chunks.isEmpty) {
      return '这份材料里没有可用的文字';
    }

    source.status = MaterialStatus.extracting;
    source.error = null;
    _projects.updateSource(projectId, source);
    _projects.beginBusy('正在拆解素材（1/${chunks.length}）…');

    try {
      final results = <Map<String, String>>[];
      for (var i = 0; i < chunks.length; i++) {
        _projects.setBusyStage('正在拆解素材（${i + 1}/${chunks.length}）…');
        final extracted = await _service.extractMaterialChunk(
          projectName: project.name,
          chunk: chunks[i],
          chunkIndex: i,
          chunkTotal: chunks.length,
          language: project.plan.language,
        );
        results.add(extracted);
      }

      final merged = MaterialIngestService.mergeExtractions(results);

      // 只填空白维度。
      var spec = project.designSpec;
      for (final dimension in SpecDimension.values) {
        final value = merged[dimension.key]?.trim() ?? '';
        if (value.isEmpty) {
          continue;
        }
        if (spec.answerOf(dimension).isNotEmpty) {
          continue;
        }
        spec = spec.withAnswer(dimension, value);
      }

      _projects.updateDesignSpec(projectId, spec);
      source.status = MaterialStatus.done;
      source.error = null;
      _projects.updateSource(projectId, source);
      _projects.endBusy();
      return null;
    } on WorkshopException catch (error) {
      source.status = MaterialStatus.failed;
      source.error = error.message;
      _projects.updateSource(projectId, source);
      _projects.failBusy(error.message, raw: error.rawOutput);
      return error.message;
    } catch (error) {
      source.status = MaterialStatus.failed;
      source.error = '$error';
      _projects.updateSource(projectId, source);
      _projects.failBusy('拆解失败：$error');
      return '$error';
    }
  }

  // ============================================================
  // 质检
  // ============================================================

  /// 跑一次本地质检。**不消耗任何 API 额度。**
  Future<void> runCheck(String projectId) async {
    final project = projectOf(projectId);
    if (project == null) {
      return;
    }
    final report = TextQualityScanner.scan(project);

    // 本地重扫时**保留** AI 复核的结果 —— 它们是上一次复核留下的，
    // 还没被处理掉，不该因为点了一次「重新扫描」就凭空消失。
    final aiIssues = project.lastCheck?.issues
            .where((issue) => issue.source == CheckSource.ai)
            .toList(growable: false) ??
        const <CheckIssue>[];

    _projects.setCheckReport(
      projectId,
      CheckReport(
        issues: <CheckIssue>[...report.issues, ...aiIssues],
        createdAt: report.createdAt,
      ),
    );
  }

  /// AI 复核（**手动触发**，约 2~4k token）。
  ///
  /// 本地规则读不懂设定语义，这一段补上「人设走形 / 前后矛盾 / 变量与设定冲突」。
  /// 默认不自动跑 —— 用户明确要求省 token。
  Future<bool> runAiReview(String projectId) async {
    final project = projectOf(projectId);
    if (project == null) {
      return false;
    }

    final localIssues = project.lastCheck?.issues
            .where((issue) => issue.source == CheckSource.local)
            .toList(growable: false) ??
        const <CheckIssue>[];

    _projects.beginBusy('正在通读设定找矛盾…');
    try {
      final aiIssues = await _service.reviewCard(
        project: project,
        language: project.plan.language,
        localIssues: localIssues,
        onStage: _projects.setBusyStage,
      );
      _projects.setCheckReport(
        projectId,
        CheckReport(
          issues: <CheckIssue>[...localIssues, ...aiIssues],
          createdAt: DateTime.now(),
        ),
      );
      _projects.endBusy();
      return true;
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return false;
    } catch (error) {
      _projects.failBusy('AI 复核失败：$error');
      return false;
    }
  }

  // ============================================================
  // 质检：逐条修复
  // ============================================================

  /// 按一条质检意见修复对应条目。
  ///
  /// ⛔ **不落库** —— 返回前后对比交给 UI 做 diff 预览，用户点「应用」才写回。
  /// 直接覆盖的话，用户连模型改成了什么样都不知道。
  Future<IssueRepair?> repairIssue(String projectId, String issueId) async {
    final project = projectOf(projectId);
    if (project == null) {
      return null;
    }
    final report = project.lastCheck;
    if (report == null) {
      return null;
    }

    CheckIssue? issue;
    for (final item in report.issues) {
      if (item.id == issueId) {
        issue = item;
        break;
      }
    }
    if (issue == null || issue.entryId == null) {
      return null;
    }

    final entry = project.entryById(issue.entryId!);
    if (entry == null) {
      return null;
    }
    final before = entry.content.trim();
    if (before.isEmpty) {
      return null;
    }

    _projects.beginBusy('正在修复「${entry.title}」…');
    try {
      final after = await _service.repairIssue(
        project: project,
        language: project.plan.language,
        issue: issue,
        entryTitle: entry.title,
        currentContent: before,
        isFrontend: entry.kind == EntryKind.frontend,
      );
      _projects.endBusy();
      return IssueRepair(
        issue: issue,
        entryId: entry.id,
        entryTitle: entry.title,
        before: before,
        after: after,
      );
    } on WorkshopException catch (error) {
      _projects.failBusy(error.message, raw: error.rawOutput);
      return null;
    } catch (error) {
      _projects.failBusy('修复失败：$error');
      return null;
    }
  }

  /// 应用一次修复：写入内容 + `revision + 1` + **自动重跑本地质检**。
  ///
  /// 自动复检是「收敛反馈」的关键 —— 改完立刻能看到问题少了一条，
  /// 而不是要用户自己记得再点一次扫描。
  Future<void> applyRepair(String projectId, IssueRepair repair) async {
    _projects.setEntryContent(projectId, repair.entryId, repair.after);
    _projects.bumpEntryRevision(projectId, repair.entryId);
    await runCheck(projectId);
  }

  // ============================================================
  // 导出
  // ============================================================

  /// 预览打包结果（不落库），用于导出页展示。
  PackedCard? previewPack(String projectId) {
    final project = projectOf(projectId);
    if (project == null) {
      return null;
    }
    return WorldbookPackager.pack(
      project,
      existingCharacterId: project.exportedCharacterId,
    );
  }
}

/// 一次「逐条修复」的产物。
///
/// 拿在手里的是**前后两份完整文本** —— UI 用它算 diff 给用户看，
/// 用户确认后才调 `applyRepair` 写回。
class IssueRepair {
  const IssueRepair({
    required this.issue,
    required this.entryId,
    required this.entryTitle,
    required this.before,
    required this.after,
  });

  /// 触发这次修复的问题。
  final CheckIssue issue;

  final String entryId;
  final String entryTitle;

  /// 修复前的内容。
  final String before;

  /// 模型给出的完整替换内容。
  final String after;

  bool get changed => before.trim() != after.trim();
}
