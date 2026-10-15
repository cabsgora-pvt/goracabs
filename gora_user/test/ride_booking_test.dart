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
import 'package:customer_app/utils/ride_booking.dart';
import 'package:customer_app/utils/ride_payable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// bookAndTrack: how rental, hire, parcel and outstation now book.
//
// test/book_in_builder_repro_test.dart shows why they had to change: booking
// from inside a sheet builder books again whenever the sheet rebuilds. These
// pin the replacement down — one booking per press, failures reported instead of
// swallowed, and the ride handed to the live ride screen with its coupon.
// ─────────────────────────────────────────────────────────────────────────────

/// A stand-in booking screen: one button that books through bookAndTrack.
class _BookingForm extends StatelessWidget {
  final Future<Map<String, dynamic>> Function() book;
  final num coupon;
  final String Function(String)? failureMessage;
  const _BookingForm({required this.book, this.coupon = 0, this.failureMessage});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ElevatedButton(
      onPressed: () => bookAndTrack(context, book: book, couponDiscount: coupon,
          failureMessage: failureMessage),
      child: const Text('Confirm Booking'),
    )),
  );
}

Widget _app(Widget form) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(home: form),
);

/// The live ride screen polls once it opens; answer it so it can render.
MockClient _rideApi() => MockClient((req) async {
  if (req.url.path.contains('/rides/')) {
    return http.Response(jsonEncode({
      '_id': 'new-ride', 'status': 'pending', 'uiPhase': 'finding', 'service': 'hire_driver',
      'pickupLat': 23.02, 'pickupLng': 72.57, 'dropLat': 23.07, 'dropLng': 72.62,
      'pickupAddress': 'Navrangpura', 'dropAddress': 'Bodakdev', 'fare': 600,
    }), 200);
  }
  return http.Response('{}', 200);
});

/// Unmounts everything and runs out the ride screen's one-shot 2s ETA timer.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() => SharedPreferences.setMockInitialValues({'token': 'test'}));

  testWidgets('books once and opens the live ride screen', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_BookingForm(book: () async {
        calls++;
        return {'success': true, 'ride': {'id': 'new-ride'}};
      })));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }, _rideApi);

    expect(calls, 1);
    expect(find.byType(ActiveRideScreen), findsOneWidget);
    // Replaced, not stacked: backing out of the ride must not land on the form.
    // skipOffstage: false, or a form merely hidden under the ride would pass.
    expect(find.text('Confirm Booking', skipOffstage: false), findsNothing);
    await _drain(tester);
  });

  // The failure mode that forced this change: a rebuild while the request is
  // out. The form here rotates mid-booking.
  testWidgets('a rebuild during booking does not book again', (tester) async {
    var calls = 0;
    final answer = Completer<Map<String, dynamic>>();
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_BookingForm(book: () {
        calls++;
        return answer.future;
      })));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();

      tester.view.physicalSize = const Size(2400, 1080); // rotate
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.physicalSize = const Size(1080, 2400); // and back
      await tester.pump(const Duration(milliseconds: 300));

      answer.complete({'success': true, 'ride': {'id': 'new-ride'}});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }, _rideApi);

    expect(calls, 1);
    await _drain(tester);
  });

  testWidgets('blocks a second tap while the booking is out', (tester) async {
    var calls = 0;
    final answer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_app(_BookingForm(book: () {
      calls++;
      return answer.future;
    })));
    await tester.tap(find.text('Confirm Booking'));
    await tester.pump();
    // The progress barrier covers the button.
    await tester.tap(find.text('Confirm Booking'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    answer.complete({'error': 'late'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _drain(tester);
  });

  testWidgets('a refused booking says why and leaves the rider on the form', (tester) async {
    await tester.pumpWidget(_app(_BookingForm(
        book: () async => {'error': 'Fare quote rejected: expired. Please refresh and try again.'})));
    await tester.tap(find.text('Confirm Booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Booking failed: Fare quote rejected: expired. Please refresh and try again.'),
        findsOneWidget);
    expect(find.text('Confirm Booking'), findsOneWidget);
    expect(find.byType(ActiveRideScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'The progress dialog must close');
    await _drain(tester);
  });

  // post() throws, rather than returning an error map, with no connection at all.
  testWidgets('no connection is reported, not swallowed', (tester) async {
    await tester.pumpWidget(_app(_BookingForm(book: () async => throw Exception('SocketException'))));
    await tester.tap(find.text('Confirm Booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Could not reach Gora'), findsOneWidget);
    expect(find.text('Confirm Booking'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('a paid-for trip that fails to book says not to pay again', (tester) async {
    await tester.pumpWidget(_app(_BookingForm(
      book: () async => {'error': 'No drivers in zone'},
      failureMessage: (e) => 'Your payment went through, but the trip could not be booked ($e). '
          'Please contact support with this message. Do not pay again.',
    )));
    await tester.tap(find.text('Confirm Booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Do not pay again'), findsOneWidget);
    expect(find.textContaining('No drivers in zone'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('the coupon is stored with the ride before it opens', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_BookingForm(
        coupon: 75,
        book: () async => {'success': true, 'ride': {'id': 'new-ride'}},
      )));
      await tester.tap(find.text('Confirm Booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }, _rideApi);

    expect(await RideCouponStore.load('new-ride'), 75);
    await _drain(tester);
  });
}
