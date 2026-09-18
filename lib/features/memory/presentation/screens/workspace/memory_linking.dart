import '../../../domain/models/memory_table.dart';

/// 一条「关联记录」的跳转目标。
///
/// 关联关系**不落库**：完全由运行时按字段值自动推导，
/// 因此不新增数据模型字段、不改 `MemoryTable.toJson` 形状、旧数据零迁移。
class MemoryLinkTarget {
  const MemoryLinkTarget({
    required this.tableId,
    required this.tableName,
    required this.rowId,
    required this.title,
    required this.matchedColumns,
    required this.reason,
  });

  final String tableId;
  final String tableName;
  final String rowId;
  final String title;

  /// 命中的本表字段标签，用于在 UI 上解释「为什么算关联」。
  final List<String> matchedColumns;

  /// 关联来源说明，例如「同表格」「角色名命中」。
  final String reason;
}

/// 记录关联推导。
///
/// 规则（按优先级）：
/// 1. **跨表格**：本表某字段的值，命中另一张表某条记录的**主键值**
///    → 视为跨表关联（例如「人物关系.对象」= 角色特征表的「林深」）；
/// 2. **同表格**：本表某字段的值，命中同表另一条记录的主键值
///    → 视为同表关联（例如「事件摘要.相关角色」指向另一条事件）。
///
/// 之所以用「值匹配」而不是显式外键：用户明确要求不改数据模型，
/// 而记忆表格本身就是 AI 自由填写的结构，没有稳定的外键语义。
///
/// ⚠️ 只拿**主键值**当匹配目标（而不是任意字段值），是因为任意字段匹配会把
/// 「两条记录恰好都写了『笑』」这种散文重叠误判成关联，噪声极大。
/// 主键列是「名称」语义（由 `_resolvePrimaryColumn` 按「名/标题/事件…」识别），
/// 命中它才是真正的「提到了某个实体」。
class MemoryLinker {
  const MemoryLinker._();

  /// 单条记录最多返回多少个关联，避免详情面板被刷爆。
  static const int maxLinks = 6;

  /// 关联判定的最小字面长度：太短的值（如「1」「是」）会命中的噪声太多。
  static const int minTokenLength = 2;

  /// 找出 [source] 表中 [row] 的所有关联记录（出边：我引用了谁）。
  ///
  /// [tables] 为全部表格，[primaryKeyOf] 提供「哪一列是这个表的主键」的判断，
  /// 由调用方注入（复用页面里的 `_resolvePrimaryColumn` 语义）。
  static List<MemoryLinkTarget> resolve({
    required List<MemoryTable> tables,
    required MemoryTable source,
    required MemoryRow row,
    required MemoryColumn? Function(MemoryTable table) primaryKeyOf,
  }) {
    final sourcePrimary = primaryKeyOf(source);

    // 本记录里「指向别处实体」的候选值：所有非主键字段的值。
    // 值 -> 来源字段标签，用于解释关联理由。
    final tokens = <String, String>{};
    for (final column in source.columns) {
      if (sourcePrimary != null && column.key == sourcePrimary.key) {
        continue;
      }
      final normalized = normalizeToken((row.data[column.key] ?? '').toString());
      if (normalized.length < minTokenLength ||
          _isGenericValue(normalized)) {
        continue;
      }
      tokens.putIfAbsent(normalized, () => column.label);
    }

    if (tokens.isEmpty) {
      return const [];
    }

    final results = <MemoryLinkTarget>[];

    for (final table in tables) {
      final targetPrimary = primaryKeyOf(table);
      if (targetPrimary == null) {
        continue;
      }

      for (final candidate in table.rows) {
        if (table.id == source.id && candidate.id == row.id) {
          continue;
        }

        // 只拿候选记录的**主键值**去匹配 —— 见类文档的精确性说明。
        final primaryValue =
            normalizeToken((candidate.data[targetPrimary.key] ?? '').toString());
        if (primaryValue.length < minTokenLength) {
          continue;
        }
        final matchedBy = tokens[primaryValue];
        if (matchedBy == null) {
          continue;
        }

        final isSameTable = table.id == source.id;
        results.add(
          MemoryLinkTarget(
            tableId: table.id,
            tableName: table.name,
            rowId: candidate.id,
            title: _titleOf(candidate, targetPrimary),
            matchedColumns: [matchedBy, targetPrimary.label],
            reason: isSameTable
                ? '同表格 · $matchedBy'
                : '$matchedBy → ${table.name}.${targetPrimary.label}',
          ),
        );
      }
    }

    results.sort((a, b) {
      // 同表关联排前面（通常更相关），其次按标题稳定排序。
      final aSame = a.tableId == source.id ? 0 : 1;
      final bSame = b.tableId == source.id ? 0 : 1;
      if (aSame != bSame) {
        return aSame - bSame;
      }
      return a.title.compareTo(b.title);
    });

    return results.take(maxLinks).toList();
  }

  /// 反向引用：哪些记录提到了**当前这条**记录。
  ///
  /// 与 [resolve] 的差别是方向相反 —— 前者是「我引用了谁」，
  /// 这里是「谁引用了我」。详情面板两个都展示，才叫双向。
  ///
  /// 匹配目标同样是本记录的**主键值**（实体名），理由见类文档。
  static List<MemoryLinkTarget> resolveBacklinks({
    required List<MemoryTable> tables,
    required MemoryTable source,
    required MemoryRow row,
    required MemoryColumn? Function(MemoryTable table) primaryKeyOf,
  }) {
    final sourcePrimary = primaryKeyOf(source);
    if (sourcePrimary == null) {
      return const [];
    }
    final normalizedTitle =
        normalizeToken((row.data[sourcePrimary.key] ?? '').toString());
    if (normalizedTitle.length < minTokenLength ||
        _isGenericValue(normalizedTitle)) {
      return const [];
    }

    final results = <MemoryLinkTarget>[];

    for (final table in tables) {
      final targetPrimary = primaryKeyOf(table);

      for (final candidate in table.rows) {
        if (table.id == source.id && candidate.id == row.id) {
          continue;
        }

        // 反向：在这条候选记录的**非主键字段**里找有没有提到我。
        for (final column in table.columns) {
          if (targetPrimary != null && column.key == targetPrimary.key) {
            continue;
          }
          final normalized =
              normalizeToken((candidate.data[column.key] ?? '').toString());
          if (normalized.length < minTokenLength) {
            continue;
          }
          if (normalized != normalizedTitle) {
            continue;
          }

          results.add(
            MemoryLinkTarget(
              tableId: table.id,
              tableName: table.name,
              rowId: candidate.id,
              title: _titleOf(candidate, targetPrimary),
              matchedColumns: [column.label],
              reason: '被 ${table.name}.${column.label} 引用',
            ),
          );
          break;
        }
      }
    }

    results.sort((a, b) => a.title.compareTo(b.title));
    return results.take(maxLinks).toList();
  }

  /// 归一化：去空白、去首尾标点、小写。中文不受影响。
  static String normalizeToken(String raw) {
    var value = raw.trim().toLowerCase();
    // 去掉包裹性标点，避免「「林深」」和「林深」匹配不上。
    value = value.replaceAll(RegExp(r'^[「『\[\(（"' "'" r'“]+'), '');
    value = value.replaceAll(RegExp(r'[」』\]\)）"' "'" r'”]+$'), '');
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    return value.trim();
  }

  /// 泛用值黑名单：这些词出现在多条记录里属于正常写作，不算关联。
  static const Set<String> _generic = {
    '无',
    '没有',
    '未知',
    '暂无',
    'null',
    'none',
    'n/a',
    '未知/其他',
    '其他',
    '非',
    '是',
    '否',
    'true',
    'false',
    '待定',
    '未填写',
  };

  static bool _isGenericValue(String normalized) {
    return _generic.contains(normalized);
  }

  /// 记录标题：主键列的值，退化到「空」。
  static String _titleOf(MemoryRow row, MemoryColumn? primary) {
    if (primary == null) {
      return '';
    }
    return (row.data[primary.key] ?? '').toString().trim();
  }

  /// 计算单条记录的「完成度」= 非空字段数 / 总字段数。
  ///
  /// 用于关卡地图的进度条。0 列表格返回 0，避免除零。
  static double rowCompleteness(MemoryTable table, MemoryRow row) {
    if (table.columns.isEmpty) {
      return 0;
    }
    var filled = 0;
    for (final column in table.columns) {
      if ((row.data[column.key] ?? '').toString().trim().isNotEmpty) {
        filled++;
      }
    }
    return filled / table.columns.length;
  }

  /// 计算整表的「完成度」= 所有记录非空字段数 / (记录数 × 字段数)。
  ///
  /// 空表返回 0 —— 用于关卡地图显示「还没开始」。
  static double tableCompleteness(MemoryTable table) {
    if (table.rows.isEmpty || table.columns.isEmpty) {
      return 0;
    }
    var filled = 0;
    for (final row in table.rows) {
      for (final column in table.columns) {
        if ((row.data[column.key] ?? '').toString().trim().isNotEmpty) {
          filled++;
        }
      }
    }
    return filled / (table.rows.length * table.columns.length);
  }
}
