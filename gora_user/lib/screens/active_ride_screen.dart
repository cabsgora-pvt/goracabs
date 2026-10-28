import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../utils/duration_format.dart';
import '../services/api_service.dart';
import '../utils/vehicle_marker.dart';
import '../utils/polyline_utils.dart';
import '../utils/map_styles.dart';
import '../utils/map_markers.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import 'rating_screen.dart';
import 'ride_chat_screen.dart';
import '../utils/call_util.dart';
import '../widgets/driver_waiting_timer.dart';
import '../widgets/ride_service_panels.dart';
import '../widgets/online_payment.dart';
import '../utils/ride_payable.dart';
import '../widgets/rental_stops_panel.dart';
import '../widgets/cancel_reasons_sheet.dart';
import '../widgets/no_driver_found.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'emergency_actions_screen.dart';
import 'parcel_bill_screen.dart';

// Generic live-tracking screen for ANY active ride (taxi/rental/outstation/hire/delivery).
// Shows status, OTP, driver card, live driver map + ETA, and cancel.
class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});
  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _ride;
  LatLng? _driverLatLng;
  double _driverHeading = 0;
  int? _etaMin;
  Timer? _statusPoll, _locPoll, _etaPoll;
  // Glides the vehicle between 5s fixes instead of teleporting it.
  late final SmoothVehicleMarker _vehicle;
  BitmapDescriptor? _vehicleIcon;
  // Flat pickup dot and drop square, replacing Google's default teardrop pins.
  // Null until drawn; the default pin shows for that first frame or two.
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropIcon;
  double? _markerDpr;
  // Numbered stop glyphs, drawn on first use per stop number.
  final Map<int, BitmapDescriptor> _stopIcons = {};
  // Numbers being drawn, so a rebuild mid-draw does not start another.
  final Set<int> _stopIconsLoading = {};

  BitmapDescriptor _stopIcon(int number) {
    final hit = _stopIcons[number];
    if (hit != null) return hit;
    final dpr = _markerDpr;
    if (dpr != null && _stopIconsLoading.add(number)) {
      PlaceMarkers.stop(dpr, number).then((d) {
        if (mounted) setState(() => _stopIcons[number] = d);
      });
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }
  // The road the driver is actually on, driver → current destination. The
  // screen used to draw three markers and nothing between them, so a driver
  // going around a lake looked like a driver going the wrong way.
  List<LatLng> _leg = const [];
  GoogleMapController? _mapCtrl;
  // Fit the camera to the whole leg once, rather than sitting on a hardcoded
  // zoom that lets the driver drift off screen as they approach.
  bool _fitted = false;

  // ── Phase ──
  // Server-computed (uiPhase), so this screen and the driver app cannot disagree
  // about what is happening. Falls back to deriving from `status` for rides
  // served by an older backend build.
  String _phase = 'finding';
  String _phaseLabel = '';
  bool _phaseOverrun = false;

  // Drives the sheet, so the map can take over the moment the trip starts.
  final DraggableScrollableController _sheet = DraggableScrollableController();
  static const double _peek = 0.22;
  static const double _half = 0.44;
  // Collapse to peek exactly once per leg change — otherwise every 3s poll
  // would yank the sheet back down while the rider is trying to read it.
  String? _collapsedFor;

  // ── Trip progress ──
  // Length of the CURRENT leg when it began. It cannot be derived from the live
  // route: that is re-fetched from the driver's present position every 30s, so
  // its length only ever shrinks and `remaining/total` would read 0% forever.
  double? _legTotalM;
  double? _legRemainingM;
  // Which leg the totals belong to, so switching pickup→drop resets them.
  String? _legKey;

  // ── Camera follow ──
  // The camera used to fit the route once and then sit still, so as the driver
  // approached they drifted out of frame, and a single accidental pan left the
  // rider looking at an empty patch of map with no way back.
  bool _following = true;
  // Fingers on the map. onCameraMoveStarted cannot tell a rider's pan from our
  // own animateCamera — the plugin drops the native move reason — so only a
  // real pointer counts as the rider taking control. Counted, not a bool, since
  // a pinch is two pointers.
  int _mapPointers = 0;
  // Sheet height as a fraction of the screen, so the map's bottom padding (and
  // therefore where fits centre the route) follows the sheet as it moves.
  double _sheetExtent = _half;

  // ── Settlement ──
  // The coupon discount this ride was booked with. The server does not keep it
  // for most services (see riderPayable), so the booking screen stores it on the
  // device and every poll reads it before showing or charging an amount.
  late final Future<num> _coupon;
  num _couponDiscount = 0;
  // Completion moves money exactly once. Polls overlap whenever a request takes
  // longer than the 3s interval, and the wallet endpoint is not idempotent, so a
  // second in-flight poll that also saw 'completed' would debit the rider twice.
  bool _finishing = false;

  // Tolls already on screen, so each one the driver adds is announced once.
  // Null until the first answer, so tolls entered before this screen opened are
  // listed but not announced as new.
  Set<String>? _seenTolls;

  // Where the current leg ends: 'pickup', 'drop', or null when the trip has no
  // fixed destination. Tracked apart from the phase because it can change while
  // the phase does not — a parcel is collected, or is turned back to the sender,
  // all while the ride stays 'ongoing'.
  String? _target;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The glyphs are drawn at the screen's pixel density, which is only
    // available from MediaQuery — hence here, not initState. Redrawn only if the
    // density actually changes (moving the app to another display).
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_markerDpr == dpr) return;
    _markerDpr = dpr;
    PlaceMarkers.pickup(dpr).then((d) { if (mounted) setState(() => _pickupIcon = d); });
    PlaceMarkers.drop(dpr).then((d) { if (mounted) setState(() => _dropIcon = d); });
  }

  @override
  void initState() {
    super.initState();
    // Keep the map's bottom padding and the recenter button riding on top of
    // the sheet as it is dragged or auto-collapses. Only rebuild when the
    // extent moves meaningfully — this fires every frame during a drag.
    _sheet.addListener(() {
      if (!_sheet.isAttached) return;
      final e = _sheet.size;
      if ((e - _sheetExtent).abs() > 0.01 && mounted) setState(() => _sheetExtent = e);
    });
    _vehicle = SmoothVehicleMarker(
      vsync: this,
      onUpdate: () {
        if (!mounted) return;
        setState(() {
          _driverLatLng = _vehicle.position;
          _driverHeading = _vehicle.bearing;
        });
      },
    );
    _coupon = RideCouponStore.load(widget.rideId);
    WidgetsBinding.instance.addObserver(this);
    _poll();
    _loadTypeImages();
    _startTimers();
    Future.delayed(const Duration(seconds: 2), _eta);
  }

  void _startTimers() {
    _statusPoll?.cancel(); _locPoll?.cancel(); _etaPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    // Marker position stays smooth at 5s (cheap — reads our own DB).
    _locPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loc());
    // ETA is a billed Google Directions call, so it gets its own slower timer.
    // It used to piggyback on the 5s location poll: 12 calls/min per active
    // rider. At 30s that is 2/min, with no visible loss of accuracy.
    _etaPoll = Timer.periodic(const Duration(seconds: 30), (_) => _eta());
  }

  // Back from the background: the OS may have paused or frozen the process, so
  // the screen could still be showing an old phase ("driver on the way") long
  // after the trip started. Re-read the ride right away and restart the timers
  // rather than waiting for — or relying on — the old ones.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || _finishing || _closing || _noDriver) return;
    _startTimers();
    _poll();
    _loc();
    _eta();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusPoll?.cancel(); _locPoll?.cancel(); _etaPoll?.cancel(); _vehicle.dispose(); _sheet.dispose(); super.dispose();
  }

  Future<void> _poll() async {
    _loadTypeImages(); // no-op once loaded; retried at most once a minute
    try {
      final r = await ApiService.getRide(widget.rideId);
      // Read before any amount is shown or charged. Already resolved after the
      // first poll, so this costs nothing from then on.
      final discount = await _coupon;
      if (!mounted || _finishing || _closing || _noDriver) return;
      final status = (r['status'] ?? '').toString();
      if (status == 'completed') {
        await _finish(Map<String, dynamic>.from(r), discount);
        return;
      }
      if (status == 'cancelled') {
        if (isNoDriverFound(Map<String, dynamic>.from(r))) {
          _onNoDriverFound();
        } else {
          _close();
        }
        return;
      }

      // Prefer the server's computed phase. The local fallback keeps this screen
      // working against a backend that predates uiPhase.
      final phase = (r['uiPhase'] ?? _localPhase(r)).toString();
      final phaseChanged = phase != _phase;
      final target = _targetFor(r, phase);
      final targetChanged = target != _target;

      // Driver requested payment. This screen showed "Payment due" with no way to
      // pay, so an online ride tracked here could never finish. Uses the same
      // shared prompt as every booking screen, which guards against stacking a
      // dialog on each 3s poll, and shows the amount this screen will charge.
      if (r['awaitingPayment'] == true && status != 'completed') {
        final toll = tollTotalOf(r);
        if (r['service'] == 'outstation') {
          final rupee = String.fromCharCode(0x20B9);
          final mode = '${r['paymentMode'] ?? 'cash'}';
          final byCash = mode == 'cash' || mode == 'cod';
          // Online and wallet fares are paid in full at booking: nothing is
          // charged here, and saying "please pay ₹5400" would be untrue. What
          // is owed is any toll, to the driver in hand. A cash fare is owed with
          // the tolls, in cash — the same as the sheet says.
          final due = riderPayable(r, couponDiscount: discount) + toll;
          promptOnlinePayment(context, widget.rideId, Map<String, dynamic>.from(r),
              title: 'Trip complete',
              message: byCash
                  ? 'Please pay your driver $rupee${due.round()} in cash${toll > 0 ? ' — fare plus $rupee${toll.round()} tolls' : ''}.'
                  : toll > 0
                      ? 'Your fare was paid when you booked. Please pay your driver $rupee${toll.round()} for tolls.'
                      : 'Your fare was paid when you booked. Nothing more to pay.',
              action: 'Done');
        } else {
          promptOnlinePayment(context, widget.rideId, Map<String, dynamic>.from(r),
              amount: riderPayable(r, couponDiscount: discount));
        }
      }

      _announceNewTolls(r);

      setState(() {
        _ride = Map<String, dynamic>.from(r);
        _couponDiscount = discount;
        _phase = phase;
        _phaseLabel = (r['uiPhaseLabel'] ?? '').toString();
        _phaseOverrun = r['uiPhaseOverrun'] == true;
        _target = target;
        // The old leg ends somewhere the driver is no longer going. Left in
        // place, a rental would keep drawing its approach route and a stale
        // "2 min" for the whole package.
        if (targetChanged) {
          _leg = const [];
          _etaMin = null;
        }
      });

      if (phaseChanged || targetChanged) {
        // A new phase usually means a new destination, so the progress baseline
        // has to be thrown away — otherwise the drop leg is measured against
        // the pickup leg's length and progress jumps or sticks.
        _legTotalM = null;
        _legRemainingM = null;
        _legKey = null;
        _fitted = false;
        _eta();
        _frameForPhase();
      }

      // Deliberately every poll, not only on change. The first poll runs from
      // initState, before the sheet controller is attached, so a rider opening
      // this screen mid-trip would otherwise never get the collapse: the call
      // would no-op on a detached controller and the phase would never change
      // again to trigger a retry. _collapsedFor keeps it idempotent, so a sheet
      // the rider has dragged open stays open.
      _applySheetForPhase(phase);
    } catch (_) {}
  }

  /// Tells the rider about each toll the driver adds, with a way to report it —
  /// the in-app half of the push the server sends.
  void _announceNewTolls(Map<String, dynamic> r) {
    if (r['service'] != 'outstation') return;
    final tolls = tollsOf(r);
    final seen = _seenTolls;
    _seenTolls = {for (final t in tolls) t.id};
    if (seen == null) return;
    final fresh = tolls.where((t) => t.id.isNotEmpty && !seen.contains(t.id)).toList();
    if (fresh.isEmpty || !mounted) return;
    final t = fresh.last;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Your driver added a toll: ${tollSummary(t)}'),
      duration: const Duration(seconds: 8),
      // A snack bar with an action stays until tapped unless told otherwise:
      // this one stayed up for the rest of the trip, held every later toll back
      // in the queue, and followed the rider onto the rating screen. The toll
      // can still be reported from the tolls panel and the bill.
      persist: false,
      action: t.reported ? null : SnackBarAction(
        label: 'Report',
        onPressed: () async {
          if (await reportToll(context, widget.rideId, t)) _poll();
        },
      ),
    ));
  }

  /// Settle a completed ride: charge, show the bill, then rating. Runs once.
  Future<void> _finish(Map<String, dynamic> r, num discount) async {
    // Set before the first await, so no other poll can get past the check in
    // _poll — Dart runs this synchronously up to that point.
    if (_finishing) return;
    _finishing = true;
    _statusPoll?.cancel(); _locPoll?.cancel(); _etaPoll?.cancel();
    // A "driver added a toll" alert still up, or queued, is news about a trip
    // that is over; the bill lists every toll.
    ScaffoldMessenger.of(context).clearSnackBars();

    final svc = (r['service'] ?? '').toString();
    final amount = riderPayable(r, couponDiscount: discount);
    // Outstation is charged at booking, so there is nothing to take here.
    if (svc != 'outstation') {
      var method = (r['paymentMode'] ?? 'cash').toString();
      if (method == 'cod') method = 'cash';
      await PaymentService.charge(context, method: method, amount: amount, rideId: widget.rideId);
      if (!mounted) return;
    }

    // Each service closes the way its booking screen always did.
    if (svc == 'delivery') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelBillScreen(
        amount: amount,
        vehicleName: (r['vehicleType'] ?? 'Delivery').toString(),
        returned: r['deliveryPhase'] == 'returned',
      )));
      if (!mounted) return;
    } else if (hasItemisedBill(svc)) {
      await showRideBill(context, r, couponDiscount: discount);
      if (!mounted) return;
    }
    RideCouponStore.clear(widget.rideId);

    final dr = r['driver'] as Map<String, dynamic>?;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RatingScreen(
      driverName: (dr?['name'] ?? r['driverName'] ?? 'Driver').toString(),
      vehicleName: (r['vehicleType'] ?? '').toString(),
      selectedTip: 0,
      rideId: widget.rideId,
      driverPhotoUrl: (dr?['profilePicUrl'] ?? '').toString().isNotEmpty
          ? AppConfig.imageUrl((dr?['profilePicUrl'] ?? '').toString())
          : '',
    )));
  }

  /// Where the driver is heading: 'pickup', 'drop', or null when there is no
  /// fixed destination to route, time or frame.
  static String? _targetFor(Map<String, dynamic> r, String phase) {
    switch (phase) {
      case 'finding':
      case 'assigned':
      case 'arrived':
        return 'pickup';
      case 'ongoing':
        break;
      // Payment, or a phase this build does not know: the driver is not
      // driving anywhere the rider is waiting on.
      default:
        return null;
    }
    switch ((r['service'] ?? '').toString()) {
      // A rental or a hire goes wherever the rider asks. Their "drop" is
      // optional and falls back to the pickup, so routing to it drew a line back
      // to where the trip began and an ETA that meant nothing. The usage panel
      // is what the rider watches instead.
      case 'rental':
      case 'hire_driver':
        return null;
      case 'delivery':
        final p = (r['deliveryPhase'] ?? '').toString();
        // Collected and on the way to the receiver.
        if (p == 'in_transit' || p == 'collected') return 'drop';
        // Still collecting, or the receiver was unavailable and it is coming
        // back to the sender — both end at the pickup.
        return 'pickup';
      default:
        return 'drop';
    }
  }

  /// How much of the current leg is behind the driver, 0..1, or null when there
  /// is not yet a baseline to measure against.
  double? get _tripFraction {
    final total = _legTotalM, rem = _legRemainingM;
    if (total == null || rem == null || total <= 0) return null;
    return (1 - rem / total).clamp(0.0, 1.0);
  }

  /// Phase derived locally, for backends that do not yet send uiPhase.
  /// Deliberately mirrors lib/ride-phase.ts so the two cannot disagree.
  String _localPhase(Map<String, dynamic> r) {
    if (r['awaitingPayment'] == true) return 'payment';
    switch ((r['status'] ?? '').toString()) {
      case 'pending': return 'finding';
      case 'accepted': return 'assigned';
      case 'arrived': return 'arrived';
      case 'ongoing': return 'ongoing';
      case 'completed': return 'completed';
      case 'cancelled': return 'cancelled';
    }
    return 'finding';
  }

  /// The map takes over the moment the trip starts, and the sheet comes back up
  /// when the rider has something to act on. This single gesture is most of what
  /// makes a ride screen feel live rather than static.
  void _applySheetForPhase(String phase) {
    if (!_sheet.isAttached) return;
    if (_collapsedFor == phase) return;
    _collapsedFor = phase;
    final target = switch (phase) {
      // Nothing to do but watch — give the map the screen.
      'ongoing' => _peek,
      // The rider must read an OTP or pay; put it in front of them.
      'arrived' || 'payment' => _half,
      _ => _half,
    };
    _sheet.animateTo(target,
        duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  // Position only — no billed calls, safe to run often.
  Future<void> _loc() async {
    try {
      final res = await ApiService.getDriverLocation(widget.rideId);
      final d = res['driver'] as Map<String, dynamic>?;
      if (d == null || d['lat'] == null || _ride == null) return;
      final la = (d['lat'] as num).toDouble(), ln = (d['lng'] as num).toDouble();
      if (!mounted) return;
      final firstFix = _driverLatLng == null;
      _vehicle.moveTo(LatLng(la, ln), heading: (d['heading'] as num?)?.toDouble());
      // Resolve the sprite for the vehicle actually assigned to this ride.
      if (_vehicleIcon == null) {
        final vt = ((_ride?['driver'] as Map<String, dynamic>?)?['vehicleTypeName'] ??
                _ride?['vehicleType'] ?? '')
            .toString();
        VehicleMarkers.descriptorFor(vt).then((ic) {
          if (mounted) setState(() => _vehicleIcon = ic);
        });
      }
      // Don't make the rider wait a full ETA cycle for the first number.
      if (firstFix) _eta();
      // Once per 5s fix, not per animation frame: re-fitting while the vehicle
      // glides between fixes would make the whole map swim.
      if (_following) _followCamera();
    } catch (_) {}
  }

  /// Keeps the driver and where they are heading in frame together.
  ///
  /// Frames the driver plus the CURRENT destination rather than the whole route:
  /// that is what the rider is actually waiting on, and it tightens naturally as
  /// the driver closes in instead of staying zoomed out on a long trip.
  void _followCamera() {
    final drv = _driverLatLng;
    final r = _ride;
    if (drv == null || r == null || _mapCtrl == null) return;
    final t = _target;
    final dLat = t == null ? null : r['${t}Lat'] as num?;
    final dLng = t == null ? null : r['${t}Lng'] as num?;
    if (dLat == null || dLng == null) {
      // No destination (a rental under way): keep the driver centred at a
      // street-level zoom, rather than holding whatever zoom the approach used.
      _mapCtrl!.animateCamera(t == null
          ? CameraUpdate.newLatLngZoom(drv, 16)
          : CameraUpdate.newLatLng(drv));
      return;
    }
    final dest = LatLng(dLat.toDouble(), dLng.toDouble());
    _mapCtrl!.animateCamera(frameDriverAndTarget(drv, dest));
  }

  /// First open and every phase change: driver and destination in frame, or
  /// the pickup at street level before there is a driver position.
  void _frameForPhase() {
    if (_mapCtrl == null || !_following) return;
    if (_phase == 'finding' || _driverLatLng == null) {
      _centerOnPickup();
    } else {
      _followCamera();
    }
  }

  /// While searching there is no driver to frame yet, so frame the pickup.
  void _centerOnPickup() {
    final r = _ride;
    final la = (r?['pickupLat'] as num?)?.toDouble();
    final ln = (r?['pickupLng'] as num?)?.toDouble();
    if (_mapCtrl == null || la == null || ln == null) return;
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(la, ln), 16));
  }

  void _recenter() {
    // Recenter is an explicit "no finger on the map", which also recovers from a
    // pointer-up lost while the app was backgrounded mid-gesture.
    _mapPointers = 0;
    setState(() => _following = true);
    if (_phase == 'finding') {
      _centerOnPickup();
    } else {
      _followCamera();
    }
  }

  // Traffic-aware ETA — one Directions call, reusing the last known driver
  // position rather than re-fetching it.
  Future<void> _eta() async {
    try {
      final from = _driverLatLng;
      final key = _target;
      // Nothing to route to. Also skipped while the driver is waiting at the
      // pickup: the ETA is not shown then, and each call is a billed Directions
      // request for a route a few metres long.
      if (from == null || _ride == null || key == null || _phase == 'arrived') return;
      final destLat = _ride!['${key}Lat'] as num?;
      final destLng = _ride!['${key}Lng'] as num?;
      if (destLat == null || destLng == null) return;
      final dir = await ApiService.getDirections(
        originLat: from.latitude, originLng: from.longitude,
        destLat: destLat.toDouble(), destLng: destLng.toDouble(),
      );
      final mins = (dir['durationMin'] as num?)?.toInt();
      // The destination changed while this request was out (the parcel was
      // collected mid-call): this route leads to the old one, so drop it.
      if (!mounted || _target != key) return;
      // A sudden jump against the last-shown ETA (not a running baseline) is a
      // real traffic signal worth a one-time nudge — small fluctuations between
      // 30s polls are normal and shouldn't say anything. Comparing against the
      // just-updated value means this can only fire again on a further jump,
      // not spam on every poll.
      if (mins != null && _etaMin != null && mins - _etaMin! >= 3 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Traffic ahead — ETA is now ${formatMinutes(mins)} (was ${formatMinutes(_etaMin!)})'),
          duration: const Duration(seconds: 5),
        ));
      }
      // The same call already pays for the geometry — it was being thrown away.
      final enc = (dir['polyline'] ?? '').toString();
      final pts = enc.isEmpty ? const <LatLng>[] : decodePolyline(enc);
      final lenM = pts.isEmpty ? null : polylineLengthMeters(pts);
      setState(() {
        if (mins != null) _etaMin = mins;
        if (pts.isNotEmpty) _leg = pts;
        if (lenM != null && lenM > 0) {
          if (_legKey != key) { _legKey = key; _legTotalM = null; }
          // Baseline is the longest length seen for this leg. A reroute can be
          // longer than the original, and clamping progress backwards would
          // look like the driver had gone the wrong way.
          if (_legTotalM == null || lenM > _legTotalM!) _legTotalM = lenM;
          _legRemainingM = lenM;
        }
      });
      // Respect a rider who has panned away: this one-time route fit must not
      // yank the camera back any more than the 5s follow does.
      if (pts.isNotEmpty && !_fitted && _following) {
        _fitted = true;
        final u = frameRoute(pts);
        if (u != null) await _mapCtrl?.animateCamera(u);
      }
    } catch (_) {/* keep last known ETA and route */}
  }

  /// Leaves the screen exactly once.
  ///
  /// A cancel pops the screen, and so does a poll that sees 'cancelled'. The
  /// route stays mounted for the length of the pop animation, so a poll landing
  /// inside that window used to pop a SECOND time — taking the home screen with
  /// it and leaving the rider on a black screen.
  bool _closing = false;

  /// The server closed this ride: no driver took it in time. Stop every poll,
  /// say so plainly, and on "Try again" leave for where the rider booked from —
  /// the same exit as a cancel. Only reacts to server state; no client timer.
  bool _noDriver = false;
  Future<void> _onNoDriverFound() async {
    if (_noDriver || _closing || !mounted) return;
    _noDriver = true;
    _statusPoll?.cancel(); _locPoll?.cancel(); _etaPoll?.cancel();
    await showNoDriverFoundDialog(context);
    if (!mounted) return;
    _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    _statusPoll?.cancel(); _locPoll?.cancel(); _etaPoll?.cancel();
    Navigator.pop(context);
  }

  /// Cancel, with a reason — as every service's own sheet asked for, and as
  /// support needs when a rider disputes a cancellation fee.
  ///
  /// The fee itself is fetched before the sheet opens, from the same rule the
  /// server applies when the cancel actually goes through (see
  /// /rides/{id}/cancel-fee) — so a rider cancelling after the driver has
  /// already committed sees the cost before they confirm, not only after.
  Future<void> _cancel() async {
    final searching = _phase == 'finding';
    final reasons = searching
        ? const ['Taking too long', 'Booked by mistake', 'Plan changed', 'Found another ride', 'Other']
        : const ['Driver is too far', 'Driver asked me to cancel', 'Plan changed',
            'Wrong pickup location', 'Other'];

    num cancelFee = 0;
    try {
      final feeRes = await ApiService.getCancelFee(widget.rideId);
      if (feeRes['appliesNow'] == true) cancelFee = (feeRes['fee'] as num?) ?? 0;
    } catch (_) {/* best effort: reasons sheet still works without it */}
    if (!mounted) return;

    // The shared reasons sheet (same as the booking screen): pick a reason,
    // then confirm. A reason used to cancel the moment it was tapped.
    final reason = await showCancelReasonsSheet(context, reasons: reasons, cancelFee: cancelFee);
    if (reason == null || !mounted || _closing) return;
    final res = await ApiService.cancelRide(widget.rideId, reason);
    if (!mounted) return;
    final error = res['error'];
    if (error != null) {
      // Previously ignored: the screen closed as if cancelled while the ride
      // stayed live on the server and a driver kept driving to the pickup.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not cancel: $error'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    _close();
  }

  /// Share the trip. Leads with the live tracking page, which follows the driver
  /// in real time; a maps link to one coordinate was out of date the moment it
  /// was sent.
  void _shareTrip(Map<String, dynamic> r) {
    final dr = r['driver'] as Map<String, dynamic>?;
    final name = (dr?['name'] ?? r['driverName'] ?? 'Driver').toString();
    final veh = [dr?['vehicleModel'], dr?['vehicleNumber']].where((s) => (s as String?)?.isNotEmpty == true).join(' ');
    final track = '${AppConfig.serverBaseUrl}/track/${widget.rideId}';

    // A parcel's share usually goes to the receiver, who needs two things: where
    // the parcel is, and the PIN to hand the driver. Not the pickup PIN, which
    // only the sender uses.
    if (r['service'] == 'delivery') {
      final dropOtp = (r['dropOtp'] ?? '').toString();
      Share.share(
        'Your Gora parcel is on its way 📦\n'
        'Track it live: $track'
        '${dropOtp.isNotEmpty ? '\nDelivery PIN: $dropOtp (give this to the driver when it arrives)' : ''}',
        subject: 'Track your Gora parcel',
      );
      return;
    }

    final phone = (r['driverPhone'] ?? dr?['phone'] ?? '').toString();
    final otp = (r['otp'] ?? '').toString();
    final msg = 'I\'m on a Gora ride 🚖\n'
        'Track me live: $track\n'
        'Driver: $name${veh.isNotEmpty ? ' ($veh)' : ''}\n'
        '${phone.isNotEmpty ? 'Driver phone: $phone\n' : ''}'
        'From: ${r['pickupAddress'] ?? ''}'
        '${(r['dropAddress'] ?? '').toString().isNotEmpty ? '\nTo: ${r['dropAddress']}' : ''}'
        '${otp.isNotEmpty ? '\nOTP: $otp' : ''}';
    Share.share(msg, subject: 'Track my Gora ride');
  }

  /// Lets the rider add up to 3 co-riders to split this ride's fare with.
  /// Each one pays their own share from their own Gora wallet — see
  /// /rides/{id}/split and riderPayable() for how the primary rider's own
  /// charge shrinks as shares get paid. Once set up it can't be edited from
  /// here (the server refuses once anyone has paid), so this just shows
  /// status when a split already exists.
  Future<void> _splitFareDialog(Map<String, dynamic> r) async {
    final res = await ApiService.getSplit(widget.rideId);
    if (!mounted) return;
    final existing = ((res['splitRequests'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final fare = (res['fare'] as num?) ?? (r['fare'] as num?) ?? 0;

    if (existing.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).cardColor,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sheetHandle(),
            _splitHeader('Split fare', 'Total fare ₹${fare.toStringAsFixed(0)}'),
            const SizedBox(height: 18),
            ...existing.map((c) => _splitPersonCard(name: '${c['name']}', share: (c['share'] as num?) ?? 0, paid: c['status'] == 'paid')),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
      return;
    }

    final fields = <({TextEditingController name, TextEditingController phone})>[
      (name: TextEditingController(), phone: TextEditingController()),
    ];
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final people = fields.length + 1;
        final each = fare / people;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sheetHandle(),
              _splitHeader('Split this fare',
                  '₹${fare.toStringAsFixed(0)} split $people ways — ₹${each.toStringAsFixed(0)} each, from each person\'s own Gora wallet.'),
              const SizedBox(height: 20),
              for (int i = 0; i < fields.length; i++) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(children: [
                    TextField(controller: fields[i].name, decoration: _splitFieldDecoration('Name', Icons.person_outline)),
                    const SizedBox(height: 10),
                    TextField(controller: fields[i].phone, keyboardType: TextInputType.phone,
                        decoration: _splitFieldDecoration('Phone number', Icons.phone_outlined)),
                  ])),
                  if (fields.length > 1)
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.grey[500], size: 20),
                      onPressed: () => setSheetState(() => fields.removeAt(i)),
                    ),
                ]),
                const SizedBox(height: 14),
              ],
              if (fields.length < 3)
                TextButton.icon(
                  onPressed: () => setSheetState(
                      () => fields.add((name: TextEditingController(), phone: TextEditingController()))),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add another friend'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Split fare', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ),
            ]),
          ),
        );
      }),
    );
    if (go != true) return;

    final contacts = fields
        .where((f) => f.phone.text.trim().isNotEmpty)
        .map((f) => {'name': f.name.text.trim().isEmpty ? 'Friend' : f.name.text.trim(), 'phone': f.phone.text.trim()})
        .toList();
    if (contacts.isEmpty || !mounted) return;

    final res2 = await ApiService.createSplit(widget.rideId, contacts);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      res2['success'] == true
          ? 'Split! Each pays ₹${((res2['share'] as num?) ?? 0).toStringAsFixed(0)} from their Gora wallet.'
          : (res2['error'] ?? 'Could not split the fare.').toString(),
    )));
  }

  Widget _sheetHandle() => Center(
    child: Container(
      width: 40, height: 4,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
    ),
  );

  Widget _splitHeader(String title, String subtitle) => Row(children: [
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.call_split, color: AppTheme.primaryBlue),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: RideUi.ink(context))),
      const SizedBox(height: 2),
      Text(subtitle, style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.3)),
    ])),
  ]);

  InputDecoration _splitFieldDecoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 19, color: Colors.grey[500]),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5)),
  );

  Widget _splitPersonCard({required String name, required num share, required bool paid}) {
    final color = paid ? Colors.green : Colors.orange;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
          child: Text(initial, style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: RideUi.ink(context)))),
        Text('₹${share.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: RideUi.ink(context))),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(paid ? 'Paid' : 'Pending', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// SOS opens the real emergency screen.
  ///
  /// This used to show "Emergency helpline: 112" as plain text and offer a share
  /// — no call, and no alert to the safety team. Every booking screen's SOS went
  /// to EmergencyActionsScreen, which raises the alert with the ride and the
  /// rider's location the moment it opens, and dials police in one tap.
  void _sos() => Navigator.push(context, MaterialPageRoute(
      builder: (_) => EmergencyActionsScreen(rideId: widget.rideId)));

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final status = (r['status'] ?? '').toString();
    final otp = (r['otp'] ?? '').toString();
    final dr = r['driver'] as Map<String, dynamic>?;
    final pic = (dr?['profilePicUrl'] ?? '').toString();
    final pLat = (r['pickupLat'] as num?)?.toDouble() ?? 0, pLng = (r['pickupLng'] as num?)?.toDouble() ?? 0;
    final dLat = (r['dropLat'] as num?)?.toDouble() ?? 0, dLng = (r['dropLng'] as num?)?.toDouble() ?? 0;
    // A rental or hire booked without a destination stores the pickup as its
    // drop, and a ride with no drop at all read as 0,0 — a pin off the coast of
    // Africa. Show a drop marker only for a real, separate destination.
    final hasDrop = r['dropLat'] is num && r['dropLng'] is num &&
        ((dLat - pLat).abs() > 0.0001 || (dLng - pLng).abs() > 0.0001);
    final svc = (r['service'] ?? 'taxi').toString();
    final vt = (r['vehicleType'] ?? '').toString().toLowerCase();
    IconData svcIcon = Icons.directions_car;
    if (svc == 'delivery') svcIcon = Icons.local_shipping;
    else if (svc == 'outstation') svcIcon = Icons.map;
    else if (svc == 'rental') svcIcon = Icons.access_time_filled;
    else if (svc == 'hire_driver') svcIcon = Icons.person_pin_circle;
    else if (vt.contains('bike')) svcIcon = Icons.two_wheeler;
    else if (vt.contains('auto')) svcIcon = Icons.electric_rickshaw;
    else if (vt.contains('suv')) svcIcon = Icons.airport_shuttle;

    // Resolved once per build so the basemap and the route colours agree — a
    // dark map with a light-theme route on it is the worst of both.
    final night = useNightMap(context);

    // The opaque AppBar took ~56pt off the top of a screen whose whole point is
    // the map. Controls now float over the map instead, so the space below the
    // status bar belongs to the journey.
    final topInset = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    // Room the floating controls occupy: safe area + 8pt margin + 48pt buttons
    // + 8pt breathing room. Used for both the map's top padding (so fits never
    // tuck the driver under a button) and the sheet's ceiling.
    final controlsH = topInset + 64;
    // The expanded sheet must stop BELOW the floating controls or it would slide
    // underneath them. DraggableScrollableSheet asserts every snap size sits in
    // [min, max], so the top snap is derived from the same ceiling rather than a
    // literal that could exceed it on a short screen.
    final maxSheet = (1 - controlsH / screenH).clamp(_half + 0.05, 0.9).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // With no AppBar the map runs under the status bar, so its icons must
      // contrast with the MAP: dark icons on the light basemap, light on the
      // night one. Otherwise the clock and battery vanish into the map.
      value: (night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      // Full-bleed map with the ride card floating over it. This used to be a
      // fixed 280px box stacked above a list, which read as "an app with a map
      // in it" rather than a live journey.
      body: Stack(children: [
        // Pointer tracking wraps the map only, so taps on the sheet and the
        // floating buttons above it never count as panning the map.
        Positioned.fill(child: Listener(
          onPointerDown: (_) => _mapPointers++,
          onPointerUp: (_) => _mapPointers = _mapPointers > 0 ? _mapPointers - 1 : 0,
          onPointerCancel: (_) => _mapPointers = _mapPointers > 0 ? _mapPointers - 1 : 0,
          child: GoogleMap(
          initialCameraPosition: CameraPosition(target: _driverLatLng ?? LatLng(pLat, pLng), zoom: 13),
          markers: {
            // Flat glyphs sit ON the point (anchor 0.5, 0.5); a teardrop pin's
            // tip is its point, so these must not reuse the pin's bottom anchor.
            Marker(
              markerId: const MarkerId('p'),
              position: LatLng(pLat, pLng),
              anchor: _pickupIcon != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
              icon: _pickupIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            ),
            if (hasDrop) Marker(
              markerId: const MarkerId('d'),
              position: LatLng(dLat, dLng),
              anchor: _dropIcon != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
              icon: _dropIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
            // Destinations added during a rental, so the rider can see the stops
            // they have sent the driver.
            for (final (i, s) in _rentalStops(r).indexed)
              Marker(
                markerId: MarkerId('stop$i'),
                position: s.$1,
                anchor: _stopIcons.containsKey(i + 1) ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
                icon: _stopIcon(i + 1),
                infoWindow: InfoWindow(title: 'Stop ${i + 1}', snippet: s.$2),
              ),
            if (_driverLatLng != null)
              Marker(
                markerId: const MarkerId('drv'),
                position: _driverLatLng!,
                rotation: _driverHeading,
                flat: true,
                anchor: const Offset(0.5, 0.5),
                icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              ),
          },
          // Casing under a bright core is what gives a nav route its crisp edge;
          // a single flat line reads as a scribble over the basemap.
          polylines: {
            if (_leg.length > 1)
              Polyline(
                polylineId: const PolylineId('leg_casing'),
                points: _leg,
                width: 10,
                color: routeCasingColor(night),
                startCap: Cap.roundCap, endCap: Cap.roundCap,
                zIndex: 1,
              ),
            if (_leg.length > 1)
              Polyline(
                polylineId: const PolylineId('leg'),
                points: _leg,
                width: 6,
                color: routeCoreColor(night),
                startCap: Cap.roundCap, endCap: Cap.roundCap,
                zIndex: 2,
              ),
          },
          trafficEnabled: true,
          style: night ? kMapStyleNight : kMapStyleDay,
          // Keeps the Google logo and controls above the sheet, and makes
          // camera fits centre the route in the VISIBLE part of the map.
          // Tracks the sheet, not a fixed 38%: at peek the old value left a
          // large dead band, so fits centred the route well above the middle of
          // what the rider could actually see.
          padding: EdgeInsets.only(
            top: controlsH,
            bottom: screenH * _sheetExtent,
          ),
          onMapCreated: (c) {
            _mapCtrl = c;
            // Frame the ride on open — the search's pickup, or the driver and
            // where they are heading. Only searches were framed, so a ride
            // opened at "Arriving now" kept whatever over-zoomed fit came first.
            _frameForPhase();
          },
          onCameraMoveStarted: () {
            if (_mapPointers > 0 && _following) setState(() => _following = false);
          },
          zoomControlsEnabled: false, myLocationButtonEnabled: false))),
        // Only while the rider has panned away — a permanent button would just
        // be clutter over the map when the camera is already following.
        // Searching radar, pinned over the pickup point. While searching the
        // camera is centred on the pickup, and Google Maps centres the target
        // in the PADDED region — so the pin's screen position is exactly the
        // middle of the visible map, on Android and iOS alike. That avoids
        // getScreenCoordinate, which returns physical pixels on Android but
        // logical points on iOS. Hidden once the rider pans, since it would
        // then detach from the pin.
        if (_phase == 'finding' && _following && _scheduledFor(r) == null)
          Positioned(
            left: MediaQuery.of(context).size.width / 2 - 110,
            top: controlsH + (screenH - controlsH - screenH * _sheetExtent) / 2 - 110,
            child: const SearchRadar(size: 220),
          ),
        if (!_following)
          Positioned(
            right: 14,
            bottom: MediaQuery.of(context).size.height * _sheetExtent + 14,
            child: Material(
              color: Theme.of(context).cardColor,
              elevation: 4,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenter,
                child: const SizedBox(
                  width: 48, height: 48,
                  child: Tooltip(
                    message: 'Recenter on driver',
                    child: Icon(Icons.my_location, color: AppTheme.primaryBlue),
                  ),
                ),
              ),
            ),
          ),
        DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: _half,
          minChildSize: _peek,
          maxChildSize: maxSheet,
          // Snap points stop the sheet resting at an arbitrary height.
          snap: true,
          // The SAME list instance across builds. DraggableScrollableSheet
          // compares snapSizes by identity and, when it changes, re-snaps the
          // sheet (goBallistic) after the frame — which cancels any drag or
          // scroll in progress. A fresh list literal here, plus a screen that
          // rebuilds every animation frame while the driver marker glides,
          // meant the sheet could be neither dragged nor scrolled on a device.
          snapSizes: _snapSizesFor(maxSheet),
          builder: (ctx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, -4))],
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                ..._sheetChildren(r, dr, pic, otp, status),
                // Appended after every phase's own content rather than woven into
                // the phase switch above — the safest way to add one more thing
                // to the sheet without touching its per-phase layouts.
                if ((r['service'] ?? '') == 'taxi' && status != 'completed' && status != 'cancelled')
                  _splitFareRow(r),
              ],
            ),
          ),
        ),
        // Last in the Stack so the controls stay tappable even when the sheet
        // is dragged up toward them.
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                _floatingButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 10),
                // Which service this is, at a glance — the sheet already carries
                // the phase, so this stays a short identity chip, not a title.
                Flexible(child: _serviceChip(svcIcon, _serviceLabel(svc))),
                const Spacer(),
                _floatingButton(
                  icon: Icons.share,
                  tooltip: 'Share trip',
                  onTap: () => _shareTrip(r),
                ),
                const SizedBox(width: 8),
                // Safety stays visually distinct: red, never tucked in a menu.
                _floatingButton(
                  icon: Icons.sos,
                  tooltip: 'Emergency SOS',
                  onTap: _sos,
                  foreground: Colors.white,
                  background: Colors.red,
                ),
              ]),
            ),
          ),
        ),
      ]),
    ),
    );
  }

  /// A tappable row offering to split this ride's fare, shown at the end of
  /// the sheet for every phase of a taxi ride that isn't over yet.
  Widget _splitFareRow(Map<String, dynamic> r) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: RideTile(
      onTap: () => _splitFareDialog(r),
      child: Row(children: [
        Icon(Icons.call_split, size: 19, color: RideUi.ink(context)),
        const SizedBox(width: 10),
        Expanded(child: Text('Split this fare with friends', style: RideUi.body(context, size: 13.5, weight: FontWeight.w700))),
        Icon(Icons.chevron_right_rounded, size: 20, color: RideUi.muted(context)),
      ]),
    ),
  );

  /// A 48pt circular control floating over the map. The elevation shadow is what
  /// keeps it readable over both a busy daytime map and the dark night map.
  Widget _floatingButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? foreground,
    Color? background,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: background ?? Theme.of(context).cardColor,
      elevation: 4,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48, height: 48,
          child: Icon(icon, size: 22,
            color: foreground ?? Theme.of(context).colorScheme.onSurface),
        ),
      ),
    ),
  );

  Widget _serviceChip(IconData icon, String label) => Material(
    color: Theme.of(context).cardColor,
    elevation: 4,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RideUi.ink(context))),
        ),
      ]),
    ),
  );

  String _serviceLabel(String svc) => switch (svc) {
    'rental' => 'Rental',
    'outstation' => 'Outstation',
    'delivery' => 'Parcel',
    'hire_driver' => 'Hire driver',
    _ => 'Ride',
  };

  // -- Sheet content, by phase -------------------------------------------------
  // The sheet used to render the same card at every stage: the rider saw an
  // almost identical panel whether the driver was ten minutes away, waiting
  // outside, or halfway to the destination. Each phase now shows the one thing
  // that matters at that moment, and hides what does not.

  Widget _handle() => const SheetHandle(bottom: 12);

  // Bold near-black heading. [color] stays null unless the phase asks for one
  // (an overrunning rental/hire turns it orange).
  Widget _title(String text, {Widget? trailing, Color? color, String? subtitle}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The heading colour unless a caller overrides it (orange past the
        // package). Left null it inherited the theme's bodyMedium — the grey
        // used for secondary text — so every phase title looked disabled.
        Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2,
            color: color ?? RideUi.ink(context))),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 13)),
        ],
      ])),
      if (trailing != null) ...[const SizedBox(width: 10), trailing],
    ],
  );

  List<double>? _snapSizes;
  List<double> _snapSizesFor(double maxSheet) {
    final s = _snapSizes;
    if (s != null && s.last == maxSheet) return s;
    return _snapSizes = List.unmodifiable([_peek, _half, maxSheet]);
  }

  /// A driver this close to the pickup — or a minute or less out — is
  /// arriving: "0 min" in a badge under "Driver on the way" read as a fault.
  static const double _arrivingKm = 0.15;
  bool _driverArrivingNow(Map<String, dynamic> r) {
    if (_etaMin != null && _etaMin! <= 1) return true;
    final d = _driverLatLng;
    final la = (r['pickupLat'] as num?)?.toDouble();
    final ln = (r['pickupLng'] as num?)?.toDouble();
    if (d == null || la == null || ln == null) return false;
    return polylineLengthMeters([d, LatLng(la, ln)]) / 1000 < _arrivingKm;
  }

  /// The ETA badge, only for a real number of minutes — never "0 min".
  Widget? _etaTrailing() => (_etaMin == null || _etaMin! <= 0) ? null : _etaBadge();

  // Big ETA ("3 min") on navy, Uber style.
  Widget _etaBadge() => _etaMin == null ? const SizedBox.shrink() : Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.primaryBlue,
      borderRadius: BorderRadius.circular(12)),
    child: Text(formatMinutes(_etaMin!),
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
  );

  /// Compact PIN row, used while the driver is still travelling.
  ///
  /// [label] lets a parcel say which PIN this is: the pickup PIN before the
  /// parcel is collected, the delivery PIN once it is on its way.
  Widget _otpRow(String otp, {String label = 'Share PIN with driver to start'}) => RideTile(
    padding: const EdgeInsets.all(10),
    child: Row(children: [
      PinChip(otp),
      const SizedBox(width: 12),
      Expanded(child: Text(label,
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: RideUi.body(context, size: 12.5, weight: FontWeight.w600))),
    ]),
  );

  /// The driver is outside and the only thing the rider has to do is read four
  /// digits aloud, so here the PIN stops being a row and becomes the panel.
  Widget _otpHero(String otp, {String label = 'SHARE THIS PIN WITH YOUR DRIVER'}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    decoration: BoxDecoration(
      color: AppTheme.primaryBlue,
      borderRadius: BorderRadius.circular(RideUi.radius)),
    child: Column(children: [
      Text(label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          letterSpacing: 1.1, color: Colors.white70)),
      const SizedBox(height: 8),
      Text(otp, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900,
        letterSpacing: 12, color: Colors.white)),
    ]),
  );

  /// Shown once, right when the driver has arrived — the moment a rider is
  /// about to get in a car. Points at the two things worth actually checking
  /// (photo, plate) instead of leaving the driver card to be read as just
  /// informational.
  Widget _verifyRideBanner(Map<String, dynamic> dr) {
    final plate = (dr['vehicleNumber'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.verified_user_outlined, color: Colors.green, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verify before boarding', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: RideUi.ink(context))),
          const SizedBox(height: 2),
          Text("Check the driver's photo and plate number below match your car.",
            style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ])),
        if (plate.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(child: PlateBox(plate, fontSize: 12)),
        ],
      ]),
    );
  }

  /// Generic artwork for the booked vehicle type, shown beside the plate. A
  /// hired driver drives the rider's own car, so there is nothing to show.
  /// Admin's vehicle-type photos (name, lower-cased → image path), from the
  /// public /vehicles/types list. Loaded once per screen.
  Map<String, String> _typeImages = const {};
  DateTime? _typeImagesTried;

  /// Called from initState and each poll; fetches until it has the list, at
  /// most once a minute after a failure.
  Future<void> _loadTypeImages() async {
    if (_typeImages.isNotEmpty) return;
    final last = _typeImagesTried;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) return;
    _typeImagesTried = DateTime.now();
    try {
      final res = await ApiService.get('/vehicles/types');
      final list = (res['types'] as List?) ?? const [];
      final m = <String, String>{
        for (final t in list.whereType<Map>())
          if ((t['name'] ?? '').toString().trim().isNotEmpty && (t['imageUrl'] ?? '').toString().isNotEmpty)
            (t['name'] as Object).toString().trim().toLowerCase(): t['imageUrl'].toString(),
      };
      if (mounted && m.isNotEmpty) setState(() => _typeImages = m);
    } catch (_) {/* neutral icon until a later poll succeeds */}
  }

  /// The photo of the ride's ACTUAL vehicle type (the driver's registered type,
  /// else the booked one), as admin uploaded it. It used to be guessed from the
  /// type's name with bundled assets — and the fallback for any car was an SUV
  /// photo, so a "Maruti Dzire" Cab showed an SUV. Unknown → a neutral icon.
  Widget? _vehicleArt(Map<String, dynamic> r) {
    if ((r['service'] ?? '') == 'hire_driver') return null;
    final dr = r['driver'] as Map<String, dynamic>?;
    final name = (dr?['vehicleTypeName'] ?? r['vehicleType'] ?? '').toString().trim().toLowerCase();
    final neutral = Icon(Icons.directions_car_outlined, size: 30, color: RideUi.muted(context));
    final path = _typeImages[name];
    if (name.isEmpty || path == null) return neutral;
    return Image.network(AppConfig.imageUrl(path), fit: BoxFit.contain,
        errorBuilder: (_, _, _) => neutral);
  }

  /// Driver photo (with rating badge), name, vehicle and plate. The full card
  /// adds the Call / Message / Share / Safety row; the compact one (trip under
  /// way) keeps just message and call beside the name so the map keeps the
  /// screen.
  Widget _driverCard(Map<String, dynamic> r, Map<String, dynamic> dr, String pic,
      {bool compact = false}) {
    final name = (dr['name'] ?? 'Driver').toString();
    final model = (dr['vehicleModel'] ?? '').toString();
    final plate = (dr['vehicleNumber'] ?? '').toString();
    final rating = (dr['rating'] as num?)?.toDouble() ?? 0;
    final photo = pic.isNotEmpty ? AppConfig.imageUrl(pic) : '';
    // Chat was not reachable from this screen at all — RideChatScreen was
    // linked from five booking screens but not from the one a rider actually
    // sits on during the ride, so "I'm at gate 2" had nowhere to go.
    void chat() => Navigator.push(context, MaterialPageRoute(
          builder: (_) => RideChatScreen(rideId: widget.rideId, otherName: name),
        ));
    // This used to show the number in a snackbar, leaving the rider to read it
    // and dial by hand. It now opens the dialer, and falls back to copying the
    // number when a dialer is not available. The live Driver record first; the
    // copy stamped on the ride at accept time only as a fallback.
    void call() => dialPhone((dr['phone'] ?? r['driverPhone'] ?? '').toString(), context: context);

    if (compact) {
      return DriverInfoCard(
        compact: true,
        name: name,
        photoUrl: photo,
        rating: rating > 0 ? rating : null,
        vehicleModel: [model, plate].where((s) => s.isNotEmpty).join(' · '),
        stats: _driverStats(dr),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _roundAction(icon: Icons.chat_bubble_outline, color: AppTheme.primaryBlue, tooltip: 'Message driver', onTap: chat),
          const SizedBox(width: 8),
          _roundAction(icon: Icons.call, color: Colors.green, tooltip: 'Call driver', onTap: call),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DriverInfoCard(
        name: name,
        photoUrl: photo,
        rating: rating > 0 ? rating : null,
        vehicleModel: model,
        plate: plate,
        stats: _driverStats(dr),
        vehicleImage: _vehicleArt(r),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        RoundActionButton(icon: Icons.call_rounded, label: 'Call', color: const Color(0xFF16A34A),
            tooltip: 'Call driver', onTap: call),
        RoundActionButton(icon: Icons.chat_bubble_rounded, label: 'Message',
            tooltip: 'Message driver', onTap: chat),
        // The floating bar above carries the "Share trip" / "Emergency SOS"
        // tooltips; these are the same actions within thumb reach.
        RoundActionButton(icon: Icons.ios_share_rounded, label: 'Share', onTap: () => _shareTrip(r)),
        RoundActionButton(icon: Icons.shield_rounded, label: 'Safety', color: Colors.white,
            background: const Color(0xFFD32F2F), onTap: _sos),
      ]),
    ]);
  }

  /// "4.8 · 1,240 trips", or null when the driver has neither yet. A new driver
  /// with no rating shows nothing rather than a "0.0" that reads as terrible.
  static String? _driverStats(Map<String, dynamic> dr) {
    final rating = (dr['rating'] as num?)?.toDouble() ?? 0;
    final trips = (dr['totalRides'] as num?)?.toInt() ?? 0;
    final parts = [
      if (rating > 0) rating.toStringAsFixed(1),
      if (trips > 0) '${_groupThousands(trips)} ${trips == 1 ? 'trip' : 'trips'}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _groupThousands(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  /// Circular tinted action — a 44pt hit target, the platform minimum for a
  /// control people tap one-handed while walking to a pickup point.
  Widget _roundAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 20)),
      ),
    ),
  );

  // Pickup → drop with the dot–line–square connector. A rental or hire booked
  // without a destination has no drop to show.
  List<Widget> _addresses(Map<String, dynamic> r) => [
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: TripRouteSummary(
        pickup: (r['pickupAddress'] ?? '').toString(),
        drop: (r['dropAddress'] ?? '').toString().trim(),
        fontSize: 12,
        // Full addresses, as before: on the live ride the rider reads them.
        maxLines: null,
      ),
    ),
  ];

  /// How far along this leg the driver is. Renders nothing until a baseline
  /// exists, rather than showing an empty bar that looks broken.
  Widget _progressBar() {
    final f = _tripFraction;
    if (f == null) return const SizedBox.shrink();
    final leftKm = (_legRemainingM ?? 0) / 1000;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: f,
          minHeight: 6,
          backgroundColor: RideUi.tile(context),
          valueColor: const AlwaysStoppedAnimation(AppTheme.primaryBlue)),
      ),
      const SizedBox(height: 6),
      Text('${(f * 100).round()}% covered - ${leftKm.toStringAsFixed(1)} km to go',
        style: RideUi.caption(context, size: 11.5)),
    ]);
  }

  Widget _cancelButton() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: RideTextAction(label: 'Cancel Ride', onPressed: _cancel),
  );

  /// "Arrive by 9:42 AM" from the live ETA, or null while it is unknown.
  String? _arriveBy() => _etaMin == null
      ? null
      : 'Arrive by ${RideUi.clock(DateTime.now().add(Duration(minutes: _etaMin!)))}';

  List<Widget> _sheetChildren(Map<String, dynamic> r, Map<String, dynamic>? dr,
      String pic, String otp, String status) {
    final heading = _phaseLabel.isNotEmpty
        ? _phaseLabel
        : (const {
            'finding': 'Looking for nearby drivers',
            'assigned': 'Driver on the way',
            'arrived': 'Driver has arrived',
            'ongoing': 'Trip in progress',
            'payment': 'Payment due',
          }[_phase] ?? status);
    final svc = (r['service'] ?? '').toString();
    final parcel = svc == 'delivery';
    // Billed on time (and km) used rather than a fixed trip to a destination.
    final metered = svc == 'rental' || svc == 'hire_driver';
    final drop = (r['dropAddress'] ?? '').toString().trim();
    final dropShort = drop.contains(',') ? drop.substring(0, drop.indexOf(',')).trim() : drop;

    switch (_phase) {
      // A ride booked for later is 'pending' until it is dispatched, which may be
      // days away. It used to sit under a searching radar the whole time — and
      // home auto-opens any pending ride, so a rider with a rental booked for
      // next week was greeted by "Finding your driver" on every launch.
      case 'finding' when _scheduledFor(r) != null:
        final at = _scheduledFor(r)!;
        return [
          _handle(),
          _title('Ride scheduled'),
          const SizedBox(height: 14),
          RideTile(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.event_available_rounded, color: AppTheme.primaryBlue, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_formatWhen(at),
                  style: RideUi.body(context, size: 16, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text("We'll assign a driver before your pickup time and let you know.",
                  style: RideUi.caption(context, size: 12.5)),
              ])),
            ]),
          ),
          const SizedBox(height: 14),
          if (svc == 'outstation') ..._outstation(r),
          ..._addresses(r),
          _cancelButton(),
        ];

      // Nothing to show but reassurance and a way out.
      case 'finding':
        final fare = riderPayable(r, couponDiscount: _couponDiscount);
        final vt = (r['vehicleType'] ?? '').toString();
        return [
          _handle(),
          // Same words as the booking screen's search view, whatever label the
          // server sends ("Finding a driver"): one booking, one name for it.
          _title('Looking for nearby drivers'),
          const SizedBox(height: 12),
          // The radar on the map carries the "searching" signal; a large
          // spinner here as well would compete with it.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: RideUi.tile(context),
              valueColor: const AlwaysStoppedAnimation(AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(height: 10),
          Text('Connecting you with nearby drivers', style: RideUi.caption(context, size: 13)),
          const RideDivider(vertical: 12),
          ..._addresses(r),
          if (vt.isNotEmpty || fare > 0) ...[
            const SizedBox(height: 10),
            RideTile(
              child: Row(children: [
                Icon(Icons.local_taxi_rounded, size: 20, color: RideUi.ink(context)),
                const SizedBox(width: 10),
                Expanded(child: Text(vt.isNotEmpty ? vt : _serviceLabel(svc), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: RideUi.body(context, size: 14, weight: FontWeight.w800))),
                if (fare > 0)
                  Text('${String.fromCharCode(0x20B9)}${fare.round()}',
                      style: RideUi.body(context, size: 16, weight: FontWeight.w900)),
              ]),
            ),
          ],
          _cancelButton(),
        ];

      // The PIN is the rider's job now, so it takes the whole panel.
      case 'arrived':
        return [
          _handle(),
          _title(heading),
          const SizedBox(height: 14),
          if (otp.isNotEmpty) parcel
              ? _otpHero(otp, label: 'GIVE THIS PICKUP PIN TO THE DRIVER')
              : _otpHero(otp),
          const SizedBox(height: 10),
          // How long the driver has been waiting — a gentle nudge to head out.
          // Seeded from the server's count, and it stays mounted at the same
          // position across the 3s polls, so it keeps counting instead of
          // restarting each time the sheet rebuilds.
          DriverWaitingTimer(
            key: ValueKey('wait-${widget.rideId}'),
            seedSeconds: (r['waitingSec'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(height: 14),
          if (dr != null) _verifyRideBanner(dr),
          if (dr != null) _driverCard(r, dr, pic),
          const SizedBox(height: 8),
          if (svc == 'outstation') ..._outstation(r),
          ..._addresses(r),
          _cancelButton(),
        ];

      // Under way: the PIN is spent and would only be noise. Progress replaces
      // it, and the driver card shrinks so the map keeps the screen.
      //
      // No Cancel here. Once the trip has started, cancelling is how a rider
      // would end a three-hour rental without paying for it; every ride app
      // removes the button at this point. SOS, call and chat all remain.
      case 'ongoing':
        final arrive = metered ? null : _arriveBy();
        return [
          _handle(),
          // A rental or hire has no destination to be N minutes from. Past the
          // package ("Extra time", "Overtime") the heading turns orange, matching
          // the extra charges accruing in the panel below it.
          _title(heading,
            trailing: metered ? null : _etaTrailing(),
            color: _phaseOverrun ? Colors.orange[800] : null,
            // Shown with the live ETA, like the badge beside it.
            subtitle: arrive == null
                ? null
                : [
                    if (dropShort.isNotEmpty) 'Heading to $dropShort',
                    arrive,
                  ].join(' · ')),
          const SizedBox(height: 14),
          // What a metered trip's rider watches is the package being used up and
          // what it will cost, not distance to a drop they may not have.
          if (svc == 'rental') RentalUsagePanel(ride: r)
          else if (svc == 'hire_driver') HireUsagePanel(ride: r)
          else _progressBar(),
          const SizedBox(height: 14),
          // With no fixed drop, "where next" is the one thing a rental rider
          // actually does during the trip.
          if (svc == 'rental') ...[
            RentalStopsPanel(rideId: widget.rideId, ride: r, onAdded: _poll),
            const SizedBox(height: 12),
          ],
          if (parcel) ..._parcelUnderWay(r),
          if (dr != null) _driverCard(r, dr, pic, compact: true),
          const SizedBox(height: 8),
          if (svc == 'outstation') ...[
            ..._outstation(r),
            OutstationTollPanel(ride: r, rideId: widget.rideId, onReported: _poll),
            const SizedBox(height: 8),
          ],
          ..._addresses(r),
        ];

      // The driver is waiting to be paid, so lead with the amount.
      case 'payment':
        final mode = (r['paymentMode'] ?? 'cash').toString();
        final byCash = mode == 'cash' || mode == 'cod';
        // Outstation takes online and wallet payments when the trip is booked.
        final prepaid = svc == 'outstation' && !byCash;
        // Outstation tolls are paid to the driver in hand, in every mode.
        final toll = svc == 'outstation' ? tollTotalOf(r) : 0;
        final fare = riderPayable(r, couponDiscount: _couponDiscount);
        // Cash covers the fare and the tolls together; prepaid shows the fare
        // that was already paid.
        final due = prepaid ? fare : fare + toll;
        return [
          _handle(),
          _title(heading),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: RideUi.tile(context),
              borderRadius: BorderRadius.circular(RideUi.radius)),
            child: Column(children: [
              Text(prepaid ? 'PAID AT BOOKING' : 'AMOUNT DUE', style: RideUi.caption(context, size: 11).copyWith(
                fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 6),
              Text('${String.fromCharCode(0x20B9)}${due.round()}',
                style: TextStyle(fontSize: 38,
                  fontWeight: FontWeight.w900, color: RideUi.ink(context))),
            ])),
          const SizedBox(height: 12),
          // The sheet said "Payment due" and offered no way to pay. The prompt
          // also opens by itself on the next poll; this is for a rider who
          // dismissed it with the back button, or is looking at the sheet.
          if (prepaid)
            _hint(toll > 0
                ? 'Fare paid when you booked. Please pay ${String.fromCharCode(0x20B9)}${toll.round()} for tolls to your driver.'
                : 'Already paid when you booked. Nothing more to pay.')
          else if (byCash)
            _hint(toll > 0
                ? 'Please pay ${String.fromCharCode(0x20B9)}${due.round()} to your driver in cash — fare plus ${String.fromCharCode(0x20B9)}${toll.round()} tolls.'
                : 'Please pay ${String.fromCharCode(0x20B9)}${due.round()} to your driver in cash.')
          else
            PrimaryRideButton(
              onPressed: () => promptOnlinePayment(
                  context, widget.rideId, Map<String, dynamic>.from(r), amount: due),
              icon: Icons.lock_outline,
              label: 'Pay ${String.fromCharCode(0x20B9)}${due.round()}',
            ),
          const SizedBox(height: 14),
          if (svc == 'outstation') ...[
            OutstationTollPanel(ride: r, rideId: widget.rideId, onReported: _poll),
            const SizedBox(height: 12),
          ],
          if (dr != null) _driverCard(r, dr, pic, compact: true),
          const SizedBox(height: 8),
          ..._addresses(r),
        ];

      // 'assigned', plus any phase a newer backend introduces that this build
      // does not know about: the general-purpose panel.
      default:
        return [
          _handle(),
          if (_driverArrivingNow(r))
            _title('Arriving now', subtitle: 'Meet at the pickup point')
          else
            _title(heading, trailing: _etaTrailing(), subtitle: 'Meet at the pickup point'),
          const SizedBox(height: 14),
          if (otp.isNotEmpty) parcel
              ? _otpRow(otp, label: 'Pickup PIN — give it to the driver when they collect')
              : _otpRow(otp),
          const SizedBox(height: 12),
          if (dr != null) _driverCard(r, dr, pic),
          const SizedBox(height: 8),
          if (svc == 'outstation') ..._outstation(r),
          ..._addresses(r),
          _cancelButton(),
        ];
    }
  }

  List<Widget> _outstation(Map<String, dynamic> r) =>
      [OutstationTripPanel(ride: r), const SizedBox(height: 8)];

  /// A rental's added stops as (position, address). Entries without usable
  /// coordinates are skipped rather than drawn at 0,0.
  static List<(LatLng, String)> _rentalStops(Map<String, dynamic> r) {
    if (r['service'] != 'rental') return const [];
    return [
      for (final s in (r['rentalStops'] as List?) ?? const [])
        if (s is Map && s['lat'] is num && s['lng'] is num)
          (LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
           (s['address'] ?? '').toString()),
    ];
  }

  /// When a still-unassigned ride is booked for, if that is far enough ahead to
  /// be a scheduled booking rather than a ride wanted now. The margin absorbs
  /// the few minutes a phone's clock is commonly off from the server's.
  static DateTime? _scheduledFor(Map<String, dynamic> r) {
    final raw = r['scheduledAt'];
    if (raw == null) return null;
    final at = DateTime.tryParse(raw.toString())?.toLocal();
    if (at == null) return null;
    return at.isAfter(DateTime.now().add(const Duration(minutes: 10))) ? at : null;
  }

  /// "Today, 9:30 AM", "Tomorrow, 6:05 PM", or "Tue 24 Sep, 9:30 AM".
  static String _formatWhen(DateTime at, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(at.year, at.month, at.day);
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Tomorrow, $time';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[at.weekday - 1]} ${at.day} ${months[at.month - 1]}, $time';
  }

  /// A parcel carries two PINs. The pickup PIN started the job and is spent; the
  /// delivery PIN is what the receiver gives the driver at handover, so the
  /// sender needs it in front of them to pass on. The parcel screen only showed
  /// it once the parcel was collected; showing it from the start of the trip
  /// gives the sender time to send it before the driver reaches the door.
  List<Widget> _parcelUnderWay(Map<String, dynamic> r) {
    final p = (r['deliveryPhase'] ?? '').toString();
    if (p == 'returned' || p == 'failed') {
      final reason = (r['failReason'] ?? '').toString().trim();
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.35))),
          child: Row(children: [
            Icon(Icons.keyboard_return_rounded, color: Colors.orange[800]),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your parcel is coming back to you',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.orange[900])),
              const SizedBox(height: 2),
              Text(reason.isEmpty ? 'The receiver could not take it.' : reason,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.orange[900])),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
      ];
    }
    final dropOtp = (r['dropOtp'] ?? '').toString();
    if (dropOtp.isEmpty) return const [];
    return [
      _otpRow(dropOtp, label: 'Delivery PIN — share it with the receiver'),
      const SizedBox(height: 12),
    ];
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600)),
  );

}

/// Closer than this, two points are framed at a fixed street-level zoom
/// instead of fitted: fitting bounds a few metres across zooms the map to its
/// maximum — a plain grey road with no car or pin in view — which is exactly
/// what a rider saw when the driver was at the pickup ("Arriving now").
const double kFrameMinSpanMeters = 300;
const double kFrameCloseZoom = 16;

/// Driver and where they are heading, in one frame. Close together, centres on
/// the destination (the pickup, while the driver is coming) at street level.
@visibleForTesting
CameraUpdate frameDriverAndTarget(LatLng driver, LatLng target, {double padding = 64}) {
  if (polylineLengthMeters([driver, target]) < kFrameMinSpanMeters) {
    return CameraUpdate.newLatLngZoom(target, kFrameCloseZoom);
  }
  return CameraUpdate.newLatLngBounds(boundsFromPoints([driver, target])!, padding);
}

/// A route's one-time fit, with the same floor for a route only metres long.
@visibleForTesting
CameraUpdate? frameRoute(List<LatLng> pts, {double padding = 56}) {
  final b = boundsFromPoints(pts);
  if (b == null) return null;
  if (polylineLengthMeters([b.southwest, b.northeast]) < kFrameMinSpanMeters) {
    return CameraUpdate.newLatLngZoom(pts.last, kFrameCloseZoom);
  }
  return CameraUpdate.newLatLngBounds(b, padding);
}
