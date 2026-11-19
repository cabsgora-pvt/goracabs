import 'package:flutter/material.dart';
import 'ride_tokens.dart';

/// Number-plate styled box: bold, bordered, slightly letter-spaced.
class PlateBox extends StatelessWidget {
  final String number;
  final double fontSize;
  const PlateBox(this.number, {super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFFFFDF2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: RideUi.ink(context), width: 1.6),
        ),
        child: Text(number.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: RideUi.ink(context),
            )),
      );
}

/// Ride PIN chip — "PIN 4821" on navy. Prominent but compact.
class PinChip extends StatelessWidget {
  final String otp;
  final String label;
  final double digitSize;
  const PinChip(this.otp, {super.key, this.label = 'PIN', this.digitSize = 20});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: RideUi.navy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Text(otp,
              style: TextStyle(color: Colors.white, fontSize: digitSize, fontWeight: FontWeight.w900, letterSpacing: 3)),
        ]),
      );
}

/// Circular driver photo with a small rating badge at its foot, falling back
/// to the driver's initial when there is no photo.
class DriverAvatar extends StatelessWidget {
  final String name;
  final String photoUrl;
  final double? rating;
  final double radius;
  const DriverAvatar({super.key, required this.name, this.photoUrl = '', this.rating, this.radius = 28});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'D';
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: RideUi.tile(context),
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(initial, style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w800, color: RideUi.accent(context)))
          : null,
    );
    if (rating == null || rating! <= 0) return avatar;
    return SizedBox(
      width: radius * 2,
      height: radius * 2 + 8,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        avatar,
        Positioned(
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: RideUi.surface(context),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rating!.toStringAsFixed(1),
                  style: RideUi.body(context, size: 11, weight: FontWeight.w800)),
              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFB300)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Five small stars for a 0–5 rating, half stars included.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  const RatingStars(this.rating, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFB300);
    final r = rating.clamp(0, 5).toDouble();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          r >= i ? Icons.star_rounded : (r >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: gold,
        ),
    ]);
  }
}

/// Uber-style driver card:
///
///   (photo)  Ramesh Kumar Patel           [car image]
///            ★★★★★ 4.8 · 1,240 trips      [RJ19 TA 4521]
///            Cab · Maruti Dzire
///
/// Every value comes from the caller; empty strings are simply not shown.
/// With [showStars] (the default) the rating is a row of stars under the full
/// name; a driver with no rating yet reads "New driver", never "0.0".
class DriverInfoCard extends StatelessWidget {
  final String name;
  final String photoUrl;
  final double? rating;
  /// Completed trips, shown beside the stars.
  final int? trips;
  /// "Cab", "Bike", "Auto" — shown before the model.
  final String vehicleType;
  final String vehicleModel;
  final String plate;
  final String? stats;
  final Widget? vehicleImage;
  final Widget? trailing;
  final bool compact;
  final bool showStars;
  const DriverInfoCard({
    super.key,
    required this.name,
    this.photoUrl = '',
    this.rating,
    this.trips,
    this.vehicleType = '',
    this.vehicleModel = '',
    this.plate = '',
    this.stats,
    this.vehicleImage,
    this.trailing,
    this.compact = false,
    this.showStars = true,
  });

  static String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final r = rating ?? 0;
    final vehicleLine = [vehicleType, vehicleModel]
        .where((s) => s.trim().isNotEmpty)
        // "Cab · Cab" when the model is just the type.
        .fold<List<String>>([], (l, s) => l.any((x) => x.toLowerCase() == s.toLowerCase()) ? l : (l..add(s)))
        .join(' · ');
    final tripsText = trips != null && trips! > 0 ? '${_thousands(trips!)} ${trips == 1 ? 'trip' : 'trips'}' : '';
    return Container(
        padding: EdgeInsets.all(compact ? 8 : 14),
        decoration: BoxDecoration(
          color: RideUi.surface(context),
          borderRadius: BorderRadius.circular(RideUi.radius),
          border: Border.all(color: RideUi.divider(context)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // The stars row carries the rating, so the avatar needs no badge.
          DriverAvatar(name: name, photoUrl: photoUrl, rating: showStars ? null : rating, radius: compact ? 22 : 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name,
                  key: const ValueKey('driver_full_name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RideUi.body(context, size: compact ? 14.5 : 16.5, weight: FontWeight.w800)),
              if (showStars) ...[
                const SizedBox(height: 3),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                  if (r > 0) ...[
                    RatingStars(r, size: compact ? 13 : 15),
                    Text(r.toStringAsFixed(1), style: RideUi.body(context, size: compact ? 12 : 13, weight: FontWeight.w800)),
                  ] else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(6)),
                      child: Text('New driver', style: RideUi.caption(context, size: 11.5)),
                    ),
                  if (tripsText.isNotEmpty)
                    Text('· $tripsText', style: RideUi.caption(context, size: compact ? 11.5 : 12.5)),
                ]),
              ],
              if (vehicleLine.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(vehicleLine,
                    key: const ValueKey('driver_vehicle_line'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: RideUi.body(context, size: compact ? 12 : 13, weight: FontWeight.w600)
                        .copyWith(color: RideUi.muted(context))),
              ],
              if (stats != null && stats!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(stats!, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 11.5)),
              ],
            ]),
          ),
          if (vehicleImage != null || plate.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 118),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (vehicleImage != null) SizedBox(height: compact ? 30 : 40, child: vehicleImage),
                if (vehicleImage != null && plate.isNotEmpty) const SizedBox(height: 4),
                if (plate.isNotEmpty) PlateBox(plate, fontSize: compact ? 12 : 13),
              ]),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      );
  }
}
