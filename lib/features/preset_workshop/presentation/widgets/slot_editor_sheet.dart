import 'package:flutter/material.dart';

import '../../../character_workshop/presentation/workshop_theme.dart';
import '../../domain/models/preset_project.dart';
import '../../domain/models/preset_slot.dart';

/// 槽位全屏编辑器。
///
/// 小屏上在卡片里改长文本很难受 —— 这个页面把编辑区撑满，
/// 顶部固定显示槽位的意图（AI 生成时依据的那段说明），底部是字数与操作。
class SlotEditorSheet extends StatefulWidget {
  const SlotEditorSheet({
    super.key,
    required this.project,
    required this.slot,
    required this.onSaved,
    this.onRegenerate,
  });

  final PresetProject project;
  final PresetSlot slot;
  final ValueChanged<String> onSaved;

  /// 传 null 表示这个槽位不能由 AI 重写（引擎填充 / 用户自填）。
  final Future<void> Function(String hint)? onRegenerate;

  static Future<void> show({
    required BuildContext context,
    required PresetProject project,
    required PresetSlot slot,
    required ValueChanged<String> onSaved,
    Future<void> Function(String hint)? onRegenerate,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SlotEditorSheet(
          project: project,
          slot: slot,
          onSaved: onSaved,
          onRegenerate: onRegenerate,
        ),
      ),
    );
  }

  @override
  State<SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends State<SlotEditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.slot.content);
  final TextEditingController _hintController = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_dirty) {
        setState(() => _dirty = true);
      } else {
        // 字数要跟着动。
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Scaffold(
      backgroundColor: WorkshopColors.pageBg,
      appBar: AppBar(
        backgroundColor: WorkshopColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.label,
              style: const TextStyle(fontSize: 15),
            ),
            Text(
              'role=${slot.role} · ${slot.identifier}',
              style: const TextStyle(
                color: WorkshopColors.textHint,
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSaved(_controller.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (slot.intent.trim().isNotEmpty)
            Container(
              width: double.infinity,
              color: WorkshopColors.surfaceSunken,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '这个槽位该写什么',
                    style: TextStyle(
                      color: WorkshopColors.textHint,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    slot.intent.trim(),
                    style: const TextStyle(
                      color: WorkshopColors.textSecondary,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _controller,
                autofocus: false,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  color: WorkshopColors.textPrimary,
                  fontSize: 13,
                  height: 1.7,
                ),
                decoration: InputDecoration(
                  hintText: slot.marker
                      ? '这个槽位的内容由引擎填充。写在这里的文本会被前置到内置内容前面。'
                      : '写这个槽位的内容…',
                  hintStyle: const TextStyle(
                    color: WorkshopColors.textHint,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: WorkshopColors.surface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(WorkshopMetrics.fieldRadius),
                    borderSide: const BorderSide(
                      color: WorkshopColors.stroke,
                      width: 0.8,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(WorkshopMetrics.fieldRadius),
                    borderSide: const BorderSide(
                      color: WorkshopColors.stroke,
                      width: 0.8,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(WorkshopMetrics.fieldRadius),
                    borderSide: const BorderSide(
                      color: WorkshopColors.accent,
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onRegenerate != null)
            Container(
              color: WorkshopColors.surface,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hintController,
                      style: const TextStyle(
                        color: WorkshopColors.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: WorkshopWidgets.inputDecoration(
                        '让 AI 重写（可留空直接重写）',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () {
                      final hint = _hintController.text.trim();
                      widget.onRegenerate!(hint);
                    },
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('重写', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: WorkshopColors.worldbook,
                      foregroundColor: const Color(0xFF10142B),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            color: WorkshopColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                Text(
                  '${_controller.text.trim().length} 字'
                  '${_dirty ? " · 未保存" : ""}',
                  style: TextStyle(
                    color: _dirty
                        ? WorkshopColors.warning
                        : WorkshopColors.textHint,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (_dirty)
                  TextButton(
                    onPressed: () {
                      _controller.text = widget.slot.content;
                      _dirty = false;
                      setState(() {});
                    },
                    child: const Text('还原', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
