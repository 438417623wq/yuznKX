import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart';
import '../../../world_info/data/world_info_provider.dart';
import '../../data/session_provider.dart';
import '../../domain/models/session.dart';

class GroupManagerScreen extends ConsumerStatefulWidget {
  final Session? session;

  const GroupManagerScreen({super.key, this.session});

  @override
  ConsumerState<GroupManagerScreen> createState() => _GroupManagerScreenState();
}

class _GroupManagerScreenState extends ConsumerState<GroupManagerScreen> with SingleTickerProviderStateMixin {
  final Set<String> _selectedCharacterIds = {};
  final Set<String> _selectedWorldInfoIds = {};
  final TextEditingController _nameController = TextEditingController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.session != null) {
      _nameController.text = widget.session!.name;
      _selectedCharacterIds.addAll(widget.session!.groupCharacterIds);
      _selectedWorldInfoIds.addAll(widget.session!.worldInfoIds);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please input a group name.')),
      );
      return;
    }

    if (_selectedCharacterIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least two members.')),
      );
      return;
    }

    final characters = ref.read(characterListProvider);
    final memberIds = _selectedCharacterIds.toList();
    final worldInfoIds = _selectedWorldInfoIds.toList();
    final avatarPath = _resolveGroupAvatar(characters);
    final description = 'Group chat with ${memberIds.length} members';

    if (widget.session != null) {
      final currentSession = widget.session!;

      Character? linkedGroupCharacter;
      try {
        linkedGroupCharacter = characters.firstWhere(
          (c) => c.id == currentSession.characterId && c.isGroup,
        );
      } catch (_) {
        linkedGroupCharacter = null;
      }

      linkedGroupCharacter ??= Character(
        id: const Uuid().v4(),
        name: name,
        isGroup: true,
        groupMemberIds: memberIds,
        worldInfoIds: worldInfoIds,
        avatarPath: avatarPath,
        description: description,
      );

      final updatedGroupCharacter = linkedGroupCharacter.copyWith(
        name: name,
        groupMemberIds: memberIds,
        worldInfoIds: worldInfoIds,
        avatarPath: avatarPath,
        description: description,
      );
      await ref.read(characterListProvider.notifier).save(updatedGroupCharacter);

      final updatedSession = currentSession.copyWith(
        name: name,
        characterId: updatedGroupCharacter.id,
        groupCharacterIds: memberIds,
        worldInfoIds: worldInfoIds,
      );
      await ref.read(sessionProvider.notifier).updateSession(updatedSession);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group updated.')),
        );
      }
    } else {
      final newGroupCharacter = Character(
        id: const Uuid().v4(),
        name: name,
        isGroup: true,
        groupMemberIds: memberIds,
        worldInfoIds: worldInfoIds,
        avatarPath: avatarPath,
        description: description,
      );
      await ref.read(characterListProvider.notifier).save(newGroupCharacter);

      final newSession = await ref.read(sessionProvider.notifier).createSession(
        name,
        characterId: newGroupCharacter.id,
        groupCharacterIds: memberIds,
        worldInfoIds: worldInfoIds,
      );

      await ref.read(activeCharacterIdProvider.notifier).setActive(newGroupCharacter.id);
      await ref.read(activeSessionIdProvider.notifier).setActive(newSession.id);
    }

    if (!mounted) {
      return;
    }

    Navigator.pop(context);
    if (widget.session == null) {
      Navigator.pop(context);
    }
  }

  String _resolveGroupAvatar(List<Character> characters) {
    if (_selectedCharacterIds.isEmpty) {
      return '';
    }

    try {
      return characters.firstWhere((c) => c.id == _selectedCharacterIds.first).avatarPath;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session != null ? 'Manage Group' : 'Create Group'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members'),
            Tab(text: 'World Info'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveGroup,
            tooltip: 'Save',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMembersTab(),
                _buildWorldInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    final members = ref.watch(characterListProvider).where((c) => !c.isGroup).toList();
    if (members.isEmpty) {
      return const Center(child: Text('No characters yet.'));
    }

    return ListView.builder(
      itemCount: members.length,
      itemBuilder: (context, index) {
        final char = members[index];
        final isSelected = _selectedCharacterIds.contains(char.id);

        return CheckboxListTile(
          value: isSelected,
          title: Text(char.name),
          subtitle: Text(
            char.tags.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: CircleAvatar(
            backgroundImage: char.avatarPath.isNotEmpty
                ? FileImage(File(char.avatarPath)) as ImageProvider
                : const NetworkImage('https://via.placeholder.com/150'),
          ),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedCharacterIds.add(char.id);
              } else {
                _selectedCharacterIds.remove(char.id);
              }
            });
          },
        );
      },
    );
  }

  Widget _buildWorldInfoTab() {
    final worldInfos = ref.watch(worldInfoProvider);
    if (worldInfos.isEmpty) {
      return const Center(child: Text('No world info yet.'));
    }

    return ListView.builder(
      itemCount: worldInfos.length,
      itemBuilder: (context, index) {
        final wi = worldInfos[index];
        final isSelected = _selectedWorldInfoIds.contains(wi.id);

        return CheckboxListTile(
          value: isSelected,
          title: Text(wi.name),
          subtitle: Text('${wi.entries.length} entries'),
          secondary: const Icon(Icons.book),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedWorldInfoIds.add(wi.id);
              } else {
                _selectedWorldInfoIds.remove(wi.id);
              }
            });
          },
        );
      },
    );
  }
}
