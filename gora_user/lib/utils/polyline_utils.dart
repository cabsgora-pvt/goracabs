import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Decodes an encoded Google polyline string into a list of LatLng points.
// Reference: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
    lat += dlat;
    shift = 0; result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
    lng += dlng;
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

// Build LatLngBounds covering a list of points (skip empty)
LatLngBounds? boundsFromPoints(List<LatLng> pts) {
  if (pts.isEmpty) return null;
  double minLat = pts.first.latitude, maxLat = pts.first.latitude;
  double minLng = pts.first.longitude, maxLng = pts.first.longitude;
  for (final p in pts) {
    if (p.latitude  < minLat) minLat = p.latitude;
    if (p.latitude  > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

/// Total length of a polyline in metres.
///
/// Used for trip progress. The route is re-fetched from the driver's CURRENT
/// position on every refresh, so the live polyline's length is exactly the
/// distance still to travel — which makes progress
/// `1 - (currentLength / lengthWhenThisLegStarted)`.
double polylineLengthMeters(List<LatLng> pts) {
  if (pts.length < 2) return 0;
  const r = 6371000.0;
  double total = 0;
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final la1 = a.latitude * math.pi / 180;
    final la2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(la1) * math.cos(la2);
    total += r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
  return total;
}
