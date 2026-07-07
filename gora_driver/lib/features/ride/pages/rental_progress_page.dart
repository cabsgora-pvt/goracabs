import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import 'invoice_page.dart';
import 'emergency_actions_page.dart';
import 'collect_fare_page.dart';

// Live rental-in-progress screen: timer, odometer, waiting toggle, extend, end with extras.
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
  Duration _elapsed = Duration.zero;
  DateTime _startedAt = DateTime.now();
  double _actualKm = 0;
  bool _waiting = false;
  bool _ending = false;

  int get _pkgHours => widget.ride.packageHours;
  int get _pkgKm => widget.ride.packageKm;
  List<Map<String, dynamic>> _stops = []; // destinations the rider added live

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final pos = await LocationService.getCurrentLocation();
    final res = await DriverApiService.rentalAction(widget.ride.id, {
      'action': 'start', 'lat': pos?.latitude, 'lng': pos?.longitude,
    });
    if (res['rental']?['rentalStartedAt'] != null) {
      _startedAt = DateTime.tryParse(res['rental']['rentalStartedAt'].toString())?.toLocal() ?? DateTime.now();
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _ping());
  }

  Future<void> _ping() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) return;
    final res = await DriverApiService.rentalAction(widget.ride.id, {
      'action': 'ping', 'lat': pos.latitude, 'lng': pos.longitude,
    });
    final r = res['rental'] as Map<String, dynamic>?;
    if (r != null && mounted) {
      setState(() {
        _actualKm = (r['actualKm'] as num?)?.toDouble() ?? _actualKm;
        _stops = ((r['rentalStops'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    }
  }

  Future<void> _toggleWait() async {
    final pos = await LocationService.getCurrentLocation();
    setState(() => _waiting = !_waiting);
    await DriverApiService.rentalAction(widget.ride.id, {
      'action': 'wait', 'isWaiting': _waiting, 'lat': pos?.latitude, 'lng': pos?.longitude,
    });
  }

  Future<void> _extend() async {
    final hrs = await showDialog<int>(context: context, builder: (_) => SimpleDialog(
      title: const Text('Extend rental by'),
      children: [2, 4, 6].map((h) => SimpleDialogOption(
        onPressed: () => Navigator.pop(context, h), child: Text('+$h hours'),
      )).toList(),
    ));
    if (hrs == null) return;
    await DriverApiService.rentalAction(widget.ride.id, {'action': 'extend', 'extraHours': hrs});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Extended +$hrs hr'), backgroundColor: AppColors.green));
  }

  Future<void> _end() async {
    // Cash → collect the fare via QR first
    if (widget.ride.paymentMode == 'cash') {
      final amt = widget.ride.totalFareValue > 0
          ? widget.ride.totalFareValue.toDouble()
          : (double.tryParse(widget.ride.fare.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0);
      final collected = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: amt)));
      if (collected != true) return;
    }
    setState(() => _ending = true);
    final pos = await LocationService.getCurrentLocation();
    final res = await DriverApiService.rentalAction(widget.ride.id, {
      'action': 'end', 'lat': pos?.latitude, 'lng': pos?.longitude,
    });
    _tick?.cancel(); _pingTimer?.cancel();
    if (!mounted) return;
    final r = res['rental'] as Map<String, dynamic>? ?? {};
    _showBill(r);
  }

  void _showBill(Map<String, dynamic> r) {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rental Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          _billRow('Used', '${(r['actualHours'] ?? 0).toStringAsFixed(1)} hr / ${(r['actualKm'] ?? 0).toStringAsFixed(1)} km'),
          _billRow('Package', '${r['packageHours'] ?? 0} hr / ${r['packageKm'] ?? 0} km'),
          const Divider(),
          _billRow('Base', '₹${widget.ride.fare.replaceAll('₹ ', '')}'),
          if ((r['extraHoursCharge'] ?? 0) > 0) _billRow('Extra hours', '₹${r['extraHoursCharge']}', color: AppColors.orange),
          if ((r['extraKmCharge'] ?? 0) > 0) _billRow('Extra km', '₹${r['extraKmCharge']}', color: AppColors.orange),
          const Divider(),
          _billRow('Total', '₹${r['finalFare'] ?? 0}', bold: true),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', onTap: () {
            Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: widget.ride);
          })),
        ]),
      ),
    );
  }

  Widget _billRow(String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
    ]),
  );

  @override
  void dispose() { _tick?.cancel(); _pingTimer?.cancel(); super.dispose(); }

  String _fmt(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final overHr = _elapsed.inMinutes / 60 > _pkgHours;
    final overKm = _actualKm > _pkgKm;
    return Scaffold(
      appBar: blueAppBar('Rental in Progress'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sos',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmergencyActionsPage(rideId: widget.ride.id))),
        backgroundColor: AppColors.red,
        icon: const Icon(Icons.sos, color: Colors.white),
        label: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      backgroundColor: AppColors.cardBg,
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        // Rider + package
        Container(
          padding: const EdgeInsets.all(16), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ride.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Package: $_pkgHours hr / $_pkgKm km', style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
            Text(widget.ride.pickupAddress, style: TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        // Destinations added by the rider (live)
        if (_stops.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.route, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Rider destinations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
              const SizedBox(height: 8),
              ..._stops.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      CircleAvatar(radius: 11, backgroundColor: AppColors.primary,
                          child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value['address']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                    ]),
                  )),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        // Live timer + km
        Row(children: [
          Expanded(child: _metric('Time used', _fmt(_elapsed), 'of $_pkgHours hr', overHr)),
          const SizedBox(width: 12),
          Expanded(child: _metric('Distance', '${_actualKm.toStringAsFixed(1)} km', 'of $_pkgKm km', overKm)),
        ]),
        if (overHr || overKm) Padding(padding: const EdgeInsets.only(top: 10), child: Container(
          padding: const EdgeInsets.all(10), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [Icon(Icons.warning_amber, color: AppColors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('Package limit exceeded — extra charges apply', style: TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)))]),
        )),
        const Spacer(),
        // Actions
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _toggleWait,
            icon: Icon(_waiting ? Icons.play_arrow : Icons.pause, color: AppColors.primary),
            label: Text(_waiting ? 'Resume' : 'Waiting', style: const TextStyle(color: AppColors.primary)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: const BorderSide(color: AppColors.primary)),
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            onPressed: _extend, icon: const Icon(Icons.add, color: AppColors.green),
            label: const Text('Extend', style: TextStyle(color: AppColors.green)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: const BorderSide(color: AppColors.green)),
          )),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52)),
          onPressed: _ending ? null : _end,
          child: Text(_ending ? 'Ending...' : '🏁 End Rental', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        )),
      ])),
    );
  }

  Widget _metric(String label, String value, String sub, bool over) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: over ? AppColors.orange : AppColors.divider, width: over ? 1.5 : 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: over ? AppColors.orange : AppColors.textDark)),
      Text(sub, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
    ]),
  );
}
