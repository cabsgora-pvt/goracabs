import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/models/models.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// "You have reached the sender / receiver" goes once the driver has done what
// it asks. Its timer does not run under a dialog or a pushed page, so it was
// still showing after the parcel was collected, and on the fare screen.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  Future<void> pumpFor(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> arrive(WidgetTester tester) async {
    tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onArrived!();
    await pumpFor(tester, 400);
  }

  testWidgets('at the sender: the nudge goes once the parcel is collected', (tester) async {
    await shell.openScreen(tester, page: DeliveryProgressPage(ride: shell.ride(service: 'delivery', status: 'ongoing')),
        override: (req) async => req.url.path.endsWith('/delivery')
            ? http.Response(jsonEncode({'success': true, 'deliveryPhase': 'in_transit'}), 200) : null);
    await arrive(tester);
    expect(find.text('You have reached the sender — collect the parcel'), findsOneWidget);
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe once parcel is collected');
      await pumpFor(tester, 1000);
    });
    expect(find.text('Delivered — enter receiver OTP'), findsOneWidget, reason: 'collected');
    expect(find.text('You have reached the sender — collect the parcel'), findsNothing);
    await shell.teardown(tester);
  });

  testWidgets('at the receiver: the nudge goes as the OTP is asked for', (tester) async {
    final ride = shell.ride(service: 'delivery', status: 'ongoing',
        progress: RideProgress.fromJson({'deliveryPhase': 'in_transit'}));
    await shell.openScreen(tester, page: DeliveryProgressPage(ride: ride));
    await arrive(tester);
    expect(find.text('You have reached the receiver — capture proof and enter the OTP'), findsOneWidget);
    await shell.act(() async {
      await tester.tap(find.text('Receiver unavailable — return to sender'));
      await pumpFor(tester, 600);
    });
    expect(find.text('Return to Sender — reason'), findsOneWidget);
    expect(find.text('You have reached the receiver — capture proof and enter the OTP'), findsNothing);
    await shell.teardown(tester);
  });
}
