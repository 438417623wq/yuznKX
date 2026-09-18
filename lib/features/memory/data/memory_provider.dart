import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../chat/data/session_provider.dart';
import '../domain/models/memory_table.dart';

/// 记忆表格存储：键为**会话 ID**（每条对话一份独立记忆）。
const _memoryTablesBoxName = 'memory_tables_v3';

/// 记忆插件设置存储：键为**会话 ID**。
const _memorySettingsBoxName = 'memory_plugin_settings_v3';

/// 旧版（角色键）记忆存储，仅作为迁移来源，**不再写入**。
const _legacyMemoryTablesBoxName = 'memory_tables_v2';
const _legacyMemorySettingsBoxName = 'memory_plugin_settings_v2';

/// 迁移完成标记，存在 `settings` box 里。
const _memoryMigrationFlagKey = 'memory_v3_migrated';
const _migrationFlagBoxName = 'settings';

/// 保证「角色键 → 会话键」迁移只跑一次，且**先于任何读取**完成。
///
/// 用模块级 Future 缓存：迁移与两个 Notifier 的 `_init` 都是异步的。
/// 若不 await，就可能出现「Notifier 先读到空 → 写入默认模板 → 迁移发现目标
/// 已有数据于是跳过」的顺序，导致旧记忆永远迁不过来。
Future<void>? _memoryMigrationFuture;

Future<void> _ensureMemoryMigrated() {
  return _memoryMigrationFuture ??= _migrateMemoryToSessionKeyOnce();
}

int _readEpochMillis(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}

/// 一次性迁移：把旧的角色级记忆继承给该角色**最近更新**的那条会话。
///
/// 规则：
/// - 每个角色只挑一条会话继承（`updatedAt` 最大的那条），其余会话从默认模板开始；
/// - 旧的 v2 数据**保留不删**，作为回滚保险；
/// - 迁移成功后写入 `settings` box 的 [_memoryMigrationFlagKey] 标记。
///
/// 为什么必须用标记位、而不是「v3 没有数据就继承」：用户之后新建的对话
/// `updatedAt` 恰好是最新的，用后者判断会让**新对话误继承旧角色的记忆**。
Future<void> _migrateMemoryToSessionKeyOnce() async {
  final flagBox = await Hive.openBox(_migrationFlagBoxName);
  if (flagBox.get(_memoryMigrationFlagKey) == true) {
    return;
  }

  try {
    final legacyTables = await Hive.openBox(_legacyMemoryTablesBoxName);
    final legacySettings = await Hive.openBox(_legacyMemorySettingsBoxName);
    final tablesBox = await Hive.openBox(_memoryTablesBoxName);
    final settingsBox = await Hive.openBox(_memorySettingsBoxName);

    // 直接读 sessions box，避免依赖 Riverpod 容器（此时容器可能尚未就绪）。
    final sessionBox = await Hive.openBox('sessions');
    final latestByCharacter = <String, MapEntry<String, int>>{};
    for (final raw in sessionBox.values) {
      if (raw is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final id = (map['id'] ?? '').toString().trim();
      final characterId = (map['characterId'] ?? '').toString().trim();
      if (id.isEmpty || characterId.isEmpty) {
        continue;
      }
      final updatedAt = _readEpochMillis(map['updatedAt']);
      final current = latestByCharacter[characterId];
      if (current == null || updatedAt > current.value) {
        latestByCharacter[characterId] = MapEntry(id, updatedAt);
      }
    }

    for (final entry in latestByCharacter.entries) {
      final characterId = entry.key;
      final targetSessionId = entry.value.key;

      final legacyTableData = legacyTables.get(characterId);
      if (legacyTableData != null && tablesBox.get(targetSessionId) == null) {
        await tablesBox.put(targetSessionId, legacyTableData);
      }

      final legacySettingData = legacySettings.get(characterId);
      if (legacySettingData != null &&
          settingsBox.get(targetSessionId) == null) {
        await settingsBox.put(targetSessionId, legacySettingData);
      }
    }

    await flagBox.put(_memoryMigrationFlagKey, true);
  } catch (error) {
    // 不写标记，下次启动重试。已迁移成功的部分不会被重复覆盖（上面有 null 判断）。
    print('Memory migration to session key failed: $error');
  }
}

/// 删除某条会话时，清理它独占的记忆数据（表格 + 插件设置）。
///
/// 由 `SessionNotifier.deleteSession` 调用，保证「删对话即删记忆」。
/// 不清理会留下孤儿数据；更麻烦的是 sessionId 一旦被复用（导入备份、
/// 恢复数据等场景），旧记忆会串到新会话上。
Future<void> purgeSessionScopedMemory(String sessionId) async {
  try {
    final tablesBox = await Hive.openBox(_memoryTablesBoxName);
    if (tablesBox.containsKey(sessionId)) {
      await tablesBox.delete(sessionId);
    }
    final settingsBox = await Hive.openBox(_memorySettingsBoxName);
    if (settingsBox.containsKey(sessionId)) {
      await settingsBox.delete(sessionId);
    }
  } catch (error) {
    print('Failed to purge session-scoped memory for $sessionId: $error');
  }
}

/// 当前活跃会话的记忆表格。
///
/// 归属键是**会话 ID**：每条对话各持一份记忆，互不影响。
final memoryProvider =
    StateNotifierProvider<MemoryNotifier, List<MemoryTable>>((ref) {
  final sessionId = ref.watch(activeSessionIdProvider);
  return MemoryNotifier(sessionId);
});

/// 当前活跃会话的记忆插件设置（同样是会话级）。
final memoryPluginSettingsProvider =
    StateNotifierProvider<MemoryPluginSettingsNotifier, MemoryPluginSettings>(
        (ref) {
  final sessionId = ref.watch(activeSessionIdProvider);
  return MemoryPluginSettingsNotifier(sessionId);
});

List<MemoryTable> getDefaultMemoryTables() {
  return getDefaultMemoryTemplateBundle().tables;
}

MemoryTemplateBundle getDefaultMemoryTemplateBundle() {
  const settings = MemoryPluginSettings(
    isPluginEnabled: true,
    isAiReadTable: true,
    isAiWriteTable: true,
    deep: 2,
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

  // 每张表的 `note` 会原样进入 prompt 的 `Note:` 行，因此必须写成**给模型的
  // 写入规则**（何时插入 / 何时更新 / 何时清空），而不是给用户看的介绍。
  final tableSpecs = <Map<String, dynamic>>[
    {
      'name': '角色特征表格',
      'note': '每个主要角色一行。首次登场时插入；外貌或衣着变化、获得或失去临时BUFF时更新对应列；'
          'BUFF 失效后把该列清空。不要为同一角色重复插入新行。',
      'columns': ['角色名', '性别/年龄/身高/外貌', '性格', '长期备注', '临时BUFF', '当前衣着'],
      'required': true,
    },
    {
      'name': '人物关系表格',
      'note': '每对角色一行。关系或情感发生实质变化时才更新，不要每轮都改。'
          '「基础关系」是底层身份，「当前关系」是可流动的状态。',
      'columns': ['双方角色名', '基础关系(底层身份)', '当前关系(流动状态)', '相互情感态度'],
      'required': true,
    },
    {
      'name': '事件摘要表格',
      'note': '每完成一个场景或一次关键转折插入一行，保持简短。'
          '「第四面墙」记录读者/玩家视角的元信息（例如系统提示、存档点、作者注），没有就留空。',
      'columns': ['日期', '地点场景', '剧情摘要', '重要细节', '第四面墙'],
      'required': true,
    },
    {
      'name': '世界设定表格',
      'note': '只在出现新的世界观设定、规则、组织或地点时插入。已存在的设定改为更新。',
      'columns': ['设定名', '类型', '详细说明', '影响范围'],
      'required': false,
    },
    {
      'name': '重要物品表格',
      'note': '只记录具有剧情意义的物品。物品易主或失去效果时更新，不再重要时删除该行。',
      'columns': ['拥有者', '物品名', '描述', '效果/意义', '来源'],
      'required': false,
    },
    {
      'name': '约定表格',
      'note': '记录角色之间的约定与待办。完成或违约后更新「完成/待完成」与「结果」两列。',
      'columns': ['日期', '双方角色名', '任务/约定内容', '完成/待完成', '结果'],
      'required': false,
    },
    {
      'name': '大总结表格',
      'note': '用于阶段性压缩：把已经稳定、不再变化的多个事件摘要合并成一行，'
          '并在「事件摘要表格」里删除对应旧行。不要用它记录仍在进行中的事件。',
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
  /// 归属键：**会话 ID**。
  final String? sessionId;
  Box? _box;
  bool _ready = false;

  MemoryPluginSettingsNotifier(this.sessionId)
      : super(getDefaultMemoryTemplateBundle().settings) {
    _init();
  }

  Future<void> _init() async {
    if (sessionId == null) {
      state = getDefaultMemoryTemplateBundle().settings;
      return;
    }
    // 迁移必须先于首次读取，否则会把默认值抢先写进 v3，
    // 让迁移逻辑误判「该会话已有数据」而跳过。
    await _ensureMemoryMigrated();

    _box = await Hive.openBox(_memorySettingsBoxName);
    final raw = _box!.get(sessionId);
    state = raw is Map
        ? MemoryPluginSettings.fromJson(Map<String, dynamic>.from(raw))
        : getDefaultMemoryTemplateBundle().settings;
    _ready = true;
    if (raw is! Map) {
      await save();
    }
  }

  Future<void> save() async {
    // _ready 之前不落盘：那时 state 还是初始值，写下去会把已有数据抹掉。
    if (!_ready || sessionId == null || _box == null) {
      return;
    }
    await _box!.put(sessionId, state.toJson());
  }

  void update(MemoryPluginSettings newSettings) {
    state = newSettings;
    save();
  }

  void patch({
    bool? isPluginEnabled,
    bool? isAiReadTable,
    bool? isAiWriteTable,
    int? deep,
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
      deep: deep,
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
  /// 归属键：**会话 ID**。每条对话一份独立记忆。
  final String? sessionId;
  Box? _box;
  bool _ready = false;

  MemoryNotifier(this.sessionId) : super(const []) {
    _init();
  }

  Future<void> _init() async {
    if (sessionId == null) {
      state = const [];
      return;
    }

    // 迁移必须先于首次读取（原因见 _ensureMemoryMigrated 的注释）。
    await _ensureMemoryMigrated();

    _box = await Hive.openBox(_memoryTablesBoxName);
    final raw = _box!.get(sessionId);

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
        _ready = true;
        await save();
        return;
      }
    } else {
      state = getDefaultMemoryTables();
      _ready = true;
      await save();
      return;
    }
    _ready = true;
  }

  Future<void> save() async {
    // _ready 之前不落盘：那时 state 还是初始值（const []），
    // 写下去会把该会话已有的记忆抹成空。
    if (!_ready || sessionId == null || _box == null) {
      return;
    }
    await _box!.put(
      sessionId,
      state.map((table) => table.toJson()).toList(),
    );
    // 与 sessionProvider.updateSessionMessages 保持一致，显式 flush，
    // 避免高频写表格时丢数据。
    await _box!.flush();
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
    // 重新编号：注入文本用的是数组下标，但 `tableIndex` 会被写进导出的
    // JSON，若不跟着更新，导出后重新导入就会出现「表里写的 index 和实际
    // 顺序对不上」的隐性错位。
    _commit([
      for (var i = 0; i < mutable.length; i++)
        mutable[i].copyWith(tableIndex: i),
    ]);
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
                if (row.id == rowId)
                  // 只切启用状态属于「非内容变更」，不应刷新 updatedAt，
                  // 否则「N 分钟前更新」的展示会被自己点开关的行为污染。
                  row.copyWith(isEnabled: enabled, touchUpdatedAt: false)
                else
                  row
            ],
          )
        else
          table
    ]);
  }

  /// 清空某张表的全部记录，但保留表格本身、字段定义与样式。
  void clearRows(String tableId) {
    _commit([
      for (final table in state)
        if (table.id == tableId) table.copyWith(rows: const []) else table
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
    // 全部表格都被「参与对话注入」关掉时，不必再往 prompt 里塞规则头。
    if (!state.any((table) => table.behavior.toChat)) {
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
    buffer.writeln(
        '- A column label marked with * is required; tables marked (Required) should always be kept filled.');
    buffer.writeln();

    // 注意：`tableIndex` 必须是 **state 里的原始下标** —— AI 回写时
    // `_processInsert/_processUpdate/_processDelete` 都按 `state[tableIndex]`
    // 取值。因此这里只能「跳过」不参与注入的表，绝不能压缩下标。
    for (var tableIndex = 0; tableIndex < state.length; tableIndex++) {
      final table = state[tableIndex];
      if (!table.behavior.toChat) {
        continue;
      }
      buffer.writeln(
        '[$tableIndex] ${table.name}${table.behavior.required ? ' (Required)' : ''}',
      );
      buffer.writeln(
        'Columns: ${table.columns.asMap().entries.map((entry) => '${entry.key}:${entry.value.label}${entry.value.required ? '*' : ''}').join(' | ')}',
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
