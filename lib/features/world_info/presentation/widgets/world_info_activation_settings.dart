import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/world_info_provider.dart';

/// 「全局世界信息/知识书激活设置」面板。
///
/// 对齐酒馆（SillyTavern）的 World Info 激活参数，改动即时写入 Hive
/// （Box `settings`，键前缀 `world_info_`），全局生效、无需逐卡配置。
class WorldInfoActivationSettingsPanel extends ConsumerWidget {
  const WorldInfoActivationSettingsPanel({super.key});

  static const Color _accent = Colors.indigo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(worldInfoSettingsProvider);
    final notifier = ref.read(worldInfoSettingsProvider.notifier);

    // 每次改动都基于「调用时刻的最新状态」计算，避免闭包捕获到过期的 settings。
    void patch(WorldInfoScanSettings Function(WorldInfoScanSettings) update) {
      notifier.update(update(ref.read(worldInfoSettingsProvider)));
    }

    return Container(
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile 默认会画上下分隔线，这里去掉，保持卡片观感。
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.tune, size: 20, color: Colors.indigoAccent),
          iconColor: Colors.indigoAccent,
          collapsedIconColor: Colors.white70,
          title: const Text(
            '全局世界信息/知识书激活设置',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            '单击展开',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _WorldInfoNumberField(
                    label: '扫描深度',
                    helper: 'Scan Depth',
                    value: settings.scanDepth,
                    max: 1000,
                    onChanged: (v) => patch((s) => s.copyWith(scanDepth: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WorldInfoNumberField(
                    label: '上下文百分比',
                    helper: 'Context %',
                    value: settings.budgetPercentage,
                    max: 100,
                    onChanged: (v) =>
                        patch((s) => s.copyWith(budgetPercentage: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _WorldInfoNumberField(
                    label: 'Token预算上限',
                    helper: 'Budget Cap',
                    value: settings.budgetCap,
                    max: 1 << 20,
                    onChanged: (v) => patch((s) => s.copyWith(budgetCap: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WorldInfoNumberField(
                    label: '最小激活数',
                    helper: 'Min Activations',
                    value: settings.minActivations,
                    max: 1000,
                    onChanged: (v) =>
                        patch((s) => s.copyWith(minActivations: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _WorldInfoNumberField(
                    label: '最大深度',
                    helper: 'Max Depth',
                    value: settings.minActivationsDepthMax,
                    max: 1000,
                    onChanged: (v) =>
                        patch((s) => s.copyWith(minActivationsDepthMax: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WorldInfoNumberField(
                    label: '最大递归深度',
                    helper: 'Max Recursion',
                    value: settings.maxRecursionDepth,
                    max: 1000,
                    onChanged: (v) =>
                        patch((s) => s.copyWith(maxRecursionDepth: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '插入策略 (Insertion Strategy)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<WorldInfoCharacterStrategy>(
              initialValue: settings.characterStrategy,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: WorldInfoCharacterStrategy.evenly,
                  child: Text('均匀排序'),
                ),
                DropdownMenuItem(
                  value: WorldInfoCharacterStrategy.characterFirst,
                  child: Text('角色世界书优先'),
                ),
                DropdownMenuItem(
                  value: WorldInfoCharacterStrategy.globalFirst,
                  child: Text('全局世界书优先'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                patch((s) => s.copyWith(characterStrategy: value));
              },
            ),
            const SizedBox(height: 8),
            _WorldInfoCheckRow(
              label: '包括名称',
              helper: 'Include names',
              value: settings.includeNames,
              onChanged: (v) => patch((s) => s.copyWith(includeNames: v)),
            ),
            _WorldInfoCheckRow(
              label: '递归扫描',
              helper: 'Recursive scan',
              value: settings.recursive,
              onChanged: (v) => patch((s) => s.copyWith(recursive: v)),
            ),
            _WorldInfoCheckRow(
              label: '区分大小写',
              helper: 'Case sensitive',
              value: settings.caseSensitive,
              onChanged: (v) => patch((s) => s.copyWith(caseSensitive: v)),
            ),
            _WorldInfoCheckRow(
              label: '匹配整个单词',
              helper: 'Match whole words',
              value: settings.matchWholeWords,
              onChanged: (v) => patch((s) => s.copyWith(matchWholeWords: v)),
            ),
            _WorldInfoCheckRow(
              label: '使用群组评分',
              helper: 'Use group scoring',
              value: settings.useGroupScoring,
              onChanged: (v) => patch((s) => s.copyWith(useGroupScoring: v)),
            ),
            _WorldInfoCheckRow(
              label: '溢出警报',
              helper: 'Overflow alert',
              value: settings.alertOnOverflow,
              onChanged: (v) => patch((s) => s.copyWith(alertOnOverflow: v)),
            ),
            const SizedBox(height: 4),
            const Text(
              '提示：「上下文百分比」决定世界书可占用上下文的比例，'
              '默认 25%，条目较多时可适当调高；「Token预算上限」为 0 表示不额外封顶。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldInfoCheckRow extends StatelessWidget {
  const _WorldInfoCheckRow({
    required this.label,
    required this.helper,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String helper;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$label ($helper)',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数字输入框。自己持有 controller，避免外层重建时把用户正在输入的内容冲掉。
class _WorldInfoNumberField extends StatefulWidget {
  const _WorldInfoNumberField({
    required this.label,
    required this.helper,
    required this.value,
    required this.onChanged,
    this.max = 1000,
  });

  final String label;
  final String helper;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_WorldInfoNumberField> createState() => _WorldInfoNumberFieldState();
}

class _WorldInfoNumberFieldState extends State<_WorldInfoNumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      return;
    }
    widget.onChanged(parsed.clamp(0, widget.max).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.label} (${widget.helper})',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: border,
            enabledBorder: border,
          ),
          onChanged: _commit,
          onSubmitted: _commit,
        ),
      ],
    );
  }
}
