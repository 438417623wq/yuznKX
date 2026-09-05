import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _globalVariablesKey = 'global_variables';
const _chatVariablesKey = 'chat_variables';

Map<String, dynamic> _normalizeMap(dynamic raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

num _toNumber(dynamic value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

final globalVariablesProvider =
    StateNotifierProvider<GlobalVariablesNotifier, Map<String, dynamic>>(
  (ref) => GlobalVariablesNotifier(),
);

final chatVariablesProvider = StateNotifierProvider.family<
    ChatVariablesNotifier, Map<String, dynamic>, String>(
  (ref, sessionId) => ChatVariablesNotifier(sessionId),
);

class GlobalVariablesNotifier extends StateNotifier<Map<String, dynamic>> {
  late final Box _settings;

  GlobalVariablesNotifier() : super(const {}) {
    _settings = Hive.box('settings');
    _load();
  }

  void _load() {
    state = _normalizeMap(_settings.get(_globalVariablesKey));
  }

  Future<void> _persist() async {
    await _settings.put(_globalVariablesKey, state);
  }

  dynamic getValue(String key) => state[key];

  void setValue(String key, dynamic value) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    state = {
      ...state,
      normalizedKey: value,
    };
    _persist();
  }

  dynamic addValue(String key, dynamic delta) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }
    final current = state[normalizedKey];
    final next = _toNumber(current) + _toNumber(delta);
    setValue(normalizedKey, next);
    return next;
  }

  void deleteValue(String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty || !state.containsKey(normalizedKey)) {
      return;
    }
    final newState = Map<String, dynamic>.from(state)..remove(normalizedKey);
    state = newState;
    _persist();
  }

  void clearAll() {
    state = const {};
    _persist();
  }
}

class ChatVariablesNotifier extends StateNotifier<Map<String, dynamic>> {
  final String sessionId;
  late final Box _settings;

  ChatVariablesNotifier(this.sessionId) : super(const {}) {
    _settings = Hive.box('settings');
    _load();
  }

  Map<String, dynamic> _allChatVariables() {
    return _normalizeMap(_settings.get(_chatVariablesKey));
  }

  void _load() {
    state = _normalizeMap(_allChatVariables()[sessionId]);
  }

  Future<void> _persist() async {
    final all = _allChatVariables();
    all[sessionId] = state;
    await _settings.put(_chatVariablesKey, all);
  }

  dynamic getValue(String key) => state[key];

  void setValue(String key, dynamic value) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    state = {
      ...state,
      normalizedKey: value,
    };
    _persist();
  }

  dynamic addValue(String key, dynamic delta) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }
    final current = state[normalizedKey];
    final next = _toNumber(current) + _toNumber(delta);
    setValue(normalizedKey, next);
    return next;
  }

  void deleteValue(String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty || !state.containsKey(normalizedKey)) {
      return;
    }
    final newState = Map<String, dynamic>.from(state)..remove(normalizedKey);
    state = newState;
    _persist();
  }

  void clearAll() {
    state = const {};
    _persist();
  }
}
