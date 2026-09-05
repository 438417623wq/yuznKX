import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/regex/domain/models/regex_script.dart';

void main() {
  test('RegexScript should parse trimStrings list', () {
    final script = RegexScript.fromJson({
      'id': 'r1',
      'scriptName': 'Trim List',
      'regex': 'foo',
      'replacement': 'bar',
      'trimStrings': ['<a>', '  ', '<b>'],
    });

    expect(script.trimStrings, ['<a>', '<b>']);
    expect(script.trimString, '<a>\n<b>');
  });

  test('RegexScript should fallback trimStrings from legacy trimString', () {
    final script = RegexScript.fromJson({
      'id': 'r2',
      'scriptName': 'Trim Legacy',
      'regex': 'foo',
      'replacement': 'bar',
      'trimString': '<x>\n<y>\n',
    });

    expect(script.trimStrings, ['<x>', '<y>']);
    expect(script.trimString, '<x>\n<y>\n');
  });
}
