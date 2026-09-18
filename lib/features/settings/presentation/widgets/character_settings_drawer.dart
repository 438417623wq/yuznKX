import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../../../../features/chat/data/chat_provider.dart';
import '../../../../features/chat/data/session_provider.dart';
import '../../../../features/api_connection/data/api_connection_provider.dart';
import '../../../../features/api_connection/presentation/screens/api_connection_list_screen.dart';

import '../../../../features/presets/data/preset_provider.dart';
import '../../../../features/presets/presentation/screens/preset_list_screen.dart';
import '../../../../features/presets/presentation/screens/preset_edit_screen.dart';
import '../../../../features/world_info/data/world_info_provider.dart';
import '../../../../features/world_info/presentation/screens/world_info_list_screen.dart';
import '../../../../features/regex/data/regex_provider.dart';
import '../../../../features/regex/presentation/screens/regex_list_screen.dart';
import '../../../../features/character/data/character_provider.dart';
import '../../../../features/character/presentation/screens/character_edit_screen.dart';
import '../../../../features/character/presentation/screens/character_list_screen.dart';
import '../../../../features/character/domain/models/character.dart';
import '../../../user/data/persona_provider.dart';
import '../../../../features/user/presentation/screens/persona_list_screen.dart';
import '../../domain/plugin_settings_provider.dart';
import '../../../../features/chat/presentation/screens/tts_settings_screen.dart';

import '../../../../features/character/data/character_exporter.dart';
import '../../../../features/memory/presentation/screens/memory_management_screen.dart';

class CharacterSettingsDrawer extends ConsumerWidget {
  const CharacterSettingsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeConnection = ref.watch(activeApiConnectionProvider);
    final activePreset = ref.watch(activePresetProvider);
    final activeWorldInfoIds = ref.watch(activeWorldInfoIdsProvider);
    final activeRegexIds = ref.watch(activeRegexScriptIdsProvider);
    final activeCharacter = ref.watch(activeCharacterProvider);
    final currentPersona = ref.watch(personaProvider);
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Container(
        color: const Color(0xFF1a1b26),
        child: Column(
          children: [
            _buildHeader(context, activeCharacter),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- 1. Chat Settings ---
                  ExpansionTile(
                    title: const Text('聊天设定',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.chat_bubble_outline,
                        color: Colors.indigoAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.indigoAccent,
                    children: [
                      _buildSettingsTile(Icons.description, '情景设定 (Scenario)',
                          '当前场景: ${activeCharacter?.scenario.isEmpty ?? true ? "无" : "自定义"}',
                          onTap: () {
                        if (activeCharacter != null) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CharacterEditScreen(
                                      character: activeCharacter)));
                        }
                      }),
                      _buildSettingsTile(Icons.person_outline, '用户身份 (Persona)',
                          '${currentPersona.name}', onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PersonaListScreen()));
                      }),
                      // 回复长度由预设的 `max_tokens` 决定。
                      // 原先这里放了一个 onChanged 为空的 Slider，既拖不动、
                      // 没预设时又恒显示 200，很容易让人误以为回复被限死在 200。
                      // 改为只读展示 + 直达预设参数页。
                      _buildSettingsTile(
                        Icons.straighten,
                        '回复长度限制 (Max Tokens)',
                        activePreset == null
                            ? '未选择预设，点击前往设置'
                            : '${activePreset.maxTokens} tokens · ${activePreset.name}',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PresetEditScreen(preset: activePreset),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const Divider(color: Colors.white10),

                  // --- 2. Model & API ---
                  // 说明：「外观与主题」已整体迁移至「设置 → 高级 → 外观与主题」。
                  ExpansionTile(
                    title: const Text('模型与API',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.api, color: Colors.tealAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.tealAccent,
                    children: [
                      _buildSettingsTile(
                        Icons.link,
                        'API 连接',
                        activeConnection != null
                            ? '${activeConnection.name} (${activeConnection.model})'
                            : '未连接',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const ApiConnectionListScreen()),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        Icons.settings_input_component,
                        '生成预设 (Presets)',
                        activePreset?.name ?? 'Default',
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PresetListScreen()));
                        },
                      ),

                      // Preferred Model Override
                      if (activeCharacter != null)
                        ListTile(
                          title: const Text('首选模型 (Override)',
                              style: TextStyle(color: Colors.white)),
                          subtitle: Text(
                              activeCharacter.preferredModelName ?? '使用 API 默认',
                              style: const TextStyle(color: Colors.white54)),
                          trailing: const Icon(Icons.edit,
                              color: Colors.white54, size: 20),
                          onTap: () {
                            _showModelSelectionDialog(
                                context, ref, activeCharacter);
                          },
                        ),

                      _buildSettingsTile(
                        Icons.book,
                        '全局世界书 (Global World Info)',
                        activeWorldInfoIds.isEmpty
                            ? '未启用（角色卡世界书请在角色卡「绑定」页设置）'
                            : '已启用 ${activeWorldInfoIds.length} 个',
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const WorldInfoListScreen()));
                        },
                      ),
                      _buildSettingsTile(
                        Icons.code,
                        '全局正则 (Global Regex)',
                        activeRegexIds.isEmpty
                            ? '未启用（角色卡正则请在角色卡「绑定」页设置）'
                            : '已启用 ${activeRegexIds.length} 个',
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegexListScreen()));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _buildSectionTitle('语音与记忆'),
                  _buildSettingsTile(
                      Icons.record_voice_over, 'TTS 语音设置', '系统默认', onTap: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => TtsSettingsScreen()));
                  }),
                  _buildSettingsTile(
                    Icons.memory,
                    '记忆管理 (Memory)',
                    '管理结构化记忆表格',
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MemoryManagementScreen()));
                    },
                  ),

                  const Divider(color: Colors.white10),

                  // --- 4. Plugins & Debug ---
                  ExpansionTile(
                    title: const Text('插件与调试',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    leading:
                        const Icon(Icons.extension, color: Colors.orangeAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.orangeAccent,
                    children: [
                      SwitchListTile(
                        title: const Text('显示模型调试信息',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text('显示 Prompt、参数与生成统计',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                        value: ref.watch(pluginSettingsProvider)[
                                'show_model_debug_info'] ??
                            false,
                        onChanged: (val) {
                          ref
                              .read(pluginSettingsProvider.notifier)
                              .toggle('show_model_debug_info');
                        },
                        activeColor: Colors.orangeAccent,
                      ),
                      if (ref.watch(pluginSettingsProvider)[
                              'show_model_debug_info'] ??
                          false)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('调试信息样式',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildStyleChip(ref, 0, '终端 (Terminal)'),
                                  _buildStyleChip(ref, 1, '玻璃 (Glass)'),
                                  _buildStyleChip(ref, 2, '卡片 (Card)'),
                                  _buildStyleChip(ref, 3, '赛博 (Cyber)'),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _buildBottomBar(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleChip(WidgetRef ref, int index, String label) {
    final settings = ref.watch(pluginSettingsProvider);
    final currentStyle = settings['model_debug_style'] is int
        ? settings['model_debug_style']
        : 0;
    final isSelected = currentStyle == index;
    return GestureDetector(
      onTap: () {
        ref.read(pluginSettingsProvider.notifier).setStyle(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orangeAccent : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? Colors.orangeAccent : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Character? character) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.2),
        image: const DecorationImage(
          image: NetworkImage('https://via.placeholder.com/400x200'),
          fit: BoxFit.cover,
          opacity: 0.3,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: (character?.avatarPath != null &&
                    character!.avatarPath.isNotEmpty)
                ? FileImage(File(character.avatarPath)) as ImageProvider
                : const NetworkImage('https://via.placeholder.com/150'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character?.name ?? '未选择角色',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${character?.tags.length ?? 0} Tags | v${character?.version ?? "1.0"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CharacterListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        CharacterEditScreen(character: character)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.indigoAccent,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Future<void> _showModelSelectionDialog(
      BuildContext context, WidgetRef ref, Character character) async {
    final controller =
        TextEditingController(text: character.preferredModelName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('设置角色首选模型', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('如果 API 支持，将优先使用此模型名称。留空则使用全局设置。',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '模型名称 (e.g. gpt-4, claude-3-opus)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.indigoAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newValue = controller.text.trim().isEmpty
                  ? null
                  : controller.text.trim();
              final updatedChar =
                  character.copyWith(preferredModelName: newValue);
              ref.read(characterListProvider.notifier).save(updatedChar);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle,
      {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24283b),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, WidgetRef ref) {
    final activeCharacter = ref.watch(activeCharacterProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF16161e),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionBtn(Icons.refresh, '重启对话', () async {
            final character = ref.read(activeCharacterProvider);
            final sessionId = ref.read(activeSessionIdProvider);

            if (sessionId == null) return;

            // 1. Confirm Restart
            final shouldRestart = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1f2937),
                title:
                    const Text('重启对话', style: TextStyle(color: Colors.white)),
                content: const Text('确定要清除当前对话历史吗？',
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child:
                        const Text('确定', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );

            if (shouldRestart != true) return;

            String? selectedGreeting;

            // 2. Check for Alternate Greetings
            if (character != null &&
                character.alternateGreetings.isNotEmpty &&
                context.mounted) {
              selectedGreeting = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  backgroundColor: const Color(0xFF1f2937),
                  title: const Text('选择开场白',
                      style: TextStyle(color: Colors.white)),
                  children: [
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(ctx, character.firstMessage),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('默认开场白',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    ...character.alternateGreetings.map((g) =>
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, g),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              g.length > 50 ? '${g.substring(0, 50)}...' : g,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        )),
                  ],
                ),
              );
              // If user cancels selection (clicks outside), we might want to default to original or cancel restart?
              // Let's assume default behavior is to use default greeting if they cancel selection, OR cancel restart.
              // But usually clicking outside means "cancel action".
              // However, the restart was already confirmed.
              // Let's assume if null, use default.
            }

            // 3. Execute Clear
            ref
                .read(chatSessionProvider(sessionId).notifier)
                .clearHistory(customGreeting: selectedGreeting);

            if (context.mounted) Navigator.pop(context); // Close drawer
          }),
          // Statistics button removed as per request
          _buildActionBtn(Icons.download, '导出', () {
            if (activeCharacter != null) {
              _showExportDialog(context, activeCharacter);
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('未选择角色')));
            }
          }),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context, Character character) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1f2937),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('导出角色',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blueAccent),
              title: const Text('导出为 PNG (SillyTavern Card)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('包含角色元数据的图片',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('正在导出 PNG...')));
                  await CharacterExporter.exportAsPng(character);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('导出失败: $e')));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.orangeAccent),
              title:
                  const Text('导出为 JSON', style: TextStyle(color: Colors.white)),
              subtitle: const Text('纯文本数据格式',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await CharacterExporter.exportAsJson(character);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('导出失败: $e')));
                  }
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
