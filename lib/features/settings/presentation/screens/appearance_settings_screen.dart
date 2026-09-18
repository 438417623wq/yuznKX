import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../chat/presentation/widgets/chat_bubble.dart';
import '../../data/theme_provider.dart';

/// 「外观与主题」独立页面。
///
/// 原先该板块以内嵌 [ExpansionTile] 的形式存在于角色设置抽屉
/// （`character_settings_drawer.dart`），现整体迁移至「设置 → 高级」板块，
/// 作为独立入口页呈现。UI 结构与交互逻辑保持不变，仅做容器替换：
/// `ExpansionTile.children` → [ListView] 的 children。
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  // 与角色设置抽屉保持一致的深色配色。
  static const Color _pageBg = Color(0xFF1a1b26);
  static const Color _dialogBg = Color(0xFF1f2937);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: const Text('外观与主题'),
        backgroundColor: const Color(0xFF16161e),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // --- 实时预览 ---
          _buildPreviewCard(context, themeSettings),

          // --- 背景图片 ---
          _buildSectionTitle('背景'),
          ListTile(
            title:
                const Text('背景图片', style: TextStyle(color: Colors.white)),
            trailing: themeSettings.backgroundImagePath != null
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => ref
                        .read(themeSettingsProvider.notifier)
                        .updateBackgroundImage(null),
                  )
                : const Icon(Icons.add_photo_alternate, color: Colors.white54),
            subtitle: Text(
                themeSettings.backgroundImagePath != null ? '已设置' : '点击选择图片',
                style: const TextStyle(color: Colors.white38)),
            onTap: () async {
              FilePickerResult? result =
                  await FilePicker.platform.pickFiles(type: FileType.image);
              if (result != null && result.files.single.path != null) {
                ref
                    .read(themeSettingsProvider.notifier)
                    .updateBackgroundImage(result.files.single.path!);
              }
            },
          ),
          if (themeSettings.backgroundImagePath != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 8),
                  child: Text('背景模糊',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Slider(
                  value: themeSettings.backgroundBlur,
                  min: 0,
                  max: 10,
                  onChanged: (val) =>
                      ref.read(themeSettingsProvider.notifier).updateBlur(val),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 0),
                  child: Text('背景遮罩浓度',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Slider(
                  value: themeSettings.backgroundOpacity,
                  min: 0.0,
                  max: 0.9,
                  onChanged: (val) => ref
                      .read(themeSettingsProvider.notifier)
                      .updateOpacity(val),
                ),
              ],
            ),

          // --- 气泡颜色 ---
          _buildSectionTitle('气泡颜色 (用户 / AI)'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildColorPicker(
                  context, ref, 'user_color', themeSettings.userBubbleColor),
              const Icon(Icons.swap_horiz, color: Colors.white24),
              _buildColorPicker(
                  context, ref, 'ai_color', themeSettings.aiBubbleColor),
            ],
          ),

          const Divider(color: Colors.white10),

          // --- 高级配色 ---
          _buildSectionTitle('自定义配色'),
          _buildDetailedColorPicker(context, ref, '主要文本',
              themeSettings.mainTextColor, 'main_text_color'),
          _buildDetailedColorPicker(context, ref, '斜体文本',
              themeSettings.italicTextColor, 'italic_text_color'),
          _buildDetailedColorPicker(context, ref, '下划线文本',
              themeSettings.underlineTextColor, 'underline_text_color'),
          _buildDetailedColorPicker(context, ref, '引用文本',
              themeSettings.quoteTextColor, 'quote_text_color'),
          _buildDetailedColorPicker(context, ref, '阴影颜色',
              themeSettings.shadowColor, 'shadow_color'),
          _buildDetailedColorPicker(context, ref, '聊天背景',
              themeSettings.chatBackgroundColor, 'chat_bg_color'),
          _buildDetailedColorPicker(context, ref, 'UI 背景',
              themeSettings.uiBackgroundColor, 'ui_bg_color'),
          _buildDetailedColorPicker(context, ref, 'UI 边框',
              themeSettings.uiBorderColor, 'ui_border_color'),
          _buildDetailedColorPicker(context, ref, '用户消息模糊色调',
              themeSettings.userMessageBlurTint, 'user_blur_tint'),
          _buildDetailedColorPicker(context, ref, 'AI 消息模糊色调',
              themeSettings.aiMessageBlurTint, 'ai_blur_tint'),
          _buildDetailedColorPicker(context, ref, '旁白颜色',
              themeSettings.narrationColor, 'narration_color'),

          const Divider(color: Colors.white10),
          _buildPatternSettings(context, ref, themeSettings),

          // --- 字体大小 ---
          _buildSectionTitle('字体大小'),
          Slider(
            value: themeSettings.fontSizeScale,
            min: 0.8,
            max: 1.5,
            divisions: 7,
            label: '${themeSettings.fontSizeScale}x',
            onChanged: (val) =>
                ref.read(themeSettingsProvider.notifier).updateFontSize(val),
          ),
        ],
      ),
    );
  }

  /// 顶部实时预览卡片。
  ///
  /// 直接复用真实聊天气泡组件 [ChatBubble] 渲染，因此预览即真实渲染路径：
  /// 改任何配色项，这里立刻反映，不必来回切到聊天页确认。
  Widget _buildPreviewCard(BuildContext context, ThemeSettings settings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(Icons.preview_outlined, color: Colors.pinkAccent),
          iconColor: Colors.pinkAccent,
          collapsedIconColor: Colors.white54,
          title: const Text('实时预览',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text('调整下方任一项，此处立即反映',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          children: [
            _buildMiniChat(settings),
            const SizedBox(height: 8),
            const Text(
              '提示：气泡背景取「气泡颜色」；「消息模糊色调」当前不参与渲染。',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// 迷你聊天窗口，背景层与真实聊天页（`chat_screen.dart`）保持同一实现。
  Widget _buildMiniChat(ThemeSettings settings) {
    final hasBackground = settings.backgroundImagePath != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            // 底色
            Positioned.fill(
              child: ColoredBox(color: settings.chatBackgroundColor),
            ),
            // 背景图
            if (hasBackground)
              Positioned.fill(
                child: Image.file(
                  File(settings.backgroundImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            // 模糊 + 遮罩
            if (hasBackground)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: settings.backgroundBlur,
                    sigmaY: settings.backgroundBlur,
                  ),
                  child: ColoredBox(
                    color: Colors.black
                        .withValues(alpha: settings.backgroundOpacity),
                  ),
                ),
              ),
            // 气泡内容（真实组件）
            const Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    ChatBubble(
                      content: '你好，这是用户消息的预览效果。',
                      isUser: true,
                      name: '你',
                      showAvatar: false,
                    ),
                    ChatBubble(
                      content: '这是 AI 回复的预览。*斜体旁白* 与 (括号旁白) 会按当前「识别设置」渲染。',
                      isUser: false,
                      name: '角色',
                      showAvatar: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 板块标题（原 ExpansionTile 内的 `Padding + Text`，样式保持一致）。
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPatternSettings(
      BuildContext context, WidgetRef ref, ThemeSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('识别设置'),
        ListTile(
          title: const Text('旁白识别',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _dialogBg,
                title:
                    const Text('旁白识别', style: TextStyle(color: Colors.white)),
                content: Consumer(builder: (context, ref, _) {
                  final currentSettings = ref.watch(themeSettingsProvider);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCheckboxTile(ref, 'rec_asterisk', '* ... *',
                          currentSettings.recognizeAsteriskNarration),
                      _buildCheckboxTile(ref, 'rec_parentheses', '( ... )',
                          currentSettings.recognizeParenthesesNarration),
                      _buildCheckboxTile(
                          ref,
                          'rec_full_parentheses',
                          '( ... ) (全角括号)',
                          currentSettings
                              .recognizeFullWidthParenthesesNarration),
                    ],
                  );
                }),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('确定')),
                ],
              ),
            );
          },
        ),
        ListTile(
          title: const Text('引用识别',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _dialogBg,
                title:
                    const Text('引用识别', style: TextStyle(color: Colors.white)),
                content: Consumer(builder: (context, ref, _) {
                  final currentSettings = ref.watch(themeSettingsProvider);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCheckboxTile(ref, 'rec_double_quote', '" ... "',
                          currentSettings.recognizeDoubleQuoteSpeech),
                      _buildCheckboxTile(
                          ref,
                          'rec_full_double_quote',
                          '“ ... ” (全角双引号)',
                          currentSettings.recognizeFullWidthDoubleQuoteSpeech),
                      _buildCheckboxTile(ref, 'rec_corner_bracket', '「 ... 」',
                          currentSettings.recognizeCornerBracketSpeech),
                    ],
                  );
                }),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('确定')),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCheckboxTile(
      WidgetRef ref, String key, String label, bool value) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      value: value,
      activeColor: Colors.indigoAccent,
      onChanged: (val) {
        ref.read(themeSettingsProvider.notifier).togglePattern(key);
      },
    );
  }

  Widget _buildDetailedColorPicker(BuildContext context, WidgetRef ref,
      String label, Color currentColor, String colorKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          GestureDetector(
            onTap: () => _showColorPickerDialog(context, ref, colorKey),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                      color: currentColor.withValues(alpha: 0.3),
                      blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(
      BuildContext context, WidgetRef ref, String key, Color currentColor) {
    return GestureDetector(
      onTap: () {
        _showColorPickerDialog(context, ref, key);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: currentColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
                color: currentColor.withValues(alpha: 0.5), blurRadius: 8),
          ],
        ),
      ),
    );
  }

  void _showColorPickerDialog(BuildContext context, WidgetRef ref, String key) {
    final colors = [
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
      Colors.black,
      Colors.white,
      const Color(0xFF1a1b26),
      const Color(0xFF24283b),
      Colors.transparent,
    ];

    String title;
    switch (key) {
      case 'user_color':
        title = '用户气泡颜色';
        break;
      case 'ai_color':
        title = 'AI 气泡颜色';
        break;
      case 'main_text_color':
        title = '主要文本颜色';
        break;
      case 'italic_text_color':
        title = '斜体文本颜色';
        break;
      case 'underline_text_color':
        title = '下划线文本颜色';
        break;
      case 'quote_text_color':
        title = '引用文本颜色';
        break;
      case 'shadow_color':
        title = '阴影颜色';
        break;
      case 'chat_bg_color':
        title = '聊天背景颜色';
        break;
      case 'ui_bg_color':
        title = 'UI 背景颜色';
        break;
      case 'ui_border_color':
        title = 'UI 边框颜色';
        break;
      case 'user_blur_tint':
        title = '用户模糊色调';
        break;
      case 'ai_blur_tint':
        title = 'AI 模糊色调';
        break;
      case 'narration_color':
        title = '旁白颜色';
        break;
      default:
        title = '选择颜色';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors
              .map((c) => GestureDetector(
                    onTap: () {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .updateColor(key, c);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: c == Colors.transparent
                          ? const Icon(Icons.block,
                              color: Colors.white54, size: 20)
                          : null,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
