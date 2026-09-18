import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/session_provider.dart';
import '../../../settings/domain/plugin_settings_provider.dart';
import '../../data/memory_provider.dart';
import '../../domain/models/memory_table.dart';
import 'memory_settings_screen.dart';

class MemoryManagementScreen extends ConsumerStatefulWidget {
  const MemoryManagementScreen({super.key});

  @override
  ConsumerState<MemoryManagementScreen> createState() =>
      _MemoryManagementScreenState();
}

class _MemoryManagementScreenState extends ConsumerState<MemoryManagementScreen>
    with TickerProviderStateMixin {
  static const List<String> _presetColors = [
    '#24C3B5',
    '#3BA6FF',
    '#56D17B',
    '#FFC857',
    '#FF8C69',
    '#E383FF',
    '#A0B5FF',
    '#73859E',
  ];

  TabController? _tabController;
  int _activeTabIndex = 0;
  final Map<String, String> _searchTextByTable = {};
  final Map<String, ScrollController> _verticalControllers = {};
  final Map<String, ScrollController> _horizontalControllers = {};

  /// 卡片列表 / 表格 两种展示形态，默认卡片（更适合手机）。
  static const String _viewModeKey = 'memory_view_mode';

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabIndexChanged);
    _tabController?.dispose();
    for (final controller in _verticalControllers.values) {
      controller.dispose();
    }
    for (final controller in _horizontalControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(memoryProvider);
    final plugins = ref.watch(pluginSettingsProvider);
    final viewMode = plugins[_viewModeKey] == 'table' ? 'table' : 'card';

    // 记忆归属当前会话。这里把会话名算出来展示在 AppBar，
    // 避免用户把「切换对话后记忆变了」误判成数据丢失。
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final sessions = ref.watch(sessionProvider);
    var activeSessionName = '';
    if (activeSessionId != null) {
      for (final session in sessions) {
        if (session.id == activeSessionId) {
          activeSessionName = session.name;
          break;
        }
      }
    }

    _syncTabController(tables.length);

    final hasActiveTable = tables.isNotEmpty &&
        _activeTabIndex >= 0 &&
        _activeTabIndex < tables.length;
    final activeTable = hasActiveTable ? tables[_activeTabIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('记忆'),
            // 记忆是**会话级**的，标明当前属于哪条对话。
            Text(
              activeSessionName.isEmpty ? '未选择对话' : '当前对话：$activeSessionName',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0E1A21),
        actions: [
          if (activeTable != null)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert),
              color: const Color(0xFF16242C),
              onSelected: (value) {
                switch (value) {
                  case 'memory_settings':
                    _openMemorySettings();
                  case 'add_table':
                    _showAddTableDialog();
                  case 'table_settings':
                    _showTableSettingsDialog(activeTable);
                  case 'columns':
                    _showColumnManagerDialog(activeTable);
                  case 'style':
                    _showTableStyleDialog(activeTable);
                  case 'import':
                    _showImportDialog();
                  case 'export':
                    _showExportDialog();
                  case 'delete_table':
                    _confirmDeleteTable(activeTable);
                  case 'reset':
                    _resetToDefault();
                }
              },
              itemBuilder: (context) => [
                _buildMenuItem('memory_settings', Icons.tune, '记忆设置'),
                const PopupMenuDivider(),
                _buildMenuItem('add_table', Icons.add_box_outlined, '新建表格'),
                _buildMenuItem(
                    'table_settings', Icons.settings_outlined, '当前表格设置'),
                _buildMenuItem('columns', Icons.view_column_outlined, '管理字段'),
                _buildMenuItem('style', Icons.palette_outlined, '表格样式'),
                const PopupMenuDivider(),
                _buildMenuItem(
                    'import', Icons.upload_file_outlined, '导入模板 JSON'),
                _buildMenuItem(
                    'export', Icons.download_outlined, '导出模板 JSON'),
                const PopupMenuDivider(),
                _buildMenuItem(
                    'delete_table', Icons.delete_outline, '删除当前表格',
                    danger: true),
                _buildMenuItem('reset', Icons.restore, '重置为默认模板'),
              ],
            )
          else
            IconButton(
              tooltip: '记忆设置',
              icon: const Icon(Icons.tune),
              onPressed: _openMemorySettings,
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF081015),
              Color(0xFF0D1820),
              Color(0xFF0A131A),
            ],
          ),
        ),
        child: tables.isEmpty
            ? _buildEmptyWorkspace(activeSessionName)
            : Column(
                children: [
                  _buildTableChips(tables),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: tables
                          .map((table) => _buildTableWorkspace(table, viewMode))
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF8A8A) : Colors.white;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  /// 表格切换条：横向滚动的 chips，替代原先的 TabBar（去掉语义不明的 ★）。
  Widget _buildTableChips(List<MemoryTable> tables) {
    return Container(
      color: const Color(0x33000000),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tables.asMap().entries.map((entry) {
            final index = entry.key;
            final table = entry.value;
            final selected = index == _activeTabIndex;
            return Padding(
              padding: EdgeInsets.only(
                  right: index == tables.length - 1 ? 0 : 8),
              child: ChoiceChip(
                selected: selected,
                label: Text(
                  table.isEnabled ? table.name : '${table.name}（已停用）',
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? const Color(0xFF04211D) : Colors.white70,
                  ),
                ),
                onSelected: (_) {
                  _tabController?.animateTo(index);
                  if (_activeTabIndex != index) {
                    setState(() => _activeTabIndex = index);
                  }
                },
                selectedColor: const Color(0xFF24C3B5),
                backgroundColor: const Color(0x22FFFFFF),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF24C3B5)
                      : const Color(0x33FFFFFF),
                ),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _openMemorySettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemorySettingsScreen()),
    );
  }

  Widget _buildEmptyWorkspace(String activeSessionName) {
    final hasSession = activeSessionName.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_motion_outlined,
                size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              hasSession ? '「$activeSessionName」还没有记忆表格' : '未选择对话',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasSession
                  ? '记忆表格按对话独立保存，可在这里加载默认模板。'
                  : '请先到聊天页选择一个角色或对话。',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (hasSession) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(memoryProvider.notifier).resetToDefault(),
                icon: const Icon(Icons.restore),
                label: const Text('加载默认模板'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableWorkspace(MemoryTable table, String viewMode) {
    final query = (_searchTextByTable[table.id] ?? '').trim().toLowerCase();
    final filteredRows = table.rows.where((row) {
      if (query.isEmpty) {
        return true;
      }
      return table.columns.any((column) {
        final value = (row.data[column.key] ?? '').toString().toLowerCase();
        return value.contains(query);
      });
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          _buildTableToolbar(table, filteredRows.length, viewMode),
          const SizedBox(height: 10),
          Expanded(
            child: viewMode == 'table'
                ? _buildTableGrid(table, filteredRows)
                : _buildCardList(table, filteredRows),
          ),
        ],
      ),
    );
  }

  /// 移动端工具栏：两行、不横向滚动。
  /// 第一行搜索占满宽度；第二行是统计 + 视图切换 + 新增。
  /// 其余操作（表格设置 / 样式 / 字段 / 删除表格 / 导入导出）都在右上角 ⋮ 菜单里。
  Widget _buildTableToolbar(
    MemoryTable table,
    int filteredCount,
    String viewMode,
  ) {
    final query = _searchTextByTable[table.id] ?? '';
    final stateLabel = table.isEnabled ? '已启用' : '已停用';
    final statusText = table.rows.length == filteredCount
        ? '${table.rows.length} 条 · $stateLabel'
        : '$filteredCount / ${table.rows.length} 条 · $stateLabel';

    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _fieldDecoration('搜索记录（全列）').copyWith(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    onPressed: () =>
                        setState(() => _searchTextByTable[table.id] = ''),
                    icon: const Icon(Icons.clear, size: 16),
                  )
                : null,
          ),
          onChanged: (value) =>
              setState(() => _searchTextByTable[table.id] = value),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9FBCD1),
                  fontSize: 12,
                ),
              ),
            ),
            _buildViewModeToggle(viewMode),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showRowEditorDialog(table),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF24C3B5),
                foregroundColor: const Color(0xFF04211D),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 卡片 / 表格 视图切换开关，状态持久化在 pluginSettingsProvider。
  Widget _buildViewModeToggle(String viewMode) {
    final isCard = viewMode != 'table';
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: true,
          icon: Icon(Icons.view_agenda_outlined, size: 16),
          tooltip: '卡片列表',
        ),
        ButtonSegment(
          value: false,
          icon: Icon(Icons.table_chart_outlined, size: 16),
          tooltip: '表格',
        ),
      ],
      selected: {isCard},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        ref
            .read(pluginSettingsProvider.notifier)
            .setString(_viewModeKey, selection.first ? 'card' : 'table');
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF24C3B5);
          }
          return const Color(0x22FFFFFF);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF04211D);
          }
          return Colors.white70;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0x33FFFFFF)),
        ),
      ),
    );
  }

  /// 卡片列表视图：每条记录一张卡，字段竖排，操作图标固定在卡内。
  /// 空值字段灰显而不隐藏，保持字段结构可预期。
  Widget _buildCardList(MemoryTable table, List<MemoryRow> rows) {
    if (rows.isEmpty) {
      return _buildEmptyRows(table);
    }

    final style = table.style;
    final accentColor = _hexColor(style.accentColor, const Color(0xFF24C3B5));
    final rowColor = _hexColor(style.rowColor, const Color(0xFF0E151A));
    final primaryColumn = table.columns.isNotEmpty ? table.columns.first : null;

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final title = primaryColumn == null
            ? ''
            : (row.data[primaryColumn.key] ?? '').toString().trim();
        final others = table.columns
            .where((column) => column.key != primaryColumn?.key)
            .toList();

        return Container(
          decoration: BoxDecoration(
            color: row.isEnabled
                ? rowColor.withOpacity(0.85)
                : const Color(0x66000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  row.isEnabled ? accentColor.withOpacity(0.35) : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? '（未命名记录）' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              row.isEnabled ? Colors.white : Colors.white38,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: row.isEnabled ? '停用' : '启用',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        row.isEnabled
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 18,
                        color: row.isEnabled
                            ? const Color(0xFF8AEBC6)
                            : Colors.white54,
                      ),
                      onPressed: () => ref
                          .read(memoryProvider.notifier)
                          .toggleRow(table.id, row.id, !row.isEnabled),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit,
                          size: 18, color: Color(0xFF79BEFF)),
                      onPressed: () => _showRowEditorDialog(table, row: row),
                    ),
                    IconButton(
                      tooltip: '删除',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFFF8A8A)),
                      onPressed: () =>
                          _confirmDeleteRow(table, row, title: title),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x1AFFFFFF)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: others.map((column) {
                    final raw = (row.data[column.key] ?? '').toString().trim();
                    final isEmpty = raw.isEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, height: 1.5),
                          children: [
                            TextSpan(
                              text: '${column.label}  ',
                              style: const TextStyle(
                                color: Color(0xFF7F93A6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: isEmpty ? '未填写' : raw,
                              style: TextStyle(
                                color: isEmpty
                                    ? const Color(0xFF5A6B7A)
                                    : Colors.white.withOpacity(
                                        row.isEnabled ? 0.92 : 0.4,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyRows(MemoryTable table) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.table_rows_outlined,
              size: 52, color: Colors.white24),
          const SizedBox(height: 10),
          const Text('没有符合条件的记录',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _showRowEditorDialog(table),
            icon: const Icon(Icons.add),
            label: const Text('添加第一条'),
          ),
        ],
      ),
    );
  }

  /// 卡片视图的删除需要二次确认，避免手机上误触丢数据。
  Future<void> _confirmDeleteRow(
    MemoryTable table,
    MemoryRow row, {
    String title = '',
  }) async {
    final label = title.trim().isEmpty ? '这条记录' : '「${title.trim()}」';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('删除记录', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定删除 $label 吗？该操作不可撤销。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    ref.read(memoryProvider.notifier).deleteRow(table.id, row.id);
  }
  Widget _buildTableGrid(MemoryTable table, List<MemoryRow> rows) {
    final style = table.style;
    final accentColor = _hexColor(style.accentColor, const Color(0xFF24C3B5));
    final headerColor = _hexColor(style.headerColor, const Color(0xFF162831));
    final rowColor = _hexColor(style.rowColor, const Color(0xFF0E151A));
    final altRowColor =
        _hexColor(style.alternateRowColor, const Color(0xFF111E24));

    if (rows.isEmpty) {
      return _buildEmptyRows(table);
    }

    final verticalController = _verticalController(table.id);
    final horizontalController = _horizontalController(table.id);

    return Container(
      decoration: BoxDecoration(
        color: rowColor.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: style.bordered
            ? Border.all(color: accentColor.withOpacity(0.35))
            : Border.all(color: Colors.transparent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scrollbar(
          controller: verticalController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: verticalController,
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              controller: horizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              interactive: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dataTableTheme: DataTableThemeData(
                      headingRowColor: WidgetStatePropertyAll(headerColor),
                      headingTextStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: style.compact ? 12 : 13,
                      ),
                      dataTextStyle: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: style.compact ? 12 : 13,
                      ),
                      dividerThickness: style.bordered ? 0.5 : 0,
                      horizontalMargin: style.compact ? 10 : 14,
                      columnSpacing: style.columnSpacing,
                    ),
                  ),
                  child: DataTable(
                    headingRowHeight: style.compact ? 44 : 56,
                    dataRowMinHeight: style.compact ? 44 : style.rowHeight,
                    dataRowMaxHeight: style.compact ? 58 : style.rowHeight + 18,
                    border: style.bordered
                        ? TableBorder.all(color: Colors.white12)
                        : null,
                    columns: [
                      ...table.columns.map(
                        (column) => DataColumn(
                          label: SizedBox(
                            width: column.width,
                            child: Text(column.label),
                          ),
                        ),
                      ),
                      const DataColumn(label: Text('操作')),
                    ],
                    rows: rows.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      final row = entry.value;
                      final rowBg = !row.isEnabled
                          ? Colors.black26
                          : (style.striped && rowIndex.isOdd
                              ? altRowColor
                              : rowColor);

                      return DataRow(
                        color: WidgetStatePropertyAll(rowBg),
                        cells: [
                          ...table.columns.map(
                            (column) => DataCell(
                              SizedBox(
                                width: column.width,
                                child: Text(
                                  (row.data[column.key] ?? '').toString(),
                                  maxLines: style.maxCellLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: row.isEnabled
                                        ? Colors.white.withOpacity(0.92)
                                        : Colors.white38,
                                  ),
                                ),
                              ),
                              onTap: () =>
                                  _showRowEditorDialog(table, row: row),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: row.isEnabled ? '停用' : '启用',
                                  icon: Icon(
                                    row.isEnabled
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: row.isEnabled
                                        ? const Color(0xFF8AEBC6)
                                        : Colors.white54,
                                    size: 18,
                                  ),
                                  onPressed: () => ref
                                      .read(memoryProvider.notifier)
                                      .toggleRow(
                                          table.id, row.id, !row.isEnabled),
                                ),
                                IconButton(
                                  tooltip: '编辑',
                                  icon: const Icon(Icons.edit,
                                      size: 18, color: Color(0xFF79BEFF)),
                                  onPressed: () =>
                                      _showRowEditorDialog(table, row: row),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Color(0xFFFF8A8A)),
                                  onPressed: () => _confirmDeleteRow(
                                    table,
                                    row,
                                    title: (table.columns.isEmpty
                                            ? ''
                                            : (row.data[table.columns.first.key] ??
                                                    '')
                                                .toString())
                                        .trim(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ScrollController _verticalController(String key) {
    return _verticalControllers.putIfAbsent(key, ScrollController.new);
  }

  ScrollController _horizontalController(String key) {
    return _horizontalControllers.putIfAbsent(key, ScrollController.new);
  }

  Future<void> _showRowEditorDialog(MemoryTable table, {MemoryRow? row}) async {
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{};
    final boolValues = <String, bool>{};

    for (final column in table.columns) {
      final rawValue = row?.data[column.key];
      if (column.type == 'boolean') {
        boolValues[column.key] = _asBool(rawValue) ?? false;
      } else {
        controllers[column.key] =
            TextEditingController(text: rawValue?.toString() ?? '');
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: Text(
          row == null ? '新增记录' : '编辑记录',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 640,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: table.columns.map((column) {
                  if (column.type == 'boolean') {
                    return StatefulBuilder(
                      builder: (context, setLocalState) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(column.label,
                            style: const TextStyle(color: Colors.white70)),
                        value: boolValues[column.key] ?? false,
                        onChanged: (value) =>
                            setLocalState(() => boolValues[column.key] = value),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextFormField(
                      controller: controllers[column.key],
                      keyboardType: column.type == 'number'
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      maxLines: column.multiline ? 4 : 1,
                      style: const TextStyle(color: Colors.white),
                      decoration: _fieldDecoration(column.label).copyWith(
                        hintText: column.hint.isEmpty ? null : column.hint,
                      ),
                      validator: (value) {
                        if (!column.required) {
                          return null;
                        }
                        if (value == null || value.trim().isEmpty) {
                          return '${column.label} 不能为空';
                        }
                        return null;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final data = <String, dynamic>{};
              for (final column in table.columns) {
                if (column.type == 'boolean') {
                  data[column.key] = boolValues[column.key] ?? false;
                } else {
                  data[column.key] = controllers[column.key]?.text.trim() ?? '';
                }
              }

              if (row == null) {
                ref.read(memoryProvider.notifier).addRow(table.id, data);
              } else {
                ref
                    .read(memoryProvider.notifier)
                    .updateRow(table.id, row.id, data);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTableSettingsDialog(MemoryTable table) async {
    final nameCtrl = TextEditingController(text: table.name);
    final noteCtrl = TextEditingController(text: table.note);
    var isEnabled = table.isEnabled;
    var behavior = table.behavior;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF132028),
          title: const Text('表格设置', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('表格名称'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: _fieldDecoration('备注说明'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用此表',
                        style: TextStyle(color: Colors.white70)),
                    value: isEnabled,
                    onChanged: (value) =>
                        setLocalState(() => isEnabled = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('必填/核心表',
                        style: TextStyle(color: Colors.white70)),
                    value: behavior.required,
                    onChanged: (value) => setLocalState(
                        () => behavior = behavior.copyWith(required: value)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('参与对话注入',
                        style: TextStyle(color: Colors.white70)),
                    value: behavior.toChat,
                    onChanged: (value) => setLocalState(
                        () => behavior = behavior.copyWith(toChat: value)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('触发即发送',
                        style: TextStyle(color: Colors.white70)),
                    value: behavior.triggerSend,
                    onChanged: (value) => setLocalState(
                        () => behavior = behavior.copyWith(triggerSend: value)),
                  ),
                  Row(
                    children: [
                      Text(
                        '触发发送深度: ${behavior.triggerSendDeep}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 8,
                          value: behavior.triggerSendDeep
                              .toDouble()
                              .clamp(1, 8)
                              .toDouble(),
                          activeColor: const Color(0xFF24C3B5),
                          onChanged: (value) => setLocalState(
                            () => behavior = behavior.copyWith(
                                triggerSendDeep: value.round()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showColumnManagerDialog(table);
                      },
                      icon: const Icon(Icons.view_column),
                      label: const Text('管理字段'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(memoryProvider.notifier).updateTableMeta(
                      tableId: table.id,
                      name: nameCtrl.text.trim().isEmpty
                          ? table.name
                          : nameCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                      isEnabled: isEnabled,
                    );
                ref
                    .read(memoryProvider.notifier)
                    .updateTableBehavior(table.id, behavior);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTableStyleDialog(MemoryTable table) async {
    var style = table.style;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF122028),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '表格样式',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '重点配置视觉密度、配色、行高与列间距。',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilterChip(
                      selected: style.compact,
                      label: const Text('紧凑布局'),
                      onSelected: (value) => setLocalState(
                          () => style = style.copyWith(compact: value)),
                    ),
                    FilterChip(
                      selected: style.striped,
                      label: const Text('斑马纹'),
                      onSelected: (value) => setLocalState(
                          () => style = style.copyWith(striped: value)),
                    ),
                    FilterChip(
                      selected: style.bordered,
                      label: const Text('显示网格线'),
                      onSelected: (value) => setLocalState(
                          () => style = style.copyWith(bordered: value)),
                    ),
                    FilterChip(
                      selected: style.softShadow,
                      label: const Text('柔和阴影'),
                      onSelected: (value) => setLocalState(
                          () => style = style.copyWith(softShadow: value)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildColorPicker(
                  title: '强调色',
                  selected: style.accentColor,
                  onSelect: (value) => setLocalState(
                      () => style = style.copyWith(accentColor: value)),
                ),
                _buildColorPicker(
                  title: '表头底色',
                  selected: style.headerColor,
                  onSelect: (value) => setLocalState(
                      () => style = style.copyWith(headerColor: value)),
                ),
                _buildColorPicker(
                  title: '行底色',
                  selected: style.rowColor,
                  onSelect: (value) => setLocalState(
                      () => style = style.copyWith(rowColor: value)),
                ),
                _buildColorPicker(
                  title: '交替行底色',
                  selected: style.alternateRowColor,
                  onSelect: (value) => setLocalState(
                      () => style = style.copyWith(alternateRowColor: value)),
                ),
                const SizedBox(height: 12),
                Text(
                  '单元格最大行数:${style.maxCellLines}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Slider(
                  min: 1,
                  max: 6,
                  value: style.maxCellLines.toDouble().clamp(1, 6).toDouble(),
                  onChanged: (value) => setLocalState(
                    () => style = style.copyWith(maxCellLines: value.round()),
                  ),
                ),
                Text(
                  '行高: ${style.rowHeight.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Slider(
                  min: 44,
                  max: 84,
                  value: style.rowHeight.clamp(44, 84).toDouble(),
                  onChanged: (value) => setLocalState(
                      () => style = style.copyWith(rowHeight: value)),
                ),
                Text(
                  '列间距: ${style.columnSpacing.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Slider(
                  min: 8,
                  max: 40,
                  value: style.columnSpacing.clamp(8, 40).toDouble(),
                  onChanged: (value) => setLocalState(
                      () => style = style.copyWith(columnSpacing: value)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(memoryProvider.notifier)
                            .updateTableStyle(table.id, style);
                        Navigator.pop(ctx);
                      },
                      child: const Text('应用样式'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker({
    required String title,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetColors.map((hex) {
              final isSelected = hex == selected;
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelect(hex),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hexColor(hex, Colors.teal),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showColumnManagerDialog(MemoryTable table) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final currentTable = ref.watch(memoryProvider).firstWhere(
                (item) => item.id == table.id,
                orElse: () => table,
              );
          final columns = currentTable.columns;

          return AlertDialog(
            backgroundColor: const Color(0xFF132028),
            title: const Text('字段管理', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (columns.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Text('暂无字段，请先添加。',
                            style: TextStyle(color: Colors.white54)),
                      )
                    else
                      ...columns.asMap().entries.map((entry) {
                        final index = entry.key;
                        final column = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(column.label,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            'key=${column.key} | type=${column.type} | width=${column.width.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: '上移',
                                onPressed: index == 0
                                    ? null
                                    : () => ref
                                        .read(memoryProvider.notifier)
                                        .reorderColumns(
                                            currentTable.id, index, index - 1),
                                icon: const Icon(Icons.arrow_upward, size: 16),
                              ),
                              IconButton(
                                tooltip: '下移',
                                onPressed: index == columns.length - 1
                                    ? null
                                    : () => ref
                                        .read(memoryProvider.notifier)
                                        .reorderColumns(
                                            currentTable.id, index, index + 1),
                                icon:
                                    const Icon(Icons.arrow_downward, size: 16),
                              ),
                              IconButton(
                                tooltip: '编辑',
                                onPressed: () => _showColumnEditorDialog(
                                  tableId: currentTable.id,
                                  column: column,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                              ),
                              IconButton(
                                tooltip: '删除',
                                onPressed: () => ref
                                    .read(memoryProvider.notifier)
                                    .deleteColumn(currentTable.id, column.key),
                                icon:
                                    const Icon(Icons.delete_outline, size: 16),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: () =>
                    _showColumnEditorDialog(tableId: currentTable.id),
                icon: const Icon(Icons.add),
                label: const Text('添加字段'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showColumnEditorDialog({
    required String tableId,
    MemoryColumn? column,
  }) async {
    final labelCtrl = TextEditingController(text: column?.label ?? '');
    final keyCtrl = TextEditingController(text: column?.key ?? '');
    final hintCtrl = TextEditingController(text: column?.hint ?? '');
    var type = column?.type ?? 'text';
    var required = column?.required ?? false;
    var multiline = column?.multiline ?? false;
    var width = (column?.width ?? 180).toDouble();
    if (width < 90) {
      width = 90;
    } else if (width > 360) {
      width = 360;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF132028),
          title: Text(
            column == null ? '添加字段' : '编辑字段',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('显示名称'),
                    onChanged: (value) {
                      if (column == null && keyCtrl.text.trim().isEmpty) {
                        keyCtrl.text = _slugKey(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('字段 key（唯一）'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: _fieldDecoration('字段类型'),
                    dropdownColor: const Color(0xFF16242C),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('text')),
                      DropdownMenuItem(value: 'number', child: Text('number')),
                      DropdownMenuItem(
                          value: 'boolean', child: Text('boolean')),
                      DropdownMenuItem(
                          value: 'datetime', child: Text('datetime')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => type = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: hintCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('占位提示（可选）'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('必填字段',
                        style: TextStyle(color: Colors.white70)),
                    value: required,
                    onChanged: (value) => setLocalState(() => required = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('多行输入',
                        style: TextStyle(color: Colors.white70)),
                    value: multiline,
                    onChanged: (value) =>
                        setLocalState(() => multiline = value),
                  ),
                  Row(
                    children: [
                      Text(
                        '列宽: ${width.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          min: 90,
                          max: 360,
                          value: width,
                          activeColor: const Color(0xFF24C3B5),
                          onChanged: (value) =>
                              setLocalState(() => width = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                final key = keyCtrl.text.trim().isEmpty
                    ? _slugKey(labelCtrl.text)
                    : keyCtrl.text.trim();
                if (label.isEmpty || key.isEmpty) {
                  _showSnack('字段名和 key 不能为空');
                  return;
                }

                final newColumn = MemoryColumn(
                  key: key,
                  label: label,
                  type: type,
                  required: required,
                  multiline: multiline,
                  width: width,
                  hint: hintCtrl.text.trim(),
                );

                if (column == null) {
                  ref
                      .read(memoryProvider.notifier)
                      .addColumn(tableId, newColumn);
                } else {
                  ref
                      .read(memoryProvider.notifier)
                      .updateColumn(tableId, column.key, newColumn);
                }
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('导入记忆模板 JSON', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 18,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _fieldDecoration('粘贴示例 JSON 或 st-memory-enhancement 配置'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ctrl.text = _buildDefaultTemplateJson();
                  },
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('填充内置示例模板'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final importedSettings = ref
                  .read(memoryProvider.notifier)
                  .importFromPluginJson(ctrl.text);
              if (importedSettings == null) {
                _showSnack('导入失败：JSON 结构不正确');
                return;
              }
              ref
                  .read(memoryPluginSettingsProvider.notifier)
                  .update(importedSettings);
              _showSnack('模板导入成功');
              Navigator.pop(ctx);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog() async {
    final settings = ref.read(memoryPluginSettingsProvider);
    final rawJson =
        ref.read(memoryProvider.notifier).exportToPluginJson(settings);
    await Clipboard.setData(ClipboardData(text: rawJson));

    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('导出模板 JSON', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 760,
          child: TextField(
            controller: TextEditingController(text: rawJson),
            maxLines: 18,
            readOnly: true,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('已自动复制到剪贴板'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    _showSnack('已复制到剪贴板');
  }

  Future<void> _showAddTableDialog() async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('新建表格', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('表格名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('备注（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(memoryProvider.notifier).addTable(
                    name: nameCtrl.text.trim(),
                    note: noteCtrl.text.trim(),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTable(MemoryTable table) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('删除表格', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定删除该表格吗？该操作不可撤销。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    final indexBeforeDelete =
        ref.read(memoryProvider).indexWhere((item) => item.id == table.id);
    ref.read(memoryProvider.notifier).deleteTable(table.id);
    _searchTextByTable.remove(table.id);

    if (indexBeforeDelete >= 0 &&
        _activeTabIndex >= indexBeforeDelete &&
        _activeTabIndex > 0) {
      setState(() => _activeTabIndex -= 1);
    }
  }

  Future<void> _resetToDefault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('重置模板', style: TextStyle(color: Colors.white)),
        content: const Text(
          '将清空当前记忆表格并恢复为默认模板。是否继续？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    ref.read(memoryProvider.notifier).resetToDefault();
    ref.read(memoryPluginSettingsProvider.notifier).resetToDefault();
    _showSnack('已恢复默认模板');
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0x3320303A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF24C3B5)),
      ),
    );
  }

  void _syncTabController(int length) {
    if (length == 0) {
      _tabController?.removeListener(_handleTabIndexChanged);
      _tabController?.dispose();
      _tabController = null;
      _activeTabIndex = 0;
      return;
    }

    final clamped = _activeTabIndex.clamp(0, length - 1).toInt();
    if (_tabController == null || _tabController!.length != length) {
      _tabController?.removeListener(_handleTabIndexChanged);
      _tabController?.dispose();
      _tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: clamped,
      )..addListener(_handleTabIndexChanged);
      _activeTabIndex = clamped;
      return;
    }
    if (_tabController!.index != clamped) {
      _tabController!.index = clamped;
    }
  }

  void _handleTabIndexChanged() {
    if (_tabController == null || _tabController!.indexIsChanging) {
      return;
    }
    if (_activeTabIndex != _tabController!.index) {
      setState(() => _activeTabIndex = _tabController!.index);
    }
  }

  Color _hexColor(String hex, Color fallback) {
    final normalized = hex.trim().replaceFirst('#', '');
    if (normalized.length != 6) {
      return fallback;
    }
    final colorValue = int.tryParse('FF$normalized', radix: 16);
    if (colorValue == null) {
      return fallback;
    }
    return Color(colorValue);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _slugKey(String raw) {
    final value = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (value.isEmpty) {
      return 'col_${DateTime.now().millisecondsSinceEpoch}';
    }
    return value;
  }

  String _buildDefaultTemplateJson() {
    final bundle = getDefaultMemoryTemplateBundle();
    final payload = {
      ...bundle.settings.toJson(),
      'tableStructure': bundle.tables.map((table) => table.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  bool? _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1') {
        return true;
      }
      if (lower == 'false' || lower == '0') {
        return false;
      }
    }
    return null;
  }
}
