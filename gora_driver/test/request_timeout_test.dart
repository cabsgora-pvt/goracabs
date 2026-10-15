import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/logic/dismissed_requests.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A request whose countdown runs out is dismissed on this phone only. It used
// to call /rides/:id/reject, which puts the driver in rejectedBy — so a request
// that merely timed out (often in the background) was gone for good. An
// explicit tap on reject still rejects.
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _request(String id, DateTime offerExpiresAt) => {
  'id': id, 'service': 'taxi', 'riderName': 'Rahul Mehta', 'vehicleType': 'Bike',
  'pickupAddress': 'Law Garden, Ellisbridge, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 85, 'totalFare': 85, 'distance': 6.2, 'paymentMode': 'cash',
  'offeredToMe': true, 'offerExpiresAt': offerExpiresAt.toUtc().toIso8601String(),
};

void main() {
  setUp(() {
    DismissedRequests.clear();
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });
  tearDown(DismissedRequests.clear);

  Future<List<http.Request>> run(WidgetTester tester, Future<void> Function() body) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <http.Request>[];
    final expires = DateTime.now().add(const Duration(seconds: 3));
    await http.runWithClient(() async {
      // Opened on top of a stand-in home, as the home poller does.
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncomingRequestsPage())),
          child: const Text('HOME'),
        )),
      ))));
      await tester.tap(find.text('HOME'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await body();
    }, () => MockClient((req) async {
      calls.add(req);
      if (req.url.path.endsWith('/rides/driver/pending')) {
        // The server keeps listing it (lapsed offer / open pool), as in production.
        return http.Response(jsonEncode({'rides': [_request('r1', expires)]}), 200);
      }
      return http.Response(jsonEncode({'success': true}), 200);
    }));
    while (tester.takeException() != null) {}
    return calls;
  }

  testWidgets('countdown running out does not reject, and the card does not loop back', (tester) async {
    final calls = await run(tester, () async {
      expect(find.text('Law Garden, Ellisbridge, Ahmedabad'), findsOneWidget);
      // Past the 3s offer window, and through two more 3s feed refreshes.
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    expect(calls.where((r) => r.url.path.endsWith('/reject')), isEmpty);
    expect(DismissedRequests.isSuppressed('r1'), isTrue);
    expect(find.text('Law Garden, Ellisbridge, Ahmedabad'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('an explicit tap on reject still rejects on the server', (tester) async {
    final calls = await run(tester, () async {
      await tester.tap(find.byIcon(Icons.close).first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    final rejects = calls.where((r) => r.method == 'POST' && r.url.path.endsWith('/rides/r1/reject'));
    expect(rejects, hasLength(1));
    expect(find.text('HOME'), findsOneWidget);
  });
}
