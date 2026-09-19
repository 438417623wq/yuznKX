/// 角色卡字段目录（chara_card_v2 规范）。
///
/// 字段的 `key` 直接沿用 chara_card_v2 的 JSON 键名，因此解析结果可以无损映射回
/// [Character]，也能原样打包进 PNG/JSON。
///
/// [instruction] 同时承担两个职责：
/// 1. 规划阶段 —— 作为该条目的 `brief`（告诉模型这条该写什么）；
/// 2. 写作阶段 —— 作为该条目的写作要求。
library;

/// 角色名字段键（永远存在，且必须有值）。
const String kNameFieldKey = 'name';

/// 单条生成的详细程度：同时决定提示词里的字数要求和 max_tokens 预算。
enum EntryLength {
  concise('简洁', '1~2 句，简洁扼要', 900),
  standard('标准', '3~5 句，展开但不啰嗦', 1800),
  detailed('详尽', '尽量展开，细节丰富', 3200);

  const EntryLength(this.label, this.hint, this.maxTokens);

  final String label;
  final String hint;
  final int maxTokens;
}

/// 输出语言。
enum OutputLanguage {
  zh('中文', '简体中文'),
  en('English', 'English'),
  auto('跟随需求', '与创作需求相同的语言');

  const OutputLanguage(this.label, this.hint);

  final String label;
  final String hint;
}

/// 一个可创作的角色卡字段。
class CardField {
  const CardField({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.instruction,
    this.isList = false,
    this.alwaysInclude = false,
  });

  final String key;
  final String label;
  final String subtitle;

  /// 交给模型的写作要求（也用作条目的 brief）。
  final String instruction;

  /// 值是否为数组（tags / alternate_greetings）。
  final bool isList;

  /// 是否默认纳入规划。
  final bool alwaysInclude;
}

/// 全部角色卡字段。
const List<CardField> kCardFields = <CardField>[
  CardField(
    key: 'description',
    label: '角色描述',
    subtitle: '外貌、身份、背景',
    instruction: '角色的外貌、身份、来历与当前处境，用第三人称客观陈述，不要写成小作文',
    alwaysInclude: true,
  ),
  CardField(
    key: 'personality',
    label: '性格',
    subtitle: '性格与行为模式',
    instruction: '性格特质、价值观、在意的事、行为模式与说话习惯（含口癖）',
    alwaysInclude: true,
  ),
  CardField(
    key: 'system_prompt',
    label: '对话风格',
    subtitle: '扮演指令',
    instruction: '给模型的扮演指令，写明语气、称呼对方的方式、必须遵守的规则与禁忌',
  ),
  CardField(
    key: 'scenario',
    label: '场景',
    subtitle: '故事开场设定',
    instruction: '故事开始时的地点、时间、氛围与双方关系',
  ),
  CardField(
    key: 'first_mes',
    label: '开场白',
    subtitle: '角色的第一段话',
    instruction: '角色说出的第一段话：先写环境与动作描写（可用括号包裹动作），再接台词',
    alwaysInclude: true,
  ),
  CardField(
    key: 'alternate_greetings',
    label: '备用开场白',
    subtitle: '3 条备选开场',
    instruction: '3 条与主开场白走向明显不同的备选开场白，每条都要独立完整',
    isList: true,
  ),
  CardField(
    key: 'mes_example',
    label: '示例对话',
    subtitle: '对话范例',
    instruction: '2~3 轮对话范例，每轮用 <START> 分隔，充分体现角色的说话风格',
  ),
  CardField(
    key: 'creator_notes',
    label: '作者备注',
    subtitle: '给创作者看的说明',
    instruction: '给使用者看的简短说明：推荐用法、适配的模型、注意事项',
  ),
  CardField(
    key: 'tags',
    label: '标签',
    subtitle: '4~8 个短标签',
    instruction: '4~8 个简短标签，每个 2~4 个字，便于检索',
    isList: true,
  ),
];

/// 默认纳入规划的字段。
const Set<String> kDefaultCardFieldKeys = <String>{
  'description',
  'personality',
  'first_mes',
};

/// 根据 key 查字段定义，找不到返回 null。
CardField? cardFieldByKey(String key) {
  for (final field in kCardFields) {
    if (field.key == key) {
      return field;
    }
  }
  return null;
}

/// 字段的中文名（含 `name` 特例）。
String cardFieldLabel(String key) {
  if (key == kNameFieldKey) {
    return '名称';
  }
  return cardFieldByKey(key)?.label ?? key;
}

/// 世界书条目的类型选项（规划阶段用）。
const List<String> kWorldbookKindOptions = <String>[
  '地点',
  '组织',
  '人物',
  '术语',
  '规则',
  '物品',
  '事件',
  '关系',
];
