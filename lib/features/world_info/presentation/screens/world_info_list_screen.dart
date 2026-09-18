import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/file_helper.dart';
import '../../data/world_info_provider.dart';
import '../../domain/models/world_info.dart';
import '../widgets/world_info_activation_settings.dart';

class WorldInfoListScreen extends ConsumerWidget {
  const WorldInfoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(worldInfoProvider);
    final activeIds = ref.watch(activeWorldInfoIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局世界书 (Global World Info)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: '导入',
            onPressed: () async {
              try {
                final result = await FileHelper.pickJson();
                if (result != null) {
                  final json = result.data;
                  if (json is Map<String, dynamic>) {
                    var wi = WorldInfo.fromJson(json);
                    if (wi.name == 'New World Info' || json['name'] == null) {
                      wi = WorldInfo(
                        id: wi.id,
                        name: result.name,
                        entries: wi.entries,
                      );
                    }
                    await ref.read(worldInfoProvider.notifier).save(wi);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('导入成功: ${wi.name}')));
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('导入失败: 无效的 JSON 格式')));
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('导入失败: $e')));
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建',
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const WorldInfoEditScreen()));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGlobalActiveSection(context, ref, list, activeIds),
          const SizedBox(height: 16),
          const WorldInfoActivationSettingsPanel(),
          const SizedBox(height: 24),
          _buildAllSectionHeader(list.length),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('还没有世界书，点击右上角「新建」或「导入」添加。',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...list.map(
              (item) => _buildWorldInfoCard(
                context,
                ref,
                item,
                isActive: activeIds.contains(item.id),
              ),
            ),
        ],
      ),
    );
  }

  /// 「全局生效」区块：集中展示对所有角色生效的世界书。
  ///
  /// 底层就是 `active_world_info_ids`（由 [activeWorldInfoIdsProvider] 承载），
  /// 它在 `chat_provider` 中作为 globalIds 参与合并，对全部角色卡生效。
  Widget _buildGlobalActiveSection(
    BuildContext context,
    WidgetRef ref,
    List<WorldInfo> list,
    List<String> activeIds,
  ) {
    final activeSet = activeIds.toSet();
    final activeItems =
        list.where((item) => activeSet.contains(item.id)).toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 20, color: Colors.green.shade400),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('全局生效（对所有角色）',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${activeItems.length} 个',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade300,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '勾选后对全部角色卡自动生效，无需在每张卡里单独启用。'
            '（角色卡专属世界书请到角色卡「绑定」页设置）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (activeItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '暂无全局生效的世界书。在下方列表中打开「全局生效」开关即可添加。',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            )
          else
            for (final item in activeItems)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.book, size: 18, color: Colors.green.shade400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            '${item.entries.length} 个条目'
                            '${item.disabled ? ' · 自身已禁用（不会生效）' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: item.disabled
                                  ? Colors.orange.shade300
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '取消全局生效',
                      icon: Icon(Icons.remove_circle_outline,
                          size: 20, color: Colors.green.shade300),
                      onPressed: () => ref
                          .read(activeWorldInfoIdsProvider.notifier)
                          .setActive(item.id, false),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    WorldInfoEditScreen(worldInfo: item)));
                      },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAllSectionHeader(int total) {
    return Row(
      children: [
        const Icon(Icons.list_alt, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        const Text('全部世界书',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text('共 $total 个',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildWorldInfoCard(
    BuildContext context,
    WidgetRef ref,
    WorldInfo item, {
    required bool isActive,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActive
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.grey.shade700,
          )),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => WorldInfoEditScreen(worldInfo: item)));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.book,
                  color: isActive ? Colors.green.shade400 : Colors.grey,
                  size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${item.entries.length} 个条目',
                            style:
                                TextStyle(color: Colors.grey[500], fontSize: 12)),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          _buildStatusChip('已全局生效', Colors.green),
                        ],
                        if (item.disabled) ...[
                          const SizedBox(width: 8),
                          _buildStatusChip('自身已禁用', Colors.orange),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text('全局生效',
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive ? Colors.green.shade300 : Colors.grey,
                      )),
                  Switch(
                    value: isActive,
                    activeThumbColor: Colors.green,
                    onChanged: (val) => ref
                        .read(activeWorldInfoIdsProvider.notifier)
                        .setActive(item.id, val),
                  ),
                ],
              ),
              IconButton(
                tooltip: '导出',
                icon: const Icon(Icons.share, size: 20),
                onPressed: () {
                  FileHelper.exportJson(item.toJson(), item.name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color.shade300, fontWeight: FontWeight.w600)),
    );
  }
}

class WorldInfoEditScreen extends ConsumerStatefulWidget {
  final WorldInfo? worldInfo;
  const WorldInfoEditScreen({super.key, this.worldInfo});

  @override
  ConsumerState<WorldInfoEditScreen> createState() =>
      _WorldInfoEditScreenState();
}

class _WorldInfoEditScreenState extends ConsumerState<WorldInfoEditScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  List<WorldInfoEntry> _entries = [];
  String _searchQuery = '';
  bool _useTabbedLayout = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.worldInfo?.name ?? '新建世界书';
    _entries = widget.worldInfo?.entries.toList() ?? [];
  }

  void _save() {
    if (_nameController.text.isEmpty) return;

    final newItem = WorldInfo(
      id: widget.worldInfo?.id ?? const Uuid().v4(),
      name: _nameController.text,
      disabled: widget.worldInfo?.disabled ?? false,
      entries: _entries,
    );

    ref.read(worldInfoProvider.notifier).save(newItem);
    Navigator.pop(context);
  }

  void _addEntry() {
    setState(() {
      _entries.add(WorldInfoEntry(
        uid: DateTime.now().millisecondsSinceEpoch,
        keys: [],
        content: '',
        comment: '新条目',
      ));
    });
  }

  void _deleteEntry(int index) {
    setState(() {
      _entries.removeAt(index);
    });
  }

  void _updateEntry(int index, WorldInfoEntry newEntry) {
    setState(() {
      _entries[index] = newEntry;
    });
  }

  Widget _buildCountCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    final disabledCount = _entries.where((entry) => entry.disable).length;
    final constantCount = _entries.where((entry) => entry.constant).length;
    final regexCount = _entries.where((entry) => entry.useRegex).length;
    final recursiveCount =
        _entries.where((entry) => !entry.preventRecursion).length;

    final positionCounts = <String, int>{
      '角色描述之前 (Before Character)': 0,
      '角色描述之后 (After Character)': 0,
      '作者注释之前 (Before Author Note)': 0,
      '作者注释之后 (After Author Note)': 0,
      '指定深度 (At Depth)': 0,
      '示例对话之前 (Before Examples)': 0,
      '示例对话之后 (After Examples)': 0,
      '用户消息顶部 (User Top)': 0,
      'AI 消息顶部 (Assistant Top)': 0,
    };

    for (final entry in _entries) {
      switch (entry.position) {
        case 0:
          positionCounts['角色描述之前 (Before Character)'] =
              (positionCounts['角色描述之前 (Before Character)'] ?? 0) + 1;
          break;
        case 1:
          positionCounts['角色描述之后 (After Character)'] =
              (positionCounts['角色描述之后 (After Character)'] ?? 0) + 1;
          break;
        case 2:
          positionCounts['作者注释之前 (Before Author Note)'] =
              (positionCounts['作者注释之前 (Before Author Note)'] ?? 0) + 1;
          break;
        case 3:
          positionCounts['作者注释之后 (After Author Note)'] =
              (positionCounts['作者注释之后 (After Author Note)'] ?? 0) + 1;
          break;
        case 4:
          positionCounts['指定深度 (At Depth)'] =
              (positionCounts['指定深度 (At Depth)'] ?? 0) + 1;
          break;
        case 5:
          positionCounts['示例对话之前 (Before Examples)'] =
              (positionCounts['示例对话之前 (Before Examples)'] ?? 0) + 1;
          break;
        case 6:
          positionCounts['示例对话之后 (After Examples)'] =
              (positionCounts['示例对话之后 (After Examples)'] ?? 0) + 1;
          break;
        case 7:
          positionCounts['用户消息顶部 (User Top)'] =
              (positionCounts['用户消息顶部 (User Top)'] ?? 0) + 1;
          break;
        case 8:
          positionCounts['AI 消息顶部 (Assistant Top)'] =
              (positionCounts['AI 消息顶部 (Assistant Top)'] ?? 0) + 1;
          break;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Text(
          '世界书概览 (Book Overview)',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '按 SillyTavern 习惯汇总的本世界书统计信息，方便在逐条编辑条目之前快速掌握整体情况。',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildCountCard(
              context,
              label: '条目总数 (Total Entries)',
              value: '${_entries.length}',
              icon: Icons.library_books_outlined,
            ),
            _buildCountCard(
              context,
              label: '已禁用 (Disabled)',
              value: '$disabledCount',
              icon: Icons.power_settings_new,
              color: Colors.grey,
            ),
            _buildCountCard(
              context,
              label: '常驻条目 (Constant)',
              value: '$constantCount',
              icon: Icons.push_pin_outlined,
              color: Colors.teal,
            ),
            _buildCountCard(
              context,
              label: '正则条目 (Regex)',
              value: '$regexCount',
              icon: Icons.code,
              color: Colors.deepOrange,
            ),
            _buildCountCard(
              context,
              label: '可递归 (Recursing)',
              value: '$recursiveCount',
              icon: Icons.hub_outlined,
              color: Colors.indigo,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '注入位置分布 (Injection Positions)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in positionCounts.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text('${item.key}: ${item.value}'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前编辑器能力 (Current Book Notes)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '当前编辑器为每个条目提供完整的 SillyTavern 高级字段，包括：次级关键词逻辑、深度注入、触发概率、时效控制（常驻/冷却/延迟）、递归行为，以及全局扫描范围。',
                style: TextStyle(color: Colors.grey.shade700, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabbedScaffold(
    BuildContext context,
    List<MapEntry<int, WorldInfoEntry>> filteredEntries,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.black, fontSize: 20),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '世界书名称',
          ),
        ),
        actions: [
          if (widget.worldInfo != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除世界书？'),
                    content: const Text('该世界书将被永久删除，此操作不可撤销。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(worldInfoProvider.notifier)
                              .delete(widget.worldInfo!.id);
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text(
                          '删除',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.deepPurple),
            onPressed: _save,
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const TabBar(
                tabs: [
                  Tab(text: '条目 (Entries)'),
                  Tab(text: '概览 (Overview)'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: '搜索条目...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 0,
                                  ),
                                ),
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: _addEntry,
                              icon: const Icon(Icons.add),
                              label: const Text('添加'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[50],
                                foregroundColor: Colors.green[800],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredEntries.length,
                          itemBuilder: (context, index) {
                            final originalIndex = filteredEntries[index].key;
                            final entry = filteredEntries[index].value;
                            return WorldInfoEntryCard(
                              key: ValueKey(entry.uid),
                              entry: entry,
                              onChanged: (newEntry) =>
                                  _updateEntry(originalIndex, newEntry),
                              onDelete: () => _deleteEntry(originalIndex),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  _buildOverviewTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _entries.asMap().entries.where((e) {
      if (_searchQuery.isEmpty) return true;
      final entry = e.value;
      return entry.comment.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          entry.keys.any(
              (k) => k.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          entry.content.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (_useTabbedLayout) {
      return _buildTabbedScaffold(context, filteredEntries);
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.black, fontSize: 20),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '世界书名称',
          ),
        ),
        actions: [
          if (widget.worldInfo != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除世界书'),
                    content: const Text('确定要删除吗？'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(worldInfoProvider.notifier)
                              .delete(widget.worldInfo!.id);
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text('删除',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          IconButton(
              icon: const Icon(Icons.save, color: Colors.deepPurple),
              onPressed: _save),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索条目...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _addEntry,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[50],
                    foregroundColor: Colors.green[800],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredEntries.length,
              itemBuilder: (context, index) {
                final originalIndex = filteredEntries[index].key;
                final entry = filteredEntries[index].value;
                return WorldInfoEntryCard(
                  key: ValueKey(entry.uid),
                  entry: entry,
                  onChanged: (newEntry) =>
                      _updateEntry(originalIndex, newEntry),
                  onDelete: () => _deleteEntry(originalIndex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WorldInfoEntryCard extends StatefulWidget {
  final WorldInfoEntry entry;
  final ValueChanged<WorldInfoEntry> onChanged;
  final VoidCallback onDelete;

  const WorldInfoEntryCard(
      {super.key,
      required this.entry,
      required this.onChanged,
      required this.onDelete});

  @override
  State<WorldInfoEntryCard> createState() => _AdvancedWorldInfoEntryCardState();
}

// ignore: unused_element
class _WorldInfoEntryCardState extends State<WorldInfoEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Column(
        children: [
          // Header Row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.power_settings_new,
                        color: entry.disable ? Colors.grey : Colors.green),
                    onPressed: () {
                      widget.onChanged(entry.copyWith(disable: !entry.disable));
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            entry.comment.isEmpty
                                ? '未命名条目'
                                : entry.comment,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        if (entry.keys.isNotEmpty)
                          Text(entry.keys.join(', '),
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.delete, color: Colors.grey),
                      onPressed: widget.onDelete),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and Group
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.comment,
                          decoration: const InputDecoration(
                              labelText: '名称 / 注释',
                              isDense: true,
                              border: OutlineInputBorder()),
                          onChanged: (v) => _update(comment: v),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.group,
                          decoration: const InputDecoration(
                              labelText: '分组 (GROUP)',
                              isDense: true,
                              border: OutlineInputBorder()),
                          onChanged: (v) => _update(group: v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Content
                  TextFormField(
                    initialValue: entry.content,
                    decoration: const InputDecoration(
                        labelText: '内容 (CONTENT)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true),
                    maxLines: 6,
                    onChanged: (v) => _update(content: v),
                  ),
                  const SizedBox(height: 16),

                  // Trigger Conditions
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.key, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            const Text('触发条件',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            _buildCheckbox('常驻', entry.constant,
                                (v) => _update(constant: v)),
                            _buildCheckbox('正则', entry.useRegex,
                                (v) => _update(useRegex: v)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: entry.keys.join(', '),
                          decoration: const InputDecoration(
                              labelText: '主触发词 (逗号分隔)',
                              border: OutlineInputBorder(),
                              isDense: true),
                          onChanged: (v) => _update(
                              keys: v.split(',').map((e) => e.trim()).toList()),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          children: [
                            _buildCheckbox('大小写敏感', entry.caseSensitive,
                                (v) => _update(caseSensitive: v)),
                            _buildCheckbox('全词匹配', entry.matchWholeWords,
                                (v) => _update(matchWholeWords: v)),
                            _buildCheckbox('逻辑组合', entry.selective,
                                (v) => _update(selective: v)),
                          ],
                        ),
                        if (entry.selective) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: entry.secondaryKeys.join(', '),
                            decoration: const InputDecoration(
                                labelText: '次级触发词 (Secondary Keys)',
                                border: OutlineInputBorder(),
                                isDense: true),
                            onChanged: (v) => _update(
                                secondaryKeys:
                                    v.split(',').map((e) => e.trim()).toList()),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            initialValue: entry.selectiveLogic,
                            decoration: const InputDecoration(
                                labelText: '逻辑关系',
                                border: OutlineInputBorder(),
                                isDense: true),
                            items: const [
                              DropdownMenuItem(
                                  value: 0, child: Text('AND (同时满足)')),
                              DropdownMenuItem(
                                  value: 1, child: Text('OR (任一满足)')),
                              DropdownMenuItem(
                                  value: 2, child: Text('NOT (不包含)')),
                            ],
                            onChanged: (v) => _update(selectiveLogic: v),
                          ),
                        ]                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Advanced Settings
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Injection Position
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('注入位置',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey)),
                              const SizedBox(height: 4),
                              DropdownButton<int>(
                                value: entry.position,
                                isExpanded: true,
                                underline: Container(),
                                items: const [
                                  DropdownMenuItem(
                                      value: 0,
                                      child: Text('角色描述之前',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 1,
                                      child: Text('角色描述之后',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 2,
                                      child: Text('作者注释之前',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 3,
                                      child: Text('作者注释之后',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 4,
                                      child: Text('指定深度',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 5,
                                      child: Text('示例对话之前',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 6,
                                      child: Text('示例对话之后',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 7,
                                      child: Text('用户消息顶部',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 8,
                                      child: Text('AI 消息顶部',
                                          style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (v) => _update(position: v),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.order.toString(),
                                          '顺序',
                                          (v) => _update(
                                              order: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.depth.toString(),
                                          '深度',
                                          (v) => _update(
                                              depth: int.tryParse(v) ?? 0))),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Timing Control
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('时效控制',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.sticky.toString(),
                                          '常驻',
                                          (v) => _update(
                                              sticky: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.cooldown.toString(),
                                          '冷却',
                                          (v) => _update(
                                              cooldown: int.tryParse(v) ?? 0))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildMiniInput(entry.delay.toString(), '延迟',
                                  (v) => _update(delay: int.tryParse(v) ?? 0)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Probability
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('概率',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey)),
                              const SizedBox(height: 4),
                              Center(
                                  child: Text('${entry.probability}%',
                                      style: const TextStyle(
                                          fontSize: 20, color: Colors.green))),
                              Slider(
                                value:
                                    entry.probability.toDouble().clamp(0, 100),
                                min: 0,
                                max: 100,
                                onChanged: (v) =>
                                    _update(probability: v.toInt()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckbox(
      String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMiniInput(
      String initialValue, String label, ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.all(8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      style: const TextStyle(fontSize: 12),
      keyboardType: TextInputType.number,
      onChanged: onChanged,
    );
  }

  void _update({
    List<String>? keys,
    List<String>? secondaryKeys,
    String? comment,
    String? content,
    bool? constant,
    bool? disable,
    bool? useRegex,
    bool? caseSensitive,
    bool? matchWholeWords,
    bool? selective,
    int? selectiveLogic,
    int? position,
    int? depth,
    int? order,
    int? probability,
    int? sticky,
    int? cooldown,
    int? delay,
    String? group,
  }) {
    widget.onChanged(
      widget.entry.copyWith(
        keys: keys ?? widget.entry.keys,
        secondaryKeys: secondaryKeys ?? widget.entry.secondaryKeys,
        comment: comment ?? widget.entry.comment,
        content: content ?? widget.entry.content,
        constant: constant ?? widget.entry.constant,
        disable: disable ?? widget.entry.disable,
        useRegex: useRegex ?? widget.entry.useRegex,
        caseSensitive: caseSensitive ?? widget.entry.caseSensitive,
        matchWholeWords: matchWholeWords ?? widget.entry.matchWholeWords,
        selective: selective ?? widget.entry.selective,
        selectiveLogic: selectiveLogic ?? widget.entry.selectiveLogic,
        position: position ?? widget.entry.position,
        depth: depth ?? widget.entry.depth,
        order: order ?? widget.entry.order,
        probability: probability ?? widget.entry.probability,
        sticky: sticky ?? widget.entry.sticky,
        cooldown: cooldown ?? widget.entry.cooldown,
        delay: delay ?? widget.entry.delay,
        group: group ?? widget.entry.group,
      ),
    );
  }
}

class _AdvancedWorldInfoEntryCardState extends State<WorldInfoEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.power_settings_new,
                      color: entry.disable ? Colors.grey : Colors.green,
                    ),
                    onPressed: () {
                      widget.onChanged(entry.copyWith(disable: !entry.disable));
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.comment.isEmpty
                              ? '未命名条目'
                              : entry.comment,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildHeaderChip(_positionLabel(entry.position)),
                            _buildHeaderChip('顺序 ${entry.order}'),
                            if (entry.position == 4)
                              _buildHeaderChip('深度 ${entry.depth}'),
                            if (entry.position == 4)
                              _buildHeaderChip(_roleLabel(entry.role)),
                            if (entry.constant) _buildHeaderChip('常驻'),
                            if (entry.useRegex) _buildHeaderChip('正则'),
                            if (entry.disable) _buildHeaderChip('已禁用'),
                          ],
                        ),
                        if (entry.keys.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            entry.keys.join(', '),
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: widget.onDelete,
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    title: '基础 (Basic)',
                    icon: Icons.description_outlined,
                    initiallyExpanded: true,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _buildTextField(
                              label: '名称 / 注释 (Name / Comment)',
                              helper: '仅用于标识条目，不会注入给模型。',
                              initialValue: entry.comment,
                              onChanged: (v) => _update(comment: v),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: _buildTextField(
                              label: '分组 (Group)',
                              helper: '同组条目用于互斥/权重抽取。',
                              initialValue: entry.group,
                              onChanged: (v) => _update(group: v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        label: '内容 (Content)',
                        helper: '触发后真正注入给模型的世界书正文。',
                        initialValue: entry.content,
                        maxLines: 6,
                        onChanged: (v) => _update(content: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    title: '触发条件 (Trigger)',
                    icon: Icons.key_outlined,
                    initiallyExpanded: true,
                    children: [
                      _buildTextField(
                        label: '主触发词 (Primary Keys)',
                        helper: '逗号分隔；空关键词会被忽略。常驻条目可以留空。',
                        initialValue: entry.keys.join(', '),
                        onChanged: (v) => _update(keys: _parseCsv(v)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: '常驻 (Constant)',
                            subtitle: '无需关键词扫描，始终激活注入。',
                            value: entry.constant,
                            onChanged: (v) => _update(constant: v),
                          ),
                          _buildToggleTile(
                            title: '正则匹配 (Regex)',
                            subtitle: '用正则表达式匹配关键词。',
                            value: entry.useRegex,
                            onChanged: (v) => _update(useRegex: v),
                          ),
                          _buildToggleTile(
                            title: '区分大小写 (Case Sensitive)',
                            subtitle: '匹配时区分英文大小写。',
                            value: entry.caseSensitive,
                            onChanged: (v) => _update(caseSensitive: v),
                          ),
                          _buildToggleTile(
                            title: '全词匹配 (Whole Words)',
                            subtitle: '仅匹配完整单词，避免部分命中。',
                            value: entry.matchWholeWords,
                            onChanged: (v) => _update(matchWholeWords: v),
                          ),
                          _buildToggleTile(
                            title: '次级关键词 (Secondary Logic)',
                            subtitle: '启用次级关键词过滤条件。',
                            value: entry.selective,
                            onChanged: (v) => _update(selective: v),
                          ),
                        ],
                      ),
                      if (entry.selective) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: '次级触发词 (Secondary Keys)',
                          helper: '逗号分隔的次级关键词。',
                          initialValue: entry.secondaryKeys.join(', '),
                          onChanged: (v) =>
                              _update(secondaryKeys: _parseCsv(v)),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField<int>(
                          label: '次级逻辑模式 (Secondary Logic Mode)',
                          value: _normalizeSelectiveLogic(entry.selectiveLogic),
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('主词满足 + 任一 次级词 (AND ANY)'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('主词满足 + 全部 次级词 (AND ALL)'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('主词满足 + 不含 次级词 (NOT ANY)'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('主词满足 + 非全部 次级词 (NOT ALL)'),
                            ),
                          ],
                          onChanged: (v) => _update(selectiveLogic: v),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    title: '注入 (Injection)',
                    icon: Icons.input_outlined,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: _buildDropdownField<int>(
                              label: '注入位置 (Position)',
                              value: _normalizePosition(entry.position),
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('角色描述之前 (Before Character)'),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('角色描述之后 (After Character)'),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Text('作者注释之前 (Before Author Note)'),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text('作者注释之后 (After Author Note)'),
                                ),
                                DropdownMenuItem(
                                  value: 4,
                                  child: Text('指定深度 (At Depth)'),
                                ),
                                DropdownMenuItem(
                                  value: 5,
                                  child: Text('示例对话之前 (Before Examples)'),
                                ),
                                DropdownMenuItem(
                                  value: 6,
                                  child: Text('示例对话之后 (After Examples)'),
                                ),
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('用户消息顶部 (User Top)'),
                                ),
                                DropdownMenuItem(
                                  value: 8,
                                  child: Text('AI 消息顶部 (Assistant Top)'),
                                ),
                              ],
                              onChanged: (v) => _update(position: v),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: _buildDropdownField<String>(
                              label: '角色 (Role)',
                              value: _normalizeRole(entry.role),
                              items: const [
                                DropdownMenuItem(
                                  value: 'system',
                                  child: Text('系统 (System)'),
                                ),
                                DropdownMenuItem(
                                  value: 'user',
                                  child: Text('用户 (User)'),
                                ),
                                DropdownMenuItem(
                                  value: 'assistant',
                                  child: Text('AI (Assistant)'),
                                ),
                              ],
                              onChanged: (v) => _update(role: v),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: '顺序 (Order)',
                              helper: '数字越大越靠前注入。',
                              value: entry.order,
                              onChanged: (v) => _update(order: v),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: '深度 (Depth)',
                              helper: '仅"指定深度"位置生效。',
                              value: entry.depth,
                              onChanged: (v) => _update(depth: v),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: _buildNumberField(
                              label: '扫描深度 (Scan Depth)',
                              value: entry.scanDepth,
                              allowBlank: true,
                              helper: '留空则使用全局默认扫描深度。',
                              onChanged: (v) => _update(
                                scanDepth: v,
                                clearScanDepth: v == null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    title: '效果与时效 (Effects)',
                    icon: Icons.tune_outlined,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: '启用概率 (Use Probability)',
                            subtitle: '按设定概率决定是否激活。',
                            value: entry.useProbability,
                            onChanged: (v) => _update(useProbability: v),
                          ),
                          _buildToggleTile(
                            title: '分组强制 (Group Override)',
                            subtitle: '强制该条目在同组中胜出。',
                            value: entry.groupOverride,
                            onChanged: (v) => _update(groupOverride: v),
                          ),
                          _buildToggleTile(
                            title: '排除递归 (Exclude Recursion)',
                            subtitle: '递归扫描时跳过该条目。',
                            value: entry.excludeRecursion,
                            onChanged: (v) => _update(excludeRecursion: v),
                          ),
                          _buildToggleTile(
                            title: '阻止递归 (Prevent Recursion)',
                            subtitle: '不把该内容加入后续扫描缓冲。',
                            value: entry.preventRecursion,
                            onChanged: (v) => _update(preventRecursion: v),
                          ),
                          _buildToggleTile(
                            title: '忽略预算 (Ignore Budget)',
                            subtitle: '即使超出世界书预算也允许激活。',
                            value: entry.ignoreBudget,
                            onChanged: (v) => _update(ignoreBudget: v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: '常驻轮数 (Sticky)',
                              helper: '激活后继续保留的轮数。',
                              value: entry.sticky,
                              onChanged: (v) => _update(sticky: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: '冷却轮数 (Cooldown)',
                              helper: '激活后禁止再次触发的轮数。',
                              value: entry.cooldown,
                              onChanged: (v) => _update(cooldown: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: '延迟轮数 (Delay)',
                              helper: '满足条件后延迟触发的轮数。',
                              value: entry.delay,
                              onChanged: (v) => _update(delay: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: _buildNumberField(
                              label: '递归延迟 (Delay Until Recursion)',
                              helper: '递归到指定层数才允许激活。',
                              value: entry.delayUntilRecursion,
                              onChanged: (v) =>
                                  _update(delayUntilRecursion: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: _buildNumberField(
                              label: '分组权重 (Group Weight)',
                              helper: '同组抽取时的权重值。',
                              value: entry.groupWeight,
                              onChanged: (v) => _update(groupWeight: v ?? 0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '触发概率: ${entry.probability}%',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: _buildNumberField(
                              label: '百分比',
                              value: entry.probability,
                              onChanged: (v) => _update(
                                probability: (v ?? 100).clamp(0, 100),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: entry.probability.clamp(0, 100).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${entry.probability.clamp(0, 100)}%',
                        onChanged: entry.useProbability
                            ? (value) => _update(
                                  probability: value.round().clamp(0, 100),
                                )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    title: '扫描范围 (Scan Scope)',
                    icon: Icons.travel_explore_outlined,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          '控制关键词除了聊天记录之外，还会在哪些角色卡/预设文本中查找。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: '用户人设描述 (Persona Description)',
                            subtitle: '在用户人设描述中扫描关键词。',
                            value: entry.matchPersonaDescription,
                            onChanged: (v) =>
                                _update(matchPersonaDescription: v),
                          ),
                          _buildToggleTile(
                            title: '角色描述 (Character Description)',
                            subtitle: '在角色卡描述中扫描关键词。',
                            value: entry.matchCharacterDescription,
                            onChanged: (v) =>
                                _update(matchCharacterDescription: v),
                          ),
                          _buildToggleTile(
                            title: '角色性格 (Character Personality)',
                            subtitle: '在角色性格/系统提示词中扫描关键词。',
                            value: entry.matchCharacterPersonality,
                            onChanged: (v) =>
                                _update(matchCharacterPersonality: v),
                          ),
                          _buildToggleTile(
                            title: '深度提示词 (Character Depth Prompt)',
                            subtitle: '在作者注释/深度提示词中扫描关键词。',
                            value: entry.matchCharacterDepthPrompt,
                            onChanged: (v) =>
                                _update(matchCharacterDepthPrompt: v),
                          ),
                          _buildToggleTile(
                            title: '场景设定 (Scenario)',
                            subtitle: '在场景设定文本中扫描关键词。',
                            value: entry.matchScenario,
                            onChanged: (v) => _update(matchScenario: v),
                          ),
                          _buildToggleTile(
                            title: '作者备注 (Creator Notes)',
                            subtitle: '在作者备注中扫描关键词。',
                            value: entry.matchCreatorNotes,
                            onChanged: (v) => _update(matchCreatorNotes: v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String initialValue,
    String? helper,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        alignLabelWithHint: maxLines > 1,
        border: const OutlineInputBorder(),
      ),
      minLines: maxLines > 1 ? maxLines : 1,
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField({
    required String label,
    required int? value,
    String? helper,
    bool allowBlank = false,
    ValueChanged<int?>? onChanged,
  }) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      onChanged: (raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty && allowBlank) {
          onChanged?.call(null);
          return;
        }
        onChanged?.call(int.tryParse(trimmed));
      },
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: CheckboxListTile(
        dense: true,
        value: value,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        onChanged: (next) => onChanged(next ?? false),
      ),
    );
  }

  List<String> _parseCsv(String input) {
    return input
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  int _normalizeSelectiveLogic(int value) {
    if (value < 0 || value > 3) {
      return 0;
    }
    return value;
  }

  int _normalizePosition(int value) {
    if (value < 0 || value > 8) {
      return 0;
    }
    return value;
  }

  String _normalizeRole(String role) {
    final value = role.trim().toLowerCase();
    if (value == 'user' || value == 'assistant') {
      return value;
    }
    return 'system';
  }

  String _positionLabel(int position) {
    switch (_normalizePosition(position)) {
      case 0:
        return '角色描述之前';
      case 1:
        return '角色描述之后';
      case 2:
        return '作者注释之前';
      case 3:
        return '作者注释之后';
      case 4:
        return '指定深度';
      case 5:
        return '示例对话之前';
      case 6:
        return '示例对话之后';
      case 7:
        return '用户消息顶部';
      case 8:
        return 'AI 消息顶部';
      default:
        return '角色描述之前';
    }
  }

  String _roleLabel(String role) {
    switch (_normalizeRole(role)) {
      case 'user':
        return '用户';
      case 'assistant':
        return 'AI';
      default:
        return '系统';
    }
  }

  void _update({
    List<String>? keys,
    List<String>? secondaryKeys,
    String? comment,
    String? content,
    String? role,
    bool? constant,
    bool? disable,
    bool? useRegex,
    bool? caseSensitive,
    bool? matchWholeWords,
    bool? selective,
    int? selectiveLogic,
    int? position,
    int? depth,
    int? order,
    int? probability,
    bool? useProbability,
    int? sticky,
    int? cooldown,
    int? delay,
    String? group,
    bool? groupOverride,
    int? groupWeight,
    bool? excludeRecursion,
    bool? preventRecursion,
    int? delayUntilRecursion,
    int? scanDepth,
    bool clearScanDepth = false,
    bool? matchPersonaDescription,
    bool? matchCharacterDescription,
    bool? matchCharacterPersonality,
    bool? matchCharacterDepthPrompt,
    bool? matchScenario,
    bool? matchCreatorNotes,
    bool? ignoreBudget,
  }) {
    widget.onChanged(
      widget.entry.copyWith(
        keys: keys ?? widget.entry.keys,
        secondaryKeys: secondaryKeys ?? widget.entry.secondaryKeys,
        comment: comment ?? widget.entry.comment,
        content: content ?? widget.entry.content,
        role: role ?? widget.entry.role,
        constant: constant ?? widget.entry.constant,
        disable: disable ?? widget.entry.disable,
        useRegex: useRegex ?? widget.entry.useRegex,
        caseSensitive: caseSensitive ?? widget.entry.caseSensitive,
        matchWholeWords: matchWholeWords ?? widget.entry.matchWholeWords,
        selective: selective ?? widget.entry.selective,
        selectiveLogic: selectiveLogic ?? widget.entry.selectiveLogic,
        position: position ?? widget.entry.position,
        depth: depth ?? widget.entry.depth,
        order: order ?? widget.entry.order,
        probability: probability ?? widget.entry.probability,
        useProbability: useProbability ?? widget.entry.useProbability,
        sticky: sticky ?? widget.entry.sticky,
        cooldown: cooldown ?? widget.entry.cooldown,
        delay: delay ?? widget.entry.delay,
        group: group ?? widget.entry.group,
        groupOverride: groupOverride ?? widget.entry.groupOverride,
        groupWeight: groupWeight ?? widget.entry.groupWeight,
        excludeRecursion: excludeRecursion ?? widget.entry.excludeRecursion,
        preventRecursion: preventRecursion ?? widget.entry.preventRecursion,
        delayUntilRecursion:
            delayUntilRecursion ?? widget.entry.delayUntilRecursion,
        scanDepth: scanDepth,
        clearScanDepth: clearScanDepth,
        matchPersonaDescription:
            matchPersonaDescription ?? widget.entry.matchPersonaDescription,
        matchCharacterDescription:
            matchCharacterDescription ?? widget.entry.matchCharacterDescription,
        matchCharacterPersonality:
            matchCharacterPersonality ?? widget.entry.matchCharacterPersonality,
        matchCharacterDepthPrompt:
            matchCharacterDepthPrompt ?? widget.entry.matchCharacterDepthPrompt,
        matchScenario: matchScenario ?? widget.entry.matchScenario,
        matchCreatorNotes: matchCreatorNotes ?? widget.entry.matchCreatorNotes,
        ignoreBudget: ignoreBudget ?? widget.entry.ignoreBudget,
      ),
    );
  }
}
