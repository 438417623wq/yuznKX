import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart';
import '../../data/session_provider.dart';
import '../../domain/models/session.dart';

/// 打开「对话历史」底部弹窗。
///
/// 列出**当前角色**的所有对话，支持切换 / 重命名 / 删除 / 新建。
/// 记忆表格是会话级的，所以每一条对话的记忆互不影响。
Future<void> showSessionHistorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const SessionHistorySheet(),
  );
}

class SessionHistorySheet extends ConsumerWidget {
  const SessionHistorySheet({super.key});

  static const Color _sheetColor = Color(0xFF1a1b26);
  static const Color _cardColor = Color(0xFF24283b);
  static const Color _activeColor = Color(0xFF2d3250);
  static const Color _accent = Colors.indigoAccent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final character = ref.watch(activeCharacterProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final allSessions = ref.watch(sessionProvider);

    // 只展示当前角色的对话；sessionProvider 已按 updatedAt 降序排列。
    final sessions = character == null
        ? const <Session>[]
        : allSessions.where((s) => s.characterId == character.id).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: _sheetColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, character, sessions.length),
          if (character != null) _buildNewSessionButton(context, ref, character),
          Flexible(
            child: sessions.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _SessionTile(
                        session: session,
                        isActive: session.id == activeSessionId,
                        onTap: () => _switchTo(context, ref, session),
                        onRename: () => _renameSession(context, ref, session),
                        onDelete: () => _confirmDelete(context, ref, session),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Character? character,
    int count,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '对话历史 (Chat History)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  character == null
                      ? '未选择角色'
                      : '${character.name} · 共 $count 条对话',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNewSessionButton(
    BuildContext context,
    WidgetRef ref,
    Character character,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _createNewSession(context, ref, character),
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: const Text('新建对话 (New Chat)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          '还没有对话记录\n点上方「新建对话」开始',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
        ),
      ),
    );
  }

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    await ref.read(activeSessionIdProvider.notifier).setActive(session.id);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _createNewSession(
    BuildContext context,
    WidgetRef ref,
    Character character,
  ) async {
    final created = await ref.read(sessionProvider.notifier).createSession(
          '新对话 (New Chat)',
          characterId: character.id,
          // 群聊沿用群成员的会话级世界书；单角色不预置，
          // 由角色自身的世界书绑定负责注入。
          groupCharacterIds:
              character.isGroup ? character.groupMemberIds : const [],
          worldInfoIds: character.isGroup ? character.worldInfoIds : const [],
        );
    await ref.read(activeSessionIdProvider.notifier).setActive(created.id);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _renameSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final controller = TextEditingController(text: session.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('重命名对话', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '输入对话名称',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = (newName ?? '').trim();
    if (trimmed.isEmpty) {
      return;
    }
    await ref
        .read(sessionProvider.notifier)
        .updateSession(session.copyWith(name: trimmed));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('删除对话', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定删除「${session.name}」吗？\n\n'
          '该对话的 ${session.messages.length} 条消息、'
          '以及它独占的**记忆表格**都会一并删除，且无法恢复。',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    // 级联清理（消息 / 记忆 / 变量）由 deleteSession 内部完成。
    // 若删的是当前活跃对话，SessionManager 会自动切到该角色的下一条。
    await ref.read(sessionProvider.notifier).deleteSession(session.id);
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Session session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive
          ? SessionHistorySheet._activeColor
          : SessionHistorySheet._cardColor,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isActive
            ? const BorderSide(color: SessionHistorySheet._accent)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        title: Row(
          children: [
            Flexible(
              child: Text(
                session.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SessionHistorySheet._accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.messages.length} 条消息 · '
                '${_formatUpdatedAt(session.updatedAt)}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              if (_lastMessagePreview(session).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _lastMessagePreview(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
          color: const Color(0xFF1f2937),
          tooltip: '更多操作',
          onSelected: (value) {
            if (value == 'rename') {
              onRename();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.drive_file_rename_outline,
                      size: 18, color: Colors.white70),
                  SizedBox(width: 10),
                  Text('重命名', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Text('删除', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _lastMessagePreview(Session session) {
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final content = session.messages[i].content.trim();
      if (content.isEmpty) {
        continue;
      }
      // 去掉换行，避免预览把行高撑开
      final singleLine = content.replaceAll(RegExp(r'\s+'), ' ');
      return singleLine.length > 40
          ? '${singleLine.substring(0, 40)}…'
          : singleLine;
    }
    return '';
  }

  String _formatUpdatedAt(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 30) {
      return '${diff.inDays} 天前';
    }
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
