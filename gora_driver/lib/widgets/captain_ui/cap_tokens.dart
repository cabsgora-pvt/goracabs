import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Visual tokens for the Rapido-Captain / Uber-Driver style UI: white space,
/// bold near-black headings, light-grey rounded tiles, hairline dividers and a
/// single strong navy CTA per screen.
///
/// Colours resolve through [AppColors], whose surface/text getters follow the
/// app-wide dark flag, so every captain_ui widget reads correctly in dark mode
/// without needing a BuildContext.
class Cap {
  Cap._();

  static const Color navy = AppColors.primary;
  static const Color green = AppColors.green;
  static const Color red = AppColors.red;
  static const Color orange = AppColors.orange;
  static const Color amber = Color(0xFFFFB300);

  static const double radius = 16;
  static const double gutter = 16;

  /// Headings and primary text.
  static Color get ink => AppColors.textDark;

  /// Secondary text.
  static Color get muted => AppColors.textGrey;

  /// Light-grey rounded tile / field fill.
  static Color get tile => AppColors.cardBg;

  /// Hairline divider / field border.
  static Color get divider => AppColors.divider;

  /// Card / sheet surface.
  static Color get surface => AppColors.white;

  /// Page background.
  static Color get bg => AppColors.background;

  /// Brand accent that keeps contrast on dark surfaces.
  static Color get accent => AppColors.dark ? AppColors.primaryLight : navy;

  static TextStyle title({double size = 22}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.3, height: 1.2);

  static TextStyle body({double size = 14, FontWeight weight = FontWeight.w600, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? ink);

  /// Big bold figure or name: balances, today's earning, the driver's name.
  static TextStyle display({double size = 30, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color ?? ink, letterSpacing: -0.8, height: 1.1);

  /// Small upper-case label above a figure or a section ("AVAILABLE BALANCE").
  static TextStyle overline({double size = 11, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color ?? muted, letterSpacing: 1.5, height: 1.2);

  /// Soft card shadow; deeper on dark surfaces so cards still lift.
  static List<BoxShadow> get softShadow => [
        BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.dark ? 0.32 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6)),
      ];

  /// Brand gradient for header cards (profile, account, wallet, earnings).
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B62F5), Color(0xFF0A3CC8), Color(0xFF06217A)],
  );

  static TextStyle caption({double size = 12.5, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: color ?? muted, height: 1.35);

  /// Grey filled field with a single hairline border; navy when focused.
  /// Use with a [CapLabel] above the field rather than a floating label.
  static InputDecoration input({
    String? hint,
    Widget? prefix,
    Widget? suffix,
    String? prefixText,
    bool dense = false,
  }) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: muted, fontWeight: FontWeight.w500, fontSize: 14.5),
      filled: true,
      fillColor: tile,
      counterText: '',
      isDense: dense,
      prefixIcon: prefix,
      prefixText: prefixText,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: b(divider),
      enabledBorder: b(divider),
      disabledBorder: b(divider),
      focusedBorder: b(accent, 1.6),
      errorBorder: b(red),
      focusedErrorBorder: b(red, 1.6),
    );
  }
}
