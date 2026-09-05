import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../data/persona_provider.dart';
import '../../domain/models/persona.dart';

class PersonaEditScreen extends ConsumerStatefulWidget {
  final Persona? persona;
  const PersonaEditScreen({super.key, this.persona});

  @override
  ConsumerState<PersonaEditScreen> createState() => _PersonaEditScreenState();
}

class _PersonaEditScreenState extends ConsumerState<PersonaEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    final p = widget.persona;
    _nameController = TextEditingController(text: p?.name ?? 'User');
    _descController = TextEditingController(text: p?.description ?? '');
    _avatarPath = p?.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _avatarPath = result.files.single.path!;
      });
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名字不能为空')),
      );
      return;
    }

    final newPersona = Persona(
      id: widget.persona?.id ?? const Uuid().v4(),
      name: name,
      description: _descController.text,
      avatarPath: _avatarPath ?? '',
    );
    
    ref.read(personaListProvider.notifier).save(newPersona);
    
    // If this is the first persona being created, make it active
    final list = ref.read(personaListProvider);
    if (list.isEmpty) {
      ref.read(activePersonaIdProvider.notifier).setActive(newPersona.id);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1b26),
      appBar: AppBar(
        title: const Text('编辑用户身份 (Persona)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.greenAccent),
            onPressed: _save,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white10,
                backgroundImage: (_avatarPath != null && _avatarPath!.isNotEmpty)
                    ? FileImage(File(_avatarPath!)) as ImageProvider
                    : null,
                child: (_avatarPath == null || _avatarPath!.isEmpty)
                    ? const Icon(Icons.add_a_photo, size: 40, color: Colors.white54)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            const Text('点击头像上传', style: TextStyle(color: Colors.white38, fontSize: 12)),
            
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '用户名称 (Name)',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF24283b),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 8,
              decoration: InputDecoration(
                labelText: '身份描述 / 备注 (Description)',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: '描述你的外貌、性格或当前扮演的角色设定...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF24283b),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '提示: 这些信息可能会被发送给 AI (取决于预设)，用于让 AI 知道你是谁。',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
