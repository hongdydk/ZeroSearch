import 'package:flutter/material.dart';

import '../layout/ui_platform.dart';
import 'mall_tokens.dart';

class AppTheme {
  static ThemeData forPlatform() => isWebUi ? web() : mall();

  static ThemeData web() {
    const seed = Color(0xFF03C75A);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      extensions: const [MallTokens.web],
    );
  }

  static ThemeData mall() {
    const seed = Color(0xFF2563EB);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      extensions: const [MallTokens.app],
    );
  }
}
