import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart';
import '../../../chat/data/session_provider.dart';
import '../../../settings/domain/plugin_settings_provider.dart';
import '../../data/variable_provider.dart';
import '../../data/variable_runtime.dart';
import '../../domain/models/variable_definition.dart';

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
          actions: [
            IconButton(
              tooltip: '变量更新模式',
              icon: const Icon(Icons.tune),
              onPressed: () => _showModeDialog(context, ref),
            ),
          ],
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

  /// 变量更新模式选择。
  ///
  /// 三档让用户自己权衡「面板会不会动」和「每轮多花多少 token」。
  Future<void> _showModeDialog(BuildContext context, WidgetRef ref) async {
    final current = VariableUpdateMode.normalize(
      ref.read(pluginSettingsProvider)['variable_update_mode']?.toString(),
    );
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('变量更新模式', style: TextStyle(color: Colors.white)),
        children: [
          for (final mode in VariableUpdateMode.values)
            ListTile(
              title: Text(
                VariableUpdateMode.labelOf(mode),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _modeHint(mode),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: mode == current
                  ? const Icon(Icons.check, color: Colors.lightGreenAccent)
                  : null,
              onTap: () => Navigator.pop(ctx, mode),
            ),
        ],
      ),
    );
    if (picked == null) {
      return;
    }
    await ref
        .read(pluginSettingsProvider.notifier)
        .setString('variable_update_mode', picked);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('变量更新模式：${VariableUpdateMode.labelOf(picked)}')),
    );
  }

  static String _modeHint(String mode) {
    switch (VariableUpdateMode.normalize(mode)) {
      case VariableUpdateMode.off:
        return '不注入指令、不解析、不写入。等同加这个功能之前的行为。';
      case VariableUpdateMode.patchExtract:
        return '模型没输出指令块时，额外发一次提取请求。多花一点 token，但弱模型也能用。';
      default:
        return '只靠模型主动输出的 <UpdateVariable> 指令块，最省 token。';
    }
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
    final character = _resolveCharacter(ref, sessionId);
    final definition = VariableDefinition.of(character?.rawExtensions);

    return _VariableScopeView(
      scopeLabel: 'chat',
      variables: variables,
      description: character == null
          ? null
          : (definition.isActive
              ? '角色卡「${character.name}」定义了 ${definition.init.length} 个变量。'
              : '角色卡「${character.name}」没有变量定义 —— 变量功能不会激活。'),
      extraActions: [
        if (definition.hasInit)
          TextButton.icon(
            onPressed: () => _resetFromCard(context, ref, sessionId, character),
            icon: const Icon(Icons.restart_alt,
                color: Colors.lightGreenAccent, size: 18),
            label: const Text(
              '从角色卡初始化',
              style: TextStyle(color: Colors.lightGreenAccent),
            ),
          ),
        TextButton.icon(
          onPressed: variables.isEmpty
              ? null
              : () => _exportJson(context, variables),
          icon: const Icon(Icons.ios_share,
              color: Colors.lightBlueAccent, size: 18),
          label: const Text(
            '导出 JSON',
            style: TextStyle(color: Colors.lightBlueAccent),
          ),
        ),
        TextButton.icon(
          onPressed: () => _importJson(context, ref, sessionId),
          icon: const Icon(Icons.file_download,
              color: Colors.amberAccent, size: 18),
          label: const Text(
            '导入 JSON',
            style: TextStyle(color: Colors.amberAccent),
          ),
        ),
      ],
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

  /// 找当前会话绑定的角色卡（群聊取第一个）。
  Character? _resolveCharacter(WidgetRef ref, String sessionId) {
    try {
      final session = ref
          .read(sessionProvider)
          .firstWhere((item) => item.id == sessionId);
      final characterId = session.isGroup
          ? (session.groupCharacterIds.isEmpty
              ? session.characterId
              : session.groupCharacterIds.first)
          : session.characterId;
      if (characterId.trim().isEmpty) {
        return null;
      }
      return ref
          .read(characterListProvider)
          .firstWhere((item) => item.id == characterId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _resetFromCard(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    Character? character,
  ) async {
    final definition = VariableDefinition.of(character?.rawExtensions);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('从角色卡初始化',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '这会清空当前会话的全部变量，并重新灌入角色卡上的 ${definition.init.length} 个初始值。\n'
          '已经推进过的剧情数值会丢失，确定继续吗？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('初始化',
                style: TextStyle(color: Colors.lightGreenAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final count = ref
        .read(variableRuntimeProvider)
        .resetToCardInitial(sessionId: sessionId, character: character);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已灌入 $count 个初始值')),
    );
  }

  Future<void> _exportJson(
    BuildContext context,
    Map<String, dynamic> variables,
  ) async {
    final text = const JsonEncoder.withIndent('  ').convert(variables);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${variables.length} 个变量到剪贴板')),
    );
  }

  Future<void> _importJson(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('导入变量 JSON', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '{"角色.好感度": 35, "角色.生命值": 82}',
              hintStyle: TextStyle(color: Colors.white38),
              labelText: 'JSON 对象',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) {
      return;
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(text.trim());
      if (raw is! Map) {
        throw const FormatException('顶层必须是一个 JSON 对象');
      }
      decoded = raw.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON 解析失败：$e')),
      );
      return;
    }

    final notifier = ref.read(chatVariablesProvider(sessionId).notifier);
    for (final entry in decoded.entries) {
      notifier.setValue(entry.key, entry.value);
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 ${decoded.length} 个变量')),
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

  /// 作用域说明（例如「角色卡「XX」定义了 6 个变量」）。
  final String? description;

  /// 额外操作按钮（会话变量页用来放「从角色卡初始化 / 导入 / 导出」）。
  final List<Widget> extraActions;

  const _VariableScopeView({
    required this.scopeLabel,
    required this.variables,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onClear,
    this.description,
    this.extraActions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (variables.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '暂无变量',
                    style: TextStyle(color: Colors.white54),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      description!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (extraActions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: extraActions,
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    description!,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  ...extraActions,
                  TextButton.icon(
                    onPressed: () => _confirmClear(context),
                    icon: const Icon(Icons.delete_sweep,
                        color: Colors.orangeAccent, size: 18),
                    label: const Text(
                      '清空当前作用域',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                ],
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
