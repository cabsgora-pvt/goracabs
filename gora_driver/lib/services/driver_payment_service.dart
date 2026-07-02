import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'driver_api_service.dart';

/// Razorpay checkout for driver subscription purchases.
class DriverPaymentService {
  /// Runs Razorpay checkout for a plan, then activates it on the server.
  /// Returns the buy() response map (`{success:true,...}`) or `{error: ...}`.
  static Future<Map<String, dynamic>> paySubscription({
    required String planId,
    String? contact,
  }) async {
    final order = await DriverApiService.createSubscriptionOrder(planId);
    if (order['orderId'] == null) {
      // Surfaces "Unauthorized" (session expired) or "Razorpay is not enabled" etc.
      return {'error': order['error']?.toString() ?? 'Could not start payment'};
    }

    // An empty key_id is the #1 cause of Razorpay "Authentication failed".
    final key = (order['keyId'] ?? '').toString();
    if (key.isEmpty) {
      return {'error': 'Payment not configured. Ask admin to set valid Razorpay keys in Settings → Payment.'};
    }

    final completer = Completer<Map<String, dynamic>>();
    final rzp = Razorpay();

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
      final res = await DriverApiService.buySubscription(
        planId,
        orderId: r.orderId ?? order['orderId'].toString(),
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      rzp.clear();
      if (!completer.isCompleted) completer.complete(res);
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete({'error': r.message ?? 'Payment cancelled'});
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});

    try {
      rzp.open({
        'key': key,
        'amount': order['amount'],
        'order_id': order['orderId'],
        'currency': order['currency'] ?? 'INR',
        'name': 'Gora Cabs',
        'description': 'Driver subscription',
        if (contact != null && contact.isNotEmpty) 'prefill': {'contact': contact},
        'theme': {'color': '#1C2656'},
      });
    } catch (e) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete({'error': 'Could not open payment: $e'});
    }

    return completer.future;
  }
}
