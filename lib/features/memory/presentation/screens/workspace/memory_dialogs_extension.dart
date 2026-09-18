part of '../memory_management_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 记录编辑 / 表格设置 / 样式 / 字段管理 / 导入导出 / 模板重置 等全部弹窗，
/// 以及页面内部的通用小工具方法。
extension _MemoryDialogsExtension on _MemoryManagementScreenState {
  /// 记录编辑器：新增与编辑共用。
  Future<void> _showRowEditorDialog(MemoryTable table,
      {MemoryRow? row}) async {
    final controllers = <String, TextEditingController>{};
    for (final column in table.columns) {
      controllers[column.key] = TextEditingController(
        text: (row?.data[column.key] ?? '').toString(),
      );
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: MemoryTheme.surfaceElevated,
          title: Text(
            row == null ? '新增记录' : '编辑记录',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: table.columns.map((column) {
                  final controller = controllers[column.key]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controller,
                      maxLines: column.multiline ? 4 : 1,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _fieldDecoration(
                        column.label.isEmpty ? column.key : column.label,
                      ).copyWith(hintText: column.hint),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }

    final data = <String, dynamic>{
      for (final entry in controllers.entries) entry.key: entry.value.text,
    };
    for (final controller in controllers.values) {
      controller.dispose();
    }

    if (row == null) {
      ref.read(memoryProvider.notifier).addRow(table.id, data);
    } else {
      ref.read(memoryProvider.notifier).updateRow(table.id, row.id, data);
    }
  }

  /// 表级操作的底部面板：由表导航项 / 分段 chip **长按**呼出。
  ///
  /// 旧版所有表级操作都挤在右上角 ⋮ 里（13 项平铺），在窄屏下这是唯一
  /// 入口，找起来很累。长按把「对这张表做什么」收进上下文菜单，
  /// ⋮ 菜单保留同样入口兜底（可发现性）。
  Future<void> _showTableActionsSheet(MemoryTable table) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MemoryTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _hexColor(
                          table.style.accentColor, MemoryTheme.accent),
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
                  Text(
                    '${table.rows.length} 条',
                    style: const TextStyle(
                      color: MemoryTheme.textFaint,
                      fontSize: MemoryTheme.fontTiny,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: MemoryTheme.divider),
            _sheetAction(
              ctx: ctx,
              icon: Icons.settings_outlined,
              color: Colors.white70,
              label: '表格设置',
              onTap: () {
                Navigator.pop(ctx);
                _showTableSettingsDialog(table);
              },
            ),
            _sheetAction(
              ctx: ctx,
              icon: Icons.view_column_outlined,
              color: Colors.white70,
              label: '管理字段',
              onTap: () {
                Navigator.pop(ctx);
                _showColumnManagerDialog(table);
              },
            ),
            _sheetAction(
              ctx: ctx,
              icon: Icons.palette_outlined,
              color: Colors.white70,
              label: '表格样式',
              onTap: () {
                Navigator.pop(ctx);
                _showTableStyleDialog(table);
              },
            ),
            _sheetAction(
              ctx: ctx,
              icon: Icons.cleaning_services_outlined,
              color: MemoryTheme.danger,
              label: '清空这张表的记录',
              onTap: () {
                Navigator.pop(ctx);
                _confirmClearRows(table);
              },
            ),
            _sheetAction(
              ctx: ctx,
              icon: Icons.delete_outline,
              color: MemoryTheme.danger,
              label: '删除这张表格',
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTable(table);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction({
    required BuildContext ctx,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 20),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontSize: MemoryTheme.fontBody),
            ),
          ],
        ),
      ),
    );
  }

  /// 表格级设置：名称 / 备注 / 启用 / 是否注入。
  Future<void> _showTableSettingsDialog(MemoryTable table) async {
    final nameController = TextEditingController(text: table.name);
    final noteController = TextEditingController(text: table.note);
    var isEnabled = table.isEnabled;
    var toChat = table.behavior.toChat;
    var required = table.behavior.required;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: MemoryTheme.surfaceElevated,
              title: const Text('表格设置',
                  style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('表格名称'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('备注（仅给自己看）'),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isEnabled,
                        title: const Text('启用这张表',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: const Text('停用后其记录不参与注入',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                        onChanged: (value) => setLocal(() => isEnabled = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: toChat,
                        title: const Text('注入到聊天上下文',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: const Text('决定这张表的内容是否发给模型',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                        onChanged: (value) => setLocal(() => toChat = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: required,
                        title: const Text('标记为必需',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: const Text('必需表在删除表格时会额外提示',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                        onChanged: (value) => setLocal(() => required = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      nameController.dispose();
      noteController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final note = noteController.text.trim();
    nameController.dispose();
    noteController.dispose();

    ref.read(memoryProvider.notifier).updateTable(
          table.copyWith(
            name: name.isEmpty ? table.name : name,
            note: note,
            isEnabled: isEnabled,
            behavior: table.behavior.copyWith(
              toChat: toChat,
              required: required,
            ),
          ),
        );
  }

  /// 表格样式：卡片视图只用 accentColor / rowColor / softShadow，
  /// 其余字段只在表格视图生效。
  Future<void> _showTableStyleDialog(MemoryTable table) async {
    var style = table.style;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: MemoryTheme.surfaceElevated,
              title: const Text('表格样式',
                  style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildColorPicker(
                        label: '强调色（色带 / 进度条）',
                        current: style.accentColor,
                        onChanged: (value) => setLocal(
                            () => style = style.copyWith(accentColor: value)),
                      ),
                      const SizedBox(height: 12),
                      _buildColorPicker(
                        label: '记录底色',
                        current: style.rowColor,
                        onChanged: (value) => setLocal(
                            () => style = style.copyWith(rowColor: value)),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: style.softShadow,
                        title: const Text('柔和阴影',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        onChanged: (value) => setLocal(
                            () => style = style.copyWith(softShadow: value)),
                      ),
                      const Divider(color: MemoryTheme.divider),
                      const Text(
                        '以下仅在「表格」视图生效',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      _buildColorPicker(
                        label: '表头底色',
                        current: style.headerColor,
                        onChanged: (value) => setLocal(
                            () => style = style.copyWith(headerColor: value)),
                      ),
                      const SizedBox(height: 12),
                      _buildColorPicker(
                        label: '交替行底色',
                        current: style.alternateRowColor,
                        onChanged: (value) => setLocal(() =>
                            style = style.copyWith(alternateRowColor: value)),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: style.striped,
                        title: const Text('斑马纹',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        onChanged: (value) =>
                            setLocal(() => style = style.copyWith(striped: value)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: style.bordered,
                        title: const Text('显示边框',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        onChanged: (value) =>
                            setLocal(() => style = style.copyWith(bordered: value)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: style.compact,
                        title: const Text('紧凑行高',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        onChanged: (value) =>
                            setLocal(() => style = style.copyWith(compact: value)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '单元格最多显示行数：${style.maxCellLines}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      Slider(
                        value: style.maxCellLines.toDouble(),
                        min: 1,
                        max: 6,
                        divisions: 5,
                        label: '${style.maxCellLines}',
                        onChanged: (value) => setLocal(
                            () => style = style.copyWith(
                                maxCellLines: value.round())),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      return;
    }
    ref.read(memoryProvider.notifier).updateTable(table.copyWith(style: style));
  }

  Widget _buildColorPicker({
    required String label,
    required String current,
    required ValueChanged<String> onChanged,
  }) {
    final selected = _hexColor(current, MemoryTheme.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _MemoryManagementScreenState._presetColors.map((hex) {
            final color = _hexColor(hex, MemoryTheme.accent);
            final isActive =
                hex.toLowerCase() == current.trim().toLowerCase();
            return InkWell(
              onTap: () => onChanged(hex),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? Colors.white : Colors.white24,
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: isActive
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          '当前：${current.trim().isEmpty ? '默认' : current}　色板示例：$selected',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  String _columnTypeLabel(String type) {
    switch (type) {
      case 'number':
        return '数字';
      case 'boolean':
        return '是/否';
      case 'datetime':
        return '日期时间';
      case 'text':
      default:
        return '文本';
    }
  }

  Future<void> _confirmDeleteColumn(
    MemoryTable table,
    MemoryColumn column,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('删除字段', style: TextStyle(color: Colors.white)),
        content: Text(
          '删除「${column.label}」后，所有记录里这一列的数据都会一并移除。',
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
    ref.read(memoryProvider.notifier).deleteColumn(table.id, column.key);
  }

  /// 字段管理：改标签 / 类型 / 宽度，增删字段。
  Future<void> _showColumnManagerDialog(MemoryTable table) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ColumnManagerDialog(
        table: table,
        onEdit: (column) {
          Navigator.pop(ctx);
          _showColumnEditorDialog(table, column: column);
        },
        onAdd: () {
          Navigator.pop(ctx);
          _showColumnEditorDialog(table);
        },
        onDelete: (column) => _confirmDeleteColumn(table, column),
        typeLabel: _columnTypeLabel,
      ),
    );
  }

  Future<void> _showColumnEditorDialog(
    MemoryTable table, {
    MemoryColumn? column,
  }) async {
    final labelController = TextEditingController(text: column?.label ?? '');
    final hintController = TextEditingController(text: column?.hint ?? '');
    // 导入的模板可能带任意 type，喂给下拉框前必须归一化（否则 release 白屏）。
    final rawType = (column?.type ?? 'text').trim().toLowerCase();
    var type = _MemoryManagementScreenState._supportedColumnTypes.contains(rawType) ? rawType : 'text';
    var multiline = column?.multiline ?? false;
    var width = column?.width ?? 120.0;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: MemoryTheme.surfaceElevated,
              title: Text(
                column == null ? '新增字段' : '编辑字段',
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: labelController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('字段名称'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        dropdownColor: MemoryTheme.surfaceElevated,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('字段类型'),
                        items: _MemoryManagementScreenState._supportedColumnTypes
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_columnTypeLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setLocal(() => type = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: hintController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _fieldDecoration('填写提示（可选）'),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: multiline,
                        title: const Text('多行文本',
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        onChanged: (value) => setLocal(() => multiline = value),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '表格视图列宽：${width.round()}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Slider(
                        value: width.clamp(60, 320),
                        min: 60,
                        max: 320,
                        divisions: 26,
                        label: '${width.round()}',
                        onChanged: (value) => setLocal(() => width = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    final label = labelController.text.trim();
    final hint = hintController.text.trim();
    labelController.dispose();
    hintController.dispose();

    if (saved != true) {
      return;
    }
    if (label.isEmpty) {
      _showSnack('字段名称不能为空');
      return;
    }

    final notifier = ref.read(memoryProvider.notifier);
    if (column == null) {
      notifier.addColumn(
        table.id,
        MemoryColumn(
          key: _slugKey(label),
          label: label,
          type: type,
          hint: hint,
          multiline: multiline,
          width: width,
        ),
      );
      return;
    }

    notifier.updateColumn(
      table.id,
      column.key,
      column.copyWith(
        label: label,
        type: type,
        hint: hint,
        multiline: multiline,
        width: width,
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('导入模板 JSON',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '粘贴模板 JSON。导入会覆盖当前对话的记忆结构。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.4),
                  decoration: _fieldDecoration('模板 JSON'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              controller.text = _buildDefaultTemplateJson();
            },
            child: const Text('填入当前模板'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    final raw = controller.text;
    controller.dispose();

    if (confirmed != true) {
      return;
    }
    if (raw.trim().isEmpty) {
      _showSnack('模板内容为空');
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _showSnack('模板格式不正确：顶层需要是对象');
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      final rawTables = map['tableStructure'];
      if (rawTables is! List || rawTables.isEmpty) {
        _showSnack('模板里没有 tableStructure');
        return;
      }
      final tables = <MemoryTable>[];
      for (var i = 0; i < rawTables.length; i++) {
        final item = rawTables[i];
        if (item is Map) {
          tables.add(
            MemoryTable.fromJson(
              Map<String, dynamic>.from(item),
              fallbackIndex: i,
            ),
          );
        }
      }
      if (tables.isEmpty) {
        _showSnack('模板里没有可用的表格');
        return;
      }
      ref.read(memoryProvider.notifier).replaceTables(tables);
      setState(() {
        _activeTabIndex = 0;
        _selectedRowId = null;
      });
      _showSnack('已导入 ${tables.length} 张表');
    } catch (error) {
      _showSnack('导入失败：$error');
    }
  }

  Future<void> _showExportDialog() async {
    final json = _buildDefaultTemplateJson();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('导出模板 JSON',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
              _showSnack('已复制到剪贴板');
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddTableDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('新建表格', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _fieldDecoration('表格名称，例如「支线任务」'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();

    if (confirmed != true || name.isEmpty) {
      return;
    }

    ref.read(memoryProvider.notifier).addTable(name: name);
    _showSnack('已创建「$name」');
  }

  Future<void> _confirmDeleteTable(MemoryTable table) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('删除表格', style: TextStyle(color: Colors.white)),
        content: Text(
          table.behavior.required
              ? '「${table.name}」被标记为必需表格，删除后其中的 ${table.rows.length} 条记录会一并丢失。'
              : '确定删除「${table.name}」吗？其中 ${table.rows.length} 条记录会一并丢失。',
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
    ref.read(memoryProvider.notifier).deleteTable(table.id);
    setState(() {
      _selectedRowId = null;
      if (_activeTabIndex > 0) {
        _activeTabIndex -= 1;
      }
    });
  }

  Future<void> _confirmClearRows(MemoryTable table) async {
    if (table.rows.isEmpty) {
      _showSnack('这张表还没有记录');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('清空记录', style: TextStyle(color: Colors.white)),
        content: Text(
          '将清空「${table.name}」的全部 ${table.rows.length} 条记录。表格结构与字段会保留。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    ref.read(memoryProvider.notifier).clearRows(table.id);
    setState(() => _selectedRowId = null);
    _showSnack('已清空「${table.name}」');
  }

  /// 调整表格顺序：上下移动 + 置顶。
  Future<void> _showTableReorderDialog(List<MemoryTable> tables) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('调整表格顺序',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: SizedBox(
            height: 360,
            child: Consumer(
              builder: (context, ref, _) {
                final current = ref.watch(memoryProvider);
                return ReorderableListView.builder(
                  itemCount: current.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    ref
                        .read(memoryProvider.notifier)
                        .reorderTables(oldIndex, newIndex);
                    // 顺序变了，选中项按 id 重新定位，避免详情面板张冠李戴。
                    final activeId = _activeTabIndex < current.length
                        ? current[_activeTabIndex].id
                        : null;
                    if (activeId != null) {
                      final next = ref.read(memoryProvider);
                      final index =
                          next.indexWhere((table) => table.id == activeId);
                      if (index >= 0) {
                        setState(() => _activeTabIndex = index);
                      }
                    }
                  },
                  itemBuilder: (context, index) {
                    final table = current[index];
                    return ListTile(
                      key: ValueKey(table.id),
                      dense: true,
                      leading: const Icon(Icons.drag_handle,
                          size: 18, color: Colors.white38),
                      title: Text(
                        table.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${table.rows.length} 条',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('重置为默认模板',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          '会用默认的 7 张表结构覆盖当前对话的记忆，已有记录将全部丢失。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    final bundle = getDefaultMemoryTemplateBundle();
    ref.read(memoryProvider.notifier).replaceTables(bundle.tables);
    setState(() {
      _activeTabIndex = 0;
      _selectedRowId = null;
    });
    _showSnack('已重置为默认模板');
  }

  // ---------------------------------------------------------------------
  // 通用小工具
  // ---------------------------------------------------------------------

  InputDecoration _fieldDecoration(String label) {
    return MemoryTheme.fieldDecoration(label);
  }

  Color _hexColor(String hex, Color fallback) {
    return MemoryTheme.hexColor(hex, fallback);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
              color: Colors.white, fontSize: MemoryTheme.fontBody),
        ),
        // 默认的 fixed SnackBar 会被 HomeScreen 的底部导航栏挡住。
        behavior: SnackBarBehavior.floating,
        backgroundColor: MemoryTheme.surfaceElevated,
        duration: const Duration(seconds: 3),
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
        backgroundColor: MemoryTheme.surfaceElevated,
        title: const Text('删除记录', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定删除 $label 吗？删除后可在提示条中撤销。',
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

    // 记下删除前的完整快照，供「撤销」还原（含原始插入位置）。
    final snapshot = [...table.rows];
    ref.read(memoryProvider.notifier).deleteRow(table.id, row.id);
    if (_selectedRowId == row.id) {
      setState(() => _selectedRowId = null);
    }
    _showUndoDeleteSnack(table, snapshot, label);
  }

  /// 删除后的「撤销」提示。
  ///
  /// 二次确认防的是**误触**，撤销防的是**后悔** —— 两者互补，
  /// 只看一眼标题就删掉的记录，靠这里还能救回来。
  void _showUndoDeleteSnack(
    MemoryTable table,
    List<MemoryRow> snapshot,
    String label,
  ) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已删除 $label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            // 整表还原快照，保持原有顺序。
            ref.read(memoryProvider.notifier).updateTable(
                  table.copyWith(rows: snapshot),
                );
          },
        ),
      ),
    );
  }

  String _slugKey(String raw) {
    final value = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (value.isEmpty) {
      // 中文标签会被上一步整段剥掉。原实现兜底成毫秒时间戳，导出 JSON 后
      // 会出现 `col_1758189600000` 这种完全不可读、且每次都不一样（无法 diff）
      // 的 key。这里改成按标签内容派生一个**稳定**的值。
      var hash = 7;
      for (final unit in raw.trim().codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      return 'col_$hash';
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

}

/// 「字段管理」弹窗。
///
/// 单独拆成 StatefulWidget 而不是内联 `StatefulBuilder`，是因为它要
/// 跟随 provider 实时刷新列表（增删字段后条目数会变）。
class _ColumnManagerDialog extends ConsumerWidget {
  const _ColumnManagerDialog({
    required this.table,
    required this.onEdit,
    required this.onAdd,
    required this.onDelete,
    required this.typeLabel,
  });

  final MemoryTable table;
  final void Function(MemoryColumn column) onEdit;
  final VoidCallback onAdd;
  final void Function(MemoryColumn column) onDelete;
  final String Function(String type) typeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用 provider 里的最新表格，避免弹窗开着时别处改了字段导致列表过期。
    final tables = ref.watch(memoryProvider);
    final current = tables.firstWhere(
      (item) => item.id == table.id,
      orElse: () => table,
    );

    return AlertDialog(
      backgroundColor: MemoryTheme.surfaceElevated,
      title: const Text('管理字段', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 420,
        child: SizedBox(
          height: 380,
          child: current.columns.isEmpty
              ? const Center(
                  child: Text('还没有字段',
                      style: TextStyle(color: Colors.white38)),
                )
              : ListView.separated(
                  itemCount: current.columns.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: MemoryTheme.divider),
                  itemBuilder: (context, index) {
                    final column = current.columns[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        column.label,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${typeLabel(column.type)} · 宽 ${column.width.round()}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit,
                                size: 17, color: MemoryTheme.edit),
                            onPressed: () => onEdit(column),
                          ),
                          IconButton(
                            tooltip: '删除',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                size: 17, color: MemoryTheme.danger),
                            onPressed: () => onDelete(column),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: onAdd, child: const Text('新增字段')),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
