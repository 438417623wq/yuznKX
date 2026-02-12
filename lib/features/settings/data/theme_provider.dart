import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Theme Settings Model ---
class ThemeSettings {
  final String? backgroundImagePath;
  final double backgroundBlur; // 0.0 - 20.0
  final double backgroundOpacity; // 0.0 - 1.0 (Dimming overlay)
  final Color userBubbleColor;
  final Color aiBubbleColor;
  final double fontSizeScale; // 0.8 - 1.5
  final bool isDarkMode;
  final String bubbleStyle; // 'classic', 'modern', 'transparent'

  const ThemeSettings({
    this.backgroundImagePath,
    this.backgroundBlur = 0.0,
    this.backgroundOpacity = 0.5,
    this.userBubbleColor = const Color(0xFF3F51B5), // Indigo
    this.aiBubbleColor = const Color(0xFF424242), // Grey[800]
    this.fontSizeScale = 1.0,
    this.isDarkMode = true,
    this.bubbleStyle = 'modern',
  });

  ThemeSettings copyWith({
    String? backgroundImagePath,
    double? backgroundBlur,
    double? backgroundOpacity,
    Color? userBubbleColor,
    Color? aiBubbleColor,
    double? fontSizeScale,
    bool? isDarkMode,
    String? bubbleStyle,
  }) {
    return ThemeSettings(
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      aiBubbleColor: aiBubbleColor ?? this.aiBubbleColor,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      bubbleStyle: bubbleStyle ?? this.bubbleStyle,
    );
  }
}

// --- Provider ---
final themeSettingsProvider = StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = ThemeSettings(
      backgroundImagePath: prefs.getString('bg_path'),
      backgroundBlur: prefs.getDouble('bg_blur') ?? 0.0,
      backgroundOpacity: prefs.getDouble('bg_opacity') ?? 0.5,
      userBubbleColor: Color(prefs.getInt('user_color') ?? 0xFF3F51B5),
      aiBubbleColor: Color(prefs.getInt('ai_color') ?? 0xFF424242),
      fontSizeScale: prefs.getDouble('font_scale') ?? 1.0,
      isDarkMode: prefs.getBool('dark_mode') ?? true,
      bubbleStyle: prefs.getString('bubble_style') ?? 'modern',
    );
  }

  Future<void> updateBackgroundImage(String? path) async {
    state = state.copyWith(backgroundImagePath: path);
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('bg_path', path);
    } else {
      await prefs.remove('bg_path');
    }
  }

  Future<void> updateBlur(double value) async {
    state = state.copyWith(backgroundBlur: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_blur', value);
  }

  Future<void> updateOpacity(double value) async {
    state = state.copyWith(backgroundOpacity: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bg_opacity', value);
  }

  Future<void> updateUserColor(Color color) async {
    state = state.copyWith(userBubbleColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_color', color.value);
  }

  Future<void> updateAiColor(Color color) async {
    state = state.copyWith(aiBubbleColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_color', color.value);
  }

  Future<void> updateFontSize(double scale) async {
    state = state.copyWith(fontSizeScale: scale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', scale);
  }

  Future<void> updateBubbleStyle(String style) async {
    state = state.copyWith(bubbleStyle: style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bubble_style', style);
  }
}
