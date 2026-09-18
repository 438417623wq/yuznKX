part of '../memory_management_screen.dart';

/// 表导航栏：宽屏为左栏竖排，窄屏为顶部分段条。
///
/// 每张表只显示：名称 + 记录条数（长按呼出该表的操作面板）。
/// 「填充度」不再出现在导航项里 —— 语义不明还占空间，只保留在
/// 右栏概览中，以「数字 + 进度条」呈现一次。
extension _MemoryTableNavExtension on _MemoryManagementScreenState {
  // ---------------------------------------------------------------------
  // 宽屏：左栏竖排
  // ---------------------------------------------------------------------

  Widget _buildTableNavColumn(List<MemoryTable> tables) {
    final totalRows =
        tables.fold<int>(0, (sum, table) => sum + table.rows.length);

    return Container(
      color: MemoryTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNavHeader(tables.length, totalRows),
          const Divider(height: 1, color: MemoryTheme.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              itemCount: tables.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildNavTile(tables, index),
              ),
            ),
          ),
          const Divider(height: 1, color: MemoryTheme.divider),
          _buildNavFooter(),
        ],
      ),
    );
  }

  Widget _buildNavHeader(int tableCount, int totalRows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 13, color: MemoryTheme.accent),
              SizedBox(width: 6),
              Text(
                '记忆中枢',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MemoryTheme.fontBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$tableCount 张表 · $totalRows 条',
            style: const TextStyle(color: MemoryTheme.textFaint, fontSize: MemoryTheme.fontTiny),
          ),
        ],
      ),
    );
  }

  /// 单张表的导航项：选中态用强调色实底 + 左侧高亮条。
  Widget _buildNavTile(List<MemoryTable> tables, int index) {
    final table = tables[index];
    final selected = index == _activeTabIndex;
    final accent = _hexColor(table.style.accentColor, MemoryTheme.accent);

    return InkWell(
      onTap: () => _selectTable(tables, index),
      // 长按呼出当前表的操作面板（设置 / 字段 / 样式 / 清空 / 删除），
      // 表级操作不必都挤进右上角 ⋮。
      onLongPress: () => _showTableActionsSheet(table),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 9, 8, 9),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.16)
              : MemoryTheme.fillSubtle,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.75) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            // 表级色点：与卡片视图的左侧色带同一语义。
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: table.isEnabled ? accent : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (table.isEnabled ? Colors.white70 : Colors.white38),
                  fontSize: MemoryTheme.fontBody,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  // 停用态删除线，比后缀「（已停用）」更省空间。
                  decoration: table.isEnabled
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
            Text(
              '${table.rows.length}',
              style: TextStyle(
                color: selected ? Colors.white70 : MemoryTheme.textFaint,
                fontSize: MemoryTheme.fontTiny,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: InkWell(
        onTap: _showAddTableDialog,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: MemoryTheme.accent.withValues(alpha: 0.4),
              style: BorderStyle.solid,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 15, color: MemoryTheme.accent),
              SizedBox(width: 5),
              Text(
                '新建表格',
                style: TextStyle(color: MemoryTheme.accent, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 窄屏：顶部分段条
  // ---------------------------------------------------------------------

  /// 单行 chip：名称 + 条数。进度条已移除（见 extension 头注释）。
  Widget _buildTableSegmentBar(List<MemoryTable> tables) {
    return Container(
      color: MemoryTheme.panel,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tables.asMap().entries.map((entry) {
            final index = entry.key;
            final table = entry.value;
            final selected = index == _activeTabIndex;
            final accent = _hexColor(table.style.accentColor, MemoryTheme.accent);

            return Padding(
              padding: EdgeInsets.only(
                  right: index == tables.length - 1 ? 0 : 8),
              child: InkWell(
                onTap: () => _selectTable(tables, index),
                onLongPress: () => _showTableActionsSheet(table),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.2)
                        : MemoryTheme.fillSubtle,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: selected ? accent : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!table.isEnabled) ...[
                        const Icon(Icons.visibility_off,
                            size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        table.name,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : (table.isEnabled
                                  ? Colors.white70
                                  : Colors.white38),
                          fontSize: MemoryTheme.fontBody,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          decoration: table.isEnabled
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${table.rows.length}',
                        style: TextStyle(
                          color: selected
                              ? Colors.white70
                              : MemoryTheme.textFaint,
                          fontSize: MemoryTheme.fontTiny,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
