import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings/domain/plugin_settings_provider.dart';
import 'frontend_render_screen.dart';

class PluginsScreen extends ConsumerWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(pluginSettingsProvider);
    final notifier = ref.read(pluginSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件扩展'),
      ),
      body: ListView(
        children: [
          _buildNavigationTile(
            context,
            title: '前端渲染',
            subtitle: '管理前端角色卡、HTML/CSS 渲染以及 JavaScript 执行模式。',
            value: plugins['frontend_advanced_render'] != false ? '已启用' : '已关闭',
            icon: Icons.auto_awesome_motion,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FrontendRenderScreen(),
                ),
              );
            },
          ),
          const Divider(),
          _buildPluginTile(
            context,
            '前端卡调试面板',
            '在聊天中显示角色卡的原始 HTML、渲染高度与错误日志。',
            plugins['frontend_card_debug_panel'] ?? false,
            (val) => notifier.toggle('frontend_card_debug_panel'),
            Icons.bug_report,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'AI 推理与调试',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            value: plugins['show_model_debug_info'] == true,
            onChanged: (val) => notifier.toggle('show_model_debug_info'),
            secondary: Icon(
              Icons.psychology,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('显示 AI 调试信息'),
            subtitle: const Text('展示模型的提示词、参数和调试信息。'),
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          if (plugins['show_model_debug_info'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('调试展示样式', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('终端'),
                        icon: Icon(Icons.terminal),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('玻璃'),
                        icon: Icon(Icons.blur_on),
                      ),
                      ButtonSegment(
                        value: 2,
                        label: Text('卡片'),
                        icon: Icon(Icons.crop_portrait),
                      ),
                      ButtonSegment(
                        value: 3,
                        label: Text('赛博'),
                        icon: Icon(Icons.bolt),
                      ),
                    ],
                    selected: {(plugins['model_debug_style'] as int?) ?? 0},
                    onSelectionChanged: (Set<int> newSelection) {
                      notifier.setStyle(newSelection.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPluginTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
    IconData icon,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      activeThumbColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildNavigationTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
