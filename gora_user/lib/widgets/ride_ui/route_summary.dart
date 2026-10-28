import 'package:flutter/material.dart';
import 'ride_tokens.dart';

/// Pickup dot used at the top of the Uber-style connector.
class RouteDot extends StatelessWidget {
  final double size;
  const RouteDot({super.key, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RideUi.ink(context),
        ),
      );
}

/// Drop square used at the bottom of the connector.
class RouteSquare extends StatelessWidget {
  final double size;
  const RouteSquare({super.key, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: RideUi.ink(context), borderRadius: BorderRadius.circular(1.5)),
      );
}

/// Thin vertical line between dot and square.
class RouteLine extends StatelessWidget {
  final double height;
  const RouteLine({super.key, this.height = 22});

  @override
  Widget build(BuildContext context) =>
      Container(width: 2, height: height, color: RideUi.muted(context).withValues(alpha: 0.5));
}

/// Pickup → drop summary with a dot–line–square connector on the left.
class TripRouteSummary extends StatelessWidget {
  final String pickup;
  final String? drop;
  final Widget? trailing;
  final double fontSize;
  /// Lines each address may wrap to (1 = ellipsis on one line, null = no limit).
  final int? maxLines;
  const TripRouteSummary({super.key, required this.pickup, this.drop, this.trailing, this.fontSize = 13.5, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final hasDrop = drop != null && drop!.trim().isNotEmpty;
    Widget line(String text, Widget marker) => Row(children: [
          SizedBox(width: 14, child: Center(child: marker)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: RideUi.body(context, size: fontSize, weight: FontWeight.w600)),
          ),
        ]);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          line(pickup, const RouteDot()),
          if (hasDrop) ...[
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: RouteLine(height: 16),
            ),
            line(drop!, const RouteSquare()),
          ],
        ]),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ]);
  }
}
