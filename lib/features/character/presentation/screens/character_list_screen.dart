import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../../data/character_provider.dart';
import '../../domain/models/character.dart';
import 'character_edit_screen.dart';

class CharacterListScreen extends ConsumerStatefulWidget {
  const CharacterListScreen({super.key});

  @override
  ConsumerState<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends ConsumerState<CharacterListScreen> {
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(characterListProvider);
    final query = _searchController.text.toLowerCase();
    final filteredChars = characters.where((c) => c.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF16161e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161e),
        elevation: 0,
        title: const Text('角色管理', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: () {
               // Show search bar or focus it
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort, color: Colors.white70),
            onPressed: () {
              // TODO: Implement sort
            },
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.grid_view : Icons.list, color: Colors.white70),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar (Optional, or integrate into AppBar)
          /*
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "搜索角色...",
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF24283b),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() {}),
            ),
          ),
          */
          Expanded(
            child: filteredChars.isEmpty
                ? const Center(child: Text('暂无角色', style: TextStyle(color: Colors.white54)))
                : _isGridView 
                    ? _buildGridView(filteredChars) 
                    : _buildListView(filteredChars),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          // Show options: Create New or Import
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1a1b26),
            builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_add, color: Colors.white),
                  title: const Text('新建角色', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterEditScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload, color: Colors.white),
                  title: const Text('导入角色 (PNG/JSON)', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(characterListProvider.notifier).importCharacter();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridView(List<Character> characters) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: characters.length,
      itemBuilder: (context, index) {
        final char = characters[index];
        return _buildGridItem(char);
      },
    );
  }

  Widget _buildGridItem(Character char) {
    return InkWell(
      onTap: () {
         ref.read(activeCharacterIdProvider.notifier).setActive(char.id);
         Navigator.pop(context);
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF24283b),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                image: char.avatarPath.isNotEmpty
                    ? DecorationImage(
                        image: FileImage(File(char.avatarPath)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: char.avatarPath.isEmpty
                  ? const Icon(Icons.person, size: 48, color: Colors.white24)
                  : null,
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        char.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        char.tags.isNotEmpty ? char.tags.join(', ') : '暂无标签',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterEditScreen(character: char)));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18, color: Colors.white70),
                        onPressed: () => _confirmDelete(char),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(List<Character> characters) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: characters.length,
      itemBuilder: (context, index) {
        final char = characters[index];
        return Card(
          color: const Color(0xFF24283b),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: char.avatarPath.isNotEmpty ? FileImage(File(char.avatarPath)) : null,
              child: char.avatarPath.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(char.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(char.tags.isNotEmpty ? char.tags.join(', ') : '暂无标签', style: const TextStyle(color: Colors.white54)),
            onTap: () {
               ref.read(activeCharacterIdProvider.notifier).setActive(char.id);
               Navigator.pop(context);
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.white70), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterEditScreen(character: char)))),
                IconButton(icon: const Icon(Icons.delete, color: Colors.white70), onPressed: () => _confirmDelete(char)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(Character char) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定要删除 "${char.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(characterListProvider.notifier).delete(char.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
