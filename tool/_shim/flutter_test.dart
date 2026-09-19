/// 极简 `package:flutter_test` 替身 —— 只为在沙箱里（`flutter test` 跑不了）
/// 把纯逻辑测试文件的断言真跑一遍。
///
/// 用法：把测试文件复制到 `tool/` 下，把
/// `import 'package:flutter_test/flutter_test.dart';`
/// 换成 `import '_shim/flutter_test.dart';`，然后 `dart run` 那个副本。
///
/// ⛔ 只支持本仓库纯逻辑测试用到的那几个 matcher。新增 matcher 要在这里补，
/// 否则会**静默当成「值相等」比较**（`Matcher` 是本地类型，不是 `test_api` 的）。
library;

class Matcher {
  const Matcher();
}

class _PredicateMatcher extends Matcher {
  const _PredicateMatcher(this.describe, this.test);

  final String describe;
  final bool Function(Object? actual) test;
}

class _EqualsMatcher extends Matcher {
  const _EqualsMatcher(this.expected);

  final Object? expected;
}

class _HasLengthMatcher extends Matcher {
  const _HasLengthMatcher(this.length);

  final int length;
}

class _ContainsMatcher extends Matcher {
  const _ContainsMatcher(this.needle);

  final Object? needle;
}

class _ContainsAllMatcher extends Matcher {
  const _ContainsAllMatcher(this.needles);

  final Iterable<Object?> needles;
}

/// `isNot(x)` —— 取反。
///
/// ⛔ 没有这个类时，`isNot(contains('x'))` 会掉进 `_matches` 最后的
/// 「直接传值当相等比较」分支，变成「拿实际值去和一个 Matcher 对象比相等」，
/// **恒为 false** → 本该通过的否定断言全部红，而且报错信息看不出原因。
class _IsNotMatcher extends Matcher {
  const _IsNotMatcher(this.inner);

  final Matcher inner;
}

const Matcher isTrue = _PredicateMatcher('isTrue', _isTrue);
const Matcher isFalse = _PredicateMatcher('isFalse', _isFalse);
const Matcher isNull = _PredicateMatcher('isNull', _isNull);
const Matcher isNotNull = _PredicateMatcher('isNotNull', _isNotNull);
const Matcher isEmpty = _PredicateMatcher('isEmpty', _isEmpty);
const Matcher isNotEmpty = _PredicateMatcher('isNotEmpty', _isNotEmpty);
const Matcher isList = _PredicateMatcher('isList', _isList);
const Matcher isMap = _PredicateMatcher('isMap', _isMap);
const Matcher isString = _PredicateMatcher('isString', _isString);

bool _isTrue(Object? value) => value == true;
bool _isFalse(Object? value) => value == false;
bool _isNull(Object? value) => value == null;
bool _isNotNull(Object? value) => value != null;
bool _isEmpty(Object? value) => _lengthOf(value) == 0;
bool _isNotEmpty(Object? value) => (_lengthOf(value) ?? 0) > 0;
bool _isList(Object? value) => value is List;
bool _isMap(Object? value) => value is Map;
bool _isString(Object? value) => value is String;

Matcher equals(Object? expected) => _EqualsMatcher(expected);
Matcher hasLength(int length) => _HasLengthMatcher(length);
Matcher contains(Object? needle) => _ContainsMatcher(needle);
Matcher containsAll(Iterable<Object?> needles) => _ContainsAllMatcher(needles);

/// 取反。既接受 Matcher，也接受裸值（裸值按相等比较后取反）。
Matcher isNot(Object? inner) =>
    _IsNotMatcher(inner is Matcher ? inner : _EqualsMatcher(inner));

// --- 测试注册 ---

class _Case {
  const _Case(this.name, this.body);

  final String name;
  final void Function() body;
}

final List<String> _groupPath = <String>[];
final List<_Case> _cases = <_Case>[];
int _passed = 0;
final List<String> _failures = <String>[];

void group(String description, void Function() body) {
  _groupPath.add(description);
  body();
  _groupPath.removeLast();
}

void test(String description, void Function() body) {
  _cases.add(_Case([..._groupPath, description].join(' › '), body));
}

void expect(Object? actual, Object? expected, {String? reason}) {
  final ok = _matches(actual, expected);
  if (ok) {
    return;
  }
  final buffer = StringBuffer('期望不符')
    ..writeln()
    ..writeln('    actual   = ${_show(actual)}')
    ..writeln('    expected = ${_show(expected)}');
  if (reason != null) {
    buffer.writeln('    reason   = $reason');
  }
  throw _ExpectFailure(buffer.toString());
}

class _ExpectFailure implements Exception {
  _ExpectFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _matches(Object? actual, Object? expected) {
  // ⛔ 必须先于其它分支 —— 否则 `isNot(contains(..))` 会被当成「值相等」比较。
  if (expected is _IsNotMatcher) {
    return !_matches(actual, expected.inner);
  }
  if (expected is _PredicateMatcher) {
    return expected.test(actual);
  }
  if (expected is _HasLengthMatcher) {
    final length = _lengthOf(actual);
    return length != null && length == expected.length;
  }
  if (expected is _ContainsMatcher) {
    if (actual is String) {
      return actual.contains(expected.needle.toString());
    }
    if (actual is Iterable) {
      return actual.contains(expected.needle);
    }
    if (actual is Map) {
      return actual.containsKey(expected.needle);
    }
    return false;
  }
  if (expected is _ContainsAllMatcher) {
    if (actual is Iterable) {
      return expected.needles.every(actual.contains);
    }
    return false;
  }
  if (expected is _EqualsMatcher) {
    return _deepEquals(actual, expected.expected);
  }
  // 直接传值 —— 当作相等比较（与 `test` 包的行为一致）。
  return _deepEquals(actual, expected);
}

int? _lengthOf(Object? value) {
  if (value is String) return value.length;
  if (value is Iterable) return value.length;
  if (value is Map) return value.length;
  return null;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

String _show(Object? value) {
  if (value is String) {
    return "'$value'";
  }
  if (value is Matcher) {
    if (value is _IsNotMatcher) return 'isNot(${_show(value.inner)})';
    if (value is _PredicateMatcher) return value.describe;
    if (value is _HasLengthMatcher) return 'hasLength(${value.length})';
    if (value is _ContainsMatcher) return 'contains(${value.needle})';
    if (value is _ContainsAllMatcher) return 'containsAll(${value.needles})';
    if (value is _EqualsMatcher) return _show(value.expected);
  }
  return '$value';
}

/// 跑完所有注册的用例并打印结果；返回进程退出码。
int runAll() {
  for (final testCase in _cases) {
    try {
      testCase.body();
      _passed++;
    } catch (error) {
      _failures.add('${testCase.name}\n    $error');
    }
  }

  print('');
  print('用例：通过 $_passed / 共 ${_cases.length}');
  if (_failures.isEmpty) {
    print('全部通过');
    return 0;
  }
  print('');
  for (var i = 0; i < _failures.length; i++) {
    print('[${i + 1}] ${_failures[i]}');
    print('');
  }
  print('失败 ${_failures.length} 个用例');
  return 1;
}
