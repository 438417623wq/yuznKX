import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/frontend_card_shim.dart';

/// 前端卡渲染器：一个 WebView + **变量双向桥**。
///
/// 这是聊天与工坊预览**共用**的实现 —— 两边必须是同一个渲染器，
/// 否则会出现「工坊预览通过、聊天里挂不上」这种最难查的问题。
///
/// 宿主包装（CSS reset + 那套防高度振荡的自测量脚本）在
/// [FrontendCardHost] 里，本类只负责：
/// - 把变量推给页面（`window.__ykx.apply`）
/// - 接住页面写回的变量（`FlutterCardVariable` 通道）
/// - 收集日志、跟随高度
class FrontendCardView extends StatefulWidget {
  const FrontendCardView({
    super.key,
    required this.html,
    this.enableJavaScript = true,
    this.isGenerating = false,
    this.variables = const <String, dynamic>{},
    this.onDebugLogs,
    this.onHeightChanged,
    this.onVariableSet,
    this.onVariableDelete,
    this.minHeight = 200,
    this.maxHeight = 2400,
    this.borderColor,
  });

  /// **已经过 [FrontendCardHost.wrap] 包装**的完整文档。
  final String html;

  final bool enableJavaScript;

  /// 生成中时不要每个 token 都重载文档，否则文档永远加载不完、卡片一直空白。
  final bool isGenerating;

  /// 当前变量快照（平铺键 = MVU 路径）。
  final Map<String, dynamic> variables;

  final ValueChanged<List<String>>? onDebugLogs;
  final ValueChanged<double>? onHeightChanged;

  /// 页面调用 `YKX.setVariable` / `YKX.addVariable` 时回调。
  final void Function(String path, dynamic value)? onVariableSet;

  /// 页面调用 `YKX.deleteVariable` 时回调。
  final void Function(String path)? onVariableDelete;

  final double minHeight;
  final double maxHeight;
  final Color? borderColor;

  @override
  State<FrontendCardView> createState() => _FrontendCardViewState();
}

class _FrontendCardViewState extends State<FrontendCardView> {
  static const String _baseUrl = 'about:blank';

  late final WebViewController _controller;
  double _height = 260;
  bool _ready = false;
  String? _loadedHtml;

  /// 最近一次推给页面的变量 JSON。用来避免把页面自己写回的值再推一遍。
  String _pushedVariables = '';

  final List<String> _logs = [];
  Timer? _reloadDebounce;
  final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  // --- 日志 ---

  void _pushLog(String line) {
    final text = line.trim();
    if (text.isEmpty || _logs.contains(text)) {
      return;
    }
    _logs.add(text);
    widget.onDebugLogs?.call(List<String>.unmodifiable(_logs));
  }

  // --- 高度 ---

  void _setHeight(double next) {
    final clamped = next.clamp(widget.minHeight, widget.maxHeight).toDouble();
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

  // --- 加载 ---

  void _load() {
    _loadedHtml = widget.html;
    _pushedVariables = '';
    _controller.loadHtmlString(widget.html, baseUrl: _baseUrl);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(
        widget.enableJavaScript
            ? JavaScriptMode.unrestricted
            : JavaScriptMode.disabled,
      )
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        FrontendCardBridge.heightChannel,
        onMessageReceived: (message) {
          final parsed = double.tryParse(message.message.trim());
          if (parsed == null || parsed <= 0 || !mounted) {
            return;
          }
          _setHeight(parsed);
        },
      )
      ..addJavaScriptChannel(
        FrontendCardBridge.logChannel,
        onMessageReceived: (message) {
          _pushLog(message.message);
        },
      )
      ..addJavaScriptChannel(
        FrontendCardBridge.variableChannel,
        onMessageReceived: _handleVariableMessage,
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
            await _pushVariables(force: true);
            await _syncHeight();
            await _syncDebugErrors();
          },
        ),
      );
    _load();
  }

  @override
  void didUpdateWidget(covariant FrontendCardView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final htmlChanged = oldWidget.html != widget.html;
    final generationEnded = oldWidget.isGenerating && !widget.isGenerating;

    if (htmlChanged || generationEnded) {
      if (widget.html != _loadedHtml) {
        if (widget.isGenerating) {
          // 生成中：文档每 token 都变，重载会永远加载不完。等停下来再重载。
          _reloadDebounce?.cancel();
          _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !widget.isGenerating) {
              _applyReload();
            }
          });
        } else {
          _reloadDebounce?.cancel();
          _reloadDebounce = null;
          _applyReload();
          return;
        }
      }
    }

    if (!_ready || !widget.enableJavaScript) {
      return;
    }
    if (!_sameVariables(oldWidget.variables, widget.variables)) {
      unawaited(_pushVariables());
    }
  }

  static bool _sameVariables(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) {
        return false;
      }
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
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

  // --- 变量桥 ---

  void _handleVariableMessage(JavaScriptMessage message) {
    final raw = message.message.trim();
    if (raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final op = decoded['op']?.toString() ?? 'set';
      final path = decoded['path']?.toString() ?? '';
      if (path.isEmpty) {
        return;
      }
      if (op == 'delete') {
        widget.onVariableDelete?.call(path);
        return;
      }
      widget.onVariableSet?.call(path, decoded['value']);
    } catch (error) {
      _pushLog('[variable_message_error] $error');
    }
  }

  /// 把变量推给页面。页面里的 `window.__ykx.apply` 会触发监听器重绘。
  Future<void> _pushVariables({bool force = false}) async {
    if (!widget.enableJavaScript) {
      return;
    }
    final encoded = jsonEncode(widget.variables);
    if (!force && encoded == _pushedVariables) {
      return;
    }
    _pushedVariables = encoded;
    try {
      await _controller.runJavaScript(
        'window.__ykx && window.__ykx.apply($encoded, "sync");',
      );
    } catch (error) {
      _pushLog('[variable_push_error] $error');
    }
  }

  // --- 高度 / 日志同步 ---

  /// 让页面自己量一次。测量逻辑在页面脚本里，这样每次上报都走同一套守卫；
  /// 从 Dart 侧直接算高度会绕过守卫，可能把一个视口比例高度强加上去，
  /// 反而重新触发它刚刚停下的收缩。
  Future<void> _syncHeight() async {
    try {
      await _controller.runJavaScript('''
(() => {
  if (typeof window.__frontendCardForceResize === 'function') {
    window.__frontendCardForceResize();
  }
})();
''');
    } catch (error) {
      _pushLog('[height_eval_error] $error');
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
    } catch (error) {
      _pushLog('[debug_collect_error] $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = math.max(_height, widget.minHeight).toDouble();
    // 这里不加隐式动画：卡片自己可能有 CSS transition，叠加起来会在每次切页时
    // 读成一次缓慢的缩放。高度是页面自己报上来的，说明它已经稳定了。
    return Container(
      width: double.infinity,
      height: minHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.borderColor ?? Colors.white24),
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
