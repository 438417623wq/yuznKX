import 'package:uuid/uuid.dart';

class RegexScript {
  final String id;
  final String scriptName;
  final String findRegex;
  final String replaceString;
  final String trimString;
  final List<String> trimStrings;
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
    this.trimStrings = const [],
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
    // Helper to safely parse int
    int? parseInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val);
      return null;
    }

    // Helper for placement list
    List<int> parsePlacement(dynamic val) {
      if (val is List) {
        final parsed = val
            .map((e) => parseInt(e))
            .whereType<int>()
            .where((e) => e == 1 || e == 2 || e == 3)
            .toList();
        return parsed.isEmpty ? [1, 2] : parsed;
      }
      return [1, 2];
    }

    List<String> parseTrimStrings(dynamic val) {
      if (val is List) {
        return val
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (val is String) {
        return val
            .split(RegExp(r'[\r\n]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    final parsedTrimStrings = parseTrimStrings(
      json['trimStrings'] ?? json['trim_strings'],
    );
    final legacyTrimString =
        json['trimString']?.toString() ?? json['trim_string']?.toString() ?? '';
    final mergedTrimStrings = parsedTrimStrings.isNotEmpty
        ? parsedTrimStrings
        : parseTrimStrings(legacyTrimString);

    return RegexScript(
      id: json['id']?.toString() ?? const Uuid().v4(),
      scriptName: json['scriptName']?.toString() ??
          json['name']?.toString() ??
          'Untitled Script',
      findRegex:
          json['findRegex']?.toString() ?? json['regex']?.toString() ?? '',
      replaceString: json['replaceString']?.toString() ??
          json['replacement']?.toString() ??
          '',
      trimString: legacyTrimString.isNotEmpty
          ? legacyTrimString
          : mergedTrimStrings.join('\n'),
      trimStrings: mergedTrimStrings,
      placement: parsePlacement(json['placement']),
      disabled: json['disabled'] == true ||
          (json.containsKey('enabled') && json['enabled'] == false),
      markdownOnly: json['markdownOnly'] == true,
      runOnEdit: json['runOnEdit'] == true,
      promptOnly: json['promptOnly'] == true,
      substituteRegex: parseInt(json['substituteRegex']) ?? 0,
      minDepth: parseInt(json['minDepth']),
      maxDepth: parseInt(json['maxDepth']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptName': scriptName,
      'findRegex': findRegex,
      'replaceString': replaceString,
      'trimString': trimString,
      'trimStrings': trimStrings,
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
