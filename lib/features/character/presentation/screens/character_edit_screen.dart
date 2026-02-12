import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../domain/models/character.dart';
import '../../data/character_provider.dart';
import '../../../world_info/data/world_info_provider.dart';
import '../../../regex/data/regex_provider.dart';

class CharacterEditScreen extends ConsumerStatefulWidget {
  final Character? character;
  const CharacterEditScreen({super.key, this.character});

  @override
  ConsumerState<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends ConsumerState<CharacterEditScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _creatorCtrl;
  late TextEditingController _versionCtrl;
  late TextEditingController _systemCtrl;
  late TextEditingController _scenarioCtrl;
  late TextEditingController _authorNoteCtrl;
  late TextEditingController _depthCtrl;
  late TextEditingController _freqCtrl;
  late TextEditingController _firstMsgCtrl;
  
  String _avatarPath = '';
  List<String> _tags = [];
  List<String> _alternateGreetings = [];
  List<String> _worldInfoIds = [];
  List<String> _regexScriptIds = [];
  
  // Advanced (Mock for now or simple strings)
  String? _boundModelId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final c = widget.character;
    
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _descCtrl = TextEditingController(text: c?.description ?? '');
    _creatorCtrl = TextEditingController(text: c?.creator ?? 'User');
    _versionCtrl = TextEditingController(text: c?.version ?? '1.0');
    _systemCtrl = TextEditingController(text: c?.systemInstruction ?? '');
    _scenarioCtrl = TextEditingController(text: c?.scenario ?? '');
    _authorNoteCtrl = TextEditingController(text: c?.authorsNote ?? '');
    _depthCtrl = TextEditingController(text: (c?.authorsNoteDepth ?? 4).toString());
    _freqCtrl = TextEditingController(text: (c?.authorsNoteFrequency ?? 0).toString());
    _firstMsgCtrl = TextEditingController(text: c?.firstMessage ?? '');
    
    _avatarPath = c?.avatarPath ?? '';
    _tags = List.from(c?.tags ?? []);
    _alternateGreetings = List.from(c?.alternateGreetings ?? []);
    _boundModelId = c?.boundModelId;
    _worldInfoIds = List.from(c?.worldInfoIds ?? []);
    _regexScriptIds = List.from(c?.regexScriptIds ?? []);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _creatorCtrl.dispose();
    _versionCtrl.dispose();
    _systemCtrl.dispose();
    _scenarioCtrl.dispose();
    _authorNoteCtrl.dispose();
    _depthCtrl.dispose();
    _freqCtrl.dispose();
    _firstMsgCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final newChar = Character(
      id: widget.character?.id ?? const Uuid().v4(),
      name: _nameCtrl.text,
      description: _descCtrl.text,
      avatarPath: _avatarPath,
      tags: _tags,
      creator: _creatorCtrl.text,
      version: _versionCtrl.text,
      systemInstruction: _systemCtrl.text,
      scenario: _scenarioCtrl.text,
      authorsNote: _authorNoteCtrl.text,
      authorsNoteDepth: int.tryParse(_depthCtrl.text) ?? 4,
      authorsNoteFrequency: int.tryParse(_freqCtrl.text) ?? 0,
      firstMessage: _firstMsgCtrl.text,
      alternateGreetings: _alternateGreetings,
      boundModelId: _boundModelId,
      // Persist existing IDs or handle advanced lists
      worldInfoIds: _worldInfoIds,
      regexScriptIds: _regexScriptIds,
    );

    ref.read(characterListProvider.notifier).save(newChar);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16161e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161e),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('保存'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blueAccent,
              tabs: const [
                Tab(text: '基础信息', icon: Icon(Icons.person_outline)),
                Tab(text: '人设详情', icon: Icon(Icons.description_outlined)),
                Tab(text: '开场白', icon: Icon(Icons.chat_bubble_outline)),
                Tab(text: '高级配置', icon: Icon(Icons.settings_suggest_outlined)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBasicInfoTab(),
                  _buildDetailsTab(),
                  _buildFirstMessageTab(),
                  _buildAdvancedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickAvatar,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(16),
                image: _avatarPath.isNotEmpty
                    ? DecorationImage(
                        image: FileImage(File(_avatarPath)),
                        fit: BoxFit.cover,
                      )
                    : const DecorationImage(
                        image: NetworkImage('https://via.placeholder.com/150'),
                        fit: BoxFit.cover,
                      ),
              ),
              child: _avatarPath.isEmpty 
                  ? const Icon(Icons.add_a_photo, color: Colors.white54)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '角色名称',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  validator: (v) => v!.isEmpty ? '请输入名称' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_creatorCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Text('v${_versionCtrl.text}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _avatarPath = pickedFile.path;
      });
    }
  }

  Widget _buildBasicInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tags
        Wrap(
          spacing: 8,
          children: [
            ..._tags.map((tag) => Chip(
              label: Text(tag),
              backgroundColor: Colors.blueAccent.withOpacity(0.1),
              labelStyle: const TextStyle(color: Colors.blueAccent),
              onDeleted: () => setState(() => _tags.remove(tag)),
            )),
            ActionChip(
              label: const Text('+ 添加标签'),
              backgroundColor: Colors.grey[800],
              labelStyle: const TextStyle(color: Colors.white70),
              onPressed: () {
                _showAddTagDialog();
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildCard(
          title: '简介描述',
          child: TextFormField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '简短描述这个角色...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF24283b).withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            '角色 ID: ${widget.character?.id ?? "New"}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('SYSTEM INSTRUCTION (核心设定)'),
        _buildCard(
          child: TextFormField(
            controller: _systemCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '这是角色的灵魂。包含性格、外貌及行为逻辑。',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('SCENARIO (场景/背景)'),
        _buildCard(
          child: TextFormField(
            controller: _scenarioCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '未设定场景...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('AUTHOR\'S NOTE (作者注释)'),
        _buildCard(
          child: Column(
            children: [
              TextFormField(
                controller: _authorNoteCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '插入到 Prompt 中的额外注释...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              ),
              const Divider(color: Colors.white10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _depthCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '深度 (Depth)', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _freqCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '频率 (Freq)', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFirstMessageTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('开场白 (FIRST MESSAGE)'),
        _buildCard(
          child: TextFormField(
            controller: _firstMsgCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '角色的第一句话...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('备选开场白 (ALTERNATES)'),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _alternateGreetings.add('');
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
            ),
          ],
        ),
        if (_alternateGreetings.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('暂无备选开场白', style: TextStyle(color: Colors.white24)))),
        ..._alternateGreetings.asMap().entries.map((entry) {
          final index = entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCard(
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: entry.value,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      onChanged: (v) => _alternateGreetings[index] = v,
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => setState(() => _alternateGreetings.removeAt(index)),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAdvancedTab() {
    final allWorldInfo = ref.watch(worldInfoProvider);
    final allRegex = ref.watch(regexScriptsProvider);

    final boundWorldInfo = allWorldInfo.where((e) => _worldInfoIds.contains(e.id)).toList();
    final boundRegex = allRegex.where((e) => _regexScriptIds.contains(e.id)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('模型配置'),
        _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前绑定模型: gemini-3-flash-preview', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('为此角色指定特定的模型，覆盖全局默认设置。', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _boundModelId, // Null means default
                dropdownColor: const Color(0xFF24283b),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('使用全局默认')),
                  DropdownMenuItem(value: 'gemini-pro', child: Text('Gemini Pro')),
                  DropdownMenuItem(value: 'gpt-4', child: Text('GPT-4')),
                ],
                onChanged: (v) => setState(() => _boundModelId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('角色世界书'),
        if (boundWorldInfo.isEmpty)
          _buildCard(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('该角色未包含内置世界书', style: TextStyle(color: Colors.white24)),
              ),
            ),
          )
        else
          ...boundWorldInfo.map((wi) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(wi.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${wi.entries.length} entries', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.redAccent),
                  onPressed: () => setState(() => _worldInfoIds.remove(wi.id)),
                  tooltip: '移除绑定',
                ),
              ),
            ),
          )),
        
        const SizedBox(height: 24),
        _buildSectionHeader('角色正则脚本'),
        if (boundRegex.isEmpty)
          _buildCard(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无内置正则脚本', style: TextStyle(color: Colors.white24)),
              ),
            ),
          )
        else
          ...boundRegex.map((script) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(script.scriptName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(script.findRegex, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.redAccent),
                  onPressed: () => setState(() => _regexScriptIds.remove(script.id)),
                  tooltip: '移除绑定',
                ),
              ),
            ),
          )),
      ],
    );
  }

  Widget _buildCard({required Widget child, String? title}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF24283b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  void _showAddTagDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF24283b),
        title: const Text('添加标签', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Tag name', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() => _tags.add(controller.text));
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
