import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../pages/collect_fare_page.dart';
import '../pages/invoice_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Finishing a job the server has already priced.
//
// Rental, hire and parcel all end the same way — the server prices the job,
// the driver collects any cash, then /complete settles it — and each screen
// wrote that out separately. Two gaps were common to all three:
//
//  * /complete's answer was ignored. If it failed, the driver was sent to the
//    invoice as if paid, while the ride sat unsettled: no earning, no
//    commission, and the ride still "active" in their home screen.
//  * A job priced but not yet settled could not be reopened. The screen started
//    over, pressed End again, and the server (rightly) refused to re-price it —
//    leaving the driver with no way to finish.
//
// Settlement (server, /complete): the DRIVER ends every job, whatever the
// payment mode.
//  * cash   — the driver has the money; commission comes off their wallet.
//  * wallet — the server debits the rider's wallet. If it is short the ride
//             switches to cash (paymentSwitchedToCash) and the driver collects
//             cashToCollect in hand.
//  * online — the ride is completed with paymentStatus 'pending'; the driver's
//             earning is credited only once the rider pays. The driver waits,
//             or records that the rider paid cash instead (/collect-cash).
// ─────────────────────────────────────────────────────────────────────────────

num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// What the driver must still take in hand for a priced ride, read from the
/// ride as the server holds it. Mirrors what each service's own pricing call
/// returns as the amount due, so a reopened job asks for the same figure the
/// screen would have asked for straight after pricing.
num cashDueFor(Map<String, dynamic> ride) {
  final cash = ride['paymentMode'] == 'cash';
  switch ('${ride['service'] ?? ''}') {
    case 'rental':
      // RentalProgressPage collects finalFare.
      return cash ? _n(ride['finalFare']) : 0;
    case 'hire_driver':
      // /hire 'end' → amountDue = totalFare for cash.
      return cash ? _n(ride['totalFare']) : 0;
    case 'delivery':
      // /delivery → fareDue (cash only) + codDue (a real handover only).
      final fare = cash ? _n(ride['totalFare']) : 0;
      final cod = ride['deliveryPhase'] == 'delivered' ? _n(ride['codCollected']) : 0;
      return fare + cod;
    default:
      return cash ? _n(ride['totalFare']) : 0;
  }
}

/// Collects [cashDue] (when there is any), settles the ride, and opens the
/// invoice. Returns false, leaving the driver where they are, if collection was
/// cancelled or settlement failed — in which case they have been told why and
/// can try again.
Future<bool> collectAndSettle(
  BuildContext context, {
  required RideRequestModel ride,
  required num cashDue,
  String? afterSettleNote,
}) async {
  if (cashDue > 0) {
    final collected = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: cashDue.toDouble())));
    if (collected != true || !context.mounted) return false;
  }
  final invoice = await settleForInvoice(context, ride);
  if (invoice == null || !context.mounted) return false;
  if (afterSettleNote != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(afterSettleNote), backgroundColor: AppColors.primary));
  }
  Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoice);
  return true;
}

/// What the invoice shows for [ride], read from /complete's answer or from the
/// settled ride: the driver's earning after commission, as the server worked it
/// out. Rental, hire and parcel invoices were handed the bare ride and fell back
/// to showing the whole fare as the earning.
RideCompletionArgs invoiceFor(RideRequestModel ride, Map<String, dynamic> settled, {num tollCollected = 0}) =>
    RideCompletionArgs(
      ride,
      driverEarning: _n(settled['driverEarning'] ?? settled['pendingDriverEarning']),
      adminProfit: _n(settled['adminProfit'] ?? settled['commissionAmount'] ?? settled['pendingCommission']),
      tollCollected: tollCollected,
    );

/// Calls /complete and reports a failure instead of swallowing it, then walks
/// the driver through what the answer says: cash to collect from a short
/// wallet, or an online payment to wait for. A ride the server already settled
/// counts as done. Returns the invoice to show, or null when settlement failed.
Future<RideCompletionArgs?> settleForInvoice(BuildContext context, RideRequestModel ride, {num tollCollected = 0}) async {
  Map<String, dynamic> res;
  try {
    res = await DriverApiService.completeRide(ride.id);
  } catch (_) {
    res = const {'error': 'No connection'};
  }
  final error = res['error']?.toString();
  if (error == null) {
    if (!context.mounted) return null;
    return afterComplete(context, ride, res, tollCollected: tollCollected);
  }
  if (error == 'Already completed') {
    // Settled elsewhere (or an earlier reply was lost): the ride itself holds
    // what it paid — and whether the rider has paid yet.
    Map<String, dynamic> doc;
    try { doc = _rideOf(await DriverApiService.getRide(ride.id)); } catch (_) { doc = const {}; }
    if (!context.mounted) return null;
    if (_onlineUnpaid(doc, ride)) {
      await waitForOnlinePayment(context, ride, amountDue: _n(doc['amountDue'] ?? res['amountDue']));
    }
    return invoiceFor(ride, doc, tollCollected: tollCollected);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Could not finish the ride: $error. Swipe again to retry.'),
      backgroundColor: AppColors.red,
      duration: const Duration(seconds: 6),
    ));
  }
  return null;
}

Map<String, dynamic> _rideOf(Map<String, dynamic> r) =>
    r['ride'] is Map ? Map<String, dynamic>.from(r['ride'] as Map) : r;

bool _onlineUnpaid(Map<String, dynamic> doc, RideRequestModel ride) =>
    (doc['paymentMode'] ?? ride.paymentMode) == 'online' &&
    doc['paymentStatus'] != null && doc['paymentStatus'] != 'paid';

/// What to do once /complete has answered [res].
Future<RideCompletionArgs> afterComplete(BuildContext context, RideRequestModel ride, Map<String, dynamic> res,
    {num tollCollected = 0}) async {
  if (res['paymentSwitchedToCash'] == true) {
    // The rider's wallet could not cover it: the ride is now a cash ride.
    final cash = _n(res['cashToCollect'] ?? res['amountDue']);
    if (cash > 0) {
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CollectFarePage(
        amount: cash.toDouble(),
        title: walletShortTitle(cash),
      )));
    }
  } else if (res['awaitingPayment'] == true && (res['paymentMode'] ?? ride.paymentMode) == 'online') {
    await waitForOnlinePayment(context, ride, amountDue: _n(res['amountDue']));
  }
  return invoiceFor(ride, res, tollCollected: tollCollected);
}

/// "Rider's wallet was short — collect ₹X in cash".
String walletShortTitle(num cash) => "Rider's wallet was short — collect ₹${cash.round()} in cash";

/// [settleForInvoice], for a caller that only needs to know it worked.
Future<bool> settleRide(BuildContext context, RideRequestModel ride) async =>
    await settleForInvoice(context, ride) != null;

/// How waiting for the rider's online payment ended.
enum OnlinePayment {
  /// The rider paid in the app.
  paidOnline,
  /// The rider paid the driver in cash; recorded with /collect-cash.
  paidCash,
  /// The driver moved on; the earning is credited once the rider pays.
  later,
}

/// Waits, with the driver, for the rider to pay [amountDue] online on a ride
/// that is already ended. The driver can record that the rider paid cash
/// instead, or move on (Later).
Future<OnlinePayment> waitForOnlinePayment(BuildContext context, RideRequestModel ride, {required num amountDue}) async {
  final r = await showDialog<OnlinePayment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PaymentWaitDialog(rideId: ride.id, amountDue: amountDue),
  );
  final out = r ?? OnlinePayment.later;
  if (out == OnlinePayment.later && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Payment pending — your earning is added once the rider pays.'),
      duration: Duration(seconds: 6),
    ));
  }
  return out;
}

/// Ends an online ride: prompts the rider to pay, ends the trip (/complete),
/// waits for the payment, then opens the invoice.
Future<void> waitForRiderPayment(
  BuildContext context,
  RideRequestModel ride, {
  bool request = true,
  /// What the invoice shows once paid; the bare ride when null.
  Object? invoiceArgs,
}) async {
  if (request) {
    try { await DriverApiService.requestPayment(ride.id); } catch (_) {}
  }
  if (!context.mounted) return;
  final toll = invoiceArgs is RideCompletionArgs ? invoiceArgs.tollCollected : 0;
  final invoice = await settleForInvoice(context, ride, tollCollected: toll);
  if (invoice != null && context.mounted) {
    Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoice);
  }
}

/// "Waiting for online payment ₹X", with "Rider paid cash" and "Later".
/// Polls the ride until it is paid. Owns its timer, so the polling stops with
/// the dialog — including when the screen beneath it is closed.
class PaymentWaitDialog extends StatefulWidget {
  final String rideId;
  final num amountDue;
  const PaymentWaitDialog({super.key, required this.rideId, required this.amountDue});
  @override
  State<PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<PaymentWaitDialog> {
  Timer? _poll;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final r = _rideOf(await DriverApiService.getRide(widget.rideId));
        if (r['paymentStatus'] == 'paid' && mounted) _done(OnlinePayment.paidOnline);
      } catch (_) {}
    });
  }

  void _done(OnlinePayment p) {
    _poll?.cancel();
    if (mounted) Navigator.pop(context, p);
  }

  Future<void> _paidCash() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Rider paid cash?'),
      content: Text('Confirm you have collected ₹${widget.amountDue.round()} in cash. '
          'The commission is taken from your wallet, as for a cash ride.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cash collected')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    Map<String, dynamic> r;
    try {
      r = await DriverApiService.collectCash(widget.rideId);
    } catch (_) {
      r = const {'error': 'No connection — try again'};
    }
    if (!mounted) return;
    if (r['success'] == true) return _done(OnlinePayment.paidCash);
    // The rider's online payment got there first: nothing to record.
    if (r['code'] == 'paidOnline' || r['code'] == 'alreadyPaid') return _done(OnlinePayment.paidOnline);
    setState(() { _busy = false; _error = (r['error'] ?? 'Could not record the cash').toString(); });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: AppColors.primary),
      const SizedBox(height: 16),
      Text(onlineWaitText(widget.amountDue), textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Your earning is added once the rider pays.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12)),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
      ],
    ]),
    actions: [
      TextButton(onPressed: _busy ? null : () => _done(OnlinePayment.later), child: const Text('Later')),
      ElevatedButton(onPressed: _busy ? null : _paidCash, child: const Text('Rider paid cash')),
    ],
  );
}

/// "Waiting for online payment ₹X".
String onlineWaitText(num amountDue) => 'Waiting for online payment ₹${amountDue.round()}';

/// Finishes a job that was priced before this screen opened.
///
/// Reads the ride from the server rather than trusting the resumed model, so
/// the amount is the one the server billed.
Future<void> finishPricedJob(BuildContext context, RideRequestModel ride) async {
  Map<String, dynamic> r;
  try {
    r = _rideOf(await DriverApiService.getRide(ride.id));
  } catch (_) {
    r = const {'error': 'No connection'};
  }
  if (!context.mounted) return;
  if (r['error'] != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Could not load the bill: ${r['error']}'), backgroundColor: AppColors.red));
    return;
  }
  if ((r['status'] ?? '').toString() == 'completed') {
    // Ended already; an online ride may still be waiting for the rider.
    if (_onlineUnpaid(r, ride)) await waitForOnlinePayment(context, ride, amountDue: _n(r['amountDue']));
    if (context.mounted) Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoiceFor(ride, r));
    return;
  }
  // Priced, not yet ended: collect any cash, then end it here — the driver
  // ends every job now, an online one included.
  await collectAndSettle(context, ride: ride, cashDue: cashDueFor(r));
}

/// Whether the DRIVER ends (settles) this service. Always, now: the server
/// completes an online job with its payment pending and credits the earning
/// once the rider pays, so no service waits on the rider's app to end.
bool driverSettles(String service) => true;
