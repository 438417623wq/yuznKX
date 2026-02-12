import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/chat_provider.dart';
import '../../data/session_provider.dart';
import 'dart:io';
import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart';

class SessionListDrawer extends ConsumerStatefulWidget {
  const SessionListDrawer({super.key});

  @override
  ConsumerState<SessionListDrawer> createState() => _SessionListDrawerState();
}

class _SessionListDrawerState extends ConsumerState<SessionListDrawer> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Container(
        color: const Color(0xFF1a1b26),
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: _buildCharacterList(),
            ),
            _buildFooterActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 10),
      color: const Color(0xFF16161e),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "角色列表",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
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
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Widget _buildCharacterList() {
    final characters = ref.watch(characterListProvider);
    final activeId = ref.watch(activeCharacterIdProvider);
    final query = _searchController.text.toLowerCase();

    final filteredChars = characters.where((c) => c.name.toLowerCase().contains(query)).toList();

    if (filteredChars.isEmpty) {
      return const Center(child: Text('没有角色', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: filteredChars.length,
      itemBuilder: (context, index) {
        final char = filteredChars[index];
        final isActive = char.id == activeId;

        return _CharacterListItem(char: char, isActive: isActive);
      },
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF16161e),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                 // Import Character
                 await ref.read(characterListProvider.notifier).importCharacter();
              },
              icon: const Icon(Icons.upload_file),
              label: const Text("导入角色"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigoAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterListItem extends ConsumerWidget {
  final Character char;
  final bool isActive;

  const _CharacterListItem({required this.char, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionProvider);
    String? sessionId;
    try {
      // Find the most relevant session for this character (usually the first one)
      final session = sessions.firstWhere((s) => s.characterId == char.id);
      sessionId = session.id;
    } catch (_) {}

    final isGenerating = sessionId != null 
        ? ref.watch(isGeneratingProviderFamily(sessionId)) 
        : false;

    return Card(
      color: isActive ? Colors.purple.withOpacity(0.3) : const Color(0xFF24283b),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isActive ? const BorderSide(color: Colors.purpleAccent) : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: char.avatarPath.isNotEmpty 
              ? FileImage(File(char.avatarPath)) as ImageProvider
              : const NetworkImage('https://via.placeholder.com/150'),
        ),
        title: Text(
          char.name,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70, 
            fontWeight: FontWeight.bold
          ),
        ),
        subtitle: Text(
          isGenerating ? '正在回复...' : '${char.tags.length} Tags • ${char.creator}',
          style: TextStyle(
            color: isGenerating ? Colors.greenAccent : Colors.white54, 
            fontSize: 12,
            fontStyle: isGenerating ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        trailing: isGenerating 
            ? const SizedBox(
                width: 16, 
                height: 16, 
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
              ) 
            : null,
        onTap: () {
          ref.read(activeCharacterIdProvider.notifier).state = char.id;
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

