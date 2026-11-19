import 'package:flutter/material.dart';

class AppColors {
  // Global dark flag — flipped by ThemeProvider. Surface/text colors below
  // resolve against it so the WHOLE app switches with one toggle.
  static bool dark = false;

  // ── Brand colors (same in light + dark) ──
  // Taken from the Gora logo: royal blue leads, orange accents, on the
  // logo's deep navy.
  static const primary = Color(0xFF0A3CC8);
  static const primaryLight = Color(0xFF5B86F5);
  static const primaryDark = Color(0xFF020820);
  static const accent = Color(0xFFFF7603);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFE53935);
  static const orange = Color(0xFFFF7603);
  static const orangeSoft = Color(0xFFFFF1E6);
  static const blueSoft = Color(0xFFEAF0FF);

  // ── Theme-varying surfaces + text ──
  // Light values follow the Uber/Rapido palette: neutral #F3F4F6 tiles,
  // #E5E7EB hairlines, near-black #111111 text, #6B7280 secondary text.
  static Color get background => dark ? const Color(0xFF020820) : const Color(0xFFFFFFFF);
  static Color get white => dark ? const Color(0xFF111A3A) : const Color(0xFFFFFFFF);
  static Color get cardBg => dark ? const Color(0xFF1B2550) : const Color(0xFFF3F4F6);
  static Color get textDark => dark ? const Color(0xFFECEFF6) : const Color(0xFF111111);
  static Color get textGrey => dark ? const Color(0xFF9AA6C0) : const Color(0xFF6B7280);
  static Color get divider => dark ? const Color(0xFF2A3350) : const Color(0xFFE5E7EB);
  static Color get shimmer => dark ? const Color(0xFF232B45) : const Color(0xFFE8EEF7);
}
