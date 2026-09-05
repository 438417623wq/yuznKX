import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings/domain/plugin_settings_provider.dart';

class FrontendRenderScreen extends ConsumerWidget {
  const FrontendRenderScreen({super.key});

  static const Color _bg = Color(0xFF1C1B29);
  static const Color _panel = Color(0xFF222130);
  static const Color _panelSoft = Color(0xFF2A2839);
  static const Color _border = Color(0xFF3A3748);
  static const Color _accent = Color(0xFFD5BBFF);
  static const Color _accentSoft = Color(0xFF9A86B9);
  static const Color _textPrimary = Color(0xFFF4F1FA);
  static const Color _textSecondary = Color(0xFFD2CBDC);
  static const Color _textMuted = Color(0xFF9A93A9);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(pluginSettingsProvider);
    final notifier = ref.read(pluginSettingsProvider.notifier);

    final advancedEnabled = settings['frontend_advanced_render'] != false;
    final jsMode = (settings['frontend_javascript_mode'] as String?) ?? 'auto';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          '前端渲染',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: _textPrimary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => notifier.resetFrontendRenderSettings(),
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                backgroundColor: _panelSoft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '恢复默认',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                _RenderSettingTile(
                  title: '高级前端渲染',
                  description: '用于渲染 HTML、CSS 与前端角色卡。',
                  badge: const _BetaBadge(),
                  trailing: Switch(
                    value: advancedEnabled,
                    onChanged: (value) {
                      notifier.setBool('frontend_advanced_render', value);
                      notifier.setBool('frontend_character_card', value);
                    },
                    activeThumbColor: _accent,
                    activeTrackColor: _accentSoft,
                    inactiveThumbColor: const Color(0xFFB2ABBF),
                    inactiveTrackColor: const Color(0xFF5D596B),
                  ),
                ),
                const Divider(height: 1, color: _border),
                _RenderSettingTile(
                  title: 'JavaScript 支持',
                  description: '控制角色卡中的脚本执行方式。',
                  badge: const _BetaBadge(),
                  trailing: InkWell(
                    onTap: () => _showJavascriptModeSheet(context, ref, jsMode),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _labelForMode(jsMode),
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _textMuted,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, color: _accent, size: 18),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '个别角色卡如果显示仍有差异，可以切换脚本模式后重新进入聊天查看效果。',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '快速说明',
              style: TextStyle(
                color: _textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: _QuickHelpCard(
                  title: 'HTML / CSS',
                  subtitle: '适合静态样式卡、状态栏和大多数纯展示型角色卡。',
                  gradient: LinearGradient(
                    colors: [Color(0xFF2A2840), Color(0xFF1E2138)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: _QuickHelpCard(
                  title: 'JavaScript',
                  subtitle: '适合有动态逻辑、切换状态和脚本交互的角色卡。',
                  gradient: LinearGradient(
                    colors: [Color(0xFF34264C), Color(0xFF211F34)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showJavascriptModeSheet(
    BuildContext context,
    WidgetRef ref,
    String currentMode,
  ) async {
    final notifier = ref.read(pluginSettingsProvider.notifier);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: SizedBox(
                    width: 44,
                    child: Divider(
                      thickness: 4,
                      color: _border,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'JavaScript 支持',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _JavascriptModeOption(
                  title: '禁止',
                  description: '只渲染结构与样式，不执行任何脚本。',
                  selected: currentMode == 'disabled',
                  onTap: () => Navigator.pop(context, 'disabled'),
                ),
                const SizedBox(height: 10),
                _JavascriptModeOption(
                  title: '自动',
                  description: '自动判断普通前端卡与脚本型角色卡的执行方式。',
                  selected: currentMode == 'auto',
                  onTap: () => Navigator.pop(context, 'auto'),
                ),
                const SizedBox(height: 10),
                _JavascriptModeOption(
                  title: 'Script 模式',
                  description: '优先处理消息正文中的 script 标签与完整文档。',
                  selected: currentMode == 'script',
                  onTap: () => Navigator.pop(context, 'script'),
                ),
                const SizedBox(height: 10),
                _JavascriptModeOption(
                  title: 'Code Block 模式',
                  description: '仅对代码块中的前端卡执行脚本。',
                  selected: currentMode == 'code_block',
                  onTap: () => Navigator.pop(context, 'code_block'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice != null) {
      await notifier.setString('frontend_javascript_mode', choice);
    }
  }

  String _labelForMode(String mode) {
    switch (mode) {
      case 'disabled':
        return '禁止';
      case 'script':
        return 'Script';
      case 'code_block':
        return 'Code Block';
      case 'auto':
      default:
        return '自动';
    }
  }
}

class _RenderSettingTile extends StatelessWidget {
  final String title;
  final String description;
  final Widget trailing;
  final Widget? badge;

  const _RenderSettingTile({
    required this.title,
    required this.description,
    required this.trailing,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: FrontendRenderScreen._textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (badge != null) badge!,
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: FrontendRenderScreen._textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _JavascriptModeOption extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _JavascriptModeOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2F2840)
              : FrontendRenderScreen._panelSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? FrontendRenderScreen._accentSoft : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected
                    ? FrontendRenderScreen._accent
                    : FrontendRenderScreen._textPrimary,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: FrontendRenderScreen._textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickHelpCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Gradient gradient;

  const _QuickHelpCard({
    required this.title,
    required this.subtitle,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.92,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: FrontendRenderScreen._border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: FrontendRenderScreen._textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: FrontendRenderScreen._textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BetaBadge extends StatelessWidget {
  const _BetaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3150),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5E4C83)),
      ),
      child: const Text(
        'BETA',
        style: TextStyle(
          color: FrontendRenderScreen._accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
