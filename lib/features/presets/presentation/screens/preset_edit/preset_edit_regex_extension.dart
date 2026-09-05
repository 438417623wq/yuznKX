part of '../preset_edit_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _PresetEditRegexExtension on _PresetEditScreenState {
  Widget _buildRegexTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _regexScripts.add(
                RegexScript(
                  id: const Uuid().v4(),
                  scriptName: '新正则',
                  findRegex: '',
                  replaceString: '',
                ),
              );
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('添加预设专属脚本'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _PresetEditScreenState._accentSoftColor,
            foregroundColor: _PresetEditScreenState._accentColor,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 16),
        if (_regexScripts.isEmpty)
          const Center(
            child: Text('暂无正则脚本',
                style: TextStyle(
                    color: _PresetEditScreenState._textSecondaryColor)),
          ),
        ..._regexScripts.asMap().entries.map((entry) {
          final index = entry.key;
          final script = entry.value;
          return Card(
            key: ValueKey(script.id),
            margin: const EdgeInsets.only(bottom: 16),
            color: _PresetEditScreenState._surfaceColor,
            shape: _sectionShape(12),
            child: ExpansionTile(
              shape: const Border(),
              title: Text(
                script.scriptName.isEmpty ? '未命名脚本' : script.scriptName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete,
                    color: _PresetEditScreenState._dangerColor),
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
                      TextFormField(
                        initialValue: script.scriptName,
                        decoration: const InputDecoration(
                          labelText: '脚本名称',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => _updateRegex(index, scriptName: v),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _PresetEditScreenState._accentSoftColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _PresetEditScreenState._accentColor
                                  .withValues(alpha: 0.28)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'REGULAR EXPRESSION',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _PresetEditScreenState._accentColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.findRegex,
                              decoration: const InputDecoration(
                                labelText: '查找正则 (Regex)',
                                hintText: '/pattern/flags',
                              ),
                              onChanged: (v) =>
                                  _updateRegex(index, findRegex: v),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.replaceString,
                              decoration: const InputDecoration(
                                labelText: '替换文本 (Replacement)',
                                hintText: '\$1...',
                              ),
                              maxLines: 2,
                              onChanged: (v) =>
                                  _updateRegex(index, replaceString: v),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: script.trimString,
                              decoration: const InputDecoration(
                                labelText: '裁剪字符串 (Trim Strings)',
                                hintText: '每行一个要移除的字符串',
                              ),
                              onChanged: (v) =>
                                  _updateRegex(index, trimString: v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '作用范围 (Placement)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _PresetEditScreenState._textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFilterChip('用户输入', script.placement.contains(1),
                              (v) {
                            final p = <int>{...script.placement};
                            if (v) {
                              p.add(1);
                            } else {
                              p.remove(1);
                            }
                            _updateRegex(index, placement: p.toList()..sort());
                          }),
                          _buildFilterChip(
                              'AI 输出', script.placement.contains(2), (v) {
                            final p = <int>{...script.placement};
                            if (v) {
                              p.add(2);
                            } else {
                              p.remove(2);
                            }
                            _updateRegex(index, placement: p.toList()..sort());
                          }),
                          _buildFilterChip('世界信息', script.placement.contains(3),
                              (v) {
                            final p = <int>{...script.placement};
                            if (v) {
                              p.add(3);
                            } else {
                              p.remove(3);
                            }
                            _updateRegex(index, placement: p.toList()..sort());
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '其他选项',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _PresetEditScreenState._textSecondaryColor,
                        ),
                      ),
                      CheckboxListTile(
                        title: const Text('禁用 (Disabled)'),
                        value: script.disabled,
                        onChanged: (v) => _updateRegex(index, disabled: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('编辑时运行 (Run on Edit)'),
                        value: script.runOnEdit,
                        onChanged: (v) => _updateRegex(index, runOnEdit: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('仅 Markdown (Markdown Only)'),
                        value: script.markdownOnly,
                        onChanged: (v) => _updateRegex(index, markdownOnly: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        title: const Text('仅提示词 (Prompt Only)'),
                        value: script.promptOnly,
                        onChanged: (v) => _updateRegex(index, promptOnly: v),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: script.substituteRegex,
                        decoration: const InputDecoration(
                          labelText: '替换宏 (Substitute Regex)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('不替换 (None)')),
                          DropdownMenuItem(value: 1, child: Text('User Name')),
                          DropdownMenuItem(
                              value: 2, child: Text('Character Name')),
                        ],
                        onChanged: (v) =>
                            _updateRegex(index, substituteRegex: v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: script.minDepth?.toString(),
                              decoration: const InputDecoration(
                                labelText: '最小深度',
                                hintText: '无限制',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onChanged: (v) => _updateRegex(index,
                                  minDepth: int.tryParse(v)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: script.maxDepth?.toString(),
                              decoration: const InputDecoration(
                                labelText: '最大深度',
                                hintText: '无限制',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onChanged: (v) => _updateRegex(index,
                                  maxDepth: int.tryParse(v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _regexScripts.removeAt(index)),
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  _PresetEditScreenState._dangerColor),
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

  Widget _buildFilterChip(
      String label, bool selected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: _PresetEditScreenState._surfaceAltColor,
      selectedColor: _PresetEditScreenState._accentSoftColor,
      checkmarkColor: _PresetEditScreenState._accentColor,
      side: BorderSide(
        color: selected
            ? _PresetEditScreenState._accentColor.withValues(alpha: 0.45)
            : _PresetEditScreenState._borderColor,
      ),
      labelStyle: TextStyle(
        color: selected
            ? _PresetEditScreenState._accentColor
            : _PresetEditScreenState._textPrimaryColor,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  void _updateRegex(int index,
      {String? scriptName,
      String? findRegex,
      String? replaceString,
      String? trimString,
      List<int>? placement,
      bool? disabled,
      bool? markdownOnly,
      bool? runOnEdit,
      bool? promptOnly,
      int? substituteRegex,
      int? minDepth,
      int? maxDepth}) {
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
