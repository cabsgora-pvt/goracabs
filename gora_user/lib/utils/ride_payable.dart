import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// What a rider pays when a ride completes.
//
// Every booking screen used to work this out for itself, from its own local
// variables, which is why each one charged something slightly different. The
// live ride screen now tracks every service, so the rule lives in one place.
// ─────────────────────────────────────────────────────────────────────────────

num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// The amount charged to the rider for [ride] at completion.
///
/// Mirrors the `billable` figure in the server's /rides/{id}/complete: a
/// service's own final amount when it has one — a rental's `finalFare`, a
/// hire's `hireFinalFare`, a parcel's `deliveryFinalFare` — and the booked
/// `fare` otherwise, plus any `tip` the rider added at booking. So a rental
/// that ran over is charged its extras, as the driver is settled on them, and
/// a taxi booked with a tip is charged the tip too — the server already
/// credits the full tip to the driver's earnings at settlement
/// (`driverEarning = ... + tip` in /rides/{id}/complete), so leaving it off
/// the rider's charge used to mean the driver was paid a tip nobody actually
/// handed over.
///
/// A multi-stop `waitingChargeTotal` is still deliberately NOT added: no
/// screen has ever charged it, and adding it here would silently raise what
/// riders pay. The server credits it to the driver at settlement regardless,
/// so it remains a known gap in the payment flow, to be decided there rather
/// than slipped in here.
///
/// [couponDiscount] is subtracted for every service except rental. Only a
/// rental's coupon is applied by the server at booking; for the rest the server
/// stores the full quoted fare and the discount exists only on the phone. A
/// rental's `fare` and `finalFare` already include its discount, so taking it
/// off again would undercharge.
///
/// `splitCollected` — what co-riders already paid through
/// /rides/{id}/split/pay — is subtracted before the coupon, mirroring
/// /rides/{id}/complete exactly: split covers a share of the fare, never the
/// tip, so it comes off `billable` before tip is added back on.
num riderPayable(Map<String, dynamic> ride, {num couponDiscount = 0}) {
  final service = '${ride['service'] ?? ''}';
  final num serviceFinal = switch (service) {
    'rental' => _n(ride['finalFare']),
    'hire_driver' => _n(ride['hireFinalFare']),
    'delivery' => _n(ride['deliveryFinalFare']),
    _ => 0,
  };
  final base = serviceFinal > 0 ? serviceFinal : _n(ride['fare']);
  final splitCollected = _n(ride['splitCollected']);
  final billable = (base - splitCollected).clamp(0, base) + _n(ride['tip']);
  if (service == 'rental' || couponDiscount <= 0) return billable;
  return (billable - couponDiscount).clamp(0, billable);
}

/// The coupon discount a ride was booked with, kept on this device.
///
/// The server does not record it for non-rental rides (see [riderPayable]), so
/// without this a ride reopened after the app was closed would be charged the
/// full fare, while the same ride tracked without a restart was charged the
/// discounted one. Stored per ride, and cleared once the ride is settled.
class RideCouponStore {
  static String _key(String rideId) => 'ride_coupon_$rideId';

  static Future<void> save(String rideId, num discount) async {
    if (rideId.isEmpty || discount <= 0) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_key(rideId), discount.toDouble());
    } catch (_) {/* best effort: the ride still charges, without the discount */}
  }

  static Future<num> load(String rideId) async {
    if (rideId.isEmpty) return 0;
    try {
      final p = await SharedPreferences.getInstance();
      return p.getDouble(_key(rideId)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clear(String rideId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(rideId));
    } catch (_) {}
  }
}
