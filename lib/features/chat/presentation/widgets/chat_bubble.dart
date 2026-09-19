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
import 'dart:convert';
import 'dart:io';
import '../../../settings/data/theme_provider.dart';
import '../../../settings/domain/plugin_settings_provider.dart';
import '../../../character/data/character_provider.dart';
import '../../../variables/data/variable_provider.dart';
import '../../../frontend_card/data/frontend_card_host.dart';
import '../../../frontend_card/data/frontend_card_shim.dart';
import '../../../frontend_card/domain/frontend_card_payload.dart';
import '../../../frontend_card/presentation/frontend_card_view.dart';
import '../../data/session_provider.dart';

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
  /// 是否渲染顶部头像。外观预览等紧凑场景可置 false，避免出现占位网络图。
  final bool showAvatar;

  /// 是不是**最后一条助手消息**。
  ///
  /// 前端卡的挂载点每轮都会出现在消息里，但**只有最新一条才真正渲染面板** ——
  /// 否则 50 轮对话就是 50 个活着的 WebView，安卓上直接吃光内存。
  final bool isLatestAssistant;

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
    this.showAvatar = true,
    this.isLatestAssistant = true,
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
          if (showAvatar) ...[
            CircleAvatar(
              backgroundImage: (avatarPath != null && avatarPath!.isNotEmpty)
                  ? FileImage(File(avatarPath!)) as ImageProvider
                  : const NetworkImage('https://via.placeholder.com/150'),
              radius: 25 * themeSettings.fontSizeScale,
            ),
            const SizedBox(height: 8),
          ],

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
                // 气泡背景色：用户 / AI 各自的「气泡颜色」设置。
                // （此前误用了「消息模糊色调」，导致气泡颜色设置完全不生效。）
                color: isUser
                    ? themeSettings.userBubbleColor
                    : themeSettings.aiBubbleColor,
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
                      _buildMountContext(ref),
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
      bool isGenerating, bool showCardDebug, _FrontendMountContext mount) {
    // 挂载点可以来自消息内容（正则把模型输出的标记换成了挂载点），
    // 也可以完全不存在 —— 那就兜底渲染在消息末尾。
    //
    // 为什么要兜底：模型不一定每轮都记得吐那个标记，预设也可能把
    // Author's Note 槽位关掉。要是只认显式挂载点，「卡上有面板但聊天里
    // 什么都没有」就会变成一个查不出原因的问题。
    final hasExplicitMount =
        segments.any((s) => s.type == _ContentSegmentType.frontendMount);

    if (segments.length == 1 &&
        segments.first.type == _ContentSegmentType.text &&
        !mount.enabled) {
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

    final cardCount =
        segments.where((s) => s.type == _ContentSegmentType.card).length;

    // 一条消息里只渲染**第一个**挂载点。模型偶尔会把标记吐两遍，
    // 那就成了两个活 WebView —— 白白吃一份内存。
    final firstMountIndex = segments.indexWhere(
      (segment) => segment.type == _ContentSegmentType.frontendMount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in segments.asMap().entries)
          if (entry.value.type == _ContentSegmentType.frontendMount)
            entry.key == firstMountIndex
                ? _buildFrontendMount(mount, isGenerating, showCardDebug)
                : const SizedBox.shrink()
          else if (entry.value.type == _ContentSegmentType.card)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FrontendCardWithDebug(
                html: entry.value.value,
                rawHtml: entry.value.rawSource,
                enableJavaScript: entry.value.enableJavaScript,
                isGenerating: isGenerating,
                showDebugPanel: showCardDebug,
                cardIndex: entry.key + 1,
                totalCards: cardCount,
                variables: mount.variables,
                onVariableSet: mount.onVariableSet,
                onVariableDelete: mount.onVariableDelete,
              ),
            )
          else if (entry.value.value.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _buildMarkdownBlock(
                  entry.value.value, syntaxes, themeSettings),
            ),
        if (!hasExplicitMount && mount.enabled)
          _buildFrontendMount(mount, isGenerating, showCardDebug),
      ],
    );
  }

  /// 渲染前端卡挂载点。
  ///
  /// **只有最新一条助手消息才真正渲染面板**；历史消息上什么都不画。
  /// 挂载点每轮都会出现在消息里（那是正则加的），但一个会话只该有一个
  /// 活着的 WebView —— 50 轮对话就是 50 个 WebView 的话，安卓直接吃光内存。
  Widget _buildFrontendMount(
    _FrontendMountContext mount,
    bool isGenerating,
    bool showCardDebug,
  ) {
    if (!mount.enabled || mount.document.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FrontendCardWithDebug(
        html: mount.document,
        rawHtml: mount.rawHtml,
        isGenerating: isGenerating,
        showDebugPanel: showCardDebug,
        cardIndex: 1,
        totalCards: 1,
        variables: mount.variables,
        onVariableSet: mount.onVariableSet,
        onVariableDelete: mount.onVariableDelete,
      ),
    );
  }

  /// 组装挂载点渲染所需的全部输入（角色卡上的前端产物 + 会话变量 + 写回回调）。
  ///
  /// 不是最新一条助手消息、或这张卡根本没有前端产物时，返回一个空上下文，
  /// 挂载点就渲染成零尺寸。
  _FrontendMountContext _buildMountContext(WidgetRef ref) {
    if (!isLatestAssistant || isUser) {
      return const _FrontendMountContext();
    }

    final character = ref.watch(activeCharacterProvider);
    final rawHtml = FrontendCardPayload.htmlOf(character?.rawExtensions);
    if (rawHtml.trim().isEmpty) {
      return const _FrontendMountContext();
    }

    final document = FrontendCardDocumentCache.of(rawHtml);
    final sessionId = ref.watch(activeSessionIdProvider);
    if (sessionId == null) {
      return _FrontendMountContext(
        enabled: true,
        document: document,
        rawHtml: rawHtml,
      );
    }

    final variables = ref.watch(chatVariablesProvider(sessionId));
    final notifier = ref.read(chatVariablesProvider(sessionId).notifier);
    return _FrontendMountContext(
      enabled: true,
      document: document,
      rawHtml: rawHtml,
      variables: variables,
      onVariableSet: notifier.setValue,
      onVariableDelete: notifier.deleteValue,
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

      // 模型把挂载标记裹进代码块的情形（提示词里说了别这么干，但模型不一定听）。
      // 那只是个标记、不是一张卡 —— 直接当挂载点，否则会渲染出一张什么都看不到
      // 的空 WebView。
      if (htmlContent.trim().isNotEmpty &&
          htmlContent.replaceAll(_frontendMountPattern, '').trim().isEmpty) {
        segments.add(_ContentSegment.frontendMount());
        cursor = match.end;
        continue;
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
    // 变量垫片只在 JS 真的会执行时注入 —— 用户明确关掉 JS 时还往里塞 script
    // 是反直觉的。
    return FrontendCardHost.wrap(
      payload,
      extraScript: enableJavaScript ? FrontendCardBridge.shim : '',
    );
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
      if (segment.type == _ContentSegmentType.frontendMount) {
        // 挂载点的 value 是空串，若不先拦下来会被下面的空白合并分支吃掉。
        if (pendingWhitespace.isNotEmpty) {
          merged.add(_ContentSegment.text(pendingWhitespace));
          pendingWhitespace = '';
        }
        merged.add(segment);
        continue;
      }

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
      final mountMatch = _firstMatchFrom(_frontendMountPattern, raw, cursor);
      final documentMatch =
          _firstMatchFrom(_htmlDocumentStartPattern, raw, cursor);
      final fragmentMatch =
          _firstMatchFrom(_htmlFragmentStartPattern, raw, cursor);

      // 挂载点最先判定：它本身长得就像个 HTML 片段，落到下面的通用分支
      // 就会被渲染成一张空卡（多一个 WebView 且什么都看不到）。
      if (mountMatch != null &&
          (documentMatch == null || mountMatch.start <= documentMatch.start) &&
          (fragmentMatch == null || mountMatch.start <= fragmentMatch.start)) {
        if (mountMatch.start > cursor) {
          segments.add(
            _ContentSegment.text(raw.substring(cursor, mountMatch.start)),
          );
        }
        segments.add(_ContentSegment.frontendMount());
        cursor = mountMatch.end;
        continue;
      }

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
    final memoryInfo = pipeline['memory'] is Map
        ? Map<String, dynamic>.from(pipeline['memory'] as Map)
        : <String, dynamic>{};

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
            if (memoryInfo.isNotEmpty)
              _buildDebugChip(
                'Memory',
                memoryInfo['injected'] == true
                    ? '${memoryInfo['injectedTableCount'] ?? 0} 表'
                        '${memoryInfo['fallbackUsed'] == true ? ' · 兜底' : ''}'
                    : '未注入',
                memoryInfo['injected'] == true
                    ? accentColor
                    : const Color(0xFFFF8A8A),
                textColor,
              ),
          ],
        ),
        if (memoryInfo.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Memory Injection',
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
              _buildDebugChip(
                '启用',
                '${memoryInfo['enabled'] == true ? '是' : '否'}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '读取',
                '${memoryInfo['readEnabled'] == true ? '开' : '关'}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '回写',
                '${memoryInfo['writeEnabled'] == true ? '开' : '关'}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '参与表',
                '${memoryInfo['injectedTableCount'] ?? 0}/'
                    '${memoryInfo['totalTableCount'] ?? 0}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '记录',
                '${memoryInfo['rowCount'] ?? 0}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '字符',
                '${memoryInfo['injectedChars'] ?? 0}',
                accentColor,
                textColor,
              ),
              _buildDebugChip(
                '路径',
                memoryInfo['fallbackUsed'] == true
                    ? '兜底（深度 ${memoryInfo['fallbackDepth'] ?? '-'}）'
                    : (memoryInfo['usedSlot'] == true
                        ? 'vectorsMemory 槽位'
                        : '未进入 prompt'),
                accentColor,
                textColor,
              ),
            ],
          ),
        ],
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

enum _ContentSegmentType { text, card, frontendMount }

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

  /// 前端卡挂载点。本身不带内容 —— 要渲染什么，由 [_FrontendMountContext] 决定。
  factory _ContentSegment.frontendMount() =>
      const _ContentSegment._(_ContentSegmentType.frontendMount, '');
}

/// 渲染前端卡挂载点所需的全部输入。
///
/// 默认构造是「空上下文」：不是最新一条助手消息、或这张卡压根没有前端产物时
/// 用它，挂载点就渲染成零尺寸。这样调用点不需要到处写 `if`。
class _FrontendMountContext {
  /// 是否可以渲染。false 时挂载点不占任何空间。
  final bool enabled;

  /// 已经过 [FrontendCardHost.wrap] 包装的完整文档（含变量垫片）。
  final String document;

  /// 未包装的原始 HTML，供调试面板展示。
  final String rawHtml;

  /// 当前会话变量快照（平铺键 = MVU 路径）。
  final Map<String, dynamic> variables;

  /// 页面通过 `YKX.setVariable` / `YKX.addVariable` 写回时调用。
  final void Function(String path, dynamic value)? onVariableSet;

  /// 页面通过 `YKX.deleteVariable` 时调用。
  final void Function(String path)? onVariableDelete;

  const _FrontendMountContext({
    this.enabled = false,
    this.document = '',
    this.rawHtml = '',
    this.variables = const <String, dynamic>{},
    this.onVariableSet,
    this.onVariableDelete,
  });
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

  /// 会话变量快照，透传给 [FrontendCardView] 的变量桥。
  final Map<String, dynamic> variables;
  final void Function(String path, dynamic value)? onVariableSet;
  final void Function(String path)? onVariableDelete;

  const FrontendCardWithDebug({
    super.key,
    required this.html,
    required this.rawHtml,
    required this.showDebugPanel,
    required this.cardIndex,
    required this.totalCards,
    this.enableJavaScript = true,
    this.isGenerating = false,
    this.variables = const <String, dynamic>{},
    this.onVariableSet,
    this.onVariableDelete,
  });

  @override
  State<FrontendCardWithDebug> createState() => _FrontendCardWithDebugState();
}

class _FrontendCardWithDebugState extends State<FrontendCardWithDebug> {
  static const int _maxHeightHistory = 12;

  List<String> _logs = const [];
  double? _reportedHeight;
  final List<double> _heightHistory = [];

  void _recordHeight(double height) {
    if (!mounted) {
      return;
    }
    if (_reportedHeight == height) {
      return;
    }
    setState(() {
      _reportedHeight = height;
      _heightHistory.add(height);
      if (_heightHistory.length > _maxHeightHistory) {
        _heightHistory.removeRange(0, _heightHistory.length - _maxHeightHistory);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FrontendCardView(
          html: widget.html,
          enableJavaScript: widget.enableJavaScript,
          isGenerating: widget.isGenerating,
          variables: widget.variables,
          onVariableSet: widget.onVariableSet,
          onVariableDelete: widget.onVariableDelete,
          onHeightChanged: _recordHeight,
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
                if (_heightHistory.length > 1) ...[
                  Text(
                    '高度变化: ${_heightHistory.map((h) => h.toStringAsFixed(0)).join(' → ')}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
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

/// 围栏语言名 → `highlighter` 包语言表的**规范键**。
///
/// ⛔ 别删这张表。`highlighter` 0.1.1 的注册表（`languages/all.dart`）用的是
/// highlight.js 的规范名，**不含常见缩写**——`'html'` 和 `'js'` 都不在里面。
/// 而 `_getLanguage(lang) ?? plaintext`（`src/highlight.dart:271`）查不到时
/// **不报错、直接降级成纯文本**，所以 ```html / ```js 会静默失去高亮。
/// 这里只映射到已确认存在的键；映射目标不存在时仍退回 plaintext，不会更糟。
const Map<String, String> _languageAliases = {
  // HTML 家族：注册表里没有 'html'，走 highlight.js 的 xml 定义
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'svg': 'xml',
  'rss': 'xml',
  'atom': 'xml',
  // JS 家族：注册表只有 'javascript'，没有 'js'
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'node': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  // 其它高频缩写
  'py': 'python',
  'python3': 'python',
  'sh': 'bash',
  'zsh': 'bash',
  'console': 'bash',
  'yml': 'yaml',
  'md': 'markdown',
  'rs': 'rust',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'rb': 'ruby',
  'golang': 'go',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'jsonc': 'json',
  'json5': 'json',
  'text': 'plaintext',
  'txt': 'plaintext',
};

String _normalizeLanguage(String raw) {
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) {
    return 'plaintext';
  }
  return _languageAliases[key] ?? key;
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
    // 围栏里写的是缩写（```html / ```js），注册表只认规范名，先归一化。
    // 块/行内判定仍用原始写法，避免归一化顺带改变既有渲染行为。
    final rawLanguage = language;
    language = _normalizeLanguage(language);

    // Heuristic: if text contains newline, treat as block
    // Or if language is specified.
    final isBlock = text.contains('\n') || rawLanguage != 'plaintext';

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

/// 前端卡挂载点。
///
/// 匹配正则替换进来的 `<div ... data-ykx-panel="1"></div>`，也兼容裸标记
/// `<!--YKX_PANEL-->`（模型直接吐标记、卡上正则没启用的情形）。
///
/// **必须优先于 [_htmlFragmentStartPattern] 判定** —— 否则挂载点会被
/// `_looksLikeHtmlFragment` 当成一张内联卡渲染，白白多出一个 WebView，
/// 而且那个 WebView 里是空的 div，什么都看不到。
final RegExp _frontendMountPattern = RegExp(
  "<div\\b[^>]*data-ykx-panel\\s*=\\s*[\"']1[\"'][^>]*>\\s*</div>"
  "|<!--\\s*YKX_PANEL\\s*-->",
  caseSensitive: false,
);

class _HtmlFragmentCapture {
  final String html;
  final int end;

  const _HtmlFragmentCapture({
    required this.html,
    required this.end,
  });
}
