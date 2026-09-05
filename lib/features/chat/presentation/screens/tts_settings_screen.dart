import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/tts_service.dart';
import 'package:file_picker/file_picker.dart';

class TtsSettingsScreen extends ConsumerStatefulWidget {
  const TtsSettingsScreen({super.key});

  @override
  ConsumerState<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends ConsumerState<TtsSettingsScreen> {
  double _pitch = 1.0;
  double _rate = 0.5;
  double _volume = 1.0;
  
  // Advanced Settings
  bool _autoPlay = false;
  bool _ignoreBrackets = false;
  bool _onlyQuotes = false;
  bool _ignoreEnglish = false;
  bool _onlyAsterisks = false;
  String _selectedVoice = 'Default';
  String? _referenceAudioPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS 语音设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice Selection
          ListTile(
            title: const Text("声优 (Voice Actor)"),
            subtitle: Text(_selectedVoice + (_referenceAudioPath != null ? " (Cloned)" : "")),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showVoiceSelectionDialog,
          ),
          if (_referenceAudioPath != null)
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
               child: Row(
                 children: [
                   const Icon(Icons.audiotrack, size: 16, color: Colors.grey),
                   const SizedBox(width: 8),
                   Expanded(child: Text(_referenceAudioPath!, style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                   IconButton(
                     icon: const Icon(Icons.close, size: 16),
                     onPressed: () => setState(() => _referenceAudioPath = null),
                   )
                 ],
               ),
             ),

          const Divider(),

          // Sliders
          _buildSlider("语速 (Rate)", _rate, (val) => setState(() => _rate = val)),
          _buildSlider("音调 (Pitch)", _pitch, (val) => setState(() => _pitch = val)),
          _buildSlider("音量 (Volume)", _volume, (val) => setState(() => _volume = val)),
          
          const Divider(),
          
          // Toggles
          SwitchListTile(
            title: const Text("自动生成语音"),
            subtitle: const Text("AI回复后自动播放语音"),
            value: _autoPlay,
            onChanged: (val) => setState(() => _autoPlay = val),
          ),
          SwitchListTile(
            title: const Text("忽略括号内容"),
            subtitle: const Text("朗读时跳过括号内的文字"),
            value: _ignoreBrackets,
            onChanged: (val) => setState(() => _ignoreBrackets = val),
          ),
          SwitchListTile(
            title: const Text("只朗读引号内容"),
            subtitle: const Text("仅朗读引号内的对话部分"),
            value: _onlyQuotes,
            onChanged: (val) => setState(() => _onlyQuotes = val),
          ),
          SwitchListTile(
            title: const Text("忽略英文"),
            subtitle: const Text("朗读时跳过英文单词"),
            value: _ignoreEnglish,
            onChanged: (val) => setState(() => _ignoreEnglish = val),
          ),
          SwitchListTile(
            title: const Text("仅朗读星号内容"),
            subtitle: const Text("仅朗读星号包裹的动作描述"),
            value: _onlyAsterisks,
            onChanged: (val) => setState(() => _onlyAsterisks = val),
          ),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.record_voice_over),
            label: const Text("测试语音"),
            onPressed: () {
               ref.read(ttsProvider.notifier).speak(
                 "这是一个语音测试，欢迎使用 SillyTavern Flutter。",
                 // TODO: Pass settings
               );
            },
          ),
        ],
      ),
    );
  }

  void _showVoiceSelectionDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("选择声优", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    _buildVoiceOption("Default"),
                    _buildVoiceOption("Voice A (Male)"),
                    _buildVoiceOption("Voice B (Female)"),
                    _buildVoiceOption("Voice C (Cute)"),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.add, color: Colors.blue),
                      title: const Text("克隆音色 (Clone Voice)", style: TextStyle(color: Colors.blue)),
                      onTap: () async {
                        Navigator.pop(context);
                        await _pickReferenceAudio();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickReferenceAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _referenceAudioPath = result.files.single.path;
        _selectedVoice = "Cloned Voice";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("已选择参考音频，将在支持的后端使用。")),
      );
    }
  }

  Widget _buildVoiceOption(String name) {
    return ListTile(
      title: Text(name),
      trailing: _selectedVoice == name ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        setState(() => _selectedVoice = name);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildSlider(String label, double value, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
