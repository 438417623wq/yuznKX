import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/preset_provider.dart';
import '../../domain/models/preset.dart';
import '../../../regex/domain/models/regex_script.dart';

class PresetEditScreen extends ConsumerStatefulWidget {
  final Preset? preset;
  const PresetEditScreen({super.key, this.preset});

  @override
  ConsumerState<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends ConsumerState<PresetEditScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  
  // Parameters
  late double _temp;
  late double _repPen;
  late int _maxTokens;
  late double _topP;
  late int _topK;
  late double _freqPen;
  late double _presPen;

  // Function
  late TextEditingController _impersonationPromptCtrl;
  late TextEditingController _newChatPromptCtrl;
  late TextEditingController _continueNudgeCtrl;
  late TextEditingController _groupChatPromptCtrl;

  // Prompts
  late List<PresetPrompt> _prompts;
  String _promptSearchQuery = '';
  bool _arePromptsExpanded = false;
  int _promptsExpansionVersion = 0;

  // Regex
  late List<RegexScript> _regexScripts;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _nameController = TextEditingController(text: p?.name ?? 'New Preset');
    
    _temp = (p?.temperature ?? 1.0).clamp(0.0, 2.0);
    _repPen = (p?.repetitionPenalty ?? 1.1).clamp(1.0, 1.5);
    _maxTokens = (p?.maxTokens ?? 2048).clamp(100, 131072).toInt(); // Increased max limit
    _topP = (p?.topP ?? 1.0).clamp(0.0, 1.0);
    _topK = (p?.topK ?? 0).clamp(0, 1000); // Increased limit
    _freqPen = (p?.frequencyPenalty ?? 0.0).clamp(-2.0, 2.0);
    _presPen = (p?.presencePenalty ?? 0.0).clamp(-2.0, 2.0);

    _impersonationPromptCtrl = TextEditingController(text: p?.impersonationPrompt ?? '');
    _newChatPromptCtrl = TextEditingController(text: p?.newChatPrompt ?? '');
    _continueNudgeCtrl = TextEditingController(text: p?.continueNudge ?? '');
    _groupChatPromptCtrl = TextEditingController(text: p?.groupChatPrompt ?? '');

    _prompts = p?.prompts != null ? List.from(p!.prompts) : [];
    _regexScripts = p?.regexScripts != null ? List.from(p!.regexScripts) : [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _impersonationPromptCtrl.dispose();
    _newChatPromptCtrl.dispose();
    _continueNudgeCtrl.dispose();
    _groupChatPromptCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    
    final newPreset = widget.preset?.copyWith(
      name: _nameController.text,
      temperature: _temp,
      repetitionPenalty: _repPen,
      maxTokens: _maxTokens,
      topP: _topP,
      topK: _topK,
      frequencyPenalty: _freqPen,
      presencePenalty: _presPen,
      prompts: _prompts,
      regexScripts: _regexScripts,
      impersonationPrompt: _impersonationPromptCtrl.text,
      newChatPrompt: _newChatPromptCtrl.text,
      continueNudge: _continueNudgeCtrl.text,
      groupChatPrompt: _groupChatPromptCtrl.text,
    ) ?? Preset(
      id: const Uuid().v4(),
      name: _nameController.text,
      temperature: _temp,
      repetitionPenalty: _repPen,
      maxTokens: _maxTokens,
      topP: _topP,
      topK: _topK,
      frequencyPenalty: _freqPen,
      presencePenalty: _presPen,
      prompts: _prompts,
      regexScripts: _regexScripts,
      impersonationPrompt: _impersonationPromptCtrl.text,
      newChatPrompt: _newChatPromptCtrl.text,
      continueNudge: _continueNudgeCtrl.text,
      groupChatPrompt: _groupChatPromptCtrl.text,
    );

    ref.read(presetsProvider.notifier).save(newPreset);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.black, fontSize: 20),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '预设名称',
            ),
          ),
          actions: [
            if (widget.preset != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                   showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('删除预设'),
                      content: const Text('确定要删除这个预设吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                        TextButton(
                          onPressed: () {
                            ref.read(presetsProvider.notifier).delete(widget.preset!.id);
                            Navigator.pop(context); // Close dialog
                            Navigator.pop(context); // Close screen
                          },
                          child: const Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.save, color: Colors.deepPurple),
              onPressed: _save,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Parameters (参数)', icon: Icon(Icons.tune)),
              Tab(text: 'Function (功能)', icon: Icon(Icons.code)),
              Tab(text: 'Prompts (提示词)', icon: Icon(Icons.list)),
              Tab(text: 'Regex (正则)', icon: Icon(Icons.abc)),
            ],
          ),
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            children: [
              _buildParametersTab(),
              _buildFunctionTab(),
              _buildPromptsTab(),
              _buildRegexTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParametersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderCard('Temperature (温度)', '控制随机性，越高越有创意', _temp, 0, 2, (v) => setState(() => _temp = v)),
        _buildSliderCard('Top P', '核采样概率', _topP, 0, 1, (v) => setState(() => _topP = v)),
        _buildSliderCard('Top K', '保留高概率Token数量', _topK.toDouble(), 0, 1000, (v) => setState(() => _topK = v.toInt()), divisions: 1000),
        _buildSliderCard('Max Tokens', '单次回复最大长度', _maxTokens.toDouble(), 100, 131072, (v) => setState(() => _maxTokens = v.toInt())),
        _buildSliderCard('Frequency Penalty', '降低重复单词频率', _freqPen, -2, 2, (v) => setState(() => _freqPen = v)),
        _buildSliderCard('Presence Penalty', '鼓励谈论新话题', _presPen, -2, 2, (v) => setState(() => _presPen = v)),
        _buildSliderCard('Repetition Penalty', '重复惩罚 (1.0 无效)', _repPen, 1, 1.5, (v) => setState(() => _repPen = v)),
      ],
    );
  }

  Widget _buildSliderCard(String title, String subtitle, double value, double min, double max, ValueChanged<double> onChanged, {int? divisions}) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
                Text(value.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: Colors.deepPurple,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFunctionCard('Impersonation Prompt (扮演指令)', '用于强制扮演用户的指令', _impersonationPromptCtrl),
        _buildFunctionCard('New Chat Prompt (新对话)', '新对话开始时发送的系统指令', _newChatPromptCtrl),
        _buildFunctionCard('Continue Nudge (继续指令)', '当用户发送空消息或请求继续时使用', _continueNudgeCtrl),
        _buildFunctionCard('Group Chat Prompt (群聊指令)', '多人聊天模式下的系统指令', _groupChatPromptCtrl),
      ],
    );
  }

  Widget _buildFunctionCard(String title, String subtitle, TextEditingController controller) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptsTab() {
    final filteredPrompts = _prompts.where((p) {
      final q = _promptSearchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) || p.content.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: '搜索提示词...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      ),
                      onChanged: (v) => setState(() => _promptSearchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _arePromptsExpanded ? '全部折叠' : '全部展开',
                    icon: Icon(_arePromptsExpanded ? Icons.unfold_less : Icons.unfold_more),
                    onPressed: () {
                      setState(() {
                        _arePromptsExpanded = !_arePromptsExpanded;
                        _promptsExpansionVersion++;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _prompts.add(PresetPrompt(identifier: const Uuid().v4(), name: 'New Prompt', role: 'system', content: ''));
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('添加新的 Prompt 模块'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple[50],
                  foregroundColor: Colors.deepPurple,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _promptSearchQuery.isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredPrompts.length,
                  itemBuilder: (context, index) {
                    return _buildPromptCard(filteredPrompts[index], index, false);
                  },
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _prompts.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = _prompts.removeAt(oldIndex);
                      _prompts.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    return _buildPromptCard(_prompts[index], index, true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPromptCard(PresetPrompt prompt, int index, bool reorderable) {
    return Card(
      key: ValueKey('${prompt.identifier}_$_promptsExpansionVersion'),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.deepPurpleAccent)),
      child: ExpansionTile(
        initiallyExpanded: _arePromptsExpanded,
        shape: const Border(),
        leading: reorderable ? const Icon(Icons.drag_handle, color: Colors.grey) : null,
        title: Row(
          children: [
            Expanded(
              child: Text(prompt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
              child: Text(prompt.role, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.power_settings_new, color: prompt.enabled ? Colors.green : Colors.grey),
              onPressed: () {
                setState(() {
                  // Find index in original list
                  final originalIndex = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                  if (originalIndex != -1) {
                     _prompts[originalIndex] = prompt.copyWith(enabled: !prompt.enabled);
                  }
                });
              },
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.name,
                        decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder()),
                        onChanged: (v) {
                          setState(() {
                            final idx = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                            if (idx != -1) _prompts[idx] = prompt.copyWith(name: v);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: prompt.role,
                        decoration: const InputDecoration(labelText: '角色 (ROLE)', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'system', child: Text('System')),
                          DropdownMenuItem(value: 'user', child: Text('User')),
                          DropdownMenuItem(value: 'assistant', child: Text('Assistant')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              final idx = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                              if (idx != -1) _prompts[idx] = prompt.copyWith(role: v);
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: prompt.content,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '内容', border: OutlineInputBorder()),
                  onChanged: (v) {
                     setState(() {
                       final idx = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                       if (idx != -1) _prompts[idx] = prompt.copyWith(content: v);
                     });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.injectionDepth.toString(),
                        decoration: const InputDecoration(labelText: '深度 (DEPTH)', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          setState(() {
                            final idx = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                            if (idx != -1) _prompts[idx] = prompt.copyWith(injectionDepth: int.tryParse(v) ?? 0);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.injectionPosition.toString(),
                        decoration: const InputDecoration(labelText: '顺序 (ORDER)', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          setState(() {
                            final idx = _prompts.indexWhere((p) => p.identifier == prompt.identifier);
                            if (idx != -1) _prompts[idx] = prompt.copyWith(injectionPosition: int.tryParse(v) ?? 0);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _prompts.removeWhere((p) => p.identifier == prompt.identifier);
                          });
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                        child: const Text('删除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegexTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          onPressed: () {
             setState(() {
              _regexScripts.add(RegexScript(id: const Uuid().v4(), scriptName: 'New Regex', findRegex: '', replaceString: ''));
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('添加预设专属脚本'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[50],
            foregroundColor: Colors.amber[900],
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 16),
        if (_regexScripts.isEmpty)
          const Center(child: Text('没有正则脚本', style: TextStyle(color: Colors.grey))),
        ..._regexScripts.asMap().entries.map((entry) {
          final index = entry.key;
          final script = entry.value;
          return Card(
            key: ValueKey(script.id),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            child: ExpansionTile(
              shape: const Border(),
              title: Text(script.scriptName.isEmpty ? 'Untitled' : script.scriptName, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  setState(() => _regexScripts.removeAt(index));
                },
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Script Name
                      TextFormField(
                        initialValue: script.scriptName,
                        decoration: const InputDecoration(labelText: '脚本名称', border: OutlineInputBorder(), isDense: true),
                        onChanged: (v) => _updateRegex(index, scriptName: v),
                      ),
                      const SizedBox(height: 16),
                      
                      // Regex & Replacement
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('REGULAR EXPRESSION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.findRegex,
                              decoration: const InputDecoration(labelText: '查找正则 (REGEX)', hintText: '/pattern/flags', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                              onChanged: (v) => _updateRegex(index, findRegex: v),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.replaceString,
                              decoration: const InputDecoration(labelText: '替换为 (REPLACEMENT)', hintText: '\$1...', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                              maxLines: 2,
                              onChanged: (v) => _updateRegex(index, replaceString: v),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.trimString,
                              decoration: const InputDecoration(labelText: '修剪掉 (TRIM STRINGS)', hintText: 'One string per line to remove...', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                              onChanged: (v) => _updateRegex(index, trimString: v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Placement
                      const Text('作用范围 (PLACEMENT)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFilterChip('用户输入', script.placement.contains(1), (v) {
                            final p = List<int>.from(script.placement);
                            if (v) p.add(1); else p.remove(1);
                            _updateRegex(index, placement: p);
                          }),
                          _buildFilterChip('AI 输出', script.placement.contains(2), (v) {
                            final p = List<int>.from(script.placement);
                            if (v) p.add(2); else p.remove(2);
                            _updateRegex(index, placement: p);
                          }),
                          _buildFilterChip('世界信息', script.placement.contains(3), (v) { // Mock 3 for World Info
                             final p = List<int>.from(script.placement);
                            if (v) p.add(3); else p.remove(3);
                            _updateRegex(index, placement: p);
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Other Options
                      const Text('其他选项', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      CheckboxListTile(
                        title: const Text('已禁用 (Disabled)'),
                        value: script.disabled,
                        onChanged: (v) => _updateRegex(index, disabled: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('在编辑时运行 (Run on Edit)'),
                        value: script.runOnEdit,
                        onChanged: (v) => _updateRegex(index, runOnEdit: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('仅格式显示 (Markdown Only)'),
                        value: script.markdownOnly,
                        onChanged: (v) => _updateRegex(index, markdownOnly: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('仅格式提示词 (Prompt Only)'),
                        value: script.promptOnly,
                        onChanged: (v) => _updateRegex(index, promptOnly: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      
                      // Macros
                      DropdownButtonFormField<int>(
                        value: script.substituteRegex,
                        decoration: const InputDecoration(labelText: '正则查找时的宏 (SUBSTITUTE REGEX)', border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('不替换 (None)')),
                          DropdownMenuItem(value: 1, child: Text('User Name')),
                          DropdownMenuItem(value: 2, child: Text('Character Name')),
                        ],
                        onChanged: (v) => _updateRegex(index, substituteRegex: v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: script.minDepth?.toString(),
                              decoration: const InputDecoration(labelText: '最小深度', hintText: '无限制', border: OutlineInputBorder(), isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _updateRegex(index, minDepth: int.tryParse(v)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: script.maxDepth?.toString(),
                              decoration: const InputDecoration(labelText: '最大深度', hintText: '无限制', border: OutlineInputBorder(), isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _updateRegex(index, maxDepth: int.tryParse(v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => setState(() => _regexScripts.removeAt(index)),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('删除脚本'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool selected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: Colors.indigo[100],
      checkmarkColor: Colors.indigo,
      labelStyle: TextStyle(color: selected ? Colors.indigo : Colors.black),
    );
  }

  void _updateRegex(int index, {
    String? scriptName, String? findRegex, String? replaceString, String? trimString,
    List<int>? placement, bool? disabled, bool? markdownOnly, bool? runOnEdit, bool? promptOnly,
    int? substituteRegex, int? minDepth, int? maxDepth
  }) {
    setState(() {
      final old = _regexScripts[index];
      _regexScripts[index] = RegexScript(
        id: old.id,
        scriptName: scriptName ?? old.scriptName,
        findRegex: findRegex ?? old.findRegex,
        replaceString: replaceString ?? old.replaceString,
        trimString: trimString ?? old.trimString,
        placement: placement ?? old.placement,
        disabled: disabled ?? old.disabled,
        markdownOnly: markdownOnly ?? old.markdownOnly,
        runOnEdit: runOnEdit ?? old.runOnEdit,
        promptOnly: promptOnly ?? old.promptOnly,
        substituteRegex: substituteRegex ?? old.substituteRegex,
        minDepth: minDepth ?? old.minDepth,
        maxDepth: maxDepth ?? old.maxDepth,
      );
    });
  }
}
