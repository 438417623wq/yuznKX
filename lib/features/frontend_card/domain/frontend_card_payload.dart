import '../data/frontend_card_host.dart';
import '../data/frontend_card_shim.dart';

/// 前端卡产物。
///
/// **存放位置**：角色卡的 `extensions.ykx_frontend`。
/// 跟着卡走，导出时随 `extensions` 一起进 chara_card_v2，再导入时原样回来。
///
/// **为什么不放消息里**：正则的显示期替换是在生成时执行一次并把结果写回
/// 消息内容持久化的，如果替换成完整 HTML，每条消息都会存一份副本。
/// 所以消息里只留几十字节的挂载点，HTML 只存这一份。
class FrontendCardPayload {
  const FrontendCardPayload({
    this.html = '',
    this.mount = FrontendCardBridge.mountMarker,
    this.version = 1,
    this.template = '',
  });

  /// 自包含的 HTML + CSS + JS。
  final String html;

  /// 模型每轮要输出的标记。
  final String mount;

  final int version;

  /// 用了哪个内置模板（只作记录，便于「换个模板」）。
  final String template;

  bool get isEmpty => html.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 在 `extensions` 里的键名。
  static const String extensionsKey = 'ykx_frontend';

  static FrontendCardPayload? fromExtensions(Map<String, dynamic>? extensions) {
    if (extensions == null) {
      return null;
    }
    final raw = extensions[extensionsKey];
    if (raw is Map) {
      return FrontendCardPayload.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    // 也接受直接存字符串的老格式。
    if (raw is String && raw.trim().isNotEmpty) {
      return FrontendCardPayload(html: raw);
    }
    return null;
  }

  /// 便捷取 HTML（没有前端卡时返回空串）。
  static String htmlOf(Map<String, dynamic>? extensions) =>
      fromExtensions(extensions)?.html ?? '';

  /// 把前端卡写进一份 `extensions` 拷贝（不修改入参）。
  static Map<String, dynamic> attach(
    Map<String, dynamic>? extensions,
    FrontendCardPayload payload,
  ) {
    final next = <String, dynamic>{
      ...?extensions?.map((key, value) => MapEntry(key.toString(), value)),
    };
    if (payload.isEmpty) {
      next.remove(extensionsKey);
    } else {
      next[extensionsKey] = payload.toJson();
    }
    return next;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'html': html,
        'mount': mount,
        'template': template,
      };

  factory FrontendCardPayload.fromJson(Map<String, dynamic> json) {
    return FrontendCardPayload(
      html: json['html']?.toString() ?? '',
      mount: json['mount']?.toString().trim().isEmpty == true
          ? FrontendCardBridge.mountMarker
          : json['mount'].toString(),
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '') ?? 1,
      template: json['template']?.toString() ?? '',
    );
  }
}

/// 已包装文档的**单条记忆**。
///
/// 宿主包装要把那套几十 KB 的自测量脚本拼进去，而 `ListView.builder` 在滚动时
/// 会反复重建 item —— 每次重建都拼一遍太浪费。同时只可能有一张前端卡在渲染，
/// 所以一条缓存就够，也不会有无界增长。
class FrontendCardDocumentCache {
  const FrontendCardDocumentCache._();

  static String _rawHtml = '';
  static String _document = '';

  /// 取包装好的完整文档。空 HTML 返回空串。
  static String of(String rawHtml) {
    if (rawHtml.trim().isEmpty) {
      return '';
    }
    if (rawHtml == _rawHtml && _document.isNotEmpty) {
      return _document;
    }
    _rawHtml = rawHtml;
    _document = FrontendCardHost.wrap(
      rawHtml,
      extraScript: FrontendCardBridge.shim,
    );
    return _document;
  }
}
