part of '../storage_management_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _StorageManagementActionsExtension on _StorageManagementScreenState {
  Future<void> _clearSection(_StorageSectionConfig section) async {
    final confirm = await _confirm(
      title: '确认清理',
      message: section.dangerousClear
          ? '将清空${section.title}并重置相关激活状态，此操作不可撤销。'
          : '确认清空${section.title}？此操作不可撤销。',
      dangerous: true,
    );
    if (!confirm) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      if (section.isCache) {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
          await tempDir.create(recursive: true);
        }
      } else {
        for (final boxName in section.boxNames) {
          final box = await _ensureBoxOpen(boxName);
          await box.clear();
          await box.flush();
        }
        await _cleanupLinkedSettings(section.id);
      }

      _invalidateAllDataProviders();
      await _refreshUsage();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清理：${section.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _cleanupLinkedSettings(String sectionId) async {
    final settings = await _ensureBoxOpen('settings');
    switch (sectionId) {
      case 'sessions':
        await settings.delete('active_session_id');
        break;
      case 'characters':
        await settings.delete('active_character_id');
        break;
      case 'presets':
        await settings.delete('active_preset_id');
        break;
      case 'world_info':
        await settings.delete('active_world_info_ids');
        break;
      case 'regex_scripts':
        await settings.delete('active_regex_ids');
        break;
      case 'api_connections':
        await settings.delete('active_api_id');
        break;
      case 'personas':
        await settings.delete('active_persona_id');
        break;
      case 'settings':
        await settings.clear();
        await settings.flush();
        break;
      default:
        break;
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _isBusy = true);
    try {
      final boxes = <String, dynamic>{};
      final boxNames = _sections
          .expand((section) => section.boxNames)
          .where((name) => name.isNotEmpty)
          .toSet();

      for (final boxName in boxNames) {
        final box = await _ensureBoxOpen(boxName);
        final entries = <String, dynamic>{};
        for (final key in box.keys) {
          entries[key.toString()] = box.get(key);
        }
        boxes[boxName] = entries;
      }

      final prefs = await SharedPreferences.getInstance();
      final sharedPrefs = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        sharedPrefs[key] = prefs.get(key);
      }

      final payload = <String, dynamic>{
        'backup_format': 'silly_tavern_flutter_v1',
        'created_at': DateTime.now().toIso8601String(),
        'boxes': boxes,
        'shared_prefs': sharedPrefs,
      };

      final now = DateTime.now();
      final fileName =
          'silly_tavern_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      await FileHelper.exportJson(payload, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('备份已生成，请在分享面板中保存。'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _importBackup() async {
    ({String name, dynamic data})? picked;
    try {
      picked = await FileHelper.pickJson();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
      return;
    }

    if (picked == null) {
      return;
    }
    if (picked.data is! Map) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导入失败：备份文件格式无效。'),
          ),
        );
      }
      return;
    }

    final backup = Map<String, dynamic>.from(picked.data as Map);
    final rawBoxes = backup['boxes'];
    if (rawBoxes is! Map) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败：未找到备份数据。')),
        );
      }
      return;
    }

    final confirm = await _confirm(
      title: '导入备份',
      message: '这将覆盖当前数据且无法撤销，是否继续？',
      dangerous: true,
    );
    if (!confirm) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      final targetBoxNames = _sections
          .expand((section) => section.boxNames)
          .where((name) => name.isNotEmpty)
          .toSet();

      final importBoxes = Map<String, dynamic>.from(rawBoxes);
      for (final boxName in targetBoxNames) {
        final box = await _ensureBoxOpen(boxName);
        await box.clear();

        final sectionData = importBoxes[boxName];
        if (sectionData is Map) {
          for (final entry in sectionData.entries) {
            await box.put(entry.key.toString(), entry.value);
          }
        }
        await box.flush();
      }

      final prefsPayload = backup['shared_prefs'];
      if (prefsPayload is Map) {
        final prefs = await SharedPreferences.getInstance();
        for (final entry in prefsPayload.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          if (value == null) {
            await prefs.remove(key);
            continue;
          }
          if (value is bool) {
            await prefs.setBool(key, value);
            continue;
          }
          if (value is int) {
            await prefs.setInt(key, value);
            continue;
          }
          if (value is double) {
            await prefs.setDouble(key, value);
            continue;
          }
          if (value is String) {
            await prefs.setString(key, value);
            continue;
          }
          if (value is List) {
            await prefs.setStringList(
              key,
              value.map((e) => e.toString()).toList(),
            );
          }
        }
      }

      _invalidateAllDataProviders();
      await _refreshUsage();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份导入成功。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _invalidateAllDataProviders() {
    ref.invalidate(apiConnectionsProvider);
    ref.invalidate(activeApiIdProvider);
    ref.invalidate(activeApiConnectionProvider);

    ref.invalidate(sessionProvider);
    ref.invalidate(activeSessionIdProvider);

    ref.invalidate(characterListProvider);
    ref.invalidate(activeCharacterIdProvider);
    ref.invalidate(activeCharacterProvider);

    ref.invalidate(presetsProvider);
    ref.invalidate(activePresetIdProvider);
    ref.invalidate(activePresetProvider);

    ref.invalidate(worldInfoProvider);
    ref.invalidate(activeWorldInfoIdsProvider);

    ref.invalidate(regexScriptsProvider);
    ref.invalidate(activeRegexScriptIdsProvider);

    ref.invalidate(personaListProvider);
    ref.invalidate(activePersonaIdProvider);
    ref.invalidate(personaProvider);

    ref.invalidate(memoryProvider);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    bool dangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text(title, style: TextStyle(color: _textPrimary)),
        content: Text(message, style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: dangerous ? Colors.redAccent : Colors.indigo,
            ),
            child: Text(dangerous ? '确认覆盖' : '确认'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
