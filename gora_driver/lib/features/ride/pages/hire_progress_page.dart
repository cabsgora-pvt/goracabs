import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import 'invoice_page.dart';

// Live hire-a-driver screen: timer vs booked hours, extend, end with overtime bill.
class HireProgressPage extends StatefulWidget {
  static const route = '/hire-progress';
  final RideRequestModel ride;
  const HireProgressPage({super.key, required this.ride});
  @override
  State<HireProgressPage> createState() => _HireProgressPageState();
}

class _HireProgressPageState extends State<HireProgressPage> {
  Timer? _tick, _ping;
  Duration _elapsed = Duration.zero;
  DateTime _startedAt = DateTime.now();
  bool _ending = false;
  int _bookedHours = 0;

  @override
  void initState() {
    super.initState();
    _bookedHours = widget.ride.hireTotalHours;
    _start();
  }

  Future<void> _start() async {
    final res = await DriverApiService.hireAction(widget.ride.id, {'action': 'start'});
    if (res['hire']?['hireStartedAt'] != null) {
      _startedAt = DateTime.tryParse(res['hire']['hireStartedAt'].toString())?.toLocal() ?? DateTime.now();
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _elapsed = DateTime.now().difference(_startedAt)); });
    _ping = Timer.periodic(const Duration(seconds: 30), (_) => DriverApiService.hireAction(widget.ride.id, {'action': 'ping'}));
  }

  Future<void> _extend() async {
    final h = await showDialog<int>(context: context, builder: (_) => SimpleDialog(
      title: const Text('Extend hire by'),
      children: [1, 2, 4].map((x) => SimpleDialogOption(onPressed: () => Navigator.pop(context, x), child: Text('+$x hours'))).toList()));
    if (h == null) return;
    await DriverApiService.hireAction(widget.ride.id, {'action': 'extend', 'extraHours': h});
    if (mounted) setState(() => _bookedHours += h);
  }

  Future<void> _end() async {
    setState(() => _ending = true);
    final res = await DriverApiService.hireAction(widget.ride.id, {'action': 'end'});
    _tick?.cancel(); _ping?.cancel();
    if (!mounted) return;
    _showBill(res['hire'] as Map<String, dynamic>? ?? {});
  }

  void _showBill(Map<String, dynamic> h) {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true,
      builder: (_) => Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Hire Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _row('Booked', '${h['totalHours'] ?? 0} hr'),
          _row('Worked', '${(h['actualHours'] ?? 0).toStringAsFixed(1)} hr'),
          const Divider(),
          _row('Base', '₹${widget.ride.fare.replaceAll('₹ ', '')}'),
          if ((h['extraCharge'] ?? 0) > 0) _row('Overtime (${h['extraHours']}hr)', '₹${h['extraCharge']}', color: AppColors.orange),
          const Divider(),
          _row('Total', '₹${h['finalFare'] ?? 0}', bold: true),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done',
            onTap: () => Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: widget.ride))),
        ])));
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color))]));

  @override
  void dispose() { _tick?.cancel(); _ping?.cancel(); super.dispose(); }

  String _fmt(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final over = _elapsed.inMinutes / 60 > _bookedHours;
    return Scaffold(
      appBar: blueAppBar('Hire in Progress'),
      backgroundColor: AppColors.cardBg,
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Container(padding: const EdgeInsets.all(16), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ride.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Booked: $_bookedHours hr · ${widget.ride.transmission == 'automatic' ? 'Automatic' : 'Manual'}',
              style: const TextStyle(fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.w600)),
            Text(widget.ride.pickupAddress, style: TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(20), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: over ? AppColors.orange : AppColors.divider, width: over ? 1.5 : 1)),
          child: Column(children: [
            Text('Time worked', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
            const SizedBox(height: 6),
            Text(_fmt(_elapsed), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: over ? AppColors.orange : AppColors.textDark)),
            Text('of $_bookedHours hr booked', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
          ])),
        if (over) Padding(padding: const EdgeInsets.only(top: 10), child: Container(padding: const EdgeInsets.all(10), width: double.infinity,
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [Icon(Icons.warning_amber, color: AppColors.orange, size: 18), SizedBox(width: 8),
            Expanded(child: Text('Overtime — extra hours billed at per-hour rate', style: TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)))]))),
        const Spacer(),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _extend,
          icon: const Icon(Icons.add, color: AppColors.green), label: const Text('Extend Hours', style: TextStyle(color: AppColors.green)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: const BorderSide(color: AppColors.green)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52)),
          onPressed: _ending ? null : _end,
          child: Text(_ending ? 'Ending...' : '🏁 End Hire', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      ])),
    );
  }
}
