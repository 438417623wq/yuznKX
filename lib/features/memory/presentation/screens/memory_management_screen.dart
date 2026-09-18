import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/session_provider.dart';
import '../../../settings/domain/plugin_settings_provider.dart';
import '../../data/memory_provider.dart';
import '../../domain/models/memory_table.dart';
import '../memory_theme.dart';
import '../widgets/memory_injection_preview.dart';
import 'memory_settings_screen.dart';
import 'workspace/memory_linking.dart';

part 'workspace/memory_shell_extension.dart';
part 'workspace/memory_table_nav_extension.dart';
part 'workspace/memory_record_list_extension.dart';
part 'workspace/memory_detail_panel_extension.dart';
part 'workspace/memory_table_grid_extension.dart';
part 'workspace/memory_dialogs_extension.dart';

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

  int _activeTabIndex = 0;

  /// 右栏详情面板当前展示的记录。`null` 时面板显示表级概览。
  ///
  /// 这是与 [_activeTabIndex] 并列的**第二个联动状态源**：
  /// 表导航 / 记录流 / 详情面板三者都读它，改动它即完成一次联动。
  String? _selectedRowId;

  final Map<String, String> _searchTextByTable = {};
  final Map<String, ScrollController> _verticalControllers = {};
  final Map<String, ScrollController> _horizontalControllers = {};

  /// 各表的记录流滚动位置。切表不跳页，所以必须自己记住位置，
  /// 否则每次切回来都会回到顶部。
  final Map<String, ScrollController> _recordControllers = {};

  /// 「字段折叠」展开的记录 ID 集合（卡片视图）。
  final Set<String> _expandedRowIds = {};

  /// 「长文本展开」的字段集合，键为 `rowId::columnKey`（卡片视图）。
  final Set<String> _expandedFieldKeys = {};

  /// 卡片视图里默认最多显示的字段数，超过则折叠。
  static const int _maxVisibleFields = 5;

  /// 卡片列表 / 表格 两种展示形态，默认卡片（更适合手机）。
  static const String _viewModeKey = 'memory_view_mode';

  /// 三栏并排的最小宽度。窄于此值改用「顶部分段 + 上下分栏」形态。
  ///
  /// 取 720 而非 900：常见平板（600~800dp）与手机横屏应能享受三栏，
  /// 只有手机竖屏（约 360~430dp）才回落到上下分栏。
  static const double _wideBreakpoint = 720;

  /// 窄屏下详情面板占工作区高度的比例，可由用户拖动调整。
  double _narrowDetailRatio = 0.42;

  /// 指向「当前选中记录」的卡片，供跳转后 `ensureVisible` 精确滚动定位。
  /// 只挂在选中那一张卡上，因此不会出现同一 GlobalKey 被多处复用。
  final GlobalKey _selectedRowKey = GlobalKey();

  /// 字段类型下拉框的合法取值。导入的模板可能带任意 `type`，
  /// 喂给 DropdownButtonFormField 前必须先归一化（否则 release 白屏）。
  static const List<String> _supportedColumnTypes = [
    'text',
    'number',
    'boolean',
    'datetime',
  ];

  @override
  void dispose() {
    for (final controller in _verticalControllers.values) {
      controller.dispose();
    }
    for (final controller in _horizontalControllers.values) {
      controller.dispose();
    }
    for (final controller in _recordControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(memoryProvider);
    final plugins = ref.watch(pluginSettingsProvider);
    final viewMode = plugins[_viewModeKey] == 'table' ? 'table' : 'card';

    // 记忆归属当前会话。这里把会话名算出来展示在顶栏，
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

    final hasActiveTable = tables.isNotEmpty &&
        _activeTabIndex >= 0 &&
        _activeTabIndex < tables.length;
    final activeTable = hasActiveTable ? tables[_activeTabIndex] : null;

    return Scaffold(
      appBar: _buildAppBar(tables, activeTable, activeSessionName),
      // 单色背景（与全局 0xFF1A1B26 同族），层次靠 panel/surface 划分，
      // 不再用多段渐变叠加。
      backgroundColor: MemoryTheme.bg,
      body: tables.isEmpty
          ? _buildEmptyWorkspace(activeSessionName)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _wideBreakpoint;
                return isWide
                    ? _buildWideWorkspace(tables, viewMode)
                    : _buildNarrowWorkspace(tables, viewMode);
              },
            ),
    );
  }

  // ---------------------------------------------------------------------
  // 联动：选中态
  // ---------------------------------------------------------------------

  /// 切换当前表。切表后清空记录选中态，避免详情面板「停留在上一张表的记录」。
  void _selectTable(List<MemoryTable> tables, int index) {
    if (index < 0 || index >= tables.length) {
      return;
    }
    if (_activeTabIndex == index) {
      return;
    }
    setState(() {
      _activeTabIndex = index;
      _selectedRowId = null;
    });
  }

  /// 选中某条记录。
  ///
  /// ⚠️ 这里是**幂等**的：重复点击同一条记录保持选中，不做「再点一次取消」。
  /// 早期实现写成 toggle，导致「点一下出现详情、再点一下详情消失」，
  /// 用户会当成 bug（想查看却把它关掉了）。取消选中只走详情面板的关闭按钮。
  void _selectRow(String? rowId) {
    if (rowId == null) {
      setState(() => _selectedRowId = null);
      return;
    }
    if (_selectedRowId == rowId) {
      return;
    }
    setState(() => _selectedRowId = rowId);
  }

  /// 从详情面板的「关联记录」跳到另一张表的某条记录。
  ///
  /// 这是「双向跳转」的入口：把 [_activeTabIndex] 与 [_selectedRowId]
  /// 同时改写，三栏会一起刷新到目标位置，并把中栏滚动到该条记录。
  void _jumpToRecord(
    List<MemoryTable> tables,
    MemoryLinkTarget target,
  ) {
    final index =
        tables.indexWhere((table) => table.id == target.tableId);
    if (index < 0) {
      _showSnack('关联的记录所在表格已被删除');
      return;
    }
    final targetTable = tables[index];
    setState(() {
      _activeTabIndex = index;
      _selectedRowId = target.rowId;
    });
    // 跳转后把中栏滚到目标记录 —— 否则用户只看到右栏变了，
    // 中栏还停在原来的滚动位置，会以为「跳转没生效」。
    _revealRow(targetTable, target.rowId);
  }

  /// 把中栏记录流滚动到指定记录。
  ///
  /// 卡片高度不固定，无法精确算偏移，所以两步走：
  /// 先按行序号做**粗定位**（保证目标大致进入视口），
  /// 再用 [_selectedRowKey] 做 `ensureVisible` **精调**。
  void _revealRow(MemoryTable table, String rowId) {
    // 卡片视图用记录流控制器；表格视图用 DataTable 的纵向控制器。
    final controller =
        _recordControllers[table.id] ?? _verticalControllers[table.id];
    final index = table.rows.indexWhere((row) => row.id == rowId);
    if (index < 0) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (controller != null && controller.hasClients) {
        final max = controller.position.maxScrollExtent;
        if (max > 0 && table.rows.length > 1) {
          final rough = max * (index / (table.rows.length - 1));
          controller.jumpTo(rough.clamp(0.0, max));
        }
      }
      final ctx = _selectedRowKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  /// 该表下当前选中的记录（若选中项不属于该表则返回 null）。
  MemoryRow? _selectedRowOf(MemoryTable table) {
    final id = _selectedRowId;
    if (id == null) {
      return null;
    }
    for (final row in table.rows) {
      if (row.id == id) {
        return row;
      }
    }
    return null;
  }
}
