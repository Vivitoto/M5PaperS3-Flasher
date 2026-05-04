import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'widgets/vink_chrome.dart';

void main() {
  runApp(const VinkFlasherApp());
}

class VinkFlasherApp extends StatelessWidget {
  const VinkFlasherApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: VinkColors.cyan,
      brightness: Brightness.dark,
      surface: VinkColors.surface,
      primary: VinkColors.cyan,
      onPrimary: Colors.black,
      secondary: VinkColors.mint,
      tertiary: VinkColors.amber,
    );

    return MaterialApp(
      title: 'Vink Flasher',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: VinkColors.ink,
        colorScheme: scheme,
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: VinkColors.text,
              displayColor: VinkColors.text,
            ),
        cardTheme: CardTheme(
          color: VinkColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: VinkColors.lineSoft),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: VinkColors.text,
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: VinkColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 64,
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0x227DD3FC),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? VinkColors.cyan
                  : VinkColors.muted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? VinkColors.cyan
                  : VinkColors.muted,
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0x1A7DD3FC),
          side: const BorderSide(color: Color(0x337DD3FC)),
          labelStyle: const TextStyle(
            color: VinkColors.text,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: VinkColors.cyan,
            foregroundColor: Colors.black,
            elevation: 0,
            minimumSize: const Size(0, 38),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: VinkColors.text,
            side: const BorderSide(color: VinkColors.line),
            minimumSize: const Size(0, 38),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: VinkColors.surfaceHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: VinkColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: VinkColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: VinkColors.cyan),
          ),
          labelStyle: const TextStyle(color: VinkColors.muted),
          helperStyle: const TextStyle(color: VinkColors.muted),
        ),
        dividerTheme: const DividerThemeData(color: VinkColors.lineSoft, thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: VinkColors.surfaceHigh,
          contentTextStyle: const TextStyle(color: VinkColors.text),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
