import 'package:flutter/material.dart';
import 'ride_tokens.dart';

/// Big, full-width primary button — the single strong CTA of a screen.
class PrimaryRideButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double height;
  const PrimaryRideButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? RideUi.navy;
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: RideUi.tile(context),
          disabledForegroundColor: RideUi.muted(context),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20, color: enabled ? Colors.white : RideUi.muted(context)), const SizedBox(width: 8)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.white : RideUi.muted(context),
                )),
          ),
        ]),
      ),
    );
  }
}

/// Fixed bottom bar: an optional chip row (payment, coupon ...) above a big
/// primary button. Honours the gesture-bar inset.
class PrimaryCtaBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? top;
  final IconData? icon;
  const PrimaryCtaBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.top,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: RideUi.surface(context),
          border: Border(top: BorderSide(color: RideUi.divider(context))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (top != null) ...[top!, const SizedBox(height: 10)],
              if (leading != null)
                Row(children: [
                  leading!,
                  const SizedBox(width: 10),
                  Expanded(child: PrimaryRideButton(label: label, onPressed: onPressed, icon: icon)),
                ])
              else
                PrimaryRideButton(label: label, onPressed: onPressed, icon: icon),
            ]),
          ),
        ),
      );
}

/// Small light-grey pill — "Cash ▾", "Now ▾", "Coupon".
class RidePillChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? labelColor;
  final Color? background;
  const RidePillChip({
    super.key,
    this.icon,
    required this.label,
    this.onTap,
    this.showChevron = true,
    this.labelColor,
    this.background,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: background ?? RideUi.tile(context),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 17, color: labelColor ?? RideUi.ink(context)), const SizedBox(width: 6)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RideUi.body(context, size: 13, weight: FontWeight.w700).copyWith(color: labelColor)),
              ),
              if (showChevron) ...[
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: labelColor ?? RideUi.ink(context)),
              ],
            ]),
          ),
        ),
      );
}

/// Round icon button with a caption under it — Call / Message / Share / Safety.
///
/// [tooltip] is optional on purpose: a screen that already has a floating
/// "Share trip" control should not get a second widget with the same tooltip.
class RoundActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? background;
  final String? tooltip;
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.background,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? RideUi.ink(context);
    Widget circle = Material(
      color: background ?? RideUi.tile(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: fg, size: 22)),
      ),
    );
    if (tooltip != null) circle = Tooltip(message: tooltip!, child: circle);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      circle,
      const SizedBox(height: 6),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: RideUi.body(context, size: 11.5, weight: FontWeight.w600)),
    ]);
  }
}

/// Text-only destructive action ("Cancel Ride") — present but not shouting.
class RideTextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  const RideTextAction({super.key, required this.label, this.onPressed, this.color = const Color(0xFFD32F2F)});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      );
}
