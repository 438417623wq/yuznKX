import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/world_info/data/world_info_provider.dart';
import '../../../features/world_info/domain/models/world_info.dart';
import '../../../features/chat/data/session_provider.dart';
import '../../../features/settings/domain/plugin_settings_provider.dart';
import '../../../features/character/data/character_provider.dart';
import 'widgets/memory_icon_view.dart';
import 'widgets/memory_table_view.dart';
import 'widgets/memory_vector_view.dart';
import 'widgets/memory_masonry_view.dart';
import 'widgets/memory_timeline_view.dart';
import 'widgets/memory_dashboard_view.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  int _selectedIndex = 0;
  String? _selectedBookId;
  bool _showChatMemory = true;
  bool _isSidebarExpanded = true;

  void _reorderEntries(WorldInfo? book, int oldIndex, int newIndex,
      {required bool isChat}) {
    if (book == null && !isChat) return;

    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final List<WorldInfoEntry> entries = isChat
          ? [] // Chat memory reordering not implemented yet as it's time-based usually
          : List.from(book!.entries);

      if (entries.isEmpty) return;

      final item = entries.removeAt(oldIndex);
      entries.insert(newIndex, item);

      // Update order field based on new index
      for (int i = 0; i < entries.length; i++) {
        entries[i] = entries[i].copyWith(order: i);
      }

      if (!isChat) {
        final updatedBook = book!.copyWith(entries: entries);
        ref.read(worldInfoProvider.notifier).save(updatedBook);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final worldInfos = ref.watch(worldInfoProvider);
    final plugins = ref.watch(pluginSettingsProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final sessions = ref.watch(sessionProvider);
    final activeCharacter = ref.watch(activeCharacterProvider);

    // 1. Get Chat Memory (Dynamic)
    List<WorldInfoEntry> chatEntries = [];
    if (activeSessionId != null && sessions.isNotEmpty) {
      try {
        final session = sessions.firstWhere((s) => s.id == activeSessionId);
        chatEntries = session.messages.asMap().entries.map((e) {
          final msg = e.value;
          final index = e.key;
          final timeStr =
              "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}";
          final roleName =
              msg.role == "user" ? "用户" : (msg.role == "system" ? "系统" : "角色");

          return WorldInfoEntry(
            uid: index,
            keys: [msg.role, 'msg'],
            comment: '$roleName ($timeStr)',
            content: msg.content,
            order: index,
            disable: false,
            secondaryKeys: [],
            constant: false,
            useRegex: false,
            caseSensitive: false,
            matchWholeWords: false,
            selective: true,
            selectiveLogic: 0,
            position: 0,
            depth: 4,
            probability: 100,
            sticky: 0,
            cooldown: 0,
            delay: 0,
            group: '',
          );
        }).toList();
      } catch (e) {
        // Session might be deleted or not found
      }
    }

    // 2. Filter World Info by Character (Isolation)
    List<WorldInfo> characterBooks = [];
    if (activeCharacter != null) {
      // If character has specific bound books, use them.
      // Otherwise, maybe show all? Or show none?
      // SillyTavern usually has "Character" specific world info and "Global" world info.
      // For now, let's filter by ids present in character.worldInfoIds if any, else show all.
      final scopedIds = <String>{
        if (activeCharacter.characterBookId?.trim().isNotEmpty == true)
          activeCharacter.characterBookId!,
        ...activeCharacter.worldInfoIds,
      };
      if (scopedIds.isNotEmpty) {
        characterBooks =
            worldInfos.where((w) => scopedIds.contains(w.id)).toList();
      } else {
        // If no bindings, maybe show all (Global mode) or create a default one for char?
        // Let's show all for backward compatibility but label them.
        characterBooks = worldInfos;
      }
    } else {
      characterBooks = worldInfos;
    }

    // 3. Selection Logic
    if (_selectedBookId == null && characterBooks.isNotEmpty) {
      _selectedBookId = characterBooks.first.id;
    } else if (_selectedBookId != null &&
        !characterBooks.any((w) => w.id == _selectedBookId)) {
      _selectedBookId =
          characterBooks.isNotEmpty ? characterBooks.first.id : null;
    }

    final activeBook = _selectedBookId != null
        ? worldInfos.firstWhere((w) => w.id == _selectedBookId,
            orElse: () => worldInfos.first)
        : null;

    final List<WorldInfoEntry> activeEntries =
        _showChatMemory ? chatEntries : (activeBook?.entries ?? []);

    // 4. Views Configuration
    final List<Widget> views = [];
    final List<NavigationDestination> destinations = [];

    // Icon View (Visual/Draggable)
    views.add(MemoryIconView(
      entries: activeEntries,
      onEdit: (entry) => _editEntry(activeBook, entry, isChat: _showChatMemory),
      onDelete: (entry) =>
          _deleteEntry(activeBook, entry, isChat: _showChatMemory),
      onReorder: (oldIndex, newIndex) => _reorderEntries(
          activeBook, oldIndex, newIndex,
          isChat: _showChatMemory),
    ));
    destinations.add(const NavigationDestination(
        icon: Icon(Icons.grid_view), label: '图标视图'));

    // Table View (Data/Sortable)
    views.add(MemoryTableView(
      entries: activeEntries,
      onEdit: (entry) => _editEntry(activeBook, entry, isChat: _showChatMemory),
      onDelete: (entry) =>
          _deleteEntry(activeBook, entry, isChat: _showChatMemory),
      onToggleActive: (entry, active) => _updateEntry(activeBook, entry,
          disable: !active, isChat: _showChatMemory),
    ));
    destinations.add(const NavigationDestination(
        icon: Icon(Icons.table_chart), label: '表格视图'));

    // Vector View (Search/RAG)
    if (plugins['memory_vector'] == true) {
      views.add(MemoryVectorView(entries: activeEntries));
      destinations.add(const NavigationDestination(
          icon: Icon(Icons.scatter_plot), label: '向量视图'));
    }

    // Extensions
    if (plugins['memory_masonry'] == true) {
      views.add(MemoryMasonryView(
          entries: activeEntries,
          onEdit: (e) => _editEntry(activeBook, e, isChat: _showChatMemory)));
      destinations.add(const NavigationDestination(
          icon: Icon(Icons.dashboard_customize), label: '瀑布流'));
    }
    if (plugins['memory_timeline'] == true) {
      views.add(MemoryTimelineView(
          entries: activeEntries,
          onEdit: (e) => _editEntry(activeBook, e, isChat: _showChatMemory)));
      destinations.add(const NavigationDestination(
          icon: Icon(Icons.timeline), label: '时间轴'));
    }
    if (plugins['memory_dashboard'] == true) {
      views.add(MemoryDashboardView(
          entries: activeEntries,
          onToggleAll: (e) => _toggleAllEntries(activeBook!, e)));
      destinations.add(const NavigationDestination(
          icon: Icon(Icons.analytics), label: '仪表盘'));
    }

    final safeIndex = _selectedIndex >= views.length ? 0 : _selectedIndex;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1b26), // SillyTavern Dark Theme
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.memory, color: Colors.tealAccent),
            const SizedBox(width: 8),
            Text(
                activeCharacter != null
                    ? '记忆库: ${activeCharacter.name}'
                    : '记忆库 (全局)',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
        backgroundColor: const Color(0xFF16161e),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使用教程',
            onPressed: _showTutorial,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Collapsible Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 200 : 70,
            color: const Color(0xFF1f2335),
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Source Toggle
                if (_isSidebarExpanded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: true,
                            label: Text('聊天'),
                            icon: Icon(Icons.chat_bubble, size: 16)),
                        ButtonSegment(
                            value: false,
                            label: Text('设定'),
                            icon: Icon(Icons.book, size: 16)),
                      ],
                      selected: {_showChatMemory},
                      onSelectionChanged: (v) =>
                          setState(() => _showChatMemory = v.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor:
                            MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.selected))
                            return Colors.teal;
                          return Colors.transparent;
                        }),
                        foregroundColor:
                            MaterialStateProperty.all(Colors.white),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(_showChatMemory ? Icons.chat_bubble : Icons.book,
                        color: Colors.tealAccent),
                    onPressed: () =>
                        setState(() => _showChatMemory = !_showChatMemory),
                  ),

                const SizedBox(height: 10),

                // Book Selector (If in World Info mode)
                if (!_showChatMemory) ...[
                  if (_isSidebarExpanded)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonFormField<String>(
                        value: _selectedBookId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF24283b),
                        decoration: const InputDecoration(
                          labelText: '选择世界书',
                          labelStyle:
                              TextStyle(color: Colors.white54, fontSize: 12),
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        items: characterBooks
                            .map((w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedBookId = v),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_isSidebarExpanded)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新建条目'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 36),
                        ),
                        onPressed: activeBook != null
                            ? () => _createEntry(activeBook)
                            : null,
                      ),
                    )
                  else
                    IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.teal),
                        onPressed: activeBook != null
                            ? () => _createEntry(activeBook)
                            : null),
                ],

                const Divider(color: Colors.white10),

                // Navigation Items
                Expanded(
                  child: ListView.builder(
                    itemCount: destinations.length,
                    itemBuilder: (context, index) {
                      final dest = destinations[index];
                      final isSelected = _selectedIndex == index;
                      return ListTile(
                        leading: IconTheme(
                          data: IconThemeData(
                              color: isSelected
                                  ? Colors.tealAccent
                                  : Colors.white54),
                          child: dest.icon,
                        ),
                        title: _isSidebarExpanded
                            ? Text(dest.label,
                                style: TextStyle(
                                    color: isSelected
                                        ? Colors.tealAccent
                                        : Colors.white70,
                                    fontSize: 13))
                            : null,
                        selected: isSelected,
                        selectedTileColor: Colors.white.withOpacity(0.05),
                        onTap: () => setState(() => _selectedIndex = index),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 24),
                        minLeadingWidth: 20,
                      );
                    },
                  ),
                ),

                // Collapse Button
                IconButton(
                  icon: Icon(
                      _isSidebarExpanded
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                      color: Colors.white38),
                  onPressed: () =>
                      setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Container(
              color: const Color(0xFF1a1b26),
              child: IndexedStack(
                index: safeIndex,
                children: views,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (Existing CRUD methods: _createEntry, _editEntry, _deleteEntry, _updateEntry, _toggleAllEntries)
  // ... (Existing _EntryEditDialog)

  void _createEntry(WorldInfo book) {
    final newEntry = WorldInfoEntry(
      uid: DateTime.now().millisecondsSinceEpoch,
      keys: [],
      content: '',
      comment: '新记忆',
    );
    _editEntry(book, newEntry, isNew: true);
  }

  void _editEntry(WorldInfo? book, WorldInfoEntry entry,
      {bool isNew = false, bool isChat = false}) {
    if (isChat) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF24283b),
          title:
              Text(entry.comment, style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
              child: Text(entry.content,
                  style: const TextStyle(color: Colors.white70))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
          ],
        ),
      );
      return;
    }

    if (book == null) return;

    showDialog(
      context: context,
      builder: (context) => _EntryEditDialog(
        entry: entry,
        onSave: (updatedEntry) {
          List<WorldInfoEntry> newEntries = [...book.entries];
          if (isNew) {
            newEntries.add(updatedEntry);
          } else {
            final idx = newEntries.indexWhere((e) => e.uid == entry.uid);
            if (idx >= 0) {
              newEntries[idx] = updatedEntry;
            }
          }
          final newBook =
              WorldInfo(id: book.id, name: book.name, entries: newEntries);
          ref.read(worldInfoProvider.notifier).save(newBook);
        },
      ),
    );
  }

  void _deleteEntry(WorldInfo? book, WorldInfoEntry entry,
      {bool isChat = false}) {
    if (isChat || book == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF24283b),
        title: const Text('删除记忆', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除条目 "${entry.comment}" 吗？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              List<WorldInfoEntry> newEntries =
                  book.entries.where((e) => e.uid != entry.uid).toList();
              final newBook =
                  WorldInfo(id: book.id, name: book.name, entries: newEntries);
              ref.read(worldInfoProvider.notifier).save(newBook);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _updateEntry(WorldInfo? book, WorldInfoEntry entry,
      {bool? disable, bool isChat = false}) {
    if (isChat || book == null) return;

    final updatedEntry = entry.copyWith(disable: disable ?? entry.disable);
    List<WorldInfoEntry> newEntries = [...book.entries];
    final idx = newEntries.indexWhere((e) => e.uid == entry.uid);
    if (idx >= 0) {
      newEntries[idx] = updatedEntry;
      final newBook =
          WorldInfo(id: book.id, name: book.name, entries: newEntries);
      ref.read(worldInfoProvider.notifier).save(newBook);
    }
  }

  void _toggleAllEntries(WorldInfo book, bool enable) {
    List<WorldInfoEntry> newEntries = book.entries.map((e) {
      return e.copyWith(disable: !enable);
    }).toList();

    final newBook =
        WorldInfo(id: book.id, name: book.name, entries: newEntries);
    ref.read(worldInfoProvider.notifier).save(newBook);
  }

  void _showTutorial() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f2335),
        title: const Row(children: [
          Icon(Icons.school, color: Colors.tealAccent),
          SizedBox(width: 8),
          Text('记忆系统使用教程', style: TextStyle(color: Colors.white))
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTutorialStep('1. 核心概念',
                    'SillyTavern 风格记忆系统分为 "聊天记忆" (短期上下文) 和 "世界设定" (长期知识库)。'),
                _buildTutorialStep('2. 视图切换',
                    '使用左侧边栏切换不同视图：\n• 图标视图：可视化卡片管理\n• 表格视图：高效批量编辑\n• 向量视图：语义检索可视化'),
                _buildTutorialStep(
                    '3. 角色隔离', '当前记忆库已自动绑定至当前角色。切换角色会自动加载对应的记忆书。'),
                _buildTutorialStep(
                    '4. 向量检索', '开启向量插件后，系统会自动计算记忆条目的相关性，并在聊天时动态注入高相关内容。'),
                _buildTutorialStep('5. 拖拽排序', '在图标视图中，长按卡片可进行拖拽排序，调整注入优先级。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我学会了')),
        ],
      ),
    );
  }

  Widget _buildTutorialStep(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 4),
          Text(content,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

class _EntryEditDialog extends StatefulWidget {
  final WorldInfoEntry entry;
  final Function(WorldInfoEntry) onSave;

  const _EntryEditDialog({required this.entry, required this.onSave});

  @override
  State<_EntryEditDialog> createState() => _EntryEditDialogState();
}

class _EntryEditDialogState extends State<_EntryEditDialog> {
  late TextEditingController _commentCtrl;
  late TextEditingController _keysCtrl;
  late TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController(text: widget.entry.comment);
    _keysCtrl = TextEditingController(text: widget.entry.keys.join(', '));
    _contentCtrl = TextEditingController(text: widget.entry.content);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _keysCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF24283b),
      title: const Text('编辑记忆', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _commentCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: '名称/注释',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keysCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: '关键词 (逗号分隔)',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: '内容',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24))),
              maxLines: 8,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: () {
            final newEntry = widget.entry.copyWith(
              keys: _keysCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),
              comment: _commentCtrl.text,
              content: _contentCtrl.text,
            );
            widget.onSave(newEntry);
            Navigator.pop(context);
          },
          child: const Text('保存', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
