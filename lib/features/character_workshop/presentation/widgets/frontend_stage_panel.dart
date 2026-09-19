import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../frontend_card/data/frontend_card_host.dart';
import '../../../frontend_card/data/frontend_card_shim.dart';
import '../../../frontend_card/presentation/frontend_card_view.dart';
import '../../data/card_project_provider.dart';
import '../../data/workshop_actions.dart';
import '../../domain/frontend_templates.dart';
import '../../domain/models/card_project.dart';
import '../screens/frontend_editor_screen.dart';
import '../workshop_theme.dart';

/// 「前端面板」阶段。
///
/// 三件事挤在一个页面里：**挑模板 / 改 HTML / 交互预览**。
///
/// 预览用的是聊天里**同一个** [FrontendCardView]（同一个宿主包装、同一套变量垫片）。
/// 两边共用一个渲染器是刻意的 —— 否则会出现「工坊预览通过、聊天里挂不上」这种
/// 最难查的问题。
///
/// 预览的变量是**本地状态**，不写会话变量。用户在预览里点按钮只会改这里的值，
/// 真正写回会话变量发生在聊天里。
class FrontendStagePanel extends ConsumerStatefulWidget {
  const FrontendStagePanel({super.key, required this.project});

  final CardProject project;

  @override
  ConsumerState<FrontendStagePanel> createState() => _FrontendStagePanelState();
}

class _FrontendStagePanelState extends ConsumerState<FrontendStagePanel> {
  /// 打字时不要每敲一下就重拼几十 KB 的宿主脚本 + 重载 WebView。
  static const Duration _previewDebounce = Duration(milliseconds: 500);

  late final TextEditingController _htmlController;
  Timer? _debounce;

  /// 最后一次推给 provider 的 HTML。
  ///
  /// 用来区分「自己写下去的回声」和「外部改动（AI 生成）」—— 前者不能回灌
  /// 到输入框，否则用户打字的光标会被顶走。
  String _persistedHtml = '';

  /// 送进预览的原始 HTML（防抖后）。
  String _previewSource = '';

  /// 已经过 [FrontendCardHost.wrap] 的完整文档。
  String _previewDocument = '';

  Map<String, dynamic> _previewVariables = <String, dynamic>{};
  List<String> _logs = const [];
  String _loadedProjectId = '';

  bool _editorOpen = true;
  bool _logsOpen = false;
  String? _newKeyError;

  /// 面板需求 —— 直接作为 `userHint` 传给 AI。
  ///
  /// 之前 `_generate()` 根本没传这个参数（后端 `buildFrontend(userHint:)`
  /// 明明有），所以 AI 只能靠 `designSpec` 猜用户想要什么面板。
  final TextEditingController _hintController = TextEditingController();

  /// 对话式迭代的指令。
  final TextEditingController _refineController = TextEditingController();

  /// AI 改出来的新版，**等用户确认**才应用。
  ///
  /// 不直接覆盖：用户一句话说歪了就把好面板冲掉了。
  String _pendingHtml = '';

  /// 本地版本历史（最近 [_maxHistory] 版，只存内存、不落库）。
  final List<_FrontendVersion> _history = <_FrontendVersion>[];

  static const int _maxHistory = 5;

  /// 快捷需求 chip → 展开成一段具体描述。
  ///
  /// 手机上打字很累，点一下就填好，用户再按需改。
  static const Map<String, String> _quickHints = <String, String>{
    '状态条': '做成一条紧凑的状态条：主角头像 + 血条 + 体力条 + 当前心情标签，'
        '横向排列，整体只占一行高度。',
    '属性表': '做成属性表：每个变量一行，左边变量名、右边数值，数值带进度条，'
        '整体是一个可以往下滚的列表。',
    '关系网': '做成角色关系面板：每个角色一张小卡，显示名字、好感度进度条、'
        '当前态度标签，按好感度从高到低排列。',
    '资源 + 时间': '做成资源面板：金币、物品数量用大号数字突出显示，'
        '底部显示游戏内的时间与当前地点。',
    '战斗面板': '做成战斗面板：双方血条对峙，中间显示回合数与当前行动方，'
        '底部列出可用技能。',
  };

  final TextEditingController _newKeyController = TextEditingController();
  final TextEditingController _newValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _htmlController = TextEditingController();
    _adoptProject(widget.project, force: true);
  }

  @override
  void didUpdateWidget(covariant FrontendStagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级拿的是 provider 里的最新项目，所以「AI 生成完了」也是从这里进来的。
    _adoptProject(widget.project);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _htmlController.dispose();
    _hintController.dispose();
    _refineController.dispose();
    _newKeyController.dispose();
    _newValueController.dispose();
    super.dispose();
  }

  // --- 数据同步 ---

  /// 把项目里的前端产物同步到本地编辑状态。
  ///
  /// 只有「项目变了」或「HTML 被外部改过」才覆盖输入框；自己写下去的值
  /// 会原样回来，这里必须认出来并跳过，否则光标会被顶走。
  void _adoptProject(CardProject project, {bool force = false}) {
    final incoming = project.frontendHtml;
    final isNewProject = project.id != _loadedProjectId;
    final changedOutside = incoming != _persistedHtml.trim();
    if (!force && !isNewProject && !changedOutside) {
      return;
    }

    // 外部改动（AI 生成 / 别的入口写入）之前，先把旧版记进历史，
    // 这样用户随时能一键回退到「AI 动手之前」。
    if (changedOutside && !isNewProject) {
      _pushHistory(_htmlController.text, 'AI 生成前');
    }

    _loadedProjectId = project.id;
    _persistedHtml = incoming;
    _htmlController.text = incoming;
    _previewSource = incoming;
    _previewDocument = _wrap(incoming);
    _previewVariables = _seedVariables(project, incoming);
    _logs = const [];
  }

  static String _wrap(String html) {
    if (html.trim().isEmpty) {
      return '';
    }
    return FrontendCardHost.wrap(html, extraScript: FrontendCardBridge.shim);
  }

  /// 预览变量的初始值：优先用项目里已有的 MVU 变量表，其次用模板自带的建议值。
  Map<String, dynamic> _seedVariables(CardProject project, String html) {
    final fromMvu = _mvuVariables(project);
    if (fromMvu.isNotEmpty) {
      return fromMvu;
    }
    for (final template in FrontendTemplate.builtIn) {
      if (template.html.trim() == html.trim()) {
        return Map<String, dynamic>.from(template.variables);
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _mvuVariables(CardProject project) {
    final result = <String, dynamic>{};
    final raw = project.mvuVariablesJson.trim();
    if (raw.isEmpty) {
      return result;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return result;
      }
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final path = item['path']?.toString().trim() ?? '';
        if (path.isEmpty) {
          continue;
        }
        result[path] = _coerceValue(item['initial']);
      }
    } catch (_) {
      // 变量表是用户/AI 写的文本，坏了就当没有，不要挡住页面。
    }
    return result;
  }

  static dynamic _coerceValue(dynamic value) {
    if (value is num || value is bool) {
      return value;
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return 0;
    }
    return num.tryParse(text) ?? text;
  }

  // --- 编辑 HTML ---

  void _onHtmlChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_previewDebounce, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _previewSource = value;
        _previewDocument = _wrap(value);
      });
      _persist(value);
    });
  }

  void _persist(String value) {
    if (value.trim() == _persistedHtml.trim()) {
      return;
    }
    _persistedHtml = value;
    ref.read(cardProjectProvider.notifier).setFrontendHtml(
          widget.project.id,
          value,
        );
  }

  void _applyHtml(String html, {Map<String, dynamic>? variables}) {
    _debounce?.cancel();
    _pushHistory(_htmlController.text, '替换前');
    _htmlController.text = html;
    setState(() {
      _previewSource = html;
      _previewDocument = _wrap(html);
      if (variables != null) {
        _previewVariables = Map<String, dynamic>.from(variables);
      }
      _logs = const [];
    });
    _persist(html);
  }

  /// 记一版历史（内容去重 + 限长）。
  ///
  /// 只存内存 —— 面板本身已经在项目里落库了，历史只是操作缓冲，
  /// 杀掉进程重进就没意义了，不值得占存储。
  void _pushHistory(String html, String label) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_history.isNotEmpty && _history.first.html == trimmed) {
      return;
    }
    _history.insert(
      0,
      _FrontendVersion(html: trimmed, label: label, at: DateTime.now()),
    );
    while (_history.length > _maxHistory) {
      _history.removeLast();
    }
  }

  void _pickTemplate(FrontendTemplate template) {
    if (_previewSource.trim().isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: WorkshopColors.surface,
          title: const Text(
            '替换当前面板？',
            style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 16),
          ),
          content: Text(
            '当前的 HTML 会被「${template.label}」模板覆盖。',
            style: const TextStyle(
              color: WorkshopColors.textSecondary,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _applyHtml(
                  template.html.trim(),
                  variables: template.variables,
                );
              },
              child: const Text('替换'),
            ),
          ],
        ),
      );
      return;
    }
    _applyHtml(template.html.trim(), variables: template.variables);
  }

  // --- 变量调试 ---

  void _setVariable(String key, dynamic value) {
    setState(() {
      _previewVariables = <String, dynamic>{
        ..._previewVariables,
        key: value,
      };
    });
  }

  void _deleteVariable(String key) {
    final next = Map<String, dynamic>.from(_previewVariables)..remove(key);
    setState(() {
      _previewVariables = next;
    });
  }

  void _addVariable() {
    final key = _newKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _newKeyError = '变量名不能为空');
      return;
    }
    if (_previewVariables.containsKey(key)) {
      setState(() => _newKeyError = '这个变量已经存在');
      return;
    }
    setState(() {
      _newKeyError = null;
      _previewVariables = <String, dynamic>{
        ..._previewVariables,
        key: _coerceValue(_newValueController.text),
      };
    });
    _newKeyController.clear();
    _newValueController.clear();
  }

  Future<void> _editVariable(String key) async {
    final controller = TextEditingController(
      text: _previewVariables[key]?.toString() ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WorkshopColors.surface,
        title: Text(
          key,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 15,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: WorkshopColors.textPrimary),
          decoration: WorkshopWidgets.inputDecoration('新的值'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      _setVariable(key, _coerceValue(result));
    }
  }

  void _resetVariables() {
    setState(() {
      _previewVariables = _seedVariables(
        widget.project,
        _htmlController.text,
      );
    });
  }

  // --- AI 生成 ---

  Future<void> _generate() async {
    final actions = ref.read(workshopActionsProvider);
    final project = actions.projectOf(widget.project.id);
    if (project == null) {
      return;
    }
    // ⛔ 这里以前没传 userHint —— 后端 `buildFrontend(userHint:)` 明明有参数，
    // 但 AI 拿不到，只能靠 designSpec 猜用户想要什么面板。
    final ok = await actions.generateFrontend(
      widget.project.id,
      userHint: _hintController.text.trim(),
    );
    if (!mounted || !ok) {
      return;
    }
    final updated = actions.projectOf(widget.project.id);
    if (updated != null) {
      _adoptProject(updated, force: true);
      setState(() {});
    }
  }

  /// 对话式迭代：让 AI 按一句话要求改面板。
  ///
  /// 结果进 [_pendingHtml] 等确认，**不直接覆盖** —— 用户一句话说歪了
  /// 不该把好面板冲掉。
  Future<void> _refine() async {
    final instruction = _refineController.text.trim();
    if (instruction.isEmpty) {
      return;
    }
    final actions = ref.read(workshopActionsProvider);
    final html = await actions.refineFrontend(widget.project.id, instruction);
    if (!mounted || html == null || html.trim().isEmpty) {
      return;
    }
    setState(() {
      _pendingHtml = html.trim();
    });
    _refineController.clear();
  }

  void _applyPending() {
    if (_pendingHtml.trim().isEmpty) {
      return;
    }
    final html = _pendingHtml;
    setState(() => _pendingHtml = '');
    _applyHtml(html);
  }

  void _discardPending() {
    setState(() => _pendingHtml = '');
  }

  /// 把待确认版本塞进预览（不落库、不动编辑器）。
  void _previewPending() {
    if (_pendingHtml.trim().isEmpty) {
      return;
    }
    _debounce?.cancel();
    setState(() {
      _previewSource = _pendingHtml;
      _previewDocument = _wrap(_pendingHtml);
      _logs = const [];
    });
  }

  void _applyQuickHint(String label) {
    final text = _quickHints[label];
    if (text == null) {
      return;
    }
    _hintController.text = text;
    setState(() {});
  }

  Future<void> _showHistoryDialog() async {
    if (_history.isEmpty) {
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: WorkshopColors.surface,
        title: const Text(
          '历史版本',
          style: TextStyle(color: WorkshopColors.textPrimary, fontSize: 15),
        ),
        children: [
          for (var i = 0; i < _history.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(i),
              child: Text(
                '${_history[i].label} · ${_history[i].html.length} 字符 · '
                '${_formatTime(_history[i].at)}',
                style: const TextStyle(
                  color: WorkshopColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    _applyHtml(_history[picked].html);
  }

  static String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // --- 渲染 ---

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final state = ref.watch(cardProjectProvider);
    final busy = state.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIntroCard(project, busy),
        const SizedBox(height: 12),
        _buildIterateCard(project, busy),
        const SizedBox(height: 12),
        _buildTemplateCard(project, busy),
        const SizedBox(height: 12),
        _buildPreviewCard(busy),
        const SizedBox(height: 12),
        _buildVariableCard(busy),
        const SizedBox(height: 12),
        _buildEditorCard(busy),
        if (_logs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLogsCard(),
        ],
      ],
    );
  }

  Widget _buildIntroCard(CardProject project, bool busy) {
    return WorkshopWidgets.card(
      title: '前端面板 (Frontend Panel)',
      subtitle: '面板 HTML 跟着角色卡走，不进消息、不烧 token。'
          '每轮只输出一个挂载标记，渲染时再从卡上取面板。',
      accentColor: WorkshopColors.stageDone,
      trailing: WorkshopWidgets.chip(
        label: project.hasFrontend ? '已设计' : '未设计',
        selected: project.hasFrontend,
        onTap: null,
        accentColor: WorkshopColors.stageDone,
      ),
      children: [
        TextField(
          controller: _hintController,
          enabled: !busy,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 12,
            height: 1.5,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '想要什么样的面板？例如「左上角一条血条，下面三个属性，底部显示当前时间」',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in _quickHints.keys)
              WorkshopWidgets.chip(
                label: label,
                selected: false,
                icon: Icons.bolt,
                onTap: busy ? null : () => _applyQuickHint(label),
                accentColor: WorkshopColors.stageDone,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.primaryButton(
                label: project.hasFrontend ? '让 AI 重做一版' : '让 AI 生成面板',
                icon: Icons.auto_awesome,
                busy: busy,
                onPressed: busy ? null : _generate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '清空面板',
                icon: Icons.delete_outline,
                onPressed: busy || !project.hasFrontend
                    ? null
                    : () => _applyHtml('', variables: const {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '面板可以读写会话变量：YKX.getVariable("角色.好感度") / '
          'YKX.setVariable(...) / YKX.onVariablesChanged(render)。'
          '变量名建议直接用 MVU 的路径。',
          style: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildIterateCard(CardProject project, bool busy) {
    final hasPanel = project.frontendHtml.trim().isNotEmpty;

    return WorkshopWidgets.card(
      title: '对话式迭代 (Refine)',
      subtitle: hasPanel
          ? '用一句话说要改什么，AI 会重写整块面板。改完先给你看，确认了才应用。'
          : '先生成一版面板，才能迭代。',
      accentColor: WorkshopColors.accent,
      trailing: _history.isEmpty
          ? null
          : WorkshopWidgets.chip(
              label: '历史 ${_history.length}',
              selected: false,
              icon: Icons.history,
              onTap: busy ? null : _showHistoryDialog,
              accentColor: WorkshopColors.textHint,
            ),
      children: [
        TextField(
          controller: _refineController,
          enabled: !busy && hasPanel,
          maxLines: 2,
          minLines: 1,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 12,
          ),
          decoration: WorkshopWidgets.inputDecoration(
            '例如「加一个金钱字段」「把血条改成蓝色」「去掉底部的日志区」',
          ),
        ),
        const SizedBox(height: 8),
        WorkshopWidgets.secondaryButton(
          label: '让 AI 改一版',
          icon: Icons.auto_fix_high,
          onPressed: busy || !hasPanel ? null : _refine,
        ),
        if (_pendingHtml.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildPendingBox(busy),
        ],
      ],
    );
  }

  /// 待确认的新版面板。
  ///
  /// 三个动作：预览（只改预览，不落库）/ 应用（写进项目）/ 放弃。
  Widget _buildPendingBox(bool busy) {
    final currentLength = widget.project.frontendHtml.trim().length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: WorkshopColors.surfaceSunken,
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        border: Border.all(color: WorkshopColors.stageDone, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI 改好了一版，还没有应用。',
            style: TextStyle(
              color: WorkshopColors.stageDone,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '新版 ${_pendingHtml.length} 字符 · 当前 $currentLength 字符',
            style: const TextStyle(
              color: WorkshopColors.textHint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: WorkshopWidgets.secondaryButton(
                  label: '预览',
                  icon: Icons.visibility,
                  onPressed: busy ? null : _previewPending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WorkshopWidgets.primaryButton(
                  label: '应用',
                  icon: Icons.check,
                  onPressed: busy ? null : _applyPending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WorkshopWidgets.secondaryButton(
                  label: '放弃',
                  icon: Icons.close,
                  onPressed: busy ? null : _discardPending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(CardProject project, bool busy) {
    return WorkshopWidgets.card(
      title: '从模板开始',
      subtitle: '模板都是自包含的（无 CDN、无框架），可以直接改。',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final template in FrontendTemplate.builtIn)
              WorkshopWidgets.chip(
                label: template.label,
                selected: false,
                icon: Icons.dashboard_customize_outlined,
                onTap: busy ? null : () => _pickTemplate(template),
                accentColor: WorkshopColors.worldbook,
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final template in FrontendTemplate.builtIn)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '· ${template.label} —— ${template.description}',
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewCard(bool busy) {
    return WorkshopWidgets.card(
      title: '交互预览',
      subtitle: '在预览里点按钮会直接改下面的变量 —— 和聊天里的行为完全一致。',
      accentColor: WorkshopColors.accent,
      trailing: WorkshopWidgets.chip(
        label: '${_previewVariables.length} 个变量',
        selected: false,
        onTap: null,
      ),
      children: [
        if (_previewDocument.isEmpty)
          WorkshopWidgets.emptyHint(
            '还没有面板。挑一个模板，或者让 AI 生成一版。\n'
            '面板是一段自包含的 HTML（可以带 <style> 和 <script>）。',
          )
        else
          FrontendCardView(
            html: _previewDocument,
            variables: _previewVariables,
            isGenerating: busy,
            borderColor: WorkshopColors.stroke,
            minHeight: 180,
            onDebugLogs: (logs) {
              if (!mounted) {
                return;
              }
              setState(() => _logs = logs);
            },
            onVariableSet: (path, value) => _setVariable(path, value),
            onVariableDelete: _deleteVariable,
          ),
      ],
    );
  }

  Widget _buildVariableCard(bool busy) {
    final entries = _previewVariables.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return WorkshopWidgets.card(
      title: '变量调试器',
      subtitle: '只影响预览，不会写进会话变量。',
      accentColor: WorkshopColors.warning,
      trailing: WorkshopWidgets.chip(
        label: '重置',
        selected: false,
        icon: Icons.restart_alt,
        onTap: busy ? null : _resetVariables,
        accentColor: WorkshopColors.warning,
      ),
      children: [
        if (entries.isEmpty)
          const Text(
            '还没有变量。加几个，面板才有东西可渲染。',
            style: TextStyle(color: WorkshopColors.textHint, fontSize: 12),
          )
        else
          for (final entry in entries)
            _buildVariableRow(entry.key, entry.value, busy),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _newKeyController,
                enabled: !busy,
                style: const TextStyle(
                  color: WorkshopColors.textPrimary,
                  fontSize: 12,
                ),
                decoration: WorkshopWidgets.inputDecoration(
                  '变量名，如 角色.好感度',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _newValueController,
                enabled: !busy,
                style: const TextStyle(
                  color: WorkshopColors.textPrimary,
                  fontSize: 12,
                ),
                decoration: WorkshopWidgets.inputDecoration('初始值'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: busy ? null : _addVariable,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              color: WorkshopColors.accent,
              tooltip: '添加变量',
            ),
          ],
        ),
        if (_newKeyError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _newKeyError!,
              style: const TextStyle(
                color: WorkshopColors.danger,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVariableRow(String key, dynamic value, bool busy) {
    final isNumber = value is num;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WorkshopColors.surfaceSunken,
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          GestureDetector(
            onTap: busy ? null : () => _editVariable(key),
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: WorkshopColors.surfaceSoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WorkshopColors.stroke, width: 0.8),
              ),
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WorkshopColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          if (isNumber) ...[
            _stepButton(
              icon: Icons.remove,
              onTap: busy ? null : () => _setVariable(key, value - 1),
            ),
            _stepButton(
              icon: Icons.add,
              onTap: busy ? null : () => _setVariable(key, value + 1),
            ),
          ],
          _stepButton(
            icon: Icons.close,
            color: WorkshopColors.danger,
            onTap: busy ? null : () => _deleteVariable(key),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Icon(
          icon,
          size: 15,
          color: onTap == null
              ? WorkshopColors.textHint
              : (color ?? WorkshopColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildEditorCard(bool busy) {
    return WorkshopWidgets.card(
      title: '面板 HTML',
      subtitle: '自包含的 HTML + CSS + JS。保存是自动的，改完不用点按钮。',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkshopWidgets.chip(
            label: '全屏',
            selected: false,
            icon: Icons.fullscreen,
            onTap: busy ? null : _openFullScreenEditor,
            accentColor: WorkshopColors.accent,
          ),
          const SizedBox(width: 6),
          WorkshopWidgets.chip(
            label: _editorOpen ? '收起' : '展开',
            selected: _editorOpen,
            icon: _editorOpen ? Icons.expand_less : Icons.expand_more,
            onTap: () => setState(() => _editorOpen = !_editorOpen),
          ),
        ],
      ),
      children: [
        if (_editorOpen)
          Container(
            decoration: BoxDecoration(
              color: WorkshopColors.surfaceSunken,
              borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
              border: Border.all(color: WorkshopColors.stroke, width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TextField(
              controller: _htmlController,
              enabled: !busy,
              onChanged: _onHtmlChanged,
              maxLines: null,
              minLines: 14,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                color: WorkshopColors.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '<div>...</div>\n<style>...</style>\n<script>...</script>',
                hintStyle: TextStyle(
                  color: WorkshopColors.textHint,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 打开全屏编辑器。返回非 null 就应用。
  Future<void> _openFullScreenEditor() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => FrontendEditorScreen(
          initialHtml: _htmlController.text,
          variablePaths: _variablePathsForEditor(),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _applyHtml(result);
  }

  /// 编辑器工具栏要列的变量路径：MVU 变量表 ∪ 预览里已有的键。
  List<String> _variablePathsForEditor() {
    final paths = <String>{
      ..._mvuVariables(widget.project).keys,
      ..._previewVariables.keys,
    }.toList()
      ..sort();
    return paths;
  }

  Widget _buildLogsCard() {    return WorkshopWidgets.card(
      title: '面板运行日志',
      subtitle: '卡片里 console 报的错、被拦的跳转都会出现在这里。',
      accentColor: WorkshopColors.danger,
      trailing: WorkshopWidgets.chip(
        label: _logsOpen ? '收起' : '${_logs.length} 条',
        selected: _logsOpen,
        icon: _logsOpen ? Icons.expand_less : Icons.expand_more,
        onTap: () => setState(() => _logsOpen = !_logsOpen),
      ),
      children: [
        if (_logsOpen)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WorkshopColors.surfaceSunken,
              borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _logs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: WorkshopColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Text(
            _logs.first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WorkshopColors.textHint,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
  }
}

/// 面板的一个历史版本。
///
/// 只存在内存里 —— 用来做「一键回退」的操作缓冲，不落库。
class _FrontendVersion {
  const _FrontendVersion({
    required this.html,
    required this.label,
    required this.at,
  });

  final String html;

  /// 这一版是怎么来的（「AI 生成前」/「替换前」）。
  final String label;

  final DateTime at;
}
