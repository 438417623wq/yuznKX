part of '../preset_project_screen.dart';

/// 阶段一：需求对齐。
///
/// 这一屏决定后面所有生成的方向 —— 相当于角色工坊的「设计需求」阶段。
/// 所有选项都是**可点即改**，没有「保存」按钮。
extension _PresetBriefStage on _PresetProjectScreenState {
  List<Widget> _buildBriefStage(
    PresetProject project,
    PresetProjectState state,
  ) {
    final brief = project.brief;
    return <Widget>[
      WorkshopWidgets.card(
        title: '这一屏在定什么',
        accentColor: kPresetAccent,
        subtitle: '预设的本质是「按顺序发给模型的一串消息」。'
            '顺序决定了注意力分布 —— 开头顶部最强，中间最弱，底部次强。'
            '所以先定「要做什么」，再定「怎么排」。',
        children: [
          if (!brief.isComplete)
            const Text(
              '⚠️ 扮演方式选了「自定义」，需要写一句描述才能继续。',
              style: TextStyle(color: WorkshopColors.warning, fontSize: 12),
            ),
        ],
      ),
      const SizedBox(height: 12),

      // --- 扮演方式 ---
      WorkshopWidgets.card(
        title: '扮演方式',
        accentColor: kPresetAccent,
        children: [
          for (final mode in RpMode.values)
            _briefOption(
              label: mode.label,
              description: mode.description,
              selected: brief.rpMode == mode,
              onTap: () => _updateBrief(
                project,
                brief.copyWith(rpMode: mode),
              ),
            ),
          if (brief.rpMode == RpMode.custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _briefController(
                key: 'rpModeNote',
                value: brief.rpModeNote,
                onChanged: (text) => _updateBrief(
                  project,
                  brief.copyWith(rpModeNote: text),
                ),
              ),
              maxLines: 3,
              style: const TextStyle(
                color: WorkshopColors.textPrimary,
                fontSize: 12,
              ),
              decoration: WorkshopWidgets.inputDecoration(
                '用一句话描述你想要的扮演方式',
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),

      // --- 目标渠道 ---
      WorkshopWidgets.card(
        title: '目标渠道',
        accentColor: kPresetAccent,
        subtitle: '不同渠道对提示词的「甲」和注意力分布不一样，'
            '结构建议与破限档位会跟着变。',
        children: [
          for (final channel in TargetChannel.values)
            _briefOption(
              label: channel.label,
              description: channel.description,
              selected: brief.channel == channel,
              badge: '建议破限：${channel.suggestedLevel.label}',
              onTap: () {
                // 换渠道时把破限档位跟着调到建议值 —— 用户还能再改。
                _updateBrief(
                  project,
                  brief.copyWith(
                    channel: channel,
                    jailbreakLevel: channel.suggestedLevel,
                  ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 12),

      // --- 人称与输出量 ---
      WorkshopWidgets.card(
        title: '人称与输出量',
        accentColor: kPresetAccent,
        children: [
          WorkshopWidgets.sectionLabel('叙事人称'),
          const SizedBox(height: 8),
          WorkshopWidgets.segmentedRow<PovMode>(
            values: PovMode.values,
            selected: brief.pov,
            label: (value) => value.label,
            onChanged: (value) =>
                _updateBrief(project, brief.copyWith(pov: value)),
          ),
          const SizedBox(height: 6),
          Text(
            brief.pov.description,
            style: const TextStyle(
              color: WorkshopColors.textHint,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          WorkshopWidgets.sectionLabel('建议单次输出字数：约 ${brief.wordLimit} 字'),
          Slider(
            value: brief.wordLimit.toDouble().clamp(200, 2000),
            min: 200,
            max: 2000,
            divisions: 18,
            // ⛔ Slider 只有 `activeColor`（未废弃）。
            // `activeThumbColor` 是 Switch / SwitchListTile 的参数，别搞混。
            activeColor: kPresetAccent,
            label: '${brief.wordLimit}',
            onChanged: (value) => _updateBrief(
              project,
              brief.copyWith(wordLimit: (value / 100).round() * 100),
            ),
          ),
          const SizedBox(height: 4),
          WorkshopWidgets.sectionLabel('输出语言'),
          const SizedBox(height: 8),
          WorkshopWidgets.segmentedRow<String>(
            values: const <String>['zh-cn', 'en'],
            selected: brief.language,
            label: (value) => value == 'zh-cn' ? '简体中文' : 'English',
            onChanged: (value) =>
                _updateBrief(project, brief.copyWith(language: value)),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // --- 文风 ---
      WorkshopWidgets.card(
        title: '文风要求',
        accentColor: kPresetAccent,
        subtitle: '点一下加入，再点一下取消。也可以自己写。',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in kStyleTagSuggestions)
                WorkshopWidgets.chip(
                  label: tag,
                  selected: brief.styleTags.contains(tag),
                  accentColor: kPresetAccent,
                  onTap: () {
                    final next = List<String>.from(brief.styleTags);
                    if (!next.remove(tag)) {
                      next.add(tag);
                    }
                    _updateBrief(project, brief.copyWith(styleTags: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _briefController(
              key: 'styleTags',
              value: brief.styleTags
                  .where((tag) => !kStyleTagSuggestions.contains(tag))
                  .join('、'),
              onChanged: (text) {
                final custom = text
                    .split(RegExp(r'[,，、;；]'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false);
                final preset = brief.styleTags
                    .where(kStyleTagSuggestions.contains)
                    .toList();
                _updateBrief(
                  project,
                  brief.copyWith(styleTags: <String>[...preset, ...custom]),
                );
              },
            ),
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 12,
            ),
            decoration: WorkshopWidgets.inputDecoration(
              '自定义文风，用顿号分隔（例如：冷硬、克制、大量留白）',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // --- 破限 ---
      WorkshopWidgets.card(
        title: '破限档位',
        accentColor: WorkshopColors.warning,
        subtitle: '「构建破限就像医生开药，直接下猛药当然可以药到病除，'
            '但对身体的破坏也很大」—— 从低档试起，不够再往上加。',
        children: [
          for (final level in JailbreakLevel.values)
            _briefOption(
              label: level.label,
              description: level.description,
              selected: brief.jailbreakLevel == level,
              accentColor: WorkshopColors.warning,
              onTap: () =>
                  _updateBrief(project, brief.copyWith(jailbreakLevel: level)),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WorkshopColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '⚠️ 破限正文要你自己填 —— 它和渠道、模型强绑定，通用模板基本没用。'
              '工坊只负责把位置留好、把结构排对，不会代写破限文本。',
              style: TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // --- COT ---
      WorkshopWidgets.card(
        title: '末尾伪造思考块',
        accentColor: kPresetAccent,
        subtitle: '在最后放一条 assistant 消息，里面是一段「假装已经想好了」的思路。'
            '模型会顺着这个思路往下写，同时天然形成 prefill。',
        children: [
          // 用裸 Switch 而不是 SwitchListTile：SwitchListTile 的
          // `activeColor` 已废弃、替代参数叫 `activeThumbColor`，
          // 而 Slider 的替代参数**不叫这个**（Slider 只有 `activeColor`）。
          // 两个控件参数名不一致，裸 Switch + 自绘标题最不容易搞错。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '要一段伪造思考（COT）',
                      style: TextStyle(
                        color: WorkshopColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '适合需要「先推理再落笔」的场景；纯氛围向扮演可以关掉',
                      style: TextStyle(
                        color: WorkshopColors.textHint,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: brief.wantCot,
                activeThumbColor: kPresetAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) =>
                    _updateBrief(project, brief.copyWith(wantCot: value)),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),

      // --- 其它 ---
      WorkshopWidgets.card(
        title: '其它补充',
        accentColor: kPresetAccent,
        subtitle: '任何上面没覆盖到的要求，直接写在这里，会原样喂给 AI。',
        children: [
          TextField(
            controller: _briefController(
              key: 'extraNotes',
              value: brief.extraNotes,
              onChanged: (text) =>
                  _updateBrief(project, brief.copyWith(extraNotes: text)),
            ),
            maxLines: 4,
            style: const TextStyle(
              color: WorkshopColors.textPrimary,
              fontSize: 12,
            ),
            decoration: WorkshopWidgets.inputDecoration(
              '例如：不要替玩家做决定；每次回复结尾留一个开放式选择',
            ),
          ),
        ],
      ),
    ];
  }

  // --- 小组件 ---

  Widget _briefOption({
    required String label,
    required String description,
    required bool selected,
    required VoidCallback onTap,
    String? badge,
    Color? accentColor,
  }) {
    final tint = accentColor ?? kPresetAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected
                ? WorkshopColors.accentSoft
                : WorkshopColors.surfaceSoft,
            borderRadius: BorderRadius.circular(WorkshopMetrics.fieldRadius),
            border: Border.all(
              color: selected ? tint : WorkshopColors.stroke,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 15,
                color: selected ? tint : WorkshopColors.textHint,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: selected
                                ? WorkshopColors.textPrimary
                                : WorkshopColors.textSecondary,
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: WorkshopColors.surfaceSunken,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: WorkshopColors.textHint,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: WorkshopColors.textHint,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateBrief(PresetProject project, PresetBrief brief) {
    ref.read(presetProjectProvider.notifier).updateBrief(project.id, brief);
  }
}
