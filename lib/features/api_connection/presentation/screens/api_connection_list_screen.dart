import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/api_connection_provider.dart';
import '../../domain/models/api_connection.dart';
import 'api_connection_edit_screen.dart';

class ApiConnectionListScreen extends ConsumerWidget {
  const ApiConnectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(apiConnectionsProvider);
    final activeId = ref.watch(activeApiIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 连接管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ApiConnectionEditScreen()),
              );
            },
          ),
        ],
      ),
      body: connections.isEmpty
          ? const Center(
              child: Text('暂无 API 连接，请点击右上角添加'),
            )
          : ListView.builder(
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final conn = connections[index];
                final isActive = conn.id == activeId;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isActive ? Colors.indigo.withOpacity(0.2) : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isActive
                        ? const BorderSide(color: Colors.indigoAccent, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    title: Text(conn.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${conn.platform} • ${conn.model}'),
                    leading: CircleAvatar(
                      backgroundColor: isActive ? Colors.indigoAccent : Colors.grey,
                      child: Icon(
                        Icons.api,
                        color: Colors.white,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isActive)
                          TextButton(
                            onPressed: () {
                              ref.read(activeApiIdProvider.notifier).setActiveId(conn.id);
                            },
                            child: const Text('启用'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ApiConnectionEditScreen(connection: conn),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                       // Optional: Quick activate or edit
                    },
                  ),
                );
              },
            ),
    );
  }
}
