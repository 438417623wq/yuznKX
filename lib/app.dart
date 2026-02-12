import 'package:flutter/material.dart';
import 'presentation/screens/home/home_screen.dart';

class SillyTavernApp extends StatelessWidget {
  const SillyTavernApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SillyTavern Flutter',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF1a1b26), // Dark background like ST
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16161e),
        ),
        useMaterial3: true,
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF16161e),
          indicatorColor: Colors.indigo.withOpacity(0.5),
          labelTextStyle: MaterialStateProperty.all(
            const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          iconTheme: MaterialStateProperty.all(
            const IconThemeData(color: Colors.white70),
          ),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
