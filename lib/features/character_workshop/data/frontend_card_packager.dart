import '../../frontend_card/data/frontend_card_shim.dart';
import '../../frontend_card/domain/frontend_card_payload.dart';
import '../../regex/domain/models/regex_script.dart';
import '../domain/frontend_templates.dart';
import '../domain/models/card_project.dart';

/// 前端面板的打包产物。
class PackedFrontend {
  const PackedFrontend({
    required this.payload,
    required this.mountScript,
    required this.postHistoryInstruction,
  });

  /// 要写进角色卡 `extensions.ykx_frontend` 的产物。
  final FrontendCardPayload payload;

  /// 把模型输出的标记换成挂载点的正则。
  final RegexScript mountScript;

  /// 追加到 `post_history_instructions` 的指令。
  final String postHistoryInstruction;
}

/// 把工坊的前端面板打包进角色卡。
///
/// **两件事都要做，缺一个面板就出不来**：
/// 1. 面板 HTML 存进 `extensions.ykx_frontend`（跟着卡走，不进消息）；
/// 2. 一条正则把模型每轮输出的挂载标记换成几十字节的挂载点。
///
/// 另外给 `post_history_instructions` 加一句指令，告诉模型每轮要吐那个标记。
/// 就算模型忘了吐（或者预设把 Author's Note 槽位关了），聊天侧还有
/// 「挂在最新一条助手消息末尾」的兜底，面板一样会出现。
class FrontendCardPackager {
  const FrontendCardPackager._();

  /// 正则 ID 由项目 ID 派生 —— 重复导出是**更新**同一个脚本，不会攒出一堆。
  static String mountScriptId(String projectId) =>
      'ykx_frontend_mount_${projectId.trim()}';

  static PackedFrontend? build(CardProject project) {
    final html = project.frontendHtml;
    if (html.isEmpty) {
      return null;
    }

    return PackedFrontend(
      payload: FrontendCardPayload(
        html: html,
        template: _templateKeyOf(html),
      ),
      mountScript: RegexScript(
        id: mountScriptId(project.id),
        scriptName: '前端面板挂载点 · ${project.characterName}',
        // 只认标记本身，不动别的文字。pattern 里带 `<` `>`，会顺便让
        // 正则引擎关掉「保护 HTML 片段」的行为（见 _shouldProtectRegexTargets），
        // 否则标记嵌在代码块里就换不掉了。
        findRegex: r'<!--\s*YKX_PANEL\s*-->',
        replaceString: FrontendCardBridge.mountHtml,
        // [2] = 只作用于模型输出。
        placement: const <int>[2],
        runOnEdit: true,
      ),
      postHistoryInstruction: postHistoryInstruction,
    );
  }

  /// 每轮都要模型吐一次挂载标记的指令。
  ///
  /// 成本约 40 个 token，换来的是「面板的位置由模型决定」——它可以把面板
  /// 放在旁白之后、对话之前，而不是永远吊在消息末尾。
  static const String postHistoryInstruction = '''
[状态面板]
每次回复的最后单独输出一行：
${FrontendCardBridge.mountMarker}
这一行是状态面板的挂载点，必须原样保留：不要改写、不要省略、不要放进代码块、不要解释。
面板本身由客户端渲染，你不要输出任何 HTML。''';

  /// 反查这段 HTML 来自哪个内置模板（只作记录，找不到就空串）。
  static String _templateKeyOf(String html) {
    final normalized = html.trim();
    for (final template in FrontendTemplate.builtIn) {
      if (template.html.trim() == normalized) {
        return template.key;
      }
    }
    return '';
  }
}
