import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import 'invoice_page.dart';
import 'collect_fare_page.dart';
import '../logic/job_settlement.dart';
import '../widgets/nav_map.dart';
import '../widgets/ride_shell.dart';
import '../widgets/ride_status_strip.dart';
import '../widgets/swipe_to_confirm.dart';

// Live hire-a-driver screen: time worked vs booked hours, extend, end with the
// overtime bill. Laid out in the shared RideShell.
class HireProgressPage extends StatefulWidget {
  static const route = '/hire-progress';
  final RideRequestModel ride;
  const HireProgressPage({super.key, required this.ride});
  @override
  State<HireProgressPage> createState() => _HireProgressPageState();
}

class _HireProgressPageState extends State<HireProgressPage> {
  Timer? _tick, _ping;

  // Time worked = the server's count at the last sync + local time since then.
  // Subtracting the server's start timestamp from the phone's clock inherited
  // the phone's error, and a reopened screen used "now" and read 0:00.
  final Stopwatch _clock = Stopwatch();
  Duration _base = Duration.zero;
  Duration get _elapsed => _base + _clock.elapsed;

  /// The server has recorded the start. Until then the screen retries it.
  bool _started = false;
  bool _ending = false;

  /// The hire has been priced ('end' succeeded), in this session or before the
  /// screen opened. From here the only way forward is collect and settle.
  bool _priced = false;
  Map<String, dynamic>? _endResponse;
  bool _cashInHand = false;
  // What the invoice shows once settled here: the earning after commission.
  Object? _invoice;

  late int _bookedHours;
  // Live overtime projection from the server, refreshed on each 30s ping.
  // Projection only — the billed figure is still computed once, in /hire 'end'.
  double _liveExtraCharge = 0;
  int _liveExtraHours = 0;

  @override
  void initState() {
    super.initState();
    _bookedHours = widget.ride.hireTotalHours;
    final p = widget.ride.progress;
    if (p.hirePhase == 'completed') {
      // Priced before this screen opened; nothing left to time.
      _priced = true;
    } else if (p.hireStarted) {
      // Reopened mid-job. It used to call 'start' again here, and the server
      // reset the hire to zero hours worked.
      _started = true;
      _sync(p.hireElapsedSec!);
      _run();
    } else {
      _run();
      _start();
    }
  }

  void _sync(int serverSeconds) {
    _base = Duration(seconds: serverSeconds);
    _clock..reset()..start();
  }

  void _run() {
    _clock.start();
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    _ping ??= Timer.periodic(const Duration(seconds: 30), (_) => _pingOnce());
  }

  Future<void> _start() async {
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.hireAction(widget.ride.id, {'action': 'start'});
    } catch (_) {
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    final secs = (res['hire'] as Map?)?['elapsedSec'];
    if (res['error'] == null && secs is num) {
      setState(() { _started = true; _sync(secs.toInt()); });
    }
    // On failure the clock keeps running locally and the next ping retries,
    // so a dropped connection at the kerb cannot leave the hire untimed.
  }

  /// Pings the server and keeps the returned overtime projection and clock.
  Future<void> _pingOnce() async {
    if (!_started) return _start();
    try {
      final res = await DriverApiService.hireAction(widget.ride.id, {'action': 'ping'});
      final h = res['hire'] as Map<String, dynamic>?;
      if (h == null || !mounted) return;
      setState(() {
        _liveExtraCharge = (h['liveExtraCharge'] as num?)?.toDouble() ?? _liveExtraCharge;
        _liveExtraHours = (h['liveExtraHours'] as num?)?.toInt() ?? _liveExtraHours;
        final booked = (h['totalHours'] as num?)?.toInt();
        if (booked != null && booked > 0) _bookedHours = booked;
        final secs = h['elapsedSec'];
        if (secs is num) _sync(secs.toInt());
      });
    } catch (_) {/* a dropped ping must never interrupt the job */}
  }

  Future<void> _extend() async {
    final h = await showDialog<int>(context: context, builder: (dctx) => SimpleDialog(
      title: const Text('Extend hire by'),
      children: [1, 2, 4].map((x) => SimpleDialogOption(onPressed: () => Navigator.pop(dctx, x), child: Text('+$x hours'))).toList()));
    if (h == null) return;
    final res = await DriverApiService.hireAction(widget.ride.id, {'action': 'extend', 'extraHours': h});
    if (!mounted) return;
    if (res['error'] != null) {
      // Used to add the hours on screen whether or not the server accepted them.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not extend: ${res['error']}'), backgroundColor: AppColors.red));
      return;
    }
    final booked = ((res['hire'] as Map?)?['totalHours'] as num?)?.toInt();
    setState(() => _bookedHours = booked ?? _bookedHours + h);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Extended by $h hr'), backgroundColor: AppColors.green));
  }

  // Price first, then collect, then settle. See collectAndSettle for why the
  // order matters; the hire flow once collected the booked fare before pricing.
  Future<void> _end() async {
    // Priced before this screen opened: the helper reads the bill from the server.
    if (_priced && _endResponse == null) {
      setState(() => _ending = true);
      await finishPricedJob(context, widget.ride);
      if (mounted) setState(() => _ending = false);
      return;
    }

    if (_endResponse == null) {
      setState(() => _ending = true);
      final res = await DriverApiService.hireAction(widget.ride.id, {'action': 'end'});
      if (!mounted) return;
      setState(() => _ending = false);
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
        return;
      }
      _tick?.cancel(); _ping?.cancel(); _clock.stop();
      setState(() { _endResponse = res; _priced = true; });
    }

    final res = _endResponse!;
    final due = (res['amountDue'] as num?)?.toDouble() ?? 0;
    // Once confirmed, a retry after a failed settlement goes straight to
    // settling — the driver is not asked to collect the same cash twice.
    if (due > 0 && !_cashInHand) {
      final collected = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: due)));
      if (collected != true || !mounted) return;
      _cashInHand = true;
    }
    setState(() => _ending = true);
    final invoice = await settleForInvoice(context, widget.ride);
    if (!mounted) return;
    setState(() => _ending = false);
    _invoice = invoice;
    if (invoice != null) _showBill(res['hire'] as Map<String, dynamic>? ?? {});
  }

  void _showBill(Map<String, dynamic> h) {
    final finalFare = (h['finalFare'] as num?) ?? 0;
    final extra = (h['extraCharge'] as num?) ?? 0;
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true,
      backgroundColor: AppColors.white,
      builder: (sheet) => Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(sheet).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hire Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 14),
          _row('Booked', '${h['totalHours'] ?? 0} hr'),
          _row('Worked', '${((h['actualHours'] as num?) ?? 0).toStringAsFixed(1)} hr'),
          const Divider(),
          // Was the formatted fare string with "₹ " stripped, which printed
          // "₹1,24,999" for some fares and "₹₹ 600" for others.
          _row('Base', '₹${(finalFare - extra).round()}'),
          if (extra > 0) _row('Overtime (${h['extraHours']} hr)', '₹${extra.round()}', color: AppColors.orange),
          const Divider(),
          _row('Total', '₹${finalFare.round()}', bold: true),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done',
            onTap: () => Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: _invoice ?? widget.ride))),
        ])));
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? AppColors.textDark))),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AppColors.textDark))]));

  @override
  void dispose() { _tick?.cancel(); _ping?.cancel(); super.dispose(); }

  String _fmt(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final over = !_priced && _elapsed.inMinutes / 60 > _bookedHours;
    return RideShell(
      rideId: r.id,
      vehicleType: r.rideType,
      // Hire has no fixed drop — the customer directs from their own vehicle.
      leg: NavLeg(label: 'Customer', destLat: r.pickupLat, destLng: r.pickupLng, destAddress: r.pickupAddress),
      phase: _priced ? 'HIRE · FINISHING' : (over ? 'HIRE · OVERTIME' : 'ON HIRE'),
      status: RideStatusStrip(
        phase: _priced ? 'Finishing' : (over ? 'Overtime' : 'On hire'),
        overrun: over,
        accruing: _priced ? null : _liveExtraCharge,
        accruingLabel: 'overtime',
        metrics: [
          if (!_priced)
            RideStatusMetric(Icons.timer_outlined, '${_fmt(_elapsed)} / ${_bookedHours}h', warn: over),
          if (_priced)
            RideStatusMetric(Icons.receipt_long, 'Bill ready'),
          if (_liveExtraHours > 0 && !_priced)
            RideStatusMetric(Icons.trending_up, '+${_liveExtraHours}h', warn: true),
        ],
      ),
      contact: RideContact(name: r.userName, phone: r.userPhone, role: 'Customer', picUrl: r.userProfilePicUrl),
      chatWith: r.userName,
      details: [
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Booked: $_bookedHours hr · ${r.transmission == 'automatic' ? 'Automatic' : 'Manual'}',
            style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(r.pickupAddress, style: TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        if (!_priced) ...[
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: over ? AppColors.orange : AppColors.divider, width: over ? 1.5 : 1)),
            child: Column(children: [
              Text('Time worked', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
              const SizedBox(height: 4),
              Text(_fmt(_elapsed), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
                color: over ? AppColors.orange : AppColors.textDark,
                fontFeatures: const [FontFeature.tabularFigures()])),
              Text('of $_bookedHours hr booked', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ])),
        ],
        if (over) Padding(padding: const EdgeInsets.only(top: 10), child: Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [Icon(Icons.warning_amber, color: AppColors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('Overtime — extra hours billed at per-hour rate', style: TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)))]))),
      ],
      actions: [
        if (!_priced) ...[
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _ending ? null : _extend,
            icon: const Icon(Icons.add, color: AppColors.green), label: const Text('Extend hours', style: TextStyle(color: AppColors.green)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: AppColors.green)))),
          const SizedBox(height: 10),
        ],
        SwipeToConfirm(
          label: _priced ? 'Swipe to finish the hire' : 'Swipe to end hire',
          tone: _priced ? SwipeTone.success : SwipeTone.danger,
          icon: _priced ? Icons.check_circle_outline : Icons.stop_circle_outlined,
          enabled: !_ending,
          onConfirm: _end,
        ),
      ],
    );
  }

  Widget _card(Widget child) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14)),
    child: child,
  );
}
