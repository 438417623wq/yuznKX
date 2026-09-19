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
  await Hive.openBox('character_workshop'); // 角色工坊旧版：仅用于一次性迁移
  await Hive.openBox('card_projects'); // 角色工坊：创作项目（五阶段流水线）
  await Hive.openBox('preset_projects'); // 预设工坊：预设项目（五阶段流水线）
  
  // Wrap with ProviderScope for Riverpod
  runApp(
    const ProviderScope(
      child: SillyTavernApp(),
    ),
  );
}
