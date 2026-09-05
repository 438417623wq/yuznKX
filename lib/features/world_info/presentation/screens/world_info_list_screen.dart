import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/file_helper.dart';
import '../../data/world_info_provider.dart';
import '../../domain/models/world_info.dart';

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
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          final isActive = activeIds.contains(item.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => WorldInfoEditScreen(worldInfo: item)));
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.book, color: Colors.green.shade700, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${item.entries.length} 个条目',
                              style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.power_settings_new,
                          color: isActive ? Colors.green : Colors.grey),
                      onPressed: () {
                        ref
                            .read(activeWorldInfoIdsProvider.notifier)
                            .toggle(item.id);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        FileHelper.exportJson(item.toJson(), item.name);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
    _nameController.text = widget.worldInfo?.name ?? 'New World Info';
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
        comment: 'New Entry',
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
      'Before Character': 0,
      'After Character': 0,
      'Before Author Note': 0,
      'After Author Note': 0,
      'At Depth': 0,
      'Before Examples': 0,
      'After Examples': 0,
      'User Top': 0,
      'Assistant Top': 0,
    };

    for (final entry in _entries) {
      switch (entry.position) {
        case 0:
          positionCounts['Before Character'] =
              (positionCounts['Before Character'] ?? 0) + 1;
          break;
        case 1:
          positionCounts['After Character'] =
              (positionCounts['After Character'] ?? 0) + 1;
          break;
        case 2:
          positionCounts['Before Author Note'] =
              (positionCounts['Before Author Note'] ?? 0) + 1;
          break;
        case 3:
          positionCounts['After Author Note'] =
              (positionCounts['After Author Note'] ?? 0) + 1;
          break;
        case 4:
          positionCounts['At Depth'] = (positionCounts['At Depth'] ?? 0) + 1;
          break;
        case 5:
          positionCounts['Before Examples'] =
              (positionCounts['Before Examples'] ?? 0) + 1;
          break;
        case 6:
          positionCounts['After Examples'] =
              (positionCounts['After Examples'] ?? 0) + 1;
          break;
        case 7:
          positionCounts['User Top'] = (positionCounts['User Top'] ?? 0) + 1;
          break;
        case 8:
          positionCounts['Assistant Top'] =
              (positionCounts['Assistant Top'] ?? 0) + 1;
          break;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Text(
          'Book Overview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'A quick ST-style summary of this lorebook before you dive into individual entries.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildCountCard(
              context,
              label: 'Total Entries',
              value: '${_entries.length}',
              icon: Icons.library_books_outlined,
            ),
            _buildCountCard(
              context,
              label: 'Disabled',
              value: '$disabledCount',
              icon: Icons.power_settings_new,
              color: Colors.grey,
            ),
            _buildCountCard(
              context,
              label: 'Constant',
              value: '$constantCount',
              icon: Icons.push_pin_outlined,
              color: Colors.teal,
            ),
            _buildCountCard(
              context,
              label: 'Regex',
              value: '$regexCount',
              icon: Icons.code,
              color: Colors.deepOrange,
            ),
            _buildCountCard(
              context,
              label: 'Recursing',
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
                'Injection Positions',
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
                'Current Book Notes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'The current editor exposes ST-style advanced fields per entry, including secondary logic, depth placement, probability, timed effects, recursion behavior, and global scan scopes.',
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
            hintText: 'World Info Name',
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
                    title: const Text('Delete World Info?'),
                    content: const Text(
                        'This lorebook will be removed permanently.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
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
                          'Delete',
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
                  Tab(text: 'Entries'),
                  Tab(text: 'Overview'),
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
                                  hintText: 'Search entries...',
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
                              label: const Text('Add'),
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
                                ? 'Untitled Entry'
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
                        ]
                      ],
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
                                      child: Text('前 (Before)',
                                          style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(
                                      value: 1,
                                      child: Text('后 (After)',
                                          style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (v) => _update(position: v),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.order.toString(),
                                          'Order',
                                          (v) => _update(
                                              order: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.depth.toString(),
                                          'Depth',
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
                                          'Stick',
                                          (v) => _update(
                                              sticky: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: _buildMiniInput(
                                          entry.cooldown.toString(),
                                          'Cool',
                                          (v) => _update(
                                              cooldown: int.tryParse(v) ?? 0))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildMiniInput(entry.delay.toString(), 'Delay',
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
                              ? 'Untitled Entry'
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
                            _buildHeaderChip('Order ${entry.order}'),
                            if (entry.position == 4)
                              _buildHeaderChip('Depth ${entry.depth}'),
                            if (entry.position == 4)
                              _buildHeaderChip(_roleLabel(entry.role)),
                            if (entry.constant) _buildHeaderChip('Constant'),
                            if (entry.useRegex) _buildHeaderChip('Regex'),
                            if (entry.disable) _buildHeaderChip('Disabled'),
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
                    title: 'Basic',
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
                              label: 'Name / Comment',
                              initialValue: entry.comment,
                              onChanged: (v) => _update(comment: v),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: _buildTextField(
                              label: 'Group',
                              initialValue: entry.group,
                              onChanged: (v) => _update(group: v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        label: 'Content',
                        initialValue: entry.content,
                        maxLines: 6,
                        onChanged: (v) => _update(content: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    context,
                    title: 'Trigger',
                    icon: Icons.key_outlined,
                    initiallyExpanded: true,
                    children: [
                      _buildTextField(
                        label: 'Primary Keys',
                        helper:
                            'Comma separated. Empty keys are ignored. Constant entries can stay empty.',
                        initialValue: entry.keys.join(', '),
                        onChanged: (v) => _update(keys: _parseCsv(v)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: 'Constant',
                            subtitle: 'Always activate without key scanning.',
                            value: entry.constant,
                            onChanged: (v) => _update(constant: v),
                          ),
                          _buildToggleTile(
                            title: 'Regex',
                            subtitle: 'Use regular expression matching.',
                            value: entry.useRegex,
                            onChanged: (v) => _update(useRegex: v),
                          ),
                          _buildToggleTile(
                            title: 'Case Sensitive',
                            subtitle: 'Respect upper/lower case.',
                            value: entry.caseSensitive,
                            onChanged: (v) => _update(caseSensitive: v),
                          ),
                          _buildToggleTile(
                            title: 'Whole Words',
                            subtitle: 'Match only full words.',
                            value: entry.matchWholeWords,
                            onChanged: (v) => _update(matchWholeWords: v),
                          ),
                          _buildToggleTile(
                            title: 'Secondary Logic',
                            subtitle: 'Enable secondary-key filtering.',
                            value: entry.selective,
                            onChanged: (v) => _update(selective: v),
                          ),
                        ],
                      ),
                      if (entry.selective) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Secondary Keys',
                          helper: 'Comma separated secondary keys.',
                          initialValue: entry.secondaryKeys.join(', '),
                          onChanged: (v) =>
                              _update(secondaryKeys: _parseCsv(v)),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField<int>(
                          label: 'Secondary Logic Mode',
                          value: _normalizeSelectiveLogic(entry.selectiveLogic),
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Primary + any secondary'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('Primary + all secondary'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('Primary + none secondary'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('Primary + not all secondary'),
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
                    title: 'Injection',
                    icon: Icons.input_outlined,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: _buildDropdownField<int>(
                              label: 'Position',
                              value: _normalizePosition(entry.position),
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Before Character'),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('After Character'),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Text('Before Author Note'),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text('After Author Note'),
                                ),
                                DropdownMenuItem(
                                  value: 4,
                                  child: Text('At Depth'),
                                ),
                                DropdownMenuItem(
                                  value: 5,
                                  child: Text('Before Examples'),
                                ),
                                DropdownMenuItem(
                                  value: 6,
                                  child: Text('After Examples'),
                                ),
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('User Top'),
                                ),
                                DropdownMenuItem(
                                  value: 8,
                                  child: Text('Assistant Top'),
                                ),
                              ],
                              onChanged: (v) => _update(position: v),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: _buildDropdownField<String>(
                              label: 'Role',
                              value: _normalizeRole(entry.role),
                              items: const [
                                DropdownMenuItem(
                                  value: 'system',
                                  child: Text('System'),
                                ),
                                DropdownMenuItem(
                                  value: 'user',
                                  child: Text('User'),
                                ),
                                DropdownMenuItem(
                                  value: 'assistant',
                                  child: Text('Assistant'),
                                ),
                              ],
                              onChanged: (v) => _update(role: v),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: 'Order',
                              value: entry.order,
                              onChanged: (v) => _update(order: v),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: 'Depth',
                              value: entry.depth,
                              onChanged: (v) => _update(depth: v),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: _buildNumberField(
                              label: 'Scan Depth',
                              value: entry.scanDepth,
                              allowBlank: true,
                              helper: 'Blank uses default scan depth.',
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
                    title: 'Effects',
                    icon: Icons.tune_outlined,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: 'Use Probability',
                            subtitle: 'Gate activation by probability.',
                            value: entry.useProbability,
                            onChanged: (v) => _update(useProbability: v),
                          ),
                          _buildToggleTile(
                            title: 'Group Override',
                            subtitle: 'Force this entry to win inside group.',
                            value: entry.groupOverride,
                            onChanged: (v) => _update(groupOverride: v),
                          ),
                          _buildToggleTile(
                            title: 'Exclude Recursion',
                            subtitle: 'Skip this entry on recursion passes.',
                            value: entry.excludeRecursion,
                            onChanged: (v) => _update(excludeRecursion: v),
                          ),
                          _buildToggleTile(
                            title: 'Prevent Recursion',
                            subtitle:
                                'Do not add this content back to scan buffer.',
                            value: entry.preventRecursion,
                            onChanged: (v) => _update(preventRecursion: v),
                          ),
                          _buildToggleTile(
                            title: 'Ignore Budget',
                            subtitle: 'Allow activation even past WI budget.',
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
                              label: 'Sticky',
                              value: entry.sticky,
                              onChanged: (v) => _update(sticky: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: 'Cooldown',
                              value: entry.cooldown,
                              onChanged: (v) => _update(cooldown: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _buildNumberField(
                              label: 'Delay',
                              value: entry.delay,
                              onChanged: (v) => _update(delay: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: _buildNumberField(
                              label: 'Delay Until Recursion',
                              value: entry.delayUntilRecursion,
                              onChanged: (v) =>
                                  _update(delayUntilRecursion: v ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: _buildNumberField(
                              label: 'Group Weight',
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
                              'Probability: ${entry.probability}%',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: _buildNumberField(
                              label: 'Percent',
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
                    title: 'Scan Scope',
                    icon: Icons.travel_explore_outlined,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildToggleTile(
                            title: 'Persona Description',
                            subtitle: 'Scan the active persona description.',
                            value: entry.matchPersonaDescription,
                            onChanged: (v) =>
                                _update(matchPersonaDescription: v),
                          ),
                          _buildToggleTile(
                            title: 'Character Description',
                            subtitle: 'Scan character description.',
                            value: entry.matchCharacterDescription,
                            onChanged: (v) =>
                                _update(matchCharacterDescription: v),
                          ),
                          _buildToggleTile(
                            title: 'Character Personality',
                            subtitle:
                                'Scan character personality / system text.',
                            value: entry.matchCharacterPersonality,
                            onChanged: (v) =>
                                _update(matchCharacterPersonality: v),
                          ),
                          _buildToggleTile(
                            title: 'Character Depth Prompt',
                            subtitle: 'Scan author note / depth prompt.',
                            value: entry.matchCharacterDepthPrompt,
                            onChanged: (v) =>
                                _update(matchCharacterDepthPrompt: v),
                          ),
                          _buildToggleTile(
                            title: 'Scenario',
                            subtitle: 'Scan scenario text.',
                            value: entry.matchScenario,
                            onChanged: (v) => _update(matchScenario: v),
                          ),
                          _buildToggleTile(
                            title: 'Creator Notes',
                            subtitle: 'Scan creator notes.',
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
        return 'Before Character';
      case 1:
        return 'After Character';
      case 2:
        return 'Before Author Note';
      case 3:
        return 'After Author Note';
      case 4:
        return 'At Depth';
      case 5:
        return 'Before Examples';
      case 6:
        return 'After Examples';
      case 7:
        return 'User Top';
      case 8:
        return 'Assistant Top';
      default:
        return 'Before Character';
    }
  }

  String _roleLabel(String role) {
    switch (_normalizeRole(role)) {
      case 'user':
        return 'User';
      case 'assistant':
        return 'Assistant';
      default:
        return 'System';
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
