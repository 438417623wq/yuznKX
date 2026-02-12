import 'package:flutter/material.dart';

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
            _buildDrawerItem(context, Icons.person, "角色管理", () {}),
            _buildDrawerItem(context, Icons.image, "背景设置", () {}),
            _buildDrawerItem(context, Icons.groups, "群组聊天", () {}),
            const Divider(color: Colors.grey),
            _buildDrawerItem(context, Icons.account_circle, "用户档案", () {}),
            _buildDrawerItem(context, Icons.api, "API 连接", () {
               // Open API settings
            }),
            _buildDrawerItem(context, Icons.settings_applications, "高级格式", () {}),
            _buildDrawerItem(context, Icons.book, "世界书 (Lorebook)", () {}),
            const Divider(color: Colors.grey),
            _buildDrawerItem(context, Icons.extension, "插件扩展", () {}),
            _buildDrawerItem(context, Icons.bar_chart, "统计数据", () {}),
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
