import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Navigation engine — the geometry behind turn-by-turn.
//
// Pure functions over the route the server already returns, so it is testable
// and holds no widget state. What it provides that a plain "draw the polyline"
// map cannot:
//
//   • the ACTIVE STEP — the stretch of road the driver is on — and the NEXT
//     STEP, whose manoeuvre comes where this one ends, with how far that is, so
//     we can render "In 200 m turn left onto MG Road"
//   • PROGRESS — the polyline split into travelled and remaining, so the route
//     visibly consumes itself instead of sitting static
//   • OFF-ROUTE detection — perpendicular distance to the route, so we can
//     reroute automatically rather than leaving the driver on a stale line
//   • ARRIVAL — a geofence on the destination so the app can prompt the next
//     action instead of waiting for the driver to notice
//   • STATIONARY detection — Rapido raises the same alert off their SDK's
//     progress callback
// ─────────────────────────────────────────────────────────────────────────────

class NavStep {
  final String instruction;
  final String maneuver;
  final int distanceM;
  final int durationSec;
  final LatLng start;
  final LatLng end;
  /// On a toll road, per the note Google adds to such steps (see the server's
  /// lib/toll-steps.ts). False when unknown.
  final bool toll;

  const NavStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceM,
    required this.durationSec,
    required this.start,
    required this.end,
    this.toll = false,
  });

  static NavStep? fromJson(Map<String, dynamic> j) {
    final sLat = (j['startLat'] as num?)?.toDouble();
    final sLng = (j['startLng'] as num?)?.toDouble();
    final eLat = (j['endLat'] as num?)?.toDouble();
    final eLng = (j['endLng'] as num?)?.toDouble();
    if (sLat == null || sLng == null || eLat == null || eLng == null) return null;
    return NavStep(
      instruction: (j['instruction'] ?? '').toString(),
      maneuver: (j['maneuver'] ?? '').toString(),
      distanceM: (j['distanceM'] as num?)?.toInt() ?? 0,
      durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      start: LatLng(sLat, sLng),
      end: LatLng(eLat, eLng),
      toll: j['toll'] == true,
    );
  }
}

/// Notices when the driver reaches a toll road, so the app can ask about the
/// toll right there — while the plaza and the receipt are in front of them.
///
/// Steps are matched by where they END. The route is re-fetched from the
/// driver's position every 30s, which moves every step's START — keying on the
/// start would make each refresh look like a new toll road. GPS jitter that
/// flips the active step back and forth at a boundary is the same toll road
/// too, so it is asked about once.
class TollWatcher {
  final Set<String> _asked = {};

  static String keyOf(NavStep s) =>
      '${s.end.latitude.toStringAsFixed(4)},${s.end.longitude.toStringAsFixed(4)}';

  /// The toll road just reached, once per toll road, or null.
  NavStep? update({required NavStep? active}) {
    if (active == null || !active.toll) return null;
    return _asked.add(keyOf(active)) ? active : null;
  }

  /// A new destination: nothing carries over.
  void reset() => _asked.clear();
}

/// Where the driver is relative to the route, recomputed on every GPS fix.
class NavProgress {
  /// Index of the nearest point on the route polyline.
  final int nearestIndex;

  /// Metres from the driver to the route line.
  final double offRouteM;

  /// Metres remaining along the route to the destination.
  final double remainingM;

  /// The step the driver is on now — the road being driven (null when steps
  /// are absent). Its instruction is the manoeuvre that brought them onto it:
  /// a turn already taken.
  final NavStep? activeStep;

  /// The manoeuvre ahead: the step after [activeStep], which begins where it
  /// ends. Null on the last step, where what lies ahead is the destination.
  ///
  /// This, not [activeStep], is what the banner shows and the voice counts
  /// down to. Both used the active step, so they were a turn behind: on the
  /// ring road they still said "Turn left onto the ring road", with the
  /// distance to the right turn off it.
  final NavStep? nextStep;

  /// Metres until the end of the active step: where [nextStep]'s manoeuvre is,
  /// or the destination on the last step.
  final double toManeuverM;

  const NavProgress({
    required this.nearestIndex,
    required this.offRouteM,
    required this.remainingM,
    required this.activeStep,
    required this.toManeuverM,
    this.nextStep,
  });
}

const double _earthR = 6371000; // metres

double _rad(double d) => d * math.pi / 180;

/// Haversine metres between two coordinates.
double metersBetween(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final la1 = _rad(a.latitude);
  final la2 = _rad(b.latitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(la1) * math.cos(la2);
  return _earthR * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Where [p] falls along the segment [a]–[b], 0..1, and how far from it, in
/// metres.
///
/// Uses a local equirectangular projection: over the tens of metres that matter
/// for off-route detection the distortion is far below GPS noise.
({double t, double distM}) _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final latRef = _rad((a.latitude + b.latitude) / 2);
  double x(LatLng q) => _rad(q.longitude) * math.cos(latRef) * _earthR;
  double y(LatLng q) => _rad(q.latitude) * _earthR;

  final px = x(p), py = y(p);
  final ax = x(a), ay = y(a);
  final bx = x(b), by = y(b);

  final dx = bx - ax, dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return (t: 0, distM: math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)));

  var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return (t: t, distM: math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)));
}

/// Cumulative metres from each polyline vertex to the end of the route.
List<double> remainingDistances(List<LatLng> route) {
  final out = List<double>.filled(route.length, 0);
  for (var i = route.length - 2; i >= 0; i--) {
    out[i] = out[i + 1] + metersBetween(route[i], route[i + 1]);
  }
  return out;
}

/// Where each step ends on [route]: the index of the route point nearest to
/// its end, searched forward from the previous step's, so a route that passes
/// a junction twice is read in order. Work it out once per route and pass it
/// to [computeProgress].
List<int> stepEndIndices(List<LatLng> route, List<NavStep> steps) {
  final out = <int>[];
  var from = 0;
  for (final st in steps) {
    var best = from;
    var bestD = double.infinity;
    for (var k = from; k < route.length; k++) {
      final d = metersBetween(route[k], st.end);
      if (d < bestD) { bestD = d; best = k; }
    }
    out.add(best);
    from = best;
  }
  return out;
}

/// Locates the driver on the route and picks the manoeuvre they are heading to.
///
/// [stepEnds] is [stepEndIndices] for this route and these steps; it is worked
/// out here when not given.
NavProgress computeProgress({
  required LatLng me,
  required List<LatLng> route,
  required List<double> remaining,
  required List<NavStep> steps,
  List<int>? stepEnds,
}) {
  if (route.length < 2) {
    return const NavProgress(
      nearestIndex: 0, offRouteM: 0, remainingM: 0, activeStep: null, toManeuverM: 0,
    );
  }

  var bestIdx = 0;
  var bestDist = double.infinity;
  var bestT = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final hit = _projectOnSegment(me, route[i], route[i + 1]);
    if (hit.distM < bestDist) { bestDist = hit.distM; bestIdx = i; bestT = hit.t; }
  }

  // Metres left to the destination along the route, from the driver's point on
  // the nearest segment — not from the segment's start, which on a long
  // straight could be kilometres behind.
  final remainingM = bestIdx + 1 < remaining.length
      ? remaining[bestIdx + 1] + (1 - bestT) * metersBetween(route[bestIdx], route[bestIdx + 1])
      : (bestIdx < remaining.length ? remaining[bestIdx] : 0.0);

  // The active step is the first whose END is still ahead, measured on the
  // same scale: metres left to the destination along the route. Distances as
  // the crow flies cannot tell: the old test, `toStart < toEnd + length`, holds
  // for almost every step already driven — two sides of a triangle outweigh the
  // third — so after a turn the driver stayed "on" the road before it until
  // the next route refresh, and the banner counted up to the turn just taken.
  final ends = stepEnds != null && stepEnds.length == steps.length ? stepEnds : stepEndIndices(route, steps);
  NavStep? active;
  var activeIdx = -1;
  var toManeuver = 0.0;
  for (var i = 0; i < steps.length; i++) {
    final endIdx = ends[i];
    final endRemaining = endIdx < remaining.length ? remaining[endIdx] : 0.0;
    if (endRemaining < remainingM - 25) {
      active = steps[i];
      activeIdx = i;
      toManeuver = remainingM - endRemaining;
      break;
    }
  }
  if (active == null && steps.isNotEmpty) {
    // Within the last few metres of every step: the final stretch.
    active = steps.last;
    activeIdx = steps.length - 1;
    toManeuver = remainingM;
  }

  return NavProgress(
    nearestIndex: bestIdx,
    offRouteM: bestDist,
    remainingM: remainingM,
    activeStep: active,
    nextStep: activeIdx >= 0 && activeIdx + 1 < steps.length ? steps[activeIdx + 1] : null,
    toManeuverM: toManeuver,
  );
}

/// Human distance for a manoeuvre banner: "250 m", "1.2 km".
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100 ? (meters / 10).round() * 10 : (meters / 50).round() * 50;
    return '${rounded <= 0 ? 10 : rounded} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Maps a Google manoeuvre string to a compact turn glyph direction.
/// Returns one of: left, right, slight-left, slight-right, sharp-left,
/// sharp-right, uturn, straight, merge, roundabout, depart, arrive.
String maneuverKind(String maneuver) {
  final m = maneuver.toLowerCase();
  if (m.contains('uturn')) return 'uturn';
  if (m.contains('roundabout') || m.contains('rotary')) return 'roundabout';
  if (m.contains('merge')) return 'merge';
  if (m.contains('sharp-left')) return 'sharp-left';
  if (m.contains('sharp-right')) return 'sharp-right';
  if (m.contains('slight-left')) return 'slight-left';
  if (m.contains('slight-right')) return 'slight-right';
  if (m.contains('left')) return 'left';
  if (m.contains('right')) return 'right';
  if (m.contains('depart')) return 'depart';
  if (m.contains('arrive')) return 'arrive';
  return 'straight';
}

/// Thresholds tuned for city driving.
class NavThresholds {
  /// Beyond this from the route line, treat the driver as off-route.
  static const double offRouteM = 60;

  /// Consecutive off-route fixes before rerouting, so one bad fix cannot
  /// trigger a reroute storm.
  static const int offRouteStrikes = 3;

  /// Within this of the destination, consider the leg arrived.
  static const double arrivalM = 60;

  /// No movement beyond this radius for [stationarySec] means stopped.
  static const double stationaryM = 25;
  static const int stationarySec = 120;
}
