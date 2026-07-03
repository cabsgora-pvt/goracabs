import 'package:flutter/material.dart';

class AppColors {
  // Global dark flag — flipped by ThemeProvider. Surface/text colors below
  // resolve against it so the WHOLE app switches with one toggle.
  static bool dark = false;

  // ── Brand colors (same in light + dark) ──
  static const primary = Color(0xFF1C2656);
  static const primaryLight = Color(0xFF3A4A8C);
  static const primaryDark = Color(0xFF10162E);
  static const accent = Color(0xFF3A4A8C);
  static const green = Color(0xFF43A047);
  static const red = Color(0xFFE53935);
  static const orange = Color(0xFFFB8C00);

  // ── Theme-varying surfaces + text ──
  static Color get background => dark ? const Color(0xFF0E1220) : const Color(0xFFFFFFFF);
  static Color get white => dark ? const Color(0xFF1A2138) : const Color(0xFFFFFFFF);
  static Color get cardBg => dark ? const Color(0xFF232B45) : const Color(0xFFF0F4FF);
  static Color get textDark => dark ? const Color(0xFFECEFF6) : const Color(0xFF0D1B2A);
  static Color get textGrey => dark ? const Color(0xFF9AA6C0) : const Color(0xFF607D8B);
  static Color get divider => dark ? const Color(0xFF2A3350) : const Color(0xFFE0E7FF);
  static Color get shimmer => dark ? const Color(0xFF232B45) : const Color(0xFFE8EEF7);
}
