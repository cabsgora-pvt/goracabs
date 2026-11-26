import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'polyline_utils.dart';

/// The points a past trip's map can show. A missing point (null, non-finite
/// or 0) is left out — it used to become LatLng(0, 0), a pin in the Gulf of
/// Guinea that the camera then fitted the whole map around.
class TripMapPoints {
  final LatLng? pickup;
  final LatLng? drop;
  /// The saved route, else the straight line between the points there are.
  final List<LatLng> route;
  const TripMapPoints(this.pickup, this.drop, this.route);

  static double? _c(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return d == null || !d.isFinite || d == 0 ? null : d;
  }

  static LatLng? _pt(dynamic lat, dynamic lng) {
    final a = _c(lat), b = _c(lng);
    return a == null || b == null ? null : LatLng(a, b);
  }

  factory TripMapPoints.of(Map<String, dynamic> ride) {
    final p = _pt(ride['pickupLat'], ride['pickupLng']);
    final d = _pt(ride['dropLat'], ride['dropLng']);
    final encoded = (ride['routePolyline'] ?? '').toString();
    var route = <LatLng>[];
    if (encoded.isNotEmpty) {
      try { route = decodePolyline(encoded); } catch (_) { route = []; }
    }
    if (route.isEmpty) route = [?p, ?d];
    return TripMapPoints(p, d, route);
  }

  bool get isEmpty => pickup == null && drop == null && route.isEmpty;

  /// Where the camera starts.
  LatLng? get center => pickup ?? drop ?? (route.isNotEmpty ? route.first : null);

  /// The bounds to fit, or null with fewer than two distinct points.
  LatLngBounds? get bounds => route.length >= 2 ? boundsFromPoints(route) : null;
}
