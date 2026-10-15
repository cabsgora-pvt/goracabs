import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/logic/job_settlement.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// A parcel, rental or hire job settled by the driver shows the earning the
// server worked out — after commission. The invoice was handed the bare ride
// and showed the whole fare as the driver's earning.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'driver_token': 't'}));

  Future<void> finish(WidgetTester tester, Future<http.Response> Function(http.Request) server) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ride = shell.ride(service: 'delivery', status: 'ongoing');   // fare ₹1,24,999
    await tester.pumpWidget(MaterialApp(
      routes: {
        InvoicePage.route: (_) => const InvoicePage(),
        '/home': (_) => const Scaffold(body: Text('HOME')),
      },
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => http.runWithClient(
            () => collectAndSettle(context, ride: ride, cashDue: 0), () => MockClient(server)),
        child: const Text('finish'),
      ))),
    ));
    await tester.tap(find.text('finish'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  http.Response json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code);

  testWidgets('the invoice shows the earning after commission', (tester) async {
    await finish(tester, (req) async => req.url.path.endsWith('/complete')
        ? json({'success': true, 'fare': 85, 'adminProfit': 17, 'driverEarning': 68})
        : json({}));
    expect(find.text('₹68'), findsOneWidget);
    expect(find.textContaining('₹17'), findsOneWidget);
    expect(find.text('₹124999'), findsNothing, reason: 'not the whole fare');
  });

  testWidgets('already settled elsewhere: the earning is read from the ride', (tester) async {
    await finish(tester, (req) async {
      if (req.url.path.endsWith('/complete')) return json({'error': 'Already completed'}, 400);
      return json({'_id': 'ride-1', 'status': 'completed', 'driverEarning': 68, 'commissionAmount': 17});
    });
    expect(find.text('₹68'), findsOneWidget);
    expect(find.textContaining('₹17'), findsOneWidget);
  });

  testWidgets('a failed settlement says so and stays', (tester) async {
    await finish(tester, (req) async => json({'error': 'Server error'}, 500));
    expect(find.byType(InvoicePage), findsNothing);
    expect(find.text('Could not finish the ride: Server error. Swipe again to retry.'), findsOneWidget);
  });
}
