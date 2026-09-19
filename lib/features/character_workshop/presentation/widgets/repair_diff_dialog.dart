import 'package:flutter/material.dart';

import '../../data/workshop_actions.dart';
import '../../domain/text_diff.dart';
import '../workshop_theme.dart';

/// 「修这条」的前后对比。
///
/// 逐条确认修复的核心：**先看再改**。直接覆盖的话用户连模型改成了什么样
/// 都不知道，出了问题也回不去。
class RepairDiffDialog extends StatelessWidget {
  const RepairDiffDialog({super.key, required this.repair});

  final IssueRepair repair;

  /// 打开对话框。返回 true 表示用户选择了应用。
  static Future<bool> show(BuildContext context, IssueRepair repair) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => RepairDiffDialog(repair: repair),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lines = TextDiff.compute(repair.before, repair.after);
    final stats = TextDiff.statsOf(lines);
    final visible = TextDiff.collapse(lines, context: 2);
    final unchanged = stats.isEmpty;

    return AlertDialog(
      backgroundColor: WorkshopColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '修复「${repair.entryTitle}」',
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            unchanged
                ? '模型没有改动内容 —— 建议放弃这一版'
                : '共 +${stats.added} 行 / -${stats.removed} 行',
            style: TextStyle(
              color: unchanged
                  ? WorkshopColors.warning
                  : WorkshopColors.stageDone,
              fontSize: 11,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: Container(
            decoration: BoxDecoration(
              color: WorkshopColors.surfaceSunken,
              borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
              border: Border.all(color: WorkshopColors.stroke, width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in visible) _buildLine(line),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('放弃'),
        ),
        FilledButton(
          onPressed:
              unchanged ? null : () => Navigator.of(context).pop(true),
          child: const Text('应用这版'),
        ),
      ],
    );
  }

  Widget _buildLine(DiffLine line) {
    if (line.text == TextDiff.ellipsisMarker) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          '⋯⋯ 未改动的部分已折叠 ⋯⋯',
          style: TextStyle(color: WorkshopColors.textHint, fontSize: 10),
        ),
      );
    }

    final (background, foreground, prefix) = switch (line.kind) {
      DiffKind.add => (
          WorkshopColors.successSoft,
          WorkshopColors.success,
          '+ ',
        ),
      DiffKind.remove => (
          WorkshopColors.dangerSoft,
          WorkshopColors.danger,
          '- ',
        ),
      DiffKind.keep => (
          Colors.transparent,
          WorkshopColors.textHint,
          '  ',
        ),
    };

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        '$prefix${line.text}',
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}
