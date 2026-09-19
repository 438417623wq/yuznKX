part of '../project_screen.dart';

/// 阶段四：质检。
///
/// **全部在本地完成，不消耗任何 API 额度。** 检查三块：
/// 结构完整性、设定一致性、文本质量。问题可以点击直接跳到对应条目。
extension _ProjectCheckExtension on _ProjectScreenState {
  List<Widget> _buildCheckStage(CardProject project, CardProjectState state) {
    final busy = state.busy;
    final report = project.lastCheck;

    return <Widget>[
      WorkshopWidgets.card(
        title: '⑤ 质检',
        subtitle: '两段式：本地规则（0 token）+ AI 复核（手动触发）',
        children: [
          if (report == null)
            WorkshopWidgets.emptyHint('还没扫描过。点下面的按钮跑一次。')
          else
            _buildReportSummary(project, report),
          const SizedBox(height: 12),
          WorkshopWidgets.primaryButton(
            label: report == null ? '本地扫描（0 token）' : '重新本地扫描',
            icon: Icons.search,
            busy: busy,
            onPressed: busy ? null : () => _runCheck(project),
          ),
          const SizedBox(height: 8),
          WorkshopWidgets.secondaryButton(
            label: '让 AI 复核一版',
            icon: Icons.psychology_alt_outlined,
            onPressed: busy ? null : () => _runAiReview(project),
          ),
          const SizedBox(height: 8),
          const Text(
            '本地扫描秒出、不花额度，只查结构完整性与文本质量；'
            'AI 复核会通读全部设定，能查出人设走形、前后矛盾、变量与设定冲突'
            '（约 2~4k token，手动触发）。',
            style: TextStyle(
              color: WorkshopColors.textHint,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ],
      ),
      if (report != null && report.issues.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final category in CheckCategory.values)
          ..._buildCategorySection(project, report, category, busy),
      ],
    ];
  }

  Widget _buildReportSummary(CardProject project, CheckReport report) {
    if (report.isClean) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WorkshopColors.successSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WorkshopColors.stageDone, width: 0.8),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_outlined,
                size: 16, color: WorkshopColors.stageDone),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '没有发现问题，可以直接导出了',
                style: TextStyle(
                  color: WorkshopColors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          report.summary,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '扫描于 ${formatWorkshopTime(report.createdAt)}',
          style: const TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategorySection(
    CardProject project,
    CheckReport report,
    CheckCategory category,
    bool busy,
  ) {
    final issues = report.issuesOf(category);
    if (issues.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      WorkshopWidgets.card(
        title: category.label,
        subtitle: '${issues.length} 项',
        accentColor: _categoryTint(category),
        children: [
          for (final issue in issues) _buildIssueTile(project, issue, busy),
        ],
      ),
      const SizedBox(height: 12),
    ];
  }

  Color _categoryTint(CheckCategory category) {
    switch (category) {
      case CheckCategory.structure:
        return WorkshopColors.accent;
      case CheckCategory.consistency:
        return WorkshopColors.worldbook;
      case CheckCategory.text:
        return WorkshopColors.warning;
    }
  }

  Color _severityColor(CheckSeverity severity) {
    switch (severity) {
      case CheckSeverity.error:
        return WorkshopColors.danger;
      case CheckSeverity.warning:
        return WorkshopColors.warning;
      case CheckSeverity.info:
        return WorkshopColors.textHint;
    }
  }

  Widget _buildIssueTile(CardProject project, CheckIssue issue, bool busy) {
    final color = _severityColor(issue.severity);
    final entry =
        issue.entryId == null ? null : project.entryById(issue.entryId!);
    final hasEntry = entry != null;
    final canRepair = issue.canRepair && hasEntry && !busy;

    return GestureDetector(
      onTap: hasEntry ? () => _jumpToEntry(project, issue.entryId!) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: WorkshopColors.surfaceSunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    issue.severity.label,
                    style: TextStyle(color: color, fontSize: 9),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: issue.source == CheckSource.ai
                        ? WorkshopColors.accent.withValues(alpha: 0.18)
                        : WorkshopColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    issue.source == CheckSource.ai ? 'AI' : '本地',
                    style: TextStyle(
                      color: issue.source == CheckSource.ai
                          ? WorkshopColors.accent
                          : WorkshopColors.textHint,
                      fontSize: 9,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issue.message,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                if (hasEntry)
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: WorkshopColors.textHint,
                  ),
              ],
            ),
            if (issue.suggestion != null) ...[
              const SizedBox(height: 6),
              Text(
                issue.suggestion!,
                style: const TextStyle(
                  color: WorkshopColors.textSecondary,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
            if (issue.canRepair && hasEntry) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: canRepair ? () => _repairIssue(project, issue) : null,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: WorkshopColors.accentSoft,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: canRepair
                            ? WorkshopColors.accent
                            : WorkshopColors.stroke,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.build_outlined,
                          size: 13,
                          color: canRepair
                              ? WorkshopColors.accent
                              : WorkshopColors.textHint,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '修这条',
                          style: TextStyle(
                            color: canRepair
                                ? WorkshopColors.accent
                                : WorkshopColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 跳到出问题的条目：切到写作阶段并展开它。
  void _jumpToEntry(CardProject project, String entryId) {
    ref.read(cardProjectProvider.notifier).setStage(
          project.id,
          ProjectStage.writing,
        );
    _expandedEntryIds.add(entryId);
    if (mounted) {
      refresh();
      _notify('已跳到该条目');
    }
  }

  Future<void> _runCheck(CardProject project) async {
    await _actions.runCheck(project.id);
    if (!mounted) {
      return;
    }
    final latest = ref.read(cardProjectByIdProvider(project.id));
    final report = latest?.lastCheck;
    _notify(report == null ? '扫描完成' : report.summary);
  }

  /// AI 复核（手动触发）。
  Future<void> _runAiReview(CardProject project) async {
    await _actions.runAiReview(project.id);
    if (!mounted) {
      return;
    }
    final latest = ref.read(cardProjectByIdProvider(project.id));
    final report = latest?.lastCheck;
    if (report == null) {
      return;
    }
    final aiCount =
        report.issues.where((issue) => issue.source == CheckSource.ai).length;
    _notify(aiCount == 0 ? 'AI 复核没发现新问题' : 'AI 复核发现 $aiCount 个问题');
  }

  /// 逐条修复：让 AI 改 → 看 diff → 应用（应用后自动复检）。
  Future<void> _repairIssue(CardProject project, CheckIssue issue) async {
    final repair = await _actions.repairIssue(project.id, issue.id);
    if (!mounted || repair == null) {
      return;
    }
    if (!repair.changed) {
      _notify('模型没有改动内容');
      return;
    }
    final apply = await RepairDiffDialog.show(context, repair);
    if (!apply || !mounted) {
      return;
    }
    await _actions.applyRepair(project.id, repair);
    if (!mounted) {
      return;
    }
    _notify('已应用修复，并重新扫描了一遍');
  }
}
