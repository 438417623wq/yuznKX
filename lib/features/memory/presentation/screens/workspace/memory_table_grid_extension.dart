part of '../memory_management_screen.dart';

/// 表格视图（DataTable），与卡片视图并列的可选形态。
///
/// 仅宽屏提供：窄屏 `_buildNarrowWorkspace` 固定传卡片形态，
/// 因为固定列宽 + 横向滚动 + 行内按钮在手机竖屏下基本不可用。
extension _MemoryTableGridExtension on _MemoryManagementScreenState {
  Widget _buildTableGrid(
    MemoryTable table,
    List<MemoryRow> rows, {
    String searchQuery = '',
  }) {
    final style = table.style;
    final accentColor = _hexColor(style.accentColor, MemoryTheme.accent);
    final headerColor =
        _hexColor(style.headerColor, const Color(0xFF26273A));
    final rowColor = _hexColor(style.rowColor, MemoryTheme.surface);
    final altRowColor =
        _hexColor(style.alternateRowColor, const Color(0xFF1E1F2C));

    if (rows.isEmpty) {
      return _buildEmptyRows(table, searchNoMatch: table.rows.isNotEmpty);
    }

    final verticalController = _verticalController(table.id);
    final horizontalController = _horizontalController(table.id);

    return Container(
      decoration: BoxDecoration(
        color: rowColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: style.bordered
            ? Border.all(color: accentColor.withValues(alpha: 0.35))
            : Border.all(color: Colors.transparent),
        boxShadow: style.softShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
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
                        fontSize: style.compact ? 12 : MemoryTheme.fontBody,
                      ),
                      dataTextStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: style.compact ? 12 : MemoryTheme.fontBody,
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
                      final isSelected = _selectedRowId == row.id;

                      // 选中行优先用强调色底，其次才是斑马纹 / 停用态。
                      final rowBg = isSelected
                          ? accentColor.withValues(alpha: 0.16)
                          : (!row.isEnabled
                              ? Colors.black26
                              : (style.striped && rowIndex.isOdd
                                  ? altRowColor
                                  : rowColor));

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
                                        ? Colors.white.withValues(alpha: 0.92)
                                        : Colors.white38,
                                  ),
                                ),
                              ),
                              onTap: () => _selectRow(row.id),
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
                                        ? MemoryTheme.enabled
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
                                      size: 18, color: MemoryTheme.edit),
                                  onPressed: () =>
                                      _showRowEditorDialog(table, row: row),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: MemoryTheme.danger),
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
}
