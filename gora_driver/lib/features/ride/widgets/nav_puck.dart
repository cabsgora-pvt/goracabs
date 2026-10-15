import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The driver's own map marker.
//
// This existed only as BitmapDescriptor.defaultMarkerWithHue(hueAzure) — a
// generic blue teardrop pin. The RIDER already saw a proper top-down vehicle
// sprite for this same driver, so the person actually navigating had the worst
// marker in the system.
//
// Two shapes, because one does not work for both jobs:
//
//   sprite   — top-down vehicle art, for the flat north-up overview (idle, or
//              reviewing the route). Reads as "your car is here".
//   chevron  — a directional puck, for active turn-by-turn. At 50-60° tilt a
//              top-down car looks like it is lying on its roof; every nav app
//              switches to an arrow for exactly this reason.
//
// Both are cached and neither can throw: a missing asset falls back to the
// drawn chevron, and a failed draw falls back to the default pin, so the driver
// can never end up with no marker at all.
// ─────────────────────────────────────────────────────────────────────────────

class NavPuck {
  NavPuck._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Maps a vehicle type name to its top-down sprite. Matching is loose on
  /// purpose — admin names vehicle types freely ("Cab Economy", "Bike Lite").
  static String assetFor(String vehicleType) {
    final t = vehicleType.toLowerCase();
    if (t.contains('scooter') || t.contains('scooty')) return 'assets/images/topview/scooter-top.png';
    if (t.contains('bike') || t.contains('moto') || t.contains('two')) return 'assets/images/topview/bike-top.png';
    if (t.contains('ev') && (t.contains('auto') || t.contains('rick'))) return 'assets/images/topview/ev-auto-top.png';
    if (t.contains('auto') || t.contains('rick')) return 'assets/images/topview/auto-top.png';
    if (t.contains('suv') || t.contains('xl') || t.contains('7')) return 'assets/images/topview/suv-top.png';
    if (t.contains('prime') || t.contains('premium') || t.contains('primium') || t.contains('luxury')) {
      return 'assets/images/topview/primium-top.png';
    }
    return 'assets/images/topview/economy-top.png';
  }

  /// Top-down vehicle sprite for [vehicleType]. Never throws.
  static Future<BitmapDescriptor> vehicle(String vehicleType, {int width = 96}) async {
    final asset = assetFor(vehicleType);
    final key = 'v:$asset@$width';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final d = await _fromAsset(asset, width: width);
      _cache[key] = d;
      return d;
    } catch (_) {
      return chevron();
    }
  }

  /// Directional navigation puck — a white-ringed disc with a bright chevron.
  /// Drawn rather than shipped so it needs no asset and scales cleanly.
  static Future<BitmapDescriptor> chevron({double size = 110}) async {
    final key = 'c:$size';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final c = Offset(size / 2, size / 2);
      final r = size / 2;

      // Soft shadow so the puck lifts off the basemap at tilt.
      canvas.drawCircle(
        c.translate(0, size * 0.02),
        r * 0.78,
        Paint()
          ..color = Colors.black.withOpacity(0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // White ring — the standard nav-puck read, works on light and dark maps.
      canvas.drawCircle(c, r * 0.74, Paint()..color = Colors.white);
      canvas.drawCircle(c, r * 0.62, Paint()..color = AppColors.primary);

      // Chevron pointing "up" — the marker is drawn with rotation applied by
      // the map, and flat:true keeps it lying on the ground plane.
      final p = Path();
      final h = size * 0.30;   // half-height of the arrow
      final w = size * 0.21;   // half-width
      p.moveTo(c.dx, c.dy - h);                 // tip
      p.lineTo(c.dx + w, c.dy + h * 0.62);      // right shoulder
      p.lineTo(c.dx, c.dy + h * 0.22);          // notch
      p.lineTo(c.dx - w, c.dy + h * 0.62);      // left shoulder
      p.close();
      canvas.drawPath(p, Paint()..color = Colors.white);

      final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final d = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
      _cache[key] = d;
      return d;
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  static Future<BitmapDescriptor> _fromAsset(String path, {int width = 96}) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}

/// Bearing in degrees from [a] to [b].
///
/// Used to point the puck when the device gives no heading — a phone that is
/// stationary or has a poor compass reports heading 0, which would otherwise
/// snap the marker to due north mid-journey.
double bearingBetween(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final deg = math.atan2(y, x) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// Shortest-path interpolation between two bearings.
///
/// Naive lerp from 350° to 10° spins the long way round through 180°; this
/// takes the 20° route, so the puck never pirouettes at a heading wrap.
double lerpBearing(double from, double to, double t) {
  final diff = (to - from + 540) % 360 - 180;
  return (from + diff * t + 360) % 360;
}
