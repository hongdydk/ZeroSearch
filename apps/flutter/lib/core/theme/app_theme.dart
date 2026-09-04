import 'package:flutter/material.dart';

import '../layout/ui_platform.dart';
import 'mall_tokens.dart';

class AppTheme {
  static const Color brandTeal = Color(0xFF074A4E);
  static const Color priceBurgundy = Color(0xFF872022);

  static ThemeData forPlatform() => isWebUi ? web() : mall();

  static ThemeData web() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.light,
    ).copyWith(
      primary: brandTeal,
      tertiary: priceBurgundy,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: mallWebCanvasColor,
      useMaterial3: true,
      dividerColor: const Color(0xFFE5E7EB),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        shadowColor: const Color(0x14000000),
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
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.light,
    ).copyWith(
      primary: brandTeal,
      tertiary: priceBurgundy,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
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
