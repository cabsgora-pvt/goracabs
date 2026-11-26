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
import 'package:customer_app/screens/ride_history_screen.dart';
import 'package:customer_app/screens/trip_detail_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/receipt.dart';
import 'package:customer_app/utils/trip_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Receipts: coupon, waiting, cancellation fee / reason, stops and payment
// status from the ride record; "Total Paid" only when the server says paid;
// no 0,0 map point for a trip without a drop.
// ─────────────────────────────────────────────────────────────────────────────

Widget _app(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('TripReceipt', () {
    test('coupon comes off a taxi fare; label follows paymentStatus', () {
      final r = TripReceipt.from({
        'service': 'taxi', 'status': 'completed', 'paymentStatus': 'paid',
        'fare': 200, 'waitingChargeTotal': 15, 'tip': 10, 'totalFare': 225,
        'couponCode': 'GORA50', 'couponDiscount': 50,
      });
      expect(r.couponOff, 50);
      expect(r.total, 175);
      expect(r.totalLabel(), 'Total Paid');
      expect(r.totalValue, 175);
    });

    test('a rental fare already has the coupon off: not subtracted twice', () {
      final r = TripReceipt.from({
        'service': 'rental', 'status': 'completed', 'paymentStatus': 'paid',
        'fare': 800, 'finalFare': 900, 'totalFare': 900, 'couponDiscount': 100,
      });
      expect(r.couponOff, 0);
      expect(r.total, 900);
    });

    test('completed but unpaid: "Amount due" with the server amountDue', () {
      final r = TripReceipt.from({
        'service': 'taxi', 'status': 'completed', 'paymentStatus': 'pending',
        'fare': 300, 'totalFare': 300, 'amountDue': 120,
      });
      expect(r.totalLabel(), 'Amount due');
      expect(r.totalValue, 120);
    });

    test('no payment status: the caller fallback label, never "Total Paid"', () {
      final r = TripReceipt.from({'status': 'Completed', 'baseFare': 90, 'tip': 10, 'total': 100});
      expect(r.totalLabel(), 'Total');
      expect(r.totalLabel(unknown: 'Total Amount'), 'Total Amount');
      expect(r.total, 100);
    });

    test('cancelled: the fee, who and why', () {
      final r = TripReceipt.from({
        'status': 'cancelled', 'paymentStatus': 'pending', 'fare': 400, 'totalFare': 400,
        'cancellationFee': 30, 'cancelledBy': 'rider', 'cancellationReason': 'Driver too far',
      });
      expect(r.total, 30);
      expect(r.totalLabel(), 'Cancellation fee');
      expect(r.cancellationLine, 'Cancelled by you · Driver too far');
      final free = TripReceipt.from({'status': 'cancelled', 'fare': 400});
      expect(free.totalLabel(), 'Cancelled');
      expect(free.total, 0);
    });

    test('outstation tolls are added; stops from stops and deliveryStops', () {
      final r = TripReceipt.from({
        'service': 'outstation', 'status': 'completed', 'fare': 5000, 'totalFare': 5000, 'tollCharge': 180,
        'stops': [{'address': 'Nadiad'}, {'address': ''}],
        'deliveryStops': [{'address': 'Anand'}],
      });
      expect(r.total, 5180);
      expect(r.stops, ['Nadiad', 'Anand']);
    });

    test('a coupon bigger than the fare never makes the total negative', () {
      final r = TripReceipt.from({'status': 'completed', 'fare': 40, 'totalFare': 40, 'couponDiscount': 100});
      expect(r.total, 0);
    });

    test('paymentLine', () {
      expect(TripReceipt.paymentLine('wallet', 'paid'), 'WALLET · Paid');
      expect(TripReceipt.paymentLine('', ''), 'CASH');
    });
  });

  group('TripMapPoints', () {
    test('a missing drop is left out, not 0,0', () {
      final m = TripMapPoints.of({'pickupLat': 23.0, 'pickupLng': 72.5, 'dropLat': null, 'dropLng': 0});
      expect(m.pickup, isNotNull);
      expect(m.drop, isNull);
      expect(m.route.length, 1);
      expect(m.bounds, isNull);
      expect(m.center!.latitude, 23.0);
    });

    test('no points at all: nothing to draw', () {
      final m = TripMapPoints.of({'pickupLat': 0, 'pickupLng': 0});
      expect(m.center, isNull);
      expect(m.isEmpty, isTrue);
    });

    test('both points: a route and bounds', () {
      final m = TripMapPoints.of({'pickupLat': 23.0, 'pickupLng': 72.5, 'dropLat': 23.1, 'dropLng': 72.6});
      expect(m.route.length, 2);
      expect(m.bounds, isNotNull);
    });
  });

  group('trip detail', () {
    setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

    testWidgets('coupon, waiting, stops, paid label and the trip actions', (tester) async {
      _size(tester, const Size(400, 1800));
      await tester.pumpWidget(_app(const TripDetailScreen(ride: {
        'id': 'r-1', 'service': 'taxi', 'status': 'Completed', 'paymentStatus': 'paid', 'paymentMode': 'wallet',
        'from': 'Paota, Jodhpur', 'to': 'Station Rd, Jodhpur', 'baseFare': 200, 'tip': 0, 'total': 215,
        'waitingChargeTotal': 15, 'couponCode': 'GORA50', 'couponDiscount': 50,
        'stops': ['Sardarpura'], 'driver': 'Ramesh', 'rating': 0.0,
        'pickupLat': 26.29, 'pickupLng': 73.02, 'dropLat': 26.28, 'dropLng': 73.03,
      })));
      await tester.pump();
      expect(find.text('Waiting charge'), findsOneWidget);
      expect(find.text('Coupon (GORA50)'), findsOneWidget);
      expect(find.text('-₹50'), findsOneWidget);
      expect(find.text('Total Paid'), findsOneWidget);
      expect(find.text('₹165'), findsOneWidget);
      expect(find.text('Sardarpura'), findsOneWidget);
      expect(find.text('Payment: WALLET · Paid'), findsOneWidget);
      expect(find.byKey(const ValueKey('trip-help')), findsOneWidget);
      expect(find.byKey(const ValueKey('trip-invoice')), findsOneWidget);
      expect(find.byKey(const ValueKey('trip-rate')), findsOneWidget);
    });

    testWidgets('unpaid trip says "Amount due", not "Total Paid"', (tester) async {
      _size(tester, const Size(400, 1600));
      await tester.pumpWidget(_app(const TripDetailScreen(ride: {
        'id': 'r-2', 'service': 'taxi', 'status': 'Completed', 'paymentStatus': 'pending',
        'from': 'A', 'to': 'B', 'baseFare': 120, 'total': 120, 'amountDue': 120,
        'pickupLat': 26.29, 'pickupLng': 73.02, 'dropLat': 26.28, 'dropLng': 73.03,
      })));
      await tester.pump();
      expect(find.text('Amount due'), findsOneWidget);
      expect(find.text('Total Paid'), findsNothing);
    });

    testWidgets('cancelled trip: reason shown, no invoice / rate, no drop map pin needed', (tester) async {
      _size(tester, const Size(400, 1600));
      await tester.pumpWidget(_app(const TripDetailScreen(ride: {
        'id': 'r-3', 'service': 'hire_driver', 'status': 'Cancelled', 'paymentStatus': 'pending',
        'from': 'Paota', 'to': '', 'baseFare': 600, 'total': 600,
        'cancellationFee': 0, 'cancelledBy': 'driver', 'cancellationReason': 'Vehicle breakdown',
        'pickupLat': 26.29, 'pickupLng': 73.02, 'dropLat': null, 'dropLng': null,
      })));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Cancelled by the driver · Vehicle breakdown'), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.byKey(const ValueKey('trip-invoice')), findsNothing);
      expect(find.byKey(const ValueKey('trip-rate')), findsNothing);
      expect(find.byKey(const ValueKey('trip-help')), findsOneWidget);
      expect(find.text('DROP'), findsNothing);
    });

    testWidgets('no coordinates at all: no map, no crash', (tester) async {
      _size(tester, const Size(400, 1600));
      await tester.pumpWidget(_app(const TripDetailScreen(ride: {
        'id': 'r-4', 'service': 'taxi', 'status': 'Completed', 'from': 'A', 'to': 'B', 'baseFare': 50, 'total': 50,
      })));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Fare Breakdown'), findsOneWidget);
    });
  });

  group('history and invoice', () {
    setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

    final stored = {
      '_id': 'h-1', 'service': 'taxi', 'status': 'completed', 'paymentStatus': 'paid', 'paymentMode': 'cash',
      'fare': 200, 'totalFare': 200, 'couponCode': 'SAVE40', 'couponDiscount': 40,
      'pickupAddress': 'Paota, Jodhpur', 'dropAddress': 'Station Rd, Jodhpur',
      'pickupLat': 26.29, 'pickupLng': 73.02, 'createdAt': '2026-10-20T10:00:00.000Z',
    };

    testWidgets('history row shows the amount after the coupon; detail maps it', (tester) async {
      _size(tester, const Size(412, 1600));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RideHistoryScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('₹160'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('trip-h-1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }, () => MockClient((req) async => req.url.path.endsWith('/rides/user')
          ? http.Response(jsonEncode({'rides': [stored]}), 200)
          : http.Response('{}', 200)));
      expect(tester.takeException(), isNull);
      expect(find.byType(TripDetailScreen), findsOneWidget);
      expect(find.text('Coupon (SAVE40)'), findsOneWidget);
      expect(find.text('Total Paid'), findsOneWidget);
    });

    testWidgets('invoice: coupon line and "Total Paid" from the full record', (tester) async {
      _size(tester, const Size(360, 1200));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const InvoiceScreen(ride: {
          'id': 'h-1', 'service': 'taxi', 'status': 'Completed', 'from': 'Paota, Jodhpur', 'to': 'Station Rd, Jodhpur',
          'baseFare': 200, 'total': 200, 'paymentMode': 'cash',
        })));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, () => MockClient((req) async => req.url.path.endsWith('/rides/h-1')
          ? http.Response(jsonEncode({...stored, 'stops': [{'address': 'Sardarpura'}]}), 200)
          : http.Response('{}', 200)));
      expect(find.text('Coupon (SAVE40)'), findsOneWidget);
      expect(find.text('-₹40'), findsOneWidget);
      expect(find.text('Total Paid'), findsOneWidget);
      expect(find.text('₹160'), findsOneWidget);
      expect(find.text('Stop 1: Sardarpura'), findsOneWidget);
      expect(find.text('Payment: CASH · Paid'), findsOneWidget);
    });

    testWidgets('invoice: a cancelled ride with a fee says so', (tester) async {
      _size(tester, const Size(360, 1200));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const InvoiceScreen(ride: {
          'id': 'c-1', 'service': 'taxi', 'status': 'Cancelled', 'from': 'A', 'to': 'B', 'baseFare': 300, 'total': 300,
        })));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, () => MockClient((req) async => req.url.path.endsWith('/rides/c-1')
          ? http.Response(jsonEncode({
              '_id': 'c-1', 'status': 'cancelled', 'fare': 300, 'totalFare': 300, 'cancellationFee': 25,
              'cancelledBy': 'rider', 'cancellationReason': 'Changed my plans',
            }), 200)
          : http.Response('{}', 200)));
      expect(find.text('Cancelled by you · Changed my plans'), findsOneWidget);
      expect(find.text('Cancellation fee'), findsWidgets);
      expect(find.text('₹25'), findsWidgets);
    });
  });
}
