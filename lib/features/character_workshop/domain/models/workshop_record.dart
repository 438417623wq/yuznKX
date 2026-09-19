/// 一次成功生成的记录，用于「最近生成」列表快速回看与复用。
class WorkshopRecord {
  WorkshopRecord({
    required this.id,
    required this.prompt,
    required this.createdAt,
    required this.data,
  });

  final String id;
  final String prompt;
  final DateTime createdAt;

  /// 解析后的卡片 JSON（键名沿用 chara_card_v2）。
  final Map<String, dynamic> data;

  String get title {
    final name = data['name']?.toString().trim() ?? '';
    return name.isEmpty ? '未命名角色' : name;
  }

  String get summary {
    final description = data['description']?.toString().trim() ?? '';
    if (description.isEmpty) {
      return prompt.trim().isEmpty ? '（无需求描述）' : prompt.trim();
    }
    return description;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'prompt': prompt,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'data': data,
    };
  }

  factory WorkshopRecord.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return WorkshopRecord(
      id: json['id']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] is int
            ? json['createdAt'] as int
            : DateTime.now().millisecondsSinceEpoch,
      ),
      data: rawData is Map
          ? rawData.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{},
    );
  }
}
