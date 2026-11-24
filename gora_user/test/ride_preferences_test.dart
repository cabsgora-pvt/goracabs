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
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/screens/taxi_booking_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/vehicle_marker.dart';
import 'package:customer_app/screens/active_ride_screen.dart';
import 'package:customer_app/widgets/ride_preferences.dart';

// Admin-defined ride preferences (GET /ride-preferences): only the ones for the
// screen's service are offered, as multi-select chips, and the picked keys go
// to /rides/book as `preferences`. No preferences → no section at all.

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

const _allPrefs = [
  {'id': '1', 'key': 'pet_friendly', 'name': 'Pet friendly', 'description': 'Travelling with a pet', 'icon': 'pets',
    'services': ['taxi', 'rental', 'outstation']},
  {'id': '2', 'key': 'extra_luggage', 'name': 'Extra luggage', 'description': '', 'icon': 'luggage',
    'services': ['taxi', 'outstation']},
  {'id': '3', 'key': 'wheelchair', 'name': 'Wheelchair access', 'description': '', 'icon': 'accessible',
    'services': ['rental']},
  {'id': '4', 'key': 'parcel_only', 'name': 'Fragile parcel', 'description': '', 'icon': 'whatever',
    'services': ['delivery']},
];

List<Map<String, dynamic>> prefs = [];
final requests = <http.Request>[];

Future<http.Response> _handle(http.Request req) async {
  requests.add(req);
  final p = req.url.path;
  if (p.endsWith('/ride-preferences')) return _json({'preferences': prefs});
  // taxi
  if (p.endsWith('/fare/estimate') && !req.body.contains('outstation')) {
    return _json({'available': true, 'distance': 6.2, 'duration': 14, 'vehicles': [
      {'name': 'Bike', 'fare': 120, 'etaMin': 3, 'capacity': 1, 'quoteToken': 'q1'},
    ]});
  }
  if (p.endsWith('/rides/book')) return _json({'ride': {'id': 'ride1', 'otp': '4821'}});
  if (p.endsWith('/rides/ride1') || p.endsWith('/driver-location')) {
    return _json({'_id': 'ride1', 'status': 'pending', 'service': 'taxi', 'uiPhase': 'finding',
      'pickupLat': 23.02, 'pickupLng': 72.57, 'dropLat': 23.07, 'dropLng': 72.62, 'fare': 600});
  }
  // rental
  if (p.endsWith('/places/reverse')) return _json({'address': 'Sadar, Rajkot'});
  if (p.endsWith('/rental/packages')) {
    return _json({'available': true, 'packages': [
      {'vehicleTypeName': 'Cab', 'hours': 4, 'km': 40, 'basePrice': 848, 'capacity': 4,
        'extraHourRate': 180, 'extraKmRate': 14, 'imageUrl': ''},
    ]});
  }
  // outstation
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'hawa', 'description': 'Hawa Mahal Road, Jaipur, Rajasthan', 'mainText': 'Hawa Mahal',
        'secondaryText': 'Jaipur, Rajasthan'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 26.9239, 'lng': 75.8267, 'address': 'Hawa Mahal Road, Jaipur, Rajasthan'});
  if (p.endsWith('/payment/config')) return _json({'razorpay': {'enabled': false}, 'walletEnabled': true});
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 268, 'oneWayMin': 310, 'vehicles': [
      {'name': 'SUV', 'capacity': 6, 'fare': 5400, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-SUV',
        'breakdown': {'base': 5400, 'nightHalt': 0, 'emptyReturn': 0}},
    ]});
  }
  return _json({});
}

final _api = MockClient(_handle);
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => _api);

Widget _app(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: home),
);

Future<void> wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester tester, [Size s = const Size(400, 860)]) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  while (tester.takeException() != null) {}
}

Map<String, dynamic> _bookBody() =>
    jsonDecode(requests.lastWhere((r) => r.url.path.endsWith('/rides/book')).body) as Map<String, dynamic>;

void _gps({required bool on}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
    if (!on) return call.method == 'isLocationServiceEnabled' ? false : null;
    switch (call.method) {
      case 'isLocationServiceEnabled': return true;
      case 'checkPermission':
      case 'requestPermission': return 3;
      case 'getCurrentPosition':
      case 'getLastKnownPosition':
        return <String, dynamic>{
          'latitude': 28.4950, 'longitude': 77.0895, 'accuracy': 5.0, 'altitude': 0.0, 'heading': 0.0,
          'speed': 0.0, 'speed_accuracy': 1.0, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'is_mocked': false,
        };
    }
    return null;
  });
}

void main() {
  setUp(() {
    prefs = _allPrefs.map((e) => Map<String, dynamic>.from(e)).toList();
    requests.clear();
    SharedPreferences.setMockInitialValues({'token': 't'});
    _gps(on: false);
  });

  group('helpers', () {
    test('icon names map to Material icons; unknown is a star', () {
      expect(ridePreferenceIcon('pets'), Icons.pets_rounded);
      expect(ridePreferenceIcon('luggage'), Icons.luggage_rounded);
      expect(ridePreferenceIcon('accessible'), Icons.accessible_rounded);
      expect(ridePreferenceIcon('ac_unit'), Icons.ac_unit_rounded);
      expect(ridePreferenceIcon('smoke_free'), Icons.smoke_free_rounded);
      expect(ridePreferenceIcon('child_care'), Icons.child_care_rounded);
      expect(ridePreferenceIcon('music_note'), Icons.music_note_rounded);
      expect(ridePreferenceIcon('star'), Icons.star_rounded);
      expect(ridePreferenceIcon('rocket'), Icons.star_rounded);
    });

    test('loadRidePreferences keeps the ones for the service', () async {
      await act(() async {
        expect((await loadRidePreferences('taxi')).map((p) => p.key), ['pet_friendly', 'extra_luggage']);
        expect((await loadRidePreferences('rental')).map((p) => p.key), ['pet_friendly', 'wheelchair']);
        expect((await loadRidePreferences('delivery')).map((p) => p.key), ['parcel_only']);
      });
    });

    test('a failed load is an empty list, never a throw', () async {
      await http.runWithClient(() async {
        expect(await loadRidePreferences('taxi'), isEmpty);
      }, () => MockClient((_) async => http.Response('<html>502</html>', 502)));
    });
  });

  group('taxi Confirm ride sheet', () {
    Future<void> toConfirmSheet(WidgetTester tester) async {
      _size(tester);
      await tester.runAsync(() => VehicleMarkers.descriptorFor('Bike'));
      await tester.pumpWidget(_app(const TaxiBookingScreen(
          fromLocation: 'Navrangpura', toLocation: 'Bodakdev', hideLocationInputs: true, preselectedVehicle: 'Bike')));
      await wait(tester, 1000);
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await wait(tester, 300);
      await tester.tap(find.text('Choose Bike'));
      await wait(tester, 600);
      await tester.tap(find.text('Confirm Pickup'));
      await wait(tester, 600);
      expect(find.text('Confirm your ride'), findsOneWidget);
    }

    testWidgets('shows only taxi preferences; the picked keys are booked', (tester) async {
      await act(() async {
        await toConfirmSheet(tester);
        expect(find.text('Ride preferences'), findsOneWidget);
        expect(find.text('Pet friendly'), findsOneWidget);
        expect(find.text('Extra luggage'), findsOneWidget);
        expect(find.text('Wheelchair access'), findsNothing, reason: 'rental only');
        expect(find.text('Fragile parcel'), findsNothing, reason: 'delivery only');
        expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
        await tester.ensureVisible(find.text('Pet friendly'));
        await tester.tap(find.text('Pet friendly'));
        await tester.pump();
        await tester.tap(find.text('Extra luggage'));
        await tester.pump();
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
        // Multi-select; tapping again deselects.
        await tester.tap(find.text('Extra luggage'));
        await tester.pump();
        expect(find.text('Pet friendly: Travelling with a pet'), findsOneWidget);
        await tester.ensureVisible(find.text('Confirm Ride'));
        await tester.tap(find.text('Confirm Ride'));
        await wait(tester, 1000);
      });
      final body = _bookBody();
      expect(body['preferences'], ['pet_friendly']);
      expect(body['preferFemaleDriver'], false);
      // Tracked on the live ride screen, like every service.
      expect(find.byType(ActiveRideScreen), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('nothing picked → no preferences key', (tester) async {
      await act(() async {
        await toConfirmSheet(tester);
        await tester.ensureVisible(find.text('Confirm Ride'));
        await tester.tap(find.text('Confirm Ride'));
        await wait(tester, 1000);
      });
      expect(_bookBody().containsKey('preferences'), isFalse);
      await _teardown(tester);
    });

    testWidgets('no preferences for taxi → the section is hidden', (tester) async {
      prefs = [_allPrefs[2], _allPrefs[3]].map((e) => Map<String, dynamic>.from(e)).toList();
      await act(() async {
        await toConfirmSheet(tester);
      });
      expect(find.text('Ride preferences'), findsNothing);
      expect(find.text('Prefer a female driver'), findsOneWidget);
      await _teardown(tester);
    });
  });

  testWidgets('rental offers its own preferences and books the picked ones', (tester) async {
    _gps(on: true);
    _size(tester, const Size(392, 850));
    await act(() async {
      await tester.pumpWidget(_app(const RentalScreen()));
      await wait(tester, 1000);
      await tester.scrollUntilVisible(find.text('Wheelchair access'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Ride preferences'), findsOneWidget);
      expect(find.text('Pet friendly'), findsOneWidget);
      expect(find.text('Extra luggage'), findsNothing, reason: 'not offered for rentals');
      await tester.tap(find.text('Wheelchair access'));
      await wait(tester, 200);
      await tester.scrollUntilVisible(find.text('Cab'), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Cab'));
      await wait(tester, 200);
      await tester.tap(find.text('Book Package · ₹848'));
      await wait(tester, 600);
      await tester.ensureVisible(find.text('Confirm Booking'));
      await tester.tap(find.text('Confirm Booking'));
      await wait(tester, 1000);
    });
    final body = _bookBody();
    expect(body['service'], 'rental');
    expect(body['preferences'], ['wheelchair']);
    await _teardown(tester);
  });

  testWidgets('outstation offers its own preferences and books the picked ones', (tester) async {
    _gps(on: true);
    _size(tester, const Size(392, 850));
    await act(() async {
      await tester.pumpWidget(_app(const OutstationScreen()));
      await wait(tester, 800);
      await tester.enterText(find.byType(TextField).at(1), 'Hawa Mahal');
      await wait(tester, 800);
      await tester.tap(find.widgetWithText(ListTile, 'Hawa Mahal'));
      await wait(tester, 400);
      await tester.tap(find.text('Confirm Location'));
      await wait(tester, 1500);
      await tester.drag(find.text('Trip Details'), const Offset(0, -520), warnIfMissed: false);
      await wait(tester, 600);
      final list = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
      await tester.ensureVisible(find.text('Select Vehicle'));
      await tester.tap(find.text('Select Vehicle'));
      await wait(tester, 500);
      await tester.scrollUntilVisible(find.text('₹5400'), 150, scrollable: list);
      await wait(tester, 300);
      await tester.tap(find.text('₹5400').first);
      await wait(tester, 500);
      await tester.scrollUntilVisible(find.text('Extra luggage'), 150, scrollable: list);
      await wait(tester, 300);
      expect(find.text('Pet friendly'), findsOneWidget);
      expect(find.text('Wheelchair access'), findsNothing, reason: 'not offered for outstation');
      await tester.tap(find.text('Extra luggage'));
      await wait(tester, 200);
      await tester.tap(find.text('Book Trip'));
      await wait(tester, 800);
      await tester.tap(find.text('Confirm Booking'));
      await wait(tester, 1500);
    });
    final body = _bookBody();
    expect(body['service'], 'outstation');
    expect(body['preferences'], ['extra_luggage']);
    await _teardown(tester);
  });
}
