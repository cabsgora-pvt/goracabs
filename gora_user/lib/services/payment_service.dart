import 'dart:async';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'api_service.dart';

class PaymentResult {
  final bool success;
  final String? error;
  final num? balance; // wallet balance after top-up (for wallet purpose)
  final String? paymentId;
  // Razorpay order + signature for a verified payment. The server re-checks
  // both when a booking that was paid upfront is tied to its ride, so the
  // payment can be refunded if no driver is ever found.
  final String? orderId;
  final String? signature;
  const PaymentResult(this.success, {this.error, this.balance, this.paymentId, this.orderId, this.signature});

  /// What /rides/book needs to tie an upfront online payment to the ride.
  Map<String, String>? get bookingProof => (paymentId ?? '').isNotEmpty && (orderId ?? '').isNotEmpty && (signature ?? '').isNotEmpty
      ? {'orderId': orderId!, 'paymentId': paymentId!, 'signature': signature!}
      : null;
}

/// What came back from the Razorpay checkout sheet itself.
class CheckoutOutcome {
  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? error;
  const CheckoutOutcome.paid({required this.paymentId, required this.orderId, required this.signature})
      : success = true, error = null;
  const CheckoutOutcome.failed(this.error)
      : success = false, paymentId = null, orderId = null, signature = null;
}

/// The outcome of paying an online ride (POST /payment/razorpay/verify with
/// purpose 'ride' and the ride id).
class RidePaymentResult {
  /// Razorpay took the money and the server accepted it for this ride.
  final bool success;
  /// The server's view after this payment: 'paid', or 'pending' when the ride
  /// is still under way and will settle when the driver ends it.
  final String? paymentStatus;
  final num? amountPaid;
  final num? amountDue;
  /// 'amountShort' (402), 'notAwaitingPayment' (409), or another server code.
  final String? code;
  /// Money the server put back in the rider's Gora wallet (short / not due).
  final num refundedToWallet;
  /// The checkout was closed or failed before any money moved.
  final bool cancelled;
  final String? error;
  const RidePaymentResult({
    required this.success,
    this.paymentStatus,
    this.amountPaid,
    this.amountDue,
    this.code,
    this.refundedToWallet = 0,
    this.cancelled = false,
    this.error,
  });

  bool get paid => success && paymentStatus == 'paid';
}

/// Central helper for all Razorpay payments (wallet top-up, outstation
/// prepayment, paying an online ride) and for prepaying an outstation booking
/// by the chosen method.
///
/// Rides are never charged here at completion: the server debits a wallet ride
/// itself when the driver ends it, and an online ride is paid by the rider with
/// [payRide], against the server's own amountDue.
class PaymentService {
  /// Opens the Razorpay checkout with [options]. Replaceable in tests, where
  /// the native plugin does not exist.
  static Future<CheckoutOutcome> Function(Map<String, dynamic> options) openCheckout = _razorpayCheckout;

  static Future<CheckoutOutcome> _razorpayCheckout(Map<String, dynamic> options) {
    final completer = Completer<CheckoutOutcome>();
    final rzp = Razorpay();
    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      rzp.clear();
      if (!completer.isCompleted) {
        completer.complete(CheckoutOutcome.paid(
            paymentId: r.paymentId, orderId: r.orderId ?? options['order_id']?.toString(), signature: r.signature));
      }
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete(CheckoutOutcome.failed(r.message ?? 'Payment cancelled'));
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});
    try {
      rzp.open(options);
    } catch (e) {
      rzp.clear();
      if (!completer.isCompleted) completer.complete(CheckoutOutcome.failed('Could not open payment: $e'));
    }
    return completer.future;
  }

  /// Creates an order, runs the checkout, and verifies it with the server.
  /// Returns the order error, the checkout outcome, and the verify answer.
  static Future<({String? orderError, CheckoutOutcome? checkout, Map<String, dynamic>? verify})> _pay({
    required num amount,
    required String purpose,
    String? rideId,
    String? contact,
    String? email,
    String description = 'Gora Cabs',
  }) async {
    final order = await ApiService.createRazorpayOrder(amount: amount, purpose: purpose, rideId: rideId);
    if (order['orderId'] == null) {
      return (orderError: order['error']?.toString() ?? 'Could not start payment', checkout: null, verify: null);
    }
    final out = await openCheckout({
      'key': order['keyId'],
      'amount': order['amount'], // paise (from server)
      'order_id': order['orderId'],
      'currency': order['currency'] ?? 'INR',
      'name': 'Gora Cabs',
      'description': description,
      if (contact != null && contact.isNotEmpty)
        'prefill': {'contact': contact, if (email != null && email.isNotEmpty) 'email': email},
      'theme': {'color': '#0A3CC8'},
    });
    if (!out.success) return (orderError: null, checkout: out, verify: null);
    final verify = await ApiService.verifyRazorpayPayment(
      orderId: out.orderId ?? order['orderId'].toString(),
      paymentId: out.paymentId ?? '',
      signature: out.signature ?? '',
      purpose: purpose,
      rideId: rideId,
    );
    return (orderError: null, checkout: out, verify: verify);
  }

  /// Top up the wallet via Razorpay. Server credits the balance on success.
  static Future<PaymentResult> topUpWallet({required num amount, String? contact, String? email}) async {
    final r = await _pay(amount: amount, purpose: 'wallet', contact: contact, email: email, description: 'Wallet top-up');
    if (r.orderError != null) return PaymentResult(false, error: r.orderError);
    final out = r.checkout!;
    if (!out.success) return PaymentResult(false, error: out.error ?? 'Payment cancelled');
    final v = r.verify!;
    return v['success'] == true
        ? PaymentResult(true, balance: v['balance'] as num?, paymentId: out.paymentId, orderId: out.orderId, signature: out.signature)
        : PaymentResult(false, error: v['error']?.toString() ?? 'Verification failed');
  }

  /// Pays an online ride. The order names the ride and the server charges its
  /// own `amountDue` for it ([amountDue] is only what the rider was shown).
  /// The ride is never completed from here: the driver ends it.
  static Future<RidePaymentResult> payRide({
    required String rideId,
    required num amountDue,
    String? contact,
    String? email,
  }) async {
    try {
      final r = await _pay(amount: amountDue, purpose: 'ride', rideId: rideId,
          contact: contact, email: email, description: 'Ride payment');
      if (r.orderError != null) return RidePaymentResult(success: false, error: r.orderError);
      final out = r.checkout!;
      if (!out.success) {
        return RidePaymentResult(success: false, cancelled: true, error: out.error ?? 'Payment cancelled');
      }
      final v = r.verify!;
      num n(dynamic x) => x is num ? x : 0;
      return RidePaymentResult(
        success: v['success'] == true,
        paymentStatus: v['paymentStatus']?.toString(),
        amountPaid: v['amountPaid'] as num?,
        amountDue: v['amountDue'] as num?,
        code: v['code']?.toString() ?? (v['alreadyProcessed'] == true ? 'alreadyProcessed' : null),
        refundedToWallet: n(v['refundedToWallet']),
        error: v['success'] == true ? null : (v['error']?.toString() ?? 'Payment could not be confirmed'),
      );
    } catch (_) {
      return const RidePaymentResult(success: false, error: 'Could not reach Gora. Check your connection.');
    }
  }

  /// Prepays an outstation trip, before it is booked, by [method]:
  ///   cash   → nothing to charge now (pay the driver), returns success.
  ///   wallet → debit the wallet (no ride id: /rides/book links the debit).
  ///   online → Razorpay, purpose 'outstation_prepay'; [PaymentResult.bookingProof]
  ///            goes with the booking as `prepaid`.
  /// Shows a snackbar on failure.
  static Future<PaymentResult> prepayOutstation(
    BuildContext context, {
    required String method,
    required num amount,
    String? contact,
    String? email,
  }) async {
    if (method == 'cash' || amount <= 0) return const PaymentResult(true);
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (method == 'wallet') {
      final r = await ApiService.walletPrepay(amount: amount, note: 'Outstation trip');
      if (r['success'] == true) return PaymentResult(true, balance: r['balance'] as num?);
      final err = r['error']?.toString() ?? 'Wallet payment failed';
      messenger?.showSnackBar(SnackBar(content: Text(err)));
      return PaymentResult(false, error: err);
    }

    final r = await _pay(amount: amount, purpose: 'outstation_prepay', contact: contact, email: email,
        description: 'Outstation trip');
    String? err = r.orderError;
    PaymentResult? ok;
    if (err == null) {
      final out = r.checkout!;
      if (!out.success) {
        err = out.error ?? 'Payment cancelled';
      } else if (r.verify!['success'] == true) {
        ok = PaymentResult(true, paymentId: out.paymentId, orderId: out.orderId, signature: out.signature);
      } else {
        err = r.verify!['error']?.toString() ?? 'Verification failed';
      }
    }
    if (ok != null) return ok;
    messenger?.showSnackBar(SnackBar(content: Text(err ?? 'Payment failed')));
    return PaymentResult(false, error: err);
  }
}
