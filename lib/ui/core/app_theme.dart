import 'package:flutter/material.dart';

/// 应用视觉主题。
abstract final class AppTheme {
  static ThemeData dark() {
    const background = Color(0xFF101214);
    const surface = Color(0xFF1A1D20);
    const primary = Color(0xFFD94B3D);
    const secondary = Color(0xFF4CA07A);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(primary: primary, secondary: secondary, surface: surface);
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: Color(0xFF303438)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF303438)),
    );
  }
}
