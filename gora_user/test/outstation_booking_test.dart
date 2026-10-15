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
import 'package:customer_app/screens/active_ride_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/ride_service_panels.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Booking an outstation trip through the form, as a rider does: where to, a
// vehicle, confirm — and what reaches the server.
// ─────────────────────────────────────────────────────────────────────────────

const _pickup = 'DLF Cyber City, Sector 24, Gurugram, Haryana 122002';
const _drop = 'Hawa Mahal Road, Badi Choupad, Jaipur, Rajasthan 302002';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

Map<String, dynamic> _vehicle(String name, int cap, int fare) => {
  'name': name, 'capacity': cap, 'fare': fare, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-$name',
  'breakdown': {'base': fare, 'nightHalt': 0, 'emptyReturn': 0},
};

MockClient _server(List<http.Request> booked) => MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/places/reverse')) return _json({'address': _pickup});
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'hawa', 'description': _drop, 'mainText': 'Hawa Mahal', 'secondaryText': 'Badi Choupad, Jaipur, Rajasthan'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 26.9239, 'lng': 75.8267, 'address': _drop});
  if (p.endsWith('/payment/config')) return _json({'razorpay': {'enabled': false}, 'walletEnabled': true});
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 268, 'oneWayMin': 310,
      'vehicles': [_vehicle('Sedan', 4, 4600), _vehicle('SUV', 6, 5400)]});
  }
  if (p.endsWith('/rides/book')) {
    booked.add(req);
    return _json({'ride': {'id': 'r-out-9', 'otp': '4821'}});
  }
  if (p.endsWith('/rides/r-out-9')) {
    return _json({'_id': 'r-out-9', 'service': 'outstation', 'status': 'pending', 'uiPhase': 'finding',
      'pickupAddress': _pickup, 'dropAddress': _drop, 'fare': 5400, 'paymentMode': 'cash',
      'pickupLat': 28.4950, 'pickupLng': 77.0895, 'dropLat': 26.9239, 'dropLng': 75.8267});
  }
  return _json({});
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled': return true;
        case 'checkPermission':
        case 'requestPermission': return 3;   // always
        case 'getCurrentPosition':
        case 'getLastKnownPosition':
          return <String, dynamic>{
            'latitude': 28.4950, 'longitude': 77.0895, 'accuracy': 5.0, 'altitude': 0.0, 'heading': 0.0,
            'speed': 0.0, 'speed_accuracy': 1.0, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'is_mocked': false,
          };
      }
      return null;
    });
  });

  Future<void> wait(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('books the chosen vehicle, labelled with the two towns', (tester) async {
    tester.view.physicalSize = const Size(392, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final booked = <http.Request>[];

    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const OutstationScreen()),
      ));
      await wait(tester, 800);

      await tester.enterText(find.byType(TextField).at(1), 'Hawa Mahal');
      await wait(tester, 800);
      await tester.tap(find.widgetWithText(ListTile, 'Hawa Mahal'));
      await wait(tester, 400);
      await tester.tap(find.text('Confirm Location'));
      await wait(tester, 1500);

      await tester.drag(find.text('Trip Details'), const Offset(0, -520), warnIfMissed: false);
      await wait(tester, 600);
      await tester.ensureVisible(find.text('Select Vehicle'));
      await tester.tap(find.text('Select Vehicle'));
      await wait(tester, 500);
      // The vehicles are further down the sheet's list, not built until reached.
      await tester.scrollUntilVisible(find.text('₹5400'), 150,
          scrollable: find.ancestor(of: find.text('Trip Details'), matching: find.byType(Scrollable)).first);
      await wait(tester, 300);
      await tester.tap(find.text('₹5400').first);
      await wait(tester, 500);

      await tester.tap(find.text('Book Trip'));
      await wait(tester, 800);
      expect(find.textContaining("don't end trip at Jaipur"), findsWidgets);
      expect(find.textContaining("don't end trip at Hawa Mahal"), findsNothing,
          reason: 'the town, not the first part of the street address');
      await tester.tap(find.text('Confirm Booking'));
      await wait(tester, 1500);

      expect(booked, hasLength(1));
      final body = jsonDecode(booked.single.body) as Map<String, dynamic>;
      expect(body['service'], 'outstation');
      expect(body['vehicleType'], 'SUV');
      expect(body['fare'], 5400);
      expect(body['quoteToken'], 'q-SUV');
      expect(body['paymentMode'], 'cash');
      expect(body['pickupAddress'], _pickup);
      expect(body['dropAddress'], _drop);
      expect(body['cityFrom'], 'Gurugram');
      expect(body['cityTo'], 'Jaipur');
      expect(find.byType(ActiveRideScreen), findsOneWidget, reason: 'the trip is tracked on the live ride screen');

      await tester.pumpWidget(const SizedBox.shrink());
      await wait(tester, 1000);
    }, () => _server(booked));
    while (tester.takeException() != null) {}
  });

  // Trips booked before the towns were sent carry the whole addresses.
  testWidgets('the ride panel labels an older trip by its towns too', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OutstationTripPanel(ride: const {
      'cityFrom': _pickup, 'cityTo': _drop, 'tripType': 'one_way', 'status': 'ongoing',
    }))));
    expect(find.text('Gurugram  →  Jaipur'), findsOneWidget);
  });
}
