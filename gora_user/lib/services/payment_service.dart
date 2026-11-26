import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'api_service.dart';

/// Razorpay success proofs not yet confirmed by Gora.
///
/// Razorpay has taken the money the moment its checkout reports success; only
/// the verify call then tells Gora. When that call never arrived — no signal,
/// the app killed in between, a 502 — the money was in limbo until support
/// found it. Each proof ({orderId, paymentId, signature, purpose, rideId}) is
/// now written to secure storage BEFORE verify is called, removed once verify
/// settles it, and verified again at the next app start / resume until it does
/// ([PaymentService.retryPendingProofs]).
class PendingPaymentProofs {
  PendingPaymentProofs._();

  static const _key = 'pending_payment_proofs';
  static const FlutterSecureStorage _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Proofs older than this are dropped: by then the Razorpay webhook (or
  /// support) has long settled the payment, and a dead proof is not retried forever.
  static const maxAge = Duration(days: 7);

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final raw = await _store.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    try {
      if (list.isEmpty) {
        await _store.delete(key: _key);
      } else {
        await _store.write(key: _key, value: jsonEncode(list));
      }
    } catch (_) {}
  }

  /// Keeps [proof] (one per paymentId).
  static Future<void> add(Map<String, dynamic> proof) async {
    final id = '${proof['paymentId'] ?? ''}';
    if (id.isEmpty) return;
    final list = (await load()).where((p) => p['paymentId'] != id).toList()
      ..add({...proof, 'savedAt': DateTime.now().toUtc().toIso8601String()});
    await _save(list);
  }

  static Future<void> remove(String paymentId) async {
    final list = await load();
    final kept = list.where((p) => p['paymentId'] != paymentId).toList();
    if (kept.length != list.length) await _save(kept);
  }
}

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
  /// 'amountShort' (402), 'notAwaitingPayment' (409), 'confirmingLater' (Razorpay
  /// took it, Gora has not confirmed it yet: retried automatically), or
  /// another server code.
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

  /// Whether a verify answer is final for its proof: the payment was accepted
  /// (success / alreadyCredited / alreadyProcessed), or refused in a way a
  /// retry cannot change (a bad signature, an order that is not this rider's or
  /// this ride's, a payment that could not pay the ride and was credited to the
  /// wallet). Not final: no answer at all, a 5xx / 502, 401 / 403 / 408 / 429,
  /// and "Payment not completed yet" — those are worth asking again.
  static bool verifyIsFinal(Map<String, dynamic> v) {
    if (v['success'] == true || v['alreadyCredited'] == true || v['alreadyProcessed'] == true) return true;
    final status = v['httpStatus'];
    if (status is! int) return false;
    if (status >= 500 || status == 401 || status == 403 || status == 408 || status == 429) return false;
    if ('${v['error'] ?? ''}'.toLowerCase().contains('not completed')) return false;
    return status >= 400;
  }

  /// Sends a proof to verify, never throwing: a dropped connection answers
  /// {error} without an httpStatus, which [verifyIsFinal] keeps for a retry.
  static Future<Map<String, dynamic>> _verify(Map<String, dynamic> proof) async {
    try {
      return await ApiService.verifyRazorpayPayment(
        orderId: '${proof['orderId'] ?? ''}',
        paymentId: '${proof['paymentId'] ?? ''}',
        signature: '${proof['signature'] ?? ''}',
        purpose: '${proof['purpose'] ?? 'wallet'}',
        rideId: (proof['rideId'] ?? '').toString().isEmpty ? null : proof['rideId'].toString(),
      );
    } catch (_) {
      return {'error': 'Could not reach Gora to confirm the payment.', 'unreachable': true};
    }
  }

  static Future<int>? _retrying;

  /// Verifies every saved proof again (app start / resume), dropping each one
  /// the server settles and any older than [PendingPaymentProofs.maxAge].
  /// Returns how many were settled. One run at a time; never throws.
  static Future<int> retryPendingProofs() => _retrying ??= _retryAll().whenComplete(() => _retrying = null);

  static Future<int> _retryAll() async {
    var settled = 0;
    try {
      final list = await PendingPaymentProofs.load();
      final now = DateTime.now().toUtc();
      for (final p in list) {
        final id = '${p['paymentId'] ?? ''}';
        final saved = DateTime.tryParse('${p['savedAt'] ?? ''}');
        if (id.isEmpty || (saved != null && now.difference(saved) > PendingPaymentProofs.maxAge)) {
          await PendingPaymentProofs.remove(id);
          continue;
        }
        final v = await _verify(p);
        if (verifyIsFinal(v)) {
          await PendingPaymentProofs.remove(id);
          if (v['success'] == true || v['alreadyCredited'] == true || v['alreadyProcessed'] == true) settled++;
        }
      }
    } catch (_) {}
    return settled;
  }

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
    // Razorpay has the money now. Kept before verify is even sent, so a
    // verify lost on the way is sent again at the next start / resume.
    final proof = <String, dynamic>{
      'orderId': out.orderId ?? order['orderId'].toString(),
      'paymentId': out.paymentId ?? '',
      'signature': out.signature ?? '',
      'purpose': purpose,
      'rideId': ?rideId,
    };
    await PendingPaymentProofs.add(proof);
    final verify = await _verify(proof);
    if (verifyIsFinal(verify)) await PendingPaymentProofs.remove('${proof['paymentId']}');
    return (orderError: null, checkout: out, verify: verify);
  }

  /// What the rider reads when Razorpay took the payment but Gora could not
  /// confirm it yet: the app confirms it by itself later.
  static const confirmingLater = 'Payment received. We could not confirm it with Gora yet — '
      'it will be confirmed automatically; please do not pay again.';

  /// Top up the wallet via Razorpay. Server credits the balance on success.
  static Future<PaymentResult> topUpWallet({required num amount, String? contact, String? email}) async {
    final r = await _pay(amount: amount, purpose: 'wallet', contact: contact, email: email, description: 'Wallet top-up');
    if (r.orderError != null) return PaymentResult(false, error: r.orderError);
    final out = r.checkout!;
    if (!out.success) return PaymentResult(false, error: out.error ?? 'Payment cancelled');
    final v = r.verify!;
    if (v['success'] == true) {
      return PaymentResult(true, balance: v['balance'] as num?, paymentId: out.paymentId, orderId: out.orderId, signature: out.signature);
    }
    return PaymentResult(false, error: verifyIsFinal(v) ? (v['error']?.toString() ?? 'Verification failed') : confirmingLater);
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
        code: v['code']?.toString() ??
            (v['alreadyProcessed'] == true ? 'alreadyProcessed' : (verifyIsFinal(v) ? null : 'confirmingLater')),
        refundedToWallet: n(v['refundedToWallet']),
        error: v['success'] == true
            ? null
            : (verifyIsFinal(v) ? (v['error']?.toString() ?? 'Payment could not be confirmed') : confirmingLater),
      );
    } catch (_) {
      return const RidePaymentResult(success: false, error: 'Could not reach Gora. Check your connection.');
    }
  }

  /// Pays what is still due on a COMPLETED wallet ride from the wallet
  /// (/wallet/pay with the ride id; the server charges its own amountDue).
  /// Returns null on success, else what to tell the rider. 409 notPayableYet:
  /// the trip has not ended, so nothing is final to pay yet.
  static Future<String?> payRideFromWallet(String rideId) async {
    Map<String, dynamic> r;
    try {
      r = await ApiService.walletPayRide(rideId);
    } catch (_) {
      return 'Could not reach Gora. Check your connection.';
    }
    if (r['success'] == true) return null;
    if (r['code'] == 'notPayableYet') return 'Pay after the trip ends.';
    if (r['httpStatus'] == 402) {
      final rupee = String.fromCharCode(0x20B9);
      final bal = r['balance'] is num ? ' (balance $rupee${(r['balance'] as num).round()})' : '';
      return 'Not enough money in your Gora wallet$bal. Add money and try again.';
    }
    return r['error']?.toString() ?? 'Wallet payment failed';
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
        err = verifyIsFinal(r.verify!) ? (r.verify!['error']?.toString() ?? 'Verification failed') : confirmingLater;
      }
    }
    if (ok != null) return ok;
    messenger?.showSnackBar(SnackBar(content: Text(err ?? 'Payment failed')));
    return PaymentResult(false, error: err);
  }
}
