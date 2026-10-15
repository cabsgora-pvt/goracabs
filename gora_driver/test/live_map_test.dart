import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// Once the OTP is in, the map leads: the trip details fold away so the drive to
// the destination gets the screen. And for a parcel, the pickup OTP is the
// sender's handover — the parcel is collected there and then, and the map
// heads for the receiver without a second step.
// ─────────────────────────────────────────────────────────────────────────────

bool _folded() =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Show trip details').evaluate().isNotEmpty;

double _mapBottom(WidgetTester tester) => tester.widget<NavMapPanel>(find.byType(NavMapPanel)).bottomInset;

Future<void> _pumpFor(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _startWithOtp(WidgetTester tester) async {
  await shell.act(() async {
    await tester.tap(find.text('Enter OTP to start ride'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text('Start'));
    await _pumpFor(tester, 1500);
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  Future<http.Response?> server(http.Request req, {bool collectFails = false}) async {
    final p = req.url.path;
    if (p.endsWith('/start')) return http.Response('{"success":true}', 200);
    if (p.endsWith('/delivery')) {
      return collectFails
          ? http.Response(jsonEncode({'error': 'No connection to the server'}), 503)
          : http.Response(jsonEncode({'success': true, 'deliveryPhase': 'in_transit'}), 200);
    }
    return null;
  }

  group('the map leads once the trip is under way', () {
    testWidgets('at the pickup the details are open; with the OTP in they fold and the map grows', (tester) async {
      await shell.openScreen(tester, size: const Size(392, 850),
          onRide: shell.ride(service: 'outstation', status: 'arrived'), override: server);
      expect(_folded(), isFalse, reason: 'at the pickup the driver needs the details');
      final before = _mapBottom(tester);
      await _startWithOtp(tester);
      expect(_folded(), isTrue);
      expect(find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label.startsWith('Swipe to')), findsOneWidget,
          reason: 'the next action stays in reach');
      expect(_mapBottom(tester), lessThan(before - 80), reason: 'the sheet shrinks and the map gets the room');
      await shell.teardown(tester);
    });

    testWidgets('the handle opens the details again', (tester) async {
      await shell.openScreen(tester, onRide: shell.ride(service: 'taxi', status: 'ongoing'));
      expect(_folded(), isTrue, reason: 'a trip reopened mid-drive opens map-first');
      await shell.showDetails(tester);
      expect(_folded(), isFalse);
      await shell.teardown(tester);
    });

    testWidgets('before the trip starts, nothing is folded', (tester) async {
      await shell.openScreen(tester, onRide: shell.ride(service: 'taxi', status: 'accepted'));
      expect(_folded(), isFalse);
      await shell.teardown(tester);
    });
  });

  group('a parcel is collected with the pickup OTP', () {
    testWidgets('the OTP marks it collected and the map heads for the receiver', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, onRide: shell.ride(service: 'delivery', status: 'arrived'), log: log,
          override: server);
      await _startWithOtp(tester);
      await _pumpFor(tester, 800);
      expect(find.byType(DeliveryProgressPage), findsOneWidget);
      expect(shell.posts(log, '/delivery').single.body['action'], 'collected');
      expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).leg.label, 'Receiver');
      expect(find.text('PARCEL · TO RECEIVER'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Swipe once parcel is collected'),
          findsNothing, reason: 'no second step');
      expect(_folded(), isTrue, reason: 'on the way to the receiver, the map leads');
      await shell.teardown(tester);
    });

    testWidgets('if marking it collected fails, the driver is told and can swipe to retry', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, onRide: shell.ride(service: 'delivery', status: 'arrived'), log: log,
          override: (req) => server(req, collectFails: true));
      await _startWithOtp(tester);
      await _pumpFor(tester, 800);
      expect(find.text('Could not mark collected: No connection to the server'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Swipe once parcel is collected'),
          findsOneWidget);
      expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).leg.label, 'Pickup');
      // Standing at the sender, having just taken the OTP: nothing to be told.
      tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onArrived!();
      await _pumpFor(tester, 400);
      expect(find.text('You have reached the sender — collect the parcel'), findsNothing);
      await shell.teardown(tester);
    });

    testWidgets('a parcel reopened at the sender is not collected behind the driver\'s back', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, page: DeliveryProgressPage(ride: shell.ride(service: 'delivery', status: 'ongoing')),
          log: log, override: server);
      await _pumpFor(tester, 800);
      expect(shell.posts(log, '/delivery'), isEmpty, reason: 'only straight after the OTP');
      expect(find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Swipe once parcel is collected'),
          findsOneWidget);
      await shell.teardown(tester);
    });
  });
}
