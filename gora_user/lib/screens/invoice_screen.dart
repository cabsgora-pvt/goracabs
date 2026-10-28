import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'home_screen.dart';

/// Invoice for one real ride.
///
/// [ride] is the summary map the ride-history screen already built from
/// GET /rides/user (keys: id, from, to, date, driver, vehicle, distance,
/// paymentMode, total, ...). The full record is then fetched from
/// GET /rides/:id (rider bearer token) for the fields the summary lacks —
/// rider name, completion time, waiting charge, final amounts. Until that
/// arrives, or if it fails, the summary is rendered on its own.
///
/// Display only: every amount here is read from the ride record; nothing is
/// recomputed or charged.
class InvoiceScreen extends StatefulWidget {
  final Map<String, dynamic> ride;

  const InvoiceScreen({super.key, required this.ride});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Map<String, dynamic>? _full;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = (widget.ride['id'] ?? '').toString();
    if (id.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await ApiService.getRide(id);
      if (!mounted) return;
      setState(() {
        if (res['error'] == null && res['_id'] != null) _full = res;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _s => widget.ride;
  Map<String, dynamic> get _f => _full ?? const {};

  int _n(dynamic v) => (v as num?)?.round() ?? 0;
  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  String _str(dynamic v) => (v ?? '').toString().trim();

  /// First non-empty value: full record first, then the history summary.
  String _pick(String fullKey, String summaryKey) {
    final a = _str(_f[fullKey]);
    return a.isNotEmpty ? a : _str(_s[summaryKey]);
  }

  num _num(String fullKey, String summaryKey) =>
      (_f[fullKey] as num?) ?? (_s[summaryKey] as num?) ?? 0;

  String get _service => _pick('service', 'service').isEmpty ? 'taxi' : _pick('service', 'service');

  String get _riderName {
    final r = _f['rider'];
    final fromRider = r is Map ? _str(r['name']) : '';
    return fromRider.isNotEmpty ? fromRider : _pick('riderName', 'riderName');
  }

  String get _driverName {
    final d = _f['driver'];
    final fromDriver = d is Map ? _str(d['name']) : '';
    if (fromDriver.isNotEmpty) return fromDriver;
    final s = _str(_s['driver']);
    return s == '—' ? '' : s;
  }

  String get _vehicleLine {
    final d = _f['driver'];
    final model = d is Map ? _str(d['vehicleModel']) : _str(_s['driverVehicleModel']);
    final number = d is Map ? _str(d['vehicleNumber']) : _str(_s['driverVehicleNumber']);
    return [model, number].where((x) => x.isNotEmpty).join(' • ');
  }

  String _fmt(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final hh = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}, '
        '${hh.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  /// Trip date: completion time when known, else booking time.
  String get _tripDate {
    final done = _fmt(_str(_f['completedAt']));
    if (done.isNotEmpty) return done;
    final created = _fmt(_str(_f['createdAt']));
    return created.isNotEmpty ? created : _str(_s['date']);
  }

  /// Distance actually covered where the service records it, else the route distance.
  double get _distanceKm {
    if (_service == 'rental' && _d(_f['actualKm'] ?? _s['actualKm']) > 0) return _d(_f['actualKm'] ?? _s['actualKm']);
    if (_service == 'delivery' && _d(_f['deliveryDistance']) > 0) return _d(_f['deliveryDistance']);
    if (_service == 'outstation' && _d(_f['actualDistance']) > 0) return _d(_f['actualDistance']);
    return _d(_num('distance', 'distance'));
  }

  // ── Amounts (read from the record, never recomputed into a charge) ──
  // Mirrors how /rides/:id/complete records totalFare: the service's final
  // amount (or the booked fare) + multi-stop waiting + tip.
  int get _billable {
    final svcFinal = _service == 'rental'
        ? _n(_f['finalFare'] ?? _s['finalFare'])
        : _service == 'hire_driver'
            ? _n(_f['hireFinalFare'])
            : _service == 'delivery'
                ? _n(_f['deliveryFinalFare'])
                : 0;
    return svcFinal > 0 ? svcFinal : _n(_num('fare', 'baseFare'));
  }

  int get _waiting => _n(_f['waitingChargeTotal']);
  int get _tip => _n(_num('tip', 'tip'));
  int get _tolls => _service == 'outstation' ? _n(_num('tollCharge', 'tollCharge')) : 0;

  int get _total {
    final recorded = _n(_num('totalFare', 'total'));
    final t = recorded > 0 ? recorded : _billable + _waiting + _tip;
    // Tolls are paid to the driver outside the fare — the trip detail screen
    // adds them to "Total Paid" the same way.
    return t + _tolls;
  }

  String get _rideId => _pick('_id', 'id');

  String get _serviceLabel {
    switch (_service) {
      case 'rental': return 'Rental';
      case 'outstation': return 'Outstation';
      case 'hire_driver': return 'Hire Driver';
      case 'delivery': return 'Parcel Delivery';
      default: return 'Ride';
    }
  }

  String get _vehicleType {
    final v = _pick('vehicleType', 'vehicle');
    return v.isNotEmpty ? v : (_service == 'hire_driver' ? 'Driver only' : '');
  }

  String get _paymentMode {
    final p = _pick('paymentMode', 'paymentMode');
    return p.isEmpty ? 'CASH' : p.toUpperCase();
  }

  String get _status => _str(_f['status']).isNotEmpty ? _str(_f['status']) : _str(_s['status']).toLowerCase();

  String _receiptText() {
    final lines = <String>[
      'Gora Cabs — $_serviceLabel invoice',
      if (_rideId.isNotEmpty) 'Ride ID: $_rideId',
      if (_tripDate.isNotEmpty) 'Date: $_tripDate',
      if (_riderName.isNotEmpty) 'Rider: $_riderName',
      '',
      'From: ${_pick('pickupAddress', 'from')}',
      if (_service != 'hire_driver' || _pick('dropAddress', 'to').isNotEmpty) 'To: ${_pick('dropAddress', 'to')}',
      if (_vehicleType.isNotEmpty) 'Vehicle: $_vehicleType${_vehicleLine.isNotEmpty ? ' ($_vehicleLine)' : ''}',
      if (_driverName.isNotEmpty) 'Driver: $_driverName',
      if (_distanceKm > 0) 'Distance: ${_distanceKm.toStringAsFixed(1)} km',
      '',
      'Total: ₹$_total',
      'Payment: $_paymentMode',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final drop = _pick('dropAddress', 'to');
    final small = RideUi.caption(context, size: 13);
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(
        children: [
          ServiceBackBar(
            trailing: IconButton(
              tooltip: 'Share invoice',
              onPressed: _loading ? null : () => Share.share(_receiptText(), subject: 'Your Gora Cabs invoice'),
              icon: Icon(Icons.share_outlined, color: RideUi.ink(context)),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                ServiceTitle(title: 'Invoice', subtitle: 'Gora-Cabs Invoice · $_serviceLabel'),

                // ── Trip summary card ──
                RideTile(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_riderName.isNotEmpty) ...[
                      Text(_riderName.toUpperCase(), style: RideUi.body(context, size: 15, weight: FontWeight.w800)),
                      const SizedBox(height: 10),
                    ],
                    TripRouteSummary(pickup: _pick('pickupAddress', 'from'), drop: drop.isEmpty ? null : drop, maxLines: 3, fontSize: 13.5),
                    const RideDivider(vertical: 12),
                    if (_rideId.isNotEmpty) Text('Ride ID: $_rideId', style: small),
                    if (_tripDate.isNotEmpty) Text('Date: $_tripDate', style: small),
                    Text('Payment: $_paymentMode', style: small),
                    if (_status.isNotEmpty && _status != 'completed')
                      Text('Status: ${_status[0].toUpperCase()}${_status.substring(1)}',
                          style: small.copyWith(color: const Color(0xFFB45309), fontWeight: FontWeight.w700)),
                    if (_driverName.isNotEmpty || _vehicleLine.isNotEmpty) ...[
                      const RideDivider(vertical: 12),
                      Row(children: [
                        Icon(Icons.person_outline, size: 20, color: RideUi.ink(context)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (_driverName.isNotEmpty)
                              Text('Driver: $_driverName', style: RideUi.body(context, size: 13.5, weight: FontWeight.w700)),
                            if (_vehicleLine.isNotEmpty) Text(_vehicleLine, style: small),
                          ]),
                        ),
                      ]),
                    ],
                  ]),
                ),

                // ── Fare ──
                const ServiceSection('Fare', top: 20),
                SummaryRow(
                    '$_serviceLabel${_vehicleType.isNotEmpty ? ' ($_vehicleType)' : ''}'
                    '${_distanceKm > 0 ? ' · ${_distanceKm.toStringAsFixed(1)} km' : ''}',
                    '₹$_billable'),
                ..._includedRows(),
                if (_waiting > 0) SummaryRow('Waiting charge', '₹$_waiting'),
                if (_tip > 0) SummaryRow('Tip', '₹$_tip'),
                if (_tolls > 0) SummaryRow('Tolls (paid to driver)', '₹$_tolls'),
                const RideDivider(vertical: 8),
                Row(children: [
                  Expanded(child: Text('Total Amount', style: RideUi.body(context, size: 17, weight: FontWeight.w800))),
                  Text('₹$_total', style: RideUi.body(context, size: 20, weight: FontWeight.w900)),
                ]),

                const SizedBox(height: 40),
                Text('Details of ECO under GST:', textAlign: TextAlign.center, style: RideUi.caption(context, size: 11)),
                const SizedBox(height: 4),
                Text(
                  'Gora cabs & travels Pvt Ltd 1st Floor, Nanak Bhavan , Tempo Stand , Airforce Area ,Jodhpur, Rajasthan 342011',
                  style: RideUi.caption(context, size: 10.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          PrimaryCtaBar(
            label: 'Go Home',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Components already contained in the main fare line (shown for
  /// transparency, not added again).
  List<Widget> _includedRows() {
    final rows = <Widget>[];
    void incl(String label, int amount) {
      if (amount > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SummaryRow('incl. $label', '₹$amount', valueColor: RideUi.muted(context)),
        ));
      }
    }
    if (_service == 'rental') {
      incl('extra hours', _n(_f['extraHoursCharge'] ?? _s['extraHoursCharge']));
      incl('extra km', _n(_f['extraKmCharge'] ?? _s['extraKmCharge']));
      incl('night charge', _n(_f['nightChargeRental'] ?? _s['nightChargeRental']));
    } else if (_service == 'outstation') {
      incl('night halt', _n(_f['nightHaltCharge'] ?? _s['nightHaltCharge']));
      incl('empty return', _n(_f['emptyReturnCharge'] ?? _s['emptyReturnCharge']));
    } else if (_service == 'hire_driver') {
      incl('extra hours', _n(_f['hireExtraCharge']));
    }
    return rows;
  }
}
