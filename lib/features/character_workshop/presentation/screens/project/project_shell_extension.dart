part of '../project_screen.dart';

/// 工作台外壳：阶段进度条、运行态提示、底部主操作栏。
extension _ProjectShellExtension on _ProjectScreenState {
  // ============================================================
  // 阶段进度条
  // ============================================================

  Widget _buildStageBar(CardProject project, bool busy) {
    final current = project.stage.index0;

    return Container(
      color: WorkshopColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      child: Row(
        children: [
          for (var i = 0; i < ProjectStage.values.length; i++)
            Expanded(
              child: GestureDetector(
                // 生成中不允许切阶段，避免状态错乱。
                onTap: busy ? null : () => _goToStage(project, ProjectStage.values[i]),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == 0
                                ? Colors.transparent
                                : (i <= current
                                    ? WorkshopColors.stageDone
                                    : WorkshopColors.strokeSoft),
                          ),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < current
                                ? WorkshopColors.stageDone
                                : (i == current
                                    ? WorkshopColors.accent
                                    : WorkshopColors.surfaceSoft),
                            border: Border.all(
                              color: i <= current
                                  ? (i == current
                                      ? WorkshopColors.accent
                                      : WorkshopColors.stageDone)
                                  : WorkshopColors.stroke,
                              width: 1,
                            ),
                          ),
                          child: i < current
                              ? const Icon(Icons.check,
                                  size: 12, color: Color(0xFF0E2A20))
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: i == current
                                        ? const Color(0xFF10142B)
                                        : WorkshopColors.textHint,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == ProjectStage.values.length - 1
                                ? Colors.transparent
                                : (i < current
                                    ? WorkshopColors.stageDone
                                    : WorkshopColors.strokeSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      ProjectStage.values[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i == current
                            ? WorkshopColors.textPrimary
                            : (i < current
                                ? WorkshopColors.textSecondary
                                : WorkshopColors.textHint),
                        fontSize: 10,
                        fontWeight: i == current
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 运行态提示（流式预览）
  // ============================================================

  Widget _buildBusyBar(CardProjectState state) {
    return Container(
      width: double.infinity,
      color: WorkshopColors.accentSoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(WorkshopColors.accent),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  state.busyStage.isEmpty ? '处理中…' : state.busyStage,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (state.streamPreview.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 90),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: WorkshopColors.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  state.streamPreview,
                  style: const TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 底部主操作栏
  // ============================================================

  Widget _buildActionBar(CardProject project, CardProjectState state) {
    final busy = state.busy;

    return Container(
      decoration: const BoxDecoration(
        color: WorkshopColors.surface,
        border: Border(
          top: BorderSide(color: WorkshopColors.strokeSoft, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_hasConnection)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '没有可用的 API 连接，去「设置 → API 连接」配置一个',
                  style: TextStyle(
                    color: WorkshopColors.warning,
                    fontSize: 11,
                  ),
                ),
              ),
            _buildPrimaryAction(project, busy),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(CardProject project, bool busy) {
    switch (project.stage) {
      case ProjectStage.design:
        final complete = project.designSpec.isComplete;
        return WorkshopWidgets.primaryButton(
          label: complete
              ? '进入创作规划'
              : '还有 ${SpecDimension.values.length - project.designSpec.confirmedCount} 个维度没确认',
          icon: complete ? Icons.arrow_forward : null,
          busy: false,
          onPressed: busy
              ? null
              : (complete
                  ? () => _goToStage(project, ProjectStage.plan)
                  : () => _notify('先把六个维度都确认一遍，或者点「让 AI 帮我决定」')),
        );

      case ProjectStage.plan:
        final hasEntries = project.hasEntries;
        return Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '回到需求对齐',
                onPressed: busy
                    ? null
                    : () => _goToStage(project, ProjectStage.design),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: WorkshopWidgets.primaryButton(
                label: hasEntries ? '开始逐条产出' : '先生成条目清单',
                icon: Icons.arrow_forward,
                onPressed: busy
                    ? null
                    : (hasEntries
                        ? () => _goToStage(project, ProjectStage.writing)
                        : () => _notify('先点上面的「生成规划」')),
              ),
            ),
          ],
        );

      case ProjectStage.writing:
        final next = project.firstUnsettled;
        return Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '回到规划',
                onPressed:
                    busy ? null : () => _goToStage(project, ProjectStage.plan),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: WorkshopWidgets.primaryButton(
                label: next == null
                    ? '去设计前端面板'
                    : '继续写「${next.title}」',
                icon: Icons.arrow_forward,
                onPressed: busy
                    ? null
                    : (next == null
                        ? () => _goToStage(project, ProjectStage.frontend)
                        : () => _actions.writeEntry(project.id, next.id)),
              ),
            ),
          ],
        );

      case ProjectStage.frontend:
        return Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '回到逐条产出',
                onPressed: busy
                    ? null
                    : () => _goToStage(project, ProjectStage.writing),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: WorkshopWidgets.primaryButton(
                // 前端面板是可选的，没做也能走 —— 所以「跳过」也是主操作。
                label: project.hasFrontend ? '去质检' : '跳过，直接去质检',
                icon: Icons.arrow_forward,
                onPressed: busy
                    ? null
                    : () => _goToStage(project, ProjectStage.checking),
              ),
            ),
          ],
        );

      case ProjectStage.checking:
        return Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '重新扫描',
                icon: Icons.refresh,
                onPressed: busy ? null : () => _actions.runCheck(project.id),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: WorkshopWidgets.primaryButton(
                label: '去导出',
                icon: Icons.arrow_forward,
                onPressed: busy
                    ? null
                    : () => _goToStage(project, ProjectStage.done),
              ),
            ),
          ],
        );

      case ProjectStage.done:
        return Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '回到质检',
                onPressed: busy
                    ? null
                    : () => _goToStage(project, ProjectStage.checking),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: WorkshopWidgets.primaryButton(
                label: project.exportedCharacterId == null
                    ? '保存为角色卡'
                    : '更新角色卡',
                icon: Icons.save_alt,
                background: WorkshopColors.success,
                foreground: const Color(0xFF10251A),
                onPressed: busy ? null : () => _exportToCharacter(project),
              ),
            ),
          ],
        );
    }
  }
}
