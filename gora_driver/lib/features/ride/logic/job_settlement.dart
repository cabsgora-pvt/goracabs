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
//  * prepaid outstation whose prepayment did not cover the bill — /complete
//             answers prepaidShortfall + cashToCollect: the driver collects
//             that much (or the rider pays it online) — /collect-cash records it.
//
// The cash figure shown to the driver is ALWAYS the server's cashToCollect
// (fare + waiting + tip + extras − coupon − split shares already paid), read
// from /complete — or, for rental / hire, from their 'end' bill — never a sum
// the app works out. The app's own sum once disagreed with the settlement
// (no coupon, no split, no waiting), so the driver asked the rider for the
// wrong amount.
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

/// The server's cash-to-collect in a reply (/complete, rental / hire 'end'),
/// or null when the reply carries none.
num? serverCashToCollect(Map<String, dynamic> res) {
  final v = res['cashToCollect'];
  if (v is num) return v;
  return v == null ? null : num.tryParse('$v');
}

/// The cash for a rental's 'end' bill: the server's cashToCollect; from an
/// older server without it, the billed finalFare. Nothing for a non-cash ride.
num rentalCashToCollect(Map<String, dynamic> endReply, {required bool cash}) {
  if (!cash) return 0;
  final c = serverCashToCollect(endReply);
  if (c != null) return c;
  final bill = endReply['rental'];
  return bill is Map ? _n(bill['finalFare']) : 0;
}

/// The cash for a hire's 'end' bill: cashToCollect, else amountDue.
num hireCashToCollect(Map<String, dynamic> endReply, {required bool cash}) {
  if (!cash) return 0;
  return serverCashToCollect(endReply) ?? _n(endReply['amountDue']);
}

/// Collects [cashDue] (when there is any — a figure the SERVER priced: the
/// service's own pricing reply), settles the ride, and opens the invoice.
/// [cashInHand]: the caller already collected the cash itself. Returns false,
/// leaving the driver where they are, if collection was cancelled or
/// settlement failed — in which case they have been told why and can retry.
Future<bool> collectAndSettle(
  BuildContext context, {
  required RideRequestModel ride,
  required num cashDue,
  bool cashInHand = false,
  String? afterSettleNote,
}) async {
  if (cashDue > 0 && !cashInHand) {
    final collected = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: cashDue.toDouble())));
    if (collected != true || !context.mounted) return false;
  }
  final invoice = await settleForInvoice(context, ride, cashCollected: cashInHand || cashDue > 0);
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
///
/// [earningPending]: the rider has not paid yet (online, or a prepaid trip's
/// shortfall) — the earning is credited once they do, so it is shown as
/// "Pending", not as money in the wallet.
RideCompletionArgs invoiceFor(RideRequestModel ride, Map<String, dynamic> settled,
        {num tollCollected = 0, bool earningPending = false}) =>
    RideCompletionArgs(
      ride,
      driverEarning: _n(settled['driverEarning'] ?? settled['pendingDriverEarning']),
      adminProfit: _n(settled['adminProfit'] ?? settled['commissionAmount'] ?? settled['pendingCommission']),
      tollCollected: tollCollected,
      earningPending: earningPending,
    );

/// Calls /complete and reports a failure instead of swallowing it, then walks
/// the driver through what the answer says: the cash to collect (the server's
/// cashToCollect), an online payment to wait for, or a prepaid trip's
/// shortfall. A ride the server already settled counts as done.
/// [cashCollected]: the cash was already taken (from a rental / hire / parcel
/// bill) — not asked for again. [tollsInHand]: tolls collected together with
/// the fare (a cash trip). Returns the invoice, or null when settlement failed.
Future<RideCompletionArgs?> settleForInvoice(BuildContext context, RideRequestModel ride,
    {num tollCollected = 0, bool cashCollected = false, num tollsInHand = 0}) async {
  Map<String, dynamic> res;
  try {
    res = await DriverApiService.completeRide(ride.id);
  } catch (_) {
    res = const {'error': 'No connection'};
  }
  final error = res['error']?.toString();
  if (error == null) {
    if (!context.mounted) return null;
    return afterComplete(context, ride, res,
        tollCollected: tollCollected, cashCollected: cashCollected, tollsInHand: tollsInHand);
  }
  if (error == 'Already completed') {
    // Settled elsewhere (or an earlier reply was lost): the ride itself holds
    // what it billed — and whether the rider has paid yet.
    Map<String, dynamic> doc;
    try { doc = _rideOf(await DriverApiService.getRide(ride.id)); } catch (_) { doc = const {}; }
    if (!context.mounted) return null;
    var pending = false;
    if (doc['prepaidShortfall'] == true && doc['paymentStatus'] != 'paid') {
      pending = await waitForOnlinePayment(context, ride, amountDue: _n(doc['amountDue'] ?? res['amountDue']),
          shortfall: true) == OnlinePayment.later;
    } else if (_onlineUnpaid(doc, ride)) {
      pending = await waitForOnlinePayment(context, ride, amountDue: _n(doc['amountDue'] ?? res['amountDue'])) ==
          OnlinePayment.later;
    } else if ((doc['paymentMode'] ?? ride.paymentMode) == 'cash' && !cashCollected) {
      // The first reply never arrived, so the driver was never shown what to
      // take: the server's billed amount (amountDue), plus tolls.
      final cash = _n(doc['amountDue'] ?? res['amountDue']);
      if (cash + tollsInHand > 0 && context.mounted) {
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CollectFarePage(
          amount: (cash + tollsInHand).toDouble(), title: cashTitle(tollsInHand))));
      }
    }
    return invoiceFor(ride, doc, tollCollected: tollCollected, earningPending: pending);
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

/// What to do once /complete has answered [res]. The amount the driver is
/// asked to take is the server's cashToCollect, never a figure worked out here.
Future<RideCompletionArgs> afterComplete(BuildContext context, RideRequestModel ride, Map<String, dynamic> res,
    {num tollCollected = 0, bool cashCollected = false, num tollsInHand = 0}) async {
  final mode = (res['paymentMode'] ?? ride.paymentMode).toString();
  var pending = false;
  if (res['prepaidShortfall'] == true) {
    // A prepaid outstation trip whose prepayment did not cover the bill: the
    // rest is due now — in cash to the driver, or online by the rider.
    final due = _n(res['cashToCollect'] ?? res['amountDue']);
    if (due > 0) {
      pending = await waitForOnlinePayment(context, ride, amountDue: due, shortfall: true) == OnlinePayment.later;
    }
  } else if (res['paymentSwitchedToCash'] == true) {
    // The rider's wallet could not cover it: the ride is now a cash ride.
    final cash = _n(res['cashToCollect'] ?? res['amountDue']);
    if (cash > 0) {
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CollectFarePage(
        amount: cash.toDouble(),
        title: walletShortTitle(cash),
      )));
    }
  } else if (mode == 'cash' && !cashCollected) {
    // Settled as a cash ride: take exactly what the server billed.
    final cash = serverCashToCollect(res) ?? _n(res['amountDue']);
    if (cash + tollsInHand > 0) {
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CollectFarePage(
        amount: (cash + tollsInHand).toDouble(), title: cashTitle(tollsInHand))));
    }
  } else if (res['awaitingPayment'] == true && mode == 'online') {
    pending = await waitForOnlinePayment(context, ride, amountDue: _n(res['amountDue'])) == OnlinePayment.later;
  }
  return invoiceFor(ride, res, tollCollected: tollCollected, earningPending: pending);
}

/// "Rider's wallet was short — collect ₹X in cash".
String walletShortTitle(num cash) => "Rider's wallet was short — collect ₹${cash.round()} in cash";

/// The collect-cash heading: the fare alone, or the fare with the tolls.
String cashTitle(num tolls) => tolls > 0 ? 'Fare + tolls — collect from the rider' : 'Collect from the rider';

/// The end-trip swipe on a cash trip. No amount: the server's figure is shown
/// once the trip is ended.
const cashEndLabel = 'Swipe to end & collect cash';

/// "Collect ₹X" — what is left on a prepaid trip.
String shortfallText(num due) => 'Collect ₹${due.round()}';

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
/// instead, or move on (Later). [shortfall]: what a prepaid trip's prepayment
/// did not cover — shown as "Collect ₹X".
Future<OnlinePayment> waitForOnlinePayment(BuildContext context, RideRequestModel ride,
    {required num amountDue, bool shortfall = false}) async {
  final r = await showDialog<OnlinePayment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PaymentWaitDialog(rideId: ride.id, amountDue: amountDue, shortfall: shortfall),
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
  /// A prepaid trip's uncovered rest: "Collect ₹X" rather than "Waiting for
  /// online payment".
  final bool shortfall;
  const PaymentWaitDialog({super.key, required this.rideId, required this.amountDue, this.shortfall = false});
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
      if (widget.shortfall)
        const Icon(Icons.payments_outlined, color: AppColors.green, size: 36)
      else
        const CircularProgressIndicator(color: AppColors.primary),
      const SizedBox(height: 16),
      Text(widget.shortfall ? shortfallText(widget.amountDue) : onlineWaitText(widget.amountDue),
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: widget.shortfall ? 22 : 14)),
      const SizedBox(height: 6),
      Text(
          widget.shortfall
              ? "The prepayment didn't cover the whole bill. Take this in cash, or the rider can pay it in the app."
              : 'Your earning is added once the rider pays.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12)),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
      ],
    ]),
    actions: [
      TextButton(onPressed: _busy ? null : () => _done(OnlinePayment.later), child: const Text('Later')),
      ElevatedButton(onPressed: _busy ? null : _paidCash,
          child: Text(widget.shortfall ? 'Cash collected' : 'Rider paid cash')),
    ],
  );
}

/// "Waiting for online payment ₹X".
String onlineWaitText(num amountDue) => 'Waiting for online payment ₹${amountDue.round()}';

/// Rental / hire: asks the server for the bill again — a repeated 'end'
/// answers {alreadyEnded: true, …bill, cashToCollect} — so a reopened job
/// collects the server's figure. Null when it could not be read.
Future<Map<String, dynamic>?> reEndBill(RideRequestModel ride) async {
  Map<String, dynamic> res;
  try {
    res = ride.service == 'rental'
        ? await DriverApiService.rentalAction(ride.id, {'action': 'end'})
        : await DriverApiService.hireAction(ride.id, {'action': 'end'});
  } catch (_) {
    return null;
  }
  return res['error'] == null ? res : null;
}

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
  // ends every job now, an online one included. Rental and hire take the
  // amount from the server's repeated 'end' (cashToCollect); a parcel's comes
  // from its saved fare + the COD it handed over.
  if (ride.service == 'rental' || ride.service == 'hire_driver') {
    final bill = await reEndBill(ride);
    if (!context.mounted) return;
    final cash = bill == null ? null : serverCashToCollect(bill);
    if (cash == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load the bill — check your connection and try again.'), backgroundColor: AppColors.red));
      return;
    }
    await collectAndSettle(context, ride: ride, cashDue: cash);
    return;
  }
  await collectAndSettle(context, ride: ride, cashDue: cashDueFor(r));
}

/// Whether the DRIVER ends (settles) this service. Always, now: the server
/// completes an online job with its payment pending and credits the earning
/// once the rider pays, so no service waits on the rider's app to end.
bool driverSettles(String service) => true;
