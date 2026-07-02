import 'dart:async';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'api_service.dart';

class PaymentResult {
  final bool success;
  final String? error;
  final num? balance; // wallet balance after top-up (for wallet purpose)
  final String? paymentId;
  const PaymentResult(this.success, {this.error, this.balance, this.paymentId});
}

/// Central helper for all Razorpay payments (wallet top-up + ride payment)
/// and for charging a booking by the chosen method (cash / wallet / online).
class PaymentService {
  /// Runs a Razorpay checkout for [amount] rupees and verifies it on the server.
  /// purpose = 'wallet' credits the wallet; 'ride' just verifies the payment.
  static Future<PaymentResult> _razorpay({
    required num amount,
    required String purpose,
    String? rideId,
    String? contact,
    String? email,
    String description = 'Gora Cabs',
  }) async {
    final order = await ApiService.createRazorpayOrder(amount: amount, purpose: purpose, rideId: rideId);
    if (order['orderId'] == null) {
      return PaymentResult(false, error: order['error']?.toString() ?? 'Could not start payment');
    }

    final completer = Completer<PaymentResult>();
    final rzp = Razorpay();

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
      final verify = await ApiService.verifyRazorpayPayment(
        orderId: r.orderId ?? order['orderId'].toString(),
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
        purpose: purpose,
        amount: amount,
        rideId: rideId,
      );
      rzp.clear();
      if (!completer.isCompleted) {
        completer.complete(verify['success'] == true
            ? PaymentResult(true, balance: verify['balance'] as num?, paymentId: r.paymentId)
            : PaymentResult(false, error: verify['error']?.toString() ?? 'Verification failed'));
      }
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete(PaymentResult(false, error: r.message ?? 'Payment cancelled'));
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});

    try {
      rzp.open({
        'key': order['keyId'],
        'amount': order['amount'], // paise (from server)
        'order_id': order['orderId'],
        'currency': order['currency'] ?? 'INR',
        'name': 'Gora Cabs',
        'description': description,
        if (contact != null && contact.isNotEmpty)
          'prefill': {'contact': contact, if (email != null && email.isNotEmpty) 'email': email},
        'theme': {'color': '#1C2656'},
      });
    } catch (e) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete(PaymentResult(false, error: 'Could not open payment: $e'));
    }

    return completer.future;
  }

  /// Top up the wallet via Razorpay. Server credits the balance on success.
  static Future<PaymentResult> topUpWallet({required num amount, String? contact, String? email}) =>
      _razorpay(amount: amount, purpose: 'wallet', contact: contact, email: email, description: 'Wallet top-up');

  /// Charge a booking by the selected [method] for [amount] rupees.
  ///   cash   → nothing to charge now (pay driver), returns success.
  ///   wallet → deduct from wallet balance (fails if low balance).
  ///   online → Razorpay checkout.
  /// Shows snackbars for errors. Returns true if the booking may proceed.
  static Future<bool> charge(
    BuildContext context, {
    required String method,
    required num amount,
    String? rideId,
    String? contact,
    String? email,
  }) async {
    if (method == 'cash' || amount <= 0) return true;

    if (method == 'wallet') {
      final r = await ApiService.walletPay(amount: amount, note: 'Ride payment', rideId: rideId);
      if (r['success'] == true) return true;
      if (context.mounted) {
        final err = r['error']?.toString() ?? 'Wallet payment failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
      return false;
    }

    // online
    final res = await _razorpay(
      amount: amount, purpose: 'ride', rideId: rideId, contact: contact, email: email, description: 'Ride payment',
    );
    if (res.success) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Payment failed')));
    }
    return false;
  }
}
