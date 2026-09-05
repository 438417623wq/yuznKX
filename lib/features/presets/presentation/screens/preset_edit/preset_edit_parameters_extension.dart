part of '../preset_edit_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _PresetEditParametersExtension on _PresetEditScreenState {
  Widget _buildParametersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 14),
          color: _PresetEditScreenState._surfaceColor,
          shape: _sectionShape(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '预设名称',
                hintText: '例如：酒馆平衡',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入预设名称';
                }
                return null;
              },
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 14),
          color: _PresetEditScreenState._surfaceColor,
          shape: _sectionShape(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '采样模板',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  '参考类酒馆常用参数，点按后可再手动微调。',
                  style: TextStyle(
                      color: _PresetEditScreenState._textSecondaryColor,
                      fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _temp = 0.70;
                          _topP = 0.95;
                          _topK = 40;
                          _maxTokens = 2000;
                          _freqPen = 0.0;
                          _presPen = 0.0;
                          _repPen = 1.05;
                        });
                      },
                      child: const Text('酒馆平衡'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _temp = 0.95;
                          _topP = 0.98;
                          _topK = 80;
                          _maxTokens = 2400;
                          _freqPen = 0.10;
                          _presPen = 0.20;
                          _repPen = 1.02;
                        });
                      },
                      child: const Text('高创意'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _temp = 0.55;
                          _topP = 0.90;
                          _topK = 30;
                          _maxTokens = 1800;
                          _freqPen = 0.0;
                          _presPen = 0.0;
                          _repPen = 1.12;
                        });
                      },
                      child: const Text('高稳健'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          color: _PresetEditScreenState._surfaceColor,
          shape: _sectionShape(22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSliderCard(
                  'TEMPERATURE (温度)',
                  '控制随机性，越高越有创造力',
                  _temp,
                  0,
                  2,
                  (v) => setState(() => _temp = v),
                  divisions: 200,
                  valueLabel: _formatDecimal(_temp),
                ),
                _buildSliderCard(
                  'TOP P',
                  '核采样概率',
                  _topP,
                  0,
                  1,
                  (v) => setState(() => _topP = v),
                  divisions: 100,
                  valueLabel: _formatDecimal(_topP),
                ),
                _buildSliderCard(
                  'TOP K',
                  '保留高概率 Token 数量 (0 为关闭)',
                  _topK.toDouble(),
                  0,
                  1000,
                  (v) => setState(() => _topK = v.toInt()),
                  divisions: 1000,
                  valueLabel: _topK == 0 ? 'Off' : _topK.toString(),
                ),
                _buildSliderCard(
                  'MAX TOKENS',
                  '单次回复最大长度',
                  _maxTokens.toDouble(),
                  1,
                  131072,
                  (v) => setState(() => _maxTokens = v.toInt()),
                  valueLabel: _maxTokens.toString(),
                ),
                _buildSliderCard(
                  'FREQUENCY PENALTY',
                  '降低重复词频 (0 为默认)',
                  _freqPen,
                  -2,
                  2,
                  (v) => setState(() => _freqPen = v),
                  divisions: 200,
                  valueLabel: _asDefaultValue(_freqPen, 0.0),
                ),
                _buildSliderCard(
                  'PRESENCE PENALTY',
                  '鼓励探索新话题 (0 为默认)',
                  _presPen,
                  -2,
                  2,
                  (v) => setState(() => _presPen = v),
                  divisions: 200,
                  valueLabel: _asDefaultValue(_presPen, 0.0),
                ),
                _buildSliderCard(
                  'REPETITION PENALTY',
                  '重复惩罚 (1.0 为默认)',
                  _repPen,
                  0.5,
                  2,
                  (v) => setState(() => _repPen = v),
                  divisions: 150,
                  valueLabel: _asDefaultValue(_repPen, 1.0),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderCard(
    String title,
    String subtitle,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
    String? valueLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _PresetEditScreenState._textSecondaryColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                valueLabel ?? _formatDecimal(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _PresetEditScreenState._accentColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: _PresetEditScreenState._accentColor,
            inactiveColor: _PresetEditScreenState._accentSoftColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _formatDecimal(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _asDefaultValue(double current, double defaultValue) {
    if ((current - defaultValue).abs() < 0.001) {
      return 'Default';
    }
    return _formatDecimal(current);
  }
}
