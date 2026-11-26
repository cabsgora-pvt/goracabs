import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/taxi_booking_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/vehicle_marker.dart';

import 'taxi_ride_flow_test.dart' show FakeServer, advance;

// ─────────────────────────────────────────────────────────────────────────────
// Taxi: a stop searches Google places like pickup / drop (it used to be plain
// text with no suggestions), and "Booking for: Someone else" sends the
// passenger to /rides/book.
// ─────────────────────────────────────────────────────────────────────────────

late FakeServer server;
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => server.client);

Widget screen() => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: const TaxiBookingScreen(
        fromLocation: 'Current Location', hideLocationInputs: false, preselectedVehicle: 'Bike'),
  ),
);

Future<void> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => VehicleMarkers.descriptorFor('Bike'));
  await act(() async {
    await tester.pumpWidget(screen());
    await advance(tester, const Duration(seconds: 1));
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await advance(tester, const Duration(milliseconds: 300));
  });
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  while (tester.takeException() != null) {}
}

Finder dropField() => find.widgetWithText(TextField, 'Where to?');
Finder stopField() =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Add stop 1 (address)');

Future<void> pickDrop(WidgetTester tester) async {
  await tester.enterText(dropField(), 'Race');
  await advance(tester, const Duration(milliseconds: 600));
  await tester.tap(find.text('Race Course'));
  await advance(tester, const Duration(milliseconds: 600));
}

Future<void> toConfirm(WidgetTester tester, {Future<void> Function()? beforeConfirm}) async {
  await tester.tap(find.text('Confirm Location'));
  await advance(tester, const Duration(seconds: 1));
  await tester.tap(find.text('Choose Bike'));
  await advance(tester, const Duration(milliseconds: 600));
  if (beforeConfirm != null) await beforeConfirm();
  await tester.tap(find.text('Confirm Pickup'));
  await advance(tester, const Duration(milliseconds: 600));
  await tester.tap(find.text('Confirm Ride'));
  await advance(tester, const Duration(seconds: 1));
}

Map<String, dynamic> lastBook() {
  final b = server.requests.lastWhere((r) => r.url.path.endsWith('/rides/book'));
  return jsonDecode(b.body) as Map<String, dynamic>;
}

void main() {
  setUp(() {
    server = FakeServer();
    SharedPreferences.setMockInitialValues({'token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  testWidgets('typing a stop shows Google suggestions; the picked place is booked as the stop', (tester) async {
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Add stop'));
      await advance(tester, const Duration(milliseconds: 300));
      await tester.enterText(stopField(), 'Kalavad');
      await tester.pump();
      expect(find.text('Searching…'), findsOneWidget);
      await advance(tester, const Duration(milliseconds: 600));
      expect(find.text('Kalavad Road'), findsOneWidget);
      // The same search as pickup / drop: in a Places session.
      final auto = server.requests.lastWhere((r) => r.url.path.endsWith('/places/autocomplete'));
      expect(auto.url.queryParameters['q'], 'Kalavad');
      expect(auto.url.queryParameters['sessiontoken'], isNotEmpty);
      await tester.tap(find.text('Kalavad Road'));
      await advance(tester, const Duration(milliseconds: 600));
      final details = server.requests.lastWhere((r) => r.url.path.endsWith('/places/details'));
      expect(details.url.queryParameters['placeId'], 'p2');
      expect(find.text('Searching…'), findsNothing);
      await pickDrop(tester);
      await toConfirm(tester);
    });
    final body = lastBook();
    final stops = (body['stops'] as List).cast<Map>();
    expect(stops, hasLength(1));
    expect(stops.first['address'], 'Kalavad Road, Rajkot');
    expect(stops.first['lat'], 22.28);
    expect(stops.first['lng'], 70.76);
    expect(body['bookingFor'], 'self');
    expect(body.containsKey('passengerName'), isFalse);
    await teardown(tester);
  });

  testWidgets('a stop search with no results says so', (tester) async {
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Add stop'));
      await advance(tester, const Duration(milliseconds: 300));
      await tester.enterText(stopField(), 'zzzqqq');
      await advance(tester, const Duration(milliseconds: 800));
    });
    expect(find.textContaining('No places found'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('"Booking for: Someone else" sends the passenger name and phone', (tester) async {
    await open(tester);
    await act(() async {
      await pickDrop(tester);
      await toConfirm(tester, beforeConfirm: () async {
        expect(find.text('Myself'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('booking-for-chip')));
        await advance(tester, const Duration(milliseconds: 600));
        await tester.tap(find.byKey(const ValueKey('booking-for-other')));
        await advance(tester, const Duration(milliseconds: 300));
        await tester.enterText(find.byKey(const ValueKey('passenger-name')), 'Asha Patel');
        await tester.enterText(find.byKey(const ValueKey('passenger-phone')), '+91 98250 12345');
        await tester.tap(find.byKey(const ValueKey('booking-for-done')));
        await advance(tester, const Duration(milliseconds: 600));
        expect(find.text('Asha Patel'), findsOneWidget);
      });
    });
    final body = lastBook();
    expect(body['bookingFor'], 'other');
    expect(body['passengerName'], 'Asha Patel');
    expect(body['passengerPhone'], '9825012345');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('recent_passengers_v1'), contains('Asha Patel'));
    await teardown(tester);
  });

  testWidgets('the sheet refuses an invalid passenger number', (tester) async {
    await open(tester);
    await act(() async {
      await pickDrop(tester);
      await tester.tap(find.text('Confirm Location'));
      await advance(tester, const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('booking-for-chip')));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('booking-for-other')));
      await advance(tester, const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const ValueKey('passenger-name')), 'Asha');
      await tester.enterText(find.byKey(const ValueKey('passenger-phone')), '12345');
      await tester.tap(find.byKey(const ValueKey('booking-for-done')));
      await advance(tester, const Duration(milliseconds: 300));
    });
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('the server refusing the passenger is explained, not a raw error', (tester) async {
    await open(tester);
    final base = server.client;
    await http.runWithClient(() async {
      await pickDrop(tester);
      await toConfirm(tester);
    }, () => MockClient((req) async {
      if (req.url.path.endsWith('/rides/book')) {
        return http.Response(jsonEncode({'error': 'x', 'code': 'PASSENGER_IS_RIDER'}), 400);
      }
      final copy = http.Request(req.method, req.url)
        ..headers.addAll(req.headers)
        ..bodyBytes = req.bodyBytes;
      return base.send(copy).then(http.Response.fromStream);
    }));
    expect(find.textContaining('passenger number is your own'), findsOneWidget);
    await teardown(tester);
  });
}
