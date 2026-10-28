import 'package:flutter/material.dart';
import 'ride_tokens.dart';

/// The small grey drag handle at the top of every sheet.
class SheetHandle extends StatelessWidget {
  final double bottom;
  const SheetHandle({super.key, this.bottom = 12});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// White, rounded-top surface that floats over a full-bleed map.
///
/// It only paints the surface (radius, shadow, optional handle); the caller
/// decides whether the content is a ListView, a Column, a DraggableScrollableSheet
/// child, etc. — so it can wrap every existing sheet without changing how that
/// sheet scrolls or sizes itself.
class RideSheetContainer extends StatelessWidget {
  final Widget child;
  final bool handle;
  final EdgeInsetsGeometry padding;
  final double radius;
  const RideSheetContainer({
    super.key,
    required this.child,
    this.handle = false,
    this.padding = EdgeInsets.zero,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: RideUi.surface(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, -4)),
          ],
        ),
        child: Padding(
          padding: padding,
          child: handle
              ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Padding(padding: EdgeInsets.only(top: 10), child: SheetHandle()),
                  Flexible(child: child),
                ])
              : child,
        ),
      );
}

/// White circular control that floats over the map (menu, back, recenter ...).
class MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? foreground;
  final Color? background;
  final double size;
  const MapCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.foreground,
    this.background,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: background ?? RideUi.surface(context),
      elevation: 3,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 22, color: foreground ?? RideUi.ink(context)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Light-grey rounded tile used for option rows (tip, coupon, preferences ...).
class RideTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  const RideTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.onTap,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: RideUi.tile(context),
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}
