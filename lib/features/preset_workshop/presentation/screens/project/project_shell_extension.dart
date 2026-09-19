part of '../preset_project_screen.dart';

/// 项目壳：阶段条、忙碌条、底部主操作栏。
///
/// 这些是五个阶段共用的框架，所以单独一个 part。
extension _PresetProjectShell on _PresetProjectScreenState {
  // --- 阶段条 ---

  Widget _buildStageBar(PresetProject project, bool busy) {
    final current = project.stage.index0;
    return Container(
      color: WorkshopColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          for (var i = 0; i < PresetStage.values.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: busy ? null : () => _goToStage(project, PresetStage.values[i]),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == PresetStage.values.length - 1 ? 0 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: i < current
                              ? WorkshopColors.stageDone
                              : (i == current
                                  ? kPresetAccent
                                  : WorkshopColors.strokeSoft),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        PresetStage.values[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == current
                              ? WorkshopColors.textPrimary
                              : (i < current
                                  ? WorkshopColors.stageDone
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
            ),
        ],
      ),
    );
  }

  // --- 忙碌条 ---

  Widget _buildBusyBar(PresetProjectState state) {
    return Container(
      width: double.infinity,
      color: WorkshopColors.surfaceSunken,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
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
          if (state.streamPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 90),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: WorkshopColors.pageBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  state.streamPreview,
                  style: const TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 10,
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

  // --- 底部主操作栏 ---

  Widget _buildActionBar(PresetProject project, PresetProjectState state) {
    final spec = _primaryAction(project);
    return Container(
      decoration: const BoxDecoration(
        color: WorkshopColors.surface,
        border: Border(top: BorderSide(color: WorkshopColors.stroke, width: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (project.stage.index0 > 0)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => _goToStage(
                            project,
                            PresetStage
                                .values[project.stage.index0 - 1],
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WorkshopColors.textSecondary,
                    side: const BorderSide(
                        color: WorkshopColors.stroke, width: 0.8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                  ),
                  child: const Icon(Icons.arrow_back, size: 16),
                ),
              ),
            Expanded(
              child: WorkshopWidgets.primaryButton(
                label: spec.label,
                icon: spec.icon,
                busy: state.busy,
                background: kPresetAccent,
                onPressed: state.busy || spec.onPressed == null
                    ? null
                    : spec.onPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _PrimaryAction _primaryAction(PresetProject project) {
    switch (project.stage) {
      case PresetStage.brief:
        return _PrimaryAction(
          label: '下一步：排布结构',
          icon: Icons.arrow_forward,
          onPressed: project.brief.isComplete
              ? () => _goToStage(project, PresetStage.structure)
              : null,
        );

      case PresetStage.structure:
        final ready = project.hasSlots;
        return _PrimaryAction(
          label: _hasConnection ? '生成各槽位内容' : '先去配置 API 连接',
          icon: _hasConnection ? Icons.auto_awesome : Icons.warning_amber_rounded,
          onPressed: !ready || !_hasConnection
              ? null
              : () async {
                  await _actions.generateSlots(project.id);
                  refresh();
                },
        );

      case PresetStage.slots:
        return _PrimaryAction(
          label: '下一步：结构诊断',
          icon: Icons.fact_check_outlined,
          onPressed: () {
            // 进诊断页先把本地规则跑一遍 —— 0 token，没理由不跑。
            _actions.runDiagnosis(project.id);
            _goToStage(project, PresetStage.diagnose);
          },
        );

      case PresetStage.diagnose:
        return _PrimaryAction(
          label: project.diagnosis.hasBlockingIssue
              ? '有错误未修，仍要导出'
              : '下一步：导出为预设',
          icon: Icons.arrow_forward,
          onPressed: () async {
            if (project.diagnosis.hasBlockingIssue) {
              final ok = await _confirm(
                title: '还有 ${project.diagnosis.errorCount} 个错误',
                message: '错误级问题会让预设跑不起来或静默失效。\n'
                    '${project.diagnosis.summaryLine()}\n\n确定要跳过它们直接导出吗？',
                confirmLabel: '仍然导出',
              );
              if (!ok) {
                return;
              }
            }
            _goToStage(project, PresetStage.done);
          },
        );

      case PresetStage.done:
        return _PrimaryAction(
          label: project.exportedPresetId == null ? '写入预设列表' : '重新写入（覆盖）',
          icon: Icons.save_alt,
          onPressed: () async {
            final preset = await _actions.export(project.id);
            if (preset != null) {
              _notify('已写入预设列表：${preset.name}');
              refresh();
            }
          },
        );
    }
  }
}

/// 底部主按钮的「该做什么」描述。
class _PrimaryAction {
  const _PrimaryAction({required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
}
