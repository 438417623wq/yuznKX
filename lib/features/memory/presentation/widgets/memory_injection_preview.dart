import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memory_provider.dart';
import '../../domain/models/memory_table.dart';
import '../memory_theme.dart';

/// 打开「记忆注入预览」底部弹窗。
///
/// 展示当前会话**实际发给模型**的记忆文本（即 `getFormattedMemory()`
/// 的返回值），并附带表级统计，让「记忆有没有生效」可自查。
Future<void> showMemoryInjectionPreview(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const MemoryInjectionPreviewSheet(),
  );
}

class MemoryInjectionPreviewSheet extends ConsumerStatefulWidget {
  const MemoryInjectionPreviewSheet({super.key});

  @override
  ConsumerState<MemoryInjectionPreviewSheet> createState() =>
      _MemoryInjectionPreviewSheetState();
}

class _MemoryInjectionPreviewSheetState
    extends ConsumerState<MemoryInjectionPreviewSheet> {
  bool _showRaw = true;

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(memoryProvider);
    final settings = ref.watch(memoryPluginSettingsProvider);
    final text = ref
        .read(memoryProvider.notifier)
        .getFormattedMemory(settings: settings);

    final injected = tables.where((t) => t.isEnabled && t.behavior.toChat).toList();
    final totalRows = injected.fold<int>(0, (sum, t) => sum + t.rows.length);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: MemoryTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(text),
          if (text.isEmpty) _buildEmptyState(settings, tables),
          if (text.isNotEmpty) ...[
            _buildStats(injected, totalRows, text),
            const Divider(height: 1, color: MemoryTheme.divider),
            Flexible(child: _buildContent(text)),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MemoryTheme.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '注入内容预览 (Injection Preview)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '这是模型实际看到的记忆文本',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (text.isNotEmpty)
            IconButton(
              tooltip: _showRaw ? '切换为着色视图' : '切换为原文',
              icon: Icon(
                _showRaw ? Icons.art_track : Icons.code,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: () => setState(() => _showRaw = !_showRaw),
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

  Widget _buildStats(List<MemoryTable> injected, int totalRows, String text) {
    // 粗略估算注入体积：CJK 系数 0.6（与 chat_provider 的 token 估算口径一致）。
    final approxTokens = (text.length * 0.6).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('参与注入', '${injected.length} 张表'),
          _chip('记录总数', '$totalRows 条'),
          _chip('字符数', '${text.length}'),
          _chip('约 tokens', '~$approxTokens'),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MemoryTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MemoryTheme.accent.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: MemoryTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    MemoryPluginSettings settings,
    List<MemoryTable> tables,
  ) {
    String reason;
    if (!settings.isPluginEnabled) {
      reason = '记忆系统已关闭。请到上方「基础」分组中启用。';
    } else if (!settings.isAiReadTable) {
      reason = '「AI 读取记忆表格」已关闭，因此不会注入任何记忆。';
    } else if (tables.isEmpty) {
      reason = '当前会话还没有记忆表格。';
    } else if (!tables.any((t) => t.behavior.toChat)) {
      reason = '所有表格都关闭了「参与对话注入」，整块记忆不会发送给模型。';
    } else {
      reason = '当前没有已启用的表格内容。';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 56, color: Colors.white24),
          const SizedBox(height: 14),
          const Text(
            '没有内容会被注入',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: _showRaw
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MemoryTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MemoryTheme.divider),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.55,
                  color: Colors.white70,
                ),
              ),
            )
          : _buildHighlighted(text),
    );
  }

  /// 着色视图：逐行判断语义，让 `[0] 表名` / `Columns:` / `Note:` / 数据行
  /// 一眼可分辨。比一大坨等宽文本好扫得多。
  Widget _buildHighlighted(String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) _buildLine(line),
      ],
    );
  }

  Widget _buildLine(String line) {
    TextStyle style;
    Color? decoration;
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      return const SizedBox(height: 8);
    } else if (trimmed.startsWith('#')) {
      // 标题行
      style = const TextStyle(
        color: MemoryTheme.accent,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
        height: 1.5,
      );
    } else if (trimmed.startsWith('-')) {
      // 规则说明
      style = const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.5,
      );
    } else if (RegExp(r'^\[\d+\]').hasMatch(trimmed)) {
      // 表头：[0] 角色特征表格 (Required)
      style = const TextStyle(
        color: Color(0xFF8AEBC6),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        height: 1.6,
      );
      decoration = MemoryTheme.accent.withValues(alpha: 0.35);
    } else if (trimmed.startsWith('Columns:')) {
      style = const TextStyle(
        color: Color(0xFF79BEFF),
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.5,
      );
    } else if (trimmed.startsWith('Note:')) {
      style = const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontStyle: FontStyle.italic,
        fontFamily: 'monospace',
        height: 1.5,
      );
    } else if (trimmed == '(Empty)' || trimmed == '(Disabled)') {
      style = const TextStyle(
        color: MemoryTheme.warning,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.5,
      );
    } else {
      // 数据行：`0 -> 0:角色名, 1:描述`
      style = const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.55,
      );
    }

    return Container(
      width: double.infinity,
      decoration: decoration == null
          ? null
          : BoxDecoration(
              border: Border(left: BorderSide(color: decoration, width: 3)),
            ),
      padding: decoration == null
          ? EdgeInsets.zero
          : const EdgeInsets.only(left: 8),
      child: Text(line, style: style),
    );
  }
}
