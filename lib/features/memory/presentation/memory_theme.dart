import 'package:flutter/material.dart';

/// 记忆模块的统一设计令牌。
///
/// 配色方向：**底色融入全局主题**（与 `app.dart` 的 0xFF1A1B26 /
/// 0xFF16161E 同族），青绿 [accent] 只做强调色。这样底部 Tab 切换时
/// 不会出现整页色系跳变。
///
/// 所有颜色必须从这里取，禁止在页面里散落一次性硬编码色值。
class MemoryTheme {
  const MemoryTheme._();

  /// 主强调色（青绿）。用于选中态、焦点边框、关键数字。
  static const Color accent = Color(0xFF24C3B5);

  /// 强调色上的文字 / 图标色（深青，保证对比度）。
  static const Color onAccent = Color(0xFF04211D);

  /// 顶栏背景。与全局 AppBarTheme（0xFF16161E）一致。
  static const Color appBar = Color(0xFF16161E);

  /// 页面主背景。与全局 scaffoldBackgroundColor（0xFF1A1B26）一致。
  static const Color bg = Color(0xFF1A1B26);

  /// 左右栏 / 顶部分段条的底色，比 [bg] 深一档，用来划分区域。
  static const Color panel = Color(0xFF15161F);

  /// 卡片 / 分组容器背景。
  static const Color surface = Color(0xFF232433);

  /// 抬升一层的表面（弹窗、菜单、底部面板）。
  static const Color surfaceElevated = Color(0xFF2B2C3D);

  /// 边框（半透明白）。
  static const Color border = Color(0x33FFFFFF);

  /// 细分隔线。
  static const Color divider = Color(0x1AFFFFFF);

  /// 未选中 tile / 分段 chip 的淡填充。
  static const Color fillSubtle = Color(0x14FFFFFF);

  /// 输入框填充色（比所在表面更暗的半透明，适配 bg 与 surface 两种底）。
  static const Color inputFill = Color(0x590D0E16);

  /// 正文色。
  static const Color textPrimary = Colors.white;

  /// 次级说明文字。
  static const Color textMuted = Colors.white60;

  /// 更弱的提示文字。
  static const Color textFaint = Colors.white38;

  /// 字段标签色（比正文弱、比提示强）。
  static const Color label = Color(0xFF8A93A8);

  /// 统计信息色。
  static const Color info = Color(0xFFA5AFCF);

  /// 空值占位文字（「未填写」）。
  static const Color emptyValue = Color(0xFF666F87);

  /// 危险操作（删除）。
  static const Color danger = Color(0xFFFF8A8A);

  /// 编辑操作。
  static const Color edit = Color(0xFF79BEFF);

  /// 启用态图标。
  static const Color enabled = Color(0xFF8AEBC6);

  /// 警示文字（可预期的问题提示）。
  static const Color warning = Color(0xFFFFC857);

  /// 字号阶梯（全模块只允许这 5 档）：
  /// 22 页面题 / 15 卡片题 / 13 正文 / 12 辅助 / 11 最小。
  static const double fontTitle = 15;
  static const double fontBody = 13;
  static const double fontSecondary = 12;
  static const double fontTiny = 11;

  /// 记忆模块的局部主题：把 `colorScheme.primary` 换成青绿，
  /// 这样 FilledButton / TextButton / Slider / Switch 等控件
  /// 不会再漏出全局主题的 indigo 色。
  static ThemeData themeData(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      surface: bg,
    );
    return base.copyWith(colorScheme: scheme);
  }

  /// 统一输入框样式。
  static InputDecoration fieldDecoration(
    String label, {
    bool dense = false,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: fontTiny),
      filled: true,
      fillColor: inputFill,
      isDense: dense,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
          : null,
      border: _border(border),
      enabledBorder: _border(border),
      focusedBorder: _border(accent),
    );
  }

  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
  }

  /// 把 `#RRGGBB` 解析成 Color，失败时回退。
  static Color hexColor(String hex, Color fallback) {
    final normalized = hex.trim().replaceFirst('#', '');
    if (normalized.length != 6) {
      return fallback;
    }
    final value = int.tryParse('FF$normalized', radix: 16);
    if (value == null) {
      return fallback;
    }
    return Color(value);
  }

  /// 相对时间描述：「刚刚 / N 分钟前 / N 小时前 / N 天前 / yyyy-MM-dd」。
  ///
  /// 与 `session_history_sheet._formatUpdatedAt` 的口径保持一致，
  /// 让「对话」与「记忆」两处的时间感统一。
  static String relativeTime(DateTime time, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(time);

    if (diff.isNegative || diff.inMinutes < 1) {
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

  /// 是否算「新写入」——用于卡片上的高亮小圆点。
  static bool isFresh(DateTime time, {DateTime? now, Duration window = const Duration(minutes: 5)}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(time);
    return !diff.isNegative && diff <= window;
  }
}
