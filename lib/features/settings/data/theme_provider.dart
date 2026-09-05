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

  // New customization fields
  final Color mainTextColor;
  final Color italicTextColor;
  final Color underlineTextColor;
  final Color quoteTextColor;
  final Color shadowColor;
  final Color chatBackgroundColor;
  final Color uiBackgroundColor;
  final Color uiBorderColor;
  final Color userMessageBlurTint;
  final Color aiMessageBlurTint;
  final Color narrationColor;

  // Pattern Recognition Flags
  final bool recognizeAsteriskNarration; // *...*
  final bool recognizeParenthesesNarration; // (...)
  final bool recognizeFullWidthParenthesesNarration; // （...）
  
  final bool recognizeDoubleQuoteSpeech; // "..."
  final bool recognizeFullWidthDoubleQuoteSpeech; // “...”
  final bool recognizeCornerBracketSpeech; // 「...」

  const ThemeSettings({
    this.backgroundImagePath,
    this.backgroundBlur = 0.0,
    this.backgroundOpacity = 0.5,
    this.userBubbleColor = const Color(0xFF3F51B5), // Indigo
    this.aiBubbleColor = const Color(0xFF424242), // Grey[800]
    this.fontSizeScale = 1.0,
    this.isDarkMode = true,
    this.bubbleStyle = 'modern',
    
    // Defaults
    this.mainTextColor = Colors.white,
    this.italicTextColor = Colors.grey,
    this.underlineTextColor = Colors.blueAccent, // Usually links
    this.quoteTextColor = Colors.grey,
    this.shadowColor = Colors.black45,
    this.chatBackgroundColor = const Color(0xFF121212), // Dark background
    this.uiBackgroundColor = const Color(0xFF1E1E1E), // Slightly lighter
    this.uiBorderColor = Colors.white24,
    this.userMessageBlurTint = const Color(0x803F51B5), // Semi-transparent indigo
    this.aiMessageBlurTint = const Color(0x80424242), // Semi-transparent grey
    this.narrationColor = Colors.grey,

    this.recognizeAsteriskNarration = true,
    this.recognizeParenthesesNarration = true,
    this.recognizeFullWidthParenthesesNarration = true,
    this.recognizeDoubleQuoteSpeech = true,
    this.recognizeFullWidthDoubleQuoteSpeech = true,
    this.recognizeCornerBracketSpeech = false,
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
    Color? mainTextColor,
    Color? italicTextColor,
    Color? underlineTextColor,
    Color? quoteTextColor,
    Color? shadowColor,
    Color? chatBackgroundColor,
    Color? uiBackgroundColor,
    Color? uiBorderColor,
    Color? userMessageBlurTint,
    Color? aiMessageBlurTint,
    Color? narrationColor,
    bool? recognizeAsteriskNarration,
    bool? recognizeParenthesesNarration,
    bool? recognizeFullWidthParenthesesNarration,
    bool? recognizeDoubleQuoteSpeech,
    bool? recognizeFullWidthDoubleQuoteSpeech,
    bool? recognizeCornerBracketSpeech,
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
      mainTextColor: mainTextColor ?? this.mainTextColor,
      italicTextColor: italicTextColor ?? this.italicTextColor,
      underlineTextColor: underlineTextColor ?? this.underlineTextColor,
      quoteTextColor: quoteTextColor ?? this.quoteTextColor,
      shadowColor: shadowColor ?? this.shadowColor,
      chatBackgroundColor: chatBackgroundColor ?? this.chatBackgroundColor,
      uiBackgroundColor: uiBackgroundColor ?? this.uiBackgroundColor,
      uiBorderColor: uiBorderColor ?? this.uiBorderColor,
      userMessageBlurTint: userMessageBlurTint ?? this.userMessageBlurTint,
      aiMessageBlurTint: aiMessageBlurTint ?? this.aiMessageBlurTint,
      narrationColor: narrationColor ?? this.narrationColor,
      recognizeAsteriskNarration: recognizeAsteriskNarration ?? this.recognizeAsteriskNarration,
      recognizeParenthesesNarration: recognizeParenthesesNarration ?? this.recognizeParenthesesNarration,
      recognizeFullWidthParenthesesNarration: recognizeFullWidthParenthesesNarration ?? this.recognizeFullWidthParenthesesNarration,
      recognizeDoubleQuoteSpeech: recognizeDoubleQuoteSpeech ?? this.recognizeDoubleQuoteSpeech,
      recognizeFullWidthDoubleQuoteSpeech: recognizeFullWidthDoubleQuoteSpeech ?? this.recognizeFullWidthDoubleQuoteSpeech,
      recognizeCornerBracketSpeech: recognizeCornerBracketSpeech ?? this.recognizeCornerBracketSpeech,
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
      
      mainTextColor: Color(prefs.getInt('main_text_color') ?? Colors.white.value),
      italicTextColor: Color(prefs.getInt('italic_text_color') ?? Colors.grey.value),
      underlineTextColor: Color(prefs.getInt('underline_text_color') ?? Colors.blueAccent.value),
      quoteTextColor: Color(prefs.getInt('quote_text_color') ?? Colors.grey.value),
      shadowColor: Color(prefs.getInt('shadow_color') ?? Colors.black45.value),
      chatBackgroundColor: Color(prefs.getInt('chat_bg_color') ?? 0xFF121212),
      uiBackgroundColor: Color(prefs.getInt('ui_bg_color') ?? 0xFF1E1E1E),
      uiBorderColor: Color(prefs.getInt('ui_border_color') ?? Colors.white24.value),
      userMessageBlurTint: Color(prefs.getInt('user_blur_tint') ?? 0x803F51B5),
      aiMessageBlurTint: Color(prefs.getInt('ai_blur_tint') ?? 0x80424242),
      narrationColor: Color(prefs.getInt('narration_color') ?? Colors.grey.value),

      recognizeAsteriskNarration: prefs.getBool('rec_asterisk') ?? true,
      recognizeParenthesesNarration: prefs.getBool('rec_parentheses') ?? true,
      recognizeFullWidthParenthesesNarration: prefs.getBool('rec_full_parentheses') ?? true,
      recognizeDoubleQuoteSpeech: prefs.getBool('rec_double_quote') ?? true,
      recognizeFullWidthDoubleQuoteSpeech: prefs.getBool('rec_full_double_quote') ?? true,
      recognizeCornerBracketSpeech: prefs.getBool('rec_corner_bracket') ?? false,
    );
  }

  Future<void> updateColor(String key, Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, color.value);
    
    switch (key) {
      case 'user_color': state = state.copyWith(userBubbleColor: color); break;
      case 'ai_color': state = state.copyWith(aiBubbleColor: color); break;
      case 'main_text_color': state = state.copyWith(mainTextColor: color); break;
      case 'italic_text_color': state = state.copyWith(italicTextColor: color); break;
      case 'underline_text_color': state = state.copyWith(underlineTextColor: color); break;
      case 'quote_text_color': state = state.copyWith(quoteTextColor: color); break;
      case 'shadow_color': state = state.copyWith(shadowColor: color); break;
      case 'chat_bg_color': state = state.copyWith(chatBackgroundColor: color); break;
      case 'ui_bg_color': state = state.copyWith(uiBackgroundColor: color); break;
      case 'ui_border_color': state = state.copyWith(uiBorderColor: color); break;
      case 'user_blur_tint': state = state.copyWith(userMessageBlurTint: color); break;
      case 'ai_blur_tint': state = state.copyWith(aiMessageBlurTint: color); break;
      case 'narration_color': state = state.copyWith(narrationColor: color); break;
    }
  }

  Future<void> togglePattern(String key) async {
    final prefs = await SharedPreferences.getInstance();
    bool newValue = false;
    
    switch (key) {
      case 'rec_asterisk': 
        newValue = !state.recognizeAsteriskNarration;
        state = state.copyWith(recognizeAsteriskNarration: newValue);
        break;
      case 'rec_parentheses':
        newValue = !state.recognizeParenthesesNarration;
        state = state.copyWith(recognizeParenthesesNarration: newValue);
        break;
      case 'rec_full_parentheses':
        newValue = !state.recognizeFullWidthParenthesesNarration;
        state = state.copyWith(recognizeFullWidthParenthesesNarration: newValue);
        break;
      case 'rec_double_quote':
        newValue = !state.recognizeDoubleQuoteSpeech;
        state = state.copyWith(recognizeDoubleQuoteSpeech: newValue);
        break;
      case 'rec_full_double_quote':
        newValue = !state.recognizeFullWidthDoubleQuoteSpeech;
        state = state.copyWith(recognizeFullWidthDoubleQuoteSpeech: newValue);
        break;
      case 'rec_corner_bracket':
        newValue = !state.recognizeCornerBracketSpeech;
        state = state.copyWith(recognizeCornerBracketSpeech: newValue);
        break;
    }
    await prefs.setBool(key, newValue);
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
