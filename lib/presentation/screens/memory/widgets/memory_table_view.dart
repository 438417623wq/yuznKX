import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/world_info/domain/models/world_info.dart';

class MemoryTableView extends StatefulWidget {
  final List<WorldInfoEntry> entries;
  final Function(WorldInfoEntry) onEdit;
  final Function(WorldInfoEntry) onDelete;
  final Function(WorldInfoEntry, bool) onToggleActive;

  const MemoryTableView({
    super.key,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  State<MemoryTableView> createState() => _MemoryTableViewState();
}

class _MemoryTableViewState extends State<MemoryTableView> {
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // Filter and Sort
    List<WorldInfoEntry> filtered = widget.entries.where((e) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return e.comment.toLowerCase().contains(q) ||
             e.keys.any((k) => k.toLowerCase().contains(q)) ||
             e.content.toLowerCase().contains(q);
    }).toList();

    // Sort
    filtered.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0: // ID
          cmp = a.uid.compareTo(b.uid);
          break;
        case 1: // Comment
          cmp = a.comment.compareTo(b.comment);
          break;
        case 2: // Keys
          cmp = (a.keys.firstOrNull ?? '').compareTo(b.keys.firstOrNull ?? '');
          break;
        case 3: // Active
          cmp = (a.disable ? 1 : 0).compareTo(b.disable ? 1 : 0);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '搜索记忆...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        
        // Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                headingRowColor: MaterialStateProperty.all(Colors.white10),
                dataRowColor: MaterialStateProperty.resolveWith((states) {
                   if (states.contains(MaterialState.hovered)) return Colors.white12;
                   return null; // transparent
                }),
                columns: [
                  DataColumn(
                    label: const Text('ID', style: TextStyle(color: Colors.white)),
                    onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; }),
                  ),
                  DataColumn(
                    label: const Text('名称', style: TextStyle(color: Colors.white)),
                    onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; }),
                  ),
                  DataColumn(
                    label: const Text('关键词', style: TextStyle(color: Colors.white)),
                    onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; }),
                  ),
                  DataColumn(
                    label: const Text('状态', style: TextStyle(color: Colors.white)),
                    onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; }),
                  ),
                  const DataColumn(label: Text('操作', style: TextStyle(color: Colors.white))),
                ],
                rows: filtered.map((e) {
                  return DataRow(
                    cells: [
                      DataCell(Text(e.uid.toString(), style: const TextStyle(color: Colors.white70))),
                      DataCell(
                        Text(e.comment.isEmpty ? '-' : e.comment, style: const TextStyle(color: Colors.white)),
                        onTap: () => widget.onEdit(e),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            e.keys.join(', '), 
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                      DataCell(
                        Switch(
                          value: !e.disable,
                          onChanged: (val) => widget.onToggleActive(e, !val),
                          activeColor: Colors.greenAccent,
                          inactiveTrackColor: Colors.red.withOpacity(0.3),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                              onPressed: () => widget.onEdit(e),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                              onPressed: () => widget.onDelete(e),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
