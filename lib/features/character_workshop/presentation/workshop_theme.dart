import 'package:flutter/material.dart';

/// 创作工坊的设计令牌。
///
/// 原本这些颜色散落在 `character_workshop_screen.dart` 里（13 处硬编码），
/// 重构时集中到这里，五个阶段的界面共用一套，避免各写各的。
class WorkshopColors {
  const WorkshopColors._();

  static const Color pageBg = Color(0xFF11152A);
  static const Color surface = Color(0xFF1A2140);
  static const Color surfaceSoft = Color(0xFF222B4F);
  static const Color surfaceSunken = Color(0xFF161C36);
  static const Color stroke = Color(0xFF323F6C);
  static const Color strokeSoft = Color(0xFF27314F);

  static const Color textPrimary = Color(0xFFEAF0FF);
  static const Color textSecondary = Color(0xFFA4B0D3);
  static const Color textHint = Color(0xFF6B7AA8);

  static const Color accent = Color(0xFF8EA1FF);
  static const Color accentSoft = Color(0xFF2A3560);

  static const Color success = Color(0xFF7EE787);
  static const Color successSoft = Color(0xFF1E3A2A);

  static const Color warning = Color(0xFFFFB347);
  static const Color warningSoft = Color(0xFF3A2E1A);

  static const Color danger = Color(0xFFFF8A8A);
  static const Color dangerSoft = Color(0xFF3A2130);

  /// 阶段进度条上的已完成色。
  static const Color stageDone = Color(0xFF8AEBC6);

  /// 世界书条目用青色区分，和角色卡字段（蓝紫）拉开。
  static const Color worldbook = Color(0xFF6ED4C0);
  static const Color worldbookSoft = Color(0xFF1B3A38);
}

/// 创作工坊的通用排版常量。
class WorkshopMetrics {
  const WorkshopMetrics._();

  static const double pagePadding = 16;
  static const double cardRadius = 14;
  static const double fieldRadius = 10;
  static const double chipRadius = 20;
}

/// 工坊里反复用到的小组件。
///
/// 都是无状态函数式构造，不持有任何 State，方便在五个阶段的 part 文件里共用。
class WorkshopWidgets {
  const WorkshopWidgets._();

  /// 带标题的卡片容器。
  static Widget card({
    required String title,
    String? subtitle,
    Widget? trailing,
    List<Widget> children = const <Widget>[],
    Color? accentColor,
  }) {
    final tint = accentColor ?? WorkshopColors.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: WorkshopColors.surface,
        borderRadius: BorderRadius.circular(WorkshopMetrics.cardRadius),
        border: Border.all(color: WorkshopColors.stroke, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: WorkshopColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 11),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: WorkshopColors.textSecondary,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }

  static Widget sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: WorkshopColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static InputDecoration inputDecoration(
    String hint, {
    bool dense = true,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: const TextStyle(color: WorkshopColors.textHint, fontSize: 12),
      isDense: dense,
      filled: true,
      fillColor: WorkshopColors.surfaceSoft,
      contentPadding:
          contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        borderSide: const BorderSide(color: WorkshopColors.stroke, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        borderSide: const BorderSide(color: WorkshopColors.stroke, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
        borderSide: const BorderSide(color: WorkshopColors.accent, width: 1),
      ),
    );
  }

  /// 等宽分段选择行（自绘，避免深色主题下 `SegmentedButton` 样式失控）。
  static Widget segmentedRow<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T> onChanged,
    bool enabled = true,
  }) {
    return Row(
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == values.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: enabled ? () => onChanged(values[i]) : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: values[i] == selected
                        ? WorkshopColors.accentSoft
                        : WorkshopColors.surfaceSoft,
                    borderRadius:
                        BorderRadius.circular(WorkshopMetrics.fieldRadius),
                    border: Border.all(
                      color: values[i] == selected
                          ? WorkshopColors.accent
                          : WorkshopColors.stroke,
                      width: values[i] == selected ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    label(values[i]),
                    style: TextStyle(
                      color: values[i] == selected
                          ? WorkshopColors.textPrimary
                          : (enabled
                              ? WorkshopColors.textSecondary
                              : WorkshopColors.textHint),
                      fontSize: 12,
                      fontWeight: values[i] == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 可点击的小标签。
  static Widget chip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    IconData? icon,
    Color? accentColor,
  }) {
    final tint = accentColor ?? WorkshopColors.accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? WorkshopColors.accentSoft : WorkshopColors.surfaceSoft,
          borderRadius: BorderRadius.circular(WorkshopMetrics.chipRadius),
          border: Border.all(
            color: selected ? tint : WorkshopColors.stroke,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected ? tint : WorkshopColors.textHint,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? WorkshopColors.textPrimary
                    : WorkshopColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 主按钮。
  static Widget primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool busy = false,
    Color? background,
    Color? foreground,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (icon == null ? const SizedBox.shrink() : Icon(icon, size: 18)),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          backgroundColor: background ?? WorkshopColors.accent,
          foregroundColor: foreground ?? const Color(0xFF10142B),
          disabledBackgroundColor: WorkshopColors.stroke,
          disabledForegroundColor: WorkshopColors.textHint,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 次要按钮。
  static Widget secondaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: WorkshopColors.textPrimary,
          side: const BorderSide(color: WorkshopColors.stroke, width: 0.8),
          padding: const EdgeInsets.symmetric(vertical: 11),
          disabledForegroundColor: WorkshopColors.textHint,
        ),
      ),
    );
  }

  /// 错误提示条。
  static Widget errorBox({
    required String message,
    String? rawOutput,
    VoidCallback? onViewRaw,
    VoidCallback? onDismiss,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: WorkshopColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkshopColors.danger, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 16, color: WorkshopColors.danger),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '出错了',
                  style: TextStyle(
                    color: WorkshopColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 14, color: WorkshopColors.textHint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (rawOutput != null &&
              rawOutput.trim().isNotEmpty &&
              onViewRaw != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onViewRaw,
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text('查看模型原始输出'),
                style: TextButton.styleFrom(
                  foregroundColor: WorkshopColors.textSecondary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 空态提示。
  static Widget emptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WorkshopColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: WorkshopColors.textSecondary,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }

  /// 进度条。
  static Widget progressBar(double value, {Color? color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 5,
        backgroundColor: WorkshopColors.strokeSoft,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? WorkshopColors.stageDone,
        ),
      ),
    );
  }
}

/// 时间格式化（工坊内共用）。
String formatWorkshopTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

/// 相对时间（「3 分钟前」）。
String relativeWorkshopTime(DateTime time) {
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
  return formatWorkshopTime(time);
}
