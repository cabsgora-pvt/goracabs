import 'package:flutter/material.dart';
import 'ride_tokens.dart';

/// Vehicle image for a row: a network image when the admin uploaded one, else
/// the bundled asset, else an icon — the same fallback chain every booking
/// screen already used.
class VehicleThumb extends StatelessWidget {
  final String? networkUrl;
  final String? asset;
  final IconData fallbackIcon;
  final double size;
  const VehicleThumb({
    super.key,
    this.networkUrl,
    this.asset,
    this.fallbackIcon = Icons.directions_car,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    Widget icon() => Icon(fallbackIcon, color: RideUi.accent(context), size: size * 0.5);
    Widget img;
    if (networkUrl != null && networkUrl!.isNotEmpty) {
      img = Image.network(networkUrl!, width: size, height: size, fit: BoxFit.contain,
          errorBuilder: (_, _, _) => icon());
    } else if (asset != null && asset!.isNotEmpty) {
      img = Image.asset(asset!, width: size, height: size, fit: BoxFit.contain,
          errorBuilder: (_, _, _) => icon());
    } else {
      img = icon();
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Center(child: img)),
    );
  }
}

/// One option in a "Choose a ride" list (Uber style):
///
///   [image]  Name  👤4            ₹144
///            3 min away · Drop 9:42 AM
///
/// The selected row gets a 2px navy border on a light background. Everything
/// shown is passed in by the caller — this widget never computes a price.
class VehicleOptionRow extends StatelessWidget {
  final Widget leading;
  final String name;
  final String? seats;
  final String? subtitle;
  final String? tagline;
  final String? price;
  final String? priceCaption;
  final bool selected;
  final bool unavailable;
  final VoidCallback? onTap;
  final Widget? badge;
  /// Extra content inside the row's border, under the main line — e.g. a
  /// service's own fare breakdown.
  final Widget? footer;

  const VehicleOptionRow({
    super.key,
    required this.leading,
    required this.name,
    this.seats,
    this.subtitle,
    this.tagline,
    this.price,
    this.priceCaption,
    this.selected = false,
    this.unavailable = false,
    this.onTap,
    this.badge,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final accent = RideUi.accent(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.06) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RideUi.radius),
          side: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(RideUi.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RideUi.body(context, size: 15.5, weight: FontWeight.w800)),
                    ),
                    if (seats != null && seats!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.person, size: 13, color: RideUi.muted(context)),
                      Text(seats!, style: RideUi.caption(context, size: 12).copyWith(fontWeight: FontWeight.w700)),
                    ],
                    if (badge != null) ...[const SizedBox(width: 6), badge!],
                  ]),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: unavailable
                            ? RideUi.caption(context, size: 12.5).copyWith(fontStyle: FontStyle.italic)
                            : RideUi.body(context, size: 12.5, weight: FontWeight.w500)),
                  ],
                  if (tagline != null && tagline!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(tagline!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 11.5)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (price != null)
                  Text(price!,
                      style: RideUi.body(context, size: 16, weight: FontWeight.w800)
                          .copyWith(color: unavailable ? RideUi.muted(context) : null)),
                if (priceCaption != null && priceCaption!.isNotEmpty)
                  Text(priceCaption!, style: RideUi.caption(context, size: 11)),
              ]),
            ]),
            ?footer,
            ]),
          ),
        ),
      ),
    );
  }
}
