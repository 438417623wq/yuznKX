import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/session_provider.dart';
import '../../data/variable_provider.dart';

class VariableManagementScreen extends ConsumerWidget {
  const VariableManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessionId = ref.watch(activeSessionIdProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF1a1b26),
        appBar: AppBar(
          title: const Text('变量管理'),
          backgroundColor: const Color(0xFF1f2937),
          bottom: const TabBar(
            tabs: [
              Tab(text: '全局变量'),
              Tab(text: '会话变量'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VariableScopeView(
              scopeLabel: 'global',
              variables: ref.watch(globalVariablesProvider),
              onAdd: (key, value) {
                ref.read(globalVariablesProvider.notifier).setValue(key, value);
              },
              onEdit: (key, value) {
                ref.read(globalVariablesProvider.notifier).setValue(key, value);
              },
              onDelete: (key) {
                ref.read(globalVariablesProvider.notifier).deleteValue(key);
              },
              onClear: () {
                ref.read(globalVariablesProvider.notifier).clearAll();
              },
            ),
            _SessionVariableTab(activeSessionId: activeSessionId),
          ],
        ),
      ),
    );
  }
}

class _SessionVariableTab extends ConsumerWidget {
  final String? activeSessionId;

  const _SessionVariableTab({required this.activeSessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activeSessionId == null || activeSessionId!.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '当前没有激活会话。\n先进入一个聊天会话再管理会话变量。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    final sessionId = activeSessionId!;
    final variables = ref.watch(chatVariablesProvider(sessionId));

    return _VariableScopeView(
      scopeLabel: 'chat',
      variables: variables,
      onAdd: (key, value) {
        ref
            .read(chatVariablesProvider(sessionId).notifier)
            .setValue(key, value);
      },
      onEdit: (key, value) {
        ref
            .read(chatVariablesProvider(sessionId).notifier)
            .setValue(key, value);
      },
      onDelete: (key) {
        ref.read(chatVariablesProvider(sessionId).notifier).deleteValue(key);
      },
      onClear: () {
        ref.read(chatVariablesProvider(sessionId).notifier).clearAll();
      },
    );
  }
}

class _VariableScopeView extends StatelessWidget {
  final String scopeLabel;
  final Map<String, dynamic> variables;
  final void Function(String key, dynamic value) onAdd;
  final void Function(String key, dynamic value) onEdit;
  final void Function(String key) onDelete;
  final VoidCallback onClear;

  const _VariableScopeView({
    required this.scopeLabel,
    required this.variables,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (variables.isEmpty)
          const Center(
            child: Text('暂无变量', style: TextStyle(color: Colors.white54)),
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_sweep,
                      color: Colors.orangeAccent),
                  label: const Text(
                    '清空当前作用域',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              ),
              ...variables.entries.map((entry) {
                final key = entry.key;
                final value = entry.value;
                return Card(
                  color: const Color(0xFF24283b),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title:
                        Text(key, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${value ?? ''}  (${_typeLabel(value)})',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.lightBlueAccent),
                          onPressed: () => _showEditDialog(context, key, value),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => onDelete(key),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'add_var_$scopeLabel',
            backgroundColor: Colors.orangeAccent,
            onPressed: () => _showAddDialog(context),
            child: const Icon(Icons.add, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('确认清空', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定清空 $scopeLabel 作用域的全部变量吗？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onClear();
    }
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('新增变量', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Key',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: valueController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Value',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '数值会自动识别为 number；true/false 会识别为 bool。',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final key = keyController.text.trim();
              if (key.isEmpty) {
                return;
              }
              onAdd(key, _parseValue(valueController.text));
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    String key,
    dynamic oldValue,
  ) async {
    final valueController =
        TextEditingController(text: oldValue?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('编辑变量', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Key: $key',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valueController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Value',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              onEdit(key, _parseValue(valueController.text));
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(dynamic value) {
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is num) return 'number';
    if (value is List) return 'list';
    if (value is Map) return 'map';
    return 'string';
  }

  static dynamic _parseValue(String raw) {
    final text = raw.trim();
    if (text.toLowerCase() == 'true') {
      return true;
    }
    if (text.toLowerCase() == 'false') {
      return false;
    }
    final intValue = int.tryParse(text);
    if (intValue != null) {
      return intValue;
    }
    final doubleValue = double.tryParse(text);
    if (doubleValue != null) {
      return doubleValue;
    }
    return raw;
  }
}
