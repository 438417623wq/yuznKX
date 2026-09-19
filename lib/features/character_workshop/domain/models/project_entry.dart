/// 创作项目的条目模型。
///
/// **核心设计**：规划阶段与写作阶段共用同一个列表。
/// - 规划阶段产出「骨架」：`title` / `kind` / `brief` / `keys` / `order`，`content` 为空。
/// - 写作阶段逐条填充 `content`，并把 `status` 推到 `done`。
///
/// 这样就不存在「清单」与「产出」两套模型需要同步的问题 —— 断点续接也因此天然成立：
/// 第一条 `status != done` 的条目就是「该继续的地方」。

/// 条目类型。
enum EntryKind {
  characterCard('characterCard', '角色卡字段', '角色卡正文的某个字段'),
  worldbook('worldbook', '世界书条目', '关键词触发的设定条目'),
  timeline('timeline', '时间线', '世界历史与关键事件节点'),
  event('event', '剧情事件', '可被触发的剧情桥段'),
  variableSchema('variableSchema', '变量结构', 'MVU 动态变量的定义与初始值'),
  frontend('frontend', '前端面板', '带交互的状态面板（HTML/CSS/JS），有独立阶段'),
  greeting('greeting', '开场白', '主开场白与备用开场白');

  const EntryKind(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static EntryKind fromKey(String? key) {
    for (final value in EntryKind.values) {
      if (value.key == key) {
        return value;
      }
    }
    return EntryKind.worldbook;
  }

  /// 世界书类条目（会进 character_book）。
  bool get isWorldbook => this == EntryKind.worldbook || this == EntryKind.event;

  /// 角色卡字段类条目（会进 chara_card_v2 的 data）。
  bool get isCharacterField => this == EntryKind.characterCard;

  /// 是否属于「世界书」体系（含时间线，但时间线通常设为常驻）。
  ///
  /// [EntryKind.frontend] **不在**这里 —— 前端面板的内容进的是角色卡
  /// `extensions.ykx_frontend`，不是 character_book。
  bool get goesToWorldbook => isWorldbook || this == EntryKind.timeline;
}

/// 条目状态机。
enum EntryStatus {
  pending('pending', '待生成'),
  generating('generating', '生成中'),
  done('done', '已完成'),
  failed('failed', '失败'),
  skipped('skipped', '已跳过');

  const EntryStatus(this.key, this.label);

  final String key;
  final String label;

  static EntryStatus fromKey(String? key) {
    for (final value in EntryStatus.values) {
      if (value.key == key) {
        return value;
      }
    }
    return EntryStatus.pending;
  }

  /// 是否算「已处理」（用于进度统计）。
  bool get isSettled =>
      this == EntryStatus.done ||
      this == EntryStatus.skipped ||
      this == EntryStatus.failed;
}

/// 单条创作条目。
class ProjectEntry {
  ProjectEntry({
    required this.id,
    required this.title,
    this.kind = EntryKind.worldbook,
    this.brief = '',
    this.content = '',
    this.keys = const <String>[],
    this.secondaryKeys = const <String>[],
    this.fieldKey = '',
    this.order = 100,
    this.depth = 4,
    this.position = 4,
    this.constant = false,
    this.status = EntryStatus.pending,
    this.error,
    this.revision = 0,
    this.updatedAt,
  });

  final String id;

  /// 条目标题（也是世界书条目的 comment）。
  String title;

  EntryKind kind;

  /// 规划阶段写下的「这条该写什么」，写作阶段作为上下文喂给模型。
  String brief;

  /// 正文内容。
  String content;

  /// 世界书触发关键词。
  List<String> keys;

  /// 世界书次要关键词（配合 selective 使用）。
  List<String> secondaryKeys;

  /// 当 [kind] 为 [EntryKind.characterCard] 时，对应 chara_card_v2 的键名
  /// （如 `description` / `personality` / `first_mes`）。
  String fieldKey;

  /// 世界书插入顺序（也用于列表排序）。
  int order;

  /// 注入深度。
  int depth;

  /// 注入位置（0=角色定义前，4=按深度插入）。
  int position;

  /// 是否常驻注入（不依赖关键词命中）。
  bool constant;

  EntryStatus status;

  String? error;

  /// 重写次数。
  int revision;

  DateTime? updatedAt;

  bool get hasContent => content.trim().isNotEmpty;

  /// 是否属于「世界书」体系（会打包进 character_book）。
  bool get goesToWorldbook => kind.goesToWorldbook;

  ProjectEntry copyWith({
    String? title,
    EntryKind? kind,
    String? brief,
    String? content,
    List<String>? keys,
    List<String>? secondaryKeys,
    String? fieldKey,
    int? order,
    int? depth,
    int? position,
    bool? constant,
    EntryStatus? status,
    Object? error = _unset,
    int? revision,
    DateTime? updatedAt,
  }) {
    return ProjectEntry(
      id: id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      brief: brief ?? this.brief,
      content: content ?? this.content,
      keys: keys ?? this.keys,
      secondaryKeys: secondaryKeys ?? this.secondaryKeys,
      fieldKey: fieldKey ?? this.fieldKey,
      order: order ?? this.order,
      depth: depth ?? this.depth,
      position: position ?? this.position,
      constant: constant ?? this.constant,
      status: status ?? this.status,
      error: identical(error, _unset) ? this.error : error as String?,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'kind': kind.key,
      'brief': brief,
      'content': content,
      'keys': keys,
      'secondaryKeys': secondaryKeys,
      'fieldKey': fieldKey,
      'order': order,
      'depth': depth,
      'position': position,
      'constant': constant,
      'status': status.key,
      'error': error,
      'revision': revision,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory ProjectEntry.fromJson(Map<String, dynamic> json) {
    List<String> readList(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList();
      }
      return <String>[];
    }

    int readInt(dynamic value, int fallback) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    return ProjectEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      kind: EntryKind.fromKey(json['kind']?.toString()),
      brief: json['brief']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      keys: readList(json['keys']),
      secondaryKeys: readList(json['secondaryKeys']),
      fieldKey: json['fieldKey']?.toString() ?? '',
      order: readInt(json['order'], 100),
      depth: readInt(json['depth'], 4),
      position: readInt(json['position'], 4),
      constant: json['constant'] == true,
      status: EntryStatus.fromKey(json['status']?.toString()),
      error: json['error']?.toString(),
      revision: readInt(json['revision'], 0),
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }
}

const Object _unset = Object();
