part of '../project_screen.dart';

/// 阶段三：逐条产出。
///
/// 一次只生成一条，每次的上下文固定是「需求对齐 + 这条的规划描述 + 已完成条目的标题与摘要」，
/// **不带已完成条目的全文** —— 所以上下文不随进度增长，中断也随时可以。
extension _ProjectWritingExtension on _ProjectScreenState {
  List<Widget> _buildWritingStage(CardProject project, CardProjectState state) {
    final busy = state.busy;

    return <Widget>[
      _buildWritingProgress(project, busy),
      const SizedBox(height: 12),
      _buildEntryList(project, busy),
    ];
  }

  Widget _buildWritingProgress(CardProject project, bool busy) {
    final next = project.firstUnsettled;
    final failed =
        project.entries.where((e) => e.status == EntryStatus.failed).length;

    return WorkshopWidgets.card(
      title: '③ 逐条产出',
      subtitle: '已完成 ${project.doneCount}/${project.totalCount} 条'
          '${failed > 0 ? ' · $failed 条失败' : ''}',
      children: [
        WorkshopWidgets.progressBar(project.progress),
        const SizedBox(height: 12),
        if (next != null)
          Text(
            '下一条：${next.title}',
            style: const TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 12,
            ),
          )
        else
          const Text(
            '全部条目都处理完了，可以进质检。',
            style: TextStyle(
              color: WorkshopColors.stageDone,
              fontSize: 12,
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _writeHintController,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '写作补充要求（可选）：对所有条目生效，比如「多用短句」',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (next != null)
              Expanded(
                child: WorkshopWidgets.primaryButton(
                  label: '写这一条',
                  icon: Icons.edit_note,
                  onPressed: busy
                      ? null
                      : () => _actions.writeEntry(
                            project.id,
                            next.id,
                            userHint: _writeHintController.text,
                          ),
                ),
              ),
            if (next != null && project.doneCount > 0)
              const SizedBox(width: 8),
            if (project.doneCount > 0 || next == null)
              Expanded(
                child: WorkshopWidgets.secondaryButton(
                  label: '全部写完（剩 ${project.totalCount - project.settledCount} 条）',
                  icon: Icons.fast_forward,
                  onPressed: busy || project.settledCount >= project.totalCount
                      ? null
                      : () => _writeAll(project),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _writeAll(CardProject project) async {
    await _actions.writeAllPending(project.id);
    if (!mounted) {
      return;
    }
    final latest = ref.read(cardProjectByIdProvider(project.id));
    if (latest != null && latest.isAllWritten) {
      _notify('全部写完，去质检看看');
    } else {
      _notify('中途停下了，可以单条重试');
    }
  }

  // --- 条目列表 ---

  Widget _buildEntryList(CardProject project, bool busy) {
    if (project.entries.isEmpty) {
      return WorkshopWidgets.card(
        title: '还没有条目',
        children: [
          WorkshopWidgets.emptyHint('先回到「创作规划」阶段生成条目清单。'),
        ],
      );
    }

    return WorkshopWidgets.card(
      title: '条目',
      subtitle: '点条目展开看正文，正文可以直接改',
      children: [
        for (var i = 0; i < project.entries.length; i++)
          _buildEntryTile(project, project.entries[i], i, busy),
      ],
    );
  }

  Widget _buildEntryTile(
    CardProject project,
    ProjectEntry entry,
    int index,
    bool busy,
  ) {
    final expanded = _expandedEntryIds.contains(entry.id);
    final statusColor = _statusColor(entry.status);
    final isWorldbook = entry.goesToWorldbook;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: WorkshopColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.status == EntryStatus.failed
              ? WorkshopColors.danger
              : (entry.status == EntryStatus.generating
                  ? WorkshopColors.accent
                  : WorkshopColors.strokeSoft),
          width: entry.status == EntryStatus.generating ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              if (expanded) {
                _expandedEntryIds.remove(entry.id);
              } else {
                _expandedEntryIds.add(entry.id);
              }
              refresh();
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
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
                          color: isWorldbook
                              ? WorkshopColors.worldbookSoft
                              : WorkshopColors.accentSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.kind.label,
                          style: TextStyle(
                            color: isWorldbook
                                ? WorkshopColors.worldbook
                                : WorkshopColors.accent,
                            fontSize: 9,
                          ),
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
                      if (entry.status == EntryStatus.generating)
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        Icon(statusColor.icon, size: 13, color: statusColor.color),
                        const SizedBox(width: 5),
                        Text(
                          entry.status.label,
                          style: TextStyle(
                            color: statusColor.color,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: WorkshopColors.textHint,
                      ),
                    ],
                  ),
                  if (!expanded) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.hasContent
                          ? _previewOf(entry.content)
                          : (entry.brief.trim().isEmpty
                              ? '（还没写）'
                              : entry.brief),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WorkshopColors.textHint,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (entry.status == EntryStatus.failed &&
                      entry.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WorkshopColors.danger,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(color: WorkshopColors.strokeSoft, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.brief.trim().isNotEmpty) ...[
                    Text(
                      '规划：${entry.brief}',
                      style: const TextStyle(
                        color: WorkshopColors.textHint,
                        fontSize: 10,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (entry.keys.isNotEmpty) ...[
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
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _entryController(project, entry.id),
                    minLines: 3,
                    maxLines: null,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                    decoration: WorkshopWidgets.inputDecoration('（还没写）'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => _actions.writeEntry(
                                  project.id,
                                  entry.id,
                                  userHint: _writeHintController.text,
                                ),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: Text(
                          entry.hasContent ? '重写' : '写这条',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: WorkshopColors.accent,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => entry.status == EntryStatus.skipped
                                ? _actions.resetEntry(project.id, entry.id)
                                : _actions.skipEntry(project.id, entry.id),
                        icon: Icon(
                          entry.status == EntryStatus.skipped
                              ? Icons.undo
                              : Icons.skip_next,
                          size: 14,
                        ),
                        label: Text(
                          entry.status == EntryStatus.skipped
                              ? '取消跳过'
                              : '跳过',
                          style: const TextStyle(fontSize: 11),
                        ),
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
            ),
          ],
        ],
      ),
    );
  }

  static String _previewOf(String content) {
    final text = content.trim();
    if (text.startsWith('[') && text.endsWith(']')) {
      // 数组型字段（标签 / 备用开场白）存的是 JSON，预览时显示条目数。
      final count = RegExp(r'"').allMatches(text).length ~/ 2;
      return '（$count 项）';
    }
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  static _StatusStyle _statusColor(EntryStatus status) {
    switch (status) {
      case EntryStatus.done:
        return const _StatusStyle(WorkshopColors.stageDone, Icons.check_circle);
      case EntryStatus.generating:
        return const _StatusStyle(WorkshopColors.accent, Icons.autorenew);
      case EntryStatus.failed:
        return const _StatusStyle(WorkshopColors.danger, Icons.error_outline);
      case EntryStatus.skipped:
        return const _StatusStyle(WorkshopColors.textHint, Icons.skip_next);
      case EntryStatus.pending:
        return const _StatusStyle(
          WorkshopColors.textHint,
          Icons.radio_button_unchecked,
        );
    }
  }
}

class _StatusStyle {
  const _StatusStyle(this.color, this.icon);

  final Color color;
  final IconData icon;
}
