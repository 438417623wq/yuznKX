import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../../features/chat/data/chat_provider.dart';
import '../../../../features/chat/data/session_provider.dart';
import '../../../../features/api_connection/data/api_connection_provider.dart';
import '../../../../features/api_connection/presentation/screens/api_connection_list_screen.dart';

import '../../../../features/presets/data/preset_provider.dart';
import '../../../../features/presets/presentation/screens/preset_list_screen.dart';
import '../../../../features/world_info/data/world_info_provider.dart';
import '../../../../features/world_info/presentation/screens/world_info_list_screen.dart';
import '../../../../features/regex/data/regex_provider.dart';
import '../../../../features/regex/presentation/screens/regex_list_screen.dart';
import '../../../../features/character/data/character_provider.dart';
import '../../../../features/character/presentation/screens/character_edit_screen.dart';
import '../../../../features/character/presentation/screens/character_list_screen.dart';
import '../../../../features/character/domain/models/character.dart';
import '../../data/theme_provider.dart';
import '../../../user/data/persona_provider.dart';
import '../../../user/presentation/screens/persona_edit_screen.dart';

class CharacterSettingsDrawer extends ConsumerWidget {
  const CharacterSettingsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeConnection = ref.watch(activeApiConnectionProvider);
    final activePreset = ref.watch(activePresetProvider);
    final activeWorldInfoIds = ref.watch(activeWorldInfoIdsProvider);
    final activeRegexIds = ref.watch(activeRegexScriptIdsProvider);
    final activeCharacter = ref.watch(activeCharacterProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
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
                    title: const Text('聊天设定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.chat_bubble_outline, color: Colors.indigoAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.indigoAccent,
                    children: [
                      _buildSettingsTile(Icons.description, '情景设定 (Scenario)', '当前场景: ${activeCharacter?.scenario.isEmpty ?? true ? "无" : "自定义"}', onTap: () {
                         if (activeCharacter != null) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterEditScreen(character: activeCharacter)));
                         }
                      }),
                      _buildSettingsTile(Icons.person_outline, '用户身份 (Persona)', '${currentPersona.name}', onTap: () {
                         Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonaEditScreen()));
                      }),
                      // Advanced generation settings shortcuts
                      ListTile(
                        title: const Text('回复长度限制', style: TextStyle(color: Colors.white70)),
                        subtitle: Slider(
                          value: (activePreset?.maxTokens ?? 200).toDouble(),
                          min: 50,
                          max: 4096,
                          divisions: 40,
                          label: '${activePreset?.maxTokens ?? 200}',
                          onChanged: (val) {
                             // This should ideally update a temporary state or the preset directly if we want
                             // For now, just visual as we don't have direct preset editing here
                          },
                        ),
                      ),
                    ],
                  ),

                  const Divider(color: Colors.white10),

                  // --- 2. Appearance & Theme ---
                  ExpansionTile(
                    title: const Text('外观与主题', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.color_lens_outlined, color: Colors.pinkAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.pinkAccent,
                    initiallyExpanded: true,
                    children: [
                       // Background Image
                       ListTile(
                         title: const Text('背景图片', style: TextStyle(color: Colors.white)),
                         trailing: themeSettings.backgroundImagePath != null 
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => ref.read(themeSettingsProvider.notifier).updateBackgroundImage(null),
                              )
                            : const Icon(Icons.add_photo_alternate, color: Colors.white54),
                         subtitle: Text(themeSettings.backgroundImagePath != null ? '已设置' : '点击选择图片', style: const TextStyle(color: Colors.white38)),
                         onTap: () async {
                           FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                           if (result != null && result.files.single.path != null) {
                             ref.read(themeSettingsProvider.notifier).updateBackgroundImage(result.files.single.path!);
                           }
                         },
                       ),
                       // Blur Slider
                       if (themeSettings.backgroundImagePath != null)
                         Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             const Padding(
                               padding: EdgeInsets.only(left: 16, top: 8),
                               child: Text('背景模糊', style: TextStyle(color: Colors.white70, fontSize: 12)),
                             ),
                             Slider(
                               value: themeSettings.backgroundBlur,
                               min: 0,
                               max: 10,
                               onChanged: (val) => ref.read(themeSettingsProvider.notifier).updateBlur(val),
                             ),
                             const Padding(
                               padding: EdgeInsets.only(left: 16, top: 0),
                               child: Text('背景遮罩浓度', style: TextStyle(color: Colors.white70, fontSize: 12)),
                             ),
                             Slider(
                               value: themeSettings.backgroundOpacity,
                               min: 0.0,
                               max: 0.9,
                               onChanged: (val) => ref.read(themeSettingsProvider.notifier).updateOpacity(val),
                             ),
                           ],
                         ),

                       // Bubble Colors
                       const Padding(
                         padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                         child: Text('气泡颜色 (用户 / AI)', style: TextStyle(color: Colors.white70)),
                       ),
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                         children: [
                           _buildColorPicker(context, ref, true, themeSettings.userBubbleColor),
                           const Icon(Icons.swap_horiz, color: Colors.white24),
                           _buildColorPicker(context, ref, false, themeSettings.aiBubbleColor),
                         ],
                       ),

                       // Font Scale
                       const Padding(
                         padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                         child: Text('字体大小', style: TextStyle(color: Colors.white70)),
                       ),
                       Slider(
                         value: themeSettings.fontSizeScale,
                         min: 0.8,
                         max: 1.5,
                         divisions: 7,
                         label: '${themeSettings.fontSizeScale}x',
                         onChanged: (val) => ref.read(themeSettingsProvider.notifier).updateFontSize(val),
                       ),
                    ],
                  ),

                  const Divider(color: Colors.white10),

                  // --- 3. Model & API ---
                  ExpansionTile(
                    title: const Text('模型与API', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    leading: const Icon(Icons.api, color: Colors.tealAccent),
                    collapsedIconColor: Colors.white54,
                    iconColor: Colors.tealAccent,
                    children: [
                      _buildSettingsTile(
                        Icons.link, 
                        'API 连接', 
                        activeConnection != null ? '${activeConnection.name} (${activeConnection.model})' : '未连接',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ApiConnectionListScreen()),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        Icons.settings_input_component, 
                        '生成预设 (Presets)', 
                        activePreset?.name ?? 'Default',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const PresetListScreen()));
                        },
                      ),
                      
                      // Preferred Model Override
                      if (activeCharacter != null)
                        ListTile(
                          title: const Text('首选模型 (Override)', style: TextStyle(color: Colors.white)),
                          subtitle: Text(
                            activeCharacter.preferredModelName ?? '使用 API 默认', 
                            style: const TextStyle(color: Colors.white54)
                          ),
                          trailing: const Icon(Icons.edit, color: Colors.white54, size: 20),
                          onTap: () {
                            _showModelSelectionDialog(context, ref, activeCharacter);
                          },
                        ),

                      _buildSettingsTile(
                        Icons.book, 
                        '世界书 (World Info)', 
                        activeWorldInfoIds.isEmpty ? '未启用' : '已启用 ${activeWorldInfoIds.length} 个',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldInfoListScreen()));
                        },
                      ),
                      _buildSettingsTile(
                        Icons.code, 
                        '正则脚本 (Regex)', 
                        activeRegexIds.isEmpty ? '未启用' : '已启用 ${activeRegexIds.length} 个',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const RegexListScreen()));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _buildSectionTitle('语音与记忆'),
                  _buildSettingsTile(Icons.record_voice_over, 'TTS 语音设置', '系统默认'),
                  _buildSettingsTile(Icons.memory, '记忆管理', '已存储 156 条记忆'),
                ],
              ),
            ),
            _buildBottomBar(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(BuildContext context, WidgetRef ref, bool isUser, Color currentColor) {
    return GestureDetector(
      onTap: () {
        _showColorPickerDialog(context, ref, isUser);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: currentColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: currentColor.withOpacity(0.5), blurRadius: 8),
          ],
        ),
      ),
    );
  }

  void _showColorPickerDialog(BuildContext context, WidgetRef ref, bool isUser) {
    // Simple predefined colors for now
    final colors = [
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.brown, Colors.grey, Colors.blueGrey, const Color(0xFF1a1b26),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isUser ? '选择用户气泡颜色' : '选择 AI 气泡颜色'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((c) => GestureDetector(
            onTap: () {
              if (isUser) {
                ref.read(themeSettingsProvider.notifier).updateUserColor(c);
              } else {
                ref.read(themeSettingsProvider.notifier).updateAiColor(c);
              }
              Navigator.pop(ctx);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
              ),
            ),
          )).toList(),
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
            backgroundImage: (character?.avatarPath != null && character!.avatarPath.isNotEmpty)
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
                MaterialPageRoute(builder: (context) => const CharacterListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CharacterEditScreen(character: character)),
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

  Future<void> _showModelSelectionDialog(BuildContext context, WidgetRef ref, Character character) async {
    final controller = TextEditingController(text: character.preferredModelName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('设置角色首选模型', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('如果 API 支持，将优先使用此模型名称。留空则使用全局设置。', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '模型名称 (e.g. gpt-4, claude-3-opus)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
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
              final newValue = controller.text.trim().isEmpty ? null : controller.text.trim();
              final updatedChar = character.copyWith(preferredModelName: newValue);
              ref.read(characterListProvider.notifier).save(updatedChar);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24283b),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF16161e),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionBtn(
            Icons.refresh, 
            '重启对话',
            () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('重启对话'),
                  content: const Text('确定要清除当前对话历史吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    TextButton(
                      onPressed: () {
                         final sessionId = ref.read(activeSessionIdProvider);
                         if (sessionId != null) {
                           ref.read(chatSessionProvider(sessionId).notifier).clearHistory();
                         }
                         Navigator.pop(ctx);
                         Navigator.pop(context); // Close drawer
                      },
                      child: const Text('确定', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            }
          ),
          _buildActionBtn(Icons.bar_chart, '统计', () {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('统计功能开发中')));
          }),
          _buildActionBtn(Icons.download, '导出', () {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导出功能开发中')));
          }),
        ],
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
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
