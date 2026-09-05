part of '../preset_edit_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _PresetEditPromptsExtension on _PresetEditScreenState {
  Widget _buildPromptsTab() {
    final filteredPrompts = _prompts.where((prompt) {
      final query = _promptSearchQuery.trim().toLowerCase();
      if (query.isEmpty) {
        return true;
      }
      return prompt.identifier.toLowerCase().contains(query) ||
          prompt.name.toLowerCase().contains(query) ||
          prompt.content.toLowerCase().contains(query);
    }).toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: '搜索 prompt…',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: _PresetEditScreenState._surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                            color: _PresetEditScreenState._borderColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                            color: _PresetEditScreenState._borderColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                            color: _PresetEditScreenState._accentColor,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _promptSearchQuery = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _arePromptsExpanded ? '全部折叠' : '全部展开',
                    icon: Icon(
                      _arePromptsExpanded
                          ? Icons.unfold_less
                          : Icons.unfold_more,
                    ),
                    color: _PresetEditScreenState._textSecondaryColor,
                    onPressed: () {
                      setState(() {
                        _arePromptsExpanded = !_arePromptsExpanded;
                        _promptsExpansionVersion++;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _prompts.add(
                      PresetPrompt(
                        identifier: const Uuid().v4(),
                        name: 'New Prompt',
                        role: 'system',
                        content: '',
                        injectionPosition: Preset.relativeInjectionPosition,
                        injectionDepth: 0,
                        injectionOrder: PresetPrompt.defaultInjectionOrder,
                        enabled: true,
                        systemPrompt: true,
                        legacyPositioning: false,
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('添加 Prompt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _PresetEditScreenState._accentSoftColor,
                  foregroundColor: _PresetEditScreenState._accentColor,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _promptSearchQuery.trim().isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredPrompts.length,
                  itemBuilder: (context, index) {
                    final prompt = filteredPrompts[index];
                    return _buildPromptCard(prompt, false);
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
                    return _buildPromptCard(_prompts[index], true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPromptCard(PresetPrompt prompt, bool reorderable) {
    return Card(
      key: ValueKey('${prompt.identifier}_$_promptsExpansionVersion'),
      margin: const EdgeInsets.only(bottom: 16),
      color: _PresetEditScreenState._surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _PresetEditScreenState._accentColor.withValues(alpha: 0.35),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: _arePromptsExpanded,
        shape: const Border(),
        leading: reorderable
            ? const Icon(
                Icons.drag_handle,
                color: _PresetEditScreenState._textSecondaryColor,
              )
            : null,
        title: Row(
          children: [
            Expanded(
              child: Text(
                prompt.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _PresetEditScreenState._accentSoftColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                prompt.role,
                style: const TextStyle(
                  fontSize: 12,
                  color: _PresetEditScreenState._accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.power_settings_new,
            color: prompt.enabled
                ? const Color(0xFF2E8C63)
                : _PresetEditScreenState._textSecondaryColor,
          ),
          onPressed: () {
            setState(() {
              _replacePrompt(
                prompt,
                prompt.copyWith(enabled: !prompt.enabled),
              );
            });
          },
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
                        readOnly: true,
                        initialValue: prompt.identifier,
                        decoration: const InputDecoration(
                          labelText: 'Identifier',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.name,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(name: value),
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: prompt.role,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text('System'),
                          ),
                          DropdownMenuItem(
                            value: 'user',
                            child: Text('User'),
                          ),
                          DropdownMenuItem(
                            value: 'assistant',
                            child: Text('Assistant'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(role: value),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: prompt.content,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _replacePrompt(
                        prompt,
                        prompt.copyWith(content: value),
                      );
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: prompt.injectionPosition,
                        decoration: const InputDecoration(
                          labelText: '注入位置',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: Preset.relativeInjectionPosition,
                            child: Text('相对顺序'),
                          ),
                          DropdownMenuItem(
                            value: Preset.absoluteInjectionPosition,
                            child: Text('绝对深度'),
                          ),
                          DropdownMenuItem(
                            value: Preset.attachExistingInjectionPosition,
                            child: Text('附着现有消息'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(injectionPosition: value),
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.injectionDepth.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Depth',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'-?\d+'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(
                                injectionDepth: int.tryParse(value) ?? 0,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: prompt.injectionOrder.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Order',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'-?\d+'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(
                                injectionOrder: int.tryParse(value) ??
                                    prompt.injectionOrder,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 210,
                      child: CheckboxListTile(
                        value: prompt.systemPrompt,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('System Prompt'),
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(systemPrompt: value ?? false),
                            );
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: CheckboxListTile(
                        value: prompt.marker,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Marker'),
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(marker: value ?? false),
                            );
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: CheckboxListTile(
                        value: prompt.legacyPositioning,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Legacy Positioning'),
                        onChanged: (value) {
                          setState(() {
                            _replacePrompt(
                              prompt,
                              prompt.copyWith(
                                legacyPositioning: value ?? false,
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (prompt.injectionPosition ==
                    Preset.attachExistingInjectionPosition) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: prompt.attachRole ?? 'system',
                          decoration: const InputDecoration(
                            labelText: 'Attach Role',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'system',
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: 'user',
                              child: Text('User'),
                            ),
                            DropdownMenuItem(
                              value: 'assistant',
                              child: Text('Assistant'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _replacePrompt(
                                prompt,
                                prompt.copyWith(attachRole: value),
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: prompt.attachIndex?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Attach Index',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              _replacePrompt(
                                prompt,
                                prompt.copyWith(
                                  attachIndex: int.tryParse(value),
                                ),
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: prompt.attachSide ?? 'end',
                          decoration: const InputDecoration(
                            labelText: 'Attach Side',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'start',
                              child: Text('Start'),
                            ),
                            DropdownMenuItem(
                              value: 'end',
                              child: Text('End'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _replacePrompt(
                                prompt,
                                prompt.copyWith(attachSide: value),
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _prompts.removeWhere(
                          (item) => item.identifier == prompt.identifier,
                        );
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _PresetEditScreenState._dangerColor,
                      side: const BorderSide(
                        color: _PresetEditScreenState._dangerColor,
                      ),
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _replacePrompt(PresetPrompt original, PresetPrompt updated) {
    final index =
        _prompts.indexWhere((item) => item.identifier == original.identifier);
    if (index == -1) {
      return;
    }
    _prompts[index] = updated;
  }
}
