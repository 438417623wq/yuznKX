import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/file_helper.dart';
import '../../data/preset_provider.dart';
import '../../domain/models/preset.dart';
import 'preset_edit_screen.dart';

class PresetListScreen extends ConsumerWidget {
  const PresetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);
    final activeId = ref.watch(activePresetIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生成预设 (Presets)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: '导入预设',
            onPressed: () async {
              try {
                final result = await FileHelper.pickJson();
                if (result != null) {
                  final json = result.data;
                  if (json is Map<String, dynamic>) {
                    var preset = Preset.fromJson(json);
                    // Use filename if preset name is default/missing
                    if (preset.name == 'Imported Preset' || json['name'] == null) {
                      preset = preset.copyWith(name: result.name);
                    }
                    
                    await ref.read(presetsProvider.notifier).save(preset);
                    // Automatically activate imported preset
                    await ref.read(activePresetIdProvider.notifier).setActive(preset.id);
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入并已启用: ${preset.name}')));
                    }
                  } else {
                     if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入失败: 文件格式不正确 (Invalid JSON structure)')));
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PresetEditScreen()));
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: presets.length,
        itemBuilder: (context, index) {
          final item = presets[index];
          final isActive = item.id == activeId;
          return ListTile(
            title: Text(item.name),
            subtitle: Text('Temp: ${item.temperature} | TopP: ${item.topP} | RepPen: ${item.repetitionPenalty}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive) const Icon(Icons.check_circle, color: Colors.green),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PresetEditScreen(preset: item)));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    FileHelper.exportJson(item.toJson(), item.name);
                  },
                ),
              ],
            ),
            onTap: () {
              ref.read(activePresetIdProvider.notifier).setActive(item.id);
            },
          );
        },
      ),
    );
  }
}

