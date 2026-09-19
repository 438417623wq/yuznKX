import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api_connection/data/api_connection_provider.dart';
import '../../../character/data/character_exporter.dart';
import '../../data/card_avatar_factory.dart';
import '../../data/card_project_provider.dart';
import '../../data/workshop_actions.dart';
import '../../data/worldbook_packager.dart';
import '../../domain/models/card_field.dart';
import '../../domain/models/card_project.dart';
import '../../domain/models/check_report.dart';
import '../../domain/models/design_spec.dart';
import '../../domain/models/project_entry.dart';
import '../../domain/models/source_material.dart';
import '../workshop_theme.dart';
import '../widgets/frontend_stage_panel.dart';
import '../widgets/repair_diff_dialog.dart';

part 'project/project_shell_extension.dart';
part 'project/project_design_extension.dart';
part 'project/project_plan_extension.dart';
part 'project/project_writing_extension.dart';
part 'project/project_frontend_extension.dart';
part 'project/project_check_extension.dart';
part 'project/project_export_extension.dart';

/// 创作工作台：一个项目的六阶段流水线。
///
/// 阶段是「单向推进 + 允许回退」的：可以点阶段条回到任意已完成的阶段重做，
/// 主操作按钮永远指向「下一个该做的事」。
class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  final ScrollController _scrollController = ScrollController();

  /// 需求对齐阶段：每个维度一个答案输入框。
  final Map<String, TextEditingController> _specControllers = {};

  /// 规划 / 写作阶段的「补充要求」。
  final TextEditingController _planHintController = TextEditingController();
  final TextEditingController _writeHintController = TextEditingController();

  /// 写作阶段：每个条目一个正文输入框。
  final Map<String, TextEditingController> _entryControllers = {};

  /// 正在被程序改写文本的控制器，用来屏蔽自己触发的监听回调。
  final Set<TextEditingController> _mutedControllers = {};

  /// 展开查看的条目（写作阶段）。
  final Set<String> _expandedEntryIds = {};

  /// 纯 UI 状态（展开 / 折叠）改动后刷新界面。
  ///
  /// 六个 `part` 扩展里不能直接调 `setState`（`@protected`，扩展不算子类），
  /// 统一走这个入口。
  void refresh() => setState(() {});

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _specControllers.values) {
      controller.dispose();
    }
    for (final controller in _entryControllers.values) {
      controller.dispose();
    }
    _planHintController.dispose();
    _writeHintController.dispose();
    ref.read(cardProjectProvider.notifier).flushPendingWrites();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(cardProjectByIdProvider(widget.projectId));
    final state = ref.watch(cardProjectProvider);

    if (project == null) {
      return Scaffold(
        backgroundColor: WorkshopColors.pageBg,
        appBar: AppBar(
          backgroundColor: WorkshopColors.surface,
          title: const Text('项目不存在'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '这个项目已经被删除了。',
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WorkshopColors.pageBg,
      appBar: AppBar(
        backgroundColor: WorkshopColors.surface,
        title: GestureDetector(
          onTap: () => _renameProject(project),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 14, color: WorkshopColors.textHint),
            ],
          ),
        ),
        actions: [
          if (project.totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${project.doneCount}/${project.totalCount}',
                  style: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStageBar(project, state.busy),
          if (state.busy) _buildBusyBar(state),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                WorkshopMetrics.pagePadding,
                14,
                WorkshopMetrics.pagePadding,
                32,
              ),
              children: [
                if (state.error != null) ...[
                  WorkshopWidgets.errorBox(
                    message: state.error!,
                    rawOutput: state.errorRaw,
                    onViewRaw: () => _showRawOutput(state.errorRaw!),
                    onDismiss: () => ref
                        .read(cardProjectProvider.notifier)
                        .clearError(),
                  ),
                  const SizedBox(height: 12),
                ],
                ..._buildStageBody(project, state),
              ],
            ),
          ),
          _buildActionBar(project, state),
        ],
      ),
    );
  }

  // --- 阶段分发 ---

  List<Widget> _buildStageBody(CardProject project, CardProjectState state) {
    switch (project.stage) {
      case ProjectStage.design:
        return _buildDesignStage(project, state);
      case ProjectStage.plan:
        return _buildPlanStage(project, state);
      case ProjectStage.writing:
        return _buildWritingStage(project, state);
      case ProjectStage.frontend:
        return _buildFrontendStage(project, state);
      case ProjectStage.checking:
        return _buildCheckStage(project, state);
      case ProjectStage.done:
        return _buildExportStage(project, state);
    }
  }

  // --- 通用工具 ---

  WorkshopActions get _actions => ref.read(workshopActionsProvider);

  bool get _hasConnection => ref.read(activeApiConnectionProvider) != null;

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

  void _goToStage(CardProject project, ProjectStage stage) {
    ref.read(cardProjectProvider.notifier).setStage(project.id, stage);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _renameProject(CardProject project) async {
    final controller = TextEditingController(text: project.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '重命名项目',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
          ),
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

  /// 解析彻底失败时，把模型原始输出交给用户手动抢救。
  void _showRawOutput(String raw) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '模型原始输出',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              raw,
              style: const TextStyle(
                color: WorkshopColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: raw));
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                _notify('已复制到剪贴板');
              }
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 展示一段可复制的长文本（MVU 三件套用）。
  void _showCopyableText(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: Text(
          title,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 15,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(
                color: WorkshopColors.textPrimary,
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                _notify('已复制到剪贴板');
              }
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 字段控制器：只在「外部改动了值」时回写文本，避免打断正在输入的焦点。
  TextEditingController _syncedController({
    required Map<String, TextEditingController> pool,
    required String key,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final existing = pool[key];
    if (existing == null) {
      final controller = TextEditingController(text: value);
      controller.addListener(() {
        if (_mutedControllers.contains(controller)) {
          return;
        }
        onChanged(controller.text);
      });
      pool[key] = controller;
      return controller;
    }

    if (existing.text != value) {
      _mutedControllers.add(existing);
      existing.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _mutedControllers.remove(existing);
    }
    return existing;
  }

  /// 需求对齐的答案输入框控制器。
  TextEditingController _specController(
    CardProject project,
    SpecDimension dimension,
  ) {
    return _syncedController(
      pool: _specControllers,
      key: dimension.key,
      value: project.designSpec.answerOf(dimension),
      onChanged: (text) {
        final current =
            ref.read(cardProjectByIdProvider(project.id)) ?? project;
        ref.read(cardProjectProvider.notifier).updateDesignSpec(
              project.id,
              current.designSpec.withAnswer(dimension, text),
            );
      },
    );
  }

  /// 条目正文输入框控制器。
  TextEditingController _entryController(CardProject project, String entryId) {
    final entry = project.entryById(entryId);
    final value = entry?.content ?? '';
    return _syncedController(
      pool: _entryControllers,
      key: entryId,
      value: value,
      onChanged: (text) {
        ref
            .read(cardProjectProvider.notifier)
            .setEntryContent(project.id, entryId, text);
      },
    );
  }
}
