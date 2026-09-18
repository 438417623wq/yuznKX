import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/file_helper.dart';
import '../../../character/data/character_provider.dart';
import '../../../character/domain/models/character.dart';
import '../../data/regex_provider.dart';
import '../../domain/models/regex_script.dart';

/// 全局正则列表。
///
/// 列表按两层折叠组织，避免「一张角色卡导入几十条正则」时全量平铺：
/// - 一级：按「全局生效 / 未启用」分组（对应 `active_regex_ids` 的启用状态）
/// - 二级：按来源分组（来自角色卡 X / 手动创建）
///
/// 注意：全局正则池（Box `regex_scripts`）**没有 owner 字段**，
/// 无法直接得知某个脚本来自哪张卡，因此来源靠反查所有角色卡的
/// `regexScriptIds` 与 `globalRegexIds` 得出（见 [_buildOwnersByRegexId]）。
class RegexListScreen extends ConsumerWidget {
  const RegexListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(regexScriptsProvider);
    final activeIds = ref.watch(activeRegexScriptIdsProvider);
    final characters = ref.watch(characterListProvider);

    final ownersByRegexId = _buildOwnersByRegexId(characters);
    final activeSet = activeIds.toSet();
    final activeItems =
        list.where((item) => activeSet.contains(item.id)).toList(growable: false);
    final inactiveItems = list
        .where((item) => !activeSet.contains(item.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局正则 (Global Regex)'),
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
            tooltip: '新建正则',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RegexEditScreen()));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildGlobalActiveSection(context, ref, activeItems),
          const SizedBox(height: 22),
          _buildAllSectionHeader(list.length),
          const SizedBox(height: 10),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('还没有正则脚本，点击右上角「新建」或「导入」添加。',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else ...[
            _buildStatusGroup(
              context: context,
              ref: ref,
              title: '全局生效',
              subtitle: '对所有角色卡自动生效',
              icon: Icons.public,
              color: Colors.green,
              items: activeItems,
              ownersByRegexId: ownersByRegexId,
              initiallyExpanded: true,
              isActiveGroup: true,
              emptyHint: '暂无全局生效的正则。在下方「未启用」分组里打开开关即可添加。',
            ),
            const SizedBox(height: 10),
            _buildStatusGroup(
              context: context,
              ref: ref,
              title: '未启用',
              subtitle: '仅保存在资源池中，不参与任何处理',
              icon: Icons.power_off_outlined,
              color: Colors.grey,
              items: inactiveItems,
              ownersByRegexId: ownersByRegexId,
              initiallyExpanded: false,
              isActiveGroup: false,
              emptyHint: '所有正则都已全局生效。',
            ),
          ],
        ],
      ),
    );
  }

  /// 反查：脚本 ID → 引用它的角色卡列表。
  ///
  /// 同时扫描 [Character.regexScriptIds]（随卡导入）与
  /// [Character.globalRegexIds]（本卡引用的全局正则）。
  Map<String, List<Character>> _buildOwnersByRegexId(
      List<Character> characters) {
    final owners = <String, List<Character>>{};
    for (final character in characters) {
      final ids = <String>{
        ...character.regexScriptIds,
        ...character.globalRegexIds,
      };
      for (final raw in ids) {
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        owners.putIfAbsent(normalized, () => <Character>[]).add(character);
      }
    }
    return owners;
  }

  /// 「全局生效」置顶区块：集中展示对所有角色生效的正则。
  Widget _buildGlobalActiveSection(
    BuildContext context,
    WidgetRef ref,
    List<RegexScript> activeItems,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 20, color: Colors.green.shade400),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('全局生效（对所有角色）',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${activeItems.length} 个',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade300,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '勾选后对全部角色卡自动生效，无需在每张卡里单独启用。'
            '（角色卡自带正则请到角色卡「绑定」页设置）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (activeItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '暂无全局生效的正则。在下方列表中打开「全局生效」开关即可添加。',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            )
          else
            for (final item in activeItems)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.code, size: 18, color: Colors.green.shade400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.scriptName,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            item.disabled
                                ? '自身已禁用（不会生效）'
                                : '已生效',
                            style: TextStyle(
                              fontSize: 11,
                              color: item.disabled
                                  ? Colors.orange.shade300
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '取消全局生效',
                      icon: Icon(Icons.remove_circle_outline,
                          size: 20, color: Colors.green.shade300),
                      onPressed: () => ref
                          .read(activeRegexScriptIdsProvider.notifier)
                          .setActive(item.id, false),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    RegexEditScreen(script: item)));
                      },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAllSectionHeader(int total) {
    return Row(
      children: [
        const Icon(Icons.list_alt, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        const Text('全部正则',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text('共 $total 个',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  /// 一级分组：按「全局生效 / 未启用」。
  Widget _buildStatusGroup({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String subtitle,
    required IconData icon,
    required MaterialColor color,
    required List<RegexScript> items,
    required Map<String, List<Character>> ownersByRegexId,
    required bool initiallyExpanded,
    required bool isActiveGroup,
    required String emptyHint,
  }) {
    final sourceGroups = _groupBySource(items, ownersByRegexId);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          leading: Icon(icon, color: color.shade300, size: 22),
          title: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length} 个',
                  style: TextStyle(
                      fontSize: 12,
                      color: color.shade300,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(emptyHint,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              )
            else ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => ref
                      .read(activeRegexScriptIdsProvider.notifier)
                      .setMany(items.map((e) => e.id), !isActiveGroup),
                  icon: Icon(
                      isActiveGroup ? Icons.toggle_off : Icons.toggle_on,
                      size: 18),
                  label: Text(isActiveGroup ? '全部停用' : '全部启用'),
                ),
              ),
              for (final entry in sourceGroups.entries)
                _buildSourceGroup(
                  context: context,
                  ref: ref,
                  sourceLabel: entry.key,
                  items: entry.value,
                  ownersByRegexId: ownersByRegexId,
                  color: color,
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 二级分组：按来源（来自角色卡 X / 手动创建）。
  Widget _buildSourceGroup({
    required BuildContext context,
    required WidgetRef ref,
    required String sourceLabel,
    required List<RegexScript> items,
    required Map<String, List<Character>> ownersByRegexId,
    required MaterialColor color,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          leading: const Icon(Icons.folder_outlined,
              size: 18, color: Colors.grey),
          title: Row(
            children: [
              Expanded(
                child: Text(sourceLabel,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text('${items.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          children: [
            for (final item in items)
              _buildRegexTile(
                context: context,
                ref: ref,
                item: item,
                ownersByRegexId: ownersByRegexId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegexTile({
    required BuildContext context,
    required WidgetRef ref,
    required RegexScript item,
    required Map<String, List<Character>> ownersByRegexId,
  }) {
    final isActive =
        ref.watch(activeRegexScriptIdsProvider).contains(item.id);
    final owners = ownersByRegexId[item.id.trim()] ?? const <Character>[];
    final rawPreview = item.findRegex.replaceAll('\n', ' ');
    final preview = rawPreview.length > 46
        ? '${rawPreview.substring(0, 46)}...'
        : rawPreview;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 4),
      title: Text(item.scriptName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.isEmpty ? '（空正则）' : preview,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (owners.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '被 ${owners.map((c) => '「${c.name}」').join('、')} 引用',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (isActive || item.disabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (isActive) _buildStatusChip('已全局生效', Colors.green),
                  if (item.disabled)
                    _buildStatusChip('自身已禁用', Colors.orange),
                ],
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('全局生效',
              style: TextStyle(
                fontSize: 10,
                color: isActive ? Colors.green.shade300 : Colors.grey,
              )),
          Switch(
            value: isActive,
            activeThumbColor: Colors.green,
            onChanged: (val) => ref
                .read(activeRegexScriptIdsProvider.notifier)
                .setActive(item.id, val),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => RegexEditScreen(script: item)));
      },
    );
  }

  Widget _buildStatusChip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color.shade300,
              fontWeight: FontWeight.w600)),
    );
  }

  /// 把一批脚本按来源分组。
  ///
  /// 分组顺序：有归属的组按条目数降序在前，「手动创建 / 未归属」固定最后。
  Map<String, List<RegexScript>> _groupBySource(
    List<RegexScript> items,
    Map<String, List<Character>> ownersByRegexId,
  ) {
    const manualKey = '手动创建 / 未归属';
    final groups = <String, List<RegexScript>>{};

    for (final item in items) {
      final owners = ownersByRegexId[item.id.trim()] ?? const <Character>[];
      final String key;
      if (owners.isEmpty) {
        key = manualKey;
      } else if (owners.length == 1) {
        key = '来自角色卡「${owners.first.name}」';
      } else {
        key = '多张角色卡共享（${owners.length} 张）';
      }
      groups.putIfAbsent(key, () => <RegexScript>[]).add(item);
    }

    final owned = groups.entries
        .where((e) => e.key != manualKey)
        .toList(growable: false)
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return <String, List<RegexScript>>{
      for (final entry in owned) entry.key: entry.value,
      if (groups.containsKey(manualKey)) manualKey: groups[manualKey]!,
    };
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
