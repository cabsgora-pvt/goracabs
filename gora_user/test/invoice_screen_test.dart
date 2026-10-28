import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/invoice_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The invoice shows the ride it was opened for. It used to be a static page —
// "MAHENDRA KUMAR", a Jodhpur address, 11/08/2025, and a total priced from a
// vehicle-name table that came to ₹0.00 for any real vehicle type.
// ─────────────────────────────────────────────────────────────────────────────

/// The summary map the ride-history screen builds (same keys).
Map<String, dynamic> historyRow() => {
  'id': '66f0c0ffee0000000000abcd',
  'service': 'taxi',
  'status': 'Completed',
  'date': '14/10/2026, 18:05',
  'from': 'Paota C Road, Jodhpur',
  'to': 'Jodhpur Railway Station, Station Rd, Jodhpur',
  'riderName': 'Priya Bhandari',
  'driver': 'Ramesh Choudhary',
  'driverVehicleModel': 'Maruti Dzire',
  'driverVehicleNumber': 'RJ19 TA 4521',
  'vehicle': 'Prime Sedan',
  'distance': 6.4,
  'paymentMode': 'cash',
  'baseFare': 142,
  'tip': 20,
  'total': 162,
};

/// GET /rides/:id for the same ride, as completed (waiting charge included in totalFare).
Map<String, dynamic> fullRide() => {
  '_id': '66f0c0ffee0000000000abcd',
  'status': 'completed',
  'service': 'taxi',
  'vehicleType': 'Prime Sedan',
  'pickupAddress': 'Paota C Road, Jodhpur',
  'dropAddress': 'Jodhpur Railway Station, Station Rd, Jodhpur',
  'distance': 6.4,
  'fare': 142,
  'tip': 20,
  'waitingChargeTotal': 10,
  'totalFare': 172,
  'paymentMode': 'cash',
  'createdAt': '2026-10-14T12:35:00.000Z',
  'completedAt': '2026-10-14T13:02:00.000Z',
  'rider': {'id': 'u1', 'name': 'Priya Bhandari'},
  'driver': {'name': 'Ramesh Choudhary', 'vehicleModel': 'Maruti Dzire', 'vehicleNumber': 'RJ19 TA 4521'},
};

Widget _app(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

  Future<List<http.Request>> pump(WidgetTester tester, {required http.Response Function() ride}) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seen = <http.Request>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(InvoiceScreen(ride: historyRow())));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => MockClient((req) async {
      seen.add(req);
      if (req.url.path.endsWith('/rides/66f0c0ffee0000000000abcd')) return ride();
      return http.Response('{}', 200);
    }));
    return seen;
  }

  testWidgets('renders the real ride from GET /rides/:id with the rider token', (tester) async {
    final seen = await pump(tester, ride: () => http.Response(jsonEncode(fullRide()), 200));

    final get = seen.firstWhere((r) => r.url.path.endsWith('/rides/66f0c0ffee0000000000abcd'));
    expect(get.headers['Authorization'], 'Bearer rider-token');

    expect(find.text('PRIYA BHANDARI'), findsOneWidget);
    expect(find.textContaining('Paota C Road, Jodhpur'), findsOneWidget);
    expect(find.textContaining('Jodhpur Railway Station'), findsOneWidget);
    expect(find.text('Driver: Ramesh Choudhary'), findsOneWidget);
    expect(find.text('Maruti Dzire • RJ19 TA 4521'), findsOneWidget);
    expect(find.text('Ride (Prime Sedan) · 6.4 km'), findsOneWidget);
    expect(find.text('Waiting charge'), findsOneWidget);
    expect(find.text('Tip'), findsOneWidget);
    expect(find.text('Payment: CASH'), findsOneWidget);
    // completedAt 13:02Z, shown in the device's local time.
    final done = DateTime.parse('2026-10-14T13:02:00.000Z').toLocal();
    expect(find.textContaining('${done.day.toString().padLeft(2, '0')}/10/2026'), findsOneWidget);
    // The recorded total (fare 142 + waiting 10 + tip 20), not a recomputation.
    expect(find.text('Total Amount'), findsOneWidget);
    expect(find.text('₹172'), findsOneWidget);

    for (final placeholder in ['MAHENDRA', 'SURENDRA', '11/08/2025', 'FHACCBFC', 'CGST', 'UIT Rd']) {
      expect(find.textContaining(placeholder), findsNothing, reason: placeholder);
    }
  });

  testWidgets('falls back to the history row when the fetch fails', (tester) async {
    await pump(tester, ride: () => http.Response(jsonEncode({'error': 'Not a participant in this ride'}), 403));
    expect(find.text('PRIYA BHANDARI'), findsOneWidget);
    expect(find.text('Driver: Ramesh Choudhary'), findsOneWidget);
    expect(find.text('Total Amount'), findsOneWidget);
    expect(find.text('₹162'), findsOneWidget);
    expect(find.textContaining('MAHENDRA'), findsNothing);
  });
}
