import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/services/driver_api_service.dart';

// Found in live QA. Going offline sent 0,0, which the server stored as the
// driver's position with a fresh timestamp; and a rental's Order Complete
// showed "0.00 km · 0 min" and "₹0.00 per km earned".

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'driver_token': 't'}));

  Future<Map<String, dynamic>> sent(Future<void> Function() call) async {
    Map<String, dynamic>? body;
    await http.runWithClient(call, () => MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'success': true}), 200);
    }));
    return body!;
  }

  group('setOnline', () {
    test('going offline sends no position', () async {
      final b = await sent(() => DriverApiService.setOnline(false));
      expect(b, {'isOnline': false});
    });

    test('going online without a fix sends no made-up position', () async {
      final b = await sent(() => DriverApiService.setOnline(true, null, null));
      expect(b.containsKey('lat'), isFalse);
      expect(b.containsKey('lng'), isFalse);
    });

    test('going online with a fix sends it', () async {
      final b = await sent(() => DriverApiService.setOnline(true, 22.29, 70.79));
      expect(b, {'isOnline': true, 'lat': 22.29, 'lng': 70.79});
    });
  });

  group('Order Complete', () {
    Future<void> show(WidgetTester tester, RideRequestModel ride) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(arguments: RideCompletionArgs(ride, driverEarning: 199, adminProfit: 50)),
          builder: (_) => const InvoicePage(),
        ),
      ));
      await tester.pump();
    }

    RideRequestModel ride(num km, int min) => RideRequestModel(
      id: 'r1', userName: 'Rider', userPhone: '', userRating: '5.0',
      pickupAddress: 'P', dropAddress: 'D', distance: '', fare: '₹249',
      eta: '', rideType: 'Cab', pickupLat: 0, pickupLng: 0, dropLat: 0, dropLng: 0,
      distanceKm: km, durationMin: min,
    );

    testWidgets('a rental with no trip distance shows no zero km lines', (tester) async {
      await show(tester, ride(0, 0));
      expect(find.text('₹199'), findsOneWidget);
      expect(find.textContaining('0.00 km'), findsNothing);
      expect(find.textContaining('per km earned'), findsNothing);
    });

    testWidgets('a taxi trip still shows distance and per km', (tester) async {
      await show(tester, ride(5, 12));
      expect(find.textContaining('5.00 km'), findsOneWidget);
      expect(find.textContaining('per km earned'), findsOneWidget);
    });
  });
}
