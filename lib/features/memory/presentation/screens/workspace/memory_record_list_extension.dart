part of '../memory_management_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 中栏：工具栏 + 记录流（卡片 / 表格两种形态）。
///
/// 与旧版的差别：不再用 `TabBarView` 承载多表，切表由 [_selectTable] 直接换数据，
/// 因此各表的滚动位置与搜索词都能自然保留。
extension _MemoryRecordListExtension on _MemoryManagementScreenState {
  Widget _buildRecordColumn(
    MemoryTable table,
    String viewMode, {
    bool isWide = true,
  }) {
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          _buildTableToolbar(table, filteredRows.length, viewMode,
              isWide: isWide),
          const SizedBox(height: 10),
          Expanded(
            child: viewMode == 'table'
                ? _buildTableGrid(table, filteredRows,
                    searchQuery: _searchTextByTable[table.id]?.trim() ?? '')
                : _buildCardList(table, filteredRows,
                    searchQuery: _searchTextByTable[table.id]?.trim() ?? '',
                    isWide: isWide),
          ),
        ],
      ),
    );
  }

  /// 中栏工具栏：搜索一行；统计 + 视图切换（仅宽屏）+ 新增一行。
  /// 其余操作（表格设置 / 样式 / 字段 / 删除表格 / 导入导出）都在右上角 ⋮ 菜单里。
  Widget _buildTableToolbar(
    MemoryTable table,
    int filteredCount,
    String viewMode, {
    required bool isWide,
  }) {
    final query = _searchTextByTable[table.id] ?? '';
    final stateLabel = table.isEnabled ? '已启用' : '已停用';
    final statusText = table.rows.length == filteredCount
        ? '${table.rows.length} 条 · $stateLabel'
        : '$filteredCount / ${table.rows.length} 条 · $stateLabel';

    // 注入开关：这张表的数据是否真的会进上下文，一处可见。
    final injectable = table.isEnabled && table.behavior.toChat;

    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Colors.white, fontSize: MemoryTheme.fontBody),
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
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MemoryTheme.info,
                        fontSize: MemoryTheme.fontSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildInjectBadge(injectable),
                ],
              ),
            ),
            // 窄屏不提供表格视图（卡片更适合手机），切换开关只在宽屏出现。
            if (isWide) ...[
              _buildViewModeToggle(viewMode),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: () => _showRowEditorDialog(table),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增'),
              style: FilledButton.styleFrom(
                backgroundColor: MemoryTheme.accent,
                foregroundColor: MemoryTheme.onAccent,
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

  /// 「已注入 / 未注入」徽章。让「记忆有没有生效」在列表层就可见，
  /// 不必进设置页或注入预览才知道。
  Widget _buildInjectBadge(bool injectable) {
    final color = injectable ? MemoryTheme.enabled : MemoryTheme.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            injectable ? Icons.bolt : Icons.bolt_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            injectable ? '已注入' : '未注入',
            style: TextStyle(color: color, fontSize: MemoryTheme.fontTiny),
          ),
        ],
      ),
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
            .setString(
                _MemoryManagementScreenState._viewModeKey,
                selection.first ? 'card' : 'table');
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MemoryTheme.accent;
          }
          return MemoryTheme.fillSubtle;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MemoryTheme.onAccent;
          }
          return Colors.white70;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: MemoryTheme.border),
        ),
      ),
    );
  }

  /// 卡片列表视图：每条记录一张卡，字段竖排，操作图标固定在卡内。
  /// 空值字段灰显而不隐藏，保持字段结构可预期。
  ///
  /// 相比旧版新增：**选中态**。点击卡片即选中，选中项与详情面板联动。
  Widget _buildCardList(
    MemoryTable table,
    List<MemoryRow> rows, {
    String searchQuery = '',
    required bool isWide,
  }) {
    if (rows.isEmpty) {
      return _buildEmptyRows(table, searchNoMatch: table.rows.isNotEmpty);
    }

    final style = table.style;
    final accentColor = _hexColor(style.accentColor, MemoryTheme.accent);
    final rowColor = _hexColor(style.rowColor, MemoryTheme.surface);

    final primaryColumn = _resolvePrimaryColumn(table);

    return ListView.separated(
      controller: _recordController(table.id),
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

        // 字段多于 5 个时默认折叠，避免卡片被撑到半屏高。
        final collapsed = others.length > _MemoryManagementScreenState._maxVisibleFields;
        final expanded = _expandedRowIds.contains(row.id);
        final visibleOthers =
            (collapsed && !expanded) ? others.take(_MemoryManagementScreenState._maxVisibleFields) : others;

        final isFresh = MemoryTheme.isFresh(row.updatedAt);
        final isSelected = _selectedRowId == row.id;

        return InkWell(
          // 选中那张卡挂上 GlobalKey，供跳转后精确滚动定位。
          key: isSelected ? _selectedRowKey : null,
          onTap: () => _selectRow(row.id),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: row.isEnabled
                  ? rowColor.withValues(alpha: 0.85)
                  : const Color(0x66000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // 选中态优先于表级强调色，否则在卡片视图里看不出来选中了哪条。
                color: isSelected
                    ? accentColor
                    : (row.isEnabled
                        ? accentColor.withValues(alpha: 0.35)
                        : Colors.white12),
                width: isSelected ? 1.6 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : (style.softShadow
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null),
            ),
            child: ClipRRect(
              // 让左侧色带跟随圆角裁切，不会戳出边框。
              borderRadius: BorderRadius.circular(12),
              // ⚠️ 这里刻意**不用 IntrinsicHeight + CrossAxisAlignment.stretch**：
              // 二者组合会让每个 list item 多跑一次 intrinsic layout，
              // 在滚动列表里是明显的性能负担。改用 Stack 叠加一条只占左侧
              // 3px 的色带，视觉效果一致但没有额外布局成本。
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(15, 6, 2, 4),
                        child: Row(
                          children: [
                            if (isFresh && row.isEnabled) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: TextStyle(
                                    color: row.isEnabled
                                        ? Colors.white
                                        : Colors.white38,
                                    fontSize: MemoryTheme.fontTitle,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: title.isEmpty
                                      ? const [
                                          TextSpan(text: '（未命名记录）'),
                                        ]
                                      : _highlightSpans(
                                          text: title,
                                          query: searchQuery,
                                          baseColor: row.isEnabled
                                              ? Colors.white
                                              : Colors.white38,
                                        ),
                                ),
                              ),
                            ),
                            // 卡片只保留「启停」和「编辑」两个最高频操作；
                            // 删除挪进详情面板（先选中再操作），不再常驻卡上，
                            // 避免与编辑并排时误触。触摸目标 44px。
                            _buildCardAction(
                              tooltip: row.isEnabled ? '停用' : '启用',
                              icon: row.isEnabled
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: row.isEnabled
                                  ? MemoryTheme.enabled
                                  : Colors.white54,
                              onPressed: () => ref
                                  .read(memoryProvider.notifier)
                                  .toggleRow(table.id, row.id, !row.isEnabled),
                            ),
                            _buildCardAction(
                              tooltip: '编辑',
                              icon: Icons.edit,
                              color: MemoryTheme.edit,
                              onPressed: () =>
                                  _showRowEditorDialog(table, row: row),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: MemoryTheme.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(15, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...visibleOthers.map(
                              (column) => _buildCardField(
                                row,
                                column,
                                style,
                                query: searchQuery,
                              ),
                            ),
                            if (collapsed)
                              InkWell(
                                onTap: () => setState(() {
                                  if (expanded) {
                                    _expandedRowIds.remove(row.id);
                                  } else {
                                    _expandedRowIds.add(row.id);
                                  }
                                }),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        expanded
                                            ? '收起'
                                            : '还有 ${others.length - _MemoryManagementScreenState._maxVisibleFields} 项',
                                        style: TextStyle(
                                          color: MemoryTheme.accent
                                              .withValues(alpha: 0.9),
                                          fontSize: MemoryTheme.fontSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(
                                        expanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 16,
                                        color: MemoryTheme.accent
                                            .withValues(alpha: 0.9),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 2),
                            // 时间可见化：让「记忆在生长」这件事被感知到。
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 11,
                                  color: MemoryTheme.textFaint,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  MemoryTheme.relativeTime(row.updatedAt),
                                  style: const TextStyle(
                                    color: MemoryTheme.textFaint,
                                    fontSize: MemoryTheme.fontTiny,
                                  ),
                                ),
                                const Spacer(),
                                // 方位词跟随屏幕形态：宽屏详情在右栏，
                                // 窄屏详情在底部。
                                Text(
                                  isSelected
                                      ? (isWide ? '已在右侧展开' : '已在下方展开')
                                      : '点击查看详情',
                                  style: TextStyle(
                                    color: isSelected
                                        ? accentColor
                                        : MemoryTheme.textFaint,
                                    fontSize: MemoryTheme.fontTiny,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // 表级色带：与「表格样式」里的强调色联动。
                  // 用 Positioned 贴在左侧，只占 3px，不影响内容布局。
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 3,
                        color: row.isEnabled
                            ? accentColor.withValues(
                                alpha: isSelected ? 1.0 : 0.85)
                            : Colors.white12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 单个字段行：标签 + 值。长文本按 `maxCellLines` 截断，给「展开」入口。
  ///
  /// [query] 非空时会**高亮命中片段** —— 否则搜索结果只有「有一条」的反馈，
  /// 用户还得自己在一堆文字里找命中在哪。
  Widget _buildCardField(
    MemoryRow row,
    MemoryColumn column,
    MemoryTableStyle style, {
    String query = '',
  }) {
    final raw = (row.data[column.key] ?? '').toString().trim();
    final isEmpty = raw.isEmpty;
    final fieldKey = '${row.id}::${column.key}';
    final expanded = _expandedFieldKeys.contains(fieldKey);

    final valueSpans = isEmpty
        ? <TextSpan>[
            const TextSpan(
              text: '未填写',
              style: TextStyle(color: MemoryTheme.emptyValue),
            ),
          ]
        : _highlightSpans(
            text: raw,
            query: query,
            baseColor: Colors.white.withValues(alpha: row.isEnabled ? 0.92 : 0.4),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            maxLines: expanded ? null : style.maxCellLines,
            overflow: expanded ? TextOverflow.clip : TextOverflow.ellipsis,
            text: TextSpan(
              children: valueSpans,
              style: const TextStyle(fontSize: MemoryTheme.fontBody, height: 1.45),
            ),
          ),
          if (!isEmpty && _isTruncatable(raw, style.maxCellLines))
            InkWell(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedFieldKeys.remove(fieldKey);
                } else {
                  _expandedFieldKeys.add(fieldKey);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  expanded ? '收起全文' : '展开全文',
                  style: const TextStyle(
                    color: MemoryTheme.edit,
                    fontSize: MemoryTheme.fontTiny,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 是否值得给「展开全文」入口：比单行预算长即给出。
  bool _isTruncatable(String raw, int maxLines) {
    return raw.length > 40 || raw.contains('\n');
  }

  /// 把 [text] 拆成若干 span，命中 [query] 的片段加高亮底色。
  List<TextSpan> _highlightSpans({
    required String text,
    required String query,
    required Color baseColor,
  }) {
    final baseStyle = TextStyle(color: baseColor);

    if (query.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;

    while (true) {
      final hit = lowerText.indexOf(lowerQuery, cursor);
      if (hit < 0) {
        if (cursor < text.length) {
          spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
        }
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + query.length),
          style: baseStyle.copyWith(
            color: MemoryTheme.accent,
            fontWeight: FontWeight.w700,
            backgroundColor: MemoryTheme.accent.withValues(alpha: 0.18),
          ),
        ),
      );
      cursor = hit + query.length;
    }

    return spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans;
  }

  /// 卡片内的紧凑操作按钮（触摸目标 44px，符合移动端下限）。
  Widget _buildCardAction({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 19, color: color),
      onPressed: onPressed,
    );
  }

  /// 智能挑选「标题列」。
  ///
  /// 优先按语义关键词匹配（角色名 / 事件名称 / 物品名…），
  /// 其次退化为「首个非空且不像日期的列」，最后才用第一列。
  /// 这样自定义表或 AI 新建的表也能有像样的标题。
  MemoryColumn? _resolvePrimaryColumn(MemoryTable table) {
    if (table.columns.isEmpty) {
      return null;
    }

    // 1) 标签命中语义关键词的直接胜出（越靠前越优先）。
    for (final column in table.columns) {
      if (_titleKeywords.any(column.label.contains)) {
        return column;
      }
    }

    // 2) 退化为「首个非空且不像日期的列」。
    for (final column in table.columns) {
      final hasValue = table.rows.any(
        (row) => (row.data[column.key] ?? '').toString().trim().isNotEmpty,
      );
      if (hasValue && !_dateLikeLabel.hasMatch(column.label)) {
        return column;
      }
    }

    // 3) 兜底：原行为。
    return table.columns.first;
  }

  static const List<String> _titleKeywords = [
    '名',
    '标题',
    '事件',
    '角色',
    '物品',
    '设定',
  ];

  static final RegExp _dateLikeLabel =
      RegExp(r'日期|时间|date|time', caseSensitive: false);

  /// 空态区分两种情况：表里真的没有记录（引导添加），
  /// 与「有记录但搜索无命中」（引导清除搜索）。旧版共用一个文案，
  /// 搜索无结果时还给「添加第一条」按钮，逻辑自相矛盾。
  Widget _buildEmptyRows(MemoryTable table, {bool searchNoMatch = false}) {
    if (searchNoMatch) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 52, color: Colors.white24),
            const SizedBox(height: 10),
            const Text('没有找到匹配的记录',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () =>
                  setState(() => _searchTextByTable[table.id] = ''),
              style: OutlinedButton.styleFrom(
                foregroundColor: MemoryTheme.accent,
                side: BorderSide(
                    color: MemoryTheme.accent.withValues(alpha: 0.45)),
              ),
              child: const Text('清除搜索'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.table_rows_outlined,
              size: 52, color: Colors.white24),
          const SizedBox(height: 10),
          const Text('这张表还没有记录', style: TextStyle(color: Colors.white54)),
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

  ScrollController _recordController(String key) {
    return _recordControllers.putIfAbsent(key, ScrollController.new);
  }
}
