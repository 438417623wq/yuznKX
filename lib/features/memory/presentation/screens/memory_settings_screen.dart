import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/session_provider.dart';
import '../../data/memory_provider.dart';

/// 记忆系统设置页。
///
/// 从 `MemoryManagementScreen` 内嵌的折叠卡片抽出来，独立成页，
/// 只保留真正会被逻辑消费的设置项（原先 18 项里有 9 项是死设置，已删除）。
class MemorySettingsScreen extends ConsumerWidget {
  const MemorySettingsScreen({super.key});

  static const Color _accent = Color(0xFF24C3B5);
  static const Color _bg = Color(0xFF081015);
  static const Color _card = Color(0xFF0E1A21);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(memoryPluginSettingsProvider);
    final notifier = ref.read(memoryPluginSettingsProvider.notifier);
    final pluginEnabled = settings.isPluginEnabled;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('记忆设置'),
        backgroundColor: const Color(0xFF0E1A21),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildSessionScopeBanner(ref),
          _buildSection(
            title: '基础 (Basics)',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用记忆系统 (Enable Memory)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '关闭后将禁用记忆读取、记忆回写与聊天记录范围限制。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                value: settings.isPluginEnabled,
                activeThumbColor: _accent,
                onChanged: (value) =>
                    notifier.patch(isPluginEnabled: value),
              ),
              const Divider(color: Colors.white12, height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'AI 读取记忆表格 (AI Read)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '把已启用的表格注入聊天上下文，让模型看到当前记忆。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                value: settings.isAiReadTable,
                activeThumbColor: _accent,
                onChanged: pluginEnabled
                    ? (value) => notifier.patch(isAiReadTable: value)
                    : null,
              ),
              const Divider(color: Colors.white12, height: 1),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'AI 回写记忆 (AI Write)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '允许模型通过 <tableEdit> 指令增删改表格内容。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                value: settings.isAiWriteTable,
                activeThumbColor: _accent,
                onChanged: pluginEnabled
                    ? (value) => notifier.patch(isAiWriteTable: value)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            title: '注入 (Injection)',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '注入深度 (Injection Depth)',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        Text(
                          '${settings.deep}',
                          style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '记忆块插入到对话历史中的位置，数值越大越靠近最近的消息。',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    Slider(
                      min: 0,
                      max: 12,
                      divisions: 12,
                      value: settings.deep.toDouble().clamp(0, 12).toDouble(),
                      activeColor: _accent,
                      inactiveColor: Colors.white24,
                      onChanged: pluginEnabled
                          ? (value) => notifier.patch(deep: value.round())
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            title: '聊天记录可见性 (History Range)',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用范围限制 (Limit Range)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'AI 将仅看到指定范围内的历史记录。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                value: settings.isHistoryRangeLimitEnabled,
                activeThumbColor: _accent,
                onChanged: pluginEnabled
                    ? (value) =>
                        notifier.patch(isHistoryRangeLimitEnabled: value)
                    : null,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(
                            'start_floor_${settings.historyRangeStartFloor}_${settings.isHistoryRangeLimitEnabled}_$pluginEnabled'),
                        initialValue:
                            settings.historyRangeStartFloor.toString(),
                        enabled:
                            pluginEnabled && settings.isHistoryRangeLimitEnabled,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('起始楼层 (Start)'),
                        onChanged: (value) {
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null ||
                              parsed == settings.historyRangeStartFloor) {
                            return;
                          }
                          notifier.patch(historyRangeStartFloor: parsed);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(
                            'end_floor_${settings.historyRangeEndFloor}_${settings.isHistoryRangeLimitEnabled}_$pluginEnabled'),
                        initialValue: settings.historyRangeEndFloor.toString(),
                        enabled:
                            pluginEnabled && settings.isHistoryRangeLimitEnabled,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('结束楼层 (End, -1=最新)'),
                        onChanged: (value) {
                          final parsed = int.tryParse(value.trim());
                          if (parsed == null ||
                              parsed == settings.historyRangeEndFloor) {
                            return;
                          }
                          notifier.patch(historyRangeEndFloor: parsed);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  '聊天消息楼层从 #0 开始，-1 表示最新。当前用户消息始终包含在可见范围内。',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            title: '保留最新消息 (Keep Latest)',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用保留楼层 (Enable)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '开启后仅保留最近 N 条消息，其余楼层对 AI 不可见。',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                value: settings.isKeepLatestEnabled,
                activeThumbColor: _accent,
                onChanged: pluginEnabled
                    ? (value) => notifier.patch(isKeepLatestEnabled: value)
                    : null,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '保留条数 (Floors)',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        Text(
                          '${settings.keepLatestFloors}',
                          style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      min: 1,
                      max: 30,
                      divisions: 29,
                      value: settings.keepLatestFloors
                          .toDouble()
                          .clamp(1, 30)
                          .toDouble(),
                      activeColor: _accent,
                      inactiveColor: Colors.white24,
                      onChanged:
                          pluginEnabled && settings.isKeepLatestEnabled
                              ? (value) => notifier.patch(
                                  keepLatestFloors: value.round())
                              : null,
                    ),
                    Text(
                      '当前保留最近 ${settings.keepLatestFloors} 条聊天楼层。',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 提示「记忆设置也是会话级」—— 同一角色的不同对话可以有各自的设置。
  Widget _buildSessionScopeBanner(WidgetRef ref) {
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final sessions = ref.watch(sessionProvider);
    var sessionName = '';
    if (activeSessionId != null) {
      for (final session in sessions) {
        if (session.id == activeSessionId) {
          sessionName = session.name;
          break;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sessionName.isEmpty
                  ? '当前未选择对话，以下设置暂不生效。'
                  : '以下设置只对「$sessionName」这条对话生效。',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              title,
              style: const TextStyle(
                color: _accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
      filled: true,
      fillColor: const Color(0x3320303A),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }
}
