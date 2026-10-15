import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'active_ride_screen_test.dart' show ApiCall, act, kCommon, pumpRide, rideJson, teardown;

// ─────────────────────────────────────────────────────────────────────────────
// Coming back from the background re-reads the ride at once.
//
// The screen stayed on "driver on the way" after the trip had started until the
// app was restarted: nothing refreshed it on resume, it only waited on timers
// the OS may have paused. Resume now polls immediately and restarts the timers.
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'),
            (call) async => true);
  });

  testWidgets('resume fetches the ride immediately and shows the new phase', (tester) async {
    final ride = rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way');
    final log = <ApiCall>[];
    await pumpRide(tester, ride, kCommon, log: log);
    expect(find.text('Driver on the way'), findsWidgets);

    // While "in the background" the driver starts the trip.
    ride
      ..['status'] = 'ongoing'
      ..['uiPhase'] = 'ongoing'
      ..['uiPhaseLabel'] = 'On trip';
    log.clear();

    await act(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Well inside the 3s poll interval: only the resume refresh can explain a fetch.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    final rideFetches = log.where((c) => c.method == 'GET' && c.url.path.endsWith('/rides/ride123'));
    expect(rideFetches, isNotEmpty, reason: 'resume must re-fetch the ride right away');
    expect(find.text('On trip'), findsWidgets);
    expect(find.text('Driver on the way'), findsNothing);

    await teardown(tester);
  });
}
