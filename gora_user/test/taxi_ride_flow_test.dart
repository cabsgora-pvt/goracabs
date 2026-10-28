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
import 'package:customer_app/widgets/finding_driver_view.dart';
import 'package:customer_app/widgets/cancel_reasons_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The taxi booking flow end to end, against canned API answers:
// choose → confirm pickup → confirm ride → finding → driver on the way →
// trip under way → completed.
//
// On a real device the full-screen "Finding your ride" view stayed up under the
// driver sheet for the whole trip, and came back behind "Ride Completed!".
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
        if (status != 'pending') 'driverName': 'Ramesh Patel',
        if (status != 'pending') 'driverPhone': '+919876543210',
        if (status != 'pending')
          'driver': {'vehicleModel': 'Hero Splendor', 'vehicleNumber': 'GJ01AB1234', 'rating': 4.8},
      }), 200);
    }
    if (p.endsWith('/places/autocomplete')) {
      final q = req.url.queryParameters['q'] ?? '';
      if (q.contains('zzz')) return http.Response(jsonEncode({'predictions': []}), 200);
      return http.Response(jsonEncode({'predictions': [
        {'placeId': 'p1', 'description': 'Race Course, Sadar, Rajkot', 'mainText': 'Race Course', 'secondaryText': 'Sadar, Rajkot'},
      ]}), 200);
    }
    if (p.endsWith('/places/details')) {
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

/// Opens the screen and books a Bike, leaving the rider on the finding view.
Future<void> bookToFinding(WidgetTester tester) async {
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
  expect(find.byType(FindingDriverView), findsOneWidget);
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

  testWidgets('finding view is removed once a driver accepts, and stays gone', (tester) async {
    await bookToFinding(tester);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 8)));
    expect(find.byType(FindingDriverView), findsNothing);
    expect(find.text('Meet at the pickup point'), findsOneWidget);
    // Only one driver sheet, not one per poll.
    expect(find.text('Ramesh Patel'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('a sheet opened over the finding view does not keep it alive on accept', (tester) async {
    await bookToFinding(tester);
    // The rider opens the cancel reasons, then the driver accepts.
    await act(() async {
      await tester.tap(find.text('Cancel Ride'));
      await advance(tester, const Duration(milliseconds: 600));
    });
    expect(find.text('Confirm Cancellation'), findsOneWidget);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 8)));
    expect(find.byType(FindingDriverView), findsNothing);
    await teardown(tester);
  });

  testWidgets('under way: PIN and cancel are hidden and the route is drawn', (tester) async {
    await bookToFinding(tester);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 6)));
    expect(find.text('Cancel Ride'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    server.status = 'ongoing';
    await act(() => advance(tester, const Duration(seconds: 6)));
    expect(find.text('Cancel Ride'), findsNothing);
    expect(find.text('4821'), findsNothing);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
    expect(map.polylines, isNotEmpty);
    await teardown(tester);
  });

  testWidgets('completion shows the summary with no searching view behind it', (tester) async {
    await bookToFinding(tester);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 6)));
    server.status = 'ongoing';
    await act(() => advance(tester, const Duration(seconds: 6)));
    server.status = 'completed';
    await act(() => advance(tester, const Duration(seconds: 6)));
    expect(find.text('Ride Completed!'), findsOneWidget);
    expect(find.text('Looking for nearby drivers'), findsNothing);
    expect(find.byType(FindingDriverView), findsNothing);
    // A clean base: no booking sheet and no planned route under the summary.
    expect(find.text('Confirm pickup'), findsNothing);
    expect(find.text('Confirm Pickup'), findsNothing);
    expect(find.text('Choose Bike'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
    expect(map.polylines, isEmpty);
    await teardown(tester);
  });

  group('cancelling from the finding view', () {
    Future<void> cancelFromFinding(WidgetTester tester) async {
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await advance(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text('Plan changed'));
        await advance(tester, const Duration(milliseconds: 200));
        await tester.tap(find.text('Confirm Cancellation'));
        await advance(tester, const Duration(seconds: 1));
      });
    }

    testWidgets('closes every booking sheet, stops polling, back to choosing a vehicle', (tester) async {
      await bookToFinding(tester);
      await cancelFromFinding(tester);
      expect(server.cancels, hasLength(1));
      expect(find.byType(FindingDriverView), findsNothing);
      expect(find.text('Confirm Cancellation'), findsNothing);
      expect(find.text('Confirm pickup'), findsNothing, reason: 'not left on the pickup step');
      expect(find.text('Choose Bike'), findsOneWidget);
      // Polling stopped: no more requests for the cancelled ride.
      final before = server.requests.where((r) => r.url.path.endsWith('/rides/ride1')).length;
      await act(() => advance(tester, const Duration(seconds: 8)));
      final after = server.requests.where((r) => r.url.path.endsWith('/rides/ride1')).length;
      expect(after, before);
      await teardown(tester);
    });

    testWidgets('a cancel the server refuses keeps the ride on screen', (tester) async {
      await bookToFinding(tester);
      server.refuseCancel = true;
      await cancelFromFinding(tester);
      expect(find.textContaining('Could not cancel'), findsWidgets);
      expect(find.text('Confirm Cancellation'), findsNothing);
      expect(find.byType(FindingDriverView), findsOneWidget);
      // Still tracked: an accept now moves on to the driver.
      server.status = 'accepted';
      await act(() => advance(tester, const Duration(seconds: 6)));
      expect(find.text('Meet at the pickup point'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a ride cancelled on the server closes the finding view', (tester) async {
      await bookToFinding(tester);
      server.status = 'cancelled';
      await act(() => advance(tester, const Duration(seconds: 5)));
      expect(find.byType(FindingDriverView), findsNothing);
      expect(find.text('Choose Bike'), findsOneWidget);
      await teardown(tester);
    });

    // The server closes a ride nobody took (cancelledBy 'system', reason
    // 'No driver found'). The app has no timer of its own: it only reacts.
    group('no driver found', () {
      void serverCloses() {
        server.status = 'cancelled';
        server.cancelledBy = 'system';
        server.cancellationReason = 'No driver found';
      }

      testWidgets('closes the finding view, says so, stops polling; Try again → vehicle list', (tester) async {
        await bookToFinding(tester);
        // Still searching while the server says pending — however long it takes.
        await act(() => advance(tester, const Duration(seconds: 10)));
        expect(find.byType(FindingDriverView), findsOneWidget);
        expect(find.text('No driver found'), findsNothing);

        serverCloses();
        await act(() => advance(tester, const Duration(seconds: 4)));
        expect(find.byType(FindingDriverView), findsNothing);
        expect(find.text('No driver found'), findsOneWidget);
        expect(find.text('No drivers available right now. Please try again.'), findsOneWidget);
        expect(find.text('Your ride was cancelled'), findsNothing);

        // Polling stopped: nothing more is asked about the closed ride.
        final before = server.requests.where((r) => r.url.path.endsWith('/rides/${server.rideId}')).length;
        await act(() => advance(tester, const Duration(seconds: 10)));
        final after = server.requests.where((r) => r.url.path.endsWith('/rides/${server.rideId}')).length;
        expect(after, before);
        expect(server.cancels, isEmpty, reason: 'the app never cancels it itself');

        final estimatesBefore = server.requests.where((r) => r.url.path.endsWith('/fare/estimate')).length;
        await act(() async {
          await tester.tap(find.text('Try again'));
          await advance(tester, const Duration(seconds: 1));
        });
        expect(find.text('No driver found'), findsNothing);
        expect(find.text('Choose Bike'), findsOneWidget);
        // Fresh quotes for the retry.
        expect(server.requests.where((r) => r.url.path.endsWith('/fare/estimate')).length, greaterThan(estimatesBefore));
        await teardown(tester);
      });

      testWidgets('after Try again the rider can book again and get a driver', (tester) async {
        await bookToFinding(tester);
        serverCloses();
        await act(() => advance(tester, const Duration(seconds: 4)));
        await act(() async {
          await tester.tap(find.text('Try again'));
          await advance(tester, const Duration(seconds: 1));
          tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
          await advance(tester, const Duration(milliseconds: 400));
          server.cancelledBy = null;
          server.cancellationReason = null;
          await tester.tap(find.text('Choose Bike'));
          await advance(tester, const Duration(milliseconds: 600));
          await tester.tap(find.text('Confirm Pickup'));
          await advance(tester, const Duration(milliseconds: 600));
          await tester.tap(find.text('Confirm Ride'));
          await advance(tester, const Duration(seconds: 1));
        });
        expect(server.booked, 2);
        expect(find.byType(FindingDriverView), findsOneWidget);
        server.status = 'accepted';
        await act(() => advance(tester, const Duration(seconds: 6)));
        expect(find.text('Meet at the pickup point'), findsOneWidget);
        await teardown(tester);
      });

      testWidgets('another system cancel (not "No driver found") keeps the plain message', (tester) async {
        await bookToFinding(tester);
        server.status = 'cancelled';
        server.cancelledBy = 'system';
        server.cancellationReason = 'face_verification_failed';
        await act(() => advance(tester, const Duration(seconds: 4)));
        expect(find.text('No driver found'), findsNothing);
        expect(find.byType(FindingDriverView), findsNothing);
        expect(find.text('Choose Bike'), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('book, cancel, book again: the driver sheet shows on accept', (tester) async {
      await bookToFinding(tester);
      await cancelFromFinding(tester);
      await act(() async {
        tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
        await advance(tester, const Duration(milliseconds: 400));
        await tester.tap(find.text('Choose Bike'));
        await advance(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text('Confirm Pickup'));
        await advance(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text('Confirm Ride'));
        await advance(tester, const Duration(seconds: 1));
      });
      expect(server.booked, 2);
      expect(find.byType(FindingDriverView), findsOneWidget);
      server.status = 'accepted';
      await act(() => advance(tester, const Duration(seconds: 6)));
      expect(find.byType(FindingDriverView), findsNothing);
      expect(find.text('Meet at the pickup point'), findsOneWidget);
      expect(find.text('Ramesh Patel'), findsOneWidget);
      await teardown(tester);
    });
  });

  testWidgets('a driver already at the pickup reads "Arriving now", not a stuck ETA', (tester) async {
    await bookToFinding(tester);
    // Driver standing on the pickup, and directions cannot route 0 m.
    server.driverAt = {'lat': 28.6139, 'lng': 77.2090, 'heading': 0};
    server.directionsFail = true;
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 12)));
    expect(find.textContaining('Calculating ETA'), findsNothing);
    expect(find.textContaining('Arriving now'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('the search chip clears the status bar inside the sheet', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.resetPadding);
    await bookToFinding(tester);
    // A modal sheet strips the top padding from MediaQuery, so SafeArea alone
    // put the chip on the clock.
    expect(tester.getTopLeft(find.text('Ride')).dy, greaterThanOrEqualTo(32));
    await teardown(tester);
  });

  testWidgets('backing out of the cancel reasons keeps the driver sheet', (tester) async {
    await bookToFinding(tester);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 6)));
    await act(() async {
      await tester.tap(find.text('Cancel Ride'));
      await advance(tester, const Duration(milliseconds: 600));
      await tester.tap(find.text("Don't cancel"));
      await advance(tester, const Duration(milliseconds: 600));
    });
    expect(find.text('Meet at the pickup point'), findsOneWidget);
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

  testWidgets('driver position comes from the server, never a hard-coded Delhi point', (tester) async {
    await bookToFinding(tester);
    server.status = 'accepted';
    await act(() => advance(tester, const Duration(seconds: 8)));
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
    final positions = map.markers.map((m) => m.position).toList();
    expect(positions, isNot(contains(const LatLng(28.6220, 77.2150))));
    final driver = map.markers.where((m) => m.markerId.value == 'driver');
    expect(driver, isNotEmpty);
    await teardown(tester);
  });

  group('round 3', () {
    testWidgets('system Back on the driver sheet exposes no booking controls', (tester) async {
      await bookToFinding(tester);
      server.status = 'accepted';
      await act(() => advance(tester, const Duration(seconds: 6)));
      expect(find.text('Meet at the pickup point'), findsOneWidget);
      await act(() async {
        await tester.binding.handlePopRoute(); // the Android back button
        await advance(tester, const Duration(seconds: 1));
      });
      expect(find.text('Meet at the pickup point'), findsOneWidget, reason: 'Back closed the live sheet');
      expect(find.text('Confirm Pickup'), findsNothing);
      expect(find.textContaining('Choose '), findsNothing);
      expect(find.text('Confirm Ride'), findsNothing);
      expect(server.booked, 1);
      await teardown(tester);
    });

    testWidgets('even with the driver sheet gone, a live ride shows no booking controls', (tester) async {
      await bookToFinding(tester);
      server.status = 'accepted';
      await act(() => advance(tester, const Duration(seconds: 6)));
      // Remove the sheet by force (pop ignores PopScope): defence in depth.
      await act(() async {
        Navigator.of(tester.element(find.text('Meet at the pickup point'))).pop();
        await advance(tester, const Duration(seconds: 1));
      });
      expect(find.text('Confirm Pickup'), findsNothing);
      expect(find.text('Confirm pickup'), findsNothing);
      expect(find.textContaining('Choose '), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(server.booked, 1);
      await teardown(tester);
    });

    testWidgets('the search reads "Looking for nearby drivers" under a "Ride" chip', (tester) async {
      await bookToFinding(tester);
      expect(find.text('Looking for nearby drivers'), findsOneWidget);
      expect(find.text('Ride'), findsOneWidget);
      expect(find.text('Finding your ride'), findsNothing);
      await teardown(tester);
    });

    testWidgets('cancel uses the shared sheet: a reason alone does not cancel', (tester) async {
      await bookToFinding(tester);
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await advance(tester, const Duration(milliseconds: 600));
      });
      expect(find.byType(CancelReasonsSheet), findsOneWidget);
      await act(() async {
        await tester.tap(find.text('Plan changed'));
        await advance(tester, const Duration(milliseconds: 600));
      });
      expect(server.cancels, isEmpty);
      expect(find.byType(CancelReasonsSheet), findsOneWidget);
      await act(() async {
        await tester.tap(find.text('Confirm Cancellation'));
        await advance(tester, const Duration(seconds: 1));
      });
      expect(server.cancels, hasLength(1));
      expect(jsonDecode(server.requests.lastWhere((r) => r.url.path.endsWith('/cancel')).body)['reason'], 'Plan changed');
      await teardown(tester);
    });
  });
}
