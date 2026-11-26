// ─────────────────────────────────────────────────────────────────────────────
// "Book again" on the home screen: repeat the last ride, or offer the way back.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'place_names.dart';

/// How close (metres) the rider must be to the last ride's drop for the card
/// to offer the return trip instead of the same trip again.
const double kReturnTripRadiusM = 1500;

/// Great-circle distance in metres between two points.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

/// What the "Book again" card books.
///
/// [isReturn]: the rider is standing near where the last ride ended, so the
/// useful repeat is the way back — drop = the last ride's pickup. Otherwise
/// the same destination again. The pickup is always the rider's current
/// location (for a return that is, by definition, the last drop).
class BookAgainPlan {
  final bool isReturn;
  final String fromLabel; // what the route summary shows as the start
  final String dropAddress;
  final double dropLat;
  final double dropLng;
  final String title; // "Return to Gondal" / "Book again to Rajkot"
  final String cta;
  const BookAgainPlan({
    required this.isReturn,
    required this.fromLabel,
    required this.dropAddress,
    required this.dropLat,
    required this.dropLng,
    required this.title,
    required this.cta,
  });
}

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// A short name for an address: the town when the trip crosses towns
/// ("Gondal"), else the place itself ("Crystal Mall").
String _shortName(String address, String other) {
  final town = cityOf(address);
  final otherTown = cityOf(other);
  if (town.isNotEmpty && town.toLowerCase() != otherTown.toLowerCase()) return town;
  final first = address.split(',').map((p) => p.trim()).firstWhere((p) => p.isNotEmpty, orElse: () => '');
  return first.isNotEmpty ? first : town;
}

/// The plan for [ride] (a completed ride with drop coordinates) given the
/// rider's current position, or null when the ride has no usable drop.
BookAgainPlan? bookAgainPlan(Map<String, dynamic> ride, {double? hereLat, double? hereLng}) {
  final pickup = (ride['pickupAddress'] ?? '').toString().trim();
  final drop = (ride['dropAddress'] ?? '').toString().trim();
  final dropLat = _d(ride['dropLat']), dropLng = _d(ride['dropLng']);
  if (drop.isEmpty || dropLat == null || dropLng == null) return null;
  final pLat = _d(ride['pickupLat']), pLng = _d(ride['pickupLng']);

  final nearDrop = hereLat != null && hereLng != null &&
      haversineMeters(hereLat, hereLng, dropLat, dropLng) <= kReturnTripRadiusM;
  // The way back needs a real pickup point that is not where the rider stands.
  final canReturn = nearDrop && pickup.isNotEmpty && pLat != null && pLng != null &&
      haversineMeters(pLat, pLng, dropLat, dropLng) > 200;

  if (canReturn) {
    final name = _shortName(pickup, drop);
    return BookAgainPlan(
      isReturn: true,
      fromLabel: drop,
      dropAddress: pickup,
      dropLat: pLat,
      dropLng: pLng,
      title: 'Return to $name',
      cta: 'Book return to $name',
    );
  }
  final name = _shortName(drop, pickup);
  return BookAgainPlan(
    isReturn: false,
    fromLabel: pickup.isNotEmpty ? pickup : 'Current location',
    dropAddress: drop,
    dropLat: dropLat,
    dropLng: dropLng,
    title: 'Book again to $name',
    cta: 'Book This Ride Again',
  );
}

/// A "Book again" / return trip longer than this goes to Outstation (another
/// city), not the in-city taxi screen.
const double kOutstationReturnKm = 30;

double haversineKm(double lat1, double lng1, double lat2, double lng2) =>
    haversineMeters(lat1, lng1, lat2, lng2) / 1000;
