import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/taxi_booking_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/vehicle_marker.dart';
import 'package:customer_app/screens/active_ride_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The taxi booking flow end to end, against canned API answers:
// choose → confirm pickup → confirm ride → handed to the live ride screen.
//
// Tracking, payment and "no driver found" are the live ride screen's job
// (test/active_ride_screen_test.dart), as for every other service.
// ─────────────────────────────────────────────────────────────────────────────

const kPhone = Size(400, 860);

/// Mutable server state the test moves through the ride's phases.
class FakeServer {
  String status = 'pending';
  // Set with status 'cancelled' to model the server's own close.
  String? cancelledBy;
  String? cancellationReason;
  Map<String, dynamic>? driverAt = {'lat': 23.0400, 'lng': 72.5900, 'heading': 45};
  bool directionsFail = false;
  bool refuseCancel = false;
  int booked = 0;
  // Merged into every /rides/{id} answer (payment fields, say).
  Map<String, dynamic> extra = {};
  final requests = <http.Request>[];
  final cancels = <String>[];
  String get rideId => 'ride$booked';

  MockClient get client => MockClient((req) async {
    requests.add(req);
    final p = req.url.path;
    if (p.endsWith('/fare/estimate')) {
      return http.Response(jsonEncode({
        'available': true,
        'distance': 6.2,
        'duration': 14,
        'vehicles': [
          {'name': 'Bike', 'fare': 120, 'etaMin': 3, 'capacity': 1, 'quoteToken': 'q1'},
        ],
      }), 200);
    }
    if (p.endsWith('/rides/book')) {
      booked++;
      status = 'pending';
      return http.Response(jsonEncode({'ride': {'id': rideId, 'otp': '4821'}}), 200);
    }
    if (p.endsWith('/cancel')) {
      if (refuseCancel) return http.Response(jsonEncode({'error': 'Ride already started'}), 400);
      cancels.add(p);
      status = 'cancelled';
      return http.Response(jsonEncode({'success': true}), 200);
    }
    if (p.endsWith('/driver-location')) {
      return http.Response(jsonEncode({
        'status': status,
        'driver': status == 'pending' ? null : driverAt,
      }), 200);
    }
    if (p.endsWith('/directions')) {
      if (directionsFail) return http.Response('{"error":"no route"}', 500);
      return http.Response(jsonEncode({
        'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'durationMin': 7,
        'distanceKm': 2.4,
      }), 200);
    }
    if (p.endsWith('/rides/$rideId')) {
      return http.Response(jsonEncode({
        '_id': rideId,
        'status': status,
        'otp': '4821',
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null) 'cancellationReason': cancellationReason,
        'service': 'taxi', 'vehicleType': 'Bike', 'fare': 120,
        ...extra,
        if (status != 'pending') 'driverName': 'Ramesh Patel',
        if (status != 'pending') 'driverPhone': '+919876543210',
        if (status != 'pending')
          'driver': {'vehicleModel': 'Hero Splendor', 'vehicleNumber': 'GJ01AB1234', 'rating': 4.8,
              'totalRides': 52, 'vehicleTypeName': 'Bike'},
      }), 200);
    }
    if (p.endsWith('/places/autocomplete')) {
      final q = req.url.queryParameters['q'] ?? '';
      if (q.contains('zzz')) return http.Response(jsonEncode({'predictions': []}), 200);
      if (q.contains('Kal')) {
        return http.Response(jsonEncode({'predictions': [
          {'placeId': 'p2', 'description': 'Kalavad Road, Rajkot', 'mainText': 'Kalavad Road', 'secondaryText': 'Rajkot'},
        ]}), 200);
      }
      return http.Response(jsonEncode({'predictions': [
        {'placeId': 'p1', 'description': 'Race Course, Sadar, Rajkot', 'mainText': 'Race Course', 'secondaryText': 'Sadar, Rajkot'},
      ]}), 200);
    }
    if (p.endsWith('/places/details')) {
      if (req.url.queryParameters['placeId'] == 'p2') {
        return http.Response(jsonEncode({'lat': 22.2800, 'lng': 70.7600, 'address': 'Kalavad Road, Rajkot'}), 200);
      }
      return http.Response(jsonEncode({'lat': 22.3000, 'lng': 70.7900, 'address': 'Race Course, Sadar, Rajkot'}), 200);
    }
    if (p.endsWith('/rides/nearby-drivers')) {
      return http.Response(jsonEncode({'drivers': []}), 200);
    }
    return http.Response('{}', 200);
  });
}

late FakeServer server;
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => server.client);

Widget app() => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: const TaxiBookingScreen(
      fromLocation: 'Navrangpura', toLocation: 'Bodakdev',
      hideLocationInputs: true, preselectedVehicle: 'Bike'),
  ),
);

Future<void> advance(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the screen and books a Bike, leaving the rider on the live ride screen.
Future<void> bookToRide(WidgetTester tester) async {
  tester.view.physicalSize = kPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => VehicleMarkers.descriptorFor('Bike'));
  await act(() async {
    await tester.pumpWidget(app());
    await advance(tester, const Duration(seconds: 1));
    // GPS is off in the test; its snackbar would cover the button.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await advance(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Choose Bike'));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Confirm Pickup'));
    await advance(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Confirm Ride'));
    await advance(tester, const Duration(seconds: 1));
  });
  expect(find.byType(ActiveRideScreen), findsOneWidget);
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  while (tester.takeException() != null) {}
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() {
    server = FakeServer();
    SharedPreferences.setMockInitialValues({'token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  // The taxi screen books and hands over: the ride is tracked — and paid — on
  // the live ride screen like every other service. It used to track the ride
  // in its own sheets and charge it at completion itself (_payableFare), a
  // second payment path that could charge a ride the server had already
  // settled.
  testWidgets('booking hands the ride to the live ride screen', (tester) async {
    await bookToRide(tester);
    expect(find.byType(ActiveRideScreen), findsOneWidget);
    expect(tester.widget<ActiveRideScreen>(find.byType(ActiveRideScreen)).rideId, 'ride1');
    expect(tester.widget<ActiveRideScreen>(find.byType(ActiveRideScreen)).rebook, isNotNull,
        reason: '"Try again" after no driver can re-book this trip');
    expect(find.byType(TaxiBookingScreen, skipOffstage: false), findsNothing, reason: 'replaced, not stacked');
    await teardown(tester);
  });

  testWidgets('the booking carries a clientRequestId, the full quoted fare and only the coupon code', (tester) async {
    await bookToRide(tester);
    final body = jsonDecode(server.requests.lastWhere((r) => r.url.path.endsWith('/rides/book')).body) as Map;
    expect(body['clientRequestId'], isA<String>());
    expect((body['clientRequestId'] as String).length, greaterThan(20));
    expect(body['fare'], 120);
    expect(body['quoteToken'], 'q1');
    expect(body.containsKey('couponDiscount'), isFalse);
    expect(body['tip'], inInclusiveRange(0, 500));
    await teardown(tester);
  });

  testWidgets('a completed wallet ride is never charged from the phone', (tester) async {
    await bookToRide(tester);
    server.status = 'completed';
    server.extra = {'paymentMode': 'wallet', 'paymentStatus': 'paid', 'riderWalletDebit': 120, 'amountDue': 120};
    await act(() => advance(tester, const Duration(seconds: 8)));
    expect(server.requests.where((r) => r.url.path.endsWith('/wallet/pay')), isEmpty);
    expect(server.requests.where((r) => r.url.path.endsWith('/complete')), isEmpty);
    expect(server.requests.where((r) => r.url.path.contains('/payment/')), isEmpty);
    await teardown(tester);
  });

  testWidgets('confirm pickup shows the green pin it asks the rider to drag', (tester) async {
    tester.view.physicalSize = kPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await act(() async {
      await tester.pumpWidget(app());
      await advance(tester, const Duration(seconds: 1));
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await advance(tester, const Duration(milliseconds: 300));
      await tester.tap(find.text('Choose Bike'));
      await advance(tester, const Duration(milliseconds: 600));
    });
    expect(find.textContaining('green pin'), findsOneWidget);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
    final pickup = map.markers.firstWhere((m) => m.markerId.value == 'pickup');
    // The default pin in green (serialised as ['defaultMarker', hue]).
    expect(pickup.icon.toJson(), ['defaultMarker', BitmapDescriptor.hueGreen]);
    expect(pickup.draggable, isTrue);
    // Above the nearby vehicles and the drop.
    for (final m in map.markers.where((m) => m.markerId.value != 'pickup')) {
      expect(pickup.zIndexInt, greaterThan(m.zIndexInt));
    }
    await teardown(tester);
  });

  group('destination search', () {
    Widget search() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = kPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await act(() async {
        await tester.pumpWidget(search());
        await advance(tester, const Duration(seconds: 1));
      });
    }

    Finder dropField() => find.widgetWithText(TextField, 'Where to?');

    testWidgets('picking a suggestion leaves no stuck "Searching…"', (tester) async {
      await open(tester);
      await act(() async {
        await tester.enterText(dropField(), 'Race');
        await tester.pump();
        expect(find.text('Searching…'), findsOneWidget);
        await advance(tester, const Duration(milliseconds: 600));
        expect(find.text('Race Course'), findsOneWidget);
        await tester.tap(find.text('Race Course'));
        await advance(tester, const Duration(milliseconds: 600));
      });
      expect(find.textContaining('Searching'), findsNothing);
      expect(find.textContaining('No places found'), findsNothing);
      await teardown(tester);
    });

    testWidgets('a search with no results says so instead of searching forever', (tester) async {
      await open(tester);
      await act(() async {
        await tester.enterText(dropField(), 'zzzqqq');
        await advance(tester, const Duration(milliseconds: 800));
      });
      expect(find.textContaining('Searching'), findsNothing);
      expect(find.textContaining('No places found'), findsOneWidget);
      await teardown(tester);
    });
  });

  // The pickup field used to have no search: typing changed only its text and
  // the ride was still booked at the phone's GPS point.
  group('pickup search', () {
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
      tester.view.physicalSize = kPhone;
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

    Finder pickupField() => find.byType(TextField).first;
    Finder dropField() => find.widgetWithText(TextField, 'Where to?');

    Future<void> pickDrop(WidgetTester tester) async {
      await tester.enterText(dropField(), 'Race');
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text('Race Course'));
      await advance(tester, const Duration(milliseconds: 600));
    }

    Future<Map<String, dynamic>> bookAndReadBody(WidgetTester tester) async {
      await tester.tap(find.text('Confirm Location'));
      await advance(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Choose Bike'));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text('Confirm Pickup'));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text('Confirm Ride'));
      await advance(tester, const Duration(seconds: 1));
      final book = server.requests.lastWhere((r) => r.url.path.endsWith('/rides/book'));
      return jsonDecode(book.body) as Map<String, dynamic>;
    }

    testWidgets('typing a pickup shows Google suggestions and the ride is booked there', (tester) async {
      await open(tester);
      late Map<String, dynamic> body;
      await act(() async {
        await tester.enterText(pickupField(), 'Kalavad');
        await tester.pump();
        expect(find.text('Use current location'), findsOneWidget);
        await advance(tester, const Duration(milliseconds: 600));
        expect(find.text('Kalavad Road'), findsOneWidget);
        await tester.tap(find.text('Kalavad Road'));
        await advance(tester, const Duration(milliseconds: 600));
        expect(find.text('Use current location'), findsNothing);
        await pickDrop(tester);
        body = await bookAndReadBody(tester);
      });
      expect(body['pickupLat'], 22.28);
      expect(body['pickupLng'], 70.76);
      expect(body['pickupAddress'], 'Kalavad Road, Rajkot');
      expect(body['dropLat'], 22.3);
      await teardown(tester);
    });

    testWidgets('a typed pickup not picked from the list is resolved on Confirm, not left at GPS', (tester) async {
      await open(tester);
      late Map<String, dynamic> body;
      await act(() async {
        await tester.enterText(pickupField(), 'Kalavad');
        await advance(tester, const Duration(milliseconds: 600));
        await pickDrop(tester);
        body = await bookAndReadBody(tester);
      });
      expect(body['pickupLat'], 22.28);
      expect(body['pickupAddress'], 'Kalavad Road, Rajkot');
      await teardown(tester);
    });

    testWidgets('a pickup with no match stops at Confirm instead of booking at GPS', (tester) async {
      await open(tester);
      await act(() async {
        await tester.enterText(pickupField(), 'zzzqqq');
        await advance(tester, const Duration(milliseconds: 600));
        await pickDrop(tester);
        await tester.tap(find.text('Confirm Location'));
        await advance(tester, const Duration(seconds: 1));
      });
      expect(find.textContaining("Couldn't find that pickup"), findsOneWidget);
      expect(find.text('Choose Bike'), findsNothing);
      expect(server.requests.where((r) => r.url.path.endsWith('/rides/book')), isEmpty);
      await teardown(tester);
    });
  });
}
