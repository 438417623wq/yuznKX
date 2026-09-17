import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter_animate/flutter_animate.dart'; // For typing animation
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../../../settings/data/theme_provider.dart';
import '../../../settings/domain/plugin_settings_provider.dart';

class ChatBubble extends ConsumerWidget {
  final String content;
  final bool isUser;
  final String name;
  final String? avatarPath;
  final int swipeIndex;
  final int swipeCount;
  final Function(int)? onSwipe;
  final VoidCallback? onRegenerate;
  final Function(String)? onEdit;
  final VoidCallback? onTts;
  final Map<String, dynamic>? metadata;
  final bool isGenerating; // New parameter

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    required this.name,
    this.avatarPath,
    this.swipeIndex = 0,
    this.swipeCount = 1,
    this.onSwipe,
    this.onRegenerate,
    this.onEdit,
    this.onTts,
    this.metadata,
    this.isGenerating = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final settings = ref.watch(pluginSettingsProvider);
    final showDebug = settings['show_model_debug_info'] == true;
    final debugStyle = settings['model_debug_style'] as int? ?? 0;
    final renderConfig = _FrontendRenderConfig.fromSettings(settings);
    final contentSegments = _splitContentSegments(content, renderConfig);

    // Define syntaxes based on settings
    final List<md.InlineSyntax> syntaxes = [];
    if (themeSettings.recognizeParenthesesNarration) {
      // Do not consume markdown links/images like ![alt](url).
      syntaxes.add(NarrationSyntax(r'(?<!\])\(.*?\)', 'narration'));
    }
    if (themeSettings.recognizeFullWidthParenthesesNarration)
      syntaxes.add(NarrationSyntax(r'\uff08.*?\uff09', 'narration'));
    if (themeSettings.recognizeDoubleQuoteSpeech)
      syntaxes.add(NarrationSyntax(
          r'".*?"', 'quote')); // Use NarrationSyntax logic but tag as quote
    if (themeSettings.recognizeFullWidthDoubleQuoteSpeech)
      syntaxes.add(NarrationSyntax(r'\u201c.*?\u201d', 'quote'));
    if (themeSettings.recognizeCornerBracketSpeech)
      syntaxes.add(NarrationSyntax(r'\u300c.*?\u300d', 'quote'));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      width: double.infinity, // Full width
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Center everything
        children: [
          // Avatar centered above message
          CircleAvatar(
            backgroundImage: (avatarPath != null && avatarPath!.isNotEmpty)
                ? FileImage(File(avatarPath!)) as ImageProvider
                : const NetworkImage('https://via.placeholder.com/150'),
            radius: 25 * themeSettings.fontSizeScale,
          ),
          const SizedBox(height: 8),

          // Name and Controls Row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  fontSize: 14 * themeSettings.fontSizeScale,
                ),
              ),
              if (swipeCount > 1) ...[
                const SizedBox(width: 8),
                _buildSwipeControls(),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Message Content - Stretched Full Screen Width with padding
          GestureDetector(
            onLongPress: () => _showContextMenu(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? themeSettings.userMessageBlurTint
                    : themeSettings.aiMessageBlurTint,
                boxShadow: [
                  BoxShadow(
                    color: themeSettings.shadowColor,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDebug && metadata != null)
                    _buildDebugInfo(metadata!, debugStyle),
                  if (content.isEmpty && isGenerating)
                    _buildTypingIndicator(themeSettings)
                  else
                    _buildRichMessageContent(
                      contentSegments,
                      syntaxes,
                      themeSettings,
                      isGenerating,
                      settings['frontend_card_debug_panel'] == true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichMessageContent(List<_ContentSegment> segments,
      List<md.InlineSyntax> syntaxes, ThemeSettings themeSettings,
      bool isGenerating, bool showCardDebug) {
    if (segments.length == 1 &&
        segments.first.type == _ContentSegmentType.text) {
      return _buildMarkdownBlock(segments.first.value, syntaxes, themeSettings);
/*
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FrontendCardMessageDebugHeader(totalCards: 0),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x33111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              '当前消息未匹配到前端角色卡代码块。\n预期格式: ```frontendcard ... ```',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          _buildMarkdownBlock(segments.first.value, syntaxes, themeSettings),
        ],
      );
*/
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in segments.asMap().entries)
          if (entry.value.type == _ContentSegmentType.card)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FrontendCardWithDebug(
                html: entry.value.value,
                rawHtml: entry.value.rawSource,
                enableJavaScript: entry.value.enableJavaScript,
                isGenerating: isGenerating,
                showDebugPanel: showCardDebug,
                cardIndex: entry.key + 1,
                totalCards: segments
                    .where((s) => s.type == _ContentSegmentType.card)
                    .length,
              ),
            )
          else if (entry.value.value.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _buildMarkdownBlock(
                  entry.value.value, syntaxes, themeSettings),
            ),
      ],
    );
  }

  Widget _buildMarkdownBlock(
    String rawText,
    List<md.InlineSyntax> syntaxes,
    ThemeSettings themeSettings,
  ) {
    final markdownContent = _normalizeContentForMarkdown(rawText);
    return MarkdownBody(
      data: markdownContent,
      extensionSet: md.ExtensionSet.none,
      inlineSyntaxes: [
        ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
        ...syntaxes,
      ],
      imageBuilder: (uri, title, alt) => _buildMarkdownImage(uri, alt),
      builders: {
        'narration': CustomElementBuilder(
          textStyle: TextStyle(
            color: themeSettings.narrationColor,
            fontStyle: FontStyle.italic,
            fontSize: 16 * themeSettings.fontSizeScale,
          ),
        ),
        'quote': CustomElementBuilder(
          textStyle: TextStyle(
            color: themeSettings.quoteTextColor,
            fontWeight: FontWeight.normal,
            fontSize: 16 * themeSettings.fontSizeScale,
          ),
        ),
        'code': CodeElementBuilder(themeSettings),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: themeSettings.mainTextColor,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
        code: TextStyle(
          color: Colors.pinkAccent,
          backgroundColor: Colors.transparent,
          fontFamily: 'monospace',
          fontSize: 14 * themeSettings.fontSizeScale,
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF282c34),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquote: TextStyle(
          color: themeSettings.quoteTextColor,
          fontStyle: FontStyle.italic,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
        blockquoteDecoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        em: TextStyle(
          color: themeSettings.recognizeAsteriskNarration
              ? themeSettings.narrationColor
              : themeSettings.italicTextColor,
          fontStyle: FontStyle.italic,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
        strong: TextStyle(
          color: themeSettings.mainTextColor,
          fontWeight: FontWeight.bold,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
        a: TextStyle(
          color: themeSettings.underlineTextColor,
          decoration: TextDecoration.underline,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
        del: TextStyle(
          color: themeSettings.mainTextColor,
          decoration: TextDecoration.lineThrough,
          fontSize: 16 * themeSettings.fontSizeScale,
        ),
      ),
    );
  }

  List<_ContentSegment> _splitContentSegments(
    String raw,
    _FrontendRenderConfig config,
  ) {
    if (!config.enabled) {
      return [_ContentSegment.text(raw)];
    }

    final pattern = RegExp(
      r'(?:<!--\s*\{\{_1::([^}]+)\}\}\s*-->\s*)?```([a-zA-Z0-9_-]*)\s*\n([\s\S]*?)\n```',
      caseSensitive: false,
      multiLine: true,
    );
    final innerTriggerPattern =
        RegExp(r'<!--\s*\{\{_1::([^}]+)\}\}\s*-->', caseSensitive: false);
    final placeholderPattern = RegExp(r'\{\{_1::.*?\}\}', caseSensitive: false);
    final segments = <_ContentSegment>[];
    var cursor = 0;

    for (final match in pattern.allMatches(raw)) {
      if (match.start > cursor) {
        _appendTextSegments(
          segments,
          raw.substring(cursor, match.start),
          config,
        );
      }

      final outsideTrigger = (match.group(1) ?? '').trim();
      final language = (match.group(2) ?? '').trim().toLowerCase();
      var htmlContent = (match.group(3) ?? '').trim();
      final innerTriggerMatch = innerTriggerPattern.firstMatch(htmlContent);
      final innerTrigger = (innerTriggerMatch?.group(1) ?? '').trim();
      final trigger = innerTrigger.isNotEmpty ? innerTrigger : outsideTrigger;

      htmlContent = htmlContent.replaceAll(innerTriggerPattern, '').trim();
      if (trigger.isNotEmpty) {
        htmlContent = htmlContent.replaceAll(placeholderPattern, trigger);
      }

      if (_shouldRenderAsFrontendCard(language, htmlContent, config)) {
        final preparedPayload =
            _prepareFrontendCardPayload(htmlContent, language);
        final enableJavaScript =
            _shouldEnableJavaScript(language, preparedPayload, config);
        segments.add(
          _ContentSegment.card(
            _buildCardPayload(preparedPayload, enableJavaScript),
            enableJavaScript: enableJavaScript,
            rawSource: preparedPayload,
          ),
        );
      } else {
        segments.add(_ContentSegment.text(match.group(0) ?? htmlContent));
      }
      cursor = match.end;
    }

    if (cursor < raw.length) {
      _appendTextSegments(segments, raw.substring(cursor), config);
    }

    if (segments.isEmpty) {
      return _extractEmbeddedHtmlSegments(raw, config);
    }
    return _mergeAdjacentCardSegments(_mergeAdjacentTextSegments(segments));
  }

  String _buildCardPayload(String preparedPayload, bool enableJavaScript) {
    final payload = enableJavaScript
        ? preparedPayload
        : _stripExecutableScripts(preparedPayload);
    return _wrapFrontendCardHtml(payload);
  }

  // A card's markup and the script that populates it are usually written as
  // separate blocks in the same message. Rendering each block in its own
  // WebView leaves the script without its target element, so adjacent card
  // blocks (even when only whitespace separates them) are merged into a
  // single document.
  List<_ContentSegment> _mergeAdjacentCardSegments(
      List<_ContentSegment> segments) {
    if (segments.length < 2) {
      return segments;
    }

    final merged = <_ContentSegment>[];
    var pendingWhitespace = '';

    for (final segment in segments) {
      if (segment.type == _ContentSegmentType.card) {
        if (merged.isNotEmpty && merged.last.type == _ContentSegmentType.card) {
          final previous = merged.removeLast();
          final separator =
              pendingWhitespace.isEmpty ? '\n' : pendingWhitespace;
          final combined = '${previous.rawSource}$separator${segment.rawSource}';
          final enableJavaScript =
              previous.enableJavaScript || segment.enableJavaScript;
          merged.add(
            _ContentSegment.card(
              _buildCardPayload(combined, enableJavaScript),
              enableJavaScript: enableJavaScript,
              rawSource: combined,
            ),
          );
        } else {
          if (pendingWhitespace.isNotEmpty) {
            merged.add(_ContentSegment.text(pendingWhitespace));
          }
          merged.add(segment);
        }
        pendingWhitespace = '';
        continue;
      }

      if (segment.value.trim().isEmpty) {
        pendingWhitespace += segment.value;
        continue;
      }

      if (pendingWhitespace.isNotEmpty) {
        merged.add(_ContentSegment.text(pendingWhitespace));
        pendingWhitespace = '';
      }
      merged.add(segment);
    }

    if (pendingWhitespace.isNotEmpty && merged.isNotEmpty) {
      merged.add(_ContentSegment.text(pendingWhitespace));
    }

    return merged;
  }

  void _appendTextSegments(
    List<_ContentSegment> target,
    String rawText,
    _FrontendRenderConfig config,
  ) {
    if (rawText.isEmpty) {
      return;
    }
    target.addAll(_extractEmbeddedHtmlSegments(rawText, config));
  }

  List<_ContentSegment> _extractEmbeddedHtmlSegments(
    String raw,
    _FrontendRenderConfig config,
  ) {
    if (raw.isEmpty) {
      return const [];
    }

    final segments = <_ContentSegment>[];
    var cursor = 0;

    while (cursor < raw.length) {
      final documentMatch =
          _firstMatchFrom(_htmlDocumentStartPattern, raw, cursor);
      final fragmentMatch =
          _firstMatchFrom(_htmlFragmentStartPattern, raw, cursor);

      Match? nextMatch;
      var isDocument = false;
      if (documentMatch != null &&
          (fragmentMatch == null ||
              documentMatch.start <= fragmentMatch.start)) {
        nextMatch = documentMatch;
        isDocument = true;
      } else if (fragmentMatch != null) {
        nextMatch = fragmentMatch;
      }

      if (nextMatch == null) {
        segments.add(_ContentSegment.text(raw.substring(cursor)));
        break;
      }

      if (nextMatch.start > cursor) {
        segments
            .add(_ContentSegment.text(raw.substring(cursor, nextMatch.start)));
      }

      final capture = isDocument
          ? _captureHtmlDocument(raw, nextMatch.start)
          : _captureHtmlFragment(raw, nextMatch.start);

      if (capture == null || capture.end <= nextMatch.start) {
        segments.add(
          _ContentSegment.text(
              raw.substring(nextMatch.start, nextMatch.start + 1)),
        );
        cursor = nextMatch.start + 1;
        continue;
      }

      final preparedPayload = _prepareFrontendCardPayload(capture.html, '');
      final enableJavaScript =
          _shouldEnableJavaScript('', preparedPayload, config);
      segments.add(
        _ContentSegment.card(
          _buildCardPayload(preparedPayload, enableJavaScript),
          enableJavaScript: enableJavaScript,
          rawSource: preparedPayload,
        ),
      );
      cursor = capture.end;
    }

    return _mergeAdjacentCardSegments(_mergeAdjacentTextSegments(
      segments.isEmpty ? [_ContentSegment.text(raw)] : segments,
    ));
  }

  Match? _firstMatchFrom(RegExp pattern, String input, int start) {
    for (final match in pattern.allMatches(input, start)) {
      return match;
    }
    return null;
  }

  _HtmlFragmentCapture? _captureHtmlDocument(String raw, int start) {
    final lowerRaw = raw.toLowerCase();
    const closeTag = '</html>';
    final closeIndex = lowerRaw.indexOf(closeTag, start);
    final end = closeIndex >= start ? closeIndex + closeTag.length : raw.length;
    final html = raw.substring(start, end).trim();
    if (html.isEmpty) {
      return null;
    }
    return _HtmlFragmentCapture(html: html, end: end);
  }

  _HtmlFragmentCapture? _captureHtmlFragment(String raw, int start) {
    final openMatch = RegExp(
      r'<([a-zA-Z][\w:-]*)\b[^>]*>',
      caseSensitive: false,
    ).matchAsPrefix(raw, start);
    if (openMatch == null) {
      return null;
    }

    final tagName = (openMatch.group(1) ?? '').toLowerCase();
    if (tagName.isEmpty) {
      return null;
    }

    if (tagName == 'script' || tagName == 'style') {
      final closeTag = '</$tagName>';
      final closeIndex = raw.toLowerCase().indexOf(closeTag, openMatch.end);
      final end = closeIndex >= openMatch.end
          ? closeIndex + closeTag.length
          : raw.length;
      final html = raw.substring(start, end).trim();
      if (html.isEmpty) {
        return null;
      }
      return _HtmlFragmentCapture(html: html, end: end);
    }

    final tokenPattern = RegExp(
      '</?$tagName\\b[^>]*>',
      caseSensitive: false,
      multiLine: true,
    );

    var depth = 0;
    for (final token in tokenPattern.allMatches(raw, start)) {
      final tokenText = token.group(0) ?? '';
      final isClosing = tokenText.startsWith('</');
      final isSelfClosing = !isClosing && tokenText.endsWith('/>');

      if (!isClosing && !isSelfClosing) {
        depth++;
      } else if (isClosing) {
        depth--;
      }

      if (depth == 0 && token.end > start) {
        final html = raw.substring(start, token.end).trim();
        if (html.isEmpty) {
          return null;
        }
        return _HtmlFragmentCapture(html: html, end: token.end);
      }
    }

    return null;
  }

  bool _shouldRenderAsFrontendCard(
    String language,
    String content,
    _FrontendRenderConfig config,
  ) {
    const explicitLanguages = {
      'frontendcard',
      'frontendcard-v2',
      'card',
      'html',
      'xml',
      'vue',
    };

    if (_isJavaScriptFence(language)) {
      // A js-fenced block is a card by intent in every mode but "disabled";
      // _shouldEnableJavaScript decides whether its scripts actually run.
      return config.javaScriptMode != _FrontendJavaScriptMode.disabled;
    }

    final hasHtmlDocument = _hasHtmlDocument(content);
    final hasHtmlFragment = _looksLikeHtmlFragment(content);
    final hasExecutableJavaScript = _containsExecutableJavaScript(content);

    if (explicitLanguages.contains(language)) {
      return true;
    }

    if (config.javaScriptMode == _FrontendJavaScriptMode.codeBlock) {
      return hasHtmlDocument || hasHtmlFragment;
    }

    if (config.javaScriptMode == _FrontendJavaScriptMode.script) {
      return hasHtmlDocument || hasHtmlFragment || hasExecutableJavaScript;
    }

    return hasHtmlDocument || hasHtmlFragment;
  }

  String _prepareFrontendCardPayload(
    String rawContent,
    String language,
  ) {
    final trimmed = rawContent.trim();
    if (_isJavaScriptFence(language)) {
      return '''
<div id="app"></div>
<script>
$trimmed
</script>
''';
    }
    return trimmed;
  }

  bool _hasHtmlDocument(String raw) {
    return _htmlDocumentStartPattern.hasMatch(raw);
  }

  bool _isJavaScriptFence(String language) {
    return const {
      'js',
      'javascript',
      'jsx',
      'ts',
      'typescript',
      'tsx',
    }.contains(language.trim().toLowerCase());
  }

  bool _containsExecutableJavaScript(String raw) {
    return RegExp(r'<script\b', caseSensitive: false).hasMatch(raw) ||
        RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(raw) ||
        RegExp(r'javascript\s*:', caseSensitive: false).hasMatch(raw);
  }

  bool _shouldEnableJavaScript(
    String language,
    String content,
    _FrontendRenderConfig config,
  ) {
    if (!config.enabled ||
        config.javaScriptMode == _FrontendJavaScriptMode.disabled) {
      return false;
    }

    if (_isJavaScriptFence(language)) {
      // The fence already declares the block as JavaScript, so run it in every
      // mode except an explicit opt-out.
      return true;
    }

    switch (config.javaScriptMode) {
      case _FrontendJavaScriptMode.disabled:
        return false;
      case _FrontendJavaScriptMode.codeBlock:
        return language.isNotEmpty && _containsExecutableJavaScript(content);
      case _FrontendJavaScriptMode.script:
        return language.isEmpty && _containsExecutableJavaScript(content);
      case _FrontendJavaScriptMode.auto:
        return _containsExecutableJavaScript(content);
    }
  }

  String _stripExecutableScripts(String raw) {
    return raw
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp("\\s+on[a-z]+\\s*=\\s*(\".*?\"|'.*?'|[^\\s>]+)",
              caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'javascript\s*:', caseSensitive: false),
          '',
        );
  }

  bool _looksLikeHtmlFragment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    if (trimmed.contains('<script') || trimmed.contains('<style')) {
      return true;
    }

    return RegExp(
      r'^<(div|section|article|aside|header|footer|table|svg|canvas|details|button|input|form|iframe)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  List<_ContentSegment> _mergeAdjacentTextSegments(
      List<_ContentSegment> segments) {
    if (segments.isEmpty) {
      return const [];
    }

    final merged = <_ContentSegment>[];
    for (final segment in segments) {
      if (segment.type == _ContentSegmentType.text &&
          merged.isNotEmpty &&
          merged.last.type == _ContentSegmentType.text) {
        final previous = merged.removeLast();
        merged.add(_ContentSegment.text(previous.value + segment.value));
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }

  String _wrapFrontendCardHtml(String rawHtml) {
    final trimmed = rawHtml.trim();
    final hasHtmlTag =
        RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(trimmed);
    final hostStyle = '''
<style>
  html, body {
    margin: 0 !important;
    padding: 0 !important;
    background: transparent !important;
    -webkit-text-size-adjust: 100% !important;
    overflow-x: hidden !important;
  }
  body {
    min-height: 200px;
  }
  img, video, canvas, svg {
    max-width: 100% !important;
    height: auto !important;
  }
  table {
    display: block !important;
    max-width: 100% !important;
    overflow-x: auto !important;
  }
  pre {
    white-space: pre-wrap !important;
    word-wrap: break-word !important;
    max-width: 100% !important;
  }
</style>
''';
    final hostScript = '''
<script>
  (function () {
    window.__frontendCardDebugErrors = [];
    var lastPostedHeight = 0;

    function pushLog(message) {
      try {
        if (!message) return;
        var text = String(message);
        window.__frontendCardDebugErrors.push(text);
        if (window.FlutterCardLog && window.FlutterCardLog.postMessage) {
          window.FlutterCardLog.postMessage(text);
        }
      } catch (_) {}
    }

    function getElementBottom(element, rootTop) {
      if (!element) return 0;
      var rect = element.getBoundingClientRect();
      return Math.max(0, (rect.bottom || 0) - rootTop);
    }

    function measureHeight() {
      var body = document.body;
      var html = document.documentElement;
      if (!body || !html) return 0;

      var bodyRect = body.getBoundingClientRect();
      var maxBottom = 0;
      var children = body.children || [];
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (!child || child.tagName === 'SCRIPT' || child.tagName === 'STYLE' || child.tagName === 'LINK') {
          continue;
        }
        var style = window.getComputedStyle(child);
        if (style && (style.position === 'fixed' || style.position === 'sticky')) {
          continue;
        }
        var offsetBottom = (child.offsetTop || 0) + (child.offsetHeight || 0);
        maxBottom = Math.max(
          maxBottom,
          getElementBottom(child, bodyRect.top || 0),
          offsetBottom
        );
      }

      var bodyStyle = window.getComputedStyle(body);
      var marginBottom = parseFloat(bodyStyle.marginBottom || '0') || 0;
      return Math.ceil(Math.max(
        body.scrollHeight || 0,
        body.offsetHeight || 0,
        maxBottom + marginBottom
      ));
    }

    function postHeight() {
      try {
        var height = Math.max(measureHeight(), 200);
        if (lastPostedHeight > 0 && Math.abs(height - lastPostedHeight) <= 1) {
          return;
        }
        lastPostedHeight = height;
        if (window.FlutterCardHeight && window.FlutterCardHeight.postMessage) {
          window.FlutterCardHeight.postMessage(String(height));
        }
      } catch (error) {
        pushLog('[height] ' + error);
      }
    }

    var resizeQueued = false;
    function scheduleHeightSync() {
      if (resizeQueued) return;
      resizeQueued = true;
      requestAnimationFrame(function () {
        resizeQueued = false;
        postHeight();
      });
    }

    window.triggerSlash = function (text) {
      pushLog('[triggerSlash] ' + String(text));
      if (window.FlutterCardLog && window.FlutterCardLog.postMessage) {
        window.FlutterCardLog.postMessage('[triggerSlash] ' + String(text));
      }
    };

    // Minimal SillyTavern surface so cards written against the desktop
    // extension API fail loudly in the log instead of throwing during load.
    if (!window.SillyTavern) {
      window.SillyTavern = {};
    }
    if (typeof window.SillyTavern.getContext !== 'function') {
      window.SillyTavern.getContext = function () {
        return {
          name: 'SillyTavern',
          chatId: 'flutter-host',
          characters: [],
          chat: [],
          chatMetadata: {},
          extensionSettings: {},
          powerUserSettings: {},
          variables: {},
          getRequestHeaders: function () { return {}; },
          saveSettingsDebounced: function () {},
          saveMetadata: function () {},
          eventSource: {},
          eventTypes: {},
          substituteParams: function (value) { return value; },
          renderExtensionTemplateAsync: function () {
            return Promise.resolve('');
          }
        };
      };
    }

    if (!window.TavernHelper) {
      window.TavernHelper = {
        getVariables: function () { return {}; },
        replaceVariables: function (value) { return value; },
        setVariables: function (variables, options) {
          pushLog('[TavernHelper.setVariables] ' + JSON.stringify(variables));
          return Promise.resolve();
        },
        insertOrAssignVariables: function (variables) {
          pushLog(
            '[TavernHelper.insertOrAssignVariables] ' + JSON.stringify(variables)
          );
          return Promise.resolve();
        },
        triggerSlash: window.triggerSlash,
        getLastMessageId: function () { return -1; },
        getChatMessages: function () { return []; },
        formatAsTavernRegexedString: function (value) { return value; }
      };
    }

    window.addEventListener('error', function (event) {
      pushLog('[window.error] ' + (event && event.message ? event.message : 'unknown'));
    });

    window.addEventListener('unhandledrejection', function (event) {
      var reason = event && event.reason ? event.reason : 'unknown';
      pushLog('[unhandledrejection] ' + String(reason));
    });

    var originalConsoleError = console.error;
    console.error = function () {
      try {
        var args = Array.prototype.slice.call(arguments);
        pushLog('[console.error] ' + args.join(' '));
      } catch (_) {}
      if (originalConsoleError) {
        originalConsoleError.apply(console, arguments);
      }
    };

    window.addEventListener('load', function () {
      scheduleHeightSync();
      setTimeout(scheduleHeightSync, 120);
      setTimeout(scheduleHeightSync, 400);
      setTimeout(scheduleHeightSync, 1000);
    });
    window.addEventListener('resize', scheduleHeightSync);
    window.addEventListener('click', function () {
      scheduleHeightSync();
      setTimeout(scheduleHeightSync, 180);
      setTimeout(scheduleHeightSync, 420);
    });

    document.addEventListener('DOMContentLoaded', function () {
      var images = document.querySelectorAll('img');
      for (var i = 0; i < images.length; i++) {
        images[i].addEventListener('load', scheduleHeightSync);
        images[i].addEventListener('error', scheduleHeightSync);
      }
      scheduleHeightSync();
    });

    if (window.ResizeObserver) {
      var observer = new ResizeObserver(function () {
        scheduleHeightSync();
      });
      window.addEventListener('DOMContentLoaded', function () {
        if (document.body) observer.observe(document.body);
      });
    } else {
      setInterval(scheduleHeightSync, 1000);
    }

    if (window.MutationObserver) {
      window.addEventListener('DOMContentLoaded', function () {
        var body = document.body;
        if (!body) return;
        var mutationObserver = new MutationObserver(function () {
          scheduleHeightSync();
        });
        mutationObserver.observe(body, {
          childList: true,
          subtree: true,
          attributes: true,
          characterData: true
        });
      });
    }

    window.__frontendCardForceResize = scheduleHeightSync;
  })();
</script>
''';

    if (hasHtmlTag) {
      if (RegExp(r'<head[\s>]', caseSensitive: false).hasMatch(trimmed)) {
        return _injectAfterFirstMatch(
          trimmed,
          RegExp(r'<head(\s[^>]*)?>', caseSensitive: false),
          '$hostStyle$hostScript',
        );
      }

      return _injectAfterFirstMatch(
        trimmed,
        RegExp(r'<html(\s[^>]*)?>', caseSensitive: false),
        '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">$hostStyle$hostScript</head>',
      );
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  $hostStyle
  $hostScript
</head>
<body>
$trimmed
</body>
</html>
''';
  }

  String _injectAfterFirstMatch(
    String source,
    RegExp pattern,
    String injection,
  ) {
    final match = pattern.firstMatch(source);
    if (match == null) {
      return source;
    }

    final matchedText = match.group(0) ?? '';
    return source.replaceFirst(matchedText, '$matchedText$injection');
  }

  Widget _buildTypingIndicator(ThemeSettings theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: theme.mainTextColor.withOpacity(0.5))
            .animate(onPlay: (c) => c.repeat())
            .fade(duration: 600.ms, begin: 0.2, end: 1.0)
            .scale(delay: 0.ms),
        const SizedBox(width: 4),
        Icon(Icons.circle, size: 8, color: theme.mainTextColor.withOpacity(0.5))
            .animate(onPlay: (c) => c.repeat())
            .fade(duration: 600.ms, begin: 0.2, end: 1.0, delay: 200.ms)
            .scale(delay: 200.ms),
        const SizedBox(width: 4),
        Icon(Icons.circle, size: 8, color: theme.mainTextColor.withOpacity(0.5))
            .animate(onPlay: (c) => c.repeat())
            .fade(duration: 600.ms, begin: 0.2, end: 1.0, delay: 400.ms)
            .scale(delay: 400.ms),
      ],
    );
  }

  Widget _buildMarkdownImage(Uri uri, String? alt) {
    final source = _normalizeImageSource(uri.toString());
    Widget imageWidget;

    if (uri.scheme == 'data') {
      try {
        final bytes = UriData.parse(source).contentAsBytes();
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildImageFallback(source, alt),
        );
      } catch (_) {
        imageWidget = _buildImageFallback(source, alt);
      }
    } else if (uri.scheme == 'file' ||
        source.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source)) {
      final path = uri.scheme == 'file' ? uri.toFilePath() : source;
      imageWidget = Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildImageFallback(source, alt),
      );
    } else {
      imageWidget = _buildNetworkImage(source, alt);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: imageWidget,
        ),
      ),
    );
  }

  Widget _buildNetworkImage(
    String source,
    String? alt, {
    bool retried = false,
  }) {
    return Image.network(
      source,
      fit: BoxFit.contain,
      headers: const {'Accept': 'image/*,*/*;q=0.8'},
      errorBuilder: (_, __, ___) {
        if (!retried) {
          final repaired = _normalizeImageSource(source, aggressive: true);
          if (repaired.isNotEmpty && repaired != source) {
            return _buildNetworkImage(repaired, alt, retried: true);
          }
        }
        return _buildImageFallback(source, alt);
      },
    );
  }

  String _normalizeContentForMarkdown(String raw) {
    var normalized = raw;

    // Convert common image blocks:
    // Image
    // https://...
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'(^|\n)\s*Image\s*\n\s*(https?://\S+)',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) {
        final leading = match.group(1) ?? '';
        final url = _normalizeImageSource(match.group(2)!, aggressive: true);
        return '$leading![Image]($url)';
      },
    );

    // Convert bare image URLs to markdown image syntax.
    normalized = normalized.replaceAllMapped(
      RegExp(
        r'^(https?://\S+)$',
        caseSensitive: false,
        multiLine: true,
      ),
      (match) {
        final url = _normalizeImageSource(match.group(1)!, aggressive: true);
        if (_looksLikeImageUrl(url)) {
          return '![Image]($url)';
        }
        return match.group(0)!;
      },
    );

    return normalized;
  }

  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('image.pollinations.ai')) {
      return true;
    }
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  String _normalizeImageSource(String raw, {bool aggressive = false}) {
    var value = raw.trim();
    value = value.replaceAll('&amp;', '&');
    value = value.replaceAll(r'\(', '(').replaceAll(r'\)', ')');

    if (value.startsWith('<') && value.endsWith('>') && value.length > 2) {
      value = value.substring(1, value.length - 1).trim();
    }

    if (value.startsWith('//')) {
      value = 'https:$value';
    }

    if (aggressive) {
      value = value.replaceAll(RegExp(r'\s+'), '');
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    return value;
  }

  Widget _buildImageFallback(String source, String? alt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        (alt != null && alt.trim().isNotEmpty)
            ? '$alt\n$source'
            : '图片加载失败\n$source',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  Widget _buildDebugInfo(Map<String, dynamic> metadata, int style) {
    switch (style) {
      case 1: // Glass
        return _buildDebugGlass(metadata);
      case 2: // Card
        return _buildDebugCard(metadata);
      case 3: // Cyberpunk
        return _buildDebugCyberpunk(metadata);
      case 0: // Terminal
      default:
        return _buildDebugTerminal(metadata);
    }
  }

  // Style 0: Terminal (Default)
  Widget _buildDebugTerminal(Map<String, dynamic> metadata) {
    final hasThought = metadata['thought'] != null &&
        (metadata['thought'] as String).isNotEmpty;
    return DebugExpandableBlock(
      margin: const EdgeInsets.only(bottom: 12),
      backgroundColor: Colors.black,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
      iconColor: Colors.greenAccent,
      title: const Text('> MODEL_ACT_LOG',
          style: TextStyle(
              fontFamily: 'monospace',
              color: Colors.greenAccent,
              fontSize: 12)),
      children: _buildDebugPanelChildren(
        metadata: metadata,
        accentColor: Colors.greenAccent,
        textColor: Colors.white70,
        mutedColor: Colors.greenAccent.withOpacity(0.85),
        rawTextColor: Colors.white70,
        thoughtBackgroundColor: Colors.greenAccent.withOpacity(0.1),
        hasThought: hasThought,
        monospace: true,
      ),
    );
  }

  // Style 1: Glassmorphism
  Widget _buildDebugGlass(Map<String, dynamic> metadata) {
    final hasThought = metadata['thought'] != null &&
        (metadata['thought'] as String).isNotEmpty;
    return DebugExpandableBlock(
      margin: const EdgeInsets.only(bottom: 12),
      backgroundColor: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.2)),
      iconColor: Colors.white,
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: Colors.white70),
          SizedBox(width: 8),
          Text('Model Insight',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w300)),
        ],
      ),
      children: _buildDebugPanelChildren(
        metadata: metadata,
        accentColor: Colors.white,
        textColor: Colors.white,
        mutedColor: Colors.white70,
        rawTextColor: Colors.white60,
        thoughtBackgroundColor: Colors.black12,
        hasThought: hasThought,
      ),
    );
  }

  // Style 2: Card (Clean)
  Widget _buildDebugCard(Map<String, dynamic> metadata) {
    final hasThought = metadata['thought'] != null &&
        (metadata['thought'] as String).isNotEmpty;
    return DebugExpandableBlock(
      margin: const EdgeInsets.only(bottom: 12),
      backgroundColor: const Color(0xFF2C2C2C),
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2))
      ],
      iconColor: Colors.blueAccent,
      title: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('Generation Metadata',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
      children: _buildDebugPanelChildren(
        metadata: metadata,
        accentColor: Colors.blueAccent,
        textColor: Colors.white70,
        mutedColor: Colors.blueAccent,
        rawTextColor: Colors.grey,
        thoughtBackgroundColor: Colors.black12,
        hasThought: hasThought,
      ),
    );
  }

  // Style 3: Cyberpunk
  Widget _buildDebugCyberpunk(Map<String, dynamic> metadata) {
    final hasThought = metadata['thought'] != null &&
        (metadata['thought'] as String).isNotEmpty;
    return DebugExpandableBlock(
      margin: const EdgeInsets.only(bottom: 12),
      backgroundColor: const Color(0xFF050510),
      border: Border.all(color: Colors.pinkAccent, width: 1),
      boxShadow: [
        BoxShadow(color: Colors.pinkAccent.withOpacity(0.4), blurRadius: 8)
      ],
      iconColor: Colors.pinkAccent,
      title: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('SYSTEM_OVERRIDE // LOGS',
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  letterSpacing: 1.5)),
          Icon(Icons.code, color: Colors.pinkAccent, size: 16),
        ],
      ),
      children: _buildDebugPanelChildren(
        metadata: metadata,
        accentColor: Colors.cyanAccent,
        textColor: Colors.white,
        mutedColor: Colors.pinkAccent,
        rawTextColor: Colors.pinkAccent,
        thoughtBackgroundColor: Colors.cyanAccent.withOpacity(0.05),
        hasThought: hasThought,
        monospace: true,
      ),
    );
  }

  List<Widget> _buildDebugPanelChildren({
    required Map<String, dynamic> metadata,
    required Color accentColor,
    required Color textColor,
    required Color mutedColor,
    required Color rawTextColor,
    required Color thoughtBackgroundColor,
    required bool hasThought,
    bool monospace = false,
  }) {
    final rawMetadata = _buildRawMetadataForDisplay(metadata);
    final promptPreview = _resolvePromptPreview(metadata);

    return [
      if (hasThought)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: thoughtBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thinking',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: monospace ? 'monospace' : null,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                metadata['thought'],
                style: TextStyle(
                  color: textColor,
                  fontSize: 10.5,
                  height: 1.35,
                  fontFamily: monospace ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      _buildPromptPreviewPanel(
        promptPreview,
        metadata,
        accentColor: accentColor,
        textColor: textColor,
        mutedColor: mutedColor,
        monospace: monospace,
      ),
      const SizedBox(height: 12),
      Text(
        'Raw Metadata',
        style: TextStyle(
          color: mutedColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 6),
      SelectableText(
        _prettyJson(rawMetadata),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: rawTextColor,
          height: 1.25,
        ),
      ),
    ];
  }

  Widget _buildPromptPreviewPanel(
    Map<String, dynamic> promptPreview,
    Map<String, dynamic> metadata, {
    required Color accentColor,
    required Color textColor,
    required Color mutedColor,
    bool monospace = false,
  }) {
    final pipeline = metadata['pipeline'] is Map<String, dynamic>
        ? metadata['pipeline'] as Map<String, dynamic>
        : (metadata['pipeline'] is Map
            ? Map<String, dynamic>.from(metadata['pipeline'])
            : <String, dynamic>{});
    final previewMessages = promptPreview['messages'] is List
        ? List<Map<String, dynamic>>.from(
            (promptPreview['messages'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)),
          )
        : const <Map<String, dynamic>>[];
    final activatedWorldInfo = pipeline['worldInfo'] is List
        ? List<Map<String, dynamic>>.from(
            (pipeline['worldInfo'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)),
          )
        : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prompt Preview',
          style: TextStyle(
            color: accentColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildDebugChip(
              'Model',
              metadata['model']?.toString() ?? 'unknown',
              accentColor,
              textColor,
            ),
            _buildDebugChip(
              'Messages',
              '${promptPreview['message_count'] ?? previewMessages.length}',
              accentColor,
              textColor,
            ),
            _buildDebugChip(
              'Est. Tokens',
              '${promptPreview['estimated_tokens'] ?? '-'}',
              accentColor,
              textColor,
            ),
            _buildDebugChip(
              'World Info',
              '${pipeline['worldInfoCount'] ?? 0}',
              accentColor,
              textColor,
            ),
          ],
        ),
        if (activatedWorldInfo.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Activated World Info',
            style: TextStyle(
              color: mutedColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in activatedWorldInfo)
                _buildDebugChip(
                  item['world_info_name']?.toString().trim().isNotEmpty == true
                      ? item['world_info_name'].toString()
                      : (item['comment']?.toString().trim().isNotEmpty == true
                          ? item['comment'].toString()
                          : 'WI ${item['uid'] ?? '?'}'),
                  item['source']?.toString() ?? 'unknown',
                  accentColor,
                  textColor,
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (previewMessages.isEmpty)
          Text(
            'No prompt preview data.',
            style: TextStyle(color: textColor, fontSize: 11),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in previewMessages)
                _buildPromptPreviewMessageCard(
                  item,
                  accentColor: accentColor,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  monospace: monospace,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDebugChip(
    String label,
    String value,
    Color accentColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: accentColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptPreviewMessageCard(
    Map<String, dynamic> item, {
    required Color accentColor,
    required Color textColor,
    required Color mutedColor,
    bool monospace = false,
  }) {
    final blocks = item['blocks'] is List
        ? List<Map<String, dynamic>>.from(
            (item['blocks'] as List)
                .whereType<Map>()
                .map((block) => Map<String, dynamic>.from(block)),
          )
        : const <Map<String, dynamic>>[];
    final role = item['role']?.toString() ?? 'system';
    final sourceLabel = item['source_label']?.toString() ?? 'Prompt';
    final index = item['index']?.toString() ?? '?';
    final tokenText = item['estimated_tokens']?.toString() ?? '-';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#$index',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              _buildRoleBadge(role, accentColor, textColor),
              Text(
                sourceLabel,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$tokenText tok',
                style: TextStyle(
                  color: textColor.withOpacity(0.75),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final block in blocks)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      block['title']?.toString() ?? 'Block',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            item['content']?.toString() ?? '',
            style: TextStyle(
              color: textColor,
              fontSize: 10.5,
              height: 1.35,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role, Color accentColor, Color textColor) {
    final normalized = role.toLowerCase();
    Color badgeColor;
    switch (normalized) {
      case 'user':
        badgeColor = Colors.orangeAccent;
        break;
      case 'assistant':
        badgeColor = Colors.lightBlueAccent;
        break;
      default:
        badgeColor = accentColor;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withOpacity(0.25)),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          color: textColor,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Map<String, dynamic> _buildRawMetadataForDisplay(
      Map<String, dynamic> metadata) {
    final raw = Map<String, dynamic>.from(metadata);
    raw.remove('thought');
    raw.remove('prompt_preview');
    return raw;
  }

  Map<String, dynamic> _resolvePromptPreview(Map<String, dynamic> metadata) {
    final embedded = metadata['prompt_preview'];
    if (embedded is Map) {
      return Map<String, dynamic>.from(embedded);
    }

    final rawPrompt = metadata['prompt'];
    if (rawPrompt is! List) {
      return const {
        'message_count': 0,
        'estimated_tokens': 0,
        'messages': [],
      };
    }

    final messages = <Map<String, dynamic>>[];
    var estimatedTokens = 0;
    for (var i = 0; i < rawPrompt.length; i++) {
      final item = rawPrompt[i];
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final content = map['content']?.toString() ?? '';
      estimatedTokens += (content.length / 2.5).ceil();
      messages.add({
        'index': i + 1,
        'role': map['role']?.toString() ?? 'system',
        'source_key': 'prompt',
        'source_label': 'Prompt Message',
        'content': content,
        'estimated_tokens': (content.length / 2.5).ceil(),
        'blocks': const [],
      });
    }

    return {
      'message_count': messages.length,
      'estimated_tokens': estimatedTokens,
      'messages': messages,
    };
  }

  Widget _buildSwipeControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            if (onSwipe != null) {
              final newIndex = (swipeIndex - 1 + swipeCount) % swipeCount;
              onSwipe!(newIndex);
            }
          },
          child:
              const Icon(Icons.chevron_left, color: Colors.white54, size: 20),
        ),
        Text(
          '${swipeIndex + 1}/$swipeCount',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        InkWell(
          onTap: () {
            if (onSwipe != null) {
              final newIndex = (swipeIndex + 1) % swipeCount;
              onSwipe!(newIndex);
            }
          },
          child:
              const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
        ),
      ],
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1f2937),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.white),
            title: const Text('编辑', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showEditDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh, color: Colors.white),
            title: const Text('重新生成', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              onRegenerate?.call();
            },
          ),
          if (onTts != null)
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.white),
              title:
                  const Text('朗读 (TTS)', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onTts?.call();
              },
            ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('编辑消息', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              onEdit?.call(controller.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> json) {
    var encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }
}

enum _ContentSegmentType { text, card }

enum _FrontendJavaScriptMode { disabled, auto, script, codeBlock }

class _FrontendRenderConfig {
  final bool enabled;
  final _FrontendJavaScriptMode javaScriptMode;

  const _FrontendRenderConfig({
    required this.enabled,
    required this.javaScriptMode,
  });

  factory _FrontendRenderConfig.fromSettings(Map<String, dynamic> settings) {
    final enabled = settings['frontend_advanced_render'] != false &&
        settings['frontend_character_card'] != false;
    final rawMode =
        (settings['frontend_javascript_mode'] as String?)?.toLowerCase() ??
            'auto';

    return _FrontendRenderConfig(
      enabled: enabled,
      javaScriptMode: switch (rawMode) {
        'disabled' => _FrontendJavaScriptMode.disabled,
        'script' => _FrontendJavaScriptMode.script,
        'code_block' => _FrontendJavaScriptMode.codeBlock,
        _ => _FrontendJavaScriptMode.auto,
      },
    );
  }
}

class _ContentSegment {
  final _ContentSegmentType type;
  final String value;
  final bool enableJavaScript;
  final String rawSource;

  const _ContentSegment._(
    this.type,
    this.value, {
    this.enableJavaScript = false,
    this.rawSource = '',
  });

  factory _ContentSegment.text(String value) =>
      _ContentSegment._(_ContentSegmentType.text, value);
  factory _ContentSegment.card(
    String value, {
    bool enableJavaScript = false,
    String rawSource = '',
  }) =>
      _ContentSegment._(
        _ContentSegmentType.card,
        value,
        enableJavaScript: enableJavaScript,
        rawSource: rawSource,
      );
}

class FrontendCardMessageDebugHeader extends StatelessWidget {
  final int totalCards;

  const FrontendCardMessageDebugHeader({super.key, required this.totalCards});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x3322d3ee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, size: 16, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(
            '前端角色卡匹配数量: $totalCards',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class FrontendCardWithDebug extends StatefulWidget {
  final String html;
  final String rawHtml;
  final bool showDebugPanel;
  final int cardIndex;
  final int totalCards;
  final bool enableJavaScript;
  final bool isGenerating;

  const FrontendCardWithDebug({
    super.key,
    required this.html,
    required this.rawHtml,
    required this.showDebugPanel,
    required this.cardIndex,
    required this.totalCards,
    this.enableJavaScript = true,
    this.isGenerating = false,
  });

  @override
  State<FrontendCardWithDebug> createState() => _FrontendCardWithDebugState();
}

class _FrontendCardWithDebugState extends State<FrontendCardWithDebug> {
  List<String> _logs = const [];
  double? _reportedHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FrontendCardWebView(
          html: widget.html,
          enableJavaScript: widget.enableJavaScript,
          isGenerating: widget.isGenerating,
          onHeightChanged: (height) {
            if (!mounted || _reportedHeight == height) {
              return;
            }
            setState(() {
              _reportedHeight = height;
            });
          },
          onDebugLogs: (logs) {
            if (!mounted) {
              return;
            }
            setState(() {
              _logs = logs;
            });
          },
        ),
        if (widget.showDebugPanel)
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: DebugExpandableBlock(
              backgroundColor: const Color(0x33111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.35)),
              iconColor: Colors.orangeAccent,
              title: Text(
                '前端卡调试 ${widget.cardIndex}/${widget.totalCards}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                const Text(
                  '原始 HTML:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'WebView 高度: '
                      '${_reportedHeight == null ? "未知" : "${_reportedHeight!.toStringAsFixed(0)}px"}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.enableJavaScript ? 'JS: 已执行' : 'JS: 被剥离',
                      style: TextStyle(
                        color: widget.enableJavaScript
                            ? Colors.lightGreenAccent
                            : Colors.orangeAccent,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.rawHtml),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制原始 HTML'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Text(
                        '复制',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  widget.rawHtml.isEmpty ? '(empty)' : widget.rawHtml,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '渲染错误日志:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (_logs.isEmpty)
                  const Text(
                    '暂无错误日志',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  )
                else
                  ..._logs.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        line,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class FrontendCardWebView extends StatefulWidget {
  final String html;
  final bool enableJavaScript;
  final bool isGenerating;
  final ValueChanged<List<String>>? onDebugLogs;
  final ValueChanged<double>? onHeightChanged;

  const FrontendCardWebView({
    super.key,
    required this.html,
    this.enableJavaScript = true,
    this.isGenerating = false,
    this.onDebugLogs,
    this.onHeightChanged,
  });

  @override
  State<FrontendCardWebView> createState() => _FrontendCardWebViewState();
}

class _FrontendCardWebViewState extends State<FrontendCardWebView> {
  static const String _baseUrl = 'about:blank';

  late final WebViewController _controller;
  double _height = 260;
  bool _ready = false;
  String? _loadedHtml;
  final List<String> _logs = [];
  Timer? _reloadDebounce;
  final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  void _pushLog(String line) {
    final text = line.trim();
    if (text.isEmpty) {
      return;
    }
    if (_logs.contains(text)) {
      return;
    }
    _logs.add(text);
    widget.onDebugLogs?.call(List<String>.unmodifiable(_logs));
  }

  void _setHeight(double next) {
    final clamped = next.clamp(_minCardHeight, 2400).toDouble();
    if ((clamped - _height).abs() <= 1) {
      return;
    }
    if (mounted) {
      setState(() {
        _height = clamped;
      });
    }
    widget.onHeightChanged?.call(clamped);
  }

  void _load() {
    _loadedHtml = widget.html;
    _controller.loadHtmlString(widget.html, baseUrl: _baseUrl);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlutterCardHeight',
        onMessageReceived: (message) {
          final parsed = double.tryParse(message.message.trim());
          if (parsed == null || parsed <= 0 || !mounted) {
            return;
          }
          _setHeight(parsed);
        },
      )
      ..addJavaScriptChannel(
        'FlutterCardLog',
        onMessageReceived: (message) {
          _pushLog(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url.trim();
            if (url.startsWith('about:blank') ||
                url.startsWith('data:') ||
                url.startsWith('http://') ||
                url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            _pushLog('[blocked_navigation] $url');
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            _pushLog('[web_resource_error] ${error.description}');
          },
          onPageFinished: (_) async {
            setState(() {
              _ready = true;
            });
            await _syncHeight();
            await _syncDebugErrors();
          },
        ),
      );
    _load();
  }

  @override
  void didUpdateWidget(covariant FrontendCardWebView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final htmlChanged = oldWidget.html != widget.html;
    final generationEnded = oldWidget.isGenerating && !widget.isGenerating;
    if (!htmlChanged && !generationEnded) {
      return;
    }
    if (widget.html == _loadedHtml) {
      return;
    }

    // During streaming the html changes on every token; reloading on each one
    // means the document never finishes loading, so the card stays blank until
    // generation stops.
    if (widget.isGenerating) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted && !widget.isGenerating) {
          _applyReload();
        }
      });
      return;
    }

    _reloadDebounce?.cancel();
    _reloadDebounce = null;
    _applyReload();
  }

  void _applyReload() {
    _logs.clear();
    widget.onDebugLogs?.call(const []);
    setState(() {
      _ready = false;
      _height = 260;
    });
    _load();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    super.dispose();
  }

  Future<void> _syncHeight() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
(() => {
  const body = document.body;
  if (!body) return '0';

  const rootTop = body.getBoundingClientRect().top || 0;
  let maxBottom = 0;
  const children = body.children || [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    if (!child) continue;
    const tag = child.tagName || '';
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'LINK') continue;
    const style = window.getComputedStyle(child);
    if (style && (style.position === 'fixed' || style.position === 'sticky')) {
      continue;
    }
    const rect = child.getBoundingClientRect();
    const flowBottom = Math.max(
      0,
      (rect.bottom || 0) - rootTop,
      (child.offsetTop || 0) + (child.offsetHeight || 0),
    );
    maxBottom = Math.max(maxBottom, flowBottom);
  }

  const h = Math.max(
    body ? body.scrollHeight : 0,
    body ? body.offsetHeight : 0,
    maxBottom,
  );
  return String(Math.ceil(h));
})();
''');

      final parsed = double.tryParse(
        raw.toString().replaceAll('"', '').trim(),
      );
      if (parsed != null && parsed > 0) {
        _setHeight(parsed);
      } else {
        _pushLog('[height_parse_failed] raw=$raw');
      }
    } catch (e) {
      _pushLog('[height_eval_error] $e');
    }
  }

  Future<void> _syncDebugErrors() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
(() => {
  try {
    return JSON.stringify(window.__frontendCardDebugErrors || []);
  } catch (e) {
    return JSON.stringify(['collect_error:' + String(e)]);
  }
})();
''');

      final rawText = raw.toString();
      final text = (rawText.startsWith('"') && rawText.endsWith('"'))
          ? (jsonDecode(rawText) as String)
          : rawText;
      final decoded = jsonDecode(text);
      if (decoded is List) {
        for (final item in decoded) {
          _pushLog(item.toString());
        }
      }
    } catch (e) {
      _pushLog('[debug_collect_error] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = math.max(_height, _minCardHeight).toDouble();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      height: minHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          WebViewWidget(
            controller: _controller,
            gestureRecognizers: _gestureRecognizers,
          ),
          if (!_ready)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xAA111827),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final ThemeSettings themeSettings;

  CodeElementBuilder(this.themeSettings);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // If it's a code block (usually detected by newline in text or if it is inside pre),
    // flutter_markdown passes the content.
    // However, inline code `like this` is also passed here.
    // We need to distinguish inline vs block.
    // Standard Markdown parser often uses <pre><code>...</code></pre> for blocks.
    // flutter_markdown calls this for <code>.

    final text = element.textContent;

    // Check if it's multiline or has language class
    // flutter_markdown 0.6.x passes 'class' attribute if available (e.g. language-dart)
    String language = 'plaintext';
    if (element.attributes['class'] != null) {
      final classes = element.attributes['class']!.split(' ');
      for (var c in classes) {
        if (c.startsWith('language-')) {
          language = c.substring(9);
          break;
        }
      }
    }

    // Heuristic: if text contains newline, treat as block
    // Or if language is specified.
    final isBlock = text.contains('\n') || language != 'plaintext';

    if (!isBlock) {
      // Inline code
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            color: Colors.pinkAccent,
            fontSize: 14 * themeSettings.fontSizeScale,
          ),
        ),
      );
    }

    // Block code with highlighting
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF282c34), // Atom One Dark bg
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: HighlightView(
          text,
          language: language,
          theme: atomOneDarkTheme, // Using imported atomOneDarkTheme
          padding: const EdgeInsets.all(12),
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14 * themeSettings.fontSizeScale,
          ),
        ),
      ),
    );
  }
}

class NarrationSyntax extends md.InlineSyntax {
  final String _tag;

  NarrationSyntax(String pattern, this._tag) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text(_tag, match[0]!);
    parser.addNode(element);
    return true;
  }
}

class CustomElementBuilder extends MarkdownElementBuilder {
  final TextStyle textStyle;

  CustomElementBuilder({required this.textStyle});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: textStyle,
      ),
    );
  }
}

class DebugExpandableBlock extends StatefulWidget {
  final Widget title;
  final List<Widget> children;
  final Color iconColor;
  final Color? backgroundColor;
  final BoxBorder? border;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? margin;

  const DebugExpandableBlock({
    super.key,
    required this.title,
    required this.children,
    required this.iconColor,
    this.backgroundColor,
    this.border,
    this.borderRadius,
    this.boxShadow,
    this.margin,
  });

  @override
  State<DebugExpandableBlock> createState() => _DebugExpandableBlockState();
}

class _DebugExpandableBlockState extends State<DebugExpandableBlock>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          border: widget.border,
          borderRadius: widget.borderRadius,
          boxShadow: widget.boxShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Theme(
              data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
              child: ListTile(
                title: widget.title,
                trailing: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: widget.iconColor),
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Body
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: GestureDetector(
                onDoubleTap: () => setState(
                    () => _isExpanded = false), // Double tap to collapse
                child: Container(
                  constraints:
                      const BoxConstraints(maxHeight: 250), // Fixed max height
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: widget.iconColor.withOpacity(0.2),
                            width: 1)),
                  ),
                  child: Scrollbar(
                    // Scroll bar
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.children,
                      ),
                    ),
                  ),
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            )
          ],
        ));
  }
}

final RegExp _htmlDocumentStartPattern = RegExp(
  r'(<!doctype html>|<html\b[^>]*>)',
  caseSensitive: false,
);

final RegExp _htmlFragmentStartPattern = RegExp(
  r'<(?:div|section|article|aside|header|footer|table|svg|canvas|details|form|iframe|style|script)\b',
  caseSensitive: false,
);

const double _minCardHeight = 200;

class _HtmlFragmentCapture {
  final String html;
  final int end;

  const _HtmlFragmentCapture({
    required this.html,
    required this.end,
  });
}
