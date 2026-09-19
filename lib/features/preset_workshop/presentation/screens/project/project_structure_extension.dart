part of '../preset_project_screen.dart';

/// 阶段二：结构排布。
///
/// **这一屏是工坊的核心。** 思路文档的原话是「先设定 role，
/// 然后调整 role 的位置与优先级关系，调好之后这就是你的预设结构，
/// 最后围绕结构编辑提示词」—— 所以这里一个字的提示词都不写，
/// 只决定「有哪些槽位、各自什么 role、谁在前谁在后」。
extension _PresetStructureStage on _PresetProjectScreenState {
  List<Widget> _buildStructureStage(
    PresetProject project,
    PresetProjectState state,
  ) {
    return <Widget>[
      _buildStructureKindCard(project),
      const SizedBox(height: 12),
      _buildStructureSummaryCard(project),
      const SizedBox(height: 12),
      _buildSlotOrderCard(project),
      const SizedBox(height: 12),
      _buildHistoryCard(project),
    ];
  }

  // --- 结构类型 ---

  Widget _buildStructureKindCard(PresetProject project) {
    return WorkshopWidgets.card(
      title: '结构类型',
      accentColor: kPresetAccent,
      subtitle: '两种都能用，区别只在 role 怎么排。切换不会丢内容 —— '
          '已有槽位的正文会按标识带过去。',
      children: [
        for (final kind in PresetStructureKind.values)
          _structureKindOption(project, kind),
        const SizedBox(height: 6),
        WorkshopWidgets.secondaryButton(
          label: '按当前需求重建骨架',
          icon: Icons.refresh,
          onPressed: () => _rebuildStructure(project),
        ),
      ],
    );
  }

  Widget _structureKindOption(PresetProject project, PresetStructureKind kind) {
    final selected = project.structureKind == kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: selected ? null : () => _switchStructure(project, kind),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected
                ? WorkshopColors.accentSoft
                : WorkshopColors.surfaceSoft,
            borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
            border: Border.all(
              color: selected ? kPresetAccent : WorkshopColors.stroke,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: selected ? kPresetAccent : WorkshopColors.textHint,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    kind.label,
                    style: TextStyle(
                      color: selected
                          ? WorkshopColors.textPrimary
                          : WorkshopColors.textSecondary,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (kind == PresetStructureKind.multiTurn) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: WorkshopColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '默认',
                        style: TextStyle(
                          color: WorkshopColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  kind.description,
                  style: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchStructure(
    PresetProject project,
    PresetStructureKind kind,
  ) async {
    final added = PresetStructureTemplates.addedBySwitch(
      project.structureKind,
      kind,
    );
    final disabled = PresetStructureTemplates.disabledBySwitch(
      project.structureKind,
      kind,
    );
    final notes = <String>[];
    if (added.isNotEmpty) {
      notes.add('新增槽位：${added.map(_labelOf).join("、")}');
    }
    if (disabled.isNotEmpty) {
      notes.add('将变为关闭：${disabled.map(_labelOf).join("、")}');
    }

    final ok = await _confirm(
      title: '切换到「${kind.label}」？',
      message: notes.isEmpty
          ? '槽位结构会重新排布，已有内容会按标识保留。'
          : '${notes.join("\n")}\n\n已有内容会按标识保留，切之前会自动存一版快照。',
      confirmLabel: '切换',
    );
    if (!ok) {
      return;
    }
    ref.read(presetProjectProvider.notifier).setStructure(project.id, kind);
  }

  Future<void> _rebuildStructure(PresetProject project) async {
    final ok = await _confirm(
      title: '重建骨架？',
      message: '会按当前需求重新排一遍槽位（比如破限档位变了，'
          '【重置】槽位的默认开关会跟着变）。\n已有内容会按标识保留。',
      confirmLabel: '重建',
    );
    if (!ok) {
      return;
    }
    ref.read(presetProjectProvider.notifier).rebuildStructure(project.id);
  }

  // --- 结构摘要 ---

  Widget _buildStructureSummaryCard(PresetProject project) {
    final enabled = project.enabledSlots;
    final roles = project.enabledRoleSequence;
    final markerCount = project.historyMarkerCount;

    return WorkshopWidgets.card(
      title: '结构体检',
      accentColor: kPresetAccent,
      children: [
        _summaryRow('启用槽位', '${enabled.length} / ${project.slots.length}'),
        _summaryRow('历史标记', markerCount == 1 ? '1 个 ✓' : '$markerCount 个 ⚠️'),
        _summaryRow('内容总量', '${project.contentLength} 字'),
        const SizedBox(height: 10),
        WorkshopWidgets.sectionLabel('启用槽位的 role 序列'),
        const SizedBox(height: 8),
        if (roles.isEmpty)
          const Text(
            '（没有启用任何槽位）',
            style: TextStyle(color: WorkshopColors.textHint, fontSize: 11),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < enabled.length; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _roleColor(roles[i]).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _roleColor(roles[i]),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '${i + 1}. ${_roleLabel(roles[i])}',
                    style: TextStyle(
                      color: _roleColor(roles[i]),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        if (enabled.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            roles.last == 'assistant'
                ? '末尾是 assistant —— prefill 成立，模型会直接接着写。'
                : '末尾不是 assistant —— 没有 prefill 效果。'
                    '（单块结构本来就如此；多轮结构建议改一下）',
            style: TextStyle(
              color: roles.last == 'assistant'
                  ? WorkshopColors.success
                  : WorkshopColors.textHint,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- 槽位顺序 ---

  Widget _buildSlotOrderCard(PresetProject project) {
    return WorkshopWidgets.card(
      title: '槽位顺序',
      accentColor: kPresetAccent,
      subtitle: '顺序就是最终发给模型的消息顺序。长按可拖拽，'
          '也可以用右侧箭头微调。',
      trailing: GestureDetector(
        onTap: () => _addCustomSlot(project),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: WorkshopColors.surfaceSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: WorkshopColors.stroke, width: 0.8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 13, color: WorkshopColors.textSecondary),
              SizedBox(width: 4),
              Text(
                '加槽位',
                style: TextStyle(
                  color: WorkshopColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
      children: [
        if (project.slots.isEmpty)
          WorkshopWidgets.emptyHint('还没有槽位。点上面的「按当前需求重建骨架」生成。')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: project.slots.length,
            onReorder: (oldIndex, newIndex) {
              final slot = project.slots[oldIndex];
              // ReorderableListView 给的 newIndex 是「插入前」的下标，
              // 往下拖时要减一才是最终位置。
              final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
              ref
                  .read(presetProjectProvider.notifier)
                  .reorderSlot(project.id, slot.identifier, target);
            },
            itemBuilder: (context, index) {
              final slot = project.slots[index];
              return ReorderableDragStartListener(
                key: ValueKey<String>(slot.identifier),
                index: index,
                child: _slotRow(project, slot, index),
              );
            },
          ),
      ],
    );
  }

  Widget _slotRow(PresetProject project, PresetSlot slot, int index) {
    final roleColor = _roleColor(slot.role);
    final dim = !slot.enabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: dim ? WorkshopColors.surfaceSunken : WorkshopColors.surfaceSoft,
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        border: Border.all(
          color: slot.isCustom ? kPresetAccent : WorkshopColors.stroke,
          width: slot.isCustom ? 1 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _roleLabel(slot.role),
                  style: TextStyle(color: roleColor, fontSize: 9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slot.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dim
                        ? WorkshopColors.textHint
                        : WorkshopColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (slot.marker)
                _miniTag('引擎填', WorkshopColors.textHint),
              if (slot.userOwned)
                _miniTag('你填', WorkshopColors.warning),
              if (slot.locked)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.lock, size: 11, color: WorkshopColors.textHint),
                ),
              Switch(
                value: slot.enabled,
                activeThumbColor: kPresetAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: slot.identifier == 'chatHistory'
                    ? null
                    : (value) => ref
                        .read(presetProjectProvider.notifier)
                        .setSlotEnabled(project.id, slot.identifier, value),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    slot.hasContent
                        ? '${slot.content.trim().length} 字：'
                            '${slot.content.trim().replaceAll(RegExp(r"\s+"), " ")}'
                        : (slot.marker
                            ? '内容由引擎填充'
                            : (slot.userOwned ? '留空也可以，由你自己填' : '（还没写内容）')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                ),
                _iconAction(
                  Icons.arrow_upward,
                  index == 0
                      ? null
                      : () => ref
                          .read(presetProjectProvider.notifier)
                          .moveSlot(project.id, slot.identifier, -1),
                ),
                _iconAction(
                  Icons.arrow_downward,
                  index == project.slots.length - 1
                      ? null
                      : () => ref
                          .read(presetProjectProvider.notifier)
                          .moveSlot(project.id, slot.identifier, 1),
                ),
                _iconAction(Icons.tune, () => _showSlotMenu(project, slot)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 9)),
      ),
    );
  }

  Widget _iconAction(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Icon(
          icon,
          size: 15,
          color: onTap == null
              ? WorkshopColors.stroke
              : WorkshopColors.textSecondary,
        ),
      ),
    );
  }

  /// 单个槽位的操作菜单（改 role / 改名 / 删除）。
  Future<void> _showSlotMenu(PresetProject project, PresetSlot slot) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkshopColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.label,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    slot.identifier,
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: WorkshopColors.strokeSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WorkshopWidgets.sectionLabel('role'),
                  const SizedBox(height: 8),
                  WorkshopWidgets.segmentedRow<String>(
                    values: const <String>['system', 'user', 'assistant'],
                    selected: slot.role,
                    enabled: !slot.locked,
                    label: (value) => _roleLabel(value),
                    onChanged: (value) {
                      Navigator.pop(sheetContext);
                      ref
                          .read(presetProjectProvider.notifier)
                          .setSlotRole(project.id, slot.identifier, value);
                    },
                  ),
                  if (slot.locked)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '这个槽位是锁定的（位置标记），role 改了没有意义。',
                        style: TextStyle(
                          color: WorkshopColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit,
                  size: 18, color: WorkshopColors.textSecondary),
              title: const Text(
                '改显示名',
                style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 13),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _renameSlot(project, slot);
              },
            ),
            if (!isEngineSlot(slot.identifier))
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    size: 18, color: WorkshopColors.danger),
                title: const Text(
                  '删除这个槽位',
                  style: TextStyle(color: WorkshopColors.danger, fontSize: 13),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final ok = await _confirm(
                    title: '删除「${slot.label}」？',
                    message: '内容会一起删掉，不能撤销（可以在下面的历史里回滚）。',
                    confirmLabel: '删除',
                  );
                  if (!ok) {
                    return;
                  }
                  final removed = ref
                      .read(presetProjectProvider.notifier)
                      .removeSlot(project.id, slot.identifier);
                  if (!removed) {
                    _notify('引擎自带的槽位不能删除，只能关闭。');
                  }
                },
              )
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  '⛔ 引擎自带的 21 个槽位不能删除 —— 删了存盘读回时会被引擎'
                  '以「默认开启」补回来，反而破坏 prefill。只能关闭。',
                  style: TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 10,
                    height: 1.6,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    refresh();
  }

  Future<void> _renameSlot(PresetProject project, PresetSlot slot) async {
    final controller = TextEditingController(text: slot.label);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '改显示名',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration('显示名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      ref
          .read(presetProjectProvider.notifier)
          .setSlotLabel(project.id, slot.identifier, result);
    }
  }

  Future<void> _addCustomSlot(PresetProject project) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '加一个自定义槽位',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration('显示名，例如「临时事件」'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) {
      return;
    }
    ref.read(presetProjectProvider.notifier).addCustomSlot(
          project.id,
          label: result,
        );
  }

  // --- 历史快照 ---

  Widget _buildHistoryCard(PresetProject project) {
    if (project.history.isEmpty) {
      return const SizedBox.shrink();
    }
    return WorkshopWidgets.card(
      title: '版本快照',
      accentColor: WorkshopColors.textHint,
      subtitle: '每次 AI 批量改写前都会自动存一版，最多留 '
          '${PresetProject.maxHistory} 版。',
      children: [
        for (var i = 0; i < project.history.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${project.history[i].label} · '
                    '${formatWorkshopTime(project.history[i].at)}',
                    style: const TextStyle(
                      color: WorkshopColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await _confirm(
                      title: '回滚到这一版？',
                      message: '当前内容会被替换掉（回滚本身也会存一版快照，可以再滚回来）。',
                      confirmLabel: '回滚',
                    );
                    if (ok) {
                      ref
                          .read(presetProjectProvider.notifier)
                          .restoreVersion(project.id, i);
                    }
                  },
                  child: const Text('回滚', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- role 显示 ---

  Color _roleColor(String role) {
    switch (role) {
      case 'user':
        return WorkshopColors.accent;
      case 'assistant':
        return WorkshopColors.stageDone;
      default:
        return WorkshopColors.textSecondary;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'user':
        return 'user';
      case 'assistant':
        return 'assistant';
      default:
        return 'system';
    }
  }
}
