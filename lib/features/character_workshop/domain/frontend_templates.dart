/// 工坊内置的前端面板模板。
///
/// **契约**：每个模板都是一段**自包含**的 HTML + CSS + JS，只依赖宿主注入的
/// `window.YKX` 变量垫片（见 `frontend_card_shim.dart`）。不依赖 Vue / React /
/// 任何 CDN —— 聊天里的 WebView 是 `loadHtmlString` 加载的，没有网络、
/// 也没有模块系统，引外部库只会白屏。
///
/// 模板只是**起点**：用户可以在工坊里直接改 HTML。所以模板写得尽量可读、
/// 变量名用中文路径，改起来不用查文档。
library;

class FrontendTemplate {
  const FrontendTemplate({
    required this.key,
    required this.label,
    required this.description,
    required this.html,
    required this.variables,
  });

  /// 持久化标识（只作记录，便于「换个模板」）。
  final String key;

  final String label;
  final String description;

  /// 自包含的 HTML + CSS + JS。
  final String html;

  /// 模板用到的变量路径 → 建议初始值。用来预填预览变量调试器。
  final Map<String, dynamic> variables;

  static const List<FrontendTemplate> builtIn = <FrontendTemplate>[
    _statusBar,
    _attributePanel,
    _relationPanel,
  ];

  static FrontendTemplate? byKey(String? key) {
    for (final template in builtIn) {
      if (template.key == key) {
        return template;
      }
    }
    return null;
  }
}

const FrontendTemplate _statusBar = FrontendTemplate(
  key: 'status_bar',
  label: '状态条',
  description: '生命 / 魔力 / 好感度三条进度条，带加减按钮',
  variables: <String, dynamic>{
    '角色.生命值': 82,
    '角色.魔力值': 45,
    '角色.好感度': 30,
  },
  html: r'''
<div class="ykx-panel">
  <div class="ykx-head">
    <span class="ykx-title">状态</span>
    <span class="ykx-note">点击 ± 修改，数值会同步进变量</span>
  </div>

  <div class="ykx-row" data-key="角色.生命值" data-max="100" data-color="#ff6b6b">
    <span class="ykx-name">生命</span>
    <div class="ykx-bar"><i></i></div>
    <span class="ykx-val">--</span>
    <button class="ykx-btn" data-step="-5">-</button>
    <button class="ykx-btn" data-step="5">+</button>
  </div>

  <div class="ykx-row" data-key="角色.魔力值" data-max="100" data-color="#5aa9ff">
    <span class="ykx-name">魔力</span>
    <div class="ykx-bar"><i></i></div>
    <span class="ykx-val">--</span>
    <button class="ykx-btn" data-step="-5">-</button>
    <button class="ykx-btn" data-step="5">+</button>
  </div>

  <div class="ykx-row" data-key="角色.好感度" data-max="100" data-color="#3ddc97">
    <span class="ykx-name">好感</span>
    <div class="ykx-bar"><i></i></div>
    <span class="ykx-val">--</span>
    <button class="ykx-btn" data-step="-5">-</button>
    <button class="ykx-btn" data-step="5">+</button>
  </div>
</div>

<style>
  .ykx-panel {
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    background: #0f1720;
    color: #e6f1f5;
    border: 1px solid #22323f;
    border-radius: 12px;
    padding: 12px 14px;
    box-sizing: border-box;
  }
  .ykx-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 10px;
  }
  .ykx-title { font-size: 15px; font-weight: 600; letter-spacing: 1px; }
  .ykx-note { font-size: 11px; color: #7f93a6; }
  .ykx-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 0;
  }
  .ykx-name { width: 36px; font-size: 12px; color: #9fbcd1; flex: none; }
  .ykx-bar {
    flex: 1 1 auto;
    height: 8px;
    min-width: 60px;
    background: #1c2a36;
    border-radius: 999px;
    overflow: hidden;
  }
  .ykx-bar > i {
    display: block;
    height: 100%;
    width: 0;
    border-radius: 999px;
    background: #3ddc97;
    transition: width .25s ease;
  }
  .ykx-val {
    width: 34px;
    text-align: right;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    flex: none;
  }
  .ykx-btn {
    flex: none;
    width: 24px;
    height: 24px;
    line-height: 1;
    border-radius: 6px;
    border: 1px solid #2c3f4d;
    background: #16242c;
    color: #cfe3ee;
    font-size: 14px;
    cursor: pointer;
  }
  .ykx-btn:active { background: #22323f; }
</style>

<script>
(function () {
  var rows = document.querySelectorAll('.ykx-row');

  function render() {
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var key = row.getAttribute('data-key');
      var max = Number(row.getAttribute('data-max')) || 100;
      var color = row.getAttribute('data-color');

      var raw = window.YKX ? YKX.getVariable(key) : undefined;
      var value = Number(raw);
      if (!isFinite(value)) { value = 0; }

      var ratio = value / max;
      if (ratio < 0) { ratio = 0; }
      if (ratio > 1) { ratio = 1; }

      row.querySelector('.ykx-bar > i').style.width = (ratio * 100) + '%';
      row.querySelector('.ykx-bar > i').style.background = color;
      row.querySelector('.ykx-val').textContent = value;
    }
  }

  function step(event) {
    var button = event.target;
    var row = button.parentNode;
    var key = row.getAttribute('data-key');
    var delta = Number(button.getAttribute('data-step')) || 0;
    YKX.addVariable(key, delta);
    render();
  }

  for (var i = 0; i < rows.length; i++) {
    var buttons = rows[i].querySelectorAll('.ykx-btn');
    for (var j = 0; j < buttons.length; j++) {
      buttons[j].addEventListener('click', step);
    }
  }

  YKX.onVariablesChanged(render);
  render();
})();
</script>
''',
);

const FrontendTemplate _attributePanel = FrontendTemplate(
  key: 'attribute_panel',
  label: '属性面板',
  description: '数值属性表格，每项可手动改写',
  variables: <String, dynamic>{
    '属性.力量': 12,
    '属性.敏捷': 9,
    '属性.智力': 14,
    '属性.魅力': 11,
  },
  html: r'''
<div class="ykx-panel">
  <div class="ykx-head">
    <span class="ykx-title">属性</span>
    <span class="ykx-note">直接输入数字后回车</span>
  </div>
  <table class="ykx-table">
    <tbody>
      <tr data-key="属性.力量"><th>力量</th><td><input type="number" /></td></tr>
      <tr data-key="属性.敏捷"><th>敏捷</th><td><input type="number" /></td></tr>
      <tr data-key="属性.智力"><th>智力</th><td><input type="number" /></td></tr>
      <tr data-key="属性.魅力"><th>魅力</th><td><input type="number" /></td></tr>
    </tbody>
  </table>
</div>

<style>
  .ykx-panel {
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    background: #0f1720;
    color: #e6f1f5;
    border: 1px solid #22323f;
    border-radius: 12px;
    padding: 12px 14px;
    box-sizing: border-box;
  }
  .ykx-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 8px;
  }
  .ykx-title { font-size: 15px; font-weight: 600; letter-spacing: 1px; }
  .ykx-note { font-size: 11px; color: #7f93a6; }
  .ykx-table { width: 100%; border-collapse: collapse; }
  .ykx-table th {
    text-align: left;
    font-size: 12px;
    font-weight: 400;
    color: #9fbcd1;
    padding: 5px 0;
  }
  .ykx-table td { text-align: right; padding: 3px 0; }
  .ykx-table tr + tr th { border-top: 1px solid #1b2833; }
  .ykx-table input {
    width: 68px;
    padding: 3px 8px;
    text-align: right;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: #e6f1f5;
    background: #16242c;
    border: 1px solid #2c3f4d;
    border-radius: 6px;
    outline: none;
  }
  .ykx-table input:focus { border-color: #3ddc97; }
</style>

<script>
(function () {
  var rows = document.querySelectorAll('.ykx-table tr');

  function render() {
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var input = row.querySelector('input');
      if (document.activeElement === input) { continue; }
      var raw = window.YKX ? YKX.getVariable(row.getAttribute('data-key')) : undefined;
      var value = Number(raw);
      input.value = isFinite(value) ? value : 0;
    }
  }

  function commit(event) {
    var input = event.target;
    var key = input.parentNode.parentNode.getAttribute('data-key');
    var value = Number(input.value);
    if (!isFinite(value)) { value = 0; }
    YKX.setVariable(key, value);
    render();
  }

  for (var i = 0; i < rows.length; i++) {
    rows[i].querySelector('input').addEventListener('change', commit);
  }

  YKX.onVariablesChanged(render);
  render();
})();
</script>
''',
);

const FrontendTemplate _relationPanel = FrontendTemplate(
  key: 'relation_panel',
  label: '关系图',
  description: '若干角色的好感度横条，带阶段标签',
  variables: <String, dynamic>{
    '关系.林昭.好感度': 62,
    '关系.苏晚.好感度': 24,
    '关系.陆沉.好感度': 88,
  },
  html: r'''
<div class="ykx-panel">
  <div class="ykx-head">
    <span class="ykx-title">关系</span>
    <span class="ykx-note">0-100</span>
  </div>
  <div class="ykx-list" id="ykx-list"></div>
</div>

<style>
  .ykx-panel {
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    background: #0f1720;
    color: #e6f1f5;
    border: 1px solid #22323f;
    border-radius: 12px;
    padding: 12px 14px;
    box-sizing: border-box;
  }
  .ykx-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 8px;
  }
  .ykx-title { font-size: 15px; font-weight: 600; letter-spacing: 1px; }
  .ykx-note { font-size: 11px; color: #7f93a6; }
  .ykx-item { padding: 6px 0; }
  .ykx-item + .ykx-item { border-top: 1px solid #1b2833; }
  .ykx-line {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
  }
  .ykx-name { flex: 1 1 auto; color: #cfe3ee; }
  .ykx-tag {
    flex: none;
    font-size: 11px;
    padding: 1px 7px;
    border-radius: 999px;
    background: #16242c;
    color: #8aa0b0;
    border: 1px solid #2c3f4d;
  }
  .ykx-val {
    flex: none;
    width: 30px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .ykx-track {
    height: 6px;
    margin-top: 5px;
    background: #1c2a36;
    border-radius: 999px;
    overflow: hidden;
  }
  .ykx-track > i {
    display: block;
    height: 100%;
    width: 0;
    background: #3ddc97;
    border-radius: 999px;
    transition: width .25s ease;
  }
</style>

<script>
(function () {
  var prefix = '关系.';
  var suffix = '.好感度';
  var list = document.getElementById('ykx-list');
  var mounted = [];

  function stageOf(value) {
    if (value >= 80) { return { text: '亲密', color: '#ff7ab8' }; }
    if (value >= 55) { return { text: '友好', color: '#3ddc97' }; }
    if (value >= 30) { return { text: '熟悉', color: '#5aa9ff' }; }
    if (value >= 10) { return { text: '陌生', color: '#8aa0b0' }; }
    return { text: '敌意', color: '#ff6b6b' };
  }

  // 卡片自己发现有哪些角色：谁在变量里出现过，就画谁。
  function discover(vars) {
    var names = [];
    for (var key in vars) {
      if (key.indexOf(prefix) !== 0 || key.indexOf(suffix) < 0) { continue; }
      var name = key.slice(prefix.length, key.length - suffix.length);
      if (name && names.indexOf(name) < 0) { names.push(name); }
    }
    names.sort();
    return names;
  }

  function build(names) {
    list.innerHTML = '';
    mounted = [];
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var item = document.createElement('div');
      item.className = 'ykx-item';
      item.innerHTML =
        '<div class="ykx-line">' +
          '<span class="ykx-name"></span>' +
          '<span class="ykx-tag"></span>' +
          '<span class="ykx-val"></span>' +
        '</div>' +
        '<div class="ykx-track"><i></i></div>';
      item.querySelector('.ykx-name').textContent = name;
      list.appendChild(item);
      mounted.push({ name: name, node: item });
    }
  }

  function render() {
    var vars = (window.YKX && YKX.getVariables()) || {};
    var names = discover(vars);
    if (names.length !== mounted.length) { build(names); }

    for (var i = 0; i < mounted.length; i++) {
      var entry = mounted[i];
      var raw = Number(vars[prefix + entry.name + suffix]);
      var value = isFinite(raw) ? raw : 0;
      var stage = stageOf(value);

      entry.node.querySelector('.ykx-tag').textContent = stage.text;
      entry.node.querySelector('.ykx-tag').style.color = stage.color;
      entry.node.querySelector('.ykx-val').textContent = value;

      var bar = entry.node.querySelector('.ykx-track > i');
      var ratio = value / 100;
      if (ratio < 0) { ratio = 0; }
      if (ratio > 1) { ratio = 1; }
      bar.style.width = (ratio * 100) + '%';
      bar.style.background = stage.color;
    }
  }

  YKX.onVariablesChanged(render);
  render();
})();
</script>
''',
);
