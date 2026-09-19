/// 前端卡与宿主之间的约定（通道名、挂载点、变量垫片）。
///
/// **设计原则**：前端产物只有一份，跟着角色卡走，不进消息、不烧 token。
/// 消息里只留一个几十字节的挂载点，渲染时再从卡上取前端产物。
/// 这样历史消息不会各存一份 5KB 的 HTML 副本。
class FrontendCardBridge {
  const FrontendCardBridge._();

  /// 页面 → 宿主：卡片改变量。
  static const String variableChannel = 'FlutterCardVariable';

  /// 页面 → 宿主：页面自报高度（宿主包装脚本在用，这里只做常量集中）。
  static const String heightChannel = 'FlutterCardHeight';

  /// 页面 → 宿主：调试日志（宿主包装脚本在用）。
  static const String logChannel = 'FlutterCardLog';

  /// 模型每轮要输出的标记。成本约 1 个 token。
  static const String mountMarker = '<!--YKX_PANEL-->';

  /// 正则把标记替换成的挂载点（几十字节）。
  ///
  /// `data-ykx-panel="1"` 是渲染侧的识别依据 —— 认这个属性，不认 class，
  /// 因为 class 可能被卡自己的 CSS 覆盖。
  static const String mountHtml =
      '<div class="ykx-frontend-root" data-ykx-panel="1"></div>';

  /// 判断一段 HTML 片段是不是前端卡挂载点。
  static bool isMountHtml(String html) {
    final lower = html.toLowerCase();
    return lower.contains('data-ykx-panel="1"') ||
        lower.contains("data-ykx-panel='1'");
  }

  /// 注入到 `<head>` 的变量垫片。
  ///
  /// 卡片可以用 `window.YKX` 读写变量：
  /// ```js
  /// const v = YKX.getVariable('角色.好感度');
  /// YKX.setVariable('角色.好感度', v + 5);
  /// YKX.onVariablesChanged(() => render());
  /// ```
  ///
  /// 用平铺键：MVU 的路径字符串本身就是键名（`角色.好感度`），
  /// 这样 Dart ↔ JS 之间不需要做结构转换。取值时若平铺键不存在，
  /// 再退回按 `.` 逐层下钻，兼容卡片自己塞的嵌套对象。
  static const String shim = r'''
<script>
(function () {
  if (window.YKX) { return; }

  var state = { vars: {}, listeners: [] };
  window.__ykx = state;

  function log(message) {
    try {
      var text = String(message);
      if (window.__frontendCardDebugErrors) {
        window.__frontendCardDebugErrors.push(text);
      }
      if (window.FlutterCardLog && window.FlutterCardLog.postMessage) {
        window.FlutterCardLog.postMessage(text);
      }
    } catch (_) {}
  }

  function post(payload) {
    try {
      if (window.FlutterCardVariable && window.FlutterCardVariable.postMessage) {
        window.FlutterCardVariable.postMessage(JSON.stringify(payload));
      }
    } catch (e) {
      log('[ykx_post_error] ' + String(e));
    }
  }

  function readPath(vars, path) {
    if (!vars || !path) { return undefined; }
    if (Object.prototype.hasOwnProperty.call(vars, path)) { return vars[path]; }
    var parts = String(path).split('.');
    var node = vars;
    for (var i = 0; i < parts.length; i++) {
      if (node === null || node === undefined) { return undefined; }
      if (typeof node !== 'object') { return undefined; }
      node = node[parts[i]];
    }
    return node;
  }

  function notify(reason) {
    var list = state.listeners.slice();
    for (var i = 0; i < list.length; i++) {
      try {
        list[i](state.vars, reason);
      } catch (e) {
        log('[ykx_listener_error] ' + String(e));
      }
    }
  }

  // 宿主把最新变量推下来时调用。
  state.apply = function (next, reason) {
    state.vars = (next && typeof next === 'object') ? next : {};
    window.YKX.variables = state.vars;
    notify(reason || 'sync');
  };

  function commit(path, value) {
    state.vars[path] = value;
    notify('local');
    post({ op: 'set', path: path, value: value });
  }

  window.YKX = {
    version: '1.0',
    variables: state.vars,

    log: log,
    getAll: function () { return state.vars; },
    getVariables: function () { return state.vars; },
    getVariable: function (path) { return readPath(state.vars, path); },

    setVariable: function (path, value) {
      // 值没变就不上报 —— 否则「宿主回推 → 监听器重绘 → 又写回」会成环。
      if (readPath(state.vars, path) === value) { return value; }
      commit(path, value);
      return value;
    },

    addVariable: function (path, delta) {
      var current = readPath(state.vars, path);
      var base = (typeof current === 'number')
        ? current
        : (parseFloat(current) || 0);
      var step = (typeof delta === 'number')
        ? delta
        : (parseFloat(delta) || 0);
      var next = base + step;
      commit(path, next);
      return next;
    },

    deleteVariable: function (path) {
      if (Object.prototype.hasOwnProperty.call(state.vars, path)) {
        delete state.vars[path];
        notify('local');
        post({ op: 'delete', path: path });
      }
    },

    onVariablesChanged: function (callback) {
      if (typeof callback !== 'function') { return function () {}; }
      state.listeners.push(callback);
      return function () {
        var i = state.listeners.indexOf(callback);
        if (i >= 0) { state.listeners.splice(i, 1); }
      };
    },

    ready: function (callback) {
      if (typeof callback === 'function') {
        try {
          callback(window.YKX);
        } catch (e) {
          log('[ykx_ready_error] ' + String(e));
        }
      }
    }
  };

  log('[ykx] bridge ready');
})();
</script>
''';
}
