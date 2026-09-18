import 'package:uuid/uuid.dart';

class MemoryColumn {
  final String key;
  final String label;
  final String type; // text / number / boolean / datetime
  final bool required;
  final bool multiline;
  final double width;
  final String hint;

  const MemoryColumn({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.multiline = false,
    this.width = 180,
    this.hint = '',
  });

  factory MemoryColumn.fromJson(Map<String, dynamic> json,
      {int? fallbackIndex}) {
    final rawLabel = (json['label'] ?? json['name'] ?? json['title'] ?? '')
        .toString()
        .trim();
    final label = rawLabel.isEmpty ? '列${(fallbackIndex ?? 0) + 1}' : rawLabel;
    final rawKey = (json['key'] ?? '').toString().trim();
    final key =
        rawKey.isEmpty ? _buildColumnKey(label, fallbackIndex ?? 0) : rawKey;

    return MemoryColumn(
      key: key,
      label: label,
      type: (json['type'] ?? 'text').toString(),
      required: _asBool(json['required']) ?? false,
      multiline: _asBool(json['multiline']) ?? false,
      width: _asDouble(json['width']) ?? 180,
      hint: (json['hint'] ?? '').toString(),
    );
  }

  static MemoryColumn fromLabel(String label, int index) {
    final safeLabel = label.trim().isEmpty ? '列${index + 1}' : label.trim();
    return MemoryColumn(
      key: _buildColumnKey(safeLabel, index),
      label: safeLabel,
      multiline: looksLikeLongText(safeLabel),
      width: estimateColumnWidth(safeLabel),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        'required': required,
        'multiline': multiline,
        'width': width,
        'hint': hint,
      };

  MemoryColumn copyWith({
    String? key,
    String? label,
    String? type,
    bool? required,
    bool? multiline,
    double? width,
    String? hint,
  }) {
    return MemoryColumn(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
      multiline: multiline ?? this.multiline,
      width: width ?? this.width,
      hint: hint ?? this.hint,
    );
  }
}

class MemoryRow {
  final String id;
  final Map<String, dynamic> data;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  MemoryRow({
    required this.id,
    required this.data,
    this.isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MemoryRow.fromJson(Map<String, dynamic> json) {
    return MemoryRow(
      id: (json['id'] ?? const Uuid().v4()).toString(),
      data: Map<String, dynamic>.from(json['data'] ?? const {}),
      isEnabled: _asBool(json['isEnabled']) ?? true,
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
        'isEnabled': isEnabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 复制一份记录。
  ///
  /// [touchUpdatedAt] 决定是否刷新 `updatedAt`：
  /// - `true`（默认）→ 视为**内容变更**，时间戳刷新为当前时间；
  /// - `false` → 视为**非内容变更**（如仅切换启用状态、批量维护），时间戳保持原样。
  ///
  /// 为什么需要这个开关：旧实现无条件写 `updatedAt ?? DateTime.now()`，
  /// 于是 `toggleRow` 这种只切开关的操作也会被标记成「刚刚更新」，
  /// 让「N 分钟前更新」这类展示彻底失真。
  MemoryRow copyWith({
    Map<String, dynamic>? data,
    bool? isEnabled,
    DateTime? updatedAt,
    bool touchUpdatedAt = true,
  }) {
    return MemoryRow(
      id: id,
      data: data ?? this.data,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt,
      updatedAt: !touchUpdatedAt
          ? this.updatedAt
          : (updatedAt ?? DateTime.now()),
    );
  }
}

class MemoryTableStyle {
  final bool compact;
  final bool striped;
  final bool bordered;
  final bool softShadow;
  final int maxCellLines;
  final double rowHeight;
  final double columnSpacing;
  final String accentColor; // Hex
  final String headerColor; // Hex
  final String rowColor; // Hex
  final String alternateRowColor; // Hex

  /// 默认配色与全局主题（0xFF1A1B26 蓝紫系）同族，青绿仅作强调。
  static const String defaultAccentColor = '#24C3B5';
  static const String defaultHeaderColor = '#26273A';
  static const String defaultRowColor = '#232433';
  static const String defaultAlternateRowColor = '#1E1F2C';

  // 旧版（青黑系）默认值。样式色值随表格持久化，老会话的 JSON 里存的就是
  // 这些；解析时原样保留会让旧数据在新配色界面上变成突兀的深青块，
  // 所以按值迁移到新默认色。用户自定义过的颜色不会命中映射，不受影响。
  static const String _legacyHeaderColor = '#162831';
  static const String _legacyRowColor = '#0E151A';
  static const String _legacyAlternateRowColor = '#111E24';

  const MemoryTableStyle({
    this.compact = false,
    this.striped = true,
    this.bordered = true,
    this.softShadow = true,
    this.maxCellLines = 2,
    this.rowHeight = 56,
    this.columnSpacing = 20,
    this.accentColor = defaultAccentColor,
    this.headerColor = defaultHeaderColor,
    this.rowColor = defaultRowColor,
    this.alternateRowColor = defaultAlternateRowColor,
  });

  factory MemoryTableStyle.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MemoryTableStyle();
    }

    return MemoryTableStyle(
      compact: _asBool(json['compact']) ?? false,
      striped: _asBool(json['striped']) ?? true,
      bordered: _asBool(json['bordered']) ?? true,
      softShadow: _asBool(json['softShadow']) ?? true,
      maxCellLines: _asInt(json['maxCellLines'])?.clamp(1, 8) ?? 2,
      rowHeight: _asDouble(json['rowHeight'])?.clamp(40, 88) ?? 56,
      columnSpacing: _asDouble(json['columnSpacing'])?.clamp(8, 48) ?? 20,
      accentColor: _normalizeHex((json['accentColor'] ?? '').toString(),
          defaultAccentColor),
      headerColor: _migrateLegacyColor(
        _normalizeHex(
            (json['headerColor'] ?? '').toString(), defaultHeaderColor),
        legacy: _legacyHeaderColor,
        replacement: defaultHeaderColor,
      ),
      rowColor: _migrateLegacyColor(
        _normalizeHex((json['rowColor'] ?? '').toString(), defaultRowColor),
        legacy: _legacyRowColor,
        replacement: defaultRowColor,
      ),
      alternateRowColor: _migrateLegacyColor(
        _normalizeHex((json['alternateRowColor'] ?? '').toString(),
            defaultAlternateRowColor),
        legacy: _legacyAlternateRowColor,
        replacement: defaultAlternateRowColor,
      ),
    );
  }

  /// 把旧版默认色映射到新配色；其余值（含用户自定义色）原样返回。
  static String _migrateLegacyColor(
    String hex, {
    required String legacy,
    required String replacement,
  }) {
    return hex.toUpperCase() == legacy ? replacement : hex;
  }

  Map<String, dynamic> toJson() => {
        'compact': compact,
        'striped': striped,
        'bordered': bordered,
        'softShadow': softShadow,
        'maxCellLines': maxCellLines,
        'rowHeight': rowHeight,
        'columnSpacing': columnSpacing,
        'accentColor': accentColor,
        'headerColor': headerColor,
        'rowColor': rowColor,
        'alternateRowColor': alternateRowColor,
      };

  MemoryTableStyle copyWith({
    bool? compact,
    bool? striped,
    bool? bordered,
    bool? softShadow,
    int? maxCellLines,
    double? rowHeight,
    double? columnSpacing,
    String? accentColor,
    String? headerColor,
    String? rowColor,
    String? alternateRowColor,
  }) {
    return MemoryTableStyle(
      compact: compact ?? this.compact,
      striped: striped ?? this.striped,
      bordered: bordered ?? this.bordered,
      softShadow: softShadow ?? this.softShadow,
      maxCellLines: maxCellLines ?? this.maxCellLines,
      rowHeight: rowHeight ?? this.rowHeight,
      columnSpacing: columnSpacing ?? this.columnSpacing,
      accentColor: accentColor ?? this.accentColor,
      headerColor: headerColor ?? this.headerColor,
      rowColor: rowColor ?? this.rowColor,
      alternateRowColor: alternateRowColor ?? this.alternateRowColor,
    );
  }
}

class MemoryTableBehavior {
  final bool required;
  final bool toChat;
  final bool triggerSend;
  final int triggerSendDeep;
  final bool useCustomStyle;
  final bool alternateTable;
  final bool insertTable;
  final bool skipTop;

  const MemoryTableBehavior({
    this.required = false,
    this.toChat = true,
    this.triggerSend = false,
    this.triggerSendDeep = 1,
    this.useCustomStyle = false,
    this.alternateTable = false,
    this.insertTable = false,
    this.skipTop = false,
  });

  factory MemoryTableBehavior.fromJson(Map<String, dynamic>? json,
      {Map<String, dynamic>? fallbackTableJson}) {
    final data = json ?? const <String, dynamic>{};
    return MemoryTableBehavior(
      required: _asBool(data['required']) ??
          _asBool(data['Required']) ??
          _asBool(fallbackTableJson?['required']) ??
          _asBool(fallbackTableJson?['Required']) ??
          false,
      toChat: _asBool(data['toChat']) ??
          _asBool(data['tochat']) ??
          _asBool(fallbackTableJson?['toChat']) ??
          _asBool(fallbackTableJson?['tochat']) ??
          true,
      triggerSend: _asBool(data['triggerSend']) ??
          _asBool(fallbackTableJson?['triggerSend']) ??
          false,
      triggerSendDeep: _asInt(data['triggerSendDeep']) ??
          _asInt(fallbackTableJson?['triggerSendDeep']) ??
          1,
      useCustomStyle: _asBool(data['useCustomStyle']) ?? false,
      alternateTable: _asBool(data['alternateTable']) ?? false,
      insertTable: _asBool(data['insertTable']) ?? false,
      skipTop: _asBool(data['skipTop']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        // ⛔ 这里**只输出仍然生效的字段**。
        // `triggerSend` / `triggerSendDeep` / `useCustomStyle` / `alternateTable` /
        // `insertTable` / `skipTop` 全部无 UI、无逻辑消费，但旧实现照样写进导出
        // JSON —— 用户会以为它们可调，实际毫无作用。`fromJson` 仍然读它们，
        // 因此旧数据的兼容性不受影响，只是导出结果变干净了。
        'required': required,
        'toChat': toChat,
      };

  MemoryTableBehavior copyWith({
    bool? required,
    bool? toChat,
    bool? triggerSend,
    int? triggerSendDeep,
    bool? useCustomStyle,
    bool? alternateTable,
    bool? insertTable,
    bool? skipTop,
  }) {
    return MemoryTableBehavior(
      required: required ?? this.required,
      toChat: toChat ?? this.toChat,
      triggerSend: triggerSend ?? this.triggerSend,
      triggerSendDeep: triggerSendDeep ?? this.triggerSendDeep,
      useCustomStyle: useCustomStyle ?? this.useCustomStyle,
      alternateTable: alternateTable ?? this.alternateTable,
      insertTable: insertTable ?? this.insertTable,
      skipTop: skipTop ?? this.skipTop,
    );
  }
}

class MemoryTable {
  final String id;
  final int tableIndex;
  final String name;
  final String note;
  final String initNode;
  final String insertNode;
  final String updateNode;
  final String deleteNode;
  final List<MemoryColumn> columns;
  final List<MemoryRow> rows;
  final bool isEnabled;
  final MemoryTableBehavior behavior;
  final MemoryTableStyle style;

  MemoryTable({
    required this.id,
    required this.tableIndex,
    required this.name,
    required this.columns,
    required this.rows,
    this.note = '',
    this.initNode = '',
    this.insertNode = '',
    this.updateNode = '',
    this.deleteNode = '',
    this.isEnabled = true,
    this.behavior = const MemoryTableBehavior(),
    this.style = const MemoryTableStyle(),
  });

  factory MemoryTable.fromJson(Map<String, dynamic> json,
      {int? fallbackIndex}) {
    final tableIndex = _asInt(json['tableIndex']) ?? fallbackIndex ?? 0;
    final rawId = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? json['tableName'] ?? '未命名表格').toString();
    final id = rawId.isNotEmpty ? rawId : 'table_${tableIndex}_$name';

    final columns = _parseColumns(json['columns']);
    final rows = _parseRows(json['rows']);

    return MemoryTable(
      id: id,
      tableIndex: tableIndex,
      name: name,
      note: (json['note'] ?? '').toString(),
      initNode: (json['initNode'] ?? '').toString(),
      insertNode: (json['insertNode'] ?? '').toString(),
      updateNode: (json['updateNode'] ?? '').toString(),
      deleteNode: (json['deleteNode'] ?? '').toString(),
      columns: columns,
      rows: rows,
      isEnabled: _asBool(json['isEnabled']) ?? _asBool(json['enable']) ?? true,
      behavior: MemoryTableBehavior.fromJson(
        _asMap(json['config']),
        fallbackTableJson: json,
      ),
      style: MemoryTableStyle.fromJson(_asMap(json['style'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableIndex': tableIndex,
        'name': name,
        'tableName': name,
        'note': note,
        // `initNode` / `insertNode` / `updateNode` / `deleteNode` 是旧版
        // 自定义指令模板的残留，已无任何消费者。停止写入以免污染导出 JSON；
        // `fromJson` 仍会读取，旧数据不会丢。
        'columns': columns.map((e) => e.toJson()).toList(),
        'rows': rows.map((e) => e.toJson()).toList(),
        'isEnabled': isEnabled,
        'enable': isEnabled,
        'Required': behavior.required,
        'tochat': behavior.toChat,
        'config': behavior.toJson(),
        'style': style.toJson(),
      };

  MemoryTable copyWith({
    int? tableIndex,
    String? name,
    String? note,
    String? initNode,
    String? insertNode,
    String? updateNode,
    String? deleteNode,
    List<MemoryColumn>? columns,
    List<MemoryRow>? rows,
    bool? isEnabled,
    MemoryTableBehavior? behavior,
    MemoryTableStyle? style,
  }) {
    return MemoryTable(
      id: id,
      tableIndex: tableIndex ?? this.tableIndex,
      name: name ?? this.name,
      note: note ?? this.note,
      initNode: initNode ?? this.initNode,
      insertNode: insertNode ?? this.insertNode,
      updateNode: updateNode ?? this.updateNode,
      deleteNode: deleteNode ?? this.deleteNode,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      isEnabled: isEnabled ?? this.isEnabled,
      behavior: behavior ?? this.behavior,
      style: style ?? this.style,
    );
  }

  static List<MemoryColumn> _parseColumns(dynamic rawColumns) {
    if (rawColumns is! List) {
      return const [];
    }

    final columns = <MemoryColumn>[];
    for (var i = 0; i < rawColumns.length; i++) {
      final item = rawColumns[i];
      if (item is String) {
        columns.add(MemoryColumn.fromLabel(item, i));
      } else if (item is Map) {
        columns.add(MemoryColumn.fromJson(Map<String, dynamic>.from(item),
            fallbackIndex: i));
      }
    }
    return columns;
  }

  static List<MemoryRow> _parseRows(dynamic rawRows) {
    if (rawRows is! List) {
      return const [];
    }
    final rows = <MemoryRow>[];
    for (final item in rawRows) {
      if (item is Map) {
        rows.add(MemoryRow.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return rows;
  }
}

/// 记忆系统的运行设置。
///
/// 说明：原先还有 9 个字段（injectionMode / messageTemplate / confirmBeforeExecution /
/// useMainApi / useTokenLimit / rebuildTokenLimitValue / toChatContainer /
/// tableToChatCanEdit / tableToChatMode），但它们从未被任何逻辑消费 ——
/// 要么零引用，要么只在设置界面里显示自己。已一并移除，读取旧数据时会自动忽略这些键。
class MemoryPluginSettings {
  final bool isPluginEnabled;
  final bool isAiReadTable;
  final bool isAiWriteTable;
  final int deep;
  final bool isHistoryRangeLimitEnabled;
  final int historyRangeStartFloor;
  final int historyRangeEndFloor;
  final bool isKeepLatestEnabled;
  final int keepLatestFloors;

  const MemoryPluginSettings({
    this.isPluginEnabled = true,
    this.isAiReadTable = true,
    this.isAiWriteTable = true,
    this.deep = 2,
    this.isHistoryRangeLimitEnabled = true,
    this.historyRangeStartFloor = 0,
    this.historyRangeEndFloor = -1,
    this.isKeepLatestEnabled = false,
    this.keepLatestFloors = 3,
  });

  factory MemoryPluginSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MemoryPluginSettings();
    }
    return MemoryPluginSettings(
      isPluginEnabled: _asBool(json['isPluginEnabled']) ??
          _asBool(json['is_plugin_enabled']) ??
          true,
      isAiReadTable: _asBool(json['isAiReadTable']) ?? true,
      isAiWriteTable: _asBool(json['isAiWriteTable']) ?? true,
      deep: _asInt(json['deep']) ?? 2,
      isHistoryRangeLimitEnabled:
          _asBool(json['is_history_range_limit_enabled']) ??
              _asBool(json['isHistoryRangeLimitEnabled']) ??
              true,
      historyRangeStartFloor: _asInt(json['history_range_start_floor']) ??
          _asInt(json['historyRangeStartFloor']) ??
          0,
      historyRangeEndFloor: _asInt(json['history_range_end_floor']) ??
          _asInt(json['historyRangeEndFloor']) ??
          -1,
      isKeepLatestEnabled: _asBool(json['is_keep_latest_enabled']) ??
          _asBool(json['isKeepLatestEnabled']) ??
          false,
      keepLatestFloors: _asInt(json['keep_latest_floors']) ??
          _asInt(json['keepLatestFloors']) ??
          3,
    );
  }

  Map<String, dynamic> toJson() => {
        'isPluginEnabled': isPluginEnabled,
        'is_plugin_enabled': isPluginEnabled,
        'isAiReadTable': isAiReadTable,
        'isAiWriteTable': isAiWriteTable,
        'deep': deep,
        'isHistoryRangeLimitEnabled': isHistoryRangeLimitEnabled,
        'is_history_range_limit_enabled': isHistoryRangeLimitEnabled,
        'historyRangeStartFloor': historyRangeStartFloor,
        'history_range_start_floor': historyRangeStartFloor,
        'historyRangeEndFloor': historyRangeEndFloor,
        'history_range_end_floor': historyRangeEndFloor,
        'isKeepLatestEnabled': isKeepLatestEnabled,
        'is_keep_latest_enabled': isKeepLatestEnabled,
        'keepLatestFloors': keepLatestFloors,
        'keep_latest_floors': keepLatestFloors,
      };

  MemoryPluginSettings copyWith({
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
    return MemoryPluginSettings(
      isPluginEnabled: isPluginEnabled ?? this.isPluginEnabled,
      isAiReadTable: isAiReadTable ?? this.isAiReadTable,
      isAiWriteTable: isAiWriteTable ?? this.isAiWriteTable,
      deep: deep ?? this.deep,
      isHistoryRangeLimitEnabled:
          isHistoryRangeLimitEnabled ?? this.isHistoryRangeLimitEnabled,
      historyRangeStartFloor:
          historyRangeStartFloor ?? this.historyRangeStartFloor,
      historyRangeEndFloor: historyRangeEndFloor ?? this.historyRangeEndFloor,
      isKeepLatestEnabled: isKeepLatestEnabled ?? this.isKeepLatestEnabled,
      keepLatestFloors: keepLatestFloors ?? this.keepLatestFloors,
    );
  }
}

class MemoryTemplateBundle {
  final List<MemoryTable> tables;
  final MemoryPluginSettings settings;

  const MemoryTemplateBundle({
    required this.tables,
    required this.settings,
  });
}

String _buildColumnKey(String label, int index) {
  final base = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return base.isEmpty ? 'col_$index' : base;
}

/// 判定字段是否应该用多行输入框。
///
/// 原实现只看「描述 / 备注」两个字样，导致「剧情摘要」「详细说明」
/// 「事件摘要总结」「重要细节」「相互情感态度」这些内容最长的字段反而
/// 是单行输入框。这里改成关键词命中，覆盖默认模板里的全部长文本字段。
bool looksLikeLongText(String label) {
  const keywords = <String>[
    '描述',
    '备注',
    '摘要',
    '说明',
    '细节',
    '态度',
    '总结',
    '内容',
    '详情',
    '剧情',
    '纪要',
    '经历',
    '设定',
    '外貌',
    '性格',
  ];
  return keywords.any(label.contains);
}

/// 估算表格视图里的列宽。
///
/// 旧实现用 `label.length > 8 ? 220 : 180`，对中文是**反向**的：
/// 「性格」2 个字符占 180px（中文实际只需约 40px，白占 140px），
/// 而「事件名称(持续时间)」11 个字符也才 220px（实际不够）。
/// 这里按显示宽度估算 —— 中日韩文字与全角标点按 2 个单位计。
double estimateColumnWidth(String label) {
  var units = 0.0;
  for (final rune in label.runes) {
    final isWide = (rune >= 0x1100 && rune <= 0x115F) || rune >= 0x2E80;
    units += isWide ? 2 : 1;
  }
  return (units * 12 + 28).clamp(110.0, 300.0);
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _asDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

String _normalizeHex(String value, String fallback) {
  final raw = value.trim();
  if (raw.isEmpty) return fallback;
  final normalized =
      raw.startsWith('#') ? raw.toUpperCase() : '#${raw.toUpperCase()}';
  if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)) {
    return normalized;
  }
  return fallback;
}
