import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pluginSettingsProvider =
    StateNotifierProvider<PluginSettingsNotifier, Map<String, dynamic>>((ref) {
  return PluginSettingsNotifier();
});

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
