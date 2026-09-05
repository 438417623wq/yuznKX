import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../character/data/character_provider.dart';
import '../domain/models/memory_table.dart';

const _memoryTablesBoxName = 'memory_tables_v2';
const _memorySettingsBoxName = 'memory_plugin_settings_v2';

final memoryProvider =
    StateNotifierProvider<MemoryNotifier, List<MemoryTable>>((ref) {
  final activeChar = ref.watch(activeCharacterProvider);
  return MemoryNotifier(activeChar?.id);
});

final memoryPluginSettingsProvider =
    StateNotifierProvider<MemoryPluginSettingsNotifier, MemoryPluginSettings>(
        (ref) {
  final activeChar = ref.watch(activeCharacterProvider);
  return MemoryPluginSettingsNotifier(activeChar?.id);
});

List<MemoryTable> getDefaultMemoryTables() {
  return getDefaultMemoryTemplateBundle().tables;
}

MemoryTemplateBundle getDefaultMemoryTemplateBundle() {
  const settings = MemoryPluginSettings(
    isPluginEnabled: true,
    isAiReadTable: true,
    isAiWriteTable: true,
    injectionMode: 'deep_system',
    deep: 2,
    confirmBeforeExecution: true,
    useMainApi: true,
    useTokenLimit: true,
    rebuildTokenLimitValue: 100000,
    isHistoryRangeLimitEnabled: true,
    historyRangeStartFloor: 0,
    historyRangeEndFloor: -1,
    isKeepLatestEnabled: false,
    keepLatestFloors: 3,
  );

  final tablePalette = [
    '#24C3B5',
    '#3BA6FF',
    '#56D17B',
    '#FFC857',
    '#FF8C69',
    '#E383FF',
    '#A0B5FF',
  ];

  final tableSpecs = <Map<String, dynamic>>[
    {
      'name': '角色特征表格',
      'note': '记录角色基础特征与长期状态。',
      'columns': ['角色名', '性别/年龄/身高/外貌', '性格', '长期备注', '临时BUFF', '当前衣着'],
      'required': true,
    },
    {
      'name': '人物关系表格',
      'note': '追踪角色关系变化和情感态度。',
      'columns': ['双方角色名', '基础关系(底层身份)', '当前关系(流动状态)', '相互情感态度'],
      'required': true,
    },
    {
      'name': '事件摘要表格',
      'note': '记录剧情推进中的关键事件。',
      'columns': ['日期', '地点场景', '剧情摘要', '重要细节', '第四面墙'],
      'required': true,
    },
    {
      'name': '世界设定表格',
      'note': '记录新增世界观设定、规则、组织或地点。',
      'columns': ['设定名', '类型', '详细说明', '影响范围'],
      'required': false,
    },
    {
      'name': '重要物品表格',
      'note': '记录具有剧情意义的关键物品。',
      'columns': ['拥有者', '物品名', '描述', '效果/意义', '来源'],
      'required': false,
    },
    {
      'name': '约定表格',
      'note': '记录角色之间的约定与待办。',
      'columns': ['日期', '双方角色名', '任务/约定内容', '完成/待完成', '结果'],
      'required': false,
    },
    {
      'name': '大总结表格',
      'note': '用于阶段性压缩总结，保留关键转折。',
      'columns': ['事件名称(持续时间)', '事件摘要总结', '重要细节', '第四面墙纪要'],
      'required': false,
    },
  ];

  final tables = <MemoryTable>[];
  for (var i = 0; i < tableSpecs.length; i++) {
    final spec = tableSpecs[i];
    final columns = (spec['columns'] as List<String>)
        .asMap()
        .entries
        .map((entry) => MemoryColumn.fromLabel(entry.value, entry.key))
        .toList();
    tables.add(
      MemoryTable(
        id: 'memory_table_$i',
        tableIndex: i,
        name: spec['name'] as String,
        note: spec['note'] as String,
        columns: columns,
        rows: const [],
        behavior: MemoryTableBehavior(
          required: (spec['required'] as bool?) ?? false,
          toChat: true,
          triggerSend: false,
          triggerSendDeep: 1,
        ),
        style: MemoryTableStyle(
          accentColor: tablePalette[i % tablePalette.length],
        ),
      ),
    );
  }

  return MemoryTemplateBundle(
    tables: tables,
    settings: settings,
  );
}

class MemoryPluginSettingsNotifier extends StateNotifier<MemoryPluginSettings> {
  final String? characterId;
  Box? _box;

  MemoryPluginSettingsNotifier(this.characterId)
      : super(getDefaultMemoryTemplateBundle().settings) {
    _init();
  }

  Future<void> _init() async {
    if (characterId == null) {
      state = getDefaultMemoryTemplateBundle().settings;
      return;
    }
    _box = await Hive.openBox(_memorySettingsBoxName);
    final raw = _box!.get(characterId);
    if (raw is Map) {
      state = MemoryPluginSettings.fromJson(Map<String, dynamic>.from(raw));
    } else {
      state = getDefaultMemoryTemplateBundle().settings;
      await save();
    }
  }

  Future<void> save() async {
    if (characterId == null || _box == null) {
      return;
    }
    await _box!.put(characterId, state.toJson());
  }

  void update(MemoryPluginSettings newSettings) {
    state = newSettings;
    save();
  }

  void patch({
    bool? isPluginEnabled,
    bool? isAiReadTable,
    bool? isAiWriteTable,
    String? injectionMode,
    int? deep,
    String? messageTemplate,
    bool? confirmBeforeExecution,
    bool? useMainApi,
    bool? useTokenLimit,
    int? rebuildTokenLimitValue,
    String? toChatContainer,
    bool? tableToChatCanEdit,
    String? tableToChatMode,
    bool? isHistoryRangeLimitEnabled,
    int? historyRangeStartFloor,
    int? historyRangeEndFloor,
    bool? isKeepLatestEnabled,
    int? keepLatestFloors,
  }) {
    state = state.copyWith(
      isPluginEnabled: isPluginEnabled,
      isAiReadTable: isAiReadTable,
      isAiWriteTable: isAiWriteTable,
      injectionMode: injectionMode,
      deep: deep,
      messageTemplate: messageTemplate,
      confirmBeforeExecution: confirmBeforeExecution,
      useMainApi: useMainApi,
      useTokenLimit: useTokenLimit,
      rebuildTokenLimitValue: rebuildTokenLimitValue,
      toChatContainer: toChatContainer,
      tableToChatCanEdit: tableToChatCanEdit,
      tableToChatMode: tableToChatMode,
      isHistoryRangeLimitEnabled: isHistoryRangeLimitEnabled,
      historyRangeStartFloor: historyRangeStartFloor,
      historyRangeEndFloor: historyRangeEndFloor,
      isKeepLatestEnabled: isKeepLatestEnabled,
      keepLatestFloors: keepLatestFloors,
    );
    save();
  }

  void resetToDefault() {
    state = getDefaultMemoryTemplateBundle().settings;
    save();
  }
}

class MemoryNotifier extends StateNotifier<List<MemoryTable>> {
  final String? characterId;
  Box? _box;

  MemoryNotifier(this.characterId) : super(const []) {
    _init();
  }

  Future<void> _init() async {
    if (characterId == null) {
      state = const [];
      return;
    }

    _box = await Hive.openBox(_memoryTablesBoxName);
    final raw = _box!.get(characterId);

    if (raw is List) {
      try {
        final list = raw.cast<dynamic>();
        state = _normalizedTables(
          list
              .asMap()
              .entries
              .where((entry) => entry.value is Map)
              .map((entry) => MemoryTable.fromJson(
                    Map<String, dynamic>.from(entry.value as Map),
                    fallbackIndex: entry.key,
                  ))
              .toList(),
        );
      } catch (error) {
        print('Error loading memory tables: $error');
        state = getDefaultMemoryTables();
        save();
      }
    } else {
      state = getDefaultMemoryTables();
      save();
    }
  }

  Future<void> save() async {
    if (characterId == null || _box == null) {
      return;
    }
    await _box!.put(characterId, state.map((table) => table.toJson()).toList());
  }

  void _commit(List<MemoryTable> nextState) {
    state = _normalizedTables(nextState);
    save();
  }

  List<MemoryTable> _normalizedTables(List<MemoryTable> tables) {
    return tables
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(tableIndex: entry.key))
        .toList();
  }

  MemoryTable? getTableById(String tableId) {
    for (final table in state) {
      if (table.id == tableId) {
        return table;
      }
    }
    return null;
  }

  void replaceTables(List<MemoryTable> tables) {
    _commit(tables);
  }

  void updateTable(MemoryTable table) {
    _commit([
      for (final current in state)
        if (current.id == table.id) table else current
    ]);
  }

  void addTable({
    String? name,
    List<MemoryColumn>? columns,
    String note = '',
  }) {
    final newTableIndex = state.length;
    final fallbackColumns = columns ??
        [
          MemoryColumn.fromLabel('标题', 0),
          MemoryColumn.fromLabel('内容', 1).copyWith(multiline: true, width: 260),
        ];
    final table = MemoryTable(
      id: const Uuid().v4(),
      tableIndex: newTableIndex,
      name: (name ?? '自定义表 ${newTableIndex + 1}').trim(),
      columns: fallbackColumns,
      rows: const [],
      note: note,
      style: const MemoryTableStyle(),
      behavior: const MemoryTableBehavior(toChat: true),
    );
    _commit([...state, table]);
  }

  void deleteTable(String tableId) {
    _commit(state.where((table) => table.id != tableId).toList());
  }

  void reorderTables(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }
    final mutable = [...state];
    final target = mutable.removeAt(oldIndex);
    mutable.insert(newIndex, target);
    _commit(mutable);
  }

  void updateTableMeta({
    required String tableId,
    String? name,
    String? note,
    bool? isEnabled,
  }) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            name: name,
            note: note,
            isEnabled: isEnabled,
          )
        else
          table
    ]);
  }

  void updateTableBehavior(String tableId, MemoryTableBehavior behavior) {
    _commit([
      for (final table in state)
        if (table.id == tableId) table.copyWith(behavior: behavior) else table
    ]);
  }

  void updateTableStyle(String tableId, MemoryTableStyle style) {
    _commit([
      for (final table in state)
        if (table.id == tableId) table.copyWith(style: style) else table
    ]);
  }

  void addColumn(String tableId, MemoryColumn column) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            columns: [...table.columns, column],
            rows: [
              for (final row in table.rows)
                row.copyWith(data: {
                  ...row.data,
                  column.key: '',
                }),
            ],
          )
        else
          table
    ]);
  }

  void updateColumn(
      String tableId, String originalKey, MemoryColumn newColumn) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            columns: [
              for (final column in table.columns)
                if (column.key == originalKey) newColumn else column
            ],
            rows: [
              for (final row in table.rows)
                row.copyWith(
                    data: _renameMapKey(row.data, originalKey, newColumn.key))
            ],
          )
        else
          table
    ]);
  }

  void deleteColumn(String tableId, String columnKey) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            columns: table.columns
                .where((column) => column.key != columnKey)
                .toList(),
            rows: [
              for (final row in table.rows)
                row.copyWith(
                  data: {
                    for (final entry in row.data.entries)
                      if (entry.key != columnKey) entry.key: entry.value
                  },
                ),
            ],
          )
        else
          table
    ]);
  }

  void reorderColumns(String tableId, int oldIndex, int newIndex) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
              columns: _reorderList(table.columns, oldIndex, newIndex))
        else
          table
    ]);
  }

  void addRow(String tableId, Map<String, dynamic> data) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            rows: [
              ...table.rows,
              MemoryRow(
                id: const Uuid().v4(),
                data: _sanitizeRowData(table, data),
              ),
            ],
          )
        else
          table
    ]);
  }

  void updateRow(String tableId, String rowId, Map<String, dynamic> data) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            rows: [
              for (final row in table.rows)
                if (row.id == rowId)
                  row.copyWith(data: _sanitizeRowData(table, data))
                else
                  row
            ],
          )
        else
          table
    ]);
  }

  void deleteRow(String tableId, String rowId) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
              rows: table.rows.where((row) => row.id != rowId).toList())
        else
          table
    ]);
  }

  void toggleRow(String tableId, String rowId, bool enabled) {
    _commit([
      for (final table in state)
        if (table.id == tableId)
          table.copyWith(
            rows: [
              for (final row in table.rows)
                if (row.id == rowId) row.copyWith(isEnabled: enabled) else row
            ],
          )
        else
          table
    ]);
  }

  void resetToDefault() {
    _commit(getDefaultMemoryTables());
  }

  MemoryPluginSettings? importFromPluginJson(String rawJson) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      final bundle = _parseTemplateBundle(decoded);
      if (bundle == null || bundle.tables.isEmpty) {
        return null;
      }
      _commit(bundle.tables);
      return bundle.settings;
    } catch (error) {
      print('Import memory template failed: $error');
      return null;
    }
  }

  String exportToPluginJson(MemoryPluginSettings settings) {
    final payload = {
      ...settings.toJson(),
      'tableStructure': state.map((table) => table.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String getFormattedMemory({MemoryPluginSettings? settings}) {
    final pluginSettings = settings ?? const MemoryPluginSettings();
    if (!pluginSettings.isAiReadTable) {
      return '';
    }
    if (state.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln('# dataTable Rules');
    buffer.writeln(
        '- Use insertRow(tableIndex, {colIndex:"val"}) for new entries.');
    buffer.writeln(
        '- Use updateRow(tableIndex, rowIndex, {colIndex:"val"}) for updates.');
    buffer
        .writeln('- Use deleteRow(tableIndex, rowIndex) to remove stale rows.');
    buffer.writeln(
        '- Wrap operations in <tableEdit><!-- commands --></tableEdit>.');
    buffer.writeln();

    for (var tableIndex = 0; tableIndex < state.length; tableIndex++) {
      final table = state[tableIndex];
      buffer.writeln('[$tableIndex] ${table.name}');
      buffer.writeln(
        'Columns: ${table.columns.asMap().entries.map((entry) => '${entry.key}:${entry.value.label}').join(' | ')}',
      );
      if (table.note.trim().isNotEmpty) {
        buffer.writeln('Note: ${table.note.trim()}');
      }

      if (!table.isEnabled) {
        buffer.writeln('(Disabled)');
        buffer.writeln();
        continue;
      }

      final activeRows = table.rows.where((row) => row.isEnabled).toList();
      if (activeRows.isEmpty) {
        buffer.writeln('(Empty)');
      } else {
        for (var rowIndex = 0; rowIndex < activeRows.length; rowIndex++) {
          final row = activeRows[rowIndex];
          final values = table.columns.asMap().entries.map((entry) {
            final key = entry.value.key;
            final value = (row.data[key] ?? '')
                .toString()
                .replaceAll('\n', ' ')
                .replaceAll(',', '，');
            return '${entry.key}:$value';
          }).join(', ');
          buffer.writeln('$rowIndex -> $values');
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  void processCommands(
    String input, {
    bool allowWrites = true,
  }) {
    if (!allowWrites) {
      return;
    }

    final blocks =
        RegExp(r'<tableEdit>([\s\S]*?)</tableEdit>', caseSensitive: false)
            .allMatches(input)
            .map((match) => match.group(1) ?? '')
            .toList();
    if (blocks.isEmpty) {
      return;
    }

    for (final block in blocks) {
      final cleanBlock = block
          .replaceAll(RegExp(r'<!--[\s\S]*?-->', caseSensitive: false), '')
          .trim();
      if (cleanBlock.isEmpty) {
        continue;
      }
      final commands = cleanBlock
          .split(RegExp(r'[\n;]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      for (final command in commands) {
        _processSingleCommand(command);
      }
    }
  }

  void _processSingleCommand(String command) {
    try {
      if (command.startsWith('insertRow')) {
        _processInsert(command);
      } else if (command.startsWith('updateRow')) {
        _processUpdate(command);
      } else if (command.startsWith('deleteRow')) {
        _processDelete(command);
      }
    } catch (error) {
      print('Error processing memory command "$command": $error');
    }
  }

  void _processInsert(String command) {
    final match = RegExp(r'insertRow\(\s*(\d+)\s*,\s*\{([\s\S]*)\}\s*\)')
        .firstMatch(command);
    if (match == null) {
      return;
    }

    final tableIndex = int.tryParse(match.group(1) ?? '');
    if (tableIndex == null || tableIndex < 0 || tableIndex >= state.length) {
      return;
    }
    final table = state[tableIndex];
    final dataMap = _parseCommandDataMap(match.group(2) ?? '');

    final mapped = <String, dynamic>{};
    for (final entry in dataMap.entries) {
      final colIndex = int.tryParse(entry.key);
      if (colIndex == null ||
          colIndex < 0 ||
          colIndex >= table.columns.length) {
        continue;
      }
      mapped[table.columns[colIndex].key] = entry.value;
    }

    if (mapped.isNotEmpty) {
      addRow(table.id, mapped);
    }
  }

  void _processUpdate(String command) {
    final match =
        RegExp(r'updateRow\(\s*(\d+)\s*,\s*(\d+)\s*,\s*\{([\s\S]*)\}\s*\)')
            .firstMatch(command);
    if (match == null) {
      return;
    }

    final tableIndex = int.tryParse(match.group(1) ?? '');
    final rowIndex = int.tryParse(match.group(2) ?? '');
    if (tableIndex == null ||
        rowIndex == null ||
        tableIndex < 0 ||
        tableIndex >= state.length ||
        rowIndex < 0) {
      return;
    }

    final table = state[tableIndex];
    final activeRows = table.rows.where((row) => row.isEnabled).toList();
    if (rowIndex >= activeRows.length) {
      return;
    }
    final row = activeRows[rowIndex];
    final dataMap = _parseCommandDataMap(match.group(3) ?? '');
    final merged = Map<String, dynamic>.from(row.data);

    for (final entry in dataMap.entries) {
      final colIndex = int.tryParse(entry.key);
      if (colIndex == null ||
          colIndex < 0 ||
          colIndex >= table.columns.length) {
        continue;
      }
      merged[table.columns[colIndex].key] = entry.value;
    }

    updateRow(table.id, row.id, merged);
  }

  void _processDelete(String command) {
    final match =
        RegExp(r'deleteRow\(\s*(\d+)\s*,\s*(\d+)\s*\)').firstMatch(command);
    if (match == null) {
      return;
    }

    final tableIndex = int.tryParse(match.group(1) ?? '');
    final rowIndex = int.tryParse(match.group(2) ?? '');
    if (tableIndex == null ||
        rowIndex == null ||
        tableIndex < 0 ||
        tableIndex >= state.length ||
        rowIndex < 0) {
      return;
    }

    final table = state[tableIndex];
    final activeRows = table.rows.where((row) => row.isEnabled).toList();
    if (rowIndex >= activeRows.length) {
      return;
    }
    deleteRow(table.id, activeRows[rowIndex].id);
  }

  Map<String, dynamic> _parseCommandDataMap(String raw) {
    final result = <String, dynamic>{};
    final pairRegex = RegExp(
      r'''("([^"\\]|\\.)*"|'([^'\\]|\\.)*'|\d+)\s*:\s*("([^"\\]|\\.)*"|'([^'\\]|\\.)*'|-?\d+(\.\d+)?|true|false|null)''',
      caseSensitive: false,
    );

    for (final match in pairRegex.allMatches(raw)) {
      final keyRaw = match.group(1) ?? '';
      final valueRaw = match.group(4) ?? '';
      final key = _decodeToken(keyRaw).toString();
      final value = _decodeToken(valueRaw);
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  dynamic _decodeToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed
          .substring(1, trimmed.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r"\'", "'");
    }

    final lower = trimmed.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if (lower == 'null') return '';

    final number = num.tryParse(trimmed);
    if (number != null) return number;
    return trimmed;
  }
}

MemoryTemplateBundle? _parseTemplateBundle(dynamic decoded) {
  if (decoded is List) {
    final tables = decoded
        .asMap()
        .entries
        .where((entry) => entry.value is Map)
        .map((entry) => MemoryTable.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
              fallbackIndex: entry.key,
            ))
        .toList();
    return MemoryTemplateBundle(
      tables: tables,
      settings: getDefaultMemoryTemplateBundle().settings,
    );
  }

  if (decoded is! Map) {
    return null;
  }

  final map = Map<String, dynamic>.from(decoded);
  final settings = MemoryPluginSettings.fromJson(map);

  final rawTables = map['tableStructure'] ?? map['tables'] ?? map['data'];
  if (rawTables is List) {
    final tables = rawTables
        .asMap()
        .entries
        .where((entry) => entry.value is Map)
        .map((entry) => MemoryTable.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
              fallbackIndex: entry.key,
            ))
        .toList();
    return MemoryTemplateBundle(tables: tables, settings: settings);
  }

  if (map.containsKey('columns')) {
    return MemoryTemplateBundle(
      tables: [MemoryTable.fromJson(map, fallbackIndex: 0)],
      settings: settings,
    );
  }

  return null;
}

Map<String, dynamic> _renameMapKey(
  Map<String, dynamic> source,
  String oldKey,
  String newKey,
) {
  if (oldKey == newKey) {
    return Map<String, dynamic>.from(source);
  }
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    if (entry.key == oldKey) {
      result[newKey] = entry.value;
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

Map<String, dynamic> _sanitizeRowData(
  MemoryTable table,
  Map<String, dynamic> rawData,
) {
  final sanitized = <String, dynamic>{};
  for (final column in table.columns) {
    final value = rawData[column.key];
    if (value == null) {
      sanitized[column.key] = '';
      continue;
    }
    if (column.type == 'number' && value is String) {
      final numValue = num.tryParse(value);
      sanitized[column.key] = numValue ?? value.trim();
      continue;
    }
    sanitized[column.key] = value;
  }
  return sanitized;
}

List<T> _reorderList<T>(List<T> source, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= source.length || newIndex < 0) {
    return source;
  }
  final mutable = [...source];
  final value = mutable.removeAt(oldIndex);
  if (newIndex > mutable.length) {
    newIndex = mutable.length;
  }
  mutable.insert(newIndex, value);
  return mutable;
}
