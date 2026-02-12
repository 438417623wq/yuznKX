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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入成功: ${wi.name}')));
                    }
                  } else {
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入失败: 无效的 JSON 格式')));
                     }
                  }
                }
              } catch (e) {
                 if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
                 }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldInfoEditScreen()));
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                 Navigator.push(context, MaterialPageRoute(builder: (_) => WorldInfoEditScreen(worldInfo: item)));
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
                          Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${item.entries.length} 个条目', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.power_settings_new, color: isActive ? Colors.green : Colors.grey),
                      onPressed: () {
                        ref.read(activeWorldInfoIdsProvider.notifier).toggle(item.id);
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
  ConsumerState<WorldInfoEditScreen> createState() => _WorldInfoEditScreenState();
}

class _WorldInfoEditScreenState extends ConsumerState<WorldInfoEditScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  List<WorldInfoEntry> _entries = [];
  String _searchQuery = '';

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

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _entries.asMap().entries.where((e) {
      if (_searchQuery.isEmpty) return true;
      final entry = e.value;
      return entry.comment.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             entry.keys.any((k) => k.toLowerCase().contains(_searchQuery.toLowerCase())) ||
             entry.content.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

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
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          ref.read(worldInfoProvider.notifier).delete(widget.worldInfo!.id);
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          IconButton(icon: const Icon(Icons.save, color: Colors.deepPurple), onPressed: _save),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  onChanged: (newEntry) => _updateEntry(originalIndex, newEntry),
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

  const WorldInfoEntryCard({
    super.key, 
    required this.entry, 
    required this.onChanged, 
    required this.onDelete
  });

  @override
  State<WorldInfoEntryCard> createState() => _WorldInfoEntryCardState();
}

class _WorldInfoEntryCardState extends State<WorldInfoEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
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
                    icon: Icon(Icons.power_settings_new, color: entry.disable ? Colors.grey : Colors.green),
                    onPressed: () {
                      widget.onChanged(WorldInfoEntry(
                        uid: entry.uid, keys: entry.keys, secondaryKeys: entry.secondaryKeys, comment: entry.comment, content: entry.content,
                        constant: entry.constant, disable: !entry.disable, useRegex: entry.useRegex, caseSensitive: entry.caseSensitive, matchWholeWords: entry.matchWholeWords, selective: entry.selective, selectiveLogic: entry.selectiveLogic, position: entry.position, depth: entry.depth, order: entry.order, probability: entry.probability, sticky: entry.sticky, cooldown: entry.cooldown, delay: entry.delay, group: entry.group,
                      ));
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.comment.isEmpty ? 'Untitled Entry' : entry.comment, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (entry.keys.isNotEmpty)
                          Text(entry.keys.join(', '), style: TextStyle(color: Colors.grey[600], fontSize: 12), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: widget.onDelete),
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
                          decoration: const InputDecoration(labelText: '名称 / 注释', isDense: true, border: OutlineInputBorder()),
                          onChanged: (v) => _update(comment: v),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.group,
                          decoration: const InputDecoration(labelText: '分组 (GROUP)', isDense: true, border: OutlineInputBorder()),
                          onChanged: (v) => _update(group: v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Content
                  TextFormField(
                    initialValue: entry.content,
                    decoration: const InputDecoration(labelText: '内容 (CONTENT)', border: OutlineInputBorder(), alignLabelWithHint: true),
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
                            const Text('触发条件', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            _buildCheckbox('常驻', entry.constant, (v) => _update(constant: v)),
                            _buildCheckbox('正则', entry.useRegex, (v) => _update(useRegex: v)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: entry.keys.join(', '),
                          decoration: const InputDecoration(
                            labelText: '主触发词 (逗号分隔)', 
                            border: OutlineInputBorder(),
                            isDense: true
                          ),
                          onChanged: (v) => _update(keys: v.split(',').map((e) => e.trim()).toList()),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          children: [
                            _buildCheckbox('大小写敏感', entry.caseSensitive, (v) => _update(caseSensitive: v)),
                            _buildCheckbox('全词匹配', entry.matchWholeWords, (v) => _update(matchWholeWords: v)),
                            _buildCheckbox('逻辑组合', entry.selective, (v) => _update(selective: v)),
                          ],
                        ),
                        if (entry.selective) ...[
                           const SizedBox(height: 8),
                           TextFormField(
                            initialValue: entry.secondaryKeys.join(', '),
                            decoration: const InputDecoration(
                              labelText: '次级触发词 (Secondary Keys)', 
                              border: OutlineInputBorder(),
                              isDense: true
                            ),
                            onChanged: (v) => _update(secondaryKeys: v.split(',').map((e) => e.trim()).toList()),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                             value: entry.selectiveLogic,
                             decoration: const InputDecoration(labelText: '逻辑关系', border: OutlineInputBorder(), isDense: true),
                             items: const [
                               DropdownMenuItem(value: 0, child: Text('AND (同时满足)')),
                               DropdownMenuItem(value: 1, child: Text('OR (任一满足)')),
                               DropdownMenuItem(value: 2, child: Text('NOT (不包含)')),
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
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('注入位置', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              DropdownButton<int>(
                                value: entry.position,
                                isExpanded: true,
                                underline: Container(),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('前 (Before)', style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(value: 1, child: Text('后 (After)', style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (v) => _update(position: v),
                              ),
                              Row(
                                children: [
                                  Expanded(child: _buildMiniInput(entry.order.toString(), 'Order', (v) => _update(order: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(child: _buildMiniInput(entry.depth.toString(), 'Depth', (v) => _update(depth: int.tryParse(v) ?? 0))),
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
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('时效控制', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(child: _buildMiniInput(entry.sticky.toString(), 'Stick', (v) => _update(sticky: int.tryParse(v) ?? 0))),
                                  const SizedBox(width: 4),
                                  Expanded(child: _buildMiniInput(entry.cooldown.toString(), 'Cool', (v) => _update(cooldown: int.tryParse(v) ?? 0))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildMiniInput(entry.delay.toString(), 'Delay', (v) => _update(delay: int.tryParse(v) ?? 0)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Probability
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('概率', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Center(child: Text('${entry.probability}%', style: const TextStyle(fontSize: 20, color: Colors.green))),
                              Slider(
                                value: entry.probability.toDouble().clamp(0, 100),
                                min: 0, max: 100,
                                onChanged: (v) => _update(probability: v.toInt()),
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

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
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

  Widget _buildMiniInput(String initialValue, String label, ValueChanged<String> onChanged) {
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
    List<String>? keys, List<String>? secondaryKeys, String? comment, String? content, bool? constant, bool? disable,
    bool? useRegex, bool? caseSensitive, bool? matchWholeWords, bool? selective, int? selectiveLogic,
    int? position, int? depth, int? order, int? probability, int? sticky, int? cooldown, int? delay, String? group,
  }) {
    widget.onChanged(WorldInfoEntry(
      uid: widget.entry.uid,
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
    ));
  }
}
