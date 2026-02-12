
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/presets/domain/models/preset.dart';
import 'package:silly_tavern_flutter/features/regex/domain/models/regex_script.dart';

void main() {
  test('Preset should parse regex_scripts from extensions', () {
    final json = {
      "id": "123",
      "name": "Test Preset",
      "extensions": {
        "regex_scripts": [
          {
            "scriptName": "Test Regex 1",
            "regex": "foo",
            "replacement": "bar"
          }
        ]
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, "Test Regex 1");
    expect(preset.regexScripts.first.findRegex, "foo");
    expect(preset.regexScripts.first.replaceString, "bar");
  });

  test('Preset should parse regexes from SPreset.RegexBinding', () {
    final json = {
      "id": "123",
      "name": "Test Preset",
      "extensions": {
        "SPreset": {
          "RegexBinding": {
            "regexes": [
              {
                "scriptName": "Test Regex 2",
                "regex": "baz",
                "replacement": "qux"
              }
            ]
          }
        }
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, "Test Regex 2");
    expect(preset.regexScripts.first.findRegex, "baz");
    expect(preset.regexScripts.first.replaceString, "qux");
  });

  test('Preset should prefer root regex_scripts if present', () {
    final json = {
      "id": "123",
      "name": "Test Preset",
      "regex_scripts": [
        {
          "scriptName": "Root Regex",
          "regex": "root",
          "replacement": "root"
        }
      ],
      "extensions": {
        "regex_scripts": [
          {
            "scriptName": "Ext Regex",
            "regex": "ext",
            "replacement": "ext"
          }
        ]
      }
    };

    final preset = Preset.fromJson(json);
    expect(preset.regexScripts.length, 1);
    expect(preset.regexScripts.first.scriptName, "Root Regex");
  });
}
