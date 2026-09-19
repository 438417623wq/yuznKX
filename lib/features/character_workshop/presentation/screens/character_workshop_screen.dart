import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api_connection/data/api_connection_provider.dart';
import '../../../api_connection/domain/models/api_connection.dart';
import '../../../api_connection/presentation/screens/api_connection_list_screen.dart';
import '../../data/card_project_provider.dart';
import '../../domain/models/card_project.dart';
import '../workshop_theme.dart';
import 'project_screen.dart';

/// 创作工坊：项目列表。
///
/// 工坊是**项目制**的 —— 一张卡从需求对齐、规划、逐条写作、质检到导出，
/// 全过程都在一个项目里，随时可以退出、重进、继续。这也是「断点续接」
/// 在 App 里的实现方式：不靠对话上下文，靠落库。
class CharacterWorkshopScreen extends ConsumerStatefulWidget {
  const CharacterWorkshopScreen({super.key});

  @override
  ConsumerState<CharacterWorkshopScreen> createState() =>
      _CharacterWorkshopScreenState();
}

class _CharacterWorkshopScreenState
    extends ConsumerState<CharacterWorkshopScreen> {
  bool _creating = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cardProjectProvider);
    final connection = ref.watch(activeApiConnectionProvider);

    return Scaffold(
      backgroundColor: WorkshopColors.pageBg,
      appBar: AppBar(
        backgroundColor: WorkshopColors.surface,
        title: const Text('创作工坊'),
        actions: [
          if (state.projects.isNotEmpty)
            IconButton(
              tooltip: '新建项目',
              icon: const Icon(Icons.add),
              onPressed: _startCreating,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WorkshopMetrics.pagePadding,
          12,
          WorkshopMetrics.pagePadding,
          40,
        ),
        children: [
          _buildApiBanner(connection),
          const SizedBox(height: 12),
          if (_creating) ...[
            _buildCreateCard(),
            const SizedBox(height: 12),
          ],
          _buildProjectList(state),
        ],
      ),
    );
  }

  // --- API 状态 ---

  Widget _buildApiBanner(ApiConnection? connection) {
    final missing = connection == null;
    final tint = missing ? WorkshopColors.warning : WorkshopColors.success;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: WorkshopColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkshopColors.stroke, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            missing ? Icons.warning_amber_rounded : Icons.bolt,
            size: 18,
            color: tint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missing ? '还没有可用的 API 连接' : '当前连接：${connection.name}',
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  missing
                      ? '生成角色卡必须依赖模型，先去配置一个'
                      : '模型：${connection.model.trim().isEmpty ? '未指定' : connection.model}',
                  style: const TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ApiConnectionListScreen()),
            ),
            child: Text(missing ? '去配置' : '切换'),
          ),
        ],
      ),
    );
  }

  // --- 新建 ---

  void _startCreating() {
    _nameController.clear();
    setState(() => _creating = true);
  }

  void _cancelCreating() {
    _nameController.clear();
    setState(() => _creating = false);
  }

  Widget _buildCreateCard() {
    return WorkshopWidgets.card(
      title: '新建创作项目',
      subtitle: '给项目起个名字，之后可以随时改',
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration('例：雨夜重逢的机械师'),
          onSubmitted: (_) => _createProject(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '取消',
                onPressed: _cancelCreating,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WorkshopWidgets.primaryButton(
                label: '开始',
                icon: Icons.arrow_forward,
                onPressed: _createProject,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _createProject() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _notify('先给项目起个名字吧');
      return;
    }
    final project =
        ref.read(cardProjectProvider.notifier).createProject(name: name);
    _cancelCreating();
    _openProject(project);
  }

  // --- 列表 ---

  Widget _buildProjectList(CardProjectState state) {
    if (!state.loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.projects.isEmpty) {
      return WorkshopWidgets.card(
        title: '还没有创作项目',
        subtitle: '这里不是「一键生成」——先对齐需求，再规划，最后一条条写出来',
        children: [
          const Text(
            '工坊会把「写一张卡」拆成五步：\n'
            '① 需求对齐：六个维度逐维确认\n'
            '② 创作规划：列出要写哪些条目\n'
            '③ 逐条产出：一次写一条，随时能停\n'
            '④ 质检：本地扫描结构、一致性、文本质量\n'
            '⑤ 导出：打包成角色卡 + 完整世界书',
            style: TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 12,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 14),
          WorkshopWidgets.primaryButton(
            label: '新建第一个项目',
            icon: Icons.add,
            onPressed: _startCreating,
          ),
        ],
      );
    }

    return WorkshopWidgets.card(
      title: '我的项目',
      subtitle: '共 ${state.projects.length} 个 · 点一下继续',
      children: [
        for (var i = 0; i < state.projects.length; i++) ...[
          if (i > 0)
            const Divider(color: WorkshopColors.strokeSoft, height: 1),
          _buildProjectTile(state.projects[i]),
        ],
      ],
    );
  }

  Widget _buildProjectTile(CardProject project) {
    return InkWell(
      onTap: () => _openProject(project),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (project.isLegacy)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Text(
                      '旧版',
                      style: TextStyle(
                        color: WorkshopColors.textHint,
                        fontSize: 10,
                      ),
                    ),
                  ),
                _buildStageBadge(project.stage),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: WorkshopColors.textHint),
                  color: WorkshopColors.surfaceSoft,
                  onSelected: (value) {
                    if (value == 'rename') {
                      _renameProject(project);
                    } else if (value == 'delete') {
                      _deleteProject(project);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('重命名',
                          style: TextStyle(
                              color: WorkshopColors.textPrimary, fontSize: 13)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除项目',
                          style: TextStyle(
                              color: WorkshopColors.danger, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              project.stage.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 11,
              ),
            ),
            if (project.hasEntries) ...[
              const SizedBox(height: 8),
              WorkshopWidgets.progressBar(project.progress),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(
                    '条目 ${project.doneCount}/${project.totalCount}',
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    relativeWorkshopTime(project.updatedAt),
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                relativeWorkshopTime(project.updatedAt),
                style: const TextStyle(
                  color: WorkshopColors.textHint,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStageBadge(ProjectStage stage) {
    final isDone = stage == ProjectStage.done;
    final tint = isDone ? WorkshopColors.success : WorkshopColors.accent;
    return Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDone ? WorkshopColors.successSoft : WorkshopColors.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint, width: 0.8),
      ),
      child: Text(
        stage.label,
        style: TextStyle(color: tint, fontSize: 10),
      ),
    );
  }

  // --- 动作 ---

  void _openProject(CardProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectScreen(projectId: project.id),
      ),
    );
  }

  Future<void> _renameProject(CardProject project) async {
    final controller = TextEditingController(text: project.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text('重命名项目',
            style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
              color: WorkshopColors.textPrimary, fontSize: 13),
          decoration: WorkshopWidgets.inputDecoration('项目名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      ref.read(cardProjectProvider.notifier).renameProject(project.id, result);
    }
  }

  Future<void> _deleteProject(CardProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text('删除项目',
            style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15)),
        content: Text(
          '「${project.name}」以及里面已经写好的 ${project.doneCount} 条内容都会一起删掉，无法恢复。\n\n'
          '已经导出成角色卡的不会受影响。',
          style: const TextStyle(
            color: WorkshopColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WorkshopColors.danger,
              foregroundColor: const Color(0xFF2A0F14),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(cardProjectProvider.notifier).deleteProject(project.id);
      _notify('已删除「${project.name}」');
    }
  }

  void _notify(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
