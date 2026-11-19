import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/logic/trip_end_check.dart';
import 'package:gora_driver/services/ride_alert_service.dart';

import 'ride_shell_test.dart' as shell;

// From live QA: a parcel at its pickup said "Waiting for rider" and "Enter OTP
// to start ride"; an outstation trip could be ended at the pickup, 223 km from
// the drop, with nothing asked; and the in-app and background pollers both hit
// the pending feed every 4 s while the app was on screen.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  group('at the pickup', () {
    testWidgets('a parcel asks for the sender and the pickup PIN', (tester) async {
      await shell.openScreen(tester, onRide: shell.ride(service: 'delivery', status: 'arrived'));
      expect(find.text('Enter pickup PIN'), findsOneWidget);
      expect(find.text('Waiting for sender'), findsOneWidget);
      expect(find.text('Enter OTP to start ride'), findsNothing);
      expect(find.text('Waiting for rider'), findsNothing);
    });

    testWidgets('a taxi still asks for the rider and the OTP', (tester) async {
      await shell.openScreen(tester, onRide: shell.ride(service: 'taxi', status: 'arrived'));
      expect(find.text('Enter OTP to start ride'), findsOneWidget);
      expect(find.text('Waiting for rider'), findsOneWidget);
    });

    testWidgets('the trip length is labelled as the trip, not the way to the rider', (tester) async {
      await shell.openScreen(tester, onRide: shell.ride(service: 'taxi', status: 'accepted'));
      expect(find.textContaining('km trip'), findsOneWidget);
    });
  });

  group('ending an outstation trip', () {
    // shell.ride: pickup 23.0225,72.5714 → drop 23.0732,72.6208 (~7.5 km).
    const atPickup = LatLng(23.0225, 72.5714);
    const atDrop = LatLng(23.0732, 72.6208);
    const farAway = LatLng(24.5926, 72.7156); // Mount Abu, ~175 km

    test('measured to the drop on a one-way trip', () {
      final r = shell.ride(service: 'outstation', status: 'ongoing');
      expect(kmFromTripEnd(r, atDrop)!, lessThan(0.1));
      expect(kmFromTripEnd(r, farAway)!, greaterThan(earlyEndKm));
    });

    test('measured back to the start on a round trip', () {
      final r = shell.ride(service: 'outstation', status: 'ongoing', tripType: 'round_trip');
      expect(kmFromTripEnd(r, atPickup)!, lessThan(0.1));
      expect(kmFromTripEnd(r, farAway)!, greaterThan(earlyEndKm));
    });

    test('nothing to check for other services, or with no fix', () {
      expect(kmFromTripEnd(shell.ride(service: 'taxi', status: 'ongoing'), farAway), isNull);
      expect(kmFromTripEnd(shell.ride(service: 'outstation', status: 'ongoing'), null), isNull);
    });
  });

  group('background poll', () {
    final now = DateTime(2026, 11, 18, 12);

    test('rests while the app has just polled on screen', () {
      expect(appOnScreen(now.subtract(const Duration(seconds: 4)), now), isTrue);
    });

    test('takes over once the heartbeats stop', () {
      expect(appOnScreen(now.subtract(const Duration(seconds: 7)), now), isFalse);
      expect(appOnScreen(null, now), isFalse);
    });
  });
}
