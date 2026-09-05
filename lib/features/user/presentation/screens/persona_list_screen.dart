import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/persona_provider.dart';
import 'persona_edit_screen.dart';

class PersonaListScreen extends ConsumerWidget {
  const PersonaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personaListProvider);
    final activeId = ref.watch(activePersonaIdProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1a1b26),
      appBar: AppBar(
        title: const Text('用户身份管理'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PersonaEditScreen()),
          );
        },
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add),
      ),
      body: personas.isEmpty
          ? const Center(child: Text('暂无用户身份，请点击 + 号创建', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: personas.length,
              itemBuilder: (context, index) {
                final persona = personas[index];
                final isActive = persona.id == activeId;

                return Card(
                  color: isActive ? const Color(0xFF24283b).withOpacity(0.8) : const Color(0xFF1f2335),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isActive 
                      ? const BorderSide(color: Colors.blueAccent, width: 2)
                      : BorderSide.none,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      ref.read(activePersonaIdProvider.notifier).setActive(persona.id);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: (persona.avatarPath.isNotEmpty)
                                  ? DecorationImage(
                                      image: FileImage(File(persona.avatarPath)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: Colors.grey[800],
                            ),
                            child: persona.avatarPath.isEmpty
                                ? const Icon(Icons.person, color: Colors.white54)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  persona.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (persona.description.isNotEmpty)
                                  Text(
                                    persona.description,
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          
                          // Actions
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PersonaEditScreen(persona: persona),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () {
                                  if (personas.length <= 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('至少保留一个身份')),
                                    );
                                    return;
                                  }
                                  
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF1f2335),
                                      title: const Text('确认删除', style: TextStyle(color: Colors.white)),
                                      content: Text('确定要删除 "${persona.name}" 吗？', style: const TextStyle(color: Colors.white70)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            ref.read(personaListProvider.notifier).delete(persona.id);
                                            // If deleting active, switch to another
                                            if (isActive) {
                                               final list = ref.read(personaListProvider); // updated list
                                               if (list.isNotEmpty) {
                                                 ref.read(activePersonaIdProvider.notifier).setActive(list.first.id);
                                               }
                                            }
                                            Navigator.pop(context);
                                          },
                                          child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
