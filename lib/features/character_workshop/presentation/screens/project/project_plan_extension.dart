part of '../project_screen.dart';

/// 阶段二：创作规划。
///
/// **这一步只列清单，不写正文。** 每条只描述「负责写什么」，
/// 具体内容留到逐条产出。这样规划可以反复重来，成本极低。
extension _ProjectPlanExtension on _ProjectScreenState {
  List<Widget> _buildPlanStage(CardProject project, CardProjectState state) {
    final busy = state.busy;

    return <Widget>[
      _buildPlanSettings(project, busy),
      const SizedBox(height: 12),
      if (project.plan.summary.trim().isNotEmpty) ...[
        WorkshopWidgets.card(
          title: '规划说明',
          children: [
            Text(
              project.plan.summary,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      _buildPlanList(project, busy),
    ];
  }

  // --- 规划设置 ---

  Widget _buildPlanSettings(CardProject project, bool busy) {
    final plan = project.plan;

    return WorkshopWidgets.card(
      title: '② 创作规划',
      subtitle: '先定好要写哪些条目。这一步不写正文，所以很快，可以反复重来',
      children: [
        WorkshopWidgets.sectionLabel('要写哪些角色卡字段'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in kCardFields)
              WorkshopWidgets.chip(
                label: field.label,
                selected: plan.plannedFieldKeys.contains(field.key),
                icon: plan.plannedFieldKeys.contains(field.key)
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                onTap: busy ? null : () => _togglePlannedField(project, field.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        WorkshopWidgets.sectionLabel('世界书条目数量：${plan.worldbookTarget} 条'),
        Slider(
          value: plan.worldbookTarget.toDouble().clamp(0, 24),
          min: 0,
          max: 24,
          divisions: 24,
          label: '${plan.worldbookTarget}',
          activeColor: WorkshopColors.worldbook,
          inactiveColor: WorkshopColors.stroke,
          onChanged: busy
              ? null
              : (value) => ref.read(cardProjectProvider.notifier).updatePlan(
                    project.id,
                    plan.copyWith(worldbookTarget: value.round()),
                  ),
        ),
        const SizedBox(height: 4),
        WorkshopWidgets.sectionLabel('单条详细程度'),
        const SizedBox(height: 8),
        WorkshopWidgets.segmentedRow<EntryLength>(
          values: EntryLength.values,
          selected: plan.length,
          label: (value) => value.label,
          enabled: !busy,
          onChanged: (value) => ref
              .read(cardProjectProvider.notifier)
              .updatePlan(project.id, plan.copyWith(length: value)),
        ),
        const SizedBox(height: 16),
        WorkshopWidgets.sectionLabel('输出语言'),
        const SizedBox(height: 8),
        WorkshopWidgets.segmentedRow<OutputLanguage>(
          values: OutputLanguage.values,
          selected: plan.language,
          label: (value) => value.label,
          enabled: !busy,
          onChanged: (value) => ref
              .read(cardProjectProvider.notifier)
              .updatePlan(project.id, plan.copyWith(language: value)),
        ),
        const SizedBox(height: 16),
        WorkshopWidgets.sectionLabel('高级'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WorkshopWidgets.chip(
              label: 'MVU 动态变量',
              selected: plan.mvuEnabled,
              icon: plan.mvuEnabled ? Icons.check_circle : Icons.circle_outlined,
              onTap: busy
                  ? null
                  : () => ref.read(cardProjectProvider.notifier).updatePlan(
                        project.id,
                        plan.copyWith(mvuEnabled: !plan.mvuEnabled),
                      ),
            ),
            WorkshopWidgets.chip(
              label: 'EJS 模板',
              selected: plan.ejsEnabled,
              icon: plan.ejsEnabled ? Icons.check_circle : Icons.circle_outlined,
              onTap: busy
                  ? null
                  : () => ref.read(cardProjectProvider.notifier).updatePlan(
                        project.id,
                        plan.copyWith(ejsEnabled: !plan.ejsEnabled),
                      ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _planHintController,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '补充要求（可选）：比如「多加几条关于教会的设定」',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: project.hasEntries ? '重新生成（覆盖）' : '生成规划',
                icon: Icons.auto_awesome,
                onPressed: busy
                    ? null
                    : () => _actions.generatePlan(
                          project.id,
                          replaceExisting: true,
                          userHint: _planHintController.text,
                        ),
              ),
            ),
            if (project.hasEntries) ...[
              const SizedBox(width: 8),
              Expanded(
                child: WorkshopWidgets.secondaryButton(
                  label: '追加条目',
                  icon: Icons.add,
                  onPressed: busy
                      ? null
                      : () => _actions.generatePlan(
                            project.id,
                            replaceExisting: false,
                            userHint: _planHintController.text,
                          ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _togglePlannedField(CardProject project, String key) {
    final plan = project.plan;
    final next = Set<String>.from(plan.plannedFieldKeys);
    if (!next.remove(key)) {
      next.add(key);
    }
    if (next.isEmpty) {
      _notify('至少留一个字段');
      return;
    }
    ref
        .read(cardProjectProvider.notifier)
        .updatePlan(project.id, plan.copyWith(plannedFieldKeys: next));
  }

  // --- 条目清单 ---

  Widget _buildPlanList(CardProject project, bool busy) {
    final entries = project.entries;

    return WorkshopWidgets.card(
      title: '条目清单',
      subtitle: entries.isEmpty
          ? '还没有条目'
          : '共 ${entries.length} 条 · 角色卡字段 ${project.characterFieldEntries.length} 条 · '
              '世界书类 ${entries.where((e) => e.goesToWorldbook).length} 条',
      accentColor: WorkshopColors.worldbook,
      trailing: TextButton(
        onPressed: busy ? null : () => _addPlanEntry(project),
        child: const Text('新增'),
      ),
      children: [
        if (entries.isEmpty)
          WorkshopWidgets.emptyHint(
            '点上面的「生成规划」，让模型根据需求对齐结果列出要写哪些条目。\n'
            '生成后你可以逐条改标题、改关键词、调顺序，或者手动加条目。',
          )
        else
          for (var i = 0; i < entries.length; i++)
            _buildPlanEntryTile(project, entries[i], i, entries.length, busy),
      ],
    );
  }

  Widget _buildPlanEntryTile(
    CardProject project,
    ProjectEntry entry,
    int index,
    int total,
    bool busy,
  ) {
    final isWorldbook = entry.goesToWorldbook;
    final tint = isWorldbook ? WorkshopColors.worldbook : WorkshopColors.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isWorldbook
                      ? WorkshopColors.worldbookSoft
                      : WorkshopColors.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.kind.label,
                  style: TextStyle(color: tint, fontSize: 9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '上移',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: index == 0
                      ? WorkshopColors.stroke
                      : WorkshopColors.textHint,
                ),
                onPressed: busy || index == 0
                    ? null
                    : () => ref
                        .read(cardProjectProvider.notifier)
                        .moveEntry(project.id, entry.id, -1),
              ),
              IconButton(
                tooltip: '下移',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: index == total - 1
                      ? WorkshopColors.stroke
                      : WorkshopColors.textHint,
                ),
                onPressed: busy || index == total - 1
                    ? null
                    : () => ref
                        .read(cardProjectProvider.notifier)
                        .moveEntry(project.id, entry.id, 1),
              ),
            ],
          ),
          if (entry.brief.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                entry.brief,
                style: const TextStyle(
                  color: WorkshopColors.textSecondary,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (entry.keys.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in entry.keys)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: WorkshopColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      key,
                      style: const TextStyle(
                        color: WorkshopColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => _editPlanEntry(project, entry),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('编辑', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: WorkshopColors.textSecondary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => ref
                        .read(cardProjectProvider.notifier)
                        .removeEntry(project.id, entry.id),
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('删除', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: WorkshopColors.textHint,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editPlanEntry(CardProject project, ProjectEntry entry) async {
    final titleController = TextEditingController(text: entry.title);
    final briefController = TextEditingController(text: entry.brief);
    final keysController = TextEditingController(text: entry.keys.join('，'));
    var kind = entry.kind;
    var constant = entry.constant;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: WorkshopColors.surface,
          title: const Text(
            '编辑条目',
            style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '类型',
                  style: TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in EntryKind.values)
                      WorkshopWidgets.chip(
                        label: value.label,
                        selected: kind == value,
                        onTap: () => setDialogState(() => kind = value),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '标题',
                  style: TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: WorkshopWidgets.inputDecoration('条目标题'),
                ),
                const SizedBox(height: 14),
                const Text(
                  '要写什么',
                  style: TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: briefController,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: WorkshopWidgets.inputDecoration(
                    '这条负责写什么，会作为写作时的上下文',
                  ),
                ),
                if (kind.goesToWorldbook || kind == EntryKind.timeline) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '触发关键词（用逗号分隔）',
                    style: TextStyle(
                      color: WorkshopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keysController,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: WorkshopWidgets.inputDecoration(
                      '例：铁匠铺，打铁，老陈',
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setDialogState(() => constant = !constant),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Icon(
                          constant
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 15,
                          color: constant
                              ? WorkshopColors.accent
                              : WorkshopColors.textHint,
                        ),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            '常驻注入（不依赖关键词，始终生效）',
                            style: TextStyle(
                              color: WorkshopColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    final keys = keysController.text
        .split(RegExp(r'[,，、;；\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    ref.read(cardProjectProvider.notifier).updateEntry(
          project.id,
          entry.copyWith(
            title: titleController.text.trim().isEmpty
                ? entry.title
                : titleController.text.trim(),
            brief: briefController.text.trim(),
            kind: kind,
            keys: keys,
            constant: constant,
          ),
        );
  }

  Future<void> _addPlanEntry(CardProject project) async {
    final entry = ProjectEntry(
      id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      title: '新条目',
      kind: EntryKind.worldbook,
      brief: '',
      order: (project.entries.length + 1) * 10,
    );
    ref.read(cardProjectProvider.notifier).addEntry(project.id, entry);
    await _editPlanEntry(project, entry);
  }
}
