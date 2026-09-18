part of '../memory_management_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 页面骨架：顶栏、宽屏三栏、窄屏分段 + 选中详情、空态。
extension _MemoryShellExtension on _MemoryManagementScreenState {
  // ---------------------------------------------------------------------
  // 顶栏
  // ---------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(
    List<MemoryTable> tables,
    MemoryTable? activeTable,
    String activeSessionName,
  ) {
    return AppBar(
      // 双行标题（标题 + 当前对话）需要比默认 56 更高的工具栏。
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('记忆'),
          // 记忆是**会话级**的，标明当前属于哪条对话。
          Text(
            activeSessionName.isEmpty ? '未选择对话' : '当前对话：$activeSessionName',
            style: const TextStyle(fontSize: MemoryTheme.fontTiny, color: Colors.white60),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      backgroundColor: MemoryTheme.appBar,
      actions: [
        if (activeTable != null)
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert),
            color: MemoryTheme.surfaceElevated,
            onSelected: (value) {
              switch (value) {
                case 'memory_settings':
                  _openMemorySettings();
                case 'injection_preview':
                  showMemoryInjectionPreview(context, ref);
                case 'add_table':
                  _showAddTableDialog();
                case 'table_settings':
                  _showTableSettingsDialog(activeTable);
                case 'columns':
                  _showColumnManagerDialog(activeTable);
                case 'style':
                  _showTableStyleDialog(activeTable);
                case 'reorder_tables':
                  _showTableReorderDialog(tables);
                case 'clear_rows':
                  _confirmClearRows(activeTable);
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
              // 分组标题 + 危险区隔离：13 项平铺时用户找不到功能，
              // 也容易在「导出」旁边误触「删除表格」。
              _buildMenuHeader('会话记忆'),
              _buildMenuItem('memory_settings', Icons.tune, '记忆设置'),
              _buildMenuItem(
                  'injection_preview', Icons.visibility_outlined, '预览注入内容'),
              _buildMenuItem('add_table', Icons.add_box_outlined, '新建表格'),
              _buildMenuHeader('当前表格'),
              _buildMenuItem(
                  'table_settings', Icons.settings_outlined, '表格设置'),
              _buildMenuItem('columns', Icons.view_column_outlined, '管理字段'),
              _buildMenuItem('style', Icons.palette_outlined, '表格样式'),
              _buildMenuItem(
                  'reorder_tables', Icons.swap_vert, '调整表格顺序'),
              _buildMenuHeader('数据'),
              _buildMenuItem('import', Icons.upload_file_outlined, '导入模板 JSON'),
              _buildMenuItem('export', Icons.download_outlined, '导出模板 JSON'),
              _buildMenuHeader('危险区'),
              _buildMenuItem('clear_rows', Icons.cleaning_services_outlined,
                  '清空当前表格记录',
                  danger: true),
              _buildMenuItem('delete_table', Icons.delete_outline, '删除当前表格',
                  danger: true),
              _buildMenuItem('reset', Icons.restore, '重置为默认模板', danger: true),
            ],
          )
        else
          IconButton(
            tooltip: '记忆设置',
            icon: const Icon(Icons.tune),
            onPressed: _openMemorySettings,
          ),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuHeader(String label) {
    return PopupMenuItem<String>(
      enabled: false,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: MemoryTheme.textFaint,
          fontSize: MemoryTheme.fontTiny,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
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
    final color = danger ? MemoryTheme.danger : Colors.white;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: MemoryTheme.fontBody)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 工作区：宽屏 / 窄屏
  // ---------------------------------------------------------------------

  /// 宽屏：左栏表导航 + 中栏记录流 + 右栏常驻详情。
  ///
  /// 三栏同屏，任意一栏的操作都能被另两栏立刻看见 —— 这就是「界面互通」。
  Widget _buildWideWorkspace(List<MemoryTable> tables, String viewMode) {
    final activeTable = tables[_activeTabIndex];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 188,
          child: _buildTableNavColumn(tables),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: MemoryTheme.divider),
        Expanded(
          child: _buildRecordColumn(activeTable, viewMode, isWide: true),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: MemoryTheme.divider),
        SizedBox(
          width: 300,
          child: _buildDetailPanel(tables, activeTable),
        ),
      ],
    );
  }

  /// 窄屏：顶部表分段 + 记录流；**选中记录后**才在底部展开详情面板。
  ///
  /// 旧版详情面板常驻占 42% 高度，列表永远只剩半屏 —— 手机上「看记录」
  /// 才是主任务，详情应该是「点开某条记录时的临时态」。未选中时列表
  /// 独占整块工作区；选中后面板出现（可用拖动条调高），点面板的 ✕ 收起。
  Widget _buildNarrowWorkspace(List<MemoryTable> tables, String viewMode) {
    final activeTable = tables[_activeTabIndex];
    final hasSelection = _selectedRowOf(activeTable) != null;

    return Column(
      children: [
        _buildTableSegmentBar(tables),
        // 窄屏固定用卡片视图：表格视图的横向滚动 + 行内按钮在
        // 360dp 宽度下基本不可用，表格形态只保留给宽屏。
        Expanded(
          child: _buildRecordColumn(activeTable, 'card', isWide: false),
        ),
        if (hasSelection) ...[
          _buildNarrowResizeHandle(),
          _buildNarrowDetailSheet(tables, activeTable),
        ],
      ],
    );
  }

  /// 窄屏底部详情面板的高度容器。
  ///
  /// 高度按屏幕高度的比例计算（而非 LayoutBuilder 量工作区）——
  /// `Column` 会给非 flex 子项无界高度约束，LayoutBuilder 在这里量不出值。
  Widget _buildNarrowDetailSheet(List<MemoryTable> tables, MemoryTable table) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final detailHeight =
        (screenHeight * _narrowDetailRatio).clamp(180.0, 460.0);
    return SizedBox(
      height: detailHeight,
      child: _buildNarrowDetailPanel(tables, table),
    );
  }

  /// 上下分栏之间的拖动条：按住可调整详情面板高度。
  ///
  /// 用 `onVerticalDragUpdate` 反向累计（手指上移 = 详情变高），
  /// 这样手势方向和面板伸缩方向一致，不会「越拖越反」。
  Widget _buildNarrowResizeHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        if (screenHeight <= 0) {
          return;
        }
        setState(() {
          final next = _narrowDetailRatio - details.delta.dy / screenHeight;
          _narrowDetailRatio = next.clamp(0.15, 0.6);
        });
      },
      child: Container(
        height: 16,
        color: MemoryTheme.panel,
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
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

  // ---------------------------------------------------------------------
  // 空态
  // ---------------------------------------------------------------------

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
                  ? '记忆按对话独立保存，创建表格后即可开始记录。'
                  : '先进入一条对话，记忆才会归属到它。',
              style: const TextStyle(color: Colors.white38, fontSize: MemoryTheme.fontBody),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: hasSession ? _resetToDefault : _openMemorySettings,
              icon: Icon(hasSession ? Icons.add_box_outlined : Icons.tune),
              // 「恢复默认模板」对第一次使用的用户不知所云；这里改成
              // 面向动作的文案。没有会话时引导去设置页。
              label: Text(hasSession ? '创建默认记忆表格' : '去查看记忆设置'),
              style: FilledButton.styleFrom(
                backgroundColor: MemoryTheme.accent,
                foregroundColor: MemoryTheme.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
