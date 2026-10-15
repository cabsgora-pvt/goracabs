import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pickup / drop markers and the "searching for a driver" radar.
//
// Pickup and drop were Google's default teardrop pins — the generic look of a
// maps demo. Ride apps use small, flat glyphs instead: a dot where you are
// picked up and a square where you are dropped. They read at a glance, never
// hide the road under a pin's bulk, and stay visually distinct from the vehicle.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceMarkers {
  PlaceMarkers._();

  // Caches the draw itself, not just its result: two maps asking for the same
  // glyph in the same frame share one draw instead of racing two.
  static final Map<String, Future<BitmapDescriptor>> _cache = {};

  /// Default logical size on the map, in points.
  static const double defaultSize = 26;

  /// Pickup: a green dot inside a white ring.
  ///
  /// [size] is in logical points. A marker the rider must press and drag needs
  /// to be larger than one they only look at.
  static Future<BitmapDescriptor> pickup(double devicePixelRatio, {double size = defaultSize}) =>
      _cached('pickup@$devicePixelRatio@$size', () => _draw(
        devicePixelRatio,
        size: size,
        fill: const Color(0xFF16A34A),
        square: false,
      ));

  /// Drop: a dark square inside a white ring.
  static Future<BitmapDescriptor> drop(double devicePixelRatio, {double size = defaultSize}) =>
      _cached('drop@$devicePixelRatio@$size', () => _draw(
        devicePixelRatio,
        size: size,
        fill: const Color(0xFF111827),
        square: true,
      ));

  /// A stop added along the way: its number on an amber disc, so the rider can
  /// tell which destination is which — a row of identical pins could not.
  static Future<BitmapDescriptor> stop(double devicePixelRatio, int number) =>
      _cached('stop$number@$devicePixelRatio', () => _drawNumbered(devicePixelRatio, number));

  static Future<BitmapDescriptor> _drawNumbered(double dpr, int number) async {
    const size = 30.0;
    final px = (size * dpr).ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(px / 2, px / 2);
    canvas.drawCircle(
      c.translate(0, px * 0.04), px * 0.42,
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.06),
    );
    canvas.drawCircle(c, px * 0.42, Paint()..color = Colors.white);
    canvas.drawCircle(c, px * 0.33, Paint()..color = const Color(0xFFF59E0B));
    final label = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(color: Colors.white, fontSize: px * (number > 9 ? 0.30 : 0.38), fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: size);
  }

  static Future<BitmapDescriptor> _cached(
    String key,
    Future<BitmapDescriptor> Function() build,
  ) =>
      _cache.putIfAbsent(key, () => build().catchError((Object _) {
        // Never leave a place unmarked: a failed draw falls back to a default
        // pin in the same colour family — uncached, so a later request draws
        // again.
        _cache.remove(key);
        return BitmapDescriptor.defaultMarkerWithHue(
          key.startsWith('pickup')
              ? BitmapDescriptor.hueGreen
              : key.startsWith('stop') ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed,
        );
      }));

  /// Draws the glyph at physical resolution and declares its LOGICAL width.
  ///
  /// The older `BitmapDescriptor.fromBytes` is deprecated and treats the image's
  /// pixel size as its on-map size, so a bitmap that looks right on a 1x screen
  /// renders at a third of the size on a 3x phone. Rendering at size x DPR and
  /// passing `width` keeps the glyph the same physical size — and sharp — on
  /// every screen density.
  static Future<BitmapDescriptor> _draw(
    double dpr, {
    required double size,
    required Color fill,
    required bool square,
  }) async {
    final px = (size * dpr).ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(px / 2, px / 2);

    // Soft shadow so the glyph lifts off both the light and the night basemap.
    canvas.drawCircle(
      c.translate(0, px * 0.04),
      px * 0.40,
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.06),
    );

    final ringR = px * 0.40;
    final innerR = px * 0.27;
    if (square) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: ringR),
            Radius.circular(px * 0.12)),
        Paint()..color = Colors.white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: innerR),
            Radius.circular(px * 0.06)),
        Paint()..color = fill,
      );
    } else {
      canvas.drawCircle(c, ringR, Paint()..color = Colors.white);
      canvas.drawCircle(c, innerR, Paint()..color = fill);
    }

    final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: size);
  }
}

/// The pickup and drop markers for one map, and where each is anchored.
///
/// Until the glyphs are drawn this holds Google's default pins, which point
/// with their tip — hence the anchors travel with the icons.
class PlaceGlyphSet {
  final BitmapDescriptor pickup;
  final BitmapDescriptor drop;
  final Offset pickupAnchor;
  final Offset dropAnchor;
  const PlaceGlyphSet._(this.pickup, this.drop, this.pickupAnchor, this.dropAnchor);

  static final fallback = PlaceGlyphSet._(
    BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    const Offset(0.5, 1.0),
    const Offset(0.5, 1.0),
  );
}

/// Builds [builder] with the flat pickup and drop markers, drawn for this
/// screen's pixel density.
///
/// For maps that live in a stateless screen or a bottom-sheet builder, where
/// there is no State of their own to load bitmaps into.
class PlaceGlyphs extends StatefulWidget {
  final Widget Function(BuildContext context, PlaceGlyphSet glyphs) builder;
  final double size;
  const PlaceGlyphs({super.key, required this.builder, this.size = PlaceMarkers.defaultSize});

  @override
  State<PlaceGlyphs> createState() => _PlaceGlyphsState();
}

class _PlaceGlyphsState extends State<PlaceGlyphs> {
  PlaceGlyphSet _set = PlaceGlyphSet.fallback;
  double? _dpr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr == _dpr) return;
    _dpr = dpr;
    Future.wait([
      PlaceMarkers.pickup(dpr, size: widget.size),
      PlaceMarkers.drop(dpr, size: widget.size),
    ]).then((d) {
      if (mounted) {
        setState(() => _set = PlaceGlyphSet._(d[0], d[1], const Offset(0.5, 0.5), const Offset(0.5, 0.5)));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _set);
}

// ─────────────────────────────────────────────────────────────────────────────
// Searching radar.
//
// Its own StatefulWidget on purpose: the ride screen uses
// SingleTickerProviderStateMixin, already claimed by the vehicle animation, and
// a second AnimationController on that mixin throws. A separate widget owns its
// own ticker, and its animation stops when it leaves the tree.
// ─────────────────────────────────────────────────────────────────────────────

class SearchRadar extends StatefulWidget {
  /// Diameter of the outermost ring at full expansion, in logical points.
  final double size;
  final Color color;

  const SearchRadar({super.key, this.size = 220, this.color = const Color(0xFF16A34A)});

  @override
  State<SearchRadar> createState() => _SearchRadarState();
}

class _SearchRadarState extends State<SearchRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the system "remove animations" accessibility setting: show a
    // single static ring instead of a pulse that some riders find distressing.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      // Purely decorative — it must never swallow a pan or pinch on the map.
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: reduceMotion
              ? CustomPaint(painter: _RadarPainter(0.55, widget.color, rings: 1))
              : AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _RadarPainter(_ctrl.value, widget.color),
                  ),
                ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  final Color color;
  final int rings;
  _RadarPainter(this.t, this.color, {this.rings = 3});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < rings; i++) {
      // Stagger the rings evenly through the cycle so one is always emerging.
      final phase = (t + i / rings) % 1.0;
      // Ease out: rings leave quickly and slow as they widen, like a real ripple.
      final eased = 1 - math.pow(1 - phase, 2).toDouble();
      final r = maxR * eased;
      final alpha = (1 - phase).clamp(0.0, 1.0);
      canvas.drawCircle(c, r, Paint()..color = color.withOpacity(0.18 * alpha));
      canvas.drawCircle(
        c, r,
        Paint()
          ..color = color.withOpacity(0.55 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // A steady core, so the pickup point stays anchored while the rings move.
    canvas.drawCircle(c, 7, Paint()..color = color.withOpacity(0.9));
    canvas.drawCircle(
      c, 7,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.color != color;
}
