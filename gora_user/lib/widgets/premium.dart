import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared building blocks for the account pages riders open most (wallet,
/// profile, settings, support, trips, offers): one type scale, one card,
/// one gradient header — so they read as one product, in light and dark.
class Premium {
  Premium._();

  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color ink(BuildContext c) => _dark(c) ? Colors.white : const Color(0xFF0F172A);
  static Color muted(BuildContext c) => _dark(c) ? Colors.white60 : const Color(0xFF64748B);
  // Dark mode follows the app's own navy theme (AppTheme.darkBg / darkSurface).
  static Color card(BuildContext c) => _dark(c) ? AppTheme.darkSurface : Colors.white;
  static Color page(BuildContext c) => _dark(c) ? AppTheme.darkBg : const Color(0xFFF5F7FB);
  static Color hairline(BuildContext c) => _dark(c) ? Colors.white10 : const Color(0xFFE8ECF3);

  static const double radius = 20;

  /// The brand gradient used by the wallet balance and profile headers.
  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF071C66), AppTheme.primaryBlue, Color(0xFF3B6BF0)],
    stops: [0, 0.55, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> shadow(BuildContext c) => _dark(c)
      ? const []
      : [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6)),
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1)),
        ];

  static BoxDecoration cardBox(BuildContext c, {double r = radius}) => BoxDecoration(
        color: card(c),
        borderRadius: BorderRadius.circular(r),
        border: _dark(c) ? Border.all(color: hairline(c)) : null,
        boxShadow: shadow(c),
      );

  // ── Type scale ──
  /// Big bold numbers (balances, totals).
  static TextStyle figure(BuildContext c, {double size = 36, Color? color}) => AppTheme.display(TextStyle(
        fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.05,
        color: color ?? ink(c), fontFeatures: const [FontFeature.tabularFigures()],
      ));

  /// Page and card titles.
  static TextStyle title(BuildContext c, {double size = 17, Color? color}) => AppTheme.display(TextStyle(
        fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: color ?? ink(c)));

  /// Row text.
  static TextStyle body(BuildContext c, {double size = 14.5, FontWeight weight = FontWeight.w600, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? ink(c));

  /// Small muted labels.
  static TextStyle label(BuildContext c, {double size = 12.5, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: color ?? muted(c), height: 1.3);

  /// Uppercase, tracked overline ("AVAILABLE BALANCE").
  static TextStyle overline(BuildContext c, {Color? color}) => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: color ?? muted(c));
}

/// A rounded card with a soft shadow.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: Premium.cardBox(context),
      child: onTap == null
          ? inner
          : Material(
              color: Colors.transparent,
              child: InkWell(borderRadius: BorderRadius.circular(Premium.radius), onTap: onTap, child: inner),
            ),
    );
  }
}

/// Uppercase tracked section heading above a group of cards.
class PremiumSection extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const PremiumSection(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: Premium.overline(context))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// The gradient header card (wallet balance, profile).
class PremiumHeaderCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  const PremiumHeaderCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 22),
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: margin,
        decoration: BoxDecoration(
          gradient: Premium.headerGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            // Soft light shapes for depth.
            Positioned(right: -40, top: -50, child: _orb(160, 0.10)),
            Positioned(right: 40, bottom: -70, child: _orb(140, 0.06)),
            Padding(padding: padding, child: child),
          ]),
        ),
      );

  static Widget _orb(double size, double a) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: a)),
      );
}

/// A round tinted icon used at the start of list rows.
class PremiumIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const PremiumIcon(this.icon, {super.key, this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryBlue;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: dark && c == AppTheme.primaryBlue ? const Color(0xFF8EA8FF) : c),
    );
  }
}
