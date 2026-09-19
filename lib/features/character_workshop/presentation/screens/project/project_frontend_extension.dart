part of '../project_screen.dart';

/// 阶段四：前端面板。
///
/// 这一阶段的产物是**一块能跑的状态面板**（自包含 HTML + CSS + JS），
/// 以及把它挂进消息的那条正则。两者都在导出时打进角色卡。
///
/// 页面本体在 [FrontendStagePanel] 里 —— 它自己持有预览状态（草稿 HTML、
/// 预览变量、运行日志），不往 `_ProjectScreenState` 上挂字段。
extension _ProjectFrontendExtension on _ProjectScreenState {
  List<Widget> _buildFrontendStage(CardProject project, CardProjectState state) {
    return <Widget>[
      WorkshopWidgets.card(
        title: '④ 前端面板',
        subtitle: '给这张卡做一块状态面板：生命值、好感度、属性表……'
            '面板跟着卡走，聊天里会显示在最新一条回复下方。',
        accentColor: WorkshopColors.stageDone,
        children: [
          if (!project.hasFrontend)
            WorkshopWidgets.emptyHint(
              '这一阶段是可选的。没有面板的卡就是普通卡，不影响前四个阶段的产出。\n'
              '想做一块的话：挑个模板，或者让 AI 按这张卡的设定生成一版。',
            )
          else
            Text(
              '面板已就绪（${project.frontendHtml.length} 字符）。'
              '导出时会自动写进角色卡，并附带一条挂载点正则。',
              style: const TextStyle(
                color: WorkshopColors.textSecondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      FrontendStagePanel(project: project),
    ];
  }
}
