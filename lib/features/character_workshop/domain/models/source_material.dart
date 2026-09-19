/// 导入的原始材料（设定文档 / 人设稿 / 世界观笔记 / 长篇小说）。
///
/// 材料不会直接塞进提示词 —— 长文会撑爆上下文。处理流程是：
/// 分片 → 逐片提取要点 → 合并去重 → 预填到 `DesignSpec` 的六个维度。
class SourceMaterial {
  SourceMaterial({
    required this.id,
    required this.fileName,
    required this.text,
    required this.importedAt,
    this.status = MaterialStatus.pending,
    this.error,
  });

  final String id;

  /// 原文件名（含扩展名）。
  final String fileName;

  /// 提取出的纯文本。
  final String text;

  final DateTime importedAt;

  MaterialStatus status;

  String? error;

  int get charCount => text.length;

  /// 粗估 token 数（CJK 系数 0.6，与项目既有约定一致）。
  int get estimatedTokens => (text.length * 0.6).round();

  /// 是否需要分片处理（超过 3000 字就分片）。
  bool get needsChunking => text.length > 3000;

  /// 按段落切成若干片，每片尽量不超过 [maxChars] 字。
  ///
  /// 以空行为切分点，避免把一句话劈成两半。
  List<String> chunk({int maxChars = 2400}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    if (trimmed.length <= maxChars) {
      return <String>[trimmed];
    }

    final blocks = trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        chunks.add(value);
      }
      buffer.clear();
    }

    for (final block in blocks) {
      // 单块就超长时硬切，保证每片都有上限。
      if (block.length > maxChars) {
        flush();
        for (var start = 0; start < block.length; start += maxChars) {
          final end = (start + maxChars).clamp(0, block.length);
          chunks.add(block.substring(start, end));
        }
        continue;
      }
      if (buffer.length + block.length + 2 > maxChars) {
        flush();
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer.write(block);
    }
    flush();

    return chunks;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'text': text,
      'importedAt': importedAt.millisecondsSinceEpoch,
      'status': status.key,
      'error': error,
    };
  }

  factory SourceMaterial.fromJson(Map<String, dynamic> json) {
    return SourceMaterial(
      id: json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        json['importedAt'] is int
            ? json['importedAt'] as int
            : DateTime.now().millisecondsSinceEpoch,
      ),
      status: MaterialStatus.fromKey(json['status']?.toString()),
      error: json['error']?.toString(),
    );
  }
}

/// 材料处理状态。
enum MaterialStatus {
  pending('pending', '待处理'),
  extracting('extracting', '解析中'),
  done('done', '已提取'),
  failed('failed', '失败');

  const MaterialStatus(this.key, this.label);

  final String key;
  final String label;

  static MaterialStatus fromKey(String? key) {
    for (final value in MaterialStatus.values) {
      if (value.key == key) {
        return value;
      }
    }
    return MaterialStatus.pending;
  }
}
