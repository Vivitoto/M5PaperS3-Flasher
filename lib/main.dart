import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const VinkFlasherApp());
}

class VinkFlasherApp extends StatelessWidget {
  const VinkFlasherApp({super.key});

  static const background = Color(0xFF0B0B0C);
  static const surface = Color(0xFF151516);
  static const surfaceHigh = Color(0xFF1E1E20);
  static const foreground = Color(0xFFF2F2F2);
  static const muted = Color(0xFFA7A7A7);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: foreground,
      brightness: Brightness.dark,
      surface: surface,
      primary: foreground,
      onPrimary: Colors.black,
      secondary: muted,
    );

    return MaterialApp(
      title: 'Vink Flasher',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: scheme,
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: foreground,
              displayColor: foreground,
            ),
        cardTheme: CardTheme(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Color(0xFF2B2B2E)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: foreground,
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: foreground,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: background,
          indicatorColor: surfaceHigh,
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? foreground : muted,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? foreground : muted,
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceHigh,
          side: const BorderSide(color: Color(0xFF333336)),
          labelStyle: const TextStyle(color: foreground, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: foreground,
            foregroundColor: Colors.black,
            elevation: 0,
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: const BorderSide(color: Color(0xFF3B3B3E)),
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF333336)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF333336)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: foreground),
          ),
          labelStyle: const TextStyle(color: muted),
          helperStyle: const TextStyle(color: muted),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF2B2B2E), thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceHigh,
          contentTextStyle: const TextStyle(color: foreground),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
