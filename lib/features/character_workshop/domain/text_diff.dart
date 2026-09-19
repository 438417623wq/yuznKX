/// 行级文本 diff（LCS）。
///
/// **为什么自己写**：只为了「应用修复前看一眼改了什么」这一个场景引一个第三方
/// diff 包不划算；而且 diff 是纯算法，本地跑零成本、零网络。
///
/// ⛔ LCS 是 O(n·m)。面板 HTML 几百行没问题，但真遇到几千行的输入会吃掉
/// 几十 MB —— 所以有 [maxCells] 保护，超了就退化成「整段替换」。
library;

/// 一行的差异类型。
enum DiffKind {
  /// 两边都有（上下文行）。
  keep,

  /// 只在旧版里有。
  remove,

  /// 只在新版里有。
  add,
}

/// diff 结果里的一行。
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DiffKind kind;
  final String text;

  /// 在旧文本里的行号（从 1 起）。[DiffKind.add] 时为 null。
  final int? oldLine;

  /// 在新文本里的行号（从 1 起）。[DiffKind.remove] 时为 null。
  final int? newLine;

  bool get isChange => kind != DiffKind.keep;
}

/// 行级 diff 工具。
class TextDiff {
  const TextDiff._();

  /// LCS 表格的单元格上限。超过就退化 —— 见文件头说明。
  static const int maxCells = 2000000;

  /// 计算 [oldText] → [newText] 的行级 diff。
  static List<DiffLine> compute(String oldText, String newText) {
    final a = oldText.split('\n');
    final b = newText.split('\n');

    if (a.length * b.length > maxCells) {
      return _fallback(a, b);
    }

    final n = a.length;
    final m = b.length;

    // dp[i][j] = a[i..] 与 b[j..] 的最长公共子序列长度。
    // 从后往前填，回溯时就能正着走。
    final dp = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
      growable: false,
    );
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }

    final result = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        result.add(
          DiffLine(
            kind: DiffKind.keep,
            text: a[i],
            oldLine: i + 1,
            newLine: j + 1,
          ),
        );
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        result.add(DiffLine(kind: DiffKind.remove, text: a[i], oldLine: i + 1));
        i++;
      } else {
        result.add(DiffLine(kind: DiffKind.add, text: b[j], newLine: j + 1));
        j++;
      }
    }
    while (i < n) {
      result.add(DiffLine(kind: DiffKind.remove, text: a[i], oldLine: i + 1));
      i++;
    }
    while (j < m) {
      result.add(DiffLine(kind: DiffKind.add, text: b[j], newLine: j + 1));
      j++;
    }
    return result;
  }

  /// 统计增删行数。
  static DiffStats statsOf(List<DiffLine> lines) {
    var added = 0;
    var removed = 0;
    for (final line in lines) {
      if (line.kind == DiffKind.add) {
        added++;
      } else if (line.kind == DiffKind.remove) {
        removed++;
      }
    }
    return DiffStats(added: added, removed: removed);
  }

  /// 一句话摘要，如 `+5 行 / -2 行`。
  static String summarize(List<DiffLine> lines) {
    final stats = statsOf(lines);
    if (stats.isEmpty) {
      return '没有变化';
    }
    return '+${stats.added} 行 / -${stats.removed} 行';
  }

  /// 折叠连续未变化的行，只保留变更点前后 [context] 行。
  ///
  /// 返回的列表里 [DiffKind.keep] 且 `text == ellipsisMarker` 的行是折叠标记。
  static const String ellipsisMarker = '⋯⋯';

  static List<DiffLine> collapse(
    List<DiffLine> lines, {
    int context = 2,
  }) {
    final changed = <int>[];
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].isChange) {
        changed.add(index);
      }
    }
    if (changed.isEmpty) {
      return lines.take(context * 2).toList(growable: false);
    }

    final keep = <int>{};
    for (final index in changed) {
      for (var offset = -context; offset <= context; offset++) {
        final target = index + offset;
        if (target >= 0 && target < lines.length) {
          keep.add(target);
        }
      }
    }

    final sorted = keep.toList()..sort();
    final result = <DiffLine>[];
    int? previous;
    for (final index in sorted) {
      if (previous != null && index > previous + 1) {
        result.add(
          const DiffLine(kind: DiffKind.keep, text: ellipsisMarker),
        );
      }
      result.add(lines[index]);
      previous = index;
    }
    return result;
  }

  /// 超长文本的退化路径：不找公共子序列，直接「全删 + 全增」。
  static List<DiffLine> _fallback(List<String> a, List<String> b) {
    return <DiffLine>[
      for (var i = 0; i < a.length; i++)
        DiffLine(kind: DiffKind.remove, text: a[i], oldLine: i + 1),
      for (var j = 0; j < b.length; j++)
        DiffLine(kind: DiffKind.add, text: b[j], newLine: j + 1),
    ];
  }
}

/// 增删行统计。
class DiffStats {
  const DiffStats({required this.added, required this.removed});

  final int added;
  final int removed;

  bool get isEmpty => added == 0 && removed == 0;

  @override
  String toString() => '+$added / -$removed';
}
