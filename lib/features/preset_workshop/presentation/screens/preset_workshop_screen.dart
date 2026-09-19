import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api_connection/data/api_connection_provider.dart';
import '../../../api_connection/domain/models/api_connection.dart';
import '../../../api_connection/presentation/screens/api_connection_list_screen.dart';
import '../../../character_workshop/presentation/workshop_theme.dart';
import '../../../presets/data/preset_provider.dart';
import '../../../presets/domain/models/preset.dart';
import '../../data/preset_project_provider.dart';
import '../../data/preset_workshop_actions.dart';
import '../../domain/models/preset_project.dart';
import 'preset_project_screen.dart';

/// 预设工坊：项目列表。
///
/// 与角色工坊同构 —— **项目制**。一个预设从需求、结构、内容、诊断到导出，
/// 全程在一个项目里，随时退出重进继续。断点续接靠落库，不靠对话上下文。
///
/// 两条入口（按需求锁定）：
/// - **从零构建**：走完整五阶段向导；
/// - **从已有预设导入**：把预设拆成槽位，直接跳到「填充内容」阶段。
class PresetWorkshopScreen extends ConsumerStatefulWidget {
  const PresetWorkshopScreen({super.key});

  @override
  ConsumerState<PresetWorkshopScreen> createState() =>
      _PresetWorkshopScreenState();
}

class _PresetWorkshopScreenState extends ConsumerState<PresetWorkshopScreen> {
  bool _creating = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(presetProjectProvider);
    final connection = ref.watch(activeApiConnectionProvider);

    return Scaffold(
      backgroundColor: WorkshopColors.pageBg,
      appBar: AppBar(
        backgroundColor: WorkshopColors.surface,
        title: const Text('预设工坊'),
        actions: [
          // ⛔ 早先写成 `state.projects.isNotEmpty` —— 那会和「新建卡片只在
          // `_creating` 为真时显示」互相锁死：**首次进入一个项目都没有，
          // 页面上就一个入口都没有**。改成只要加载完就常驻。
          if (state.loaded)
            IconButton(
              tooltip: '新建预设',
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _creating = true),
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
          _buildIntroCard(),
          const SizedBox(height: 12),
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
                      ? '生成提示词需要模型；不过结构排布与本地诊断不需要'
                      : '模型：${connection.model.trim().isEmpty ? '未指定' : connection.model}',
                  style: const TextStyle(
                    color: WorkshopColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (missing)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ApiConnectionListScreen(),
                ),
              ),
              child: const Text('去配置', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // --- 新建 ---

  Widget _buildCreateCard() {
    return WorkshopWidgets.card(
      title: '新建预设',
      accentColor: kPresetAccent,
      trailing: GestureDetector(
        onTap: () => setState(() => _creating = false),
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close, size: 15, color: WorkshopColors.textHint),
        ),
      ),
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration('预设名，例如「克苏鲁跑团」'),
        ),
        const SizedBox(height: 10),
        WorkshopWidgets.primaryButton(
          label: '从零构建',
          icon: Icons.auto_awesome,
          background: kPresetAccent,
          onPressed: () => _createNew(),
        ),
        const SizedBox(height: 8),
        WorkshopWidgets.secondaryButton(
          label: '从已有预设导入',
          icon: Icons.download_outlined,
          onPressed: () => _importExisting(),
        ),
        const SizedBox(height: 8),
        const Text(
          '「从零构建」会走完需求 → 结构 → 内容 → 诊断 → 导出五步；'
          '「从已有预设导入」把预设拆成槽位，直接进「填充内容」——'
          '适合在别人的预设上改。',
          style: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  void _createNew() {
    final project = ref
        .read(presetProjectProvider.notifier)
        .createProject(name: _nameController.text);
    _nameController.clear();
    setState(() => _creating = false);
    _openProject(project.id);
  }

  Future<void> _importExisting() async {
    final presets = ref.read(presetsProvider);
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('预设列表是空的 —— 先去「设置 → 预设」里导入一份。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<Preset>(
      context: context,
      backgroundColor: WorkshopColors.surface,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '选一个预设导入',
                  style: TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  '导入后会按它的提示词顺序建好槽位，'
                  '引擎不认识的标识也会原样保留（不会丢内容）。',
                  style: TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const Divider(height: 1, color: WorkshopColors.strokeSoft),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: presets.length,
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    final enabled =
                        preset.prompts.where((p) => p.enabled).length;
                    return ListTile(
                      title: Text(
                        preset.name,
                        style: const TextStyle(
                          color: WorkshopColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${preset.prompts.length} 个槽位 · $enabled 个启用',
                        style: const TextStyle(
                          color: WorkshopColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => Navigator.pop(sheetContext, preset),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) {
      return;
    }
    final project =
        await ref.read(presetWorkshopActionsProvider).importFromPreset(picked);
    if (!mounted) {
      return;
    }
    _nameController.clear();
    setState(() => _creating = false);
    _openProject(project.id);
  }

  // --- 说明 ---

  Widget _buildIntroCard() {
    return WorkshopWidgets.card(
      title: '预设工坊在做什么',
      accentColor: WorkshopColors.textHint,
      subtitle: '预设的本质是「按顺序发给模型的一串消息」。'
          '顺序决定了模型的注意力分布 —— 开头顶部最强，中间最弱，底部次强。\n'
          '所以工坊不直接写一段大提示词，而是让你先排好结构（有哪些槽位、'
          '各自什么 role、谁在前谁在后），再往槽位里填内容。',
      children: const [
        Text(
          '⛔ 破限文本工坊不会代写 —— 它和渠道、模型强绑定，通用模板基本没用。'
          '工坊只负责把位置留好、把结构排对。',
          style: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // --- 项目列表 ---

  Widget _buildProjectList(PresetProjectState state) {
    if (!state.loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.projects.isEmpty) {
      return WorkshopWidgets.card(
        title: '还没有预设项目',
        accentColor: kPresetAccent,
        subtitle: '预设不是「写一段大提示词」—— 先排结构，再往槽位里填内容',
        children: [
          const Text(
            '工坊把「做一个预设」拆成五步：\n'
            '① 需求：扮演方式、目标渠道、人称、文风\n'
            '② 结构：有哪些槽位、各自什么 role、谁在前谁在后\n'
            '③ 内容：逐个槽位写提示词（AI 代写，或你自己写）\n'
            '④ 诊断：本地规则 + AI 复核，专抓「不报错但已失效」的问题\n'
            '⑤ 导出：写进预设列表，去「设置 → 预设」里启用',
            style: TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 12,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 14),
          // 正在填名字时不重复给按钮 —— 上面那张新建卡片已经在处理了。
          if (!_creating) ...[
            WorkshopWidgets.primaryButton(
              label: '新建第一个预设',
              icon: Icons.add,
              background: kPresetAccent,
              onPressed: () => setState(() => _creating = true),
            ),
            const SizedBox(height: 8),
            WorkshopWidgets.secondaryButton(
              label: '从已有预设导入',
              icon: Icons.download_outlined,
              onPressed: () => _importExisting(),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkshopWidgets.sectionLabel('我的预设项目（${state.projects.length}）'),
        const SizedBox(height: 10),
        for (final project in state.projects) ...[
          _projectTile(project),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _projectTile(PresetProject project) {
    final filled = project.enabledSlots.where((slot) => slot.hasContent).length;
    final total = project.enabledSlots.length;

    return GestureDetector(
      onTap: () => _openProject(project.id),
      onLongPress: () => _showProjectMenu(project),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: WorkshopColors.surface,
          borderRadius: BorderRadius.circular(WorkshopMetrics.cardRadius),
          border: Border.all(color: WorkshopColors.stroke, width: 0.8),
        ),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (project.exportedPresetId != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: WorkshopColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '已导出',
                      style: TextStyle(
                        color: WorkshopColors.success,
                        fontSize: 9,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showProjectMenu(project),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: WorkshopColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _tag(project.stage.label, kPresetAccent),
                _tag(project.structureKind.label, WorkshopColors.accent),
                _tag('$filled/$total 槽位有内容', WorkshopColors.textHint),
                if (project.diagnosis.hasBlockingIssue)
                  _tag(
                    '${project.diagnosis.errorCount} 个错误',
                    WorkshopColors.danger,
                  ),
                if (project.importedFromPresetId != null)
                  _tag('导入自已有预设', WorkshopColors.worldbook),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              relativeWorkshopTime(project.updatedAt),
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    );
  }

  Future<void> _showProjectMenu(PresetProject project) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WorkshopColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  project.name,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: WorkshopColors.strokeSoft),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  size: 18, color: WorkshopColors.textSecondary),
              title: const Text(
                '重命名',
                style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 13),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _rename(project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all,
                  size: 18, color: WorkshopColors.textSecondary),
              title: const Text(
                '复制一份',
                style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                final copy = PresetProject(
                  id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
                  name: '${project.name} 副本',
                  stage: project.stage,
                  brief: project.brief,
                  structureKind: project.structureKind,
                  slots: project.slots
                      .map((slot) => slot.copyWith())
                      .toList(growable: false),
                );
                ref.read(presetProjectProvider.notifier).addProject(copy);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  size: 18, color: WorkshopColors.danger),
              title: const Text(
                '删除项目',
                style: TextStyle(color: WorkshopColors.danger, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(project);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(PresetProject project) async {
    final controller = TextEditingController(text: project.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '重命名预设',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
          decoration: WorkshopWidgets.inputDecoration('预设名'),
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
          .renameProject(project.id, result);
    }
  }

  Future<void> _confirmDelete(PresetProject project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '删除项目？',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: Text(
          '「${project.name}」会连同槽位内容一起删掉。\n'
          '${project.exportedPresetId != null ? "已经导出的预设不会被删 —— 它在「设置 → 预设」里。" : "这个项目还没导出过。"}',
          style: const TextStyle(
            color: WorkshopColors.textSecondary,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: WorkshopColors.danger,
              foregroundColor: const Color(0xFF2B1018),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(presetProjectProvider.notifier).deleteProject(project.id);
    }
  }

  void _openProject(String projectId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PresetProjectScreen(projectId: projectId),
      ),
    );
  }
}
