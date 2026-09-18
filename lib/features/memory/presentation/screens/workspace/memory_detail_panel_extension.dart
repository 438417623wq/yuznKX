part of '../memory_management_screen.dart';

/// 右栏常驻详情面板 + 窄屏底部详情面板。
///
/// 这是「信息互通」的汇聚点：显示选中记录的完整字段、注入状态、
/// 以及**双向关联**（我引用了谁 / 谁引用了我），关联项可直接跳转。
/// 宽屏右栏常驻；窄屏只在选中记录时出现（见 shell extension）。
extension _MemoryDetailPanelExtension on _MemoryManagementScreenState {
  /// 宽屏右栏：常驻，无选中记录时显示表级概览。
  Widget _buildDetailPanel(List<MemoryTable> tables, MemoryTable table) {
    final selected = _selectedRowOf(table);
    final accent = _hexColor(table.style.accentColor, MemoryTheme.accent);

    return Container(
      color: MemoryTheme.panel,
      child: selected == null
          ? _buildTableOverview(table, accent)
          : _buildRecordDetail(tables, table, selected, accent),
    );
  }

  /// 未选中记录时的表级概览：让右栏永远有内容，不出现空洞。
  Widget _buildTableOverview(MemoryTable table, Color accent) {
    final completeness = MemoryLinker.tableCompleteness(table);
    final enabledCount = table.rows.where((row) => row.isEnabled).length;
    final primary = _resolvePrimaryColumn(table);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: MemoryTheme.fontTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (table.note.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            table.note.trim(),
            style: const TextStyle(
              color: MemoryTheme.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildOverviewMetric(
          label: '记录条数',
          value: '${table.rows.length}',
          hint: enabledCount == table.rows.length
              ? '全部启用'
              : '启用 $enabledCount 条',
          color: accent,
        ),
        const SizedBox(height: 10),
        _buildOverviewMetric(
          label: '字段数',
          value: '${table.columns.length}',
          hint: primary == null ? '无主键列' : '主键：${primary.label}',
          color: MemoryTheme.edit,
        ),
        const SizedBox(height: 10),
        _buildOverviewMetric(
          label: '填充度',
          value: '${(completeness * 100).round()}%',
          hint: completeness >= 0.8
              ? '内容充实'
              : (completeness >= 0.4 ? '还能再补' : '内容偏少'),
          color: MemoryTheme.enabled,
          // 填充度是全模块唯一保留进度条的位置（导航项里的已移除）。
          progress: completeness,
          progressColor: accent,
        ),
        const SizedBox(height: 18),
        const Text(
          '提示',
          style: TextStyle(
            color: MemoryTheme.label,
            fontSize: MemoryTheme.fontTiny,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '点击中栏任意记录，这里会展开它的完整内容与关联记录。',
          style: TextStyle(
            color: MemoryTheme.textFaint,
            fontSize: 11.5,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewMetric({
    required String label,
    required String value,
    required String hint,
    required Color color,
    double? progress,
    Color? progressColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: MemoryTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: MemoryTheme.label,
                        fontSize: MemoryTheme.fontTiny,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hint,
                      style: const TextStyle(
                        color: MemoryTheme.textFaint,
                        fontSize: MemoryTheme.fontTiny,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progressColor ?? color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 选中记录的完整详情：字段全文 + 注入状态 + 双向关联。
  Widget _buildRecordDetail(
    List<MemoryTable> tables,
    MemoryTable table,
    MemoryRow row,
    Color accent,
  ) {
    final primary = _resolvePrimaryColumn(table);
    final title = primary == null
        ? ''
        : (row.data[primary.key] ?? '').toString().trim();
    final isFresh = MemoryTheme.isFresh(row.updatedAt);

    final links = MemoryLinker.resolve(
      tables: tables,
      source: table,
      row: row,
      primaryKeyOf: _resolvePrimaryColumn,
    );
    final backlinks = MemoryLinker.resolveBacklinks(
      tables: tables,
      source: table,
      row: row,
      primaryKeyOf: _resolvePrimaryColumn,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      children: [
        // 标题行 + 收起按钮（收起 = 取消选中，回到表级概览）。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFresh) ...[
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: accent.withValues(alpha: 0.6), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                title.isEmpty ? '（未命名记录）' : title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: MemoryTheme.fontTitle,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            IconButton(
              tooltip: '收起详情',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              onPressed: () => _selectRow(null),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              row.isEnabled ? Icons.visibility : Icons.visibility_off,
              size: 11,
              color: row.isEnabled ? MemoryTheme.enabled : Colors.white38,
            ),
            const SizedBox(width: 4),
            Text(
              row.isEnabled ? '已启用' : '已停用',
              style: TextStyle(
                color: row.isEnabled ? MemoryTheme.enabled : Colors.white38,
                fontSize: MemoryTheme.fontTiny,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.schedule, size: 11, color: MemoryTheme.textFaint),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                MemoryTheme.relativeTime(row.updatedAt),
                style: const TextStyle(
                  color: MemoryTheme.textFaint,
                  fontSize: MemoryTheme.fontTiny,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 字段全文：详情面板不做截断，这是它相对卡片的唯一价值。
        ...table.columns.map(
          (column) => _buildDetailField(row, column, primary),
        ),

        if (links.isNotEmpty || backlinks.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Divider(height: 20, color: MemoryTheme.divider),
        ],

        if (links.isNotEmpty) ...[
          _buildLinkSectionTitle(Icons.north_east, '我引用了', links.length),
          const SizedBox(height: 6),
          ...links.map((link) => _buildLinkTile(tables, link, accent)),
        ],

        if (backlinks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLinkSectionTitle(
              Icons.south_west, '被引用', backlinks.length),
          const SizedBox(height: 6),
          ...backlinks.map((link) => _buildLinkTile(tables, link, accent)),
        ],

        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRowEditorDialog(table, row: row),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('编辑',
                    style: TextStyle(fontSize: MemoryTheme.fontSecondary)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MemoryTheme.edit,
                  side: BorderSide(
                      color: MemoryTheme.edit.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => ref
                    .read(memoryProvider.notifier)
                    .toggleRow(table.id, row.id, !row.isEnabled),
                icon: Icon(
                  row.isEnabled ? Icons.visibility_off : Icons.visibility,
                  size: 15,
                ),
                label: Text(
                  row.isEnabled ? '停用' : '启用',
                  style: const TextStyle(fontSize: MemoryTheme.fontSecondary),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MemoryTheme.enabled,
                  side: BorderSide(
                      color: MemoryTheme.enabled.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _confirmDeleteRow(table, row, title: title),
          icon: const Icon(Icons.delete_outline, size: 15),
          label: const Text('删除这条记录',
              style: TextStyle(fontSize: MemoryTheme.fontSecondary)),
          style: OutlinedButton.styleFrom(
            foregroundColor: MemoryTheme.danger,
            side:
                BorderSide(color: MemoryTheme.danger.withValues(alpha: 0.45)),
            minimumSize: const Size(double.infinity, 34),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailField(
    MemoryRow row,
    MemoryColumn column,
    MemoryColumn? primary,
  ) {
    final raw = (row.data[column.key] ?? '').toString().trim();
    final isPrimary = primary != null && column.key == primary.key;
    final isEmpty = raw.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                column.label,
                style: TextStyle(
                  color: isPrimary ? MemoryTheme.accent : MemoryTheme.label,
                  fontSize: MemoryTheme.fontTiny,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isPrimary) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: MemoryTheme.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '主键',
                    style: TextStyle(
                        color: MemoryTheme.accent,
                        fontSize: MemoryTheme.fontTiny),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
            decoration: BoxDecoration(
              color: MemoryTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              isEmpty ? '未填写' : raw,
              style: TextStyle(
                color: isEmpty
                    ? MemoryTheme.emptyValue
                    : Colors.white.withValues(alpha: 0.9),
                fontSize: MemoryTheme.fontSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkSectionTitle(IconData icon, String label, int count) {
    return Row(
      children: [
        Icon(icon, size: 12, color: MemoryTheme.info),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: MemoryTheme.info,
            fontSize: MemoryTheme.fontTiny,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: const TextStyle(
              color: MemoryTheme.textFaint, fontSize: MemoryTheme.fontTiny),
        ),
      ],
    );
  }

  /// 单条关联记录：可点击跳转（这就是「双向跳转」的落点）。
  Widget _buildLinkTile(
    List<MemoryTable> tables,
    MemoryLinkTarget link,
    Color accent,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _jumpToRecord(tables, link),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
          decoration: BoxDecoration(
            color: MemoryTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: MemoryTheme.accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title.isEmpty ? '（未命名记录）' : link.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: MemoryTheme.fontSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${link.tableName} · ${link.reason}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MemoryTheme.textFaint,
                        fontSize: MemoryTheme.fontTiny,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 16, color: MemoryTheme.accent),
            ],
          ),
        ),
      ),
    );
  }

  /// 窄屏详情面板（选中记录后出现在底部的下半区）。
  ///
  /// 与宽屏右栏语义一致：选中记录 → 记录详情 + 双向关联。
  /// 未选中时整个面板不渲染（窄屏列表独占工作区）。
  Widget _buildNarrowDetailPanel(List<MemoryTable> tables, MemoryTable table) {
    final selected = _selectedRowOf(table);
    final accent = _hexColor(table.style.accentColor, MemoryTheme.accent);

    return Container(
      decoration: BoxDecoration(
        color: MemoryTheme.surface,
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.5))),
      ),
      child: selected == null
          ? _buildTableOverview(table, accent)
          : _buildNarrowRecordDetail(tables, table, selected, accent),
    );
  }

  /// 窄屏记录详情：带标题栏与关闭按钮，内容可滚动。
  Widget _buildNarrowRecordDetail(
    List<MemoryTable> tables,
    MemoryTable table,
    MemoryRow row,
    Color accent,
  ) {
    final primary = _resolvePrimaryColumn(table);
    final title = primary == null
        ? ''
        : (row.data[primary.key] ?? '').toString().trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? '（未命名记录）' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: MemoryTheme.fontTitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  table.name,
                  style: TextStyle(color: accent, fontSize: 10),
                ),
              ),
              IconButton(
                tooltip: '收起详情',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                icon:
                    const Icon(Icons.close, size: 16, color: Colors.white54),
                onPressed: () => _selectRow(null),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: MemoryTheme.divider),
        Expanded(
          child: _buildNarrowDetailBody(tables, table, row),
        ),
      ],
    );
  }

  /// 窄屏详情的内容体：字段全文 + 双向关联 + 操作按钮。
  ///
  /// 自带滚动（不再需要外部传入 ScrollController）。
  Widget _buildNarrowDetailBody(
    List<MemoryTable> tables,
    MemoryTable table,
    MemoryRow row,
  ) {
    final primary = _resolvePrimaryColumn(table);
    final links = MemoryLinker.resolve(
      tables: tables,
      source: table,
      row: row,
      primaryKeyOf: _resolvePrimaryColumn,
    );
    final backlinks = MemoryLinker.resolveBacklinks(
      tables: tables,
      source: table,
      row: row,
      primaryKeyOf: _resolvePrimaryColumn,
    );
    final accent = _hexColor(table.style.accentColor, MemoryTheme.accent);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        ...table.columns.map(
          (column) => _buildDetailField(row, column, primary),
        ),
        if (links.isNotEmpty) ...[
          const Divider(height: 20, color: MemoryTheme.divider),
          _buildLinkSectionTitle(Icons.north_east, '我引用了', links.length),
          const SizedBox(height: 6),
          ...links.map((link) => _buildLinkTile(tables, link, accent)),
        ],
        if (backlinks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLinkSectionTitle(Icons.south_west, '被引用', backlinks.length),
          const SizedBox(height: 6),
          ...backlinks.map((link) => _buildLinkTile(tables, link, accent)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRowEditorDialog(table, row: row),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('编辑',
                    style: TextStyle(fontSize: MemoryTheme.fontSecondary)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MemoryTheme.edit,
                  side: BorderSide(
                      color: MemoryTheme.edit.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 34),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _confirmDeleteRow(table, row, title: ''),
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('删除',
                    style: TextStyle(fontSize: MemoryTheme.fontSecondary)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MemoryTheme.danger,
                  side: BorderSide(
                      color: MemoryTheme.danger.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 34),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
