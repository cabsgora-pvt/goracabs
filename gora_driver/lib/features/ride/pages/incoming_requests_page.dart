import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../logic/dismissed_requests.dart';
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
  final Set<String> _rejectedIds = {};
  Timer? _timer;
  bool _accepting = false;
  bool _firstLoaded = false;

  // Per-service ringtone (admin-managed) + player
  Map<String, String> _ringtones = {};
  final AudioPlayer _player = AudioPlayer();
  String? _playingService;
  bool _closed = false; // guards against double-pop (which lands on the start screen)

  // Driver's current location — used to compute the driver → pickup distance
  // shown on each card. Fetched once when the screen opens.
  double? _driverLat, _driverLng;

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
    try {
      final cfg = await DriverApiService.getDriverConfig();
      final r = (cfg['ringtones'] as Map?) ?? {};
      _ringtones = r.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    await _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_accepting || _closed || !mounted) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      final models = rides
          .map((e) => RideRequestModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((m) => !_rejectedIds.contains(m.id))
          .where((m) => !DismissedRequests.isSuppressed(m.id,
              offeredToMe: m.offeredToMe, offerExpiresAt: m.offerExpiresAt))
          .take(_maxRequests)
          .toList();
      if (!mounted || _closed) return;
      _firstLoaded = true;
      if (models.isEmpty) { _close(); return; }
      setState(() => _requests = models);
      _updateRing();
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
    try {
      await _player.stop();
      if (rel.isEmpty) return; // no custom ringtone set for this service
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(UrlSource(AppConfig.imageUrl(rel)));
    } catch (_) {}
  }

  Future<void> _stopRing() async {
    _playingService = null;
    try { await _player.stop(); } catch (_) {}
  }

  // Close the screen exactly once (timer's _refresh and button handlers could
  // otherwise both pop, removing the home screen and leaving a blank start view).
  void _close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _stopRing();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _accept(RideRequestModel m) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _timer?.cancel();
    await _stopRing();
    final r = await DriverApiService.acceptRide(m.id);
    if (!mounted) return;
    if (r['success'] == true || r['ride'] != null) {
      Navigator.pushReplacementNamed(context, OnRidePage.route, arguments: m);
    } else {
      // Taken by someone else or error → drop it and resume
      _rejectedIds.add(m.id);
      setState(() { _requests.removeWhere((x) => x.id == m.id); _accepting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Ride already taken')),
      );
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
      if (_requests.isEmpty) { _close(); } else { _updateRing(); }
    }
  }

  // Explicit reject (tap on ✕ or swipe left): the server records rejectedBy so
  // this ride is not offered to this driver again.
  void _reject(RideRequestModel m) {
    _rejectedIds.add(m.id);
    DriverApiService.rejectRide(m.id); // fire-and-forget; server records rejectedBy
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
    if (!mounted) return;
    setState(() => _requests.removeWhere((x) => x.id == m.id));
    if (_requests.isEmpty) { _close(); } else { _updateRing(); }
  }

  @override
  Widget build(BuildContext context) {
    final single = _requests.length == 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary])),
            child: Column(children: [
              Text(single ? 'New Ride Request' : '${_requests.length} New Requests',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text(single ? 'Swipe to accept or reject' : 'Swipe any request to accept / reject',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          Expanded(
            child: !_firstLoaded
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? const SizedBox()
                    : single
                        // 1 request → full-page single view
                        ? SingleChildScrollView(padding: const EdgeInsets.all(14), child: _requestCard(_requests.first, big: true))
                        // multiple → scrollable list
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
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
      default: return (color: AppColors.green, label: 'TAXI');
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
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text('₹${base.toStringAsFixed(0)}',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 30, color: AppColors.textDark)),
      if (hasTip)
        Text('  + ₹${r.tipAmount.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.green)),
    ],
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

class _RequestCardState extends State<_RequestCard> {
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
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) _fire(widget.onTimeout);
      else setState(() => _left--);
    });
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  // Run accept/reject exactly once (swipe, tap and the timer can all race).
  void _fire(VoidCallback cb) {
    if (_handled) return;
    _handled = true;
    _t?.cancel();
    cb();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    return Dismissible(
      key: ValueKey('dis_${r.id}'),
      direction: widget.enabled ? DismissDirection.horizontal : DismissDirection.none,
      confirmDismiss: (dir) async {
        if (!widget.enabled) return false;
        _fire(dir == DismissDirection.startToEnd ? widget.onAccept : widget.onReject);
        return false; // parent handles removal / navigation
      },
      background: _swipeBg(Alignment.centerLeft, AppColors.green, Icons.check, 'ACCEPT'),
      secondaryBackground: _swipeBg(Alignment.centerRight, AppColors.red, Icons.close, 'REJECT'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Vehicle badge
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_vehicleIcon(r.rideType), size: 16, color: widget.serviceColor),
                  const SizedBox(width: 6),
                  Text(_cap(r.rideType.isNotEmpty ? r.rideType : 'Auto'),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark)),
                ]),
              ),
              // What kind of job this is. The label was worked out for every
              // service and never shown, so a parcel or a 300 km outstation
              // trip looked exactly like a ride across town.
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
            ]),
          ),
          // Big fare + tip
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: _fareWithTip(r),
          ),
          if (r.service == 'delivery')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _parcelLine(r),
            ),
          // Route (pickup → drop)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _leg(Icons.radio_button_checked, AppColors.green, _pickupKm(), r.pickupAddress),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(height: 22, child: Column(children: [
                  Expanded(child: Container(width: 2, color: AppColors.divider)),
                  Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textGrey),
                ])),
              ),
              _leg(Icons.location_on, AppColors.red, _dropKm(), r.dropAddress),
            ]),
          ),
          // Payment
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _paymentLine(r),
          ),
          // Actions: reject (with countdown ring) + brand-coloured Accept
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              GestureDetector(
                onTap: widget.enabled ? () => _fire(widget.onReject) : null,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 54, height: 54,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 54, height: 54,
                      child: CircularProgressIndicator(
                        value: _left / _total, strokeWidth: 3,
                        color: AppColors.red, backgroundColor: AppColors.divider,
                      ),
                    ),
                    const Icon(Icons.close, color: AppColors.red, size: 24),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.enabled ? () => _fire(widget.onAccept) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, // brand colour, not yellow
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

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
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark))),
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

  // One leg of the route: marker + optional big km heading + "Name - address".
  Widget _leg(IconData icon, Color color, String km, String address) {
    final split = address.split(' - ');
    final name = split.first.trim();
    final rest = split.length > 1 ? split.sublist(1).join(' - ').trim() : '';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (km.isNotEmpty)
          Text(km, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark)),
        // Text.rich, not RichText: it follows the theme's font and the
        // driver's text size setting like the rest of the card.
        Text.rich(
          TextSpan(children: [
            TextSpan(text: name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textDark)),
            if (rest.isNotEmpty)
              TextSpan(text: ' - $rest', style: TextStyle(fontWeight: FontWeight.w400, fontSize: 12.5, color: AppColors.textGrey)),
          ]),
          maxLines: 3, overflow: TextOverflow.ellipsis,
        ),
      ])),
    ]);
  }

  Widget _paymentLine(RideRequestModel r) {
    final cash = r.paymentMode == 'cash';
    final wallet = r.paymentMode == 'wallet';
    return Row(children: [
      Icon(cash ? Icons.payments : (wallet ? Icons.account_balance_wallet : Icons.credit_card),
          size: 15, color: cash ? AppColors.green : AppColors.primary),
      const SizedBox(width: 5),
      Text(cash ? 'Cash — collect from rider' : (wallet ? 'Paid via Wallet' : 'Paid Online'),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cash ? AppColors.green : AppColors.primary)),
    ]);
  }

  // Full-bleed coloured background revealed while swiping the card.
  Widget _swipeBg(Alignment align, Color c, IconData ic, String label) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 28),
    alignment: align,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)),
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
