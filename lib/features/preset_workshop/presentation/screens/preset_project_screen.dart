import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api_connection/data/api_connection_provider.dart';
import '../../../character_workshop/presentation/workshop_theme.dart';
import '../../data/preset_packager.dart';
import '../../data/preset_project_provider.dart';
import '../../data/preset_prompt_builder.dart';
import '../../data/preset_workshop_actions.dart';
import '../../domain/models/preset_brief.dart';
import '../../domain/models/preset_diagnosis.dart';
import '../../domain/models/preset_project.dart';
import '../../domain/models/preset_slot.dart';
import '../../domain/preset_slot_catalog.dart';
import '../../domain/preset_structure_templates.dart';
import '../widgets/preset_repair_diff_dialog.dart';
import '../widgets/slot_editor_sheet.dart';

part 'project/project_shell_extension.dart';
part 'project/project_brief_extension.dart';
part 'project/project_structure_extension.dart';
part 'project/project_slots_extension.dart';
part 'project/project_diagnose_extension.dart';
part 'project/project_export_extension.dart';

/// 预设工坊的视觉主色 —— 与角色工坊（蓝紫）拉开，用青绿。
const Color kPresetAccent = WorkshopColors.worldbook;

/// 预设工作台：一个项目的五阶段流水线。
///
/// 与角色工坊同构：阶段单向推进 + 允许回退，主按钮永远指向「下一个该做的事」。
/// 五个 `part` 扩展各负责一个阶段，`setState` 统一走 [refresh]。
class PresetProjectScreen extends ConsumerStatefulWidget {
  const PresetProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<PresetProjectScreen> createState() =>
      _PresetProjectScreenState();
}

class _PresetProjectScreenState extends ConsumerState<PresetProjectScreen> {
  final ScrollController _scrollController = ScrollController();

  /// 微调输入框。
  final TextEditingController _refineController = TextEditingController();

  /// 槽位正文输入框（槽位页展开编辑时用）。
  final Map<String, TextEditingController> _slotControllers = {};

  /// 需求页的输入框（自定义扮演方式 / 文风 / 补充说明）。
  final Map<String, TextEditingController> _briefControllers = {};

  /// 正在被程序改写文本的控制器，用来屏蔽自己触发的监听回调。
  final Set<TextEditingController> _mutedControllers = {};

  /// 展开的槽位。
  final Set<String> _expandedSlots = {};

  /// 微调对话记录（只在本页会话内保留，不落库）。
  final List<String> _refineLog = <String>[];

  /// 纯 UI 状态（展开 / 折叠）改动后刷新界面。
  ///
  /// 五个 `part` 扩展里不能直接调 `setState`（`@protected`，扩展不算子类），
  /// 统一走这个入口。
  void refresh() => setState(() {});

  @override
  void dispose() {
    _scrollController.dispose();
    _refineController.dispose();
    for (final controller in _slotControllers.values) {
      controller.dispose();
    }
    for (final controller in _briefControllers.values) {
      controller.dispose();
    }
    ref.read(presetProjectProvider.notifier).flushPendingWrites();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(presetProjectByIdProvider(widget.projectId));
    final state = ref.watch(presetProjectProvider);

    if (project == null) {
      return Scaffold(
        backgroundColor: WorkshopColors.pageBg,
        appBar: AppBar(
          backgroundColor: WorkshopColors.surface,
          title: const Text('项目不存在'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '这个项目已经被删除了。',
              style: TextStyle(color: WorkshopColors.textSecondary, fontSize: 13),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${project.enabledSlots.length}/${project.slots.length} 槽位',
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
                    onDismiss: () =>
                        ref.read(presetProjectProvider.notifier).clearError(),
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

  List<Widget> _buildStageBody(PresetProject project, PresetProjectState state) {
    switch (project.stage) {
      case PresetStage.brief:
        return _buildBriefStage(project, state);
      case PresetStage.structure:
        return _buildStructureStage(project, state);
      case PresetStage.slots:
        return _buildSlotsStage(project, state);
      case PresetStage.diagnose:
        return _buildDiagnoseStage(project, state);
      case PresetStage.done:
        return _buildExportStage(project, state);
    }
  }

  // --- 通用工具 ---

  PresetWorkshopActions get _actions => ref.read(presetWorkshopActionsProvider);

  bool get _hasConnection => ref.read(activeApiConnectionProvider) != null;

  void _notify(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _goToStage(PresetProject project, PresetStage stage) {
    ref.read(presetProjectProvider.notifier).setStage(project.id, stage);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 确认弹窗（切结构这种会动到内容前先问一下）。
  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = '继续',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: Text(
          title,
          style: const TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: Text(
          message,
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
              backgroundColor: kPresetAccent,
              foregroundColor: const Color(0xFF10142B),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _renameProject(PresetProject project) async {
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
          style: const TextStyle(color: WorkshopColors.textPrimary, fontSize: 13),
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
      ref.read(presetProjectProvider.notifier).renameProject(project.id, result);
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

  /// 展示一段可复制的长文本。
  void _showCopyableText(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: Text(
          title,
          style: const TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(
                color: WorkshopColors.textPrimary,
                fontSize: 12,
                height: 1.5,
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

  /// 需求页输入框控制器。
  TextEditingController _briefController({
    required String key,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return _syncedController(
      pool: _briefControllers,
      key: key,
      value: value,
      onChanged: onChanged,
    );
  }

  /// 槽位正文输入框控制器。
  TextEditingController _slotController(PresetProject project, PresetSlot slot) {
    return _syncedController(
      pool: _slotControllers,
      key: slot.identifier,
      value: slot.content,
      onChanged: (text) {
        ref
            .read(presetProjectProvider.notifier)
            .setSlotContent(project.id, slot.identifier, text);
      },
    );
  }

  /// 打开某个槽位的全屏编辑。
  Future<void> _openSlotEditor(PresetProject project, PresetSlot slot) async {
    await SlotEditorSheet.show(
      context: context,
      project: project,
      slot: slot,
      onSaved: (content) {
        ref
            .read(presetProjectProvider.notifier)
            .setSlotContent(project.id, slot.identifier, content);
      },
      onRegenerate: slot.userOwned || slot.marker
          ? null
          : (hint) async {
              Navigator.pop(context);
              await _actions.regenerateSlot(
                project.id,
                slot.identifier,
                userHint: hint,
              );
            },
    );
    refresh();
  }

  /// 槽位标识 → 中文名。
  String _labelOf(String identifier) => slotLabelOf(identifier);

  /// 显示诊断问题的详情弹窗。
  void _showIssueDetail(PresetDiagnosisIssue issue) {
    _showCopyableText(
      issue.title,
      <String>[
        issue.detail,
        if (issue.suggestion.trim().isNotEmpty) '建议：${issue.suggestion}',
      ].join('\n\n'),
    );
  }
}
