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

/// Uber-style driver card:
///
///   (photo ★4.8)  Ramesh                [car image]
///                 Maruti Dzire · White  [RJ19 TA 4521]
///
/// Every value comes from the caller; empty strings are simply not shown.
class DriverInfoCard extends StatelessWidget {
  final String name;
  final String photoUrl;
  final double? rating;
  final String vehicleModel;
  final String plate;
  final String? stats;
  final Widget? vehicleImage;
  final Widget? trailing;
  final bool compact;
  const DriverInfoCard({
    super.key,
    required this.name,
    this.photoUrl = '',
    this.rating,
    this.vehicleModel = '',
    this.plate = '',
    this.stats,
    this.vehicleImage,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(compact ? 8 : 14),
        decoration: BoxDecoration(
          color: RideUi.surface(context),
          borderRadius: BorderRadius.circular(RideUi.radius),
          border: Border.all(color: RideUi.divider(context)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          DriverAvatar(name: name, photoUrl: photoUrl, rating: rating, radius: compact ? 20 : 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RideUi.body(context, size: compact ? 14 : 16.5, weight: FontWeight.w800)),
              if (vehicleModel.isNotEmpty) ...[
                SizedBox(height: compact ? 0 : 2),
                Text(vehicleModel, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: compact ? 12 : 12.5)),
              ],
              if (stats != null && stats!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(stats!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 11.5)),
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
