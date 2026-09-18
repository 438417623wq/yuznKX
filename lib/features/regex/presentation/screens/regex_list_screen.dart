import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/file_helper.dart';
import '../../data/regex_provider.dart';
import '../../domain/models/regex_script.dart';

class RegexListScreen extends ConsumerWidget {
  const RegexListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(regexScriptsProvider);
    final activeIds = ref.watch(activeRegexScriptIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('正则脚本 (Regex)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: '导入脚本',
            onPressed: () async {
              try {
                final result = await FileHelper.pickJson();
                if (result != null) {
                  final json = result.data;
                  if (json is Map<String, dynamic>) {
                    var script = RegexScript.fromJson(json);
                     // Use filename if script name is default
                    if (script.scriptName == 'Untitled Script' || json['scriptName'] == null) {
                      script = RegexScript(
                        id: script.id,
                        scriptName: result.name,
                        findRegex: script.findRegex,
                        replaceString: script.replaceString,
                        placement: script.placement,
                        disabled: script.disabled,
                        markdownOnly: script.markdownOnly,
                      );
                    }
                    await ref.read(regexScriptsProvider.notifier).save(script);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入成功: ${script.scriptName}')));
                    }
                  } else {
                     if (context.mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入失败: 无效的 JSON 格式')));
                     }
                  }
                }
              } catch (e) {
                 if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
                 }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RegexEditScreen()));
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          final isActive = activeIds.contains(item.id);
          return ListTile(
            title: Text(item.scriptName),
            subtitle: Text('Regex: ${item.findRegex}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isActive,
                  onChanged: (val) {
                    ref.read(activeRegexScriptIdsProvider.notifier).toggle(item.id);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    FileHelper.exportJson(item.toJson(), item.scriptName);
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => RegexEditScreen(script: item)));
            },
          );
        },
      ),
    );
  }
}

class RegexEditScreen extends ConsumerStatefulWidget {
  final RegexScript? script;
  const RegexEditScreen({super.key, this.script});

  @override
  ConsumerState<RegexEditScreen> createState() => _RegexEditScreenState();
}

class _RegexEditScreenState extends ConsumerState<RegexEditScreen> {
  final _nameCtrl = TextEditingController();
  final _regexCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _trimCtrl = TextEditingController();
  final _minDepthCtrl = TextEditingController();
  final _maxDepthCtrl = TextEditingController();

  List<int> _placement = [1, 2];
  bool _disabled = false;
  bool _runOnEdit = false;
  bool _markdownOnly = false;
  bool _promptOnly = false;
  int _substituteRegex = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.script;
    _nameCtrl.text = s?.scriptName ?? '新建正则';
    _regexCtrl.text = s?.findRegex ?? '';
    _replaceCtrl.text = s?.replaceString ?? '';
    _trimCtrl.text = s?.trimString ?? '';
    _minDepthCtrl.text = s?.minDepth?.toString() ?? '';
    _maxDepthCtrl.text = s?.maxDepth?.toString() ?? '';

    _placement = s?.placement.toList() ?? [1, 2];
    _disabled = s?.disabled ?? false;
    _runOnEdit = s?.runOnEdit ?? false;
    _markdownOnly = s?.markdownOnly ?? false;
    _promptOnly = s?.promptOnly ?? false;
    _substituteRegex = s?.substituteRegex ?? 0;
  }

  void _save() {
    if (_nameCtrl.text.isEmpty) return;

    final newItem = RegexScript(
      id: widget.script?.id ?? const Uuid().v4(),
      scriptName: _nameCtrl.text,
      findRegex: _regexCtrl.text,
      replaceString: _replaceCtrl.text,
      trimString: _trimCtrl.text,
      placement: _placement,
      disabled: _disabled,
      runOnEdit: _runOnEdit,
      markdownOnly: _markdownOnly,
      promptOnly: _promptOnly,
      substituteRegex: _substituteRegex,
      minDepth: int.tryParse(_minDepthCtrl.text),
      maxDepth: int.tryParse(_maxDepthCtrl.text),
    );

    ref.read(regexScriptsProvider.notifier).save(newItem);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正则脚本编辑器', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
           TextButton(
            onPressed: _save,
            style: TextButton.styleFrom(
              backgroundColor: Colors.indigo.shade50,
              foregroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Script Name
          const Text('脚本名称', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl, 
            decoration: InputDecoration(
              hintText: '输入正则脚本名称', 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Regex & Replacement Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text('正则表达式 (REGULAR EXPRESSION)', 
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700, letterSpacing: 1.0)
                  ),
                ),
                const SizedBox(height: 16),
                _buildLabel('查找正则 (REGEX)'),
                TextField(
                  controller: _regexCtrl, 
                  decoration: _buildInputDecoration('/pattern/flags'),
                ),
                const SizedBox(height: 16),
                _buildLabel('替换为 (REPLACEMENT)'),
                TextField(
                  controller: _replaceCtrl, 
                  decoration: _buildInputDecoration('\$1...'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildLabel('修剪掉 (TRIM STRINGS)'),
                TextField(
                  controller: _trimCtrl, 
                  decoration: _buildInputDecoration('每行一个要去除的字符串...'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Placement Section
          const Text('作用范围 (PLACEMENT)', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildPlacementChip('用户输入', 1),
              _buildPlacementChip('AI 输出', 2),
              _buildPlacementChip('世界信息', 3),
              _buildPlacementChip('推理内容', 4), // Mock ID
            ],
          ),
          const SizedBox(height: 24),

          // Other Options
          const Text('其他选项', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildSwitchTile('已禁用 (Disabled)', _disabled, (v) => setState(() => _disabled = v)),
                const Divider(height: 1),
                _buildSwitchTile('在编辑时运行 (Run on Edit)', _runOnEdit, (v) => setState(() => _runOnEdit = v)),
                const Divider(height: 1),
                _buildSwitchTile('仅格式显示 (Markdown Only)', _markdownOnly, (v) => setState(() => _markdownOnly = v)),
                const Divider(height: 1),
                _buildSwitchTile('仅格式提示词 (Prompt Only)', _promptOnly, (v) => setState(() => _promptOnly = v)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Macros & Depth
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('正则查找时的宏替换 (SUBSTITUTE REGEX)'),
                DropdownButtonFormField<int>(
                  value: _substituteRegex,
                  decoration: _buildInputDecoration(''),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('不替换 (None)')),
                    DropdownMenuItem(
                        value: 1, child: Text('用户名 (User Name)')),
                    DropdownMenuItem(
                        value: 2, child: Text('角色名 (Character Name)')),
                  ],
                  onChanged: (v) => setState(() => _substituteRegex = v ?? 0),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('最小深度'),
                          TextField(
                            controller: _minDepthCtrl,
                            decoration: _buildInputDecoration('无限制'),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('最大深度'),
                          TextField(
                            controller: _maxDepthCtrl,
                            decoration: _buildInputDecoration('无限制'),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          if (widget.script != null)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: () {
                   showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除脚本'),
                      content: const Text('确定要删除这个脚本吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                        TextButton(
                          onPressed: () {
                            ref.read(regexScriptsProvider.notifier).delete(widget.script!.id);
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                          child: const Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('删除脚本', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildPlacementChip(String label, int id) {
    final selected = _placement.contains(id);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) => setState(() {
        if (v) _placement.add(id); else _placement.remove(id);
      }),
      selectedColor: Colors.indigo.shade100,
      checkmarkColor: Colors.indigo,
      labelStyle: TextStyle(
        color: selected ? Colors.indigo : Colors.grey[700],
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? Colors.indigo.shade100 : Colors.grey.shade300),
      ),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeColor: Colors.indigo,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
