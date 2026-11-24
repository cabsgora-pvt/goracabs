import 'package:flutter/material.dart';
import '../screens/active_ride_screen.dart';
import '../widgets/account_hold.dart';
import 'ride_payable.dart';

/// Books a ride once, then hands it to the live ride screen.
///
/// Rental, hire, parcel and outstation each booked from INSIDE the builder of
/// their "finding a driver" sheet. A builder is not a one-time callback: it runs
/// again whenever the sheet rebuilds — the phone rotates, the keyboard or theme
/// changes — and every run booked another ride
/// (test/book_in_builder_repro_test.dart). Each screen then tracked the ride in
/// its own bottom sheets, re-implementing what the live ride screen already does
/// and drifting from it.
///
/// Here the booking runs once, from a button press, and the ride is then tracked
/// on [ActiveRideScreen] — the same screen a rider returns to from home — so a
/// ride looks and behaves the same whether it was just booked or reopened.
///
/// The booking screen is replaced rather than stacked under the ride: backing
/// out of a live ride goes home, not to a form for booking it again.
///
/// Returns the new ride's id, or null when booking failed; the rider has been
/// told why, and is still on the booking screen to retry.
Future<String?> bookAndTrack(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function() book,
  num couponDiscount = 0,
  String Function(String error)? failureMessage,
  void Function(Map<String, dynamic> response)? onBooked,
}) async {
  final navigator = Navigator.of(context);
  final dialogs = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

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

  Map<String, dynamic> res;
  try {
    res = await book();
  } catch (_) {
    // post() throws, rather than returning an error map, when there is no
    // connection at all. Every screen used to swallow this and leave the rider
    // watching "Finding your driver" for a ride that did not exist.
    res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
  }
  dialogs.pop();

  final ride = res['ride'];
  final id = (ride is Map ? ride['id'] ?? ride['_id'] : null)?.toString() ?? '';
  if (id.isEmpty) {
    final error = (res['error'] ?? 'Please try again.').toString();
    // A payment taken before booking (outstation) that the server gave back
    // because the booking was refused: tell the rider where the money is,
    // instead of "contact support, do not pay again".
    final refunded = res['refunded'];
    final message = refunded is num && refunded > 0
        ? refundedMessage(error, refunded)
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

  // Before navigating: if the app is killed on the next frame, a ride reopened
  // from home must still be charged with its coupon.
  await RideCouponStore.save(id, couponDiscount);
  onBooked?.call(res);
  navigator.pushReplacement(MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: id)));
  return id;
}

/// What a rider reads when a booking they had already paid for was refused and
/// the server put the money back in their Gora wallet.
String refundedMessage(String error, num amount) {
  final rupees = amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(2);
  return 'The trip could not be booked ($error). '
      'Your payment of ₹$rupees has been returned to your Gora wallet.';
}
