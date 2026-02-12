import 'package:flutter/material.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  // Dummy data
  final List<Map<String, dynamic>> _lorebooks = [
    {"name": "基本世界观", "entries": 12, "active": true},
    {"name": "魔法系统", "entries": 45, "active": true},
    {"name": "赛博城市", "entries": 30, "active": false},
    {"name": "人物关系", "entries": 8, "active": false},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('世界书 (Lorebook)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: () {},
            tooltip: "导入",
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
            tooltip: "新建",
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lorebooks.length,
        itemBuilder: (context, index) {
          final book = _lorebooks[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: SwitchListTile(
              title: Text(
                book['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("${book['entries']} 条目"),
              value: book['active'],
              onChanged: (val) {
                setState(() {
                  book['active'] = val;
                });
              },
              secondary: const Icon(Icons.book),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.search),
        label: const Text("搜索条目"),
      ),
    );
  }
}
