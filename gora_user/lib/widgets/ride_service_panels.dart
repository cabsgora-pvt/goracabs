import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/place_names.dart';
import '../utils/ride_payable.dart';
import 'ride_ui/ride_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Service-specific content for the live ride screen.
//
// Rental, hire, parcel and outstation used to be tracked inside bottom sheets on
// their own booking screens, and each sheet showed things the generic ride
// screen did not: package usage, overtime, trip details, a final bill. Moving
// them onto the shared ride screen must not lose any of that, so it lives here.
//
// Every figure comes from the server. The running extras use the same shared
// formula the bill is computed with (lib/ride-extras.ts), so what a rider watches
// accrue is exactly what they are charged.
// ─────────────────────────────────────────────────────────────────────────────

num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _money(num v) => '₹${v.round()}';

/// A label/value row that ellipsises instead of overflowing.
Widget _billRow(String label, String value, {bool bold = false, Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(children: [
    Expanded(
      child: Text(label,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
    ),
    const SizedBox(width: 12),
    Text(value,
      style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
  ]),
);

/// Used / included, as a bar that turns orange once the package is exceeded.
class _UsageBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final num used;
  final num included;
  final String unit;
  const _UsageBar({required this.icon, required this.label, required this.used,
      required this.included, required this.unit});

  @override
  Widget build(BuildContext context) {
    final over = included > 0 && used > included;
    final frac = included > 0 ? (used / included).clamp(0.0, 1.0).toDouble() : 0.0;
    final color = over ? Colors.orange[800]! : AppTheme.primaryBlue;
    String fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(label,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: Colors.grey[700], fontWeight: FontWeight.w600))),
        Text('${fmt(used)} / ${fmt(included)} $unit',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: frac, minHeight: 6,
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

Widget _accruing(num amount, String label) => amount <= 0
    ? const SizedBox.shrink()
    : Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.35)),
        ),
        child: Row(children: [
          Icon(Icons.trending_up_rounded, size: 18, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(child: Text(label,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: Colors.orange[900], fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Text('+${_money(amount)}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.orange[900])),
        ]),
      );

/// Rental in progress: package hours and km used, and extras accruing.
///
/// A rider previously could not see extras building up at all — the running
/// total was only computed on the driver's side, so the first they learned of
/// extra hours was the final bill.
class RentalUsagePanel extends StatelessWidget {
  final Map<String, dynamic> ride;
  const RentalUsagePanel({super.key, required this.ride});

  @override
  Widget build(BuildContext context) => Column(children: [
    _UsageBar(icon: Icons.timer_outlined, label: 'Time used',
      used: _n(ride['actualHours']), included: _n(ride['packageHours']), unit: 'hr'),
    const SizedBox(height: 12),
    _UsageBar(icon: Icons.route, label: 'Distance used',
      used: _n(ride['actualKm']), included: _n(ride['packageKm']), unit: 'km'),
    _accruing(_n(ride['liveExtraCharge']), 'Extra charges so far — beyond your package'),
  ]);
}

/// Driver hire in progress: hours on duty against the booking, and overtime.
class HireUsagePanel extends StatelessWidget {
  final Map<String, dynamic> ride;
  const HireUsagePanel({super.key, required this.ride});

  @override
  Widget build(BuildContext context) => Column(children: [
    _UsageBar(icon: Icons.timer_outlined, label: 'Hours on duty',
      used: _n(ride['hireActualHours']), included: _n(ride['hireTotalHours']), unit: 'hr'),
    _accruing(_n(ride['liveExtraCharge']), 'Overtime so far — beyond your booked hours'),
  ]);
}

/// Outstation: which cities, whether a return leg is booked, and — on a round
/// trip — which leg the trip is on.
class OutstationTripPanel extends StatelessWidget {
  final Map<String, dynamic> ride;
  const OutstationTripPanel({super.key, required this.ride});

  /// The driver app reports these on a round trip. Null while the leg says
  /// nothing the rider does not already see from the phase.
  static (IconData, String)? legStatus(Map<String, dynamic> ride) {
    if (ride['tripType'] != 'round_trip' || ride['status'] != 'ongoing') return null;
    return switch ('${ride['outstationPhase'] ?? ''}') {
      'at_destination' => (Icons.flag_outlined, 'At destination — your driver is waiting'),
      'returning' => (Icons.replay, 'Return journey in progress'),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Trips booked before the towns were sent carry whole addresses here.
    final from = cityOf('${ride['cityFrom'] ?? ''}');
    final to = cityOf('${ride['cityTo'] ?? ''}');
    final roundTrip = ride['tripType'] == 'round_trip';
    if (from.isEmpty && to.isEmpty) return const SizedBox.shrink();
    final leg = legStatus(ride);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.map_outlined, color: AppTheme.primaryBlue, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(
          '${from.isEmpty ? 'Pickup' : from}  ${roundTrip ? '⇄' : '→'}  ${to.isEmpty ? 'Drop' : to}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: RideUi.ink(context)),
        )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue, borderRadius: BorderRadius.circular(6)),
          child: Text(roundTrip ? 'ROUND TRIP' : 'ONE WAY',
            style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ]),
      if (leg != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(leg.$1, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(leg.$2,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))),
        ]),
      ],
      ]),
    );
  }
}

/// One toll on an outstation trip, as the server holds it.
typedef Toll = ({String id, num amount, DateTime? at, String place, bool reported});

/// Tolls the driver entered on an outstation trip, oldest first.
List<Toll> tollsOf(Map<String, dynamic> ride) => [
  for (final t in (ride['tolls'] as List?) ?? const [])
    if (t is Map && _n(t['amount']) > 0)
      (
        id: '${t['id'] ?? t['_id'] ?? ''}',
        amount: _n(t['amount']),
        at: DateTime.tryParse('${t['at'] ?? ''}')?.toLocal(),
        place: '${t['place'] ?? ''}',
        // The rider's app sees the stored record (reportedAt); the toll API
        // answers with the flag.
        reported: t['reported'] == true || t['reportedAt'] != null,
      ),
];

/// Their total, as the server keeps it.
num tollTotalOf(Map<String, dynamic> ride) => _n(ride['tollCharge']);

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String tollSummary(Toll t) =>
    '${_money(t.amount)}${t.place.isNotEmpty ? ' · ${t.place}' : ''}${t.at != null ? ' · ${_clock(t.at!)}' : ''}';

const _reportReasons = <(String, String)>[
  ('no_toll', 'No toll was paid here'),
  ('wrong_amount', 'The amount is wrong'),
  ('other', 'Something else'),
];

/// Asks the rider why, then reports [toll] to support. True once sent.
///
/// A report does not change the bill: the support team reviews it with the
/// driver's entry, where it was made, and the rider's reason.
Future<bool> reportToll(BuildContext context, String rideId, Toll toll) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReportTollSheet(toll: toll),
  );
  if (choice == null) return false;
  Map<String, dynamic> res;
  try {
    res = await ApiService.reportToll(rideId, toll.id, choice.$1, choice.$2);
  } catch (_) {
    res = const {'error': 'No connection'};
  }
  final ok = res['error'] == null;
  messenger.showSnackBar(SnackBar(
    content: Text(ok
        ? 'Report sent. Our support team will look into this toll.'
        : 'Could not send the report: ${res['error']}'),
    backgroundColor: ok ? Colors.green[700] : Colors.red,
  ));
  return ok;
}

class _ReportTollSheet extends StatefulWidget {
  final Toll toll;
  const _ReportTollSheet({required this.toll});
  @override
  State<_ReportTollSheet> createState() => _ReportTollSheetState();
}

class _ReportTollSheetState extends State<_ReportTollSheet> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Report this toll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: RideUi.ink(context))),
      const SizedBox(height: 4),
      Text(tollSummary(widget.toll), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      const SizedBox(height: 12),
      for (final (code, label) in _reportReasons)
        RadioListTile<String>(
          value: code,
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v),
          title: Text(label),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      TextField(
        controller: _note,
        maxLength: 300,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(
          onPressed: _reason == null ? null : () => Navigator.pop(context, (_reason!, _note.text.trim())),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
          child: const Text('Send report'),
        )),
      ]),
    ])),
  );
}

/// Each toll with its amount, where and when it was paid, and — when [rideId]
/// is given — a way to report it. Shown on the live ride, the bill and the
/// trip record, so a toll reads the same everywhere.
class TollList extends StatefulWidget {
  final Map<String, dynamic> ride;
  /// Null hides the Report action.
  final String? rideId;
  /// Called after a report is sent, so the host can refresh from the server.
  final VoidCallback? onReported;
  const TollList({super.key, required this.ride, this.rideId, this.onReported});
  @override
  State<TollList> createState() => _TollListState();
}

class _TollListState extends State<TollList> {
  // Reported here and not yet reflected by the server's copy of the ride.
  final Set<String> _justReported = {};
  String? _sending;

  @override
  Widget build(BuildContext context) {
    final tolls = tollsOf(widget.ride);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, t) in tolls.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Toll ${i + 1}${t.at != null ? ' · ${_clock(t.at!)}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
              if (t.place.isNotEmpty)
                Text(t.place, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              if (t.reported || _justReported.contains(t.id))
                Text('Reported — our team will review it',
                  style: TextStyle(fontSize: 11.5, color: Colors.red[700], fontWeight: FontWeight.w700)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money(t.amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RideUi.ink(context))),
              if (widget.rideId != null && t.id.isNotEmpty && !t.reported && !_justReported.contains(t.id))
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.red[700],
                  ),
                  onPressed: _sending != null ? null : () async {
                    setState(() => _sending = t.id);
                    final ok = await reportToll(context, widget.rideId!, t);
                    if (!mounted) return;
                    setState(() { _sending = null; if (ok) _justReported.add(t.id); });
                    if (ok) widget.onReported?.call();
                  },
                  child: Text('Report', semanticsLabel: 'Report toll ${i + 1}'),
                ),
            ]),
          ]),
        ),
    ]);
  }
}

/// Tolls on an outstation trip, live, as the driver enters them.
///
/// Tolls are paid to the driver in hand at the end of the trip, whatever the
/// fare was paid with — they are never charged in the app. Showing each one as
/// it is added, with where it was paid, means the amount the driver asks for is
/// never a surprise — and one that looks wrong can be reported there and then.
class OutstationTollPanel extends StatelessWidget {
  final Map<String, dynamic> ride;
  final String? rideId;
  final VoidCallback? onReported;
  const OutstationTollPanel({super.key, required this.ride, this.rideId, this.onReported});

  @override
  Widget build(BuildContext context) {
    final tolls = tollsOf(ride);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.toll, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Expanded(child: Text('Tolls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: RideUi.ink(context)))),
          Text(_money(tollTotalOf(ride)), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: RideUi.ink(context))),
        ]),
        const SizedBox(height: 6),
        if (tolls.isEmpty)
          Text('No tolls added yet. Your driver adds each toll they pay.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700]))
        else
          TollList(ride: ride, rideId: rideId, onReported: onReported),
        const SizedBox(height: 6),
        Text('You pay tolls to your driver at the end of the trip.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
      ]),
    );
  }
}

/// True when this service shows an itemised bill before rating. Outstation
/// always does: its bill always carries a toll line, even at ₹0.
bool hasItemisedBill(String service) =>
    service == 'rental' || service == 'hire_driver' || service == 'outstation';

/// The final bill for a rental or driver hire, shown before rating.
///
/// Reproduces what the rental and hire booking screens showed, from the
/// server's settled figures. The total is [riderPayable] — the exact amount the
/// ride screen charges — so the bill can never show one figure and charge
/// another. Resolves when the rider continues.
Future<void> showRideBill(BuildContext context, Map<String, dynamic> ride, {num couponDiscount = 0}) {
  final isRental = ride['service'] == 'rental';
  final isOutstation = ride['service'] == 'outstation';
  final base = _n(ride['fare']);
  final List<Widget> rows;
  // Outstation tolls: after the fare and any coupon, before the total. Paid to
  // the driver in hand, so they are listed for the record, not charged here.
  final tollRows = <Widget>[];
  num tolls = 0;

  if (isOutstation) {
    final mode = '${ride['paymentMode'] ?? 'cash'}';
    final prepaid = mode != 'cash' && mode != 'cod';
    rows = [
      _billRow(prepaid ? 'Fare (paid at booking)' : 'Fare', _money(base)),
    ];
    final list = tollsOf(ride);
    final rideId = '${ride['_id'] ?? ride['id'] ?? ''}';
    tolls = tollTotalOf(ride);
    tollRows.addAll([
      _billRow('Tolls (${list.length}) · paid to driver', _money(tolls)),
      // Each toll with where it was paid; one that looks wrong can be
      // reported from the bill.
      if (list.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: TollList(ride: ride, rideId: rideId.isEmpty ? null : rideId),
        ),
    ]);
  } else if (isRental) {
    final exHr = _n(ride['extraHoursCharge']);
    final exKm = _n(ride['extraKmCharge']);
    final night = _n(ride['nightChargeRental']);
    rows = [
      _billRow('Used', '${_n(ride['actualHours']).toStringAsFixed(1)} hr / ${_n(ride['actualKm']).toStringAsFixed(1)} km'),
      _billRow('Package', '${_n(ride['packageHours'])} hr / ${_n(ride['packageKm'])} km'),
      const Divider(),
      _billRow('Base fare', _money(base)),
      if (exHr > 0) _billRow('Extra hours', _money(exHr), color: Colors.orange[800]),
      if (exKm > 0) _billRow('Extra km', _money(exKm), color: Colors.orange[800]),
      if (night > 0) _billRow('Night charge', _money(night)),
    ];
  } else {
    final exCharge = _n(ride['hireExtraCharge']);
    rows = [
      _billRow('On duty', '${_n(ride['hireActualHours']).toStringAsFixed(1)} hr'),
      _billRow('Booked', '${_n(ride['hireTotalHours'])} hr'),
      const Divider(),
      _billRow('Base fare', _money(base)),
      if (exCharge > 0)
        _billRow('Overtime (${_n(ride['hireExtraHours'])} hr)', _money(exCharge), color: Colors.orange[800]),
    ];
  }
  // A rental's coupon is already inside its server fare (riderPayable ignores the
  // discount for rentals), so a coupon line only appears where one was applied
  // on top of the bill.
  final total = riderPayable(ride, couponDiscount: couponDiscount) + tolls;
  final showCoupon = !isRental && couponDiscount > 0;

  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    // Display only — nothing is started from this builder, so a rebuild (a
    // rotation, the keyboard) can re-run it safely.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
      // The theme's body text is grey, which made the bill read as disabled.
      child: DefaultTextStyle.merge(style: TextStyle(color: RideUi.ink(ctx)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isRental ? 'Rental Bill' : isOutstation ? 'Trip Bill' : 'Hire Bill',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        ...rows,
        if (showCoupon) _billRow('Coupon', '−${_money(couponDiscount)}', color: Colors.green[700]),
        ...tollRows,
        const Divider(),
        _billRow('Total', _money(total), bold: true, color: AppTheme.primaryBlue),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Rate your trip',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        )),
      ])),
    ),
  );
}
