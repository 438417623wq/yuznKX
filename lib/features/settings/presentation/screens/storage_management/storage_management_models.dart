part of '../storage_management_screen.dart';

class _StorageSectionConfig {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> boxNames;
  final bool clearable;
  final bool isCache;
  final bool dangerousClear;

  const _StorageSectionConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.boxNames,
    this.clearable = false,
    this.isCache = false,
    this.dangerousClear = false,
  });
}

class _StorageSectionStat {
  final int bytes;
  final int records;

  const _StorageSectionStat({
    required this.bytes,
    required this.records,
  });
}
