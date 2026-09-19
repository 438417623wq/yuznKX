part of '../preset_project_screen.dart';

/// 阶段五：导出。
///
/// 导出前把**最终会发给模型的消息序列**摊开给用户看一眼 ——
/// 这是整个工坊里唯一能「看到成品」的地方，也是最后一处发现结构问题的地方。
extension _PresetExportStage on _PresetProjectScreenState {
  List<Widget> _buildExportStage(
    PresetProject project,
    PresetProjectState state,
  ) {
    return <Widget>[
      _buildExportCard(project, state),
      const SizedBox(height: 12),
      _buildFinalPromptCard(project),
      const SizedBox(height: 12),
      _buildExportNotesCard(project),
    ];
  }

  // --- 导出 ---

  Widget _buildExportCard(PresetProject project, PresetProjectState state) {
    final exported = project.exportedPresetId != null;
    return WorkshopWidgets.card(
      title: exported ? '已导出' : '导出为预设',
      accentColor: exported ? WorkshopColors.success : kPresetAccent,
      subtitle: exported
          ? '重复导出是幂等的 —— 会覆盖同一个预设，不会多出一份。'
          : '写入 App 的预设列表。不会自动启用 —— '
              '你正在聊天时把预设换掉太突兀，去「设置 → 预设」里手动选。',
      children: [
        WorkshopWidgets.primaryButton(
          label: exported ? '重新写入（覆盖）' : '写入预设列表',
          icon: Icons.save_alt,
          busy: state.busy,
          background: kPresetAccent,
          onPressed: state.busy
              ? null
              : () async {
                  final preset = await _actions.export(project.id);
                  if (preset != null) {
                    _notify('已写入预设列表：${preset.name}');
                    refresh();
                  }
                },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '复制 JSON',
                icon: Icons.copy_all,
                onPressed: () {
                  final packed = PresetPackager.build(
                    project: project,
                    presetId: project.exportedPresetId,
                  );
                  final preset = PresetPackager.applyBriefParameters(
                    packed.preset,
                    project.brief,
                  );
                  _showCopyableText(
                    '预设 JSON',
                    const JsonEncoder.withIndent('  ')
                        .convert(preset.toJson()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- 最终 prompt 预览 ---

  Widget _buildFinalPromptCard(PresetProject project) {
    final enabled = project.enabledSlots;
    final merged = _mergedTurnCount(enabled);

    return WorkshopWidgets.card(
      title: '最终会发出去的消息序列',
      accentColor: kPresetAccent,
      subtitle: '顺序 = 注意力分布。顶部和底部注意力最强，中间最弱。\n'
          '在 Claude / Gemini 上，相邻的同 role user/assistant 会被合并 —— '
          '按现在的结构，${enabled.length} 个槽位会变成 $merged 条对话消息'
          '（system 全部提到系统提示里）。',
      children: [
        if (enabled.isEmpty)
          WorkshopWidgets.emptyHint('没有启用任何槽位 —— 这个预设发出去什么都没有。')
        else
          for (var i = 0; i < enabled.length; i++)
            _finalPromptRow(enabled[i], i, enabled.length),
      ],
    );
  }

  Widget _finalPromptRow(PresetSlot slot, int index, int total) {
    final roleColor = switch (slot.role) {
      'user' => WorkshopColors.accent,
      'assistant' => WorkshopColors.stageDone,
      _ => WorkshopColors.textSecondary,
    };
    final position = index == 0
        ? '顶部 · 注意力最强'
        : (index == total - 1 ? '底部 · 注意力次强' : '中部 · 注意力最弱');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 11,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              slot.role,
              style: TextStyle(color: roleColor, fontSize: 9),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.label,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    position,
                    if (slot.marker) '← 引擎注入（世界书 / 角色卡 / 历史）',
                    if (slot.userOwned) '← 你填的',
                    if (!slot.marker && !slot.hasContent) '⚠️ 空的',
                  ].join(' · '),
                  style: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 在 Claude / Gemini 上会剩下几条 user/assistant 消息。
  int _mergedTurnCount(List<PresetSlot> enabled) {
    var count = 0;
    String? lastRole;
    for (final slot in enabled) {
      if (slot.role == 'system') {
        continue;
      }
      if (slot.role != lastRole) {
        count++;
        lastRole = slot.role;
      }
    }
    return count;
  }

  // --- 导出前的最后提醒 ---

  Widget _buildExportNotesCard(PresetProject project) {
    final report = project.diagnosis;
    final notes = <String>[
      if (report.hasBlockingIssue)
        '⛔ 还有 ${report.errorCount} 个错误级问题没修（回到「结构诊断」看看）',
      if (project.historyMarkerCount != 1)
        '⛔ 历史标记有 ${project.historyMarkerCount} 个，必须恰好 1 个',
      if (project.enabledSlots.isNotEmpty &&
          project.enabledSlots.last.role != 'assistant' &&
          project.structureKind == PresetStructureKind.multiTurn)
        '⚠️ 末尾不是 assistant，没有 prefill 效果',
      if (project.slotOf('nsfw')?.hasContent == false)
        'ℹ️ 破限槽还空着 —— 这很正常，它需要按你的渠道和模型自己写',
      if (project.exportedPresetId == null)
        'ℹ️ 导出后记得去「设置 → 预设」里启用它',
    ];

    if (notes.isEmpty) {
      return WorkshopWidgets.card(
        title: '一切就绪',
        accentColor: WorkshopColors.success,
        children: const [
          Text(
            '结构、内容、诊断都过了。导出即可使用。',
            style: TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      );
    }

    return WorkshopWidgets.card(
      title: '导出前最后看一眼',
      accentColor: WorkshopColors.warning,
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              note,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
      ],
    );
  }
}
