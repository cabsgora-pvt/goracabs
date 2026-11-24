import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/active_ride_screen.dart';
import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/utils/ride_booking.dart';

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/rides/book, as the hardened server answers it, through the real
// ApiService and bookAndTrack:
//   * one clientRequestId per booking attempt, reused when a request that timed
//     out is retried (the server then returns the ride it already made);
//   * 409 activeRide opens the rider's live ride instead of an error;
//   * the coupon shown is the one the SERVER applied;
//   * 402 prepaymentRequired says where a refunded payment went.
// ─────────────────────────────────────────────────────────────────────────────

class _Form extends StatelessWidget {
  final RideBooker book;
  const _Form(this.book);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ElevatedButton(
      onPressed: () => bookAndTrack(context, book: book),
      child: const Text('Confirm Booking'),
    )),
  );
}

Widget _app(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(home: home),
);

/// The body a screen sends: whatever it books, plus the attempt's id.
Future<Map<String, dynamic>> _bookTaxi(String id, bool fresh) => ApiService.bookRide({
  'clientRequestId': id,
  'service': 'taxi', 'vehicleType': 'Cab Economy',
  'pickupLat': 23.02, 'pickupLng': 72.57, 'dropLat': 23.07, 'dropLng': 72.62,
  'fare': 240, 'tip': 0, 'paymentMode': 'cash', 'couponCode': 'SAVE50',
});

Map<String, dynamic> _ride(String id) => {
  '_id': id, 'status': 'pending', 'uiPhase': 'finding', 'service': 'taxi',
  'pickupLat': 23.02, 'pickupLng': 72.57, 'dropLat': 23.07, 'dropLng': 72.62,
  'pickupAddress': 'Navrangpura', 'dropAddress': 'Bodakdev', 'fare': 240,
  'couponCode': 'SAVE50', 'couponDiscount': 50,
};

/// A JSON answer; utf-8, since the server's messages carry ₹.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

  test('clientRequestId is a fresh v4-style id per attempt', () {
    final a = newClientRequestId(), b = newClientRequestId();
    expect(a, isNot(b));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue, reason: a);
  });

  testWidgets('sends a clientRequestId with the rider token, and a retry after a timeout reuses it', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final auth = <String?>[];
    var bookCalls = 0;
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        bookCalls++;
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        auth.add(req.headers['Authorization']);
        // The first request reaches the server but the answer never arrives.
        if (bookCalls == 1) throw TimeoutException('lost on the way back');
        // The retry carries the same id: the server hands back the same ride.
        return _json({'success': true, 'duplicate': true, 'ride': {'id': 'r-1'}}, 200);
      }
      if (req.url.path.contains('/rides/')) return _json(_ride('r-1'), 200);
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not confirm your booking'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);

    expect(bookCalls, 2);
    final id = bodies[0]['clientRequestId'];
    expect(id, isA<String>());
    expect((id as String).length, greaterThan(20));
    expect(bodies[1]['clientRequestId'], id, reason: 'the retry must not look like a new booking');
    expect(auth, everyElement('Bearer rider-token'));
    expect(bodies[0].containsKey('couponDiscount'), isFalse, reason: 'only the code is sent; the server decides');
    expect(find.byType(ActiveRideScreen), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('two separate bookings get two different ids', (tester) async {
    final ids = <String>[];
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        ids.add((jsonDecode(req.body) as Map)['clientRequestId'] as String);
        return _json({'error': 'Fare quote rejected: Quote expired'}, 400);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Confirm Booking'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 7)); // let the snackbar go
      }
    }, () => api);
    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
    await _drain(tester);
  });

  testWidgets('409 activeRide opens that ride instead of an error', (tester) async {
    String? opened;
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return _json({
          'error': 'You already have a ride in progress. Finish or cancel it before booking another.',
          'code': 'activeRide', 'activeRideId': 'live-7', 'activeRideStatus': 'accepted',
        }, 409);
      }
      if (req.url.path.endsWith('/rides/live-7')) {
        opened = 'live-7';
        return _json(_ride('live-7')..['status'] = 'accepted'..['uiPhase'] = 'assigned', 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);

    final screen = tester.widget<ActiveRideScreen>(find.byType(ActiveRideScreen));
    expect(screen.rideId, 'live-7');
    expect(opened, 'live-7');
    expect(find.textContaining('Booking failed'), findsNothing);
    expect(find.textContaining('already have a ride in progress'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('the coupon announced is the discount the server applied', (tester) async {
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return _json({
          'success': true,
          'ride': {'id': 'r-2', 'couponCode': 'SAVE50', 'couponDiscount': 35, 'payableEstimate': 205},
          'promo': {'code': 'SAVE50', 'applied': true, 'discount': 35},
        }, 200);
      }
      if (req.url.path.contains('/rides/')) {
        return _json(_ride('r-2')..['couponDiscount'] = 35, 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);

    expect(find.descendant(of: find.byType(SnackBar), matching: find.text('Coupon SAVE50 applied: ₹35 off')), findsOneWidget);
    // The ride screen shows the server's figure too.
    expect(find.byKey(const ValueKey('ride-coupon')), findsOneWidget);
    expect(find.textContaining('₹35 off'), findsWidgets);
    expect(find.textContaining('₹50 off'), findsNothing);
    await _drain(tester);
  });

  testWidgets('a coupon the server refused says why', (tester) async {
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return _json({
          'success': true,
          'ride': {'id': 'r-3', 'couponCode': '', 'couponDiscount': 0},
          'promo': {'code': 'SAVE50', 'applied': false, 'reason': 'You have already used this code'},
        }, 200);
      }
      if (req.url.path.contains('/rides/')) {
        return _json(_ride('r-3')..['couponDiscount'] = 0..['couponCode'] = '', 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);
    expect(find.text('Coupon not applied: You have already used this code'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('402 prepaymentRequired with a refund says the money is back in the wallet', (tester) async {
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return _json({
          'error': 'Your payment of ₹3000 does not cover the ₹3400 fare. It was added to your Gora wallet; please pay again.',
          'code': 'prepaymentRequired', 'amountDue': 3400, 'couponDiscount': 0,
          'refunded': 3000, 'refundedTo': 'wallet', 'walletBalance': 3120,
        }, 402);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);
    expect(find.textContaining('₹3000 has been returned to your Gora wallet'), findsOneWidget);
    expect(find.text('Confirm Booking'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('400 invalidTip is reported as the server put it', (tester) async {
    final api = MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return _json({'error': 'Tip must be between ₹0 and ₹500', 'code': 'invalidTip'}, 400);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const _Form(_bookTaxi)));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }, () => api);
    expect(find.text('Booking failed: Tip must be between ₹0 and ₹500'), findsOneWidget);
    expect(kMaxTip, 500);
    await _drain(tester);
  });
}
