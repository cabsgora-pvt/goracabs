import 'package:flutter/material.dart';
import '../services/api_service.dart';

// Guard so we only show one "Pay Now" dialog per ride at a time.
final Set<String> _prompting = {};

// Online gating: the driver ended an online ride (awaitingPayment) — ask the
// rider to confirm, then complete the ride. The existing "ride completed" flow
// performs the actual charge, so there is NO double-charge here.
//
// [amount] is what the caller will actually charge. When omitted, the ride's
// own total is shown, as before. [title], [message] and [action] replace the
// wording where "pay ₹X" would be untrue — an outstation trip paid in full at
// booking, where the rider only confirms the trip has ended.
Future<void> promptOnlinePayment(
  BuildContext context,
  String? rideId,
  Map<String, dynamic> ride, {
  num? amount,
  String? title,
  String? message,
  String? action,
}) async {
  if (rideId == null || _prompting.contains(rideId)) return;
  _prompting.add(rideId);
  final shown = (amount ?? ((ride['totalFare'] ?? ride['fare'] ?? 0) as num)).toDouble();
  final pay = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(title ?? 'Pay to complete your ride'),
      content: Text(message ?? 'Please pay ₹${shown.toStringAsFixed(0)} to finish this ride.'),
      actions: [
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(action ?? 'Pay Now')),
      ],
    ),
  );
  if (pay == true) {
    try { await ApiService.completeRide(rideId); } catch (_) {}
  }
  _prompting.remove(rideId);
}
