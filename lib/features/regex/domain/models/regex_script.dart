import 'package:uuid/uuid.dart';

class RegexScript {
  final String id;
  final String scriptName;
  final String findRegex;
  final String replaceString;
  final String trimString;
  final List<int> placement; // [1] input, [2] output
  final bool disabled;
  final bool markdownOnly;
  final bool runOnEdit;
  final bool promptOnly;
  final int? substituteRegex; // 0=None, 1=User Name, 2=Char Name
  final int? minDepth;
  final int? maxDepth;

  RegexScript({
    required this.id,
    required this.scriptName,
    required this.findRegex,
    required this.replaceString,
    this.trimString = '',
    this.placement = const [1, 2],
    this.disabled = false,
    this.markdownOnly = false,
    this.runOnEdit = false,
    this.promptOnly = false,
    this.substituteRegex = 0,
    this.minDepth,
    this.maxDepth,
  });

  factory RegexScript.fromJson(Map<String, dynamic> json) {
    return RegexScript(
      id: json['id']?.toString() ?? const Uuid().v4(),
      scriptName: json['scriptName']?.toString() ?? json['name']?.toString() ?? 'Untitled Script',
      findRegex: json['findRegex']?.toString() ?? json['regex']?.toString() ?? '',
      replaceString: json['replaceString']?.toString() ?? json['replacement']?.toString() ?? '',
      trimString: json['trimString']?.toString() ?? '',
      placement: (json['placement'] as List?)?.map((e) => (e is num) ? e.toInt() : 1).toList() ?? [1, 2],
      disabled: json['disabled'] == true,
      markdownOnly: json['markdownOnly'] == true,
      runOnEdit: json['runOnEdit'] == true,
      promptOnly: json['promptOnly'] == true,
      substituteRegex: json['substituteRegex'] as int? ?? 0,
      minDepth: json['minDepth'] as int?,
      maxDepth: json['maxDepth'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptName': scriptName,
      'findRegex': findRegex,
      'replaceString': replaceString,
      'trimString': trimString,
      'placement': placement,
      'disabled': disabled,
      'markdownOnly': markdownOnly,
      'runOnEdit': runOnEdit,
      'promptOnly': promptOnly,
      'substituteRegex': substituteRegex,
      'minDepth': minDepth,
      'maxDepth': maxDepth,
    };
  }
}
