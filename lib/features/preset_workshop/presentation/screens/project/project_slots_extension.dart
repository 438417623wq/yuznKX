part of '../preset_project_screen.dart';

/// 阶段三：填充内容。
///
/// 两种方式并存（按需求锁定的决策）：
/// - **结构向导生成的骨架**：一次生成全部可写槽位；
/// - **对话式微调**：用自然语言提要求，模型只改它认为该改的槽位。
///
/// 破限槽（`nsfw`）是 [PresetSlot.userOwned]，AI 不碰 ——
/// 它和渠道、模型强绑定，通用模板基本没用。
extension _PresetSlotsStage on _PresetProjectScreenState {
  List<Widget> _buildSlotsStage(
    PresetProject project,
    PresetProjectState state,
  ) {
    final editable = PresetPromptBuilder.editableSlots(project);
    final filled = editable.where((slot) => slot.hasContent).length;

    return <Widget>[
      WorkshopWidgets.card(
        title: '生成进度',
        accentColor: kPresetAccent,
        subtitle: '可写槽位 ${editable.length} 个，已填 $filled 个。'
            '标着「引擎填」的槽位由世界书 / 角色卡 / 聊天记录自动注入，不用管。',
        children: [
          WorkshopWidgets.progressBar(
            editable.isEmpty ? 0 : filled / editable.length,
            color: kPresetAccent,
          ),
          const SizedBox(height: 12),
          WorkshopWidgets.primaryButton(
            label: filled == 0 ? '生成全部槽位内容' : '重新生成全部（会覆盖现有内容）',
            icon: Icons.auto_awesome,
            busy: state.busy,
            background: kPresetAccent,
            onPressed: !_hasConnection || state.busy || editable.isEmpty
                ? null
                : () async {
                    if (filled > 0) {
                      final ok = await _confirm(
                        title: '重新生成全部？',
                        message: '现有的 $filled 个槽位内容会被覆盖。'
                            '（会先存一版快照，可以回滚）',
                        confirmLabel: '重新生成',
                      );
                      if (!ok) {
                        return;
                      }
                    }
                    await _actions.generateSlots(project.id);
                    refresh();
                  },
          ),
          if (!_hasConnection) ...[
            const SizedBox(height: 8),
            const Text(
              '⚠️ 还没有可用的 API 连接，先去「设置 → API 连接」里配置。',
              style: TextStyle(color: WorkshopColors.warning, fontSize: 11),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),

      // --- 逐槽位编辑 ---
      for (final slot in project.slots) ...[
        _slotContentCard(project, slot),
        const SizedBox(height: 10),
      ],

      const SizedBox(height: 2),
      _buildRefineCard(project, state),
    ];
  }

  // --- 单个槽位 ---

  Widget _slotContentCard(PresetProject project, PresetSlot slot) {
    final expanded = _expandedSlots.contains(slot.identifier);
    final writable = !slot.marker && !slot.userOwned;

    return WorkshopWidgets.card(
      title: slot.label,
      accentColor: slot.enabled ? kPresetAccent : WorkshopColors.textHint,
      subtitle: 'role=${slot.role} · ${slot.identifier}'
          '${slot.enabled ? "" : " · 已关闭"}'
          '${slot.marker ? " · 内容由引擎填充" : ""}'
          '${slot.userOwned ? " · 由你自己填，AI 不代写" : ""}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (writable && _hasConnection)
            _iconAction(
              Icons.refresh,
              () => _regenerateSlot(project, slot),
            ),
          _iconAction(
            expanded ? Icons.expand_less : Icons.expand_more,
            () {
              if (expanded) {
                _expandedSlots.remove(slot.identifier);
              } else {
                _expandedSlots.add(slot.identifier);
              }
              refresh();
            },
          ),
        ],
      ),
      children: [
        if (slot.marker && !slot.hasContent)
          WorkshopWidgets.emptyHint(
            '这个槽位的内容在运行时由引擎注入。你写在这里的文本会被「前置」到'
            '内置内容前面 —— 适合放板块标题或开标签，写正文没有意义。',
          )
        else if (expanded)
          TextField(
            controller: _slotController(project, slot),
            maxLines: null,
            minLines: 6,
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 12,
              height: 1.6,
            ),
            decoration: WorkshopWidgets.inputDecoration(
              '写这个槽位的内容…',
              dense: false,
            ),
          )
        else
          GestureDetector(
            onTap: () {
              _expandedSlots.add(slot.identifier);
              refresh();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: WorkshopColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: WorkshopColors.strokeSoft,
                  width: 0.8,
                ),
              ),
              child: Text(
                slot.hasContent
                    ? slot.content.trim()
                    : (slot.userOwned ? '（留空也完全没问题）' : '（还没写内容，点这里开始编辑）'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: slot.hasContent
                      ? WorkshopColors.textSecondary
                      : WorkshopColors.textHint,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ),
        if (writable && slot.hasContent) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${slot.content.trim().length} 字',
                  style: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 10,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openSlotEditor(project, slot),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('全屏编辑', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await _confirm(
                    title: '清空「${slot.label}」？',
                    message: '内容会清掉，可以点「重新生成」再写一版。',
                    confirmLabel: '清空',
                  );
                  if (ok) {
                    ref
                        .read(presetProjectProvider.notifier)
                        .clearSlotContent(project.id, slot.identifier);
                  }
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: WorkshopColors.danger,
                ),
                child: const Text('清空', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _regenerateSlot(PresetProject project, PresetSlot slot) async {
    final controller = TextEditingController();
    final hint = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: Text(
          '重写「${slot.label}」',
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 15,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '想怎么改？（可留空，直接重写一版）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('重写'),
          ),
        ],
      ),
    );
    if (hint == null) {
      return;
    }
    await _actions.regenerateSlot(project.id, slot.identifier, userHint: hint);
    refresh();
  }

  // --- 对话式微调 ---

  Widget _buildRefineCard(PresetProject project, PresetProjectState state) {
    return WorkshopWidgets.card(
      title: '对话式微调',
      accentColor: kPresetAccent,
      subtitle: '用自然语言提要求。模型只改它认为该改的槽位，'
          '改的是「完整正文」，会整段替换。',
      children: [
        if (_refineLog.isNotEmpty) ...[
          for (final entry in _refineLog.reversed.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '· $entry',
                style: const TextStyle(
                  color: WorkshopColors.textHint,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _refineController,
          maxLines: 3,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 12,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '例如：底部指令太长，精简到 100 字以内；'
            '把「顶部声明」里的文风要求改成冷硬简洁',
          ),
        ),
        const SizedBox(height: 10),
        WorkshopWidgets.primaryButton(
          label: '让 AI 改',
          icon: Icons.auto_fix_high,
          busy: state.busy,
          background: kPresetAccent,
          onPressed: !_hasConnection || state.busy
              ? null
              : () async {
                  final instruction = _refineController.text.trim();
                  if (instruction.isEmpty) {
                    _notify('先写一句你的要求');
                    return;
                  }
                  final result = await _actions.refine(project.id, instruction);
                  if (result != null && result.reply.isNotEmpty) {
                    _refineLog.add(result.reply);
                    _refineController.clear();
                  }
                  refresh();
                },
        ),
      ],
    );
  }
}
