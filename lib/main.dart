import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const M5PaperS3FlasherApp());
}

class M5PaperS3FlasherApp extends StatelessWidget {
  const M5PaperS3FlasherApp({super.key});

  static const background = Color(0xFF1A1A2E);
  static const surface = Color(0xFF22223A);
  static const accent = Color(0xFF4A90E2);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ink Flasher',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ),
        cardTheme: CardTheme(
          color: surface,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          centerTitle: false,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
