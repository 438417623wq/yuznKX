import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/world_info/domain/models/world_info.dart';
import 'dart:math';

class MemoryVectorView extends StatefulWidget {
  final List<WorldInfoEntry> entries;

  const MemoryVectorView({super.key, required this.entries});

  @override
  State<MemoryVectorView> createState() => _MemoryVectorViewState();
}

class _MemoryVectorViewState extends State<MemoryVectorView> {
  final TextEditingController _queryController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  void _search() async {
    setState(() => _isSearching = true);
    // Simulate network/processing delay
    await Future.delayed(const Duration(milliseconds: 800));

    final query = _queryController.text.toLowerCase();
    final List<Map<String, dynamic>> results = [];
    final random = Random();

    for (var entry in widget.entries) {
      // Simulate similarity score
      double score = 0.0;
      if (query.isNotEmpty) {
        if (entry.content.toLowerCase().contains(query)) score += 0.4;
        if (entry.keys.any((k) => k.toLowerCase().contains(query))) score += 0.3;
        if (entry.comment.toLowerCase().contains(query)) score += 0.2;
        // Add some noise
        score += random.nextDouble() * 0.1;
      } else {
        score = random.nextDouble() * 0.5;
      }
      
      if (score > 1.0) score = 1.0;
      
      if (score > 0.1) {
        results.add({
          'entry': entry,
          'score': score,
        });
      }
    }

    results.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Panel: Search & Results
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('向量检索', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _queryController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入问题或关键词...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send, color: Colors.blueAccent),
                          onPressed: _search,
                        ),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isSearching 
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty 
                    ? const Center(child: Text('暂无匹配结果', style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final entry = item['entry'] as WorldInfoEntry;
                          final score = item['score'] as double;
                          
                          return Card(
                            color: Colors.white10,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(entry.comment.isEmpty ? '条目 #${entry.uid}' : entry.comment, 
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getScoreColor(score).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: _getScoreColor(score)),
                                        ),
                                        child: Text(
                                          '相似度: ${(score * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(color: _getScoreColor(score), fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: score,
                                      backgroundColor: Colors.white12,
                                      color: _getScoreColor(score),
                                      minHeight: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        
        // Right Panel: Visual Graph
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('关联图谱', style: TextStyle(color: Colors.white70)),
                ),
                Expanded(
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _GraphPainter(_results),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(double score) {
    if (score > 0.8) return Colors.greenAccent;
    if (score > 0.5) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

class _GraphPainter extends CustomPainter {
  final List<Map<String, dynamic>> results;
  final Random _random = Random(42); // Fixed seed for stability

  _GraphPainter(this.results);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1;

    // Draw Center Node (Query)
    paint.color = Colors.blueAccent;
    canvas.drawCircle(center, 8, paint);
    
    // Draw Result Nodes
    for (var i = 0; i < results.length; i++) {
      final score = results[i]['score'] as double;
      // Distance based on inverse score (higher score = closer)
      final distance = (1.0 - score) * (size.width / 2 * 0.8) + 40; 
      final angle = _random.nextDouble() * 2 * pi;
      
      final x = center.dx + cos(angle) * distance;
      final y = center.dy + sin(angle) * distance;
      final nodePos = Offset(x, y);

      // Draw Line
      linePaint.color = Colors.white.withOpacity(score * 0.5);
      canvas.drawLine(center, nodePos, linePaint);

      // Draw Node
      paint.color = _getScoreColor(score);
      canvas.drawCircle(nodePos, 5 + (score * 5), paint); // Size based on score
    }
  }

  Color _getScoreColor(double score) {
    if (score > 0.8) return Colors.greenAccent;
    if (score > 0.5) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

