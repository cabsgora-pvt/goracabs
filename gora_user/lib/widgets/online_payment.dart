import 'package:flutter/material.dart';
import '../services/api_service.dart';

// Guard so we only show one "Pay Now" dialog per ride at a time.
final Set<String> _prompting = {};

// Online gating: the driver ended an online ride (awaitingPayment) — ask the
// rider to confirm, then complete the ride. The existing "ride completed" flow
// performs the actual charge, so there is NO double-charge here.
Future<void> promptOnlinePayment(BuildContext context, String? rideId, Map<String, dynamic> ride) async {
  if (rideId == null || _prompting.contains(rideId)) return;
  _prompting.add(rideId);
  final amount = ((ride['totalFare'] ?? ride['fare'] ?? 0) as num).toDouble();
  final pay = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Pay to complete your ride'),
      content: Text('Please pay ₹${amount.toStringAsFixed(0)} to finish this ride.'),
      actions: [
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay Now')),
      ],
    ),
  );
  if (pay == true) {
    try { await ApiService.completeRide(rideId); } catch (_) {}
  }
  _prompting.remove(rideId);
}
