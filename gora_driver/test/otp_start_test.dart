import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// Starting a trip with the rider's OTP. The dialog disposed its text controller
// the moment it closed, while the field was still animating out — "A
// TextEditingController was used after being disposed" on trip start. Any such
// error fails these tests: the framework reports it to the test.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  Future<http.Response?> server(http.Request req) async {
    if (req.url.path.endsWith('/arrived')) return http.Response('{"success":true,"waitingSec":0}', 200);
    if (req.url.path.endsWith('/start')) return http.Response('{"success":true}', 200);
    return null;
  }

  Future<void> pumpFor(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> typeOtp(WidgetTester tester) async {
    await tester.tap(find.text('Enter OTP to start ride'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '4821');
  }

  void expectOnTrip(WidgetTester tester, List<shell.ApiCall> log) {
    expect(shell.posts(log, '/start').single.body['otp'], '4821');
    expect(find.text('Enter Ride OTP'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label.startsWith('Swipe to')), findsOneWidget,
        reason: 'on the trip: the end swipe is showing');
  }

  for (final service in ['taxi', 'outstation']) {
    testWidgets('$service: Start sends the OTP and starts the trip', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, onRide: shell.ride(service: service, status: 'arrived'), log: log, override: server);
      await shell.act(() async {
        await typeOtp(tester);
        await tester.tap(find.text('Start'));
        await pumpFor(tester, 1000);
      });
      expectOnTrip(tester, log);
      await shell.teardown(tester);
    });
  }

  // The usual way there: the map notices the pickup, the driver swipes, then
  // asks for the OTP. The "swipe Arrived" nudge goes once they have.
  testWidgets('arrived by swipe, then OTP and Start', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: shell.ride(service: 'outstation', status: 'accepted'), log: log, override: server);
    tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onArrived!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('You have reached the pickup — swipe Arrived'), findsOneWidget);
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe when you have arrived');
      await pumpFor(tester, 1200);
      expect(find.text('You have reached the pickup — swipe Arrived'), findsNothing,
          reason: 'done what it asked; not still up as the trip starts');
      await typeOtp(tester);
      await tester.tap(find.text('Start'));
      await pumpFor(tester, 1500);
    });
    expectOnTrip(tester, log);
    await shell.teardown(tester);
  });

  testWidgets('Cancel closes the dialog and starts nothing', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: shell.ride(service: 'taxi', status: 'arrived'), log: log, override: server);
    await shell.act(() async {
      await typeOtp(tester);
      await tester.tap(find.text('Cancel'));
      await pumpFor(tester, 1000);
    });
    expect(shell.posts(log, '/start'), isEmpty);
    expect(find.text('Enter OTP to start ride'), findsOneWidget);
    await shell.teardown(tester);
  });
}
