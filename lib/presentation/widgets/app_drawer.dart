import 'package:flutter/material.dart';

import '../../features/settings/presentation/screens/storage_management_screen.dart';
import '../../features/character/presentation/screens/character_list_screen.dart';
import '../../features/world_info/presentation/screens/world_info_list_screen.dart';
import '../../features/regex/presentation/screens/regex_list_screen.dart';
import '../../features/variables/presentation/screens/variable_management_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFF1a1b26),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFF16161e),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SillyTavern',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '移动版',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(context, Icons.person, "角色管理", () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterListScreen(showGroupsOnly: false)));
            }),
            _buildDrawerItem(context, Icons.image, "背景设置", () {}),
            _buildDrawerItem(context, Icons.groups, "群组聊天", () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterListScreen(showGroupsOnly: true)));
            }),
            const Divider(color: Colors.grey),
            _buildDrawerItem(context, Icons.account_circle, "用户档案", () {}),
            _buildDrawerItem(context, Icons.api, "API 连接", () {
               // Open API settings
            }),
            _buildDrawerItem(context, Icons.settings_applications, "高级格式", () {}),
            const Divider(color: Colors.grey),
            // 资源池：角色卡内的同名资源与这里相互独立
            _buildDrawerItem(context, Icons.book, "全局世界书 (Global World Info)", () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const WorldInfoListScreen()));
            }),
            _buildDrawerItem(context, Icons.code, "全局正则 (Global Regex)", () {
              Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegexListScreen()));
            }),
            _buildDrawerItem(
                context, Icons.data_object, "变量管理 (Variables)", () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VariableManagementScreen()));
            }),
            const Divider(color: Colors.grey),
            _buildDrawerItem(context, Icons.extension, "插件扩展", () {}),
            _buildDrawerItem(context, Icons.storage, "存储与数据", () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageManagementScreen()));
            }),
            _buildDrawerItem(context, Icons.help, "帮助与文档", () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigoAccent),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white70),
      ),
      onTap: () {
        Navigator.pop(context); // Close drawer
        onTap();
        // Here we could navigate to specific pages or show dialogs
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已选择: $title')),
        );
      },
    );
  }
}
