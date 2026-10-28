import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Visual tokens for the Uber/Ola-style ride UI: white space, bold near-black
/// headings, light-grey rounded tiles, thin dividers and one strong navy CTA.
///
/// Every colour is resolved against the current theme so the same widgets read
/// correctly in the app's dark mode as well.
class RideUi {
  RideUi._();

  static const Color navy = AppTheme.primaryBlue;
  static const double radius = 16;
  static const double gutter = 16;

  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  /// Headings and primary text.
  static Color ink(BuildContext c) => _dark(c) ? Colors.white : const Color(0xFF111111);

  /// Secondary text.
  static Color muted(BuildContext c) => _dark(c) ? Colors.white60 : const Color(0xFF6B7280);

  /// Light-grey rounded tile / pill fill.
  static Color tile(BuildContext c) => _dark(c) ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF3F4F6);

  /// Thin hairline divider.
  static Color divider(BuildContext c) => _dark(c) ? Colors.white12 : const Color(0xFFE5E7EB);

  /// Sheet / card surface.
  static Color surface(BuildContext c) => Theme.of(c).cardColor;

  /// Decoration for a text field drawn INSIDE a [tile]-coloured box.
  ///
  /// `border: InputBorder.none` alone is not enough: the app theme sets its own
  /// filled background and enabled/focused outline borders, which still drew a
  /// rounded field inside the box — a double border.
  static InputDecoration bareInput(BuildContext c, String hint, {double vertical = 12, double fontSize = 14}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: muted(c), fontSize: fontSize, fontWeight: FontWeight.w500),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: vertical),
      );

  /// The single grey field box that [bareInput] fields sit in.
  static BoxDecoration fieldBox(BuildContext c) =>
      BoxDecoration(color: tile(c), borderRadius: BorderRadius.circular(12));

  /// Brand accent that keeps contrast on dark surfaces.
  static Color accent(BuildContext c) => _dark(c) ? AppTheme.darkPrimary : navy;

  static TextStyle title(BuildContext c, {double size = 20}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: ink(c), letterSpacing: -0.2);

  static TextStyle body(BuildContext c, {double size = 14, FontWeight weight = FontWeight.w600}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: ink(c));

  static TextStyle caption(BuildContext c, {double size = 12.5}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: muted(c));

  /// "9:42 AM" style clock string.
  static String clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Section heading used inside sheets ("Services", "Choose a ride" ...).
class RideSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final double size;
  const RideSectionTitle(this.text, {super.key, this.trailing, this.size = 18});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RideUi.title(context, size: size)),
        ),
        ?trailing,
      ]);
}

/// Thin full-width hairline.
class RideDivider extends StatelessWidget {
  final double indent;
  final double vertical;
  const RideDivider({super.key, this.indent = 0, this.vertical = 0});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent, top: vertical, bottom: vertical),
        child: Container(height: 1, color: RideUi.divider(context)),
      );
}
