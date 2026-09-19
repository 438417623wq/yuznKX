part of '../project_screen.dart';

/// 阶段一：需求对齐。
///
/// 六维度逐维确认，全部确认后才允许进入创作规划 —— 这是「先对齐需求再做规划」
/// 的落地方式。每个维度支持三种输入：AI 候选、用户改写、用户自填。
extension _ProjectDesignExtension on _ProjectScreenState {
  List<Widget> _buildDesignStage(CardProject project, CardProjectState state) {
    final busy = state.busy;

    return <Widget>[
      _buildMaterialSection(project, busy),
      const SizedBox(height: 12),
      WorkshopWidgets.card(
        title: '① 需求对齐',
        subtitle:
            '已确认 ${project.designSpec.confirmedCount}/${SpecDimension.values.length} 个维度'
            ' · 每个维度都可以直接改，或者让 AI 给方案',
        trailing: TextButton(
          onPressed: busy || project.designSpec.isComplete
              ? null
              : () => _autoFillAllDimensions(project),
          child: const Text('让 AI 帮我决定'),
        ),
        children: [
          WorkshopWidgets.progressBar(
            project.designSpec.confirmedCount /
                SpecDimension.values.length,
          ),
        ],
      ),
      const SizedBox(height: 12),
      for (final dimension in SpecDimension.values) ...[
        _buildDimensionCard(project, dimension, busy),
        const SizedBox(height: 12),
      ],
    ];
  }

  // --- 素材导入 ---

  Widget _buildMaterialSection(CardProject project, bool busy) {
    return WorkshopWidgets.card(
      title: '素材导入（可选）',
      subtitle: '有设定文档、人设稿、世界观笔记甚至长篇小说？丢进来，我来拆解成上面的六个维度',
      children: [
        WorkshopWidgets.secondaryButton(
          label: '选择文件（txt / md / docx）',
          icon: Icons.upload_file,
          onPressed: busy ? null : () => _importMaterial(project),
        ),
        if (project.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final source in project.sources)
            _buildMaterialTile(project, source, busy),
        ],
      ],
    );
  }

  Widget _buildMaterialTile(
    CardProject project,
    SourceMaterial source,
    bool busy,
  ) {
    final isDone = source.status == MaterialStatus.done;
    final isFailed = source.status == MaterialStatus.failed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
      decoration: BoxDecoration(
        color: WorkshopColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFailed ? WorkshopColors.danger : WorkshopColors.strokeSoft,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFailed ? Icons.error_outline : Icons.description_outlined,
            size: 16,
            color: isFailed
                ? WorkshopColors.danger
                : (isDone ? WorkshopColors.success : WorkshopColors.textHint),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WorkshopColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isFailed
                      ? (source.error ?? '拆解失败')
                      : '${source.charCount} 字 · 约 ${source.estimatedTokens} token'
                          '${source.needsChunking ? ' · 将分片处理' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isFailed
                        ? WorkshopColors.danger
                        : WorkshopColors.textHint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _extractMaterial(project, source),
            child: Text(isDone ? '重新拆解' : '拆解'),
          ),
          IconButton(
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close,
              size: 15,
              color: WorkshopColors.textHint,
            ),
            onPressed: busy
                ? null
                : () => ref
                    .read(cardProjectProvider.notifier)
                    .removeSource(project.id, source.id),
          ),
        ],
      ),
    );
  }

  Future<void> _importMaterial(CardProject project) async {
    final error = await _actions.importMaterial(project.id);
    if (error != null) {
      _notify('导入失败：$error');
    } else if (mounted) {
      _notify('已导入，点「拆解」让它填进六个维度');
    }
  }

  Future<void> _extractMaterial(
    CardProject project,
    SourceMaterial source,
  ) async {
    final error = await _actions.extractMaterial(project.id, source.id);
    if (error != null) {
      _notify('拆解失败：$error');
    } else {
      _notify('拆解完成，已填入空着的维度（你写过的答案不会被覆盖）');
    }
  }

  // --- 单维度卡片 ---

  Widget _buildDimensionCard(
    CardProject project,
    SpecDimension dimension,
    bool busy,
  ) {
    final spec = project.designSpec;
    final confirmed = spec.isConfirmed(dimension);
    final candidates = spec.candidatesOf(dimension);
    final tint = confirmed ? WorkshopColors.stageDone : WorkshopColors.accent;

    return WorkshopWidgets.card(
      title: dimension.label,
      subtitle: dimension.question,
      accentColor: tint,
      trailing: confirmed
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: WorkshopColors.successSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: WorkshopColors.stageDone,
                  width: 0.8,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 11, color: WorkshopColors.stageDone),
                  SizedBox(width: 3),
                  Text(
                    '已确认',
                    style: TextStyle(
                      color: WorkshopColors.stageDone,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            )
          : null,
      children: [
        Text(
          dimension.hint,
          style: const TextStyle(
            color: WorkshopColors.textHint,
            fontSize: 11,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _specController(project, dimension),
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(
            color: WorkshopColors.textPrimary,
            fontSize: 13,
            height: 1.5,
          ),
          decoration: WorkshopWidgets.inputDecoration('写下你的想法，或者从下面的候选里挑一个'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: candidates.isEmpty ? '让 AI 给 3 个方案' : '换一批方案',
                icon: Icons.auto_awesome,
                onPressed: busy
                    ? null
                    : () => _actions.generateDesignCandidates(
                          project.id,
                          dimension,
                          userHint: spec.answerOf(dimension),
                        ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WorkshopWidgets.secondaryButton(
                label: '清除',
                icon: Icons.backspace_outlined,
                onPressed: busy || spec.answerOf(dimension).isEmpty
                    ? null
                    : () => ref
                        .read(cardProjectProvider.notifier)
                        .updateDesignSpec(
                          project.id,
                          spec.withoutConfirmation(dimension).withAnswer(
                                dimension,
                                '',
                              ),
                        ),
              ),
            ),
          ],
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '候选方案（点一下就用它）',
            style: TextStyle(color: WorkshopColors.textHint, fontSize: 11),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < candidates.length; i++)
            _buildCandidateTile(project, dimension, candidates[i], i + 1),
        ],
      ],
    );
  }

  Widget _buildCandidateTile(
    CardProject project,
    SpecDimension dimension,
    String candidate,
    int index,
  ) {
    final selected = project.designSpec.answerOf(dimension) == candidate.trim();

    return GestureDetector(
      onTap: () {
        ref.read(cardProjectProvider.notifier).updateDesignSpec(
              project.id,
              project.designSpec.withAnswer(dimension, candidate),
            );
        _notify('已采用方案 $index');
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
        decoration: BoxDecoration(
          color: selected
              ? WorkshopColors.accentSoft
              : WorkshopColors.surfaceSunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? WorkshopColors.accent : WorkshopColors.strokeSoft,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? WorkshopColors.accent
                        : WorkshopColors.surfaceSoft,
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF10142B)
                          : WorkshopColors.textHint,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (selected)
                  const Text(
                    '当前采用',
                    style: TextStyle(
                      color: WorkshopColors.accent,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              candidate,
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 逐个维度让 AI 给方案并自动采用第一个，直到六个维度都有答案。
  Future<void> _autoFillAllDimensions(CardProject project) async {
    for (final dimension in SpecDimension.values) {
      if (!mounted) {
        return;
      }
      final latest = ref.read(cardProjectByIdProvider(project.id));
      if (latest == null) {
        return;
      }
      if (latest.designSpec.answerOf(dimension).isNotEmpty) {
        continue;
      }

      final ok = await _actions.generateDesignCandidates(
        project.id,
        dimension,
      );
      if (!ok) {
        return; // 失败就停下，保留已完成的进度。
      }

      final after = ref.read(cardProjectByIdProvider(project.id));
      final candidates = after?.designSpec.candidatesOf(dimension) ?? const [];
      if (candidates.isEmpty || !mounted) {
        continue;
      }
      ref.read(cardProjectProvider.notifier).updateDesignSpec(
            project.id,
            (after ?? latest)
                .designSpec
                .withAnswer(dimension, candidates.first),
          );
    }
    if (mounted) {
      _notify('六个维度都填好了，可以直接改，也可以直接进下一步');
    }
  }
}
