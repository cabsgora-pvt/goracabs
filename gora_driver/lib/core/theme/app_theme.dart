import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// Uber-Driver / Rapido-Captain look: white surfaces, white app bars with a
// bold black left-aligned title, flat hairline cards, grey filled fields with a
// single clean border, and one strong navy CTA per screen.
class AppTheme {
  static const Color _lightInk = Color(0xFF111111);
  static const Color _lightMuted = Color(0xFF6B7280);
  static const Color _lightTile = Color(0xFFF3F4F6);
  static const Color _lightLine = Color(0xFFE5E7EB);

  static OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
    primaryColor: AppColors.primary,
    dividerColor: _lightLine,
    dividerTheme: const DividerThemeData(color: _lightLine, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _lightInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: _lightInk),
      titleTextStyle: TextStyle(color: _lightInk, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _lightInk,
        side: const BorderSide(color: _lightLine, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightTile,
      hintStyle: const TextStyle(color: _lightMuted, fontWeight: FontWeight.w500),
      labelStyle: const TextStyle(color: _lightMuted, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      prefixIconColor: _lightMuted,
      border: _border(_lightLine),
      enabledBorder: _border(_lightLine),
      focusedBorder: _border(AppColors.primary, 1.6),
      errorBorder: _border(AppColors.red),
      focusedErrorBorder: _border(AppColors.red, 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _lightLine),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(color: _lightInk, fontSize: 19, fontWeight: FontWeight.w800),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
    ),
    fontFamily: 'Roboto',
  );

  // Dark theme — surfaces flip to dark navy.
  static const Color darkBg = Color(0xFF0E1220);
  static const Color darkSurface = Color(0xFF1A2138);
  static const Color _darkTile = Color(0xFF232B45);
  static const Color _darkLine = Color(0xFF2A3350);
  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      secondary: AppColors.accent,
      surface: darkSurface,
    ),
    scaffoldBackgroundColor: darkBg,
    primaryColor: AppColors.primary,
    dividerColor: _darkLine,
    dividerTheme: const DividerThemeData(color: _darkLine, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurface,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white24, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkTile,
      border: _border(_darkLine),
      enabledBorder: _border(_darkLine),
      focusedBorder: _border(AppColors.primaryLight, 1.6),
      errorBorder: _border(AppColors.red),
      focusedErrorBorder: _border(AppColors.red, 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _darkLine),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    fontFamily: 'Roboto',
  );
}
