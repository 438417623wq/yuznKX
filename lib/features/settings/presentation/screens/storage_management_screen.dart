import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/file_helper.dart';
import '../../../api_connection/data/api_connection_provider.dart';
import '../../../character/data/character_provider.dart';
import '../../../chat/data/session_provider.dart';
import '../../../memory/data/memory_provider.dart';
import '../../../presets/data/preset_provider.dart';
import '../../../regex/data/regex_provider.dart';
import '../../../user/data/persona_provider.dart';
import '../../../world_info/data/world_info_provider.dart';

part 'storage_management/storage_management_data_extension.dart';
part 'storage_management/storage_management_actions_extension.dart';
part 'storage_management/storage_management_ui_extension.dart';
part 'storage_management/storage_management_models.dart';

class StorageManagementScreen extends ConsumerStatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  ConsumerState<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState
    extends ConsumerState<StorageManagementScreen> {
  final _pageBg = const Color(0xFF11152A);
  final _surface = const Color(0xFF1A2140);
  final _surfaceSoft = const Color(0xFF222B4F);
  final _stroke = const Color(0xFF323F6C);
  final _textPrimary = const Color(0xFFEAF0FF);
  final _textSecondary = const Color(0xFFA4B0D3);

  final List<_StorageSectionConfig> _sections = const [
    _StorageSectionConfig(
      id: 'cache',
      title: '临时缓存',
      subtitle: '图片与临时下载文件',
      icon: Icons.bolt_outlined,
      color: Color(0xFFFFB347),
      boxNames: [],
      clearable: true,
      isCache: true,
    ),
    _StorageSectionConfig(
      id: 'sessions',
      title: '聊天会话',
      subtitle: '对话历史与会话索引',
      icon: Icons.forum_outlined,
      color: Color(0xFF4BC6FF),
      boxNames: ['sessions'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'characters',
      title: '角色与群组',
      subtitle: '角色卡、群组与元数据',
      icon: Icons.face_5_outlined,
      color: Color(0xFF7EE787),
      boxNames: ['characters'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'presets',
      title: '预设',
      subtitle: '采样参数、提示词与正则',
      icon: Icons.tune_outlined,
      color: Color(0xFF8EA1FF),
      boxNames: ['presets'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'world_info',
      title: '世界信息',
      subtitle: '条目与触发规则',
      icon: Icons.menu_book_outlined,
      color: Color(0xFF5CE0B3),
      boxNames: ['world_info'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'regex_scripts',
      title: '正则脚本',
      subtitle: '输入与输出处理脚本',
      icon: Icons.data_array_outlined,
      color: Color(0xFF74C0FC),
      boxNames: ['regex_scripts'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'memory_tables',
      title: '记忆表',
      subtitle: '会话级记忆表格数据',
      icon: Icons.memory_outlined,
      color: Color(0xFFFF9DDA),
      // 记忆表自 v3 起按**会话 ID**存储（`memory_tables_v3`），
      // 插件设置同样是会话级（`memory_plugin_settings_v3`）。
      // 一并纳入 v2（旧角色键）以便清理历史遗留数据。
      // 注意：这里原本写的是 `memory_tables`（v1 的 Box 名），
      // 自 v2 起就已失配，导致该项的容量统计与清除长期是空操作。
      boxNames: [
        'memory_tables_v3',
        'memory_plugin_settings_v3',
        'memory_tables_v2',
        'memory_plugin_settings_v2',
      ],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'personas',
      title: '用户身份',
      subtitle: '用户身份配置',
      icon: Icons.badge_outlined,
      color: Color(0xFFC7A3FF),
      boxNames: ['personas'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'api_connections',
      title: '接口连接',
      subtitle: '接口地址、模型与连接配置',
      icon: Icons.hub_outlined,
      color: Color(0xFFFFD166),
      boxNames: ['api_connections'],
      clearable: true,
    ),
    _StorageSectionConfig(
      id: 'settings',
      title: '应用设置',
      subtitle: '全局设置与当前激活项',
      icon: Icons.settings_outlined,
      color: Color(0xFFB8C0FF),
      boxNames: ['settings'],
      clearable: true,
      dangerousClear: true,
    ),
  ];

  bool _isLoading = true;
  bool _isBusy = false;
  Map<String, _StorageSectionStat> _stats = const {};

  int get _totalBytes =>
      _stats.values.fold<int>(0, (sum, item) => sum + item.bytes);

  int get _totalRecords =>
      _stats.values.fold<int>(0, (sum, item) => sum + item.records);

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections
        .map((section) => (
              section,
              _stats[section.id] ??
                  const _StorageSectionStat(bytes: 0, records: 0),
            ))
        .toList();

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: const Text('数据管理中心'),
        backgroundColor: Colors.transparent,
        foregroundColor: _textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新存储统计',
            onPressed: _isBusy ? null : _refreshUsage,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _refreshUsage,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 14),
                  _buildBackupActions(),
                  const SizedBox(height: 14),
                  ...sections.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSectionCard(
                        config: entry.$1,
                        stat: entry.$2,
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
