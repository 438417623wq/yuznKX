import 'package:flutter/material.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';

import '../workshop_theme.dart';

/// 全屏面板编辑器。
///
/// 为什么需要它：面板 HTML 动辄几百行，在阶段卡片那个小输入框里改太难受，
/// 而且手打 `YKX.getVariable('角色.好感度')` 这种路径在手机上是酷刑。
/// 这里给足空间 + 一排「点一下就插入」的变量按钮。
///
/// 高亮走 `flutter_highlighter`（项目已有依赖）—— ⛔ 它只读，
/// 所以做成「编辑 / 高亮预览」切换，而不是试图把高亮叠在 TextField 上。
class FrontendEditorScreen extends StatefulWidget {
  const FrontendEditorScreen({
    super.key,
    required this.initialHtml,
    this.variablePaths = const <String>[],
    this.title = '编辑面板 HTML',
  });

  final String initialHtml;

  /// 卡上可用的变量路径（点一下插入 `YKX.getVariable('...')`）。
  final List<String> variablePaths;

  final String title;

  @override
  State<FrontendEditorScreen> createState() => _FrontendEditorScreenState();
}

class _FrontendEditorScreenState extends State<FrontendEditorScreen> {
  late final TextEditingController _controller;
  bool _highlight = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialHtml);
    _controller.addListener(_markDirty);
  }

  @override
  void dispose() {
    _controller.removeListener(_markDirty);
    _controller.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) {
      return;
    }
    setState(() => _dirty = true);
  }

  /// 在光标处插入片段。没聚焦过（selection 无效）就追加到末尾。
  void _insertSnippet(String snippet) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, snippet);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
    if (_highlight) {
      setState(() => _highlight = false);
    }
  }

  void _close() {
    // 没改过就返回 null，调用方据此跳过无意义的写入。
    Navigator.of(context).pop(_dirty ? _controller.text : null);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _close();
      },
      child: Scaffold(
        backgroundColor: WorkshopColors.pageBg,
        appBar: AppBar(
          backgroundColor: WorkshopColors.surface,
          foregroundColor: WorkshopColors.textPrimary,
          title: Text(widget.title, style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              tooltip: _highlight ? '切回编辑' : '高亮预览',
              icon: Icon(_highlight ? Icons.edit_note : Icons.highlight),
              onPressed: () => setState(() => _highlight = !_highlight),
            ),
            TextButton(
              onPressed: _close,
              child: const Text(
                '完成',
                style: TextStyle(color: WorkshopColors.accent),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: _highlight ? _buildHighlighted() : _buildEditor(),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部工具条：一排变量，点一下插入读取代码。
  Widget _buildToolbar() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: WorkshopColors.surface,
        border: Border(
          bottom: BorderSide(color: WorkshopColors.stroke, width: 0.8),
        ),
      ),
      child: widget.variablePaths.isEmpty
          ? const Center(
              child: Text(
                '这张卡还没有变量 —— 先去 MVU 阶段设计变量。',
                style: TextStyle(
                  color: WorkshopColors.textHint,
                  fontSize: 11,
                ),
              ),
            )
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              children: [
                for (final path in widget.variablePaths)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _toolChip(
                      label: path,
                      icon: Icons.data_object,
                      onTap: () =>
                          _insertSnippet("YKX.getVariable('$path')"),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _toolChip(
                    label: '监听变化',
                    icon: Icons.refresh,
                    onTap: () => _insertSnippet(
                      'YKX.onVariablesChanged(function (vars, reason) { render(); });',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _toolChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: WorkshopColors.surfaceSoft,
          borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
          border: Border.all(color: WorkshopColors.stroke, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: WorkshopColors.accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      color: WorkshopColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          color: WorkshopColors.textPrimary,
          fontSize: 13,
          height: 1.5,
          fontFamily: 'monospace',
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '<div>...</div>\n<style>...</style>\n<script>...</script>',
          hintStyle: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildHighlighted() {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      return const Center(
        child: Text(
          '没有内容可以高亮。',
          style: TextStyle(color: WorkshopColors.textHint, fontSize: 12),
        ),
      );
    }
    return Container(
      color: const Color(0xFF282C34),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: HighlightView(
          text,
          // ⛔ 必须是 'xml'，不能写 'html' —— `highlighter` 包的语言表里
          // HTML 走的就是 highlight.js 的 `xml` 定义。传 'html' 不会报错，
          // 但会**静默降级成纯文本**（`_getLanguage(lang) ?? plaintext`），
          // 白做一场高亮。
          language: 'xml',
          theme: atomOneDarkTheme,
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
