import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../../utils/polyline_utils.dart';
import 'nav_engine.dart';
import 'nav_puck.dart';
import 'place_markers.dart';
import 'map_styles.dart';
import 'voice_guide.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Driver navigation, shared by every service.
//
// Beyond drawing a route, this is a working turn-by-turn system built on the
// manoeuvre steps Google already returns on the Directions calls we pay for:
//
//   • a manoeuvre banner — "In 250 m · Turn left onto MG Road"
//   • the route consumes itself: travelled polyline dims, remaining stays bold
//   • automatic reroute when the driver leaves the line (3 strikes, not 1)
//   • arrival detection on a geofence, surfacing the next action in place
//   • stationary detection, the alert Rapido raises off its SDK callback
//   • an expandable full step list, spoken guidance, and hand-off to Google Maps
//
// The public API is unchanged (leg, fallbackPolyline, height, insets,
// showHeader) so every existing call site keeps working untouched.
// ─────────────────────────────────────────────────────────────────────────────

/// One navigation target — "where is the driver heading right now".
class NavLeg {
  final String label;
  final double? destLat;
  final double? destLng;
  final String destAddress;

  const NavLeg({
    required this.label,
    required this.destLat,
    required this.destLng,
    this.destAddress = '',
  });

  bool get isValid => destLat != null && destLng != null && !(destLat == 0 && destLng == 0);
  String get key => '$label:$destLat,$destLng';
  LatLng? get target => isValid ? LatLng(destLat!, destLng!) : null;
}

class NavMapPanel extends StatefulWidget {
  final NavLeg leg;
  final String? fallbackPolyline;
  final double height;
  final bool showHeader;
  final double topInset;
  final double bottomInset;

  /// Fired once when the driver enters the destination geofence. Lets the host
  /// screen surface its own next action (Arrived / Collected / Reached stop).
  final VoidCallback? onArrived;

  /// Fired once as the driver reaches each toll road, so the host can ask about
  /// the toll there and then. Null where tolls are not recorded — and then no
  /// toll prompt is spoken either.
  final ValueChanged<NavStep>? onTollRoad;

  /// Every GPS fix, for a host that needs to know where the driver is (the
  /// location of a toll as it is entered).
  final ValueChanged<LatLng>? onPosition;

  /// The driver's own vehicle type, so their marker is the vehicle they
  /// actually drive rather than a generic pin. Optional: an empty value falls
  /// back to the economy sprite.
  final String vehicleType;

  const NavMapPanel({
    super.key,
    required this.leg,
    this.fallbackPolyline,
    this.height = 260,
    this.showHeader = true,
    this.topInset = 10,
    this.bottomInset = 10,
    this.onArrived,
    this.onTollRoad,
    this.onPosition,
    this.vehicleType = '',
  });

  @override
  State<NavMapPanel> createState() => _NavMapPanelState();
}

class _NavMapPanelState extends State<NavMapPanel> with WidgetsBindingObserver {
  GoogleMapController? _ctrl;
  LatLng? _me;
  double _heading = 0;

  List<LatLng> _route = [];
  List<double> _remaining = [];
  // Where each step ends on the route; worked out once per route.
  List<int> _stepEnds = const [];
  List<NavStep> _steps = [];
  NavProgress? _progress;

  int? _etaMin;
  double? _distKm;
  // Length of THIS leg when it started, so trip progress can be a fraction.
  // It cannot be derived from the live route: every refresh re-routes from the
  // driver's current position, so the fetched polyline always starts at them
  // and "remaining / total" would sit at 0% forever.
  double? _legTotalM;
  bool _following = true;
  // Fingers currently on the map. Counted rather than a bool because a pinch
  // is two pointers, and lifting one must not look like the gesture ended.
  int _mapPointers = 0;

  // Spoken turn-by-turn. The announcer decides what to say and when; the guide
  // just speaks. Kept apart so the timing rules are testable without an engine.
  final VoiceGuide _voice = VoiceGuide();
  final NavAnnouncer _announcer = NavAnnouncer();
  final TollWatcher _tollWatcher = TollWatcher();
  bool _voiceMuted = false;
  // Set when the driver hands navigation to Google Maps, cleared when they come
  // back. Location keeps flowing in the background on purpose, and so did this
  // voice — talking over Google Maps' own, every turn announced twice.
  bool _handedOff = false;
  // Own marker. Vehicle sprite for the flat overview, chevron once navigating —
  // a top-down car at 55 degrees of tilt reads as lying on its roof.
  BitmapDescriptor? _puckVehicle;
  BitmapDescriptor? _puckChevron;
  // Last bearing the camera was driven to, so heading noise while stationary
  // does not make the whole map twitch.
  double _camBearing = 0;
  // Current map zoom, so the route line can be widened to match. Seeded to the
  // initial camera zoom rather than 0, or the first frame draws a hairline.
  double _zoom = 15;
  bool _rerouting = false;
  bool _arrived = false;
  bool _showSteps = false;

  int _offRouteStrikes = 0;
  LatLng? _stationaryAnchor;
  DateTime _stationarySince = DateTime.now();
  bool _stationary = false;

  Timer? _routeTimer;
  StreamSubscription<Position>? _locSub;

  @override
  void initState() {
    super.initState();
    final fb = widget.fallbackPolyline;
    if (fb != null && fb.isNotEmpty) {
      _route = decodePolyline(fb);
      _remaining = remainingDistances(_route);
    }
    _loadPucks();
    WidgetsBinding.instance.addObserver(this);
    _voice.init().then((_) {
      if (!mounted) return;
      setState(() => _voiceMuted = _voice.muted);
      _announcer.language = _voice.language;
      // The first route may already have been fetched in English; fetch it again
      // so the instructions, and so the prompts, are in the driver's language.
      if (_voice.language != VoiceLanguage.english) _fetchRoute();
    });
    _primeLocation();
    // background: true keeps the fix coming when the driver switches to Google
    // Maps or locks the screen — otherwise the route and ETA freeze mid-trip.
    _locSub = LocationService.liveLocation(
      background: true,
      notificationText: 'Navigating to your next stop',
    ).listen(_onPosition, onError: (_) {});
    _routeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchRoute());
  }

  @override
  void didUpdateWidget(covariant NavMapPanel old) {
    super.didUpdateWidget(old);
    if (old.leg.label != widget.leg.label) _loadDestGlyph();
    if (old.leg.key != widget.leg.key) {
      // New destination (pickup→drop, or the rider added a stop) — start clean.
      _route = [];
      _remaining = [];
      _steps = [];
      _stepEnds = const [];
      _progress = null;
      _etaMin = null;
      _distKm = null;
      _legTotalM = null;
      _arrived = false;
      _offRouteStrikes = 0;
      _following = true;
      // A new destination starts announcements over. Deliberately NOT done on
      // the periodic route refresh: steps are keyed by start + instruction, so a
      // refreshed but unchanged step is recognised and not announced twice.
      _announcer.reset();
      _tollWatcher.reset();
      _fetchRoute();
    }
  }

  @override
  void dispose() {
    // Stop mid-sentence rather than let a stale instruction play on after the
    // driver has left this screen.
    WidgetsBinding.instance.removeObserver(this);
    _voice.dispose();
    _locSub?.cancel();
    _routeTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _handedOff) {
      // Back from Google Maps: this app's guidance takes over again.
      _handedOff = false;
    }
  }

  Future<void> _primeLocation() async {
    final p = await LocationService.getCurrentLocation();
    if (p != null) _onPosition(p);
  }

  // Flat destination glyph for the current leg (dot, square or numbered stop).
  BitmapDescriptor? _destGlyph;
  String? _destGlyphKey;
  double? _dpr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr != _dpr) {
      _dpr = dpr;
      _loadDestGlyph();
    }
  }

  Future<void> _loadDestGlyph() async {
    final dpr = _dpr;
    if (dpr == null) return;
    final key = '${widget.leg.label}@$dpr';
    if (key == _destGlyphKey) return;
    _destGlyphKey = key;
    // Until the new leg's glyph is drawn, show its fallback pin — never the
    // previous leg's glyph, which would mark a drop as a pickup.
    // No setState: both callers (a dependency or widget change) rebuild next.
    _destGlyph = null;
    final d = await PlaceMarkers.forLeg(widget.leg.label, dpr);
    if (!mounted || _destGlyphKey != key) return;
    setState(() => _destGlyph = d);
  }

  Future<void> _loadPucks() async {
    final v = await NavPuck.vehicle(widget.vehicleType);
    final c = await NavPuck.chevron();
    if (!mounted) return;
    setState(() { _puckVehicle = v; _puckChevron = c; });
  }

  /// True while we are actively guiding — route loaded, not yet arrived. Drives
  /// both the marker shape and whether the camera tilts into nav mode.
  bool get _navigating => !_arrived && _route.length > 1;

  /// Camera for turn-by-turn: tilted, rotated to travel direction, and aimed a
  /// little AHEAD of the driver so the road they are about to drive fills the
  /// screen instead of the road behind them.
  ///
  /// Zoom tightens approaching a manoeuvre and relaxes afterwards, which is the
  /// behaviour that makes junctions legible without the driver pinching.
  CameraPosition _navCamera(LatLng me) {
    final toTurn = _progress?.toManeuverM;
    double zoom = 16.5;
    if (toTurn != null) {
      if (toTurn < 120) {
        zoom = 18;
      } else if (toTurn < 350) {
        zoom = 17.2;
      }
    }
    // Bias the target forward along the current heading so the puck sits low in
    // frame. Scaled to zoom: less shift when zoomed in, or the puck falls off.
    final aheadM = toTurn != null && toTurn < 120 ? 25.0 : 70.0;
    final rad = _camBearing * math.pi / 180;
    const mPerDegLat = 111320.0;
    final dLat = (aheadM * math.cos(rad)) / mPerDegLat;
    final dLng = (aheadM * math.sin(rad)) /
        (mPerDegLat * math.cos(me.latitude * math.pi / 180));
    return CameraPosition(
      target: LatLng(me.latitude + dLat, me.longitude + dLng),
      zoom: zoom,
      tilt: 55,
      bearing: _camBearing,
    );
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    final me = LatLng(p.latitude, p.longitude);
    final first = _me == null;
    widget.onPosition?.call(me);

    setState(() {
      _me = me;
      if (p.heading.isFinite && p.heading >= 0) _heading = p.heading;
      if (_route.length > 1) {
        _progress = computeProgress(
          me: me, route: _route, remaining: _remaining, steps: _steps, stepEnds: _stepEnds,
        );
      }
    });

    if (_following) {
      // Only rotate the map when actually moving. GPS heading is noise at a
      // standstill, and letting it drive the camera makes the whole world spin
      // while the driver waits at a light.
      final moving = p.speed.isFinite && p.speed > 1.5; // ~5.4 km/h
      if (_navigating && moving) {
        _camBearing = lerpBearing(_camBearing, _heading, 0.35);
      }
      _ctrl?.animateCamera(
        _navigating
            ? CameraUpdate.newCameraPosition(_navCamera(me))
            : CameraUpdate.newLatLng(me),
      );
    }

    _checkArrival(me);
    _checkToll(me);
    _checkStationary(me);
    _announce();
    _checkOffRoute();

    if (first) _fetchRoute();
  }

  void _checkToll(LatLng me) {
    if (widget.onTollRoad == null) return;
    final reached = _tollWatcher.update(active: _progress?.activeStep);
    if (reached == null) return;
    widget.onTollRoad!(reached);
    // Said as well as shown: the driver is watching the road, not the phone.
    // Any turn instruction on the same fix is spoken after this and wins.
    if (_maySpeak) _voice.say(NavAnnouncer.tollPhrase(_announcer.language));
  }

  void _checkArrival(LatLng me) {
    final target = widget.leg.target;
    if (target == null || _arrived) return;
    if (metersBetween(me, target) <= NavThresholds.arrivalM) {
      setState(() => _arrived = true);
      widget.onArrived?.call();
    }
  }

  void _checkStationary(LatLng me) {
    final anchor = _stationaryAnchor;
    if (anchor == null || metersBetween(me, anchor) > NavThresholds.stationaryM) {
      _stationaryAnchor = me;
      _stationarySince = DateTime.now();
      if (_stationary) setState(() => _stationary = false);
      return;
    }
    final stoppedFor = DateTime.now().difference(_stationarySince).inSeconds;
    final isStopped = stoppedFor >= NavThresholds.stationarySec && !_arrived;
    if (isStopped != _stationary) setState(() => _stationary = isStopped);
  }

  void _checkOffRoute() {
    final pr = _progress;
    if (pr == null || _route.length < 2 || _rerouting) return;
    if (pr.offRouteM > NavThresholds.offRouteM) {
      _offRouteStrikes++;
      // Three consecutive bad fixes, so a single GPS jump cannot trigger a
      // reroute storm in an urban canyon.
      if (_offRouteStrikes >= NavThresholds.offRouteStrikes) {
        _offRouteStrikes = 0;
        _fetchRoute(reroute: true);
      }
    } else {
      _offRouteStrikes = 0;
    }
  }

  Future<void> _fetchRoute({bool reroute = false}) async {
    final me = _me;
    if (me == null || !widget.leg.isValid || !mounted) return;
    if (reroute) setState(() => _rerouting = true);
    try {
      final d = await DriverApiService.getDirections(
        originLat: me.latitude, originLng: me.longitude,
        destLat: widget.leg.destLat!, destLng: widget.leg.destLng!,
        steps: true,
        language: _announcer.language,
      );
      if (!mounted) return;
      if (reroute && d['error'] == null) {
        final phrase = _announcer.rerouted();
        if (phrase != null && _maySpeak) _voice.say(phrase);
      }
      final enc = (d['polyline'] as String?) ?? '';
      final rawSteps = (d['steps'] as List?) ?? const [];
      setState(() {
        if (enc.isNotEmpty) {
          _route = decodePolyline(enc);
          _remaining = remainingDistances(_route);
          final legLength = _remaining.isNotEmpty ? _remaining.first : 0.0;
          // First route for this leg sets the baseline. A later reroute can be
          // LONGER than the original (detour, wrong turn) — grow the baseline
          // then, otherwise the bar would pin at 0% for the rest of the trip.
          if (_legTotalM == null || legLength > _legTotalM!) _legTotalM = legLength;
        }
        _steps = rawSteps
            .map((e) => NavStep.fromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<NavStep>()
            .toList();
        _stepEnds = stepEndIndices(_route, _steps);
        _etaMin = (d['durationMin'] as num?)?.toInt();
        _distKm = (d['distanceKm'] as num?)?.toDouble();
        if (_route.length > 1) {
          _progress = computeProgress(
            me: me, route: _route, remaining: _remaining, steps: _steps, stepEnds: _stepEnds,
          );
        }
      });
    } catch (_) {
      // Keep the last good route and ETA rather than blanking the screen.
    } finally {
      if (mounted && reroute) setState(() => _rerouting = false);
    }
  }

  Future<void> _openExternal() async {
    if (!widget.leg.isValid) return;
    final lat = widget.leg.destLat, lng = widget.leg.destLng;
    final uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    // Try the native Google Maps intent directly and fall back only if it fails.
    // Gating on canLaunchUrl meant Android 11+ (no query declared for this
    // scheme) ALWAYS answered no, so drivers always got browser Maps instead
    // of the Maps app and its turn-by-turn voice guidance.
    // Google Maps speaks from here on; this voice stops mid-sentence and stays
    // quiet until the driver returns to the app.
    _handedOff = true;
    _voice.stop();
    var opened = false;
    try { opened = await launchUrl(uri); } catch (_) { opened = false; }
    if (!opened) {
      try { opened = await launchUrl(web, mode: LaunchMode.externalApplication); } catch (_) { opened = false; }
    }
    // Nothing opened: nothing else is guiding, so this voice carries on.
    if (!opened) _handedOff = false;
  }

  bool get _maySpeak => !_voiceMuted && !_handedOff;

  /// The banner on the last stretch, where the destination is what lies ahead.
  String _arriveText(String label) => _announcer.language == VoiceLanguage.hindi
      ? '${NavAnnouncer.spokenLabel(label, VoiceLanguage.hindi)} पर पहुँचें'
      : 'Arrive at the ${NavAnnouncer.spokenLabel(label, VoiceLanguage.english)}';

  void _announce() {
    final p = _progress;
    final current = p?.activeStep;
    // As the drive begins, where to go now: the opening "Head north on ...".
    String? phrase;
    if (!_arrived && current != null && _steps.isNotEmpty && identical(current, _steps.first)) {
      phrase = _announcer.depart(current);
    }
    // Then the turn ahead — the step after the one being driven, which begins
    // where it ends. The current step's own instruction is the turn already
    // taken: counting down to it said "turn left" as the driver came up to a
    // right turn.
    phrase ??= _announcer.update(
      step: p?.nextStep,
      toManeuverM: p?.toManeuverM ?? double.infinity,
      arrived: _arrived,
      destinationLabel: widget.leg.label,
    );
    // Worked out even while silent, so a muted or handed-off stretch does not
    // leave a backlog of stale prompts to blurt out when the voice returns.
    if (phrase != null && _maySpeak) _voice.say(phrase);
  }

  Future<void> _toggleVoice() async {
    final next = !_voiceMuted;
    setState(() => _voiceMuted = next);
    await _voice.setMuted(next);
  }

  void _recenter() {
    // Tapping Recenter means no finger is on the map. Resetting here recovers
    // from a pointer-up that was lost (app backgrounded mid-gesture), which
    // would otherwise leave every later programmatic move looking like a pan.
    _mapPointers = 0;
    setState(() => _following = true);
    if (_me != null) _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(_me!, 16));
  }

  void _fitRoute() {
    setState(() => _following = false);
    final pts = <LatLng>[
      ..._route,
      if (_me != null) _me!,
      if (widget.leg.target != null) widget.leg.target!,
    ];
    final b = boundsFromPoints(pts);
    if (b != null) _ctrl?.animateCamera(CameraUpdate.newLatLngBounds(b, 60));
  }

  /// Fraction of this leg covered, 0..1. Null until a route exists.
  double? get _tripFraction {
    final total = _legTotalM;
    if (total == null || total <= 0) return null;
    if (_arrived) return 1;
    final remaining = _progress?.remainingM;
    if (remaining == null) return null;
    return (1 - remaining / total).clamp(0.0, 1.0);
  }

  // ── Route split so the travelled part visibly falls behind ──
  List<LatLng> get _travelled {
    final i = _progress?.nearestIndex ?? 0;
    if (_route.isEmpty || i <= 0) return const [];
    return _route.sublist(0, math.min(i + 1, _route.length));
  }

  List<LatLng> get _ahead {
    final i = _progress?.nearestIndex ?? 0;
    if (_route.isEmpty) return const [];
    return _route.sublist(math.min(i, _route.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final leg = widget.leg;
    final dest = leg.target;
    final start = _me ?? dest ?? const LatLng(23.0225, 72.5714);
    final step = _progress?.activeStep;
    // What the banner shows: the turn ahead, or the destination on the last
    // stretch — never the turn that led onto this road.
    final next = _progress?.nextStep;
    final bannerText = next?.instruction ?? _arriveText(leg.label);
    final bannerKind = next != null ? maneuverKind(next.maneuver) : 'arrive';

    // Resolved once per build: the map style and every route colour must agree,
    // or a dark basemap ends up with a light-theme route drawn on it.
    final night = useNightMap(context);

    return SizedBox(
      height: widget.height,
      child: Stack(children: [
        // A real finger on the map is the only reliable signal that the DRIVER
        // moved the camera. onCameraMoveStarted cannot tell: the plugin receives
        // the native move reason and drops it, so our own animateCamera calls
        // fire it too. Keying "stop following" off that callback alone made the
        // nav camera switch itself off after its very first move, and made the
        // Recenter button undo itself instantly. Pointers, not callbacks.
        Listener(
          onPointerDown: (_) => _mapPointers++,
          onPointerUp: (_) => _mapPointers = math.max(0, _mapPointers - 1),
          onPointerCancel: (_) => _mapPointers = math.max(0, _mapPointers - 1),
          child: GoogleMap(
          initialCameraPosition: CameraPosition(target: start, zoom: 15),
          onMapCreated: (c) {
            _ctrl = c;
            if (_me != null) c.animateCamera(CameraUpdate.newLatLngZoom(_me!, 16));
          },
          onCameraMoveStarted: () {
            // Only a gesture stops following — see the Listener above.
            if (_mapPointers > 0 && _following) setState(() => _following = false);
          },
          onCameraMove: (pos) {
            // Only repaint when the width bucket actually changes — this fires
            // continuously during a pinch and a setState per frame would make
            // the gesture stutter.
            if (routeWidthForZoom(pos.zoom) != routeWidthForZoom(_zoom)) {
              setState(() => _zoom = pos.zoom);
            } else {
              _zoom = pos.zoom;
            }
          },
          style: night ? kMapStyleNight : kMapStyleDay,
          // Centres the camera — and so the driver's own position while
          // following — in the part of the map not covered by the page's top bar
          // and bottom sheet. Without it a full-screen map put the driver's puck
          // at the middle of the screen, behind the sheet. The extra 54 clears
          // the "Navigate to" button drawn just above the sheet.
          padding: EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset + 54),
          trafficEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
          markers: {
            if (_me != null)
              Marker(
                markerId: const MarkerId('me'),
                position: _me!,
                // The map is already rotated to the travel direction while
                // navigating, so the puck only needs the residual angle;
                // otherwise it would double-rotate and point sideways.
                rotation: _navigating ? _heading - _camBearing : _heading,
                flat: true,
                anchor: const Offset(0.5, 0.5),
                icon: (_navigating ? _puckChevron : _puckVehicle)
                    ?? _puckVehicle
                    ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'You'),
              ),
            if (dest != null)
              Marker(
                markerId: const MarkerId('dest'),
                position: dest,
                // Flat glyphs sit ON the point; a teardrop pin points with its tip.
                anchor: _destGlyph != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
                icon: _destGlyph ?? PlaceMarkers.fallbackForLeg(leg.label),
                infoWindow: InfoWindow(title: leg.label, snippet: leg.destAddress),
              ),
          },
          polylines: {
            if (_travelled.length > 1)
              Polyline(
                polylineId: const PolylineId('done'),
                points: _travelled,
                color: routeTravelledColor(night),
                width: routeWidthForZoom(_zoom).round(),
                zIndex: 1,
              ),
            // Dark casing beneath the bright core. This pairing is what gives a
            // nav route its crisp edge against the basemap; a single flat line
            // reads as a scribble, especially over traffic colouring.
            if (_ahead.length > 1)
              Polyline(
                polylineId: const PolylineId('ahead_casing'),
                points: _ahead,
                color: routeCasingColor(night),
                width: casingWidthForZoom(_zoom).round(),
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                zIndex: 2,
              ),
            if (_ahead.length > 1)
              Polyline(
                polylineId: const PolylineId('ahead'),
                points: _ahead,
                color: routeCoreColor(night),
                width: routeWidthForZoom(_zoom).round(),
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                zIndex: 3,
              ),
          },
        ),
        ),

        // ── Manoeuvre banner ──
        if (step != null && !_arrived)
          Positioned(
            top: widget.topInset, left: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: Row(children: [
                _ManeuverGlyph(kind: bannerKind),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDistance(_progress?.toManeuverM ?? step.distanceM.toDouble()),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      Text(
                        bannerText,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, height: 1.25, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                if (_steps.length > 1)
                  GestureDetector(
                    onTap: () => setState(() => _showSteps = !_showSteps),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(_showSteps ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white70, size: 22),
                    ),
                  ),
              ]),
            ),
          ),

        // ── Full step list ──
        if (_showSteps && _steps.isNotEmpty && !_arrived)
          Positioned(
            top: widget.topInset + 68, left: 10, right: 10,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 190),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: _steps.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) {
                  final s = _steps[i];
                  // The turn ahead is the one to pick out, as on the banner.
                  final active = identical(s, next ?? step);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      _ManeuverGlyph(kind: maneuverKind(s.maneuver), small: true, dark: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.instruction,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                              color: active ? AppColors.primary : AppColors.textDark,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Text(formatDistance(s.distanceM.toDouble()),
                          style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ]),
                  );
                },
              ),
            ),
          ),

        // ── Leg header (destination + ETA) ──
        if (widget.showHeader)
          Positioned(
            top: (step != null && !_arrived) ? widget.topInset + 68 : widget.topInset,
            left: 10, right: 10,
            child: (_showSteps && !_arrived)
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      const Icon(Icons.navigation, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Text('To ${leg.label}',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
                              if (_tripFraction != null) ...[
                                const SizedBox(width: 6),
                                Text('${(_tripFraction! * 100).round()}% covered',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              ],
                            ]),
                            Text(leg.destAddress.isNotEmpty ? leg.destAddress : 'Destination',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (_etaMin != null) ...[
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$_etaMin min',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.primary)),
                            Text(
                              _progress != null && _progress!.remainingM > 0
                                  ? formatDistance(_progress!.remainingM)
                                  : '${(_distKm ?? 0).toStringAsFixed(1)} km',
                              style: TextStyle(fontSize: 10, color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ],
                    ]),
                    // Trip progress — how much of this leg is behind the driver.
                    if (_tripFraction != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _tripFraction,
                          minHeight: 5,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation(
                            _arrived ? AppColors.green : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    ]),
                  ),
          ),

        // ── Status strips ──
        if (_rerouting) _strip(top: widget.topInset + 68, color: AppColors.orange, icon: Icons.autorenew, text: 'Off route — finding a new way'),
        if (_stationary && !_rerouting) _strip(top: widget.topInset + 68, color: AppColors.textGrey, icon: Icons.pause_circle_outline, text: 'Not moving — tap if you need help'),
        if (_arrived)
          _strip(top: widget.topInset, color: AppColors.green, icon: Icons.check_circle,
              text: 'You have reached ${leg.label}'),

        // ── Map controls ──
        Positioned(
          right: 10, bottom: widget.bottomInset + 52,
          child: Column(children: [
            _circleBtn(
              icon: _following ? Icons.my_location : Icons.location_searching,
              tooltip: 'Recenter',
              onTap: _recenter,
              active: _following,
            ),
            const SizedBox(height: 8),
            _circleBtn(icon: Icons.zoom_out_map, tooltip: 'Fit route', onTap: _fitRoute),
            const SizedBox(height: 8),
            // Remembered across rides: a driver who mutes it does not want to
            // turn it off again on every trip.
            _circleBtn(
              icon: _voiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              tooltip: _voiceMuted ? 'Turn voice guidance on' : 'Mute voice guidance',
              onTap: _toggleVoice,
              active: !_voiceMuted,
            ),
          ]),
        ),

        // ── External turn-by-turn hand-off ──
        Positioned(
          left: 10, right: 10, bottom: widget.bottomInset,
          child: SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: leg.isValid ? _openExternal : null,
              icon: const Icon(Icons.assistant_direction, size: 20),
              label: Text('Navigate to ${leg.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _strip({required double top, required Color color, required IconData icon, required String text}) =>
      Positioned(
        top: top, left: 10, right: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Row(children: [
            Icon(icon, size: 17, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(text,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white))),
          ]),
        ),
      );

  Widget _circleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) =>
      Material(
        color: active ? AppColors.primary : AppColors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Tooltip(
              message: tooltip,
              child: Icon(icon, size: 20, color: active ? Colors.white : AppColors.primary),
            ),
          ),
        ),
      );
}

/// Turn glyph for a manoeuvre. Drawn, not emoji, so it recolours and scales.
class _ManeuverGlyph extends StatelessWidget {
  final String kind;
  final bool small;
  final bool dark;
  const _ManeuverGlyph({required this.kind, this.small = false, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 18.0 : 30.0;
    final color = dark ? AppColors.primary : Colors.white;
    IconData icon;
    switch (kind) {
      case 'left': icon = Icons.turn_left; break;
      case 'right': icon = Icons.turn_right; break;
      case 'slight-left': icon = Icons.turn_slight_left; break;
      case 'slight-right': icon = Icons.turn_slight_right; break;
      case 'sharp-left': icon = Icons.turn_sharp_left; break;
      case 'sharp-right': icon = Icons.turn_sharp_right; break;
      case 'uturn': icon = Icons.u_turn_left; break;
      case 'roundabout': icon = Icons.roundabout_left; break;
      case 'merge': icon = Icons.merge; break;
      case 'arrive': icon = Icons.place; break;
      case 'depart': icon = Icons.navigation; break;
      default: icon = Icons.straight;
    }
    return Icon(icon, size: size, color: color);
  }
}
