import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Destination markers for the driver's navigation map.
//
// The same flat glyphs the rider sees on their side of the same ride — a green
// dot where someone is picked up, a dark square where they are dropped, and a
// numbered disc for a stop along the way — so both ends of a trip describe the
// destination the same way. The driver map used Google's default teardrop pins,
// which say nothing about what kind of place the driver is heading to.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceMarkers {
  PlaceMarkers._();

  // Caches the draw itself, not just its result: two map widgets asking for the
  // same glyph in the same frame share one draw instead of racing two.
  static final Map<String, Future<BitmapDescriptor>> _cache = {};
  static const double _size = 30;

  static Future<BitmapDescriptor> pickup(double dpr) =>
      _cached('pickup@$dpr', () => _draw(dpr, fill: const Color(0xFF16A34A), square: false));

  static Future<BitmapDescriptor> drop(double dpr) =>
      _cached('drop@$dpr', () => _draw(dpr, fill: const Color(0xFF111827), square: true));

  static Future<BitmapDescriptor> stop(double dpr, int number) =>
      _cached('stop$number@$dpr', () => _draw(dpr, fill: const Color(0xFFF59E0B), square: false, number: number));

  /// Where the leg ends is somewhere a person gets in: the pickup, the customer
  /// a hired driver goes to, a parcel's sender, or the start of a round trip.
  static bool isPickupLike(String legLabel) {
    final l = legLabel.toLowerCase();
    return l.contains('pickup') || l.contains('customer') || l.contains('sender') || l.contains('start');
  }

  /// The stop number in a "Stop 3" leg label, or null.
  static int? stopNumber(String legLabel) {
    final m = RegExp(r'^\s*stop\s+(\d+)', caseSensitive: false).firstMatch(legLabel);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The glyph for a navigation leg, from its label.
  static Future<BitmapDescriptor> forLeg(String legLabel, double dpr) {
    final n = stopNumber(legLabel);
    if (n != null) return stop(dpr, n);
    return isPickupLike(legLabel) ? pickup(dpr) : drop(dpr);
  }

  /// Google's pin in the matching colour, for the frame before a glyph is drawn.
  static BitmapDescriptor fallbackForLeg(String legLabel) => BitmapDescriptor.defaultMarkerWithHue(
        stopNumber(legLabel) != null
            ? BitmapDescriptor.hueOrange
            : isPickupLike(legLabel) ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
      );

  static Future<BitmapDescriptor> _cached(String key, Future<BitmapDescriptor> Function() build) =>
      _cache.putIfAbsent(key, () => build().catchError((Object _) {
        // Not cached, so a later request tries the draw again.
        _cache.remove(key);
        return BitmapDescriptor.defaultMarkerWithHue(
          key.startsWith('pickup')
              ? BitmapDescriptor.hueGreen
              : key.startsWith('stop') ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed,
        );
      }));

  /// Drawn at physical resolution with its LOGICAL width declared, so it is the
  /// same physical size — and sharp — on every screen density.
  static Future<BitmapDescriptor> _draw(double dpr, {required Color fill, required bool square, int? number}) async {
    final px = (_size * dpr).ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(px / 2, px / 2);
    final ringR = px * 0.40;
    final innerR = number != null ? px * 0.31 : px * 0.27;

    // Soft shadow so the glyph lifts off both the day and the night basemap.
    canvas.drawCircle(
      c.translate(0, px * 0.04), ringR,
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.06),
    );
    if (square) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: ringR), Radius.circular(px * 0.12)),
          Paint()..color = Colors.white);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: innerR), Radius.circular(px * 0.06)),
          Paint()..color = fill);
    } else {
      canvas.drawCircle(c, ringR, Paint()..color = Colors.white);
      canvas.drawCircle(c, innerR, Paint()..color = fill);
    }
    if (number != null) {
      final label = TextPainter(
        text: TextSpan(
          text: '$number',
          style: TextStyle(color: Colors.white, fontSize: px * (number > 9 ? 0.28 : 0.36), fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    }
    final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: _size);
  }
}
