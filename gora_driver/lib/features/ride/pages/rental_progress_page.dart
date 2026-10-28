import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import 'invoice_page.dart';
import 'collect_fare_page.dart';
import '../logic/job_settlement.dart';
import '../widgets/nav_map.dart';
import '../widgets/ride_shell.dart';
import '../widgets/ride_status_strip.dart';
import '../widgets/swipe_to_confirm.dart';

// Live rental-in-progress screen: clock, odometer, waiting toggle, extend, end
// with extras. Laid out in the shared RideShell.
class RentalProgressPage extends StatefulWidget {
  static const route = '/rental-progress';
  final RideRequestModel ride;
  const RentalProgressPage({super.key, required this.ride});
  @override
  State<RentalProgressPage> createState() => _RentalProgressPageState();
}

class _RentalProgressPageState extends State<RentalProgressPage> {
  Timer? _tick;       // 1s UI timer
  Timer? _pingTimer;  // 15s location ping
  // Background stream keeps the odometer running when the app is not on screen.
  // The 15s ping alone stopped the moment the driver switched apps, so a
  // backgrounded rental accumulated no distance at all.
  StreamSubscription<Position>? _bgSub;

  // Time used = the server's count at the last sync + local time since then.
  // A reopened rental used to start this at the phone's "now" and read 0:00.
  final Stopwatch _clock = Stopwatch();
  Duration _base = Duration.zero;
  Duration get _elapsed => _base + _clock.elapsed;

  bool _started = false;
  double _actualKm = 0;
  bool _waiting = false;
  bool _ending = false;
  Map<String, dynamic>? _bill; // set once the server has priced the rental
  bool _cashInHand = false;
  // What the invoice shows once settled here: the earning after commission.
  Object? _invoice;
  /// Priced before this screen opened; the bill is read from the server.
  bool _pricedEarlier = false;

  // Live overrun, refreshed on every 15s ping. Projection only — never billed
  // from here; /end remains the single source of the final figure.
  String _phase = 'ongoing';
  double _liveExtraCharge = 0;
  int _liveExtraHours = 0;
  int _liveExtraKm = 0;

  // Package size can grow mid-rental ('extend'); the screen kept showing the
  // booked size, so an extended rental looked like it was over its limit.
  late int _pkgHours;
  late int _pkgKm;
  List<Map<String, dynamic>> _stops = []; // destinations the rider added live

  bool get _priced => _bill != null || _pricedEarlier;

  @override
  void initState() {
    super.initState();
    final r = widget.ride;
    final p = r.progress;
    _pkgHours = r.packageHours;
    _pkgKm = r.packageKm;
    if (p.rentalPhase == 'completed') {
      _pricedEarlier = true;
      return;
    }
    // Whatever the server already knows, restored before anything is fetched.
    _actualKm = p.actualKm;
    _waiting = p.rentalWaiting;
    _stops = p.rentalStops;
    if (p.rentalPhase.isNotEmpty) _phase = p.rentalPhase;
    if (p.rentalStarted) {
      _started = true;
      _sync(p.rentalElapsedSec!);
    }
    _run();
    // 'start' is idempotent on the server, so it is safe to call either way; it
    // also returns the rental's current figures.
    if (!_started) _start();
  }

  void _sync(int serverSeconds) {
    _base = Duration(seconds: serverSeconds);
    _clock..reset()..start();
  }

  void _run() {
    _clock.start();
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    _pingTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => _ping());
    _bgSub ??= LocationService.liveLocation(
      background: true,
      distanceFilter: 25,
      notificationText: 'Rental in progress — tracking distance',
    ).listen((pos) {
      DriverApiService.rentalAction(widget.ride.id, {
        'action': 'ping', 'lat': pos.latitude, 'lng': pos.longitude,
      }).catchError((_) => <String, dynamic>{});
    }, onError: (_) {});
  }

  Future<void> _start() async {
    final pos = await LocationService.getCurrentLocation();
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.rentalAction(widget.ride.id, {
        'action': 'start', 'lat': pos?.latitude, 'lng': pos?.longitude,
      });
    } catch (_) {
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    _apply(res['rental'] as Map<String, dynamic>?);
  }

  Future<void> _ping() async {
    if (!_started) return _start();
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) return;
    try {
      final res = await DriverApiService.rentalAction(widget.ride.id, {
        'action': 'ping', 'lat': pos.latitude, 'lng': pos.longitude,
      });
      if (mounted) _apply(res['rental'] as Map<String, dynamic>?);
    } catch (_) {/* a dropped ping must never interrupt the job */}
  }

  /// Takes the server's view of the rental.
  void _apply(Map<String, dynamic>? r) {
    if (r == null) return;
    setState(() {
      final secs = r['elapsedSec'];
      if (secs is num) { _started = true; _sync(secs.toInt()); }
      _actualKm = (r['actualKm'] as num?)?.toDouble() ?? _actualKm;
      if (r['isWaiting'] is bool) _waiting = r['isWaiting'] as bool;
      if (r['rentalStops'] is List) {
        _stops = (r['rentalStops'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      _pkgHours = (r['packageHours'] as num?)?.toInt() ?? _pkgHours;
      _pkgKm = (r['packageKm'] as num?)?.toInt() ?? _pkgKm;
      // Server-computed with the same formula /end uses, so the running total
      // and the closing bill cannot disagree.
      _phase = (r['phase'] ?? _phase).toString();
      _liveExtraCharge = (r['liveExtraCharge'] as num?)?.toDouble() ?? _liveExtraCharge;
      _liveExtraHours = (r['liveExtraHours'] as num?)?.toInt() ?? _liveExtraHours;
      _liveExtraKm = (r['liveExtraKm'] as num?)?.toInt() ?? _liveExtraKm;
    });
  }

  Future<void> _toggleWait() async {
    final pos = await LocationService.getCurrentLocation();
    final wanted = !_waiting;
    setState(() => _waiting = wanted);
    final res = await DriverApiService.rentalAction(widget.ride.id, {
      'action': 'wait', 'isWaiting': wanted, 'lat': pos?.latitude, 'lng': pos?.longitude,
    });
    if (!mounted) return;
    if (res['error'] != null) {
      // The toggle used to stay flipped on screen while the server still
      // counted km — the driver thought they were parked and were not.
      setState(() => _waiting = !wanted);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not update waiting: ${res['error']}'), backgroundColor: AppColors.red));
      return;
    }
    _apply(res['rental'] as Map<String, dynamic>?);
  }

  Future<void> _extend() async {
    final hrs = await showDialog<int>(context: context, builder: (dctx) => SimpleDialog(
      title: const Text('Extend rental by'),
      children: [2, 4, 6].map((h) => SimpleDialogOption(
        onPressed: () => Navigator.pop(dctx, h), child: Text('+$h hours'),
      )).toList(),
    ));
    if (hrs == null) return;
    final res = await DriverApiService.rentalAction(widget.ride.id, {'action': 'extend', 'extraHours': hrs});
    if (!mounted) return;
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not extend: ${res['error']}'), backgroundColor: AppColors.red));
      return;
    }
    _apply(res['rental'] as Map<String, dynamic>?);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Extended +$hrs hr'), backgroundColor: AppColors.green));
  }

  // End → bill → collect → settle.
  //
  // The old order collected cash BEFORE calling 'end', so it charged the booked
  // base fare and every extra hour/km was computed afterwards and never billed.
  // Now the server prices the rental first and the driver collects that number.
  Future<void> _end() async {
    if (_pricedEarlier) {
      setState(() => _ending = true);
      await finishPricedJob(context, widget.ride);
      if (mounted) setState(() => _ending = false);
      return;
    }
    if (_bill == null) {
      setState(() => _ending = true);
      final pos = await LocationService.getCurrentLocation();
      final res = await DriverApiService.rentalAction(widget.ride.id, {
        'action': 'end', 'lat': pos?.latitude, 'lng': pos?.longitude,
      });
      if (!mounted) return;
      setState(() => _ending = false);
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
        return;
      }
      _tick?.cancel(); _pingTimer?.cancel(); _bgSub?.cancel(); _clock.stop();
      setState(() => _bill = (res['rental'] as Map<String, dynamic>?) ?? {});
    }
    await _settle();
  }

  double get _amountDue => ((_bill?['finalFare'] as num?) ?? 0).toDouble();

  Future<void> _settle() async {
    final bill = _bill;
    if (bill == null) return;

    if (widget.ride.paymentMode == 'cash') {
      if (!_cashInHand) {
        final collected = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: _amountDue)));
        // Cancelled → stay put; the swipe now reads "Collect ₹X & finish".
        if (collected != true || !mounted) { if (mounted) setState(() {}); return; }
        _cashInHand = true;
      }
      // Settlement (commission, driver wallet, Transaction) happens here.
      setState(() => _ending = true);
      final invoice = await settleForInvoice(context, widget.ride);
      if (!mounted) return;
      setState(() => _ending = false);
      if (invoice == null) return;
      _invoice = invoice;
    }
    // Online/wallet: the rider is prompted to pay the final amount in their app,
    // and their payment call completes + settles the ride.
    if (!mounted) return;
    _showBill(bill);
  }

  void _showBill(Map<String, dynamic> r) {
    num n(dynamic v) => v is num ? v : 0;
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true,
      backgroundColor: AppColors.white,
      builder: (sheet) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(sheet).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rental Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 16),
          _billRow('Used', '${n(r['actualHours']).toStringAsFixed(1)} hr / ${n(r['actualKm']).toStringAsFixed(1)} km'),
          _billRow('Package', '${r['packageHours'] ?? 0} hr / ${r['packageKm'] ?? 0} km'),
          const Divider(),
          _billRow('Base', '₹${r['baseFare'] ?? 0}'),
          if (n(r['extraHoursCharge']) > 0) _billRow('Extra hours', '₹${r['extraHoursCharge']}', color: AppColors.orange),
          if (n(r['extraKmCharge']) > 0) _billRow('Extra km', '₹${r['extraKmCharge']}', color: AppColors.orange),
          if (n(r['nightCharge']) > 0) _billRow('Night charge', '₹${r['nightCharge']}'),
          const Divider(),
          _billRow('Total', '₹${r['finalFare'] ?? 0}', bold: true),
          if (r['awaitingPayment'] == true)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(
              'Waiting for the rider to pay online — the ride closes once they do.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey))),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', onTap: () {
            Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: _invoice ?? widget.ride);
          })),
        ]),
      ),
    );
  }

  Widget _billRow(String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? AppColors.textDark))),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AppColors.textDark)),
    ]),
  );

  @override
  void dispose() { _tick?.cancel(); _pingTimer?.cancel(); _bgSub?.cancel(); super.dispose(); }

  String _fmt(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final overHr = !_priced && _elapsed.inMinutes / 60 > _pkgHours;
    final overKm = !_priced && _actualKm > _pkgKm;
    final extraTime = !_priced && _phase == 'extra_time';

    final swipeLabel = _pricedEarlier
        ? 'Swipe to finish the rental'
        : _bill != null
            ? (r.paymentMode == 'cash'
                ? 'Swipe to collect ₹${_amountDue.toStringAsFixed(0)} & finish'
                : 'Swipe to finish')
            : 'Swipe to end rental';

    return RideShell(
      rideId: r.id,
      vehicleType: r.rideType,
      // Rental has no fixed drop, so the leg follows whatever destination the
      // rider most recently added (falls back to pickup).
      leg: _stops.isNotEmpty
          ? NavLeg(
              label: 'Stop ${_stops.length}',
              destLat: (_stops.last['lat'] as num?)?.toDouble(),
              destLng: (_stops.last['lng'] as num?)?.toDouble(),
              destAddress: (_stops.last['address'] ?? '').toString(),
            )
          : NavLeg(label: 'Pickup', destLat: r.pickupLat, destLng: r.pickupLng, destAddress: r.pickupAddress),
      // Under way, a rental only has somewhere to drive once the rider adds a
      // stop; it was pointing back at the pickup ("You have reached Pickup").
      hasDestination: !_priced && _stops.isNotEmpty,
      phase: _priced ? 'RENTAL · FINISHING' : (_waiting ? 'RENTAL · WAITING' : (extraTime ? 'RENTAL · EXTRA TIME' : 'ON RENTAL')),
      // Pinned: the driver must be able to see they are into extra time, and how
      // much it has reached, without hunting for it.
      status: RideStatusStrip(
        phase: _priced ? 'Finishing' : (_waiting ? 'Waiting' : (extraTime ? 'Extra time' : 'On rental')),
        overrun: extraTime,
        accruing: _priced ? null : _liveExtraCharge,
        metrics: _priced
            ? const [RideStatusMetric(Icons.receipt_long, 'Bill ready')]
            : [
                RideStatusMetric(Icons.timer_outlined, '${_fmt(_elapsed)} / ${_pkgHours}h', warn: _liveExtraHours > 0),
                RideStatusMetric(Icons.route, '${_actualKm.toStringAsFixed(1)} / $_pkgKm km', warn: _liveExtraKm > 0),
              ],
      ),
      contact: RideContact(name: r.userName, phone: r.userPhone, role: 'Rider', picUrl: r.userProfilePicUrl),
      chatWith: r.userName,
      details: [
        Container(
          padding: const EdgeInsets.all(14), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Package: $_pkgHours hr / $_pkgKm km', style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(r.pickupAddress, style: TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        // Destinations added by the rider (live)
        if (_stops.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.route, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Rider destinations',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textDark))),
              ]),
              const SizedBox(height: 8),
              ..._stops.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      CircleAvatar(radius: 11, backgroundColor: AppColors.primary,
                          child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value['address']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textDark))),
                    ]),
                  )),
            ]),
          ),
        ],
        if (!_priced) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _metric('Time used', _fmt(_elapsed), 'of $_pkgHours hr', overHr)),
            const SizedBox(width: 10),
            Expanded(child: _metric('Distance', '${_actualKm.toStringAsFixed(1)} km', 'of $_pkgKm km', overKm)),
          ]),
        ],
        if (overHr || overKm) Padding(padding: const EdgeInsets.only(top: 10), child: Container(
          padding: const EdgeInsets.all(10), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [Icon(Icons.warning_amber, color: AppColors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('Package limit exceeded — extra charges apply', style: TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)))]),
        )),
      ],
      actions: [
        if (!_priced) ...[
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _ending ? null : _toggleWait,
              icon: Icon(_waiting ? Icons.play_arrow : Icons.pause, color: AppColors.primary),
              label: Text(_waiting ? 'Resume' : 'Waiting', style: const TextStyle(color: AppColors.primary)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: AppColors.primary)),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: _ending ? null : _extend, icon: const Icon(Icons.add, color: AppColors.green),
              label: const Text('Extend', style: TextStyle(color: AppColors.green)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: AppColors.green)),
            )),
          ]),
          const SizedBox(height: 10),
        ],
        // Swipe, not tap: ending prices the rental and starts collection, which
        // an accidental tap in a moving vehicle must not be able to do.
        SwipeToConfirm(
          label: swipeLabel,
          tone: _priced ? SwipeTone.success : SwipeTone.danger,
          icon: _priced ? Icons.check_circle_outline : Icons.stop_circle_outlined,
          enabled: !_ending,
          onConfirm: _end,
        ),
      ],
    );
  }

  Widget _metric(String label, String value, String sub, bool over) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: over ? AppColors.orange : AppColors.divider, width: over ? 1.5 : 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
          color: over ? AppColors.orange : AppColors.textDark,
          fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      Text(sub, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
    ]),
  );
}
