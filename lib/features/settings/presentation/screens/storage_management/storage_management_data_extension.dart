part of '../storage_management_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _StorageManagementDataExtension on _StorageManagementScreenState {
  Future<void> _refreshUsage() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);

    final nextStats = <String, _StorageSectionStat>{};
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final appDocPath = appDocDir.path.replaceAll('\\', '/');

      for (final section in _sections) {
        if (section.isCache) {
          final cacheBytes = await _getDirSize(await getTemporaryDirectory());
          nextStats[section.id] = _StorageSectionStat(
            bytes: cacheBytes,
            records: 0,
          );
          continue;
        }

        var bytes = 0;
        var records = 0;
        for (final boxName in section.boxNames) {
          final box = await _ensureBoxOpen(boxName);
          records += box.length;
          bytes += await _getBoxSize(box);
        }

        if (section.id == 'characters') {
          bytes += await _countManagedAvatarSize(appDocPath);
        }

        nextStats[section.id] = _StorageSectionStat(
          bytes: bytes,
          records: records,
        );
      }
    } catch (_) {
      // Keep UI alive even if one module fails.
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _stats = nextStats;
      _isLoading = false;
    });
  }

  Future<Box> _ensureBoxOpen(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<int> _getBoxSize(Box box) async {
    try {
      final path = box.path;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          return await file.length();
        }
      }
    } catch (_) {
      // Fallback below.
    }

    var bytes = 0;
    for (final key in box.keys) {
      final value = box.get(key);
      try {
        bytes +=
            utf8.encode(jsonEncode({'k': key.toString(), 'v': value})).length;
      } catch (_) {
        bytes += value.toString().length;
      }
    }
    return bytes;
  }

  Future<int> _countManagedAvatarSize(String appDocPath) async {
    var bytes = 0;
    final characters = ref.read(characterListProvider);

    for (final character in characters) {
      final avatarPath = character.avatarPath.trim();
      if (avatarPath.isEmpty) {
        continue;
      }
      final normalized = avatarPath.replaceAll('\\', '/');
      if (!normalized.startsWith(appDocPath)) {
        continue;
      }

      final avatarFile = File(avatarPath);
      if (await avatarFile.exists()) {
        bytes += await avatarFile.length();
      }
    }
    return bytes;
  }

  Future<int> _getDirSize(Directory dir) async {
    var size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (_) {
      return size;
    }
    return size;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
