import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/file_helper.dart';
import '../../data/preset_provider.dart';
import '../../domain/models/preset.dart';
import 'preset_edit_screen.dart';

class PresetListScreen extends ConsumerWidget {
  const PresetListScreen({super.key});

  static const _bgColor = Color(0xFF1C1B29);
  static const _surfaceColor = Color(0xFF222130);
  static const _surfaceAltColor = Color(0xFF2A2839);
  static const _borderColor = Color(0xFF3A3748);
  static const _textPrimaryColor = Color(0xFFF4F1FA);
  static const _textSecondaryColor = Color(0xFFD2CBDC);
  static const _accentColor = Color(0xFFD5BBFF);
  static const _successColor = Color(0xFFD5BBFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);
    final activeId = ref.watch(activePresetIdProvider);

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _textPrimaryColor,
        title: const Text(
          '预设管理',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入预设',
            onPressed: () async {
              try {
                final result = await FileHelper.pickJson();
                if (result == null) {
                  return;
                }

                final json = result.data;
                if (json is! Map) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('导入失败：JSON 结构无效')),
                    );
                  }
                  return;
                }

                final parsed = Preset.parseWithReport(
                  Map<String, dynamic>.from(json),
                  fallbackName: result.name,
                );
                final preset = parsed.preset;
                final report = parsed.report;

                await ref.read(presetsProvider.notifier).save(preset);
                await ref
                    .read(activePresetIdProvider.notifier)
                    .setActive(preset.id);

                if (context.mounted) {
                  final warningHint = report.hasWarnings ? '（含警告）' : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '已导入并激活：${preset.name}$warningHint。${report.summaryLine()}',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导入失败：$e')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建预设',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PresetEditScreen()),
              );
            },
          ),
        ],
      ),
      body: presets.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = presets[index];
                final isActive = item.id == activeId;
                return _buildPresetCard(context, ref, item, isActive);
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _surfaceAltColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _borderColor),
              ),
              child: const Icon(Icons.tune, color: _accentColor, size: 30),
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有预设',
              style: TextStyle(
                color: _textPrimaryColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '点击右上角 + 创建预设，或使用导入按钮加载你已有的预设文件。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard(
    BuildContext context,
    WidgetRef ref,
    Preset item,
    bool isActive,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(activePresetIdProvider.notifier).setActive(item.id);
        },
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? _accentColor : _borderColor,
              width: isActive ? 1.2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isActive
                      ? _accentColor.withValues(alpha: 0.14)
                      : _surfaceAltColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isActive ? Icons.check_circle : Icons.tune,
                  color: isActive ? _successColor : _accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Temp ${item.temperature}  |  TopP ${item.topP}  |  RepPen ${item.repetitionPenalty}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textSecondaryColor,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                    color: _accentColor,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PresetEditScreen(preset: item),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '导出',
                    icon: const Icon(Icons.share_outlined),
                    color: _textSecondaryColor,
                    onPressed: () {
                      FileHelper.exportJson(item.toJson(), item.name);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
