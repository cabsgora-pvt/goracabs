import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../models/models.dart';
import '../../../services/device_channel.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../../services/ride_alert_service.dart';
import '../../home/logic/feed_status.dart';
import '../logic/accept_outcome.dart';
import '../logic/dismissed_requests.dart';
import '../logic/request_announcement.dart';
import '../widgets/lower_tier_chip.dart';
import '../widgets/voice_guide.dart';
import '../widgets/swipe_to_confirm.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../../../services/session.dart';
import 'on_ride_page.dart';

// Shows up to 5 pending ride requests at once (taxi / rental / outstation / etc.).
// The driver can Accept or Reject any of them; rejected/taken ones drop off and
// fresh requests fill in. A card whose countdown runs out is only dismissed
// locally (DismissedRequests) — it is NOT rejected on the server. Accepting one navigates to the on-ride screen.
class IncomingRequestsPage extends StatefulWidget {
  static const route = '/incoming-requests';
  const IncomingRequestsPage({super.key});
  @override
  State<IncomingRequestsPage> createState() => _IncomingRequestsPageState();
}

class _IncomingRequestsPageState extends State<IncomingRequestsPage> {
  static const int _maxRequests = 5;
  List<RideRequestModel> _requests = [];
  // The feed rows as received, so an accepted ride can be reopened from them
  // merged with the contact details the accept / active-ride reply carries.
  final Map<String, Map<String, dynamic>> _raw = {};
  final Set<String> _rejectedIds = {};
  Timer? _timer;
  bool _accepting = false;
  bool _firstLoaded = false;

  // Per-service ringtone (admin-managed) + player
  Map<String, String> _ringtones = {};
  final AudioPlayer _player = AudioPlayer();
  String? _playingService;
  bool _vibrating = false;

  // "New ride, 142 rupees, 1.2 km away", once per request (voice settings).
  final VoiceGuide _voice = VoiceGuide();
  bool _voiceReady = false;
  bool _announceOn = true;
  final Set<String> _announced = {};
  bool _closed = false; // guards against double-pop (which lands on the start screen)

  // Driver's current location — used to compute the driver → pickup distance
  // shown on each card. Fetched once when the screen opens.
  double? _driverLat, _driverLng;

  /// Offers to this driver are paused until then (too many rejections). The
  /// open pool is still listed.
  DateTime? _cooldownUntil;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Fetch driver location in the background (for pickup-distance display).
    LocationService.getCurrentLocation().then((pos) {
      if (pos != null && mounted) {
        setState(() { _driverLat = pos.latitude; _driverLng = pos.longitude; });
      }
    }).catchError((_) {});
    // The ringtone plays as an alarm-class sound (not media), so a phone with
    // its media volume down still rings for a request.
    unawaited(_setRingContext());
    unawaited(_initVoice());
    try {
      final cfg = await DriverApiService.getDriverConfig();
      final r = (cfg['ringtones'] as Map?) ?? {};
      _ringtones = r.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    await _refresh();
    _timer = Timer.periodic(requestRefreshEvery, (_) => _refresh());
  }

  Future<void> _setRingContext() async {
    try { await _player.setAudioContext(requestRingContext); } catch (_) {}
  }

  Future<void> _initVoice() async {
    try {
      _announceOn = await RequestAnnouncer.enabled();
      if (!_announceOn) return;
      await _voice.init();
      _voiceReady = true;
      if (mounted && _requests.isNotEmpty) _announce(_requests.first);
    } catch (_) {}
  }

  /// Says the top request once. The ringtone is turned down while it speaks.
  void _announce(RideRequestModel r) {
    if (!_announceOn || !_voiceReady || _announced.contains(r.id) || _closed) return;
    _announced.add(r.id);
    final km = r.pickupDistanceKm > 0 ? r.pickupDistanceKm.toDouble() : _localPickupKm(r);
    final text = RequestAnnouncer.phrase(r, _voice.language, pickupKm: km);
    unawaited(_speakOverRing(text));
  }

  Future<void> _speakOverRing(String text) async {
    try { await _player.setVolume(0.3); } catch (_) {}
    // evenIfMuted: this has its own switch; the voice-guidance mute is for
    // turn-by-turn directions.
    await _voice.say(text, evenIfMuted: true);
    await Future<void>.delayed(const Duration(seconds: 4));
    try { if (!_closed) await _player.setVolume(1.0); } catch (_) {}
  }

  double? _localPickupKm(RideRequestModel r) {
    if (_driverLat == null || _driverLng == null || r.pickupLat == 0 || r.pickupLng == 0) return null;
    return Geolocator.distanceBetween(_driverLat!, _driverLng!, r.pickupLat, r.pickupLng) / 1000;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.stop();
    _player.dispose();
    if (_vibrating) unawaited(DeviceChannel.stopVibration());
    unawaited(_voice.stop());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_accepting || _closed || !mounted) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      if (res['error'] == null) {
        final until = offerCooldownUntilOf(res);
        if (mounted && until != _cooldownUntil) setState(() => _cooldownUntil = until);
      }
      for (final e in rides) {
        if (e is Map && e['id'] != null) _raw[e['id'].toString()] = Map<String, dynamic>.from(e);
      }
      final models = rides
          .map((e) => RideRequestModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((m) => !_rejectedIds.contains(m.id))
          .where((m) => !DismissedRequests.isSuppressed(m.id,
              offeredToMe: m.offeredToMe, offerExpiresAt: m.offerExpiresAt))
          .take(_maxRequests)
          .toList();
      // Re-checked after the await. A refresh already in flight when Accept was
      // pressed comes back after the server has moved the ride out of
      // 'pending' — it used to see an empty feed and close this page under the
      // accept, leaving the driver on a half-closed "New trip request" screen
      // (or back home) with the trip accepted on the server.
      if (!mounted || _closed || _accepting) return;
      _firstLoaded = true;
      if (models.isEmpty) { _close(); return; }
      setState(() => _requests = models);
      _updateRing();
      _announce(models.first);
    } catch (_) {}
  }

  // Play the ringtone of the top (nearest) request's service; loop until handled.
  void _updateRing() {
    if (_requests.isEmpty) { _stopRing(); return; }
    final svc = _requests.first.service;
    if (_playingService == svc) return;
    _playRing(svc);
  }

  Future<void> _playRing(String svc) async {
    final rel = _ringtones[svc] ?? '';
    _playingService = svc;
    // Buzzes too, for as long as a request is up: a phone on silent, or in a
    // pocket on a loud road, still gets the driver's attention.
    if (!_vibrating) {
      _vibrating = true;
      unawaited(DeviceChannel.startVibration());
    }
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
    } catch (_) {}
    // The admin's ringtone for the service, else the bundled one, else the
    // phone's own notification sound: a request must never arrive silently
    // because one file would not load (a bad upload, a 404, a codec).
    for (final src in ringtoneSources(rel)) {
      if (_playingService != svc) return; // handled meanwhile
      try {
        await _player.play(src);
        return;
      } catch (_) {}
    }
    if (_playingService == svc) await DeviceChannel.playSystemAlert();
  }

  Future<void> _stopRing() async {
    _playingService = null;
    if (_vibrating) {
      _vibrating = false;
      unawaited(DeviceChannel.stopVibration());
    }
    unawaited(_voice.stop());
    try { await _player.stop(); } catch (_) {}
    unawaited(DeviceChannel.stopSystemAlert());
  }

  // Close the screen exactly once (timer's _refresh and button handlers could
  // otherwise both pop, removing the home screen and leaving a blank start view).
  void _close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _stopRing();
    // Nothing left on this page (taken by someone else, no longer pending…).
    unawaited(RideAlertService.clearIncomingAlert());
    unawaited(DeviceChannel.releaseLockScreen());
    if (!mounted) return;
    // Remove THIS page, wherever it is in the stack. Navigator.pop removes the
    // top route — and when something had been pushed above this page (the
    // trip's OTP dialog, another screen), that was what got popped: this page
    // stayed behind, already marked closed and with its last card gone, as an
    // empty "New trip request" screen nothing could close.
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      Navigator.pop(context);
    } else {
      Navigator.removeRoute(context, route);
    }
  }

  Future<void> _accept(RideRequestModel m) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _timer?.cancel();
    // Not awaited: the ringtone stops in parallel. A stalled audio plugin call
    // must never hold up the accept itself.
    unawaited(_stopRing());
    unawaited(RideAlertService.clearIncomingAlert());
    Map<String, dynamic>? r;
    try {
      r = await DriverApiService.acceptRide(m.id);
    } catch (_) {
      // Timed out or the connection dropped: the server may well have assigned
      // the ride to us anyway. Telling the driver it failed would leave the
      // rider waiting for a captain who is not coming.
      r = null;
    }
    if (!mounted) return;
    if (r == null) {
      final active = await _activeRide();
      if (!mounted) return;
      if (active != null && active['id']?.toString() == m.id) {
        _open(m, active);
        return;
      }
      _resume(m, const AcceptOutcome(AcceptAction.keepCard,
          'Could not reach the server — the trip was not accepted. Try again.'));
      return;
    }
    final outcome = acceptOutcome(r);
    if (outcome.action == AcceptAction.open) {
      // Phone numbers are not in the feed: the active-ride reply has them.
      final active = await _activeRide();
      if (!mounted) return;
      final ride = r['ride'];
      _open(m, active != null && active['id']?.toString() == m.id
          ? active
          : (ride is Map ? _contactsOf(Map<String, dynamic>.from(ride)) : const {}));
      return;
    }
    _resume(m, outcome);
  }

  Future<Map<String, dynamic>?> _activeRide() async {
    try {
      final a = await DriverApiService.getActiveRide();
      final ride = a['ride'];
      return ride is Map ? Map<String, dynamic>.from(ride) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _contactsOf(Map<String, dynamic> ride) => {
    for (final k in const ['riderPhone', 'senderPhone', 'receiverPhone', 'senderName', 'receiverName', 'status',
        'bookingFor', 'passengerName', 'passengerPhone'])
      if (ride[k] != null) k: ride[k],
  };

  void _open(RideRequestModel m, Map<String, dynamic> extra) {
    // Nothing may close or refresh this page any more: it is being replaced.
    _closed = true;
    unawaited(DeviceChannel.releaseLockScreen());
    final raw = _raw[m.id];
    final model = raw == null && extra.isEmpty
        ? m
        : RideRequestModel.fromJson({...?raw, ...extra, 'id': m.id});
    // An advance booking (outstation / rental / hire up to 48 h ahead) is not
    // a trip to drive to now: the server keeps offering this driver other
    // requests until an hour before it. Confirm it and go back home, where it
    // is listed as an upcoming trip; the trip screen opens once it is due.
    final due = model.dueAt;
    if (isUpcomingTrip(due)) {
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
        content: Text(upcomingAcceptedText(due!)),
        duration: const Duration(seconds: 8),
      ));
      return;
    }
    // A clean stack under the new trip: only home below it. This page could
    // open over the last trip's Order Complete (or any other screen), and a
    // plain replace left that screen underneath — Back from the new trip
    // then showed the previous trip's invoice.
    Navigator.pushNamedAndRemoveUntil(context, OnRidePage.route, (r) => r.isFirst, arguments: model);
  }

  /// The accept was refused (or did not get through): say why, then carry on
  /// with whatever requests are still up — or close if none can be taken.
  void _resume(RideRequestModel m, AcceptOutcome outcome) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message), duration: const Duration(seconds: 5)),
    );
    if (outcome.action == AcceptAction.closeAll) {
      setState(() { _requests = []; _accepting = false; });
      _close();
      return;
    }
    setState(() {
      if (outcome.action == AcceptAction.dropCard) {
        _rejectedIds.add(m.id);
        _requests.removeWhere((x) => x.id == m.id);
      } else if (outcome.action == AcceptAction.dismissCard) {
        DismissedRequests.dismiss(m.id, offerExpiresAt: m.offerExpiresAt);
        _requests.removeWhere((x) => x.id == m.id);
      }
      _accepting = false;
    });
    _timer = Timer.periodic(requestRefreshEvery, (_) => _refresh());
    if (_requests.isEmpty) { _close(); } else { _updateRing(); }
  }

  // Explicit reject (tap on ✕ or swipe left): the server records rejectedBy so
  // this ride is not offered to this driver again.
  void _reject(RideRequestModel m) {
    _rejectedIds.add(m.id);
    // Not waited for; the server records rejectedBy. Too many rejections pause
    // this driver's offers (offerCooldownUntil): say so, wherever they are.
    final here = ScaffoldMessenger.maybeOf(context);
    DriverApiService.rejectRide(m.id).then((res) {
      final until = offerCooldownUntilOf(res);
      if (until == null) return;
      _cooldownUntil = until;
      if (mounted) setState(() {});
      final root = Session.navigatorKey.currentState?.overlay?.context;
      final messenger = (root != null && root.mounted ? ScaffoldMessenger.maybeOf(root) : null) ?? here;
      messenger?.showSnackBar(SnackBar(
        content: Text(cooldownText(until)), duration: const Duration(seconds: 6)));
    }).catchError((_) {});
    unawaited(RideAlertService.clearIncomingAlert());
    setState(() => _requests.removeWhere((x) => x.id == m.id));
    if (_requests.isEmpty) { _close(); } else { _updateRing(); }
  }

  // Countdown ran out (also happens while the app is in the background). Not a
  // rejection: the server's offer expiry already moves the offer on, and a
  // reject here would hide the ride from this driver for good. Only take the
  // card off screen, and keep it from popping straight back up on the next
  // poll — it can still come back later if the server offers it again.
  void _timedOut(RideRequestModel m) {
    DismissedRequests.dismiss(m.id, offerExpiresAt: m.offerExpiresAt);
    unawaited(RideAlertService.clearIncomingAlert());
    if (!mounted) return;
    setState(() => _requests.removeWhere((x) => x.id == m.id));
    if (_requests.isEmpty) { _close(); } else { _updateRing(); }
  }

  @override
  Widget build(BuildContext context) {
    final single = _requests.length == 1;
    return Scaffold(
      backgroundColor: Cap.tile,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(single || _requests.isEmpty ? 'New trip request' : '${_requests.length} new requests',
                  style: Cap.title(size: 24)),
              const SizedBox(height: 4),
              Text('Slide to accept · swipe left to decline',
                  style: Cap.caption(size: 13)),
              if (_cooldownUntil != null && _cooldownUntil!.isAfter(DateTime.now())) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.pause_circle_outline_rounded, size: 16, color: AppColors.orange),
                  const SizedBox(width: 6),
                  Expanded(child: Text(cooldownText(_cooldownUntil!),
                      style: Cap.body(size: 12.5, weight: FontWeight.w700, color: AppColors.orange))),
                ]),
              ],
            ]),
          ),
          Expanded(
            child: !_firstLoaded
                ? Center(child: CircularProgressIndicator(color: Cap.accent, strokeWidth: 2.6))
                : _requests.isEmpty
                    ? const SizedBox()
                    : single
                        // 1 request → full-page single view
                        ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), child: _requestCard(_requests.first, big: true))
                        // multiple → scrollable list
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            itemCount: _requests.length,
                            itemBuilder: (_, i) => _requestCard(_requests[i]),
                          ),
          ),
        ]),
      ),
    );
  }

  ({Color color, String label}) _serviceMeta(String s) {
    switch (s) {
      case 'outstation': return (color: AppColors.orange, label: 'OUTSTATION');
      case 'rental': return (color: AppColors.primary, label: 'RENTAL');
      case 'hire_driver': return (color: Colors.indigo, label: 'HIRE DRIVER');
      case 'delivery': return (color: Colors.teal, label: 'PARCEL');
      default: return (color: AppColors.primary, label: 'TAXI');
    }
  }

  Widget _requestCard(RideRequestModel r, {bool big = false}) {
    final meta = _serviceMeta(r.service);
    return _RequestCard(
      key: ValueKey(r.id),
      ride: r,
      serviceColor: meta.color,
      serviceLabel: meta.label,
      enabled: !_accepting,
      driverLat: _driverLat,
      driverLng: _driverLng,
      onAccept: () => _accept(r),
      onReject: () => _reject(r),
      onTimeout: () => _timedOut(r),
    );
  }
}

// Fare display: base ride price + tip (e.g. "₹142 + ₹55").
// Tip is shown in green only when the rider actually added one; otherwise
// just the ride price is shown.
Widget _fareWithTip(RideRequestModel r) {
  final base = r.baseFare > 0 ? r.baseFare : r.totalFareValue;
  final hasTip = r.tipAmount > 0;
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('₹${base.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 38, color: Cap.ink, letterSpacing: -0.5)),
        if (hasTip)
          Text('  + ₹${r.tipAmount.toStringAsFixed(0)} tip',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.green)),
      ],
    ),
  );
}

// A single ride-request card, styled after the reference layout:
// vehicle badge → big fare (+ tip) → pickup/drop route → reject (with a
// countdown ring) + a brand-coloured Accept button.
//
// The WHOLE card is swipeable: drag it RIGHT to accept, LEFT to reject.
// Each card also counts down; when it reaches zero it is dismissed locally
// (onTimeout) — not rejected on the server.
class _RequestCard extends StatefulWidget {
  final RideRequestModel ride;
  final Color serviceColor;
  /// PARCEL, OUTSTATION… — shown for every service but a plain taxi ride.
  final String serviceLabel;
  final bool enabled;
  final double? driverLat, driverLng;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  /// Countdown reached zero. Separate from [onReject] so a timeout never
  /// records a server-side rejection.
  final VoidCallback onTimeout;
  const _RequestCard({
    super.key,
    required this.ride,
    required this.serviceColor,
    required this.serviceLabel,
    required this.enabled,
    required this.driverLat,
    required this.driverLng,
    required this.onAccept,
    required this.onReject,
    required this.onTimeout,
  });
  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> with SingleTickerProviderStateMixin {
  // Fallback window for a request that was never offered exclusively (the open
  // pool). When the server DID offer this ride to us it sends offerExpiresAt,
  // and we count down to that instead — a fixed 15s here disagreed with the
  // server's 20s offer window, so the ring expired while the offer was still
  // ours to take.
  static const int _fallbackTotal = 15;
  late final int _total;
  late int _left;
  Timer? _t;
  bool _handled = false;
  // Drains the ring round the decline button smoothly, full → empty over the
  // offer window (the 1 s timer below still decides when the card times out).
  late final AnimationController _ring;

  int _secondsLeft() {
    final until = widget.ride.offerExpiresAt;
    if (until == null) return _fallbackTotal;
    final s = until.difference(DateTime.now()).inSeconds;
    // Clamp: a clock-skewed or already-lapsed offer should not render a
    // negative ring, and should not sit there forever either.
    return s.clamp(1, 120);
  }

  @override
  void initState() {
    super.initState();
    _total = _secondsLeft();
    _left = _total;
    _ring = AnimationController(vsync: this, duration: Duration(seconds: _total), value: 1.0)
      ..reverse(from: 1.0);
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) _fire(widget.onTimeout);
      else setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _ring.dispose();
    super.dispose();
  }

  // Run accept/reject exactly once (swipe, tap and the timer can all race).
  void _fire(VoidCallback cb) {
    if (_handled) return;
    _handled = true;
    _t?.cancel();
    _ring.stop();
    cb();
  }

  // Decline button wrapped in the countdown ring (Rapido / Uber style).
  Widget _declineWithRing(bool urgent) {
    final color = urgent ? AppColors.red : Cap.accent;
    return SizedBox(
      width: 64, height: 64,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ring,
            builder: (context, child) => CircularProgressIndicator(
              key: const ValueKey('decline_countdown_ring'),
              value: _ring.value,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              backgroundColor: Cap.tile,
              color: color,
            ),
          ),
        ),
        Tooltip(
          message: 'Decline',
          child: Material(
            color: AppColors.red.withValues(alpha: 0.10),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.enabled ? () => _fire(widget.onReject) : null,
              child: const SizedBox(
                width: 50, height: 50,
                child: Icon(Icons.close, color: AppColors.red, size: 24),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final frac = _total > 0 ? _left / _total : 0.0;
    final urgent = _left <= 5;
    return Dismissible(
      key: ValueKey('dis_${r.id}'),
      // Swiping the card left declines. Accepting is ONLY the slide track below
      // — a right-swipe of the whole card accepted on a brush.
      direction: widget.enabled ? DismissDirection.endToStart : DismissDirection.none,
      confirmDismiss: (dir) async {
        if (!widget.enabled) return false;
        _fire(widget.onReject);
        return false; // parent handles removal / navigation
      },
      background: _swipeBg(Alignment.centerRight, AppColors.red, Icons.close, 'REJECT'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Cap.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Countdown bar across the top of the card
          LinearProgressIndicator(
            value: frac,
            minHeight: 5,
            backgroundColor: Cap.tile,
            color: urgent ? AppColors.red : Cap.accent,
          ),
          // Service + vehicle chips, seconds left
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_vehicleIcon(r.rideType), size: 16, color: Cap.ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_cap(r.rideType.isNotEmpty ? r.rideType : 'Auto'),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Cap.body(size: 13, weight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
              // What kind of job this is. A parcel or a 300 km outstation trip
              // must not look like a ride across town.
              if (r.service != 'taxi') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.serviceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(widget.serviceLabel,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5,
                          letterSpacing: 0.4, color: widget.serviceColor)),
                ),
              ],
              const Spacer(),
              Text('${_left}s',
                  style: Cap.body(size: 13, weight: FontWeight.w900, color: urgent ? AppColors.red : Cap.muted)),
            ]),
          ),
          // Big fare + tip, payment mode
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: _fareWithTip(r),
          ),
          if (r.estDriverEarning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(youGetText(r.estDriverEarning!),
                  key: ValueKey('you_get_${r.id}'),
                  style: Cap.body(size: 14.5, weight: FontWeight.w900, color: AppColors.green)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _paymentLine(r),
          ),
          // Booked for a lower tier than this driver's own (a Prime SUV driver
          // taking a Cab ride): the fare above is that tier's.
          if (lowerTierRideLabel(r.vehicleTypeName, ownVehicleTypeOf(context)) case final tier?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LowerTierChip(tier, key: ValueKey('lower_tier_${r.id}')),
              ),
            ),
          // Booked for someone else: who to look for at pickup, and who booked.
          if (bookedForLabel(r) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                key: ValueKey('booked_for_${r.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_pin_circle_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(bookedForLabel(r)!,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Cap.body(size: 13.5, weight: FontWeight.w900, color: AppColors.primary)),
                  ),
                ]),
              ),
            ),
          // What the feed knows about the job beyond the fare: the rider's
          // rating, stops, a round trip and its return, passengers, the rental
          // package, the hire's hours and gearbox, the outstation cities.
          if (requestFacts(r).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in requestFacts(r)) _factChip(f),
              ]),
            ),
          // A booking for later (a scheduled taxi, or outstation / rental /
          // hire listed up to 48 h ahead): when it is due, plainly.
          if (showsScheduledTime(r))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                key: ValueKey('scheduled_${r.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.event_outlined, size: 18, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(scheduledLabel(r.dueAt!),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Cap.body(size: 13.5, weight: FontWeight.w900, color: AppColors.orange)),
                  ),
                ]),
              ),
            ),
          if (r.service == 'delivery')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _parcelLine(r),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 1, color: Cap.divider),
          ),
          // Route (pickup → drop) with the dot / line / square connector.
          // Rental and hire have no drop: then only the pickup is shown, never
          // a "DROP 0 km" row with no address.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: r.dropAddress.trim().isEmpty
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                      child: Container(width: 10, height: 10,
                          decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _leg('Pickup', _pickupKm(), r.pickupAddress)),
                  ])
                : IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        width: 14,
                        child: Column(children: [
                          const SizedBox(height: 6),
                          Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                          Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: Cap.divider)),
                          Container(width: 10, height: 10,
                              decoration: BoxDecoration(color: Cap.ink, borderRadius: BorderRadius.circular(1.5))),
                          const SizedBox(height: 6),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _leg('Pickup', _pickupKm(), r.pickupAddress),
                          const SizedBox(height: 14),
                          _leg('Drop', _dropKm(), r.dropAddress),
                        ]),
                      ),
                    ]),
                  ),
          ),
          // Actions: decline + big Accept
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              _declineWithRing(urgent),
              const SizedBox(width: 12),
              Expanded(
                // Slide to accept (Uber / Rapido style): commits only past 85%
                // of the track; released earlier it snaps back. Disabled while
                // an accept is in flight, and _fire runs it exactly once.
                child: SwipeToConfirm(
                  key: ValueKey('accept_${r.id}'),
                  label: 'Slide to accept',
                  tone: SwipeTone.success,
                  icon: Icons.keyboard_double_arrow_right_rounded,
                  enabled: widget.enabled && !_handled,
                  onConfirm: () async => _fire(widget.onAccept),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _factChip(RequestFact f) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(f.icon, size: 14, color: f.icon == Icons.star_rounded ? AppColors.orange : Cap.ink),
      const SizedBox(width: 4),
      Flexible(
        child: Text(f.text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Cap.body(size: 12, weight: FontWeight.w800)),
      ),
    ]),
  );

  // What the parcel is, before the driver takes it on: a bike will not carry
  // every carton, and a fragile or cash-on-delivery job asks more of them.
  Widget _parcelLine(RideRequestModel r) {
    String kg(double w) => w == w.roundToDouble() ? '${w.round()} kg' : '${w.toStringAsFixed(1)} kg';
    final facts = [
      r.itemType.isNotEmpty ? r.itemType : 'Parcel',
      if (r.weightKg > 0) kg(r.weightKg),
      if (r.packageSize.isNotEmpty) 'Size ${r.packageSize}',
    ];
    Widget chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
    );
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inventory_2_outlined, size: 16, color: widget.serviceColor),
        const SizedBox(width: 6),
        Flexible(child: Text(facts.join(' · '),
            style: Cap.body(size: 13, weight: FontWeight.w700))),
      ]),
      if (r.isFragile) chip('Fragile', AppColors.orange),
      if (r.codAmount > 0) chip('COD ₹${r.codAmount.toStringAsFixed(0)}', Colors.teal),
    ]);
  }

  // Driver → pickup distance heading. Prefers a backend-supplied value;
  // otherwise computes it from the driver's location and the pickup coords.
  String _pickupKm() {
    final r = widget.ride;
    // Server value is road-corrected and carries the learned-speed ETA with it.
    if (r.pickupDistanceKm > 0) {
      final km = '${r.pickupDistanceKm.toStringAsFixed(1)} Km';
      return r.eta != '—' ? '$km · ${r.eta}' : km;
    }
    if (widget.driverLat != null && widget.driverLng != null && r.pickupLat != 0 && r.pickupLng != 0) {
      final m = Geolocator.distanceBetween(widget.driverLat!, widget.driverLng!, r.pickupLat, r.pickupLng);
      return '${(m / 1000).toStringAsFixed(1)} Km';
    }
    return ''; // no location yet → show pickup without a distance heading
  }

  // Trip distance heading (pickup → drop).
  String _dropKm() {
    final r = widget.ride;
    if (r.distanceKm > 0) return '${r.distanceKm.toStringAsFixed(1)} Km';
    return r.distance;
  }

  // One leg of the route: small label, big km heading, "Name - address".
  Widget _leg(String label, String km, String address) {
    final split = address.split(' - ');
    final name = split.first.trim();
    final rest = split.length > 1 ? split.sublist(1).join(' - ').trim() : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label.toUpperCase(),
            style: Cap.caption(size: 10.5).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        if (km.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(km, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Cap.body(size: 15, weight: FontWeight.w900)),
          ),
        ],
      ]),
      const SizedBox(height: 2),
      // Text.rich, not RichText: it follows the theme's font and the
      // driver's text size setting like the rest of the card.
      Text.rich(
        TextSpan(children: [
          TextSpan(text: name, style: Cap.body(size: 14, weight: FontWeight.w800)),
          if (rest.isNotEmpty)
            TextSpan(text: ' - $rest', style: Cap.body(size: 12.5, weight: FontWeight.w400, color: Cap.muted)),
        ]),
        maxLines: 3, overflow: TextOverflow.ellipsis,
      ),
    ]);
  }

  Widget _paymentLine(RideRequestModel r) {
    final cash = r.paymentMode == 'cash';
    final wallet = r.paymentMode == 'wallet';
    final c = cash ? AppColors.green : Cap.accent;
    return Row(children: [
      Icon(cash ? Icons.payments_outlined : (wallet ? Icons.account_balance_wallet_outlined : Icons.credit_card),
          size: 16, color: c),
      const SizedBox(width: 6),
      Flexible(
        child: Text(cash ? 'Cash — collect from rider' : (wallet ? 'Paid via Wallet' : 'Paid Online'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Cap.body(size: 12.5, weight: FontWeight.w700, color: c)),
      ),
    ]);
  }

  // Full-bleed coloured background revealed while swiping the card.
  Widget _swipeBg(Alignment align, Color c, IconData ic, String label) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 28),
    alignment: align,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ic, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
    ]),
  );

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static IconData _vehicleIcon(String v) {
    final s = v.toLowerCase();
    if (s.contains('auto')) return Icons.electric_rickshaw;
    if (s.contains('bike') || s.contains('moto')) return Icons.two_wheeler;
    if (s.contains('suv') || s.contains('xl')) return Icons.airport_shuttle;
    return Icons.local_taxi;
  }
}

/// The request ringtone: the admin's file for the service, else the bundled
/// default.
Source ringtoneSource(String adminPath) => adminPath.trim().isEmpty
    ? AssetSource(defaultRingtoneAsset)
    : UrlSource(AppConfig.imageUrl(adminPath));

/// How often the open request page re-reads the feed (taken / new requests).
/// The home screen's poller already found these; 3 s was more than needed.
const requestRefreshEvery = Duration(seconds: 5);

/// The ringtone's audio: an alarm-class sound, so it follows the alarm volume
/// and is heard with media muted, and it keeps the CPU awake while it rings.
final requestRingContext = AudioContext(
  android: const AudioContextAndroid(
    usageType: AndroidUsageType.alarm,
    contentType: AndroidContentType.sonification,
    audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    stayAwake: true,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
);

/// "You get ≈ ₹118" — the server's estimate of the driver's part.
String youGetText(num est) => 'You get ≈ ₹${est.round()}';

/// One fact on a request card.
/// "For: Asha (booked by Rahul)" when the rider booked this request for
/// someone else; null for a rider travelling themselves.
String? bookedForLabel(RideRequestModel r) {
  if (!r.isForOther) return null;
  final booker = r.userName.trim();
  return booker.isEmpty || booker == 'Rider'
      ? 'For: ${r.passengerName.trim()}'
      : 'For: ${r.passengerName.trim()} (booked by $booker)';
}

class RequestFact {
  final IconData icon;
  final String text;
  const RequestFact(this.icon, this.text);
  @override
  String toString() => text;
}

String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// The extra facts a request card shows, in order.
List<RequestFact> requestFacts(RideRequestModel r, {DateTime? now}) {
  String when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : scheduledLabel(t, now: now).replaceFirst('Scheduled for ', '');
  }
  final facts = <RequestFact>[];
  if (r.riderRating > 0) facts.add(RequestFact(Icons.star_rounded, r.riderRating.toStringAsFixed(1)));
  if (r.service == 'outstation' && r.cityFrom.trim().isNotEmpty && r.cityTo.trim().isNotEmpty) {
    facts.add(RequestFact(Icons.alt_route_rounded, '${r.cityFrom.trim()} → ${r.cityTo.trim()}'));
  }
  if (r.tripType == 'round_trip') {
    final back = when(r.returnAt);
    facts.add(RequestFact(Icons.sync_alt_rounded, back.isEmpty ? 'Round trip' : 'Round trip · back $back'));
  }
  if (r.stops.isNotEmpty) facts.add(RequestFact(Icons.more_horiz_rounded, _plural(r.stops.length, 'stop')));
  if (r.numPassengers > 0) facts.add(RequestFact(Icons.people_alt_outlined, _plural(r.numPassengers, 'passenger')));
  if (r.service == 'rental' && (r.packageHours > 0 || r.packageKm > 0)) {
    facts.add(RequestFact(Icons.timer_outlined, [
      if (r.packageHours > 0) '${r.packageHours} hr',
      if (r.packageKm > 0) '${r.packageKm} km',
    ].join(' · ')));
  }
  if (r.service == 'hire_driver') {
    if (r.hireTotalHours > 0) facts.add(RequestFact(Icons.timer_outlined, '${r.hireTotalHours} hr hire'));
    final gear = r.transmission.trim().toLowerCase();
    if (gear.isNotEmpty) {
      facts.add(RequestFact(Icons.settings_outlined,
          gear.startsWith('auto') ? 'Automatic' : gear.startsWith('man') ? 'Manual' : r.transmission.trim()));
    }
  }
  return facts;
}

/// Bundled request ringtone, played when no admin ringtone is set.
const defaultRingtoneAsset = 'sounds/ride_request.mp3';

/// What to try, in order: the admin's file (if any), then the bundled one.
/// The phone's own notification sound comes after both (DeviceChannel).
List<Source> ringtoneSources(String adminPath) => [
  if (adminPath.trim().isNotEmpty) UrlSource(AppConfig.imageUrl(adminPath)),
  AssetSource(defaultRingtoneAsset),
];

/// A card shows its due time when the job is booked for later: a scheduledAt,
/// or a departure / hire start more than 10 minutes ahead (the server's
/// SCHEDULED_AFTER_MS).
bool showsScheduledTime(RideRequestModel r, {DateTime? now}) {
  final due = r.dueAt;
  if (due == null) return false;
  if (r.scheduledAt != null) return true;
  return due.isAfter((now ?? DateTime.now()).add(const Duration(minutes: 10)));
}

/// After accepting an advance booking.
String upcomingAcceptedText(DateTime due, {DateTime? now}) =>
    'Trip accepted for ${scheduledLabel(due, now: now).replaceFirst('Scheduled for ', '')}. '
    'It is listed on Home as your upcoming trip; you keep getting other requests until an hour before.';

/// "Scheduled for Today, 6:30 PM" / "Scheduled for 28 Nov, 9:05 AM".
String scheduledLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = at.hour == 0 ? 12 : (at.hour > 12 ? at.hour - 12 : at.hour);
  final time = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour >= 12 ? 'PM' : 'AM'}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  final date = diff == 0 ? 'Today' : diff == 1 ? 'Tomorrow' : '${at.day} ${m[at.month - 1]}';
  return 'Scheduled for $date, $time';
}
