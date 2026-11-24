import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'driver_api_service.dart';

/// Razorpay checkout for driver subscription purchases and wallet top-ups.
class DriverPaymentService {
  /// Adds [amount] rupees to the driver's wallet through Razorpay checkout.
  /// Returns `{success:true, walletBalance, amount}` or `{error: ...}`.
  static Future<Map<String, dynamic>> rechargeWallet({required int amount, String? contact}) async {
    final order = await DriverApiService.createRechargeOrder(amount);
    if (order['orderId'] == null) {
      return {'error': order['error']?.toString() ?? 'Could not start payment'};
    }
    final key = (order['keyId'] ?? '').toString();
    if (key.isEmpty) {
      return {'error': 'Payment not configured. Please contact support to add balance.'};
    }

    final completer = Completer<Map<String, dynamic>>();
    final rzp = Razorpay();
    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
      Map<String, dynamic> res;
      try {
        res = await DriverApiService.verifyRecharge(
          orderId: r.orderId ?? order['orderId'].toString(),
          paymentId: r.paymentId ?? '',
          signature: r.signature ?? '',
        );
      } catch (_) {
        res = {'error': 'Payment received but not confirmed yet. It will show in your wallet shortly.'};
      }
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
        'description': 'Wallet recharge',
        if (contact != null && contact.isNotEmpty) 'prefill': {'contact': contact},
        'theme': {'color': '#0A3CC8'},
      });
    } catch (e) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete({'error': 'Could not open payment: $e'});
    }
    return completer.future;
  }

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
      Map<String, dynamic> res;
      try {
        // The order came from /subscription/order, which stamps it for this
        // driver and plan — the only kind of order /subscription/buy accepts
        // (a generic /payment/razorpay/order is refused).
        res = await DriverApiService.buySubscription(
          planId,
          orderId: r.orderId ?? order['orderId'].toString(),
          paymentId: r.paymentId ?? '',
          signature: r.signature ?? '',
        );
      } catch (_) {
        res = {'error': 'Payment received but not confirmed yet. Pull down to refresh in a moment.'};
      }
      // Already activated by this same payment: a success.
      if (res['alreadyApplied'] == true) res = {...res, 'success': true};
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
        'theme': {'color': '#0A3CC8'},
      });
    } catch (e) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete({'error': 'Could not open payment: $e'});
    }

    return completer.future;
  }
}
