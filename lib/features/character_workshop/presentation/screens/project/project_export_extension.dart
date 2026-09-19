part of '../project_screen.dart';

/// 阶段五：打包导出。
///
/// 这是整条链路的终点：把项目里的条目打包成一张 chara_card_v2 角色卡 +
/// 一个完整的 `character_book`，同时把世界书落进全局世界书池并回填 `characterBookId`，
/// 这样刚导出的卡在 App 内立刻就能用世界书。
extension _ProjectExportExtension on _ProjectScreenState {
  List<Widget> _buildExportStage(CardProject project, CardProjectState state) {
    final busy = state.busy;
    final packed = _actions.previewPack(project.id);

    return <Widget>[
      _buildCardPreview(project, packed, busy),
      const SizedBox(height: 12),
      _buildExportActions(project, busy),
      const SizedBox(height: 12),
      _buildMvuSection(project, busy),
      const SizedBox(height: 12),
      _buildSpecExport(project),
    ];
  }

  // --- 卡片预览 ---

  Widget _buildCardPreview(
    CardProject project,
    PackedCard? packed,
    bool busy,
  ) {
    final character = packed?.character;
    final worldbook = packed?.worldbook;
    final fieldCount = project.characterFieldEntries
        .where((entry) => entry.hasContent)
        .length;

    return WorkshopWidgets.card(
      title: '⑥ 导出',
      subtitle: '打包成角色卡与世界书',
      children: [
        _buildPreviewRow('角色名', character?.name ?? project.characterName),
        _buildPreviewRow(
          '角色卡字段',
          '$fieldCount 个已填',
        ),
        _buildPreviewRow(
          '世界书条目',
          worldbook == null ? '无' : '${worldbook.entries.length} 条',
          tint: worldbook == null ? WorkshopColors.textHint : WorkshopColors.worldbook,
        ),
        _buildPreviewRow(
          '前端面板',
          project.hasFrontend
              ? '${project.frontendHtml.length} 字符 · 附带挂载点正则'
              : '无',
          tint: project.hasFrontend
              ? WorkshopColors.stageDone
              : WorkshopColors.textHint,
        ),
        if (character != null && character.tags.isNotEmpty)
          _buildPreviewRow('标签', character.tags.join('、')),
        if (character != null && character.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: WorkshopColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
            ),
            child: Text(
              character.description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),
        ],
        if (worldbook != null) ...[
          const SizedBox(height: 12),
          WorkshopWidgets.sectionLabel('世界书条目一览'),
          const SizedBox(height: 8),
          for (final entry in worldbook.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 7),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: WorkshopColors.worldbook,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.comment,
                          style: const TextStyle(
                            color: WorkshopColors.textPrimary,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          entry.keys.isEmpty
                              ? '常驻注入'
                              : '触发：${entry.keys.join('、')}',
                          style: const TextStyle(
                            color: WorkshopColors.textHint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (project.exportedCharacterId != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WorkshopColors.successSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WorkshopColors.stageDone, width: 0.8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 15, color: WorkshopColors.stageDone),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已经保存到角色卡列表了。再点一次会更新同一张卡，不会重复创建。',
                    style: TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewRow(String label, String value, {Color? tint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: tint ?? WorkshopColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 导出动作 ---

  Widget _buildExportActions(CardProject project, bool busy) {
    return WorkshopWidgets.card(
      title: '导出方式',
      children: [
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '导出 JSON',
                icon: Icons.data_object,
                onPressed: busy ? null : () => _exportShare(project, asPng: false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '导出 PNG',
                icon: Icons.image_outlined,
                onPressed: busy ? null : () => _exportShare(project, asPng: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        WorkshopWidgets.secondaryButton(
          label: '查看角色卡 JSON',
          icon: Icons.code,
          onPressed: busy ? null : () => _showCardJson(project),
        ),
        const SizedBox(height: 8),
        const Text(
          'PNG 会把卡数据写进图片的 tEXt 块，是酒馆最通用的格式。\n'
          'JSON 适合备份和二次编辑。',
          style: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 10,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Future<void> _exportToCharacter(CardProject project) async {
    final character =
        await ref.read(cardProjectProvider.notifier).exportToCharacter(project.id);
    if (!mounted) {
      return;
    }
    if (character == null) {
      _notify('导出失败');
      return;
    }
    final latest = ref.read(cardProjectByIdProvider(project.id));
    final worldbookCount = latest == null
        ? 0
        : WorldbookPackager.buildWorldInfo(latest)?.entries.length ?? 0;
    _notify(
      worldbookCount > 0
          ? '已保存「${character.name}」，含 $worldbookCount 条世界书'
          : '已保存「${character.name}」',
    );
  }

  Future<void> _exportShare(CardProject project, {required bool asPng}) async {
    final packed = _actions.previewPack(project.id);
    if (packed == null) {
      return;
    }
    try {
      if (asPng) {
        // PNG 导出没有立绘会退化成 1×1 透明图，先补一张占位头像。
        final character =
            await CardAvatarFactory.withPlaceholderAvatar(packed.character);
        await CharacterExporter.exportAsPng(character);
      } else {
        await CharacterExporter.exportAsJson(packed.character);
      }
    } catch (error) {
      _notify('导出失败：$error');
    }
  }

  void _showCardJson(CardProject project) {
    final packed = _actions.previewPack(project.id);
    if (packed == null) {
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(
      CharacterExporter.buildV2Json(packed.character),
    );
    _showCopyableText('角色卡 JSON', json);
  }

  // --- MVU ---

  Widget _buildMvuSection(CardProject project, bool busy) {
    final hasMvu = project.mvuSchemaText.isNotEmpty ||
        project.mvuInitvarText.isNotEmpty ||
        project.mvuUpdateRulesText.isNotEmpty;

    return WorkshopWidgets.card(
      title: '动态变量（MVU，可选）',
      subtitle: '需要好感度、数值成长、状态标记这类跨轮次追踪的状态时用',
      accentColor: WorkshopColors.warning,
      children: [
        const Text(
          '会产出三份 MVU 核心产物：schema.ts（Zod 变量结构）、initvar.yaml（初始值）、'
          '变量更新规则.yaml。生成后可以复制到写卡工作区，由 forge CLI 完成脚本注入与打包。',
          style: TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 11,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 12),
        WorkshopWidgets.secondaryButton(
          label: hasMvu ? '重新设计变量' : '生成变量设计',
          icon: Icons.auto_awesome,
          onPressed: busy ? null : () => _generateMvu(project),
        ),
        if (hasMvu) ...[
          const SizedBox(height: 12),
          if (project.mvuSchemaText.isNotEmpty)
            _buildMvuRow('schema.ts', project.mvuSchemaText),
          if (project.mvuInitvarText.isNotEmpty)
            _buildMvuRow('initvar.yaml', project.mvuInitvarText),
          if (project.mvuUpdateRulesText.isNotEmpty)
            _buildMvuRow('变量更新规则.yaml', project.mvuUpdateRulesText),
          if (project.mvuVariablesJson.trim().isNotEmpty &&
              project.mvuVariablesJson.trim() != '[]') ...[
            const SizedBox(height: 6),
            Text(
              '结构化变量表已保存，质检时会拿它和世界书条目做一致性检查。',
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMvuRow(String label, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
        decoration: BoxDecoration(
          color: WorkshopColors.surfaceSunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WorkshopColors.strokeSoft, width: 0.8),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              size: 15,
              color: WorkshopColors.textHint,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: WorkshopColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${content.length} 字符',
                    style: const TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _showCopyableText(label, content),
              child: const Text('查看'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateMvu(CardProject project) async {
    final ok = await _actions.generateMvu(project.id);
    if (!mounted) {
      return;
    }
    _notify(ok ? '变量设计已生成' : '生成失败，看看上面的提示');
  }

  // --- 设计规格导出 ---

  Widget _buildSpecExport(CardProject project) {
    return WorkshopWidgets.card(
      title: '设计规格',
      subtitle: '六维度的对齐结果，可以导出去存档',
      children: [
        WorkshopWidgets.secondaryButton(
          label: '查看 / 复制 design-spec.md',
          icon: Icons.article_outlined,
          onPressed: () => _showCopyableText(
            'design-spec.md',
            project.designSpec.toMarkdown(project.name),
          ),
        ),
      ],
    );
  }
}
