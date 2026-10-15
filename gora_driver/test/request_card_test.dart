import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A request card says what kind of job it is — and, for a parcel, what the
// parcel is — before the driver accepts. Every service card looked like a taxi
// ride across town: the service label was worked out and never shown.
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _request(String id, String service, {Map<String, dynamic> extra = const {}}) => {
  'id': id, 'service': service, 'riderName': 'Rahul Mehta', 'vehicleType': 'Bike',
  'pickupAddress': 'Law Garden, Ellisbridge, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 85, 'totalFare': 85, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
  ...extra,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  Future<void> show(WidgetTester tester, List<Map<String, dynamic>> rides) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: IncomingRequestsPage()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => MockClient((req) async => http.Response(
        jsonEncode(req.url.path.endsWith('/rides/driver/pending') ? {'rides': rides} : {}), 200)));
    // The ringtone player has no plugin in a test; that is not what is checked.
    while (tester.takeException() != null) {}
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    while (tester.takeException() != null) {}
  }

  testWidgets('a parcel: labelled, with what it is, its weight and size', (tester) async {
    await show(tester, [_request('p1', 'delivery', extra: {
      'itemType': 'Electronics', 'weightKg': 2, 'packageSize': 'M', 'isFragile': true, 'codAmount': 2500,
    })]);
    expect(find.text('PARCEL'), findsOneWidget);
    expect(find.text('Electronics · 2 kg · Size M'), findsOneWidget);
    expect(find.text('Fragile'), findsOneWidget);
    expect(find.text('COD ₹2500'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a plain parcel: no fragile or COD chips', (tester) async {
    await show(tester, [_request('p2', 'delivery', extra: {'itemType': 'Documents', 'weightKg': 0.5})]);
    expect(find.text('Documents · 0.5 kg'), findsOneWidget);
    expect(find.text('Fragile'), findsNothing);
    expect(find.textContaining('COD'), findsNothing);
    await close(tester);
  });

  testWidgets('an outstation trip is labelled; a taxi ride is not', (tester) async {
    await show(tester, [_request('o1', 'outstation'), _request('t1', 'taxi')]);
    expect(find.text('OUTSTATION'), findsOneWidget);
    expect(find.text('TAXI'), findsNothing);
    expect(find.byIcon(Icons.inventory_2_outlined), findsNothing, reason: 'parcel details only on a parcel');
    await close(tester);
  });
}
