import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../screens/active_ride_screen.dart';
import '../services/api_service.dart';
import '../widgets/account_hold.dart';

/// Books one ride: sends the booking with [clientRequestId] and returns the
/// server's answer. With [freshQuote] it first asks /fare/estimate again for
/// the same trip — the "Try again" after no driver was found, by which time
/// the original quote may have expired.
typedef RideBooker = Future<Map<String, dynamic>> Function(String clientRequestId, bool freshQuote);

/// The most a rider may tip at booking (the server refuses more: invalidTip).
const int kMaxTip = 500;

/// A random id for one booking attempt (RFC 4122 v4 layout). The server
/// returns the ride it already made for an id it has seen, so a retry after a
/// timeout can never book twice.
String newClientRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// A fresh signed quote for [vehicleType], from /fare/estimate called with
/// [estimate] (the same inputs the trip is booked with). Returns the vehicle's
/// entry ({fare, quoteToken, ...}), or null when it is no longer offered.
Future<Map<String, dynamic>?> freshQuoteFor(Map<String, dynamic> estimate, String? vehicleType) async {
  try {
    final res = await ApiService.post('/fare/estimate', estimate);
    final list = res['vehicles'];
    if (list is! List) return null;
    for (final v in list) {
      if (v is Map && v['name'] == vehicleType) return Map<String, dynamic>.from(v);
    }
  } catch (_) {}
  return null;
}

/// Books a ride once, then hands it to the live ride screen.
///
/// Rental, hire, parcel and outstation each booked from INSIDE the builder of
/// their "finding a driver" sheet. A builder is not a one-time callback: it runs
/// again whenever the sheet rebuilds — the phone rotates, the keyboard or theme
/// changes — and every run booked another ride
/// (test/book_in_builder_repro_test.dart). Each screen then tracked the ride in
/// its own bottom sheets, re-implementing what the live ride screen already does
/// and drifting from it. Taxi did the same, and charged the ride itself.
///
/// Here the booking runs once, from a button press, and the ride is then tracked
/// — and paid — on [ActiveRideScreen], the same screen a rider returns to from
/// home, so a ride looks and behaves the same whether it was just booked or
/// reopened.
///
/// The booking carries one `clientRequestId` per attempt. When the request
/// times out or the connection drops, the rider is offered a retry with the
/// SAME id: if the first request did reach the server, the retry gets that ride
/// back (`duplicate: true`) instead of booking a second one.
///
/// When the server already has a live ride for this rider (409 activeRide),
/// that ride is opened instead of an error.
///
/// The booking screen is replaced rather than stacked under the ride: backing
/// out of a live ride goes home, not to a form for booking it again.
///
/// [rebook] (default: [book]) is kept by the ride screen for "Try again" when
/// no driver is found; pass [canRebook] false for a trip that was paid before
/// booking, which must not be re-booked without a new payment.
///
/// Returns the new ride's id, or null when booking failed; the rider has been
/// told why, and is still on the booking screen to retry.
Future<String?> bookAndTrack(
  BuildContext context, {
  required RideBooker book,
  bool freshQuote = false,
  bool canRebook = true,
  String Function(String error)? failureMessage,
  void Function(Map<String, dynamic> response)? onBooked,
}) async {
  final navigator = Navigator.of(context);
  final dialogs = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final clientRequestId = newClientRequestId();
  var fresh = freshQuote;

  Map<String, dynamic> res;
  while (true) {
    // Blocks a second tap while the request is out, and gives the rider
    // something to look at on a slow network.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    var unreachable = false;
    try {
      res = await book(clientRequestId, fresh);
    } catch (_) {
      // post() throws, rather than returning an error map, when the request
      // timed out or there is no connection at all. The server may or may not
      // have made the ride.
      unreachable = true;
      res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
    }
    dialogs.pop();
    if (!unreachable) break;
    if (!context.mounted) return null;
    final retry = await _askRetry(context);
    if (retry != true || !context.mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(res['error'].toString()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ));
      return null;
    }
    // Same id, same quote: a retry must find the ride the first one made.
    fresh = false;
  }

  final ride = res['ride'];
  final id = (ride is Map ? ride['id'] ?? ride['_id'] : null)?.toString() ?? '';
  if (id.isEmpty) {
    // Signed out (401): SessionGuard has already taken the rider to sign in.
    if (res['httpStatus'] == 401 || res['code'] == 'unauthorized') return null;

    // A live ride already exists: open it rather than report an error.
    final activeId = (res['activeRideId'] ?? '').toString();
    if (res['code'] == 'activeRide' && activeId.isNotEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('You already have a ride in progress — here it is.'),
        duration: Duration(seconds: 5),
      ));
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: activeId)));
      return activeId;
    }

    final error = (res['error'] ?? 'Please try again.').toString();
    // A payment taken before booking (outstation) that the server gave back
    // because the booking was refused: tell the rider where the money is,
    // instead of "contact support, do not pay again".
    final refunded = res['refunded'];
    final message = refunded is num && refunded > 0
        ? refundedMessage(error, refunded)
        : res['code'] == 'prepaymentRequired'
            ? error
            : (failureMessage?.call(error) ?? 'Booking failed: $error');
    // A held account is not a failure worth retrying: say so plainly.
    if (isAccountHoldResponse(res)) {
      // A rider who has already paid must be told what happened to the money.
      final paidNote = refunded is num && refunded > 0 ? message : failureMessage?.call(error);
      if (context.mounted) await showAccountHoldDialog(context, paidNote ?? error);
      return null;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 6),
    ));
    return null;
  }

  _announceCoupon(messenger, res);
  onBooked?.call(res);
  navigator.pushReplacement(MaterialPageRoute(
      builder: (_) => ActiveRideScreen(rideId: id, rebook: canRebook ? book : null)));
  return id;
}

/// The server decides every coupon at booking. Say what it decided: the
/// discount it gave, or why it gave none — never a discount the phone made up.
void _announceCoupon(ScaffoldMessengerState messenger, Map<String, dynamic> res) {
  final ride = res['ride'] is Map ? res['ride'] as Map : const {};
  final discount = ride['couponDiscount'];
  final code = (ride['couponCode'] ?? '').toString();
  final promo = res['promo'];
  if (discount is num && discount > 0) {
    final rupees = discount == discount.roundToDouble() ? discount.toInt().toString() : discount.toStringAsFixed(2);
    messenger.showSnackBar(SnackBar(
      content: Text('Coupon ${code.isNotEmpty ? '$code ' : ''}applied: ₹$rupees off'),
      backgroundColor: Colors.green[700],
    ));
  } else if (promo is Map && promo['applied'] != true && (promo['reason'] ?? '').toString().isNotEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text('Coupon not applied: ${promo['reason']}'),
      backgroundColor: Colors.orange,
    ));
  }
}

Future<bool?> _askRetry(BuildContext context) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) => AlertDialog(
    title: const Text('Could not confirm your booking'),
    content: const Text('The connection dropped before Gora answered. '
        'Retrying is safe — it will not book a second ride.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retry')),
    ],
  ),
);

/// What a rider reads when a booking they had already paid for was refused and
/// the server put the money back in their Gora wallet.
String refundedMessage(String error, num amount) {
  final rupees = amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(2);
  return 'The trip could not be booked ($error). '
      'Your payment of ₹$rupees has been returned to your Gora wallet.';
}
