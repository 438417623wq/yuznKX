import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:silly_tavern_flutter/features/world_info/domain/models/world_info.dart';

class MemoryDashboardView extends StatelessWidget {
  final List<WorldInfoEntry> entries;
  final Function(bool enableAll) onToggleAll;

  const MemoryDashboardView({
    super.key,
    required this.entries,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final enabled = entries.where((e) => !e.disable).length;
    final disabled = total - enabled;
    
    // Calculate keyword frequency
    final Map<String, int> keywordCounts = {};
    for (var e in entries) {
      for (var k in e.keys) {
        keywordCounts[k] = (keywordCounts[k] ?? 0) + 1;
      }
    }
    final sortedKeywords = keywordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overview Cards
          Row(
            children: [
              _buildStatCard(context, '总计', '$total', Colors.blue),
              const SizedBox(width: 8),
              _buildStatCard(context, '启用', '$enabled', Colors.green),
              const SizedBox(width: 8),
              _buildStatCard(context, '禁用', '$disabled', Colors.red),
            ],
          ),
          const SizedBox(height: 24),
          
          // 2. Pie Chart Section
          const Text('记忆分布', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 200,
              width: 200,
              child: CustomPaint(
                painter: _PieChartPainter(
                  values: [enabled.toDouble(), disabled.toDouble()],
                  colors: [Colors.green, Colors.red],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(Colors.green, '启用'),
              const SizedBox(width: 16),
              _buildLegendItem(Colors.red, '禁用'),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // 3. Top Keywords
          const Text('热门关键词', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sortedKeywords.take(10).map((e) {
              return Chip(
                label: Text('${e.key} (${e.value})'),
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              );
            }).toList(),
          ),
          
          const SizedBox(height: 32),
          
          // 4. Global Controls
          const Text('全局控制', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('启用所有记忆'),
                  subtitle: const Text('启用当前书中的所有条目'),
                  onTap: () => onToggleAll(true),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined),
                  title: const Text('禁用所有记忆'),
                  subtitle: const Text('禁用当前书中的所有条目'),
                  onTap: () => onToggleAll(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  _PieChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (sum, val) => sum + val);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
