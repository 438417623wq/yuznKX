/// RP Hub 上下文组装的共享数据结构。
///
/// 说明：本文件原本还包含一套独立的 Prompt 组装器 `buildRpHubStyleContext()`，
/// 它从未被生产链路调用，却与 `chat_provider._assemblePromptMessages()` 分叉演进，
/// 造成「两套装配逻辑」的隐患。现已删除，统一由 `chat_provider` 负责装配。
///
/// 目前仅保留运行时真正使用的注入描述结构。
library;

/// 需要按「深度」插入到对话历史中的一段注入内容。
///
/// 世界书 @Depth 条目、Author's Note、预设里的绝对位置 Prompt
/// 都通过它来描述「插在哪、以什么角色、什么顺序」。
class RpHubContextDepthInjection {
  final String title;
  final String role;
  final String content;
  final int depth;
  final int order;
  final String sourceKey;
  final String sourceLabel;

  const RpHubContextDepthInjection({
    required this.title,
    required this.role,
    required this.content,
    required this.depth,
    required this.order,
    required this.sourceKey,
    required this.sourceLabel,
  });
}
