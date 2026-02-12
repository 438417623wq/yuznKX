import 'package:flutter/material.dart';
import '../../../features/api_connection/presentation/screens/api_connection_list_screen.dart';

import '../../../features/presets/presentation/screens/preset_list_screen.dart';
import '../../../features/world_info/presentation/screens/world_info_list_screen.dart';
import '../../../features/regex/presentation/screens/regex_list_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSectionHeader("通用"),
          _buildSettingsTile(context, Icons.person, "用户资料", "设置用户名和头像", () {}),
          _buildSettingsTile(context, Icons.api, "API 连接", "配置文本生成后端 (OpenAI, Claude...)", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ApiConnectionListScreen()),
            );
          }),
          _buildSettingsTile(context, Icons.tune, "生成预设 (Presets)", "管理生成参数和 Prompt 模板", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PresetListScreen()),
            );
          }),
          _buildSettingsTile(context, Icons.book, "全局世界书 (World Info)", "管理 Lore 和设定集", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const WorldInfoListScreen()),
            );
          }),
          _buildSettingsTile(context, Icons.code, "全局正则 (Regex)", "管理输入/输出处理脚本", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RegexListScreen()),
            );
          }),
          
          _buildSectionHeader("界面"),
          _buildSettingsTile(context, Icons.palette, "外观主题", "深色/浅色模式, 配色方案", () {}),
          _buildSettingsTile(context, Icons.wallpaper, "背景设置", "自定义聊天背景", () {}),
          _buildSettingsTile(context, Icons.chat_bubble, "气泡样式", "调整对话气泡大小和样式", () {}),

          _buildSectionHeader("高级"),
          _buildSettingsTile(context, Icons.storage, "数据管理", "备份、恢复与清理", () {}),
          _buildSettingsTile(context, Icons.extension, "插件扩展", "管理已安装的插件", () {}),
          _buildSettingsTile(context, Icons.translate, "翻译设置", "配置自动翻译引擎", () {}),

          _buildSectionHeader("关于"),
          _buildSettingsTile(context, Icons.info, "关于应用", "版本信息与更新日志", () {}),
          _buildSettingsTile(context, Icons.help, "帮助文档", "查看使用指南", () {}),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.indigoAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
      onTap: onTap,
    );
  }
}
