import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/ride_history_screen.dart';
import 'package:customer_app/screens/trip_detail_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/ride_service_panels.dart';

import 'active_ride_screen_test.dart' as screen;

// ─────────────────────────────────────────────────────────────────────────────
// Outstation tolls, rider side: seen live as the driver adds them, owed to the
// driver in hand at the end, and itemised on the bill and the trip record.
// ─────────────────────────────────────────────────────────────────────────────

const _two = [
  {'id': 't1', 'amount': 85, 'at': '2026-09-22T06:30:00.000Z', 'source': 'prompt'},
  {'id': 't2', 'amount': 85, 'at': '2026-09-22T07:10:00.000Z', 'source': 'manual'},
];

// With where each was paid, as the server names it.
const placed = [
  {'id': 't1', 'amount': 95, 'at': '2026-09-22T06:30:00.000Z', 'place': 'Kherki Daula Toll Plaza, NH 48, Gurugram'},
  {'id': 't2', 'amount': 85, 'at': '2026-09-22T07:10:00.000Z', 'place': 'Shahjahanpur Toll Plaza, NH 48'},
];

Map<String, dynamic> trip({
  String status = 'ongoing',
  String uiPhase = 'ongoing',
  String payment = 'online',
  List<Map<String, dynamic>> tolls = const [],
  bool awaiting = false,
}) => screen.outstation(status: status, uiPhase: uiPhase)
  ..addAll({
    'paymentMode': payment,
    'tolls': tolls,
    'tollCharge': tolls.fold<num>(0, (s, t) => s + (t['amount'] as num)),
    'awaitingPayment': awaiting,
    if (uiPhase == 'payment') 'uiPhaseLabel': 'Payment due',
  });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), (call) async => true);
  });

  // ── During the trip ──
  testWidgets('each toll shows as the driver adds it, with the total', (tester) async {
    await screen.pumpRide(tester, trip(tolls: _two), screen.kCommon, scrollSheet: true);
    expect(find.byType(OutstationTollPanel), findsOneWidget);
    expect(find.text('Tolls'), findsOneWidget);
    expect(find.text('₹170'), findsOneWidget);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    expect(find.textContaining('Toll 2'), findsOneWidget);
    expect(find.text('You pay tolls to your driver at the end of the trip.'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('before any toll: says so, rather than an empty list', (tester) async {
    await screen.pumpRide(tester, trip(), screen.kCommon, scrollSheet: true);
    expect(find.text('No tolls added yet. Your driver adds each toll they pay.'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('a taxi ride shows no toll panel', (tester) async {
    await screen.pumpRide(tester, screen.rideJson(status: 'ongoing', uiPhase: 'ongoing'), screen.kCommon, scrollSheet: true);
    expect(find.byType(OutstationTollPanel), findsNothing);
    await screen.teardown(tester);
  });

  for (final size in const [screen.kSmall, screen.kCommon]) {
    testWidgets('no overflow with tolls at ${size.width.toInt()}', (tester) async {
      final overflows = await screen.pumpRide(tester, trip(tolls: [
        ..._two,
        for (var i = 3; i <= 9; i++) {'id': 't$i', 'amount': 1450, 'at': '2026-09-22T08:00:00.000Z'},
      ]), size, scrollSheet: true);
      expect(overflows, isEmpty);
      await screen.teardown(tester);
    });
  }

  // ── When the driver ends it ──
  testWidgets('prepaid: the fare is not asked for again; the tolls are, for the driver', (tester) async {
    await screen.pumpRide(tester, trip(uiPhase: 'payment', tolls: _two, awaiting: true), screen.kCommon,
        rideId: 'toll-pay-1', scrollSheet: true);
    expect(find.text('Trip complete'), findsOneWidget);
    expect(find.text('Your fare was paid when you booked. Please pay your driver ₹170 for tolls.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Pay Now'), findsNothing);
    expect(find.textContaining('Please pay ₹5400'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pump();
    // Top of the sheet; the hint is further down, past the tolls.
    expect(find.text('PAID AT BOOKING'), findsOneWidget);
    await screen.scrollSheetToEnd(tester);
    expect(find.text('Fare paid when you booked. Please pay ₹170 for tolls to your driver.'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('prepaid with no tolls: nothing more to pay', (tester) async {
    await screen.pumpRide(tester, trip(uiPhase: 'payment', awaiting: true), screen.kCommon, rideId: 'toll-pay-2');
    expect(find.text('Your fare was paid when you booked. Nothing more to pay.'), findsOneWidget);
    await screen.teardown(tester);
  });

  // Cash is collected before the trip completes, so this should not arise; if
  // it does, the prompt must not claim the fare was paid at booking.
  testWidgets('cash: the prompt asks for the fare and tolls, never "paid at booking"', (tester) async {
    await screen.pumpRide(tester, trip(uiPhase: 'payment', payment: 'cash', tolls: _two, awaiting: true), screen.kCommon,
        rideId: 'toll-pay-3');
    expect(find.text('Please pay your driver ₹5570 in cash — fare plus ₹170 tolls.'), findsOneWidget);
    expect(find.textContaining('paid when you booked'), findsNothing);
    await screen.teardown(tester);
  });

  // ── The bill ──
  Future<void> finish(WidgetTester tester, Map<String, dynamic> ride, String id) async {
    await screen.pumpRide(tester, ride..addAll({'status': 'completed', 'uiPhase': 'completed'}), screen.kCommon, rideId: id);
  }

  testWidgets('the bill shows where each toll was paid', (tester) async {
    await finish(tester, trip(tolls: placed), 'bill-o-4');
    expect(find.text('Kherki Daula Toll Plaza, NH 48, Gurugram'), findsOneWidget);
    expect(find.text('₹5580'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('the bill lists each toll and adds them to the total', (tester) async {
    await finish(tester, trip(tolls: _two), 'bill-o-1');
    expect(find.text('Trip Bill'), findsOneWidget);
    expect(find.text('Fare (paid at booking)'), findsOneWidget);
    expect(find.text('₹5400'), findsOneWidget);
    expect(find.text('Tolls (2) · paid to driver'), findsOneWidget);
    expect(find.text('₹170'), findsOneWidget);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    expect(find.textContaining('Toll 2'), findsOneWidget);
    expect(find.text('₹5570'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('outstation always shows a toll line, even with none', (tester) async {
    await finish(tester, trip(), 'bill-o-2');
    expect(find.text('Tolls (0) · paid to driver'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('₹5400'), findsNWidgets(2), reason: 'fare and total');
    await screen.teardown(tester);
  });

  testWidgets('cash: the fare is not labelled as paid at booking', (tester) async {
    await finish(tester, trip(payment: 'cash', tolls: _two), 'bill-o-3');
    expect(find.text('Fare'), findsOneWidget);
    expect(find.text('Fare (paid at booking)'), findsNothing);
    expect(find.text('₹5570'), findsOneWidget);
    await screen.teardown(tester);
  });

  // ── Where, and reporting ──
  testWidgets('each toll shows where it was paid', (tester) async {
    await screen.pumpRide(tester, trip(tolls: placed), screen.kCommon, scrollSheet: true);
    expect(find.text('Kherki Daula Toll Plaza, NH 48, Gurugram'), findsOneWidget);
    expect(find.text('Shahjahanpur Toll Plaza, NH 48'), findsOneWidget);
    await screen.teardown(tester);
  });

  Future<void> sendReport(WidgetTester tester, {String reason = 'The amount is wrong', String note = ''}) async {
    await screen.act(() async {
      await tester.tap(find.bySemanticsLabel('Report toll 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Report this toll'), findsOneWidget);
      await tester.tap(find.text(reason));
      await tester.pump();
      if (note.isNotEmpty) await tester.enterText(find.byType(TextField), note);
      await tester.tap(find.text('Send report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
  }

  testWidgets('a toll can be reported, with a reason, and is then marked', (tester) async {
    final semantics = tester.ensureSemantics();
    final log = <screen.ApiCall>[];
    await screen.pumpRide(tester, trip(tolls: placed), screen.kCommon, log: log, scrollSheet: true, rideId: 'rep-1');
    await sendReport(tester, note: 'Board at the plaza said 65');
    final sent = log.where((c) => c.method == 'POST' && c.url.path.endsWith('/rides/rep-1/toll')).toList();
    expect(sent, hasLength(1));
    expect(jsonDecode(sent.single.body), {'action': 'report', 'tollId': 't1', 'reason': 'wrong_amount', 'note': 'Board at the plaza said 65'});
    expect(find.text('Report sent. Our support team will look into this toll.'), findsOneWidget);
    expect(find.text('Reported — our team will review it'), findsOneWidget);
    expect(find.bySemanticsLabel('Report toll 1'), findsNothing, reason: 'once per toll');
    expect(find.bySemanticsLabel('Report toll 2'), findsOneWidget);
    semantics.dispose();
    await screen.teardown(tester);
  });

  // The panel marks the toll itself; the screen still re-reads the ride at once
  // rather than at the next poll, so everything else on it agrees.
  testWidgets('after a report, the ride is read again straight away', (tester) async {
    final semantics = tester.ensureSemantics();
    final log = <screen.ApiCall>[];
    await screen.pumpRide(tester, trip(tolls: placed), screen.kCommon, log: log, scrollSheet: true, rideId: 'rep-2');
    await screen.act(() async {
      await tester.tap(find.bySemanticsLabel('Report toll 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('No toll was paid here'));
      await tester.pump();
      log.clear();
      await tester.tap(find.text('Send report'));
      // No time passes, so no poll falls due: any read now is the refresh.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    });
    final calls = [for (final c in log) '${c.method} ${c.url.path}'];
    final sent = calls.indexWhere((c) => c.startsWith('POST') && c.endsWith('/rides/rep-2/toll'));
    expect(sent, isNot(-1), reason: calls.join('\n'));
    expect(calls.skip(sent + 1).where((c) => c.startsWith('GET') && c.endsWith('/rides/rep-2')), isNotEmpty,
        reason: calls.join('\n'));
    semantics.dispose();
    await screen.teardown(tester);
  });

  testWidgets('Send stays off until a reason is chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    await screen.pumpRide(tester, trip(tolls: placed), screen.kCommon, scrollSheet: true);
    await tester.tap(find.bySemanticsLabel('Report toll 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final send = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send report'));
    expect(send.onPressed, isNull);
    semantics.dispose();
    await screen.teardown(tester);
  });

  testWidgets('a report that fails says so, and can be tried again', (tester) async {
    final semantics = tester.ensureSemantics();
    await screen.pumpRide(tester, trip(tolls: placed), screen.kCommon, scrollSheet: true,
        override: (req) async => req.url.path.endsWith('/toll')
            ? http.Response(jsonEncode({'error': 'Could not send the report. Please try again.'}), 500) : null);
    await sendReport(tester);
    expect(find.text('Could not send the report: Could not send the report. Please try again.'), findsOneWidget);
    expect(find.text('Reported — our team will review it'), findsNothing);
    expect(find.bySemanticsLabel('Report toll 1'), findsOneWidget);
    semantics.dispose();
    await screen.teardown(tester);
  });

  testWidgets('a toll already reported shows it, with no second report', (tester) async {
    final semantics = tester.ensureSemantics();
    await screen.pumpRide(tester, trip(tolls: [
      {...placed[0], 'reportedAt': '2026-09-22T08:00:00.000Z', 'reportReason': 'no_toll'},
      placed[1],
    ]), screen.kCommon, scrollSheet: true);
    expect(find.text('Reported — our team will review it'), findsOneWidget);
    expect(find.bySemanticsLabel('Report toll 1'), findsNothing);
    semantics.dispose();
    await screen.teardown(tester);
  });

  // ── Told as each toll is added ──
  testWidgets('a toll the driver adds is announced, with Report', (tester) async {
    final ride = trip(tolls: [placed[0]]);
    await screen.pumpRide(tester, ride, screen.kCommon, rideId: 'alert-1');
    expect(find.textContaining('Your driver added a toll'), findsNothing,
        reason: 'tolls already there when the screen opens are not news');
    ride['tolls'] = placed;
    ride['tollCharge'] = 180;
    await screen.act(() async {
      await tester.pump(const Duration(milliseconds: 3200));   // the next poll
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.textContaining('Your driver added a toll: ₹85 · Shahjahanpur Toll Plaza, NH 48'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Report'), findsOneWidget);
    await screen.teardown(tester);
  });

  // A snack bar with an action stays until tapped by default. This one must not:
  // it held every later toll back and outlived the trip.
  testWidgets('the toll alert goes by itself, and the next toll is announced too', (tester) async {
    final ride = trip(tolls: [placed[0]]);
    await screen.pumpRide(tester, ride, screen.kCommon, rideId: 'alert-2');
    ride['tolls'] = placed;
    ride['tollCharge'] = 180;
    await screen.act(() async {
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('₹85 · Shahjahanpur Toll Plaza'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    });
    expect(find.textContaining('Your driver added a toll'), findsNothing, reason: 'gone after its 8 seconds');
    ride['tolls'] = [...placed,
      {'id': 't3', 'amount': 105, 'at': '2026-09-22T08:00:00.000Z', 'place': 'Manoharpur Toll Plaza, NH 48'}];
    ride['tollCharge'] = 285;
    await screen.act(() async {
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.textContaining('₹105 · Manoharpur Toll Plaza'), findsOneWidget);
    await screen.teardown(tester);
  });

  testWidgets('a toll alert does not outlive the trip', (tester) async {
    final ride = trip(payment: 'cash', tolls: [placed[0]]);
    await screen.pumpRide(tester, ride, screen.kCommon, rideId: 'alert-3');
    ride['tolls'] = placed;
    ride['tollCharge'] = 180;
    await screen.act(() async {
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Your driver added a toll'), findsOneWidget);
      ride.addAll({'status': 'completed', 'uiPhase': 'completed'});
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('Trip Bill'), findsOneWidget);
    expect(find.textContaining('Your driver added a toll'), findsNothing);
    await screen.teardown(tester);
  });

  // ── The trip record ──
  Future<void> record(WidgetTester tester, num toll, {List<Map<String, dynamic>> tolls = const []}) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: TripDetailScreen(ride: {
      'service': 'outstation', 'tripType': 'round_trip', 'fare': 5400, 'baseFare': 5400, 'total': 5400,
      'tollCharge': toll, 'tolls': tolls, 'id': 'hist-1', 'paymentMode': 'online', 'from': 'Ahmedabad', 'to': 'Mount Abu',
      'pickupLat': 23.0, 'pickupLng': 72.5, 'dropLat': 24.5, 'dropLng': 72.7, 'status': 'Completed',
    })));
    await tester.pump();
  }

  testWidgets('trip record: tolls itemised and included in the total', (tester) async {
    await record(tester, 170);
    expect(find.text('Tolls (paid to driver)'), findsOneWidget);
    expect(find.text('₹170'), findsOneWidget);
    expect(find.text('₹5570'), findsOneWidget);
  });

  testWidgets('trip record: each toll with where it was paid, reportable', (tester) async {
    final semantics = tester.ensureSemantics();
    await record(tester, 180, tolls: placed);
    expect(find.text('Kherki Daula Toll Plaza, NH 48, Gurugram'), findsOneWidget);
    expect(find.bySemanticsLabel('Report toll 1'), findsOneWidget);
    semantics.dispose();
  });

  // From the server as it stores them: `_id`, and `reportedAt` rather than a flag.
  testWidgets('trip record opened from history: each toll, where, and reported', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stored = {
      '_id': 'h-77', 'service': 'outstation', 'status': 'completed', 'tripType': 'one_way',
      'fare': 5400, 'totalFare': 5400, 'tollCharge': 180, 'paymentMode': 'online',
      'pickupAddress': 'Gurugram', 'dropAddress': 'Jaipur', 'createdAt': '2026-09-22T05:00:00.000Z',
      'pickupLat': 28.45, 'pickupLng': 77.02, 'dropLat': 26.91, 'dropLng': 75.78,
      'tolls': [
        {'_id': 'x1', 'amount': 95, 'at': '2026-09-22T06:30:00.000Z', 'place': 'Kherki Daula Toll Plaza, NH 48, Gurugram',
         'reportedAt': '2026-09-22T08:00:00.000Z', 'reportReason': 'wrong_amount'},
        {'_id': 'x2', 'amount': 85, 'at': '2026-09-22T07:10:00.000Z', 'place': 'Shahjahanpur Toll Plaza, NH 48'},
      ],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: const RideHistoryScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }, () => MockClient((req) async => req.url.path.endsWith('/rides/user')
        ? http.Response(jsonEncode({'rides': [stored]}), 200)
        : http.Response('{}', 200)));
    // "Your trips" lists every service in one list: the trip is its row.
    expect(find.text('Gurugram → Jaipur'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trip-h-77')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TripDetailScreen), findsOneWidget);
    expect(find.text('Kherki Daula Toll Plaza, NH 48, Gurugram'), findsOneWidget);
    expect(find.text('Shahjahanpur Toll Plaza, NH 48'), findsOneWidget);
    expect(find.text('Reported — our team will review it'), findsOneWidget);
    expect(find.bySemanticsLabel('Report toll 1'), findsNothing);
    expect(find.bySemanticsLabel('Report toll 2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('trip record: the toll line shows even at ₹0', (tester) async {
    await record(tester, 0);
    expect(find.text('Tolls (paid to driver)'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('₹5400'), findsWidgets);
  });
}
