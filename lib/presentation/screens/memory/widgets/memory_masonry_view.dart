import 'package:flutter/material.dart';
import 'package:silly_tavern_flutter/features/world_info/domain/models/world_info.dart';

class MemoryMasonryView extends StatelessWidget {
  final List<WorldInfoEntry> entries;
  final Function(WorldInfoEntry) onEdit;

  const MemoryMasonryView({
    super.key,
    required this.entries,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('暂无记忆条目', style: TextStyle(color: Colors.white54)),
      );
    }

    final leftColumn = <WorldInfoEntry>[];
    final rightColumn = <WorldInfoEntry>[];

    for (var i = 0; i < entries.length; i++) {
      if (i % 2 == 0) {
        leftColumn.add(entries[i]);
      } else {
        rightColumn.add(entries[i]);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: leftColumn.map((e) => _buildCard(context, e)).toList(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: rightColumn.map((e) => _buildCard(context, e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, WorldInfoEntry entry) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = !entry.disable;

    return GestureDetector(
      onTap: () => onEdit(entry),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isEnabled ? colorScheme.surfaceVariant : colorScheme.surfaceVariant.withOpacity(0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Image Placeholder (Random Gradient)
            Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                gradient: LinearGradient(
                  colors: [
                    _getColorForEntry(entry.comment).withOpacity(0.8),
                    _getColorForEntry(entry.keys.firstOrNull ?? '').withOpacity(0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Icon(
                  isEnabled ? Icons.memory : Icons.memory_outlined,
                  color: Colors.white.withOpacity(0.7),
                  size: 24,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.comment.isNotEmpty ? entry.comment : '未命名记忆',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (entry.keys.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: entry.keys.take(3).map((key) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          key,
                          style: TextStyle(fontSize: 10, color: colorScheme.primary),
                        ),
                      )).toList(),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    entry.content,
                    style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForEntry(String text) {
    if (text.isEmpty) return Colors.blueGrey;
    final hash = text.hashCode;
    final colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.orange, Colors.deepOrange, Colors.brown,
    ];
    return colors[hash.abs() % colors.length];
  }
}
