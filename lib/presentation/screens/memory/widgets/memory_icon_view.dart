import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/world_info/domain/models/world_info.dart';
import 'dart:ui';

class MemoryIconView extends ConsumerWidget {
  final List<WorldInfoEntry> entries;
  final Function(WorldInfoEntry) onEdit;
  final Function(WorldInfoEntry) onDelete;
  final Function(int, int) onReorder;

  const MemoryIconView({
    super.key,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Center(child: Text('暂无记忆条目', style: TextStyle(color: Colors.white54)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const itemWidth = 100.0;
        final crossAxisCount = (width / (itemWidth + 16)).floor();
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(entries.length, (index) {
              final entry = entries[index];
              return _buildDraggableItem(context, entry, index);
            }),
          ),
        );
      },
    );
  }

  Widget _buildDraggableItem(BuildContext context, WorldInfoEntry entry, int index) {
    return LongPressDraggable<int>(
      data: index,
      feedback: Transform.scale(
        scale: 1.1,
        child: Material(
          color: Colors.transparent,
          child: _buildIconBadge(context, entry),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildIconBadge(context, entry),
      ),
      child: DragTarget<int>(
        onWillAccept: (data) => data != null && data != index,
        onAccept: (fromIndex) {
          onReorder(fromIndex, index);
        },
        builder: (context, candidateData, rejectedData) {
          return _buildIconBadge(context, entry, isHighlighted: candidateData.isNotEmpty);
        },
      ),
    );
  }

  Widget _buildIconBadge(BuildContext context, WorldInfoEntry entry, {bool isHighlighted = false}) {
    IconData icon = Icons.memory;
    Color color = Colors.blueAccent;
    
    final lowerComment = entry.comment.toLowerCase();
    if (lowerComment.contains('location') || lowerComment.contains('地点') || lowerComment.contains('place')) {
      icon = Icons.place;
      color = Colors.greenAccent;
    } else if (lowerComment.contains('person') || lowerComment.contains('角色') || lowerComment.contains('char') || lowerComment.contains('用户')) {
      icon = Icons.person;
      color = Colors.orangeAccent;
    } else if (lowerComment.contains('lore') || lowerComment.contains('设定') || lowerComment.contains('history')) {
      icon = Icons.history_edu;
      color = Colors.purpleAccent;
    } else if (lowerComment.contains('item') || lowerComment.contains('物品') || lowerComment.contains('obj')) {
      icon = Icons.inventory_2;
      color = Colors.tealAccent;
    }

    return Tooltip(
      message: "${entry.comment}\n关键词: ${entry.keys.join(', ')}",
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: InkWell(
        onTap: () => onEdit(entry),
        onLongPress: () {
          // Handled by Draggable, but we can add a secondary action if needed
          // Or we can move delete to a button
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(isHighlighted ? 0.4 : 0.2),
                color.withOpacity(isHighlighted ? 0.2 : 0.05),
              ],
            ),
            border: Border.all(
              color: color.withOpacity(isHighlighted ? 0.8 : 0.5),
              width: isHighlighted ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              Positioned(
                bottom: 8,
                left: 4,
                right: 4,
                child: Text(
                  entry.comment.isEmpty ? '#${entry.uid}' : entry.comment,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.disable)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 10, color: Colors.white),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => onDelete(entry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
