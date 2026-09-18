import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/preset_provider.dart';
import '../../domain/models/preset.dart';
import '../../../regex/domain/models/regex_script.dart';
part 'preset_edit/preset_edit_parameters_extension.dart';
part 'preset_edit/preset_edit_function_extension.dart';
part 'preset_edit/preset_edit_prompts_extension.dart';
part 'preset_edit/preset_edit_regex_extension.dart';

class PresetEditScreen extends ConsumerStatefulWidget {
  final Preset? preset;
  const PresetEditScreen({super.key, this.preset});

  @override
  ConsumerState<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends ConsumerState<PresetEditScreen> {
  static const Color _accentColor = Color(0xFFD5BBFF);
  static const Color _accentSoftColor = Color(0xFF3A3150);
  static const Color _bgColor = Color(0xFF1C1B29);
  static const Color _tabBgColor = Color(0xFF242233);
  static const Color _surfaceColor = Color(0xFF222130);
  static const Color _surfaceAltColor = Color(0xFF2A2839);
  static const Color _textPrimaryColor = Color(0xFFF4F1FA);
  static const Color _textSecondaryColor = Color(0xFFD2CBDC);
  static const Color _borderColor = Color(0xFF3A3748);
  static const Color _dangerColor = Color(0xFFFF8E97);
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;

  // Parameters
  late double _temp;
  late double _repPen;
  late int _maxTokens;
  late double _topP;
  late int _topK;
  late double _freqPen;
  late double _presPen;

  // Function
  late TextEditingController _impersonationPromptCtrl;
  late TextEditingController _newChatPromptCtrl;
  late TextEditingController _newGroupChatPromptCtrl;
  late TextEditingController _continueNudgeCtrl;
  late TextEditingController _groupNudgePromptCtrl;

  // 停止序列（每行一条）
  late TextEditingController _stopStringsCtrl;

  // Prompts
  late List<PresetPrompt> _prompts;
  String _promptSearchQuery = '';
  bool _arePromptsExpanded = false;
  int _promptsExpansionVersion = 0;

  // Regex
  late List<RegexScript> _regexScripts;

  ThemeData _buildPageTheme(BuildContext context) {
    final base = Theme.of(context);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _accentColor,
      onPrimary: const Color(0xFF251C33),
      secondary: _accentColor,
      onSecondary: const Color(0xFF251C33),
      surface: _surfaceColor,
      onSurface: _textPrimaryColor,
      outline: _borderColor,
      error: _dangerColor,
    );

    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _bgColor,
      cardColor: _surfaceColor,
      dividerColor: _borderColor,
      textTheme: base.textTheme.apply(
        bodyColor: _textPrimaryColor,
        displayColor: _textPrimaryColor,
      ),
      iconTheme: const IconThemeData(color: _textSecondaryColor),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimaryColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceAltColor,
        prefixIconColor: _textSecondaryColor,
        labelStyle: const TextStyle(
          color: _textSecondaryColor,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: _textSecondaryColor.withValues(alpha: 0.85),
        ),
        floatingLabelStyle: const TextStyle(
          color: _accentColor,
          fontWeight: FontWeight.w700,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentColor, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _dangerColor, width: 1.4),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentColor,
          side: const BorderSide(color: _borderColor),
          backgroundColor: _surfaceColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: const Color(0xFF251C33),
          elevation: 0,
          minimumSize: const Size(double.infinity, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accentColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: _borderColor),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _accentColor;
          }
          return _surfaceColor;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: _textPrimaryColor,
        iconColor: _textSecondaryColor,
      ),
    );
  }

  RoundedRectangleBorder _sectionShape([double radius = 18]) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: _borderColor),
    );
  }

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _nameController = TextEditingController(text: p?.name ?? 'New Preset');

    _temp = (p?.temperature ?? 0.7).clamp(0.0, 2.0);
    _repPen = (p?.repetitionPenalty ?? 1.05).clamp(0.5, 2.0);
    _maxTokens = (p?.maxTokens ?? 2000).clamp(1, 131072).toInt();
    _topP = (p?.topP ?? 0.95).clamp(0.0, 1.0);
    _topK = (p?.topK ?? 40).clamp(0, 1000);
    _freqPen = (p?.frequencyPenalty ?? 0.0).clamp(-2.0, 2.0);
    _presPen = (p?.presencePenalty ?? 0.0).clamp(-2.0, 2.0);

    _impersonationPromptCtrl =
        TextEditingController(text: p?.impersonationPrompt ?? '');
    _newChatPromptCtrl = TextEditingController(text: p?.newChatPrompt ?? '');
    _newGroupChatPromptCtrl =
        TextEditingController(text: p?.newGroupChatPrompt ?? '');
    _continueNudgeCtrl = TextEditingController(text: p?.continueNudge ?? '');
    _groupNudgePromptCtrl =
        TextEditingController(text: p?.groupNudgePrompt ?? '');
    _stopStringsCtrl = TextEditingController(
      text: (p?.stopStrings ?? const <String>[]).join('\n'),
    );

    _prompts = p?.prompts != null ? List.from(p!.prompts) : [];
    _regexScripts = p?.regexScripts != null ? List.from(p!.regexScripts) : [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _impersonationPromptCtrl.dispose();
    _newChatPromptCtrl.dispose();
    _newGroupChatPromptCtrl.dispose();
    _continueNudgeCtrl.dispose();
    _groupNudgePromptCtrl.dispose();
    _stopStringsCtrl.dispose();
    super.dispose();
  }

  List<String> _parseStopStrings(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final newPreset = widget.preset?.copyWith(
          name: _nameController.text,
          temperature: _temp,
          repetitionPenalty: _repPen,
          maxTokens: _maxTokens,
          stopStrings: _parseStopStrings(_stopStringsCtrl.text),
          topP: _topP,
          topK: _topK,
          frequencyPenalty: _freqPen,
          presencePenalty: _presPen,
          prompts: _prompts,
          regexScripts: _regexScripts,
          impersonationPrompt: _impersonationPromptCtrl.text,
          newChatPrompt: _newChatPromptCtrl.text,
          newGroupChatPrompt: _newGroupChatPromptCtrl.text,
          continueNudge: _continueNudgeCtrl.text,
          groupNudgePrompt: _groupNudgePromptCtrl.text,
        ) ??
        Preset(
          id: const Uuid().v4(),
          name: _nameController.text,
          temperature: _temp,
          repetitionPenalty: _repPen,
          maxTokens: _maxTokens,
          stopStrings: _parseStopStrings(_stopStringsCtrl.text),
          topP: _topP,
          topK: _topK,
          frequencyPenalty: _freqPen,
          presencePenalty: _presPen,
          prompts: _prompts,
          regexScripts: _regexScripts,
          impersonationPrompt: _impersonationPromptCtrl.text,
          newChatPrompt: _newChatPromptCtrl.text,
          newGroupChatPrompt: _newGroupChatPromptCtrl.text,
          continueNudge: _continueNudgeCtrl.text,
          groupNudgePrompt: _groupNudgePromptCtrl.text,
        );

    ref.read(presetsProvider.notifier).save(newPreset);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildPageTheme(context),
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            title: Text(
              widget.preset == null ? '新建预设' : '编辑预设',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              if (widget.preset != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _dangerColor),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('删除预设'),
                        content: const Text('确认删除这个预设吗？此操作不可撤销。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              ref
                                  .read(presetsProvider.notifier)
                                  .delete(widget.preset!.id);
                              Navigator.pop(context);
                              Navigator.pop(context);
                            },
                            child: const Text(
                              '删除',
                              style: TextStyle(color: _dangerColor),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              IconButton(
                icon: const Icon(Icons.save_outlined, color: _accentColor),
                onPressed: _save,
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _tabBgColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _borderColor),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: _surfaceAltColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      dividerColor: Colors.transparent,
                      labelColor: _accentColor,
                      unselectedLabelColor: _textSecondaryColor,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(icon: Icon(Icons.tune), text: '参数'),
                        Tab(icon: Icon(Icons.terminal), text: '功能'),
                        Tab(icon: Icon(Icons.list_alt), text: 'Prompts'),
                        Tab(icon: Icon(Icons.data_array), text: '正则'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildParametersTab(),
                      _buildFunctionTab(),
                      _buildPromptsTab(),
                      _buildRegexTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
