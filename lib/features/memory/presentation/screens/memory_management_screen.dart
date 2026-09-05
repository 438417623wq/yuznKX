import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memory_provider.dart';
import '../../domain/models/memory_table.dart';

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
  bool _isPluginSettingsCollapsed = true;
  final Map<String, String> _searchTextByTable = {};
  final Map<String, ScrollController> _verticalControllers = {};
  final Map<String, ScrollController> _horizontalControllers = {};
  final ScrollController _pluginSettingsController = ScrollController();

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
    _pluginSettingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(memoryProvider);
    final settings = ref.watch(memoryPluginSettingsProvider);
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final pluginSettingsMaxHeight =
        (viewportHeight * 0.48).clamp(280.0, 520.0).toDouble();
    _syncTabController(tables.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理插件 (Memory)'),
        backgroundColor: const Color(0xFF0E1A21),
        actions: [
          IconButton(
            tooltip: '导入模板 JSON',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _showImportDialog,
          ),
          IconButton(
            tooltip: '导出模板 JSON',
            icon: const Icon(Icons.download_outlined),
            onPressed: _showExportDialog,
          ),
          IconButton(
            tooltip: '新建表格',
            icon: const Icon(Icons.table_view),
            onPressed: _showAddTableDialog,
          ),
          IconButton(
            tooltip: '重置默认模板',
            icon: const Icon(Icons.restore),
            onPressed: _resetToDefault,
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
            ? _buildEmptyWorkspace()
            : Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: pluginSettingsMaxHeight),
                      child: _buildPluginSettingsCard(settings),
                    ),
                  ),
                  Material(
                    color: const Color(0x33000000),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorColor: const Color(0xFF24C3B5),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      dividerColor: Colors.white12,
                      tabs: tables
                          .map(
                            (table) => Tab(
                              text: table.name,
                              icon: table.behavior.required
                                  ? const Icon(Icons.star, size: 14)
                                  : null,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: tables
                          .map((table) => _buildTableWorkspace(table))
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyWorkspace() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_motion_outlined,
                size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              '当前角色还没有可用记忆表格',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(memoryProvider.notifier).resetToDefault(),
              icon: const Icon(Icons.restore),
              label: const Text('加载默认模板'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginSettingsCard(MemoryPluginSettings settings) {
    final pluginEnabled = settings.isPluginEnabled;
    if (_isPluginSettingsCollapsed) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x3324C3B5)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x221CC8BA), Color(0x22103D57)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.extension, size: 18, color: Color(0xFF78E8DD)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '插件级设置 (已折叠)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '展开插件级设置',
              onPressed: () => setState(
                () => _isPluginSettingsCollapsed = false,
              ),
              icon: const Icon(Icons.unfold_more, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x3324C3B5)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x221CC8BA), Color(0x22103D57)],
        ),
      ),
      child: Scrollbar(
        controller: _pluginSettingsController,
        thumbVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _pluginSettingsController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.extension,
                      size: 18, color: Color(0xFF78E8DD)),
                  const SizedBox(width: 8),
                  const Text(
                    '插件级设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '折叠插件级设置',
                    onPressed: () => setState(
                      () => _isPluginSettingsCollapsed = true,
                    ),
                    icon: const Icon(Icons.unfold_less, color: Colors.white70),
                  ),
                  TextButton.icon(
                    onPressed: _showMessageTemplateDialog,
                    icon: const Icon(Icons.edit_note_outlined, size: 16),
                    label: const Text('编辑提示词模板'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用记忆插件总开关',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '关闭后将禁用记忆读取、记忆回写与聊天记录范围限制。',
                  style: TextStyle(color: Colors.white60),
                ),
                value: settings.isPluginEnabled,
                activeColor: const Color(0xFF24C3B5),
                onChanged: (value) => ref
                    .read(memoryPluginSettingsProvider.notifier)
                    .patch(isPluginEnabled: value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    selected: settings.isAiReadTable,
                    label: const Text('AI 读取记忆表格'),
                    onSelected: pluginEnabled
                        ? (value) => ref
                            .read(memoryPluginSettingsProvider.notifier)
                            .patch(isAiReadTable: value)
                        : null,
                  ),
                  FilterChip(
                    selected: settings.isAiWriteTable,
                    label: const Text('AI 回写记忆'),
                    onSelected: pluginEnabled
                        ? (value) => ref
                            .read(memoryPluginSettingsProvider.notifier)
                            .patch(isAiWriteTable: value)
                        : null,
                  ),
                  FilterChip(
                    selected: settings.confirmBeforeExecution,
                    label: const Text('写入前确认'),
                    onSelected: pluginEnabled
                        ? (value) => ref
                            .read(memoryPluginSettingsProvider.notifier)
                            .patch(confirmBeforeExecution: value)
                        : null,
                  ),
                  FilterChip(
                    selected: settings.useTokenLimit,
                    label: const Text('启用 Token 限制'),
                    onSelected: pluginEnabled
                        ? (value) => ref
                            .read(memoryPluginSettingsProvider.notifier)
                            .patch(useTokenLimit: value)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: settings.injectionMode,
                      decoration: _fieldDecoration('注入模式'),
                      dropdownColor: const Color(0xFF16242C),
                      items: const [
                        DropdownMenuItem(
                            value: 'deep_system', child: Text('deep_system')),
                        DropdownMenuItem(
                            value: 'system', child: Text('system')),
                        DropdownMenuItem(value: 'none', child: Text('none')),
                      ],
                      onChanged: pluginEnabled
                          ? (value) {
                              if (value != null) {
                                ref
                                    .read(memoryPluginSettingsProvider.notifier)
                                    .patch(injectionMode: value);
                              }
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '注入深度: ${settings.deep}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Slider(
                          min: 0,
                          max: 12,
                          value:
                              settings.deep.toDouble().clamp(0, 12).toDouble(),
                          activeColor: const Color(0xFF24C3B5),
                          inactiveColor: Colors.white24,
                          onChanged: pluginEnabled
                              ? (value) => ref
                                  .read(memoryPluginSettingsProvider.notifier)
                                  .patch(deep: value.round())
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildHistoryVisibilityCard(settings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryVisibilityCard(MemoryPluginSettings settings) {
    final canEditRange =
        settings.isPluginEnabled && settings.isHistoryRangeLimitEnabled;
    final keepLatestEnabled = settings.isKeepLatestEnabled;
    final canEditKeepLatest = settings.isPluginEnabled && keepLatestEnabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
        color: const Color(0x22000000),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '聊天记录可见性',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '启用聊天记录范围限制',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'AI 将仅看到指定范围内的历史记录。',
              style: TextStyle(color: Colors.white60),
            ),
            value: settings.isHistoryRangeLimitEnabled,
            activeColor: const Color(0xFF24C3B5),
            onChanged: settings.isPluginEnabled
                ? (value) => ref
                    .read(memoryPluginSettingsProvider.notifier)
                    .patch(isHistoryRangeLimitEnabled: value)
                : null,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                      'start_floor_${settings.historyRangeStartFloor}_${settings.isHistoryRangeLimitEnabled}_${settings.isPluginEnabled}'),
                  initialValue: settings.historyRangeStartFloor.toString(),
                  enabled: canEditRange,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('起始楼层（从 #0 开始）'),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null ||
                        parsed == settings.historyRangeStartFloor) {
                      return;
                    }
                    ref
                        .read(memoryPluginSettingsProvider.notifier)
                        .patch(historyRangeStartFloor: parsed);
                  },
                  onFieldSubmitted: (value) {
                    if (value.trim().isNotEmpty &&
                        int.tryParse(value.trim()) == null) {
                      _showSnack('楼层必须是整数');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                      'end_floor_${settings.historyRangeEndFloor}_${settings.isHistoryRangeLimitEnabled}_${settings.isPluginEnabled}'),
                  initialValue: settings.historyRangeEndFloor.toString(),
                  enabled: canEditRange,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('结束楼层 (-1 表示最新)'),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null ||
                        parsed == settings.historyRangeEndFloor) {
                      return;
                    }
                    ref
                        .read(memoryPluginSettingsProvider.notifier)
                        .patch(historyRangeEndFloor: parsed);
                  },
                  onFieldSubmitted: (value) {
                    if (value.trim().isNotEmpty &&
                        int.tryParse(value.trim()) == null) {
                      _showSnack('楼层必须是整数');
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '聊天消息楼层从 #0 开始，#1、#2 递增，-1 表示最新。当前用户消息始终会被包含在可见范围内。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Text(
            '保留最新的 N 条消息，并隐藏其余旧楼层',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '启用保留楼层',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              '开启后仅保留最近 N 条消息，其余楼层对 AI 不可见。',
              style: TextStyle(color: Colors.white60),
            ),
            value: keepLatestEnabled,
            activeColor: const Color(0xFF24C3B5),
            onChanged: settings.isPluginEnabled
                ? (value) => ref
                    .read(memoryPluginSettingsProvider.notifier)
                    .patch(isKeepLatestEnabled: value)
                : null,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                      'keep_latest_${settings.keepLatestFloors}_${settings.isKeepLatestEnabled}_${settings.isPluginEnabled}'),
                  initialValue: settings.keepLatestFloors.toString(),
                  enabled: canEditKeepLatest,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: false),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d*')),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration('保留最新 N 条'),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return;
                    }
                    if (parsed == settings.keepLatestFloors) {
                      return;
                    }
                    ref
                        .read(memoryPluginSettingsProvider.notifier)
                        .patch(keepLatestFloors: parsed);
                  },
                  onFieldSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      _showSnack('楼层必须是正整数');
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                children: [
                  const TextSpan(text: '当前保留最近 '),
                  TextSpan(
                    text: '${settings.keepLatestFloors}',
                    style: const TextStyle(
                        color: Color(0xFFB8F4EE), fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' 条聊天楼层。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableWorkspace(MemoryTable table) {
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          _buildTableToolbar(table, filteredRows.length),
          const SizedBox(height: 10),
          Expanded(child: _buildTableGrid(table, filteredRows)),
        ],
      ),
    );
  }

  Widget _buildTableToolbar(MemoryTable table, int filteredCount) {
    final toolbarController = _horizontalController('toolbar_${table.id}');
    return Scrollbar(
      controller: toolbarController,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: toolbarController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('搜索记录（全列）').copyWith(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: (_searchTextByTable[table.id] ?? '').isNotEmpty
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
            ),
            const SizedBox(width: 10),
            _buildStatusPill(
              icon: Icons.format_list_bulleted,
              label: '记录 ${table.rows.length}',
            ),
            const SizedBox(width: 10),
            _buildStatusPill(
              icon: Icons.filter_alt_outlined,
              label: '筛选 $filteredCount',
            ),
            const SizedBox(width: 10),
            _buildStatusPill(
              icon: table.isEnabled ? Icons.check_circle : Icons.remove_circle,
              label: table.isEnabled ? '已启用' : '已停用',
              color: table.isEnabled
                  ? const Color(0xFF4ED8A8)
                  : Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _showTableSettingsDialog(table),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('表格设置'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _showTableStyleDialog(table),
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('样式'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _showColumnManagerDialog(table),
              icon: const Icon(Icons.view_column, size: 16),
              label: const Text('字段'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => _confirmDeleteTable(table),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('删除表格'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _showRowEditorDialog(table),
              icon: const Icon(Icons.add),
              label: const Text('新增记录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    Color color = const Color(0xFF9FBCD1),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x33FFFFFF)),
        color: const Color(0x22000000),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTableGrid(MemoryTable table, List<MemoryRow> rows) {
    final style = table.style;
    final accentColor = _hexColor(style.accentColor, const Color(0xFF24C3B5));
    final headerColor = _hexColor(style.headerColor, const Color(0xFF162831));
    final rowColor = _hexColor(style.rowColor, const Color(0xFF0E151A));
    final altRowColor =
        _hexColor(style.alternateRowColor, const Color(0xFF111E24));

    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.table_rows_outlined,
                size: 52, color: Colors.white24),
            const SizedBox(height: 10),
            const Text('没有符合条件的记录', style: TextStyle(color: Colors.white54)),
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
                                  onPressed: () => ref
                                      .read(memoryProvider.notifier)
                                      .deleteRow(table.id, row.id),
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

  Future<void> _showMessageTemplateDialog() async {
    final settings = ref.read(memoryPluginSettingsProvider);
    final ctrl = TextEditingController(text: settings.messageTemplate);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132028),
        title: const Text('编辑 message_template',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 720,
          child: TextField(
            controller: ctrl,
            maxLines: 18,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('用于注入给模型的记忆提示词模板'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              ref
                  .read(memoryPluginSettingsProvider.notifier)
                  .patch(messageTemplate: ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
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
