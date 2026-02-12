import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models/api_connection.dart';

// 1. Provider for the list of connections
final apiConnectionsProvider = StateNotifierProvider<ApiConnectionsNotifier, List<ApiConnection>>((ref) {
  return ApiConnectionsNotifier();
});

class ApiConnectionsNotifier extends StateNotifier<List<ApiConnection>> {
  ApiConnectionsNotifier() : super([]) {
    _loadConnections();
  }

  static const String _boxName = 'api_connections';
  Box? _box;

  Future<void> _loadConnections() async {
    _box = Hive.box(_boxName);
    final rawList = _box!.values.toList();
    state = rawList.map((e) => ApiConnection.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> saveConnection(ApiConnection connection) async {
    _box ??= Hive.box(_boxName);
    
    // Check if exists to update
    final index = state.indexWhere((c) => c.id == connection.id);
    List<ApiConnection> newState;
    
    if (index >= 0) {
      newState = [...state];
      newState[index] = connection;
    } else {
      newState = [...state, connection];
    }

    state = newState;
    
    // Save to Hive
    await _box!.put(connection.id, connection.toJson());
  }

  Future<void> deleteConnection(String id) async {
    _box ??= Hive.box(_boxName);
    final newState = state.where((c) => c.id != id).toList();
    state = newState;
    await _box!.delete(id);
  }
}

// 2. Provider for the currently active connection ID
final activeApiIdProvider = StateNotifierProvider<ActiveApiIdNotifier, String?>((ref) {
  return ActiveApiIdNotifier();
});

class ActiveApiIdNotifier extends StateNotifier<String?> {
  ActiveApiIdNotifier() : super(null) {
    _loadActiveId();
  }

  Future<void> _loadActiveId() async {
    final box = Hive.box('settings');
    state = box.get('active_api_id') as String?;
  }

  Future<void> setActiveId(String? id) async {
    state = id;
    final box = Hive.box('settings');
    if (id == null) {
      await box.delete('active_api_id');
    } else {
      await box.put('active_api_id', id);
    }
  }
}

// 3. Provider for the actual active ApiConnection object
final activeApiConnectionProvider = Provider<ApiConnection?>((ref) {
  final id = ref.watch(activeApiIdProvider);
  final connections = ref.watch(apiConnectionsProvider);
  if (id == null) return null;
  try {
    return connections.firstWhere((c) => c.id == id);
  } catch (e) {
    return null;
  }
});
