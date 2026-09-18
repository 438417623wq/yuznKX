import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../regex/data/regex_provider.dart';
import '../../../regex/domain/models/regex_script.dart';
import '../../../regex/presentation/screens/regex_list_screen.dart';
import '../../../world_info/data/world_info_provider.dart';
import '../../../world_info/domain/models/world_info.dart';
import '../../../world_info/presentation/screens/world_info_list_screen.dart';
import '../../data/character_provider.dart';
import '../../domain/models/character.dart';

class CharacterEditScreen extends ConsumerStatefulWidget {
  final Character? character;

  const CharacterEditScreen({super.key, this.character});

  @override
  ConsumerState<CharacterEditScreen> createState() =>
      _CharacterEditScreenState();
}

class _CharacterEditScreenState extends ConsumerState<CharacterEditScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TabController _tabController;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _personalityCtrl;
  late final TextEditingController _systemPromptCtrl;
  late final TextEditingController _creatorNotesCtrl;
  late final TextEditingController _scenarioCtrl;
  late final TextEditingController _exampleCtrl;
  late final TextEditingController _authorsNoteCtrl;
  late final TextEditingController _depthCtrl;
  late final TextEditingController _frequencyCtrl;
  late final TextEditingController _firstMessageCtrl;
  late final TextEditingController _creatorCtrl;
  late final TextEditingController _versionCtrl;
  late final TextEditingController _preferredModelCtrl;

  String _avatarPath = '';
  List<String> _tags = [];
  List<String> _alternateGreetings = [];

  /// 本卡引用的「全局世界书」ID（非卡片独占，来自全局资源池）。
  List<String> _worldInfoIds = [];

  /// 随角色卡导入的「角色正则」ID（extensions.regex_scripts）。
  List<String> _regexScriptIds = [];

  /// 本卡引用的「全局正则」ID（来自设置板块的全局正则池）。
  List<String> _globalRegexIds = [];

  String? _characterBookId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final character = widget.character;

    _nameCtrl = TextEditingController(text: character?.name ?? '');
    _descriptionCtrl =
        TextEditingController(text: character?.description ?? '');
    _personalityCtrl = TextEditingController(
      text: character?.personality.isNotEmpty == true
          ? character!.personality
          : character?.systemInstruction ?? '',
    );
    _systemPromptCtrl =
        TextEditingController(text: character?.systemPrompt ?? '');
    _creatorNotesCtrl =
        TextEditingController(text: character?.creatorNotes ?? '');
    _scenarioCtrl = TextEditingController(text: character?.scenario ?? '');
    _exampleCtrl =
        TextEditingController(text: character?.exampleDialogue ?? '');
    _authorsNoteCtrl =
        TextEditingController(text: character?.authorsNote ?? '');
    _depthCtrl = TextEditingController(
      text: (character?.authorsNoteDepth ?? 4).toString(),
    );
    _frequencyCtrl = TextEditingController(
      text: (character?.authorsNoteFrequency ?? 0).toString(),
    );
    _firstMessageCtrl =
        TextEditingController(text: character?.firstMessage ?? '');
    _creatorCtrl = TextEditingController(text: character?.creator ?? '');
    _versionCtrl = TextEditingController(text: character?.version ?? '1.0');
    _preferredModelCtrl = TextEditingController(
      text: character?.preferredModelName ?? '',
    );

    _avatarPath = character?.avatarPath ?? '';
    _tags = List<String>.from(character?.tags ?? const []);
    _alternateGreetings =
        List<String>.from(character?.alternateGreetings ?? const []);
    _worldInfoIds = List<String>.from(character?.worldInfoIds ?? const []);
    _regexScriptIds = List<String>.from(character?.regexScriptIds ?? const []);
    _globalRegexIds = List<String>.from(character?.globalRegexIds ?? const []);
    _characterBookId = character?.characterBookId;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _personalityCtrl.dispose();
    _systemPromptCtrl.dispose();
    _creatorNotesCtrl.dispose();
    _scenarioCtrl.dispose();
    _exampleCtrl.dispose();
    _authorsNoteCtrl.dispose();
    _depthCtrl.dispose();
    _frequencyCtrl.dispose();
    _firstMessageCtrl.dispose();
    _creatorCtrl.dispose();
    _versionCtrl.dispose();
    _preferredModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return;
    }
    setState(() {
      _avatarPath = file.path;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedCharacterBook = _lookupWorldInfo(_characterBookId);
    final rawCharacterBook = selectedCharacterBook == null
        ? null
        : _worldInfoToCharacterBook(selectedCharacterBook);

    final character = Character(
      id: widget.character?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      personality: _personalityCtrl.text.trim(),
      systemPrompt: _systemPromptCtrl.text.trim(),
      creatorNotes: _creatorNotesCtrl.text.trim(),
      avatarPath: _avatarPath,
      tags: List<String>.from(_tags),
      creator: _creatorCtrl.text.trim(),
      version:
          _versionCtrl.text.trim().isEmpty ? '1.0' : _versionCtrl.text.trim(),
      systemInstruction: _personalityCtrl.text.trim(),
      scenario: _scenarioCtrl.text.trim(),
      authorsNote: _authorsNoteCtrl.text.trim(),
      authorsNoteDepth: int.tryParse(_depthCtrl.text.trim()) ?? 4,
      authorsNoteFrequency: int.tryParse(_frequencyCtrl.text.trim()) ?? 0,
      firstMessage: _firstMessageCtrl.text,
      alternateGreetings: List<String>.from(_alternateGreetings),
      exampleDialogue: _exampleCtrl.text,
      preferredModelName: _preferredModelCtrl.text.trim().isEmpty
          ? null
          : _preferredModelCtrl.text.trim(),
      characterBookId: _characterBookId,
      worldInfoIds: _worldInfoIds
          .where((id) => id.trim().isNotEmpty && id != _characterBookId)
          .toList(growable: false),
      regexScriptIds: _regexScriptIds
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      globalRegexIds: _globalRegexIds
          .where((id) => id.trim().isNotEmpty && !_regexScriptIds.contains(id))
          .toList(growable: false),
      cardSpec: widget.character?.cardSpec ?? 'chara_card_v2',
      cardSpecVersion: widget.character?.cardSpecVersion ?? '2.0',
      rawCardData: widget.character?.rawCardData ?? const {},
      rawExtensions: widget.character?.rawExtensions ?? const {},
      rawCharacterBook: rawCharacterBook,
    );

    ref.read(characterListProvider.notifier).save(character);
    Navigator.pop(context);
  }

  WorldInfo? _lookupWorldInfo(String? id) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }

    final all = ref.read(worldInfoProvider);
    for (final item in all) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Map<String, dynamic> _worldInfoToCharacterBook(WorldInfo worldInfo) {
    return {
      'name': worldInfo.name,
      'entries': [
        for (final entry in worldInfo.entries) entry.toJson(),
      ],
    };
  }

  Future<void> _showAddTagDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标签名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                setState(() {
                  _tags = [..._tags, value];
                });
              }
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCharacterBookSelector(List<WorldInfo> allWorldInfo) async {
    String? selectedId = _characterBookId;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择角色卡世界书'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioListTile<String?>(
                  value: null,
                  groupValue: selectedId,
                  title: const Text('不绑定角色卡世界书'),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedId = value;
                    });
                  },
                ),
                for (final worldInfo in allWorldInfo)
                  RadioListTile<String?>(
                    value: worldInfo.id,
                    groupValue: selectedId,
                    title: Text(worldInfo.name),
                    subtitle: Text('${worldInfo.entries.length} 条目'),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedId = value;
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _characterBookId = selectedId;
                  _worldInfoIds.removeWhere((id) => id == selectedId);
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWorldInfoSelector(List<WorldInfo> allWorldInfo) async {
    final selected = _worldInfoIds.toSet();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择全局世界书'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final worldInfo in allWorldInfo)
                  if (worldInfo.id != _characterBookId)
                    CheckboxListTile(
                      value: selected.contains(worldInfo.id),
                      title: Text(worldInfo.name),
                      subtitle: Text('${worldInfo.entries.length} 条目'),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(worldInfo.id);
                          } else {
                            selected.remove(worldInfo.id);
                          }
                        });
                      },
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _worldInfoIds = selected.toList(growable: false);
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRegexSelector(List<RegexScript> allRegex) async {
    final selected = _regexScriptIds.toSet();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择角色正则'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final script in allRegex)
                  CheckboxListTile(
                    value: selected.contains(script.id),
                    title: Text(script.scriptName),
                    subtitle: Text(
                      script.findRegex,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          selected.add(script.id);
                        } else {
                          selected.remove(script.id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _regexScriptIds = selected.toList(growable: false);
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWorldInfo(WorldInfo? worldInfo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorldInfoEditScreen(worldInfo: worldInfo),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _editRegex(RegexScript script) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RegexEditScreen(script: script)),
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// 选择本卡要引用的「全局正则」。
  ///
  /// 候选来自设置板块"全局正则"里已启用的脚本；角色自带正则
  /// （[_regexScriptIds]）已在角色正则板块单独管理，此处不重复列出。
  Future<void> _showGlobalRegexSelector(
      List<RegexScript> activeGlobalRegex) async {
    final selected = _globalRegexIds.toSet();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择全局正则'),
          content: SizedBox(
            width: double.maxFinite,
            child: activeGlobalRegex.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '暂无可选的全局正则。\n请先到「设置 → 全局正则」中创建并启用脚本。',
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final script in activeGlobalRegex)
                        CheckboxListTile(
                          value: selected.contains(script.id),
                          title: Text(script.scriptName),
                          subtitle: Text(
                            script.findRegex,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(script.id);
                              } else {
                                selected.remove(script.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _globalRegexIds = selected.toList(growable: false);
                });
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 从全局资源池中彻底删除一个世界书。
  Future<void> _deleteWorldInfo(WorldInfo worldInfo) async {
    final confirmed = await _confirmDelete(
      title: '删除世界书',
      message: '确定要删除「${worldInfo.name}」吗？\n'
          '该世界书将从全局资源池中永久移除，所有引用它的角色卡都会失去它。',
    );
    if (confirmed != true) {
      return;
    }

    await ref.read(worldInfoProvider.notifier).delete(worldInfo.id);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_characterBookId == worldInfo.id) {
        _characterBookId = null;
      }
      _worldInfoIds =
          _worldInfoIds.where((item) => item != worldInfo.id).toList();
    });
  }

  /// 从全局资源池中彻底删除一个正则脚本。
  Future<void> _deleteRegex(RegexScript script) async {
    final confirmed = await _confirmDelete(
      title: '删除正则脚本',
      message: '确定要删除「${script.scriptName}」吗？\n'
          '该脚本将从资源池中永久移除，所有引用它的角色卡都会失去它。',
    );
    if (confirmed != true) {
      return;
    }

    await ref.read(regexScriptsProvider.notifier).delete(script.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _regexScriptIds =
          _regexScriptIds.where((item) => item != script.id).toList();
      _globalRegexIds =
          _globalRegexIds.where((item) => item != script.id).toList();
    });
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allWorldInfo = ref.watch(worldInfoProvider);
    final allRegex = ref.watch(regexScriptsProvider);
    final activeWorldInfoIds = ref.watch(activeWorldInfoIdsProvider);
    final activeRegexIds = ref.watch(activeRegexScriptIdsProvider);
    final characterBook = _lookupWorldInfo(_characterBookId);

    // 「全局生效」资源：来自设置板块的全局池，对所有角色卡自动生效，
    // 本卡无需重复启用（下方「本卡额外启用」会排除它们，避免重复展示）。
    final globalActiveWorldInfo = allWorldInfo
        .where((item) => activeWorldInfoIds.contains(item.id))
        .toList(growable: false);
    final globalActiveWorldInfoIds =
        globalActiveWorldInfo.map((e) => e.id).toSet();

    final globalActiveRegex = allRegex
        .where((item) => activeRegexIds.contains(item.id))
        .toList(growable: false);
    final globalActiveRegexIds = globalActiveRegex.map((e) => e.id).toSet();

    // 本卡额外启用的全局世界书。
    final boundWorldInfo = allWorldInfo
        .where((item) =>
            _worldInfoIds.contains(item.id) &&
            !globalActiveWorldInfoIds.contains(item.id))
        .toList(growable: false);

    // 随角色卡导入的正则（卡片独占）。
    final boundRegex = allRegex
        .where((item) => _regexScriptIds.contains(item.id))
        .toList(growable: false);

    // 本卡引用的全局正则：来源为设置板块已启用的全局正则池，
    // 且排除掉已归入「角色正则」或已「全局生效」的脚本，避免重复展示。
    final boundGlobalRegex = allRegex
        .where((item) =>
            _globalRegexIds.contains(item.id) &&
            !_regexScriptIds.contains(item.id) &&
            !globalActiveRegexIds.contains(item.id))
        .toList(growable: false);
    final availableGlobalRegex = allRegex
        .where((item) =>
            activeRegexIds.contains(item.id) &&
            !_regexScriptIds.contains(item.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.character == null ? '新建角色卡' : '编辑角色卡'),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '基本'),
            Tab(text: '卡片'),
            Tab(text: '开场'),
            Tab(text: '绑定'),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBasicTab(),
                  _buildCardTab(),
                  _buildGreetingTab(),
                  _buildBindingsTab(
                    allWorldInfo: allWorldInfo,
                    allRegex: allRegex,
                    characterBook: characterBook,
                    boundWorldInfo: boundWorldInfo,
                    boundRegex: boundRegex,
                    boundGlobalRegex: boundGlobalRegex,
                    availableGlobalRegex: availableGlobalRegex,
                    globalActiveWorldInfo: globalActiveWorldInfo,
                    globalActiveRegex: globalActiveRegex,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title =
        _nameCtrl.text.trim().isEmpty ? '未命名角色卡' : _nameCtrl.text.trim();
    final creator =
        _creatorCtrl.text.trim().isEmpty ? '未知作者' : _creatorCtrl.text.trim();
    final version =
        _versionCtrl.text.trim().isEmpty ? '1.0' : _versionCtrl.text.trim();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _pickAvatar,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  image: _avatarPath.isEmpty
                      ? null
                      : DecorationImage(
                          image: FileImage(File(_avatarPath)),
                          fit: BoxFit.cover,
                        ),
                ),
                child: _avatarPath.isEmpty
                    ? const Icon(Icons.add_a_photo_outlined)
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeaderChip(creator),
                      _buildHeaderChip('v$version'),
                      if (_characterBookId != null) _buildHeaderChip('角色卡世界书'),
                      if (_worldInfoIds.isNotEmpty)
                        _buildHeaderChip('全局世界书 ${_worldInfoIds.length}'),
                      if (_regexScriptIds.isNotEmpty)
                        _buildHeaderChip('正则 ${_regexScriptIds.length}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: '基础信息',
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入角色名称';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _creatorCtrl,
                decoration: const InputDecoration(
                  labelText: '作者',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _versionCtrl,
                decoration: const InputDecoration(
                  labelText: '版本',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '描述 (Description)',
          child: TextFormField(
            controller: _descriptionCtrl,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '角色描述 (Description)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '标签',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () {
                    setState(() {
                      _tags = _tags.where((item) => item != tag).toList();
                    });
                  },
                ),
              ActionChip(
                label: const Text('添加标签'),
                avatar: const Icon(Icons.add, size: 18),
                onPressed: _showAddTagDialog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: '角色性格 / Personality',
          child: TextFormField(
            controller: _personalityCtrl,
            minLines: 8,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '系统提示词 (System Prompt)',
          child: TextFormField(
            controller: _systemPromptCtrl,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '场景设定 (Scenario)',
          child: TextFormField(
            controller: _scenarioCtrl,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '作者备注 (Creator Notes)',
          child: TextFormField(
            controller: _creatorNotesCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '深度提示词 / 历史后置指令 (Depth Prompt / Post History Instructions)',
          child: Column(
            children: [
              TextFormField(
                controller: _authorsNoteCtrl,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _depthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '注入深度 (Depth)',
                        helperText: '相对对话末尾的层数，越小越靠近末尾。',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _frequencyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '注入频率 (Frequency)',
                        helperText: '每隔 N 条消息插入一次，0 表示不重复注入。',
                        border: OutlineInputBorder(),
                      ),
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

  Widget _buildGreetingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: '开场白 (First Message)',
          child: TextFormField(
            controller: _firstMessageCtrl,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '备用开场白 (Alternate Greetings)',
          trailing: TextButton.icon(
            onPressed: () {
              setState(() {
                _alternateGreetings = [..._alternateGreetings, ''];
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
          ),
          child: Column(
            children: [
              if (_alternateGreetings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂无备用开场白'),
                ),
              for (final entry in _alternateGreetings.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.value,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: '备用开场白 ${entry.key + 1}',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _alternateGreetings[entry.key] = value;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _alternateGreetings.removeAt(entry.key);
                          });
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '示例对话 (Example Dialogue)',
          child: TextFormField(
            controller: _exampleCtrl,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBindingsTab({
    required List<WorldInfo> allWorldInfo,
    required List<RegexScript> allRegex,
    required WorldInfo? characterBook,
    required List<WorldInfo> boundWorldInfo,
    required List<RegexScript> boundRegex,
    required List<RegexScript> boundGlobalRegex,
    required List<RegexScript> availableGlobalRegex,
    required List<WorldInfo> globalActiveWorldInfo,
    required List<RegexScript> globalActiveRegex,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionCard(
          title: '角色卡偏好设置',
          child: TextFormField(
            controller: _preferredModelCtrl,
            decoration: const InputDecoration(
              labelText: '角色偏好模型名 (Preferred Model)',
              helperText: '可选，覆盖当前聊天使用的默认模型名',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '角色卡世界书',
          trailing: Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _showCharacterBookSelector(allWorldInfo),
                child: const Text('选择'),
              ),
              TextButton(
                onPressed: () => _editWorldInfo(null),
                child: const Text('新建'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '随角色卡导入的内嵌世界书（character_book），仅本卡使用。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (characterBook == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('当前没有绑定角色卡世界书'),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(characterBook.name),
                  subtitle: Text('${characterBook.entries.length} 条目'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        onPressed: () => _editWorldInfo(characterBook),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                      ),
                      IconButton(
                        onPressed: () => _deleteWorldInfo(characterBook),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: '删除',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _characterBookId = null;
                          });
                        },
                        icon: const Icon(Icons.link_off_outlined),
                        tooltip: '解绑',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '全局世界书',
          trailing: TextButton.icon(
            onPressed: () => _showWorldInfoSelector(allWorldInfo),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('管理'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 分组 1：全局生效（自动继承） ---
              _buildBindingGroupHeader(
                label: '全局生效（自动继承，对所有角色生效）',
                count: globalActiveWorldInfo.length,
                color: Colors.green,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '来自「设置 → 全局世界书」且已开启全局生效，本卡自动继承，'
                  '无需在此重复启用。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (globalActiveWorldInfo.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('当前没有全局生效的世界书',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                )
              else
                for (final worldInfo in globalActiveWorldInfo)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.public,
                        size: 18, color: Colors.green),
                    title: Text(worldInfo.name),
                    subtitle: Text(
                      '${worldInfo.entries.length} 条目'
                      '${worldInfo.disabled ? ' · 自身已禁用（不会生效）' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: worldInfo.disabled ? Colors.orange : null,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () => _editWorldInfo(worldInfo),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: '编辑',
                    ),
                  ),
              const Divider(height: 24),

              // --- 分组 2：本卡额外启用 ---
              _buildBindingGroupHeader(
                label: '本卡额外启用',
                count: boundWorldInfo.length,
                color: Colors.indigo,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '仅对当前角色卡生效的全局世界书引用；世界书内容请到全局列表编辑。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (boundWorldInfo.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('当前没有本卡额外启用的全局世界书',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              for (final worldInfo in boundWorldInfo)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(worldInfo.name),
                  subtitle: Text('${worldInfo.entries.length} 条目'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        onPressed: () => _editWorldInfo(worldInfo),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                      ),
                      IconButton(
                        onPressed: () => _deleteWorldInfo(worldInfo),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: '删除',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _worldInfoIds = _worldInfoIds
                                .where((id) => id != worldInfo.id)
                                .toList();
                          });
                        },
                        icon: const Icon(Icons.link_off_outlined),
                        tooltip: '解绑',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '角色正则（本卡启用）',
          trailing: TextButton.icon(
            onPressed: () => _showRegexSelector(allRegex),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('管理'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '随角色卡导入的正则（extensions.regex_scripts），删除角色卡时会'
                  '一并回收未被其它卡片引用的条目。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (boundRegex.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('当前没有绑定角色正则'),
                ),
              for (final script in boundRegex)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(script.scriptName),
                  subtitle: Text(
                    script.findRegex,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        onPressed: () => _editRegex(script),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                      ),
                      IconButton(
                        onPressed: () => _deleteRegex(script),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: '删除',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _regexScriptIds = _regexScriptIds
                                .where((id) => id != script.id)
                                .toList();
                          });
                        },
                        icon: const Icon(Icons.link_off_outlined),
                        tooltip: '解绑',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: '全局正则',
          trailing: TextButton.icon(
            onPressed: () => _showGlobalRegexSelector(availableGlobalRegex),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('管理'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 分组 1：全局生效（自动继承） ---
              _buildBindingGroupHeader(
                label: '全局生效（自动继承，对所有角色生效）',
                count: globalActiveRegex.length,
                color: Colors.green,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '来自「设置 → 全局正则」且已开启全局生效，本卡自动继承，'
                  '无需在此重复启用。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (globalActiveRegex.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('当前没有全局生效的正则',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                )
              else
                for (final script in globalActiveRegex)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.public,
                        size: 18, color: Colors.green),
                    title: Text(script.scriptName),
                    subtitle: Text(
                      script.disabled
                          ? '自身已禁用（不会生效）'
                          : script.findRegex,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: script.disabled ? Colors.orange : null,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () => _editRegex(script),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: '编辑',
                    ),
                  ),
              const Divider(height: 24),

              // --- 分组 2：本卡额外启用 ---
              _buildBindingGroupHeader(
                label: '本卡额外启用',
                count: boundGlobalRegex.length,
                color: Colors.indigo,
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '仅对当前角色卡生效的全局正则引用，不受全局生效开关影响；'
                  '脚本内容请到全局列表编辑。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (boundGlobalRegex.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('当前没有本卡额外启用的全局正则',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              for (final script in boundGlobalRegex)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(script.scriptName),
                  subtitle: Text(
                    script.findRegex,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        onPressed: () => _editRegex(script),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                      ),
                      IconButton(
                        onPressed: () => _deleteRegex(script),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: '删除',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _globalRegexIds = _globalRegexIds
                                .where((id) => id != script.id)
                                .toList();
                          });
                        },
                        icon: const Icon(Icons.link_off_outlined),
                        tooltip: '解绑',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 绑定页内的分组标题（用于区分「全局生效」与「本卡额外启用」）。
  Widget _buildBindingGroupHeader({
    required String label,
    required int count,
    required MaterialColor color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.label_outline, size: 16, color: color.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color.shade300,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: color.shade300,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
