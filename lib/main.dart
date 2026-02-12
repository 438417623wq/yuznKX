import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  // Initialize bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('api_connections');
  await Hive.openBox('presets');
  await Hive.openBox('world_info');
  await Hive.openBox('regex_scripts');
  await Hive.openBox('sessions');
  await Hive.openBox('characters'); // Add characters box
  
  // Wrap with ProviderScope for Riverpod
  runApp(
    const ProviderScope(
      child: SillyTavernApp(),
    ),
  );
}
