part of '../preset_project_screen.dart';

/// 阶段四：结构诊断。
///
/// 按需求锁定：**只作为工坊内的一步，不外放到预设列表**。
///
/// 两段式（沿用角色工坊 P3 的做法）：
/// - 本地规则 0 token，进页面自动跑；
/// - AI 复核手动触发，省 token。
///
/// 逐条修复复用同一条链路：`repairIssue` → 本地 LCS diff 预览 → 应用 → 自动复检。
extension _PresetDiagnoseStage on _PresetProjectScreenState {
  List<Widget> _buildDiagnoseStage(
    PresetProject project,
    PresetProjectState state,
  ) {
    final report = project.diagnosis;

    return <Widget>[
      _buildDiagnosisSummaryCard(project, state, report),
      const SizedBox(height: 12),
      _buildRoundTripCard(project),
      const SizedBox(height: 12),
      if (report.issues.isEmpty)
        WorkshopWidgets.card(
          title: '没有发现问题',
          accentColor: WorkshopColors.success,
          subtitle: report.ranAt == null
              ? '还没跑过诊断。'
              : '体检时间：${formatWorkshopTime(report.ranAt!)}'
                  '${report.aiReviewRequested ? "（含 AI 复核）" : "（仅本地规则）"}',
          children: const [
            Text(
              '本地规则主要查「静默出错」—— 漏槽位、历史标记重复、'
              '宏写错这类问题不会报错也不会崩，但预设实际已经不生效了。\n'
              '语义层（歧义、自相矛盾、指令冲突）需要手动点「让 AI 复核」。',
              style: TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ],
        )
      else
        for (final issue in report.sortedIssues) ...[
          _issueCard(project, issue),
          const SizedBox(height: 10),
        ],
    ];
  }

  // --- 摘要 ---

  Widget _buildDiagnosisSummaryCard(
    PresetProject project,
    PresetProjectState state,
    PresetDiagnosisReport report,
  ) {
    return WorkshopWidgets.card(
      title: '诊断结果',
      accentColor: report.hasBlockingIssue
          ? WorkshopColors.danger
          : (report.issues.isEmpty
              ? WorkshopColors.success
              : WorkshopColors.warning),
      subtitle: report.ranAt == null
          ? '还没跑过。'
          : '体检时间：${formatWorkshopTime(report.ranAt!)}'
              '${report.aiReviewRequested ? "（含 AI 复核）" : "（仅本地规则）"}',
      children: [
        Text(
          report.summaryLine(),
          style: TextStyle(
            color: report.hasBlockingIssue
                ? WorkshopColors.danger
                : WorkshopColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '重新体检（本地）',
                icon: Icons.fact_check_outlined,
                onPressed: state.busy
                    ? null
                    : () => _actions.runDiagnosis(project.id),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: report.aiReviewRequested ? '再让 AI 复核' : '让 AI 复核',
                icon: Icons.psychology_outlined,
                onPressed: state.busy || !_hasConnection
                    ? null
                    : () => _actions.runDiagnosis(project.id, withAi: true),
              ),
            ),
          ],
        ),
        if (!_hasConnection) ...[
          const SizedBox(height: 8),
          const Text(
            '本地规则不需要 API 连接；AI 复核需要。',
            style: TextStyle(color: WorkshopColors.textHint, fontSize: 11),
          ),
        ],
      ],
    );
  }

  // --- 导出自检 ---

  Widget _buildRoundTripCard(PresetProject project) {
    final report = _actions.verifyExport(project.id);
    final healthy = report.isHealthy;

    return WorkshopWidgets.card(
      title: '存盘读回自检',
      accentColor: healthy ? WorkshopColors.success : WorkshopColors.danger,
      subtitle: '预设存进本地后会被重新读一遍。这一步模拟那个过程，'
          '确认顺序和开关没有被引擎改动。',
      children: [
        Row(
          children: [
            Icon(
              healthy ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: healthy ? WorkshopColors.success : WorkshopColors.danger,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                report.describe(),
                style: TextStyle(
                  color: healthy
                      ? WorkshopColors.textSecondary
                      : WorkshopColors.danger,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
        if (!healthy) ...[
          const SizedBox(height: 8),
          const Text(
            '⛔ 顺序或开关被改掉会让 prefill 静默失效。'
            '点上面的「重新体检（本地）」能看到具体是哪些槽位出了问题。',
            style: TextStyle(
              color: WorkshopColors.textHint,
              fontSize: 10,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }

  // --- 单条问题 ---

  Widget _issueCard(PresetProject project, PresetDiagnosisIssue issue) {
    final tint = switch (issue.level) {
      PresetIssueLevel.error => WorkshopColors.danger,
      PresetIssueLevel.warning => WorkshopColors.warning,
      PresetIssueLevel.info => WorkshopColors.accent,
    };
    final icon = switch (issue.level) {
      PresetIssueLevel.error => Icons.error_outline,
      PresetIssueLevel.warning => Icons.warning_amber_rounded,
      PresetIssueLevel.info => Icons.info_outline,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: WorkshopColors.surface,
        borderRadius: BorderRadius.circular(WorkshopMetrics.cardRadius),
        border: Border.all(color: tint.withValues(alpha: 0.5), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _levelTag(issue.level.label, tint),
              const SizedBox(width: 4),
              _levelTag(
                issue.source.label,
                issue.source == PresetIssueSource.ai
                    ? WorkshopColors.accent
                    : WorkshopColors.textHint,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            issue.detail,
            style: const TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          if (issue.suggestion.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '建议：${issue.suggestion}',
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (issue.slotIdentifier != null)
                Expanded(
                  child: Text(
                    '槽位：${_labelOf(issue.slotIdentifier!)}',
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (issue.canRepair)
                TextButton.icon(
                  onPressed: () => _repairIssue(project, issue),
                  icon: const Icon(Icons.auto_fix_high, size: 14),
                  label: const Text('修这条', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: kPresetAccent,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => _showIssueDetail(issue),
                  icon: const Icon(Icons.tune, size: 14),
                  label: const Text('手动处理', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: WorkshopColors.textSecondary,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _levelTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9)),
    );
  }

  /// 逐条修复：AI 改 → diff 预览 → 应用 → 自动复检。
  Future<void> _repairIssue(
    PresetProject project,
    PresetDiagnosisIssue issue,
  ) async {
    final repair = await _actions.repairIssue(project.id, issue);
    if (repair == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final applied = await PresetRepairDiffDialog.show(context, repair);
    if (!applied) {
      return;
    }
    _actions.applyRepair(project.id, repair);

    // 改完立刻复检 —— 本地规则 0 token，没理由不跑。
    _actions.runDiagnosis(project.id);
    _notify('已应用，并重新体检了一遍');
    refresh();
  }
}
