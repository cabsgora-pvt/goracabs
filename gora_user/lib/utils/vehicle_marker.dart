import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Vehicle map markers.
//
// The top-down vehicle art already shipped in assets/images/topview/ and the
// home screen already used it for the idle "vehicles nearby" layer — but the
// ASSIGNED driver, the one actually coming to collect the rider, was drawn as a
// generic blue pin on every tracking screen. This centralises the icon lookup
// so the car the rider watches approach is the car they were shown, and adds
// the motion that makes it read as a moving vehicle rather than a jumping dot.
// ─────────────────────────────────────────────────────────────────────────────

class VehicleMarkers {
  VehicleMarkers._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Maps a vehicle type name to its top-down sprite.
  /// Matching is loose on purpose — admin names the types freely
  /// ("Cab Economy", "Prime Sedan", "Auto", "Bike Lite"…).
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

  /// Cached marker bitmap for a vehicle type. Never throws — falls back to a
  /// drawn glyph, then to the default pin, so a missing asset cannot blank the
  /// driver off the rider's map.
  static Future<BitmapDescriptor> descriptorFor(String vehicleType, {int width = 96}) async {
    final asset = assetFor(vehicleType);
    final key = '$asset@$width';
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final d = await _fromAsset(asset, width: width);
      _cache[key] = d;
      return d;
    } catch (_) {
      try {
        final d = await _fromIcon(Icons.local_taxi, AppTheme.primaryBlue);
        _cache[key] = d;
        return d;
      } catch (_) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }
    }
  }

  static Future<BitmapDescriptor> _fromAsset(String path, {int width = 96}) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor> _fromIcon(IconData icon, Color color, {double size = 84}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = size / 2;
    canvas.drawCircle(Offset(r, r), r, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(r, r),
      r,
      Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.62,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}

/// Bearing in degrees from [a] to [b] — used when the server sends no heading,
/// so the vehicle still points the way it is travelling.
double bearingBetween(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final deg = math.atan2(y, x) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// Shortest-path angle lerp, so 350° → 10° turns +20° rather than -340°.
double _lerpBearing(double from, double to, double t) {
  var diff = (to - from + 540) % 360 - 180;
  return (from + diff * t + 360) % 360;
}

/// Glides a vehicle marker between server updates.
///
/// The driver's position arrives every ~5 s. Snapping the marker to each fix
/// makes the vehicle teleport; interpolating over the gap makes it drive. Also
/// eases the bearing so the icon banks into turns instead of snapping around.
class SmoothVehicleMarker {
  SmoothVehicleMarker({required TickerProvider vsync, required this.onUpdate})
      : _ctrl = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 1400),
        ) {
    _ctrl.addListener(_tick);
  }

  final AnimationController _ctrl;
  final VoidCallback onUpdate;

  LatLng? _from;
  LatLng? _to;
  double _fromBearing = 0;
  double _toBearing = 0;

  LatLng? position;
  double bearing = 0;

  bool get hasPosition => position != null;

  void _tick() {
    final a = _from, b = _to;
    if (a == null || b == null) return;
    final t = Curves.easeOutCubic.transform(_ctrl.value);
    position = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    bearing = _lerpBearing(_fromBearing, _toBearing, t);
    onUpdate();
  }

  /// Feeds a new server fix. [heading] is used when supplied and non-zero,
  /// otherwise the bearing is derived from the movement itself.
  void moveTo(LatLng target, {double? heading}) {
    final current = position;
    if (current == null) {
      position = target;
      bearing = heading ?? 0;
      onUpdate();
      return;
    }
    // Ignore jitter — re-animating over a metre of GPS noise looks like a twitch.
    final moved = (target.latitude - current.latitude).abs() > 1e-6 ||
        (target.longitude - current.longitude).abs() > 1e-6;
    if (!moved) return;

    _from = current;
    _to = target;
    _fromBearing = bearing;
    _toBearing = (heading != null && heading > 0) ? heading : bearingBetween(current, target);
    _ctrl
      ..reset()
      ..forward();
  }

  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
  }
}

/// One ambient vehicle on the idle map.
class _AmbientVeh {
  _AmbientVeh({
    required this.from,
    required this.to,
    required this.fromBearing,
    required this.toBearing,
    required this.icon,
  });

  LatLng from;
  LatLng to;
  double fromBearing;
  double toBearing;
  BitmapDescriptor icon;

  LatLng positionAt(double t) => LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );

  double bearingAt(double t) => _lerpBearing(fromBearing, toBearing, t);
}

/// Drifts the "vehicles nearby" layer on the idle home map.
///
/// Deliberately NOT one SmoothVehicleMarker per driver: that would mean up to
/// 40 AnimationControllers, each with its own ticker. This keeps a SINGLE
/// controller and diffs the set by driver id, so a vehicle that persists
/// between polls glides from where it currently appears to its new fix, one
/// that is new snaps in, and one that dropped out disappears.
class AmbientVehicleFleet {
  AmbientVehicleFleet({
    required TickerProvider vsync,
    required this.onUpdate,
    Duration duration = const Duration(seconds: 4),
  }) : _ctrl = AnimationController(vsync: vsync, duration: duration) {
    _ctrl.addListener(onUpdate);
  }

  final AnimationController _ctrl;
  final VoidCallback onUpdate;
  final Map<String, _AmbientVeh> _fleet = {};

  bool get isEmpty => _fleet.isEmpty;

  /// Feeds a fresh batch from /rides/nearby-drivers.
  Future<void> update(List<Map<String, dynamic>> drivers) async {
    final t = Curves.easeInOut.transform(_ctrl.value);
    final next = <String, _AmbientVeh>{};

    for (final d in drivers) {
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final id = (d['id'] ?? '$lat,$lng').toString();
      final target = LatLng(lat, lng);
      final heading = (d['heading'] as num?)?.toDouble();

      final prev = _fleet[id];
      final icon = prev?.icon ?? await VehicleMarkers.descriptorFor((d['vehicleType'] ?? '').toString());

      if (prev == null) {
        // New vehicle — snap it in rather than flying it across the map.
        next[id] = _AmbientVeh(
          from: target, to: target,
          fromBearing: heading ?? 0, toBearing: heading ?? 0,
          icon: icon,
        );
      } else {
        final currentPos = prev.positionAt(t);
        next[id] = _AmbientVeh(
          from: currentPos,
          to: target,
          fromBearing: prev.bearingAt(t),
          toBearing: (heading != null && heading > 0) ? heading : bearingBetween(currentPos, target),
          icon: icon,
        );
      }
    }

    _fleet
      ..clear()
      ..addAll(next);
    _ctrl
      ..reset()
      ..forward();
    onUpdate();
  }

  void clear() {
    if (_fleet.isEmpty) return;
    _fleet.clear();
    onUpdate();
  }

  Set<Marker> get markers {
    final t = Curves.easeInOut.transform(_ctrl.value);
    return _fleet.entries.map((e) {
      final v = e.value;
      return Marker(
        markerId: MarkerId('veh_${e.key}'),
        position: v.positionAt(t),
        icon: v.icon,
        anchor: const Offset(0.5, 0.5),
        rotation: v.bearingAt(t),
        flat: true,
      );
    }).toSet();
  }

  void dispose() {
    _ctrl.removeListener(onUpdate);
    _ctrl.dispose();
  }
}
