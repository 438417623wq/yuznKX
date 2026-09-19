import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pluginSettingsProvider =
    StateNotifierProvider<PluginSettingsNotifier, Map<String, dynamic>>((ref) {
  return PluginSettingsNotifier();
});

/// 变量更新模式。
///
/// 模型每轮在回复末尾输出变量更新块，成本约 100~300 token。三档让用户
/// 自己权衡「面板会不会动」和「花多少钱」。
class VariableUpdateMode {
  const VariableUpdateMode._();

  /// 关闭：不注入指令、不解析、不写入。老卡的行为。
  static const String off = 'off';

  /// 只靠模型主动输出的指令块（默认）。
  static const String patch = 'patch';

  /// 指令块 + 兜底提取：本轮没解析到指令块时，额外发一次提取请求。
  /// 弱模型学不会格式时靠它兜住。
  static const String patchExtract = 'patch_extract';

  static const List<String> values = <String>[off, patch, patchExtract];

  static String normalize(String? raw) {
    final text = (raw ?? '').trim();
    if (values.contains(text)) {
      return text;
    }
    return patch;
  }

  /// 是否启用变量管道（注入 + 解析 + 写入）。
  static bool isEnabled(String? mode) => normalize(mode) != off;

  /// 是否启用兜底提取。
  static bool usesExtract(String? mode) => normalize(mode) == patchExtract;

  static String labelOf(String? mode) {
    switch (normalize(mode)) {
      case off:
        return '关闭';
      case patchExtract:
        return '指令块 + 兜底提取';
      default:
        return '仅指令块';
    }
  }
}

class PluginSettingsNotifier extends StateNotifier<Map<String, dynamic>> {
  PluginSettingsNotifier()
      : super({
          // 记忆表格的展示形态：'card'（卡片列表，手机推荐）/ 'table'（表格）
          'memory_view_mode': 'card',
          'frontend_advanced_render': true,
          'frontend_javascript_mode': 'auto',
          'frontend_character_card': true,
          'frontend_card_debug_panel': false,
          'show_model_debug_info': false,
          'variable_update_mode': VariableUpdateMode.patch,
          'model_debug_style':
              0, // 0: Terminal, 1: Glass, 2: Card, 3: Cyberpunk
        }) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = {
      'memory_view_mode':
          prefs.getString('plugin_memory_view_mode') ?? 'card',
      'frontend_advanced_render':
          prefs.getBool('plugin_frontend_advanced_render') ??
              prefs.getBool('plugin_frontend_character_card') ??
              true,
      'frontend_javascript_mode':
          prefs.getString('plugin_frontend_javascript_mode') ?? 'auto',
      'frontend_character_card':
          prefs.getBool('plugin_frontend_character_card') ?? true,
      'frontend_card_debug_panel':
          prefs.getBool('plugin_frontend_card_debug_panel') ?? false,
      'show_model_debug_info':
          prefs.getBool('plugin_show_model_debug_info') ?? false,
      'variable_update_mode': VariableUpdateMode.normalize(
        prefs.getString('plugin_variable_update_mode'),
      ),
      'model_debug_style': prefs.getInt('plugin_model_debug_style') ?? 0,
    };
  }

  Future<void> toggle(String key) async {
    final prefs = await SharedPreferences.getInstance();
    // Safe cast since map values are bool in the map definition, but dynamic is safer for logic
    final current = state[key];
    final bool newValue = current is bool ? !current : true;

    await prefs.setBool('plugin_$key', newValue);
    state = {...state, key: newValue};
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin_$key', value);
    state = {...state, key: value};
  }

  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_$key', value);
    state = {...state, key: value};
  }

  Future<void> setStyle(int styleIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('plugin_model_debug_style', styleIndex);
    state = {...state, 'model_debug_style': styleIndex};
  }

  Future<void> resetFrontendRenderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin_frontend_advanced_render', true);
    await prefs.setString('plugin_frontend_javascript_mode', 'auto');
    state = {
      ...state,
      'frontend_advanced_render': true,
      'frontend_javascript_mode': 'auto',
    };
  }
}
