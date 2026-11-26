// ─────────────────────────────────────────────────────────────────────────────
// "Driver is 1.2 km · 4 min away" on the live ride screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'book_again.dart' show haversineMeters;
import 'duration_format.dart';

/// "450 m" / "1.2 km" / "12 km".
String formatDistanceM(double meters) {
  if (meters < 0 || !meters.isFinite) return '';
  if (meters < 1000) {
    final m = (meters / 10).round() * 10;
    return '${m < 10 ? 10 : m} m';
  }
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// Live distance and time from the driver to where they are heading.
///
/// [roadFactor] is road length ÷ straight line, measured at the last
/// Directions (ETA) call, so the straight-line distance recomputed on every
/// location poll still reads like a road distance. [etaMin] / [etaAtM] are that
/// call's minutes and the straight-line distance it was measured at: the time
/// is scaled by how much closer the driver has got since, so it too moves
/// with each poll instead of every 30 s. Returns (metres, minutes); minutes is
/// null while no ETA has come back yet.
(double, int?) liveDistanceAndEta({
  required double driverLat,
  required double driverLng,
  required double destLat,
  required double destLng,
  double? roadFactor,
  int? etaMin,
  double? etaAtM,
}) {
  final straight = haversineMeters(driverLat, driverLng, destLat, destLng);
  final f = (roadFactor == null || !roadFactor.isFinite) ? 1.0 : roadFactor.clamp(1.0, 3.0);
  final meters = straight * f;
  int? mins;
  if (etaMin != null) {
    if (etaAtM != null && etaAtM > 50) {
      mins = (etaMin * (straight / etaAtM)).round();
      // Never more than the call said (the driver only gets closer between
      // calls in the rider's eyes), never "0 min" while still on the way.
      if (mins > etaMin) mins = etaMin;
    } else {
      mins = etaMin;
    }
    if (mins < 1) mins = 1;
  }
  return (meters, mins);
}

/// "Driver is 1.2 km · 4 min away" (approaching the pickup) or
/// "1.2 km · 4 min to drop" (on the trip). Null when there is nothing to say.
String? driverAwayLine({required double meters, int? mins, required bool toPickup}) {
  final d = formatDistanceM(meters);
  if (d.isEmpty) return null;
  final parts = [d, if (mins != null) formatMinutes(mins)].join(' · ');
  return toPickup ? 'Driver is $parts away' : '$parts to drop';
}
