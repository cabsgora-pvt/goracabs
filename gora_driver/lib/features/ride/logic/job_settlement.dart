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
RideCompletionArgs invoiceFor(RideRequestModel ride, Map<String, dynamic> settled) => RideCompletionArgs(
  ride,
  driverEarning: _n(settled['driverEarning']),
  adminProfit: _n(settled['adminProfit'] ?? settled['commissionAmount']),
);

/// Calls /complete and reports a failure instead of swallowing it. A ride the
/// server already settled (the rider's payment got there first) counts as done.
/// Returns the invoice to show, or null when settlement failed.
Future<RideCompletionArgs?> settleForInvoice(BuildContext context, RideRequestModel ride) async {
  Map<String, dynamic> res;
  try {
    res = await DriverApiService.completeRide(ride.id);
  } catch (_) {
    res = const {'error': 'No connection'};
  }
  final error = res['error']?.toString();
  if (error == null) return invoiceFor(ride, res);
  if (error == 'Already completed') {
    // Settled elsewhere: the ride itself holds what it paid.
    Map<String, dynamic> doc;
    try { doc = await DriverApiService.getRide(ride.id); } catch (_) { doc = const {}; }
    return invoiceFor(ride, doc);
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

/// [settleForInvoice], for a caller that only needs to know it worked.
Future<bool> settleRide(BuildContext context, RideRequestModel ride) async =>
    await settleForInvoice(context, ride) != null;

/// Waits, with the driver, for the rider to pay online, then opens the invoice.
///
/// [request] asks the server to prompt the rider first (a trip ending now); a
/// reopened job whose payment is already requested passes false. The driver can
/// step away with Cancel — the ride stays open and can be reopened later.
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
  // True when the rider paid; null when the driver stepped away with Cancel.
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PaymentWaitDialog(rideId: ride.id),
  );
  if (paid == true && context.mounted) {
    Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoiceArgs ?? ride);
  }
}

/// Polls until the rider has paid. Owns its timer, so the polling stops with the
/// dialog — including when the screen beneath it is closed. A timer created in a
/// dialog builder kept asking the server every 3s for as long as the app ran.
class _PaymentWaitDialog extends StatefulWidget {
  final String rideId;
  const _PaymentWaitDialog({required this.rideId});
  @override
  State<_PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<_PaymentWaitDialog> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final r = await DriverApiService.getRide(widget.rideId);
        if ((r['status'] ?? '').toString() == 'completed' && mounted) {
          _poll?.cancel();
          Navigator.pop(context, true);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(mainAxisSize: MainAxisSize.min, children: const [
      CircularProgressIndicator(color: AppColors.primary),
      SizedBox(height: 16),
      Text('Waiting for the rider to pay online…', textAlign: TextAlign.center),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
    ],
  );
}

/// Finishes a job that was priced before this screen opened.
///
/// Reads the ride from the server rather than trusting the resumed model, so
/// the amount is the one the server billed.
Future<void> finishPricedJob(BuildContext context, RideRequestModel ride) async {
  Map<String, dynamic> r;
  try {
    r = await DriverApiService.getRide(ride.id);
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
    Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoiceFor(ride, r));
    return;
  }
  final due = cashDueFor(r);
  if (due > 0 || driverSettles(ride.service)) {
    await collectAndSettle(context, ride: ride, cashDue: due);
  } else if (r['awaitingPayment'] == true) {
    await waitForRiderPayment(context, ride, request: false);
  } else {
    final invoice = await settleForInvoice(context, ride);
    if (invoice != null && context.mounted) {
      Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: invoice);
    }
  }
}

/// Whether the DRIVER settles this service once any cash is in hand, rather
/// than waiting for the rider's online payment to settle it.
///
/// This mirrors the flows exactly as they already were, so a reopened job
/// finishes the same way an uninterrupted one does: hire and parcel settle from
/// the driver's side whatever the payment mode; rental and rides wait for the
/// rider's app. That difference is part of the known payment-flow gap (an
/// online fare can be settled before the rider has paid) and is deliberately
/// not changed here.
bool driverSettles(String service) => service == 'hire_driver' || service == 'delivery';
