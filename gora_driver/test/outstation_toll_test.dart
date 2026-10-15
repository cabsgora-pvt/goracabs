import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_engine.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/voice_guide.dart';
import 'package:gora_driver/models/models.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// Outstation tolls, driver side: noticing a toll road has been driven, entering
// each toll, and collecting them — outside the fare — at the end of the trip.
// ─────────────────────────────────────────────────────────────────────────────

NavStep tollStep({double endLat = 23.10, double endLng = 72.60, double startLat = 23.05, bool toll = true}) =>
    NavStep(
      instruction: 'Merge onto NH48. Toll road', maneuver: 'merge', distanceM: 8000, durationSec: 400,
      start: LatLng(startLat, 72.55), end: LatLng(endLat, endLng), toll: toll,
    );

NavStep plainStep({double endLat = 23.20}) => NavStep(
  instruction: 'Turn left', maneuver: 'turn-left', distanceM: 900, durationSec: 60,
  start: const LatLng(23.10, 72.60), end: LatLng(endLat, 72.70),
);

const _two = [
  {'id': 't1', 'amount': 85, 'at': '2026-09-22T06:30:00.000Z', 'source': 'prompt'},
  {'id': 't2', 'amount': 85, 'at': '2026-09-22T07:10:00.000Z', 'source': 'manual'},
];

shell.ApiCall? last(List<shell.ApiCall> log, String suffix) {
  final hits = log.where((c) => c.method == 'POST' && c.url.path.endsWith(suffix)).toList();
  return hits.isEmpty ? null : hits.last;
}

Future<void> collectFare(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Collect Fare'), 300,
      scrollable: find.descendant(of: find.byType(CollectFarePage), matching: find.byType(Scrollable)).first);
  await tester.tap(find.text('Collect Fare'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  // ── Noticing a toll road ──
  group('TollWatcher', () {
    test('asks once, as the driver reaches a toll road', () {
      final w = TollWatcher();
      final t = tollStep();
      expect(w.update(active: plainStep()), isNull, reason: 'not on it yet');
      expect(w.update(active: t), same(t));
      expect(w.update(active: t), isNull, reason: 'only once');
    });

    test('an ordinary road asks nothing', () {
      expect(TollWatcher().update(active: tollStep(toll: false)), isNull);
    });

    // The route is re-fetched from the driver's position every 30s, which moves
    // the step's start but not its end.
    test('a route refresh on the same toll road does not ask again', () {
      final w = TollWatcher();
      expect(w.update(active: tollStep(startLat: 23.05)), isNotNull);
      expect(w.update(active: tollStep(startLat: 23.08)), isNull);
    });

    test('GPS jitter at the boundary does not ask again', () {
      final w = TollWatcher();
      final t = tollStep();
      w.update(active: t);
      w.update(active: plainStep());
      expect(w.update(active: t), isNull);
    });

    test('each separate toll road is asked about', () {
      final w = TollWatcher();
      expect(w.update(active: tollStep(endLat: 23.10)), isNotNull);
      expect(w.update(active: tollStep(endLat: 23.40)), isNotNull);
    });

    test('a new destination starts over', () {
      final w = TollWatcher();
      final t = tollStep();
      w.update(active: t);
      w.reset();
      expect(w.update(active: t), same(t));
    });

    test('the toll flag is read from the directions step', () {
      Map<String, dynamic> j(Object? toll) => {'instruction': 'x', 'startLat': 1, 'startLng': 1, 'endLat': 2, 'endLng': 2, 'toll': toll};
      expect(NavStep.fromJson(j(true))!.toll, isTrue);
      expect(NavStep.fromJson(j(false))!.toll, isFalse);
      expect(NavStep.fromJson(j(null))!.toll, isFalse);
    });

    test('place and report state are read from the server', () {
      final t = TollEntry.fromJson({'id': 'a', 'amount': 95, 'place': 'Kherki Daula Toll Plaza', 'reported': true});
      expect(t.place, 'Kherki Daula Toll Plaza');
      expect(t.reported, isTrue);
      expect(TollEntry.fromJson({'id': 'b', 'amount': 5}).reported, isFalse);
    });

    test('the spoken prompt, in both languages', () {
      expect(NavAnnouncer.tollPhrase(VoiceLanguage.english), 'You are on a toll road. Add the toll in the app when you pay it.');
      expect(NavAnnouncer.tollPhrase(VoiceLanguage.hindi), contains('टोल'));
    });

    test('tolls are parsed from the resumed ride, and bad entries dropped', () {
      final p = RideProgress.fromJson({'tolls': [..._two, {'id': '', 'amount': 5}, {'id': 't9', 'amount': 0}], 'tollCharge': 170});
      expect(p.tolls.map((t) => t.id), ['t1', 't2']);
      expect(p.tollCharge, 170);
      expect(TollEntry.total(p.tolls), 170);
    });
  });

  // ── On the trip ──
  RideRequestModel outstation({String payment = 'cash', List<Map<String, dynamic>> tolls = const [], bool awaiting = false, String status = 'ongoing'}) =>
      shell.ride(service: 'outstation', status: status, paymentMode: payment,
          progress: RideProgress.fromJson({'tolls': tolls, 'tollCharge': tolls.fold<num>(0, (s, t) => s + (t['amount'] as num)), 'awaitingPayment': awaiting}));

  Future<http.Response?> Function(http.Request) server({List<Map<String, dynamic>>? after, String? error, bool offline = false}) =>
      (req) async {
        if (!req.url.path.endsWith('/toll')) return null;
        if (offline) throw http.ClientException('offline');
        if (error != null) return http.Response(jsonEncode({'error': error}), 409);
        final list = after ?? const [];
        return http.Response(jsonEncode({'success': true, 'tolls': list,
          'tollCharge': list.fold<num>(0, (s, t) => s + (t['amount'] as num))}), 200);
      };

  testWidgets('tolls already entered show on a reopened trip, with the total pinned', (tester) async {
    await shell.openScreen(tester, onRide: outstation(tolls: _two));
    // Mid-drive the map leads and the details are folded; the total is not.
    expect(find.text('+₹170 toll'), findsOneWidget, reason: 'in the status strip, where it cannot scroll away');
    expect(find.textContaining('Toll 1'), findsNothing);
    await shell.showDetails(tester);
    expect(find.text('Tolls'), findsOneWidget);
    expect(find.text('₹170'), findsOneWidget);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    expect(find.textContaining('Toll 2'), findsOneWidget);
    await shell.teardown(tester);
  });

  testWidgets('a taxi ride has no tolls at all', (tester) async {
    await shell.openScreen(tester, onRide: shell.ride(status: 'ongoing'));
    expect(find.text('Tolls'), findsNothing);
    expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onTollRoad, isNull);
    await shell.teardown(tester);
  });

  testWidgets('no tolls before the outstation trip has started', (tester) async {
    await shell.openScreen(tester, onRide: outstation(status: 'accepted'));
    expect(find.text('Tolls'), findsNothing);
    expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onTollRoad, isNull);
    await shell.teardown(tester);
  });

  testWidgets('reaching a toll road asks; No toll dismisses it', (tester) async {
    await shell.openScreen(tester, onRide: outstation());
    tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onTollRoad!(tollStep());
    await tester.pump();
    expect(find.text('Toll road. Paying a toll here? Add it.'), findsOneWidget);
    await tester.tap(find.text('No toll'));
    await tester.pump();
    expect(find.text('Toll road. Paying a toll here? Add it.'), findsNothing);
    await shell.teardown(tester);
  });

  testWidgets('adding from the prompt sends the amount, where the toll road was reached, and a retry-safe reference', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(), log: log,
        override: server(after: [{'id': 'n1', 'amount': 85, 'at': '2026-09-22T06:30:00.000Z', 'source': 'prompt'}]));
    final step = tollStep();
    final map = tester.widget<NavMapPanel>(find.byType(NavMapPanel));
    map.onPosition!(const LatLng(28.3901, 76.9802));   // at the toll road
    map.onTollRoad!(step);
    map.onPosition!(const LatLng(28.4500, 77.0100));   // driven on since
    await tester.pump();
    await shell.act(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add toll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '85');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    final body = last(log, '/toll')!.body;
    expect(body['action'], 'add');
    expect(body['amount'], 85);
    expect(body['source'], 'prompt');
    expect(body['lat'], 28.3901, reason: 'where the toll road was reached, not where the driver is now');
    expect(body['lng'], 76.9802);
    expect((body['clientRef'] as String).isNotEmpty, isTrue);
    await shell.showDetails(tester);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    expect(find.text('Toll road. Paying a toll here? Add it.'), findsNothing, reason: 'answered');
    await shell.teardown(tester);
  });

  testWidgets('a toll added by hand is placed where the driver is', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(), log: log, override: server(after: [{'id': 'm1', 'amount': 40}]));
    tester.widget<NavMapPanel>(find.byType(NavMapPanel)).onPosition!(const LatLng(23.2001, 72.6302));
    await shell.scrollSheet(tester);
    await shell.act(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Add toll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '40');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    final body = last(log, '/toll')!.body;
    expect(body['source'], 'manual');
    expect(body['lat'], 23.2001);
    expect(body['lng'], 72.6302);
    await shell.teardown(tester);
  });

  testWidgets('each toll shows where it was paid, and when the rider reported it', (tester) async {
    await shell.openScreen(tester, onRide: outstation(tolls: [
      {'id': 't1', 'amount': 95, 'place': 'Kherki Daula Toll Plaza, NH 48, Gurugram', 'reported': true},
      {'id': 't2', 'amount': 85, 'place': 'Shahjahanpur Toll Plaza, NH 48'},
    ]));
    await shell.scrollSheet(tester);
    expect(find.text('Kherki Daula Toll Plaza, NH 48, Gurugram'), findsOneWidget);
    expect(find.text('Shahjahanpur Toll Plaza, NH 48'), findsOneWidget);
    expect(find.text('Reported by the rider — support will review it'), findsOneWidget);
    await shell.teardown(tester);
  });

  for (final (label, typed, message) in [
    ('empty', '', 'Enter the toll amount'),
    ('zero', '0', 'Enter the toll amount'),
    ('over the cap', '2500', 'A single toll cannot be more than ₹2000'),
  ]) {
    testWidgets('an $label amount is refused before anything is sent', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, onRide: outstation(), log: log, override: server());
      await shell.scrollSheet(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Add toll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(last(log, '/toll'), isNull);
      await shell.teardown(tester);
    });
  }

  testWidgets('a refused toll is reported and not shown as added', (tester) async {
    await shell.openScreen(tester, onRide: outstation(), override: server(error: 'Tolls can only be changed while the trip is in progress'));
    await shell.scrollSheet(tester);
    await shell.act(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Add toll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    expect(find.text('Could not add the toll: Tolls can only be changed while the trip is in progress'), findsOneWidget);
    expect(find.textContaining('Toll 1'), findsNothing);
    await shell.teardown(tester);
  });

  // A dropped connection may still have reached the server: the retry must be
  // recognisable as the same toll.
  testWidgets('offline: Retry resends with the same reference', (tester) async {
    final log = <shell.ApiCall>[];
    var offline = true;
    await shell.openScreen(tester, onRide: outstation(), log: log, override: (req) async {
      if (!req.url.path.endsWith('/toll')) return null;
      if (offline) throw http.ClientException('offline');
      return http.Response(jsonEncode({'success': true, 'tolls': [{'id': 'n1', 'amount': 60}], 'tollCharge': 60}), 200);
    });
    await shell.scrollSheet(tester);
    await shell.act(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Add toll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Toll of ₹60 not saved — no connection'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));   // any exit animation, done
      expect(find.text('Toll of ₹60 not saved — no connection'), findsOneWidget,
          reason: 'an unsaved toll stays in front of the driver until it is retried');
      offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    final sent = log.where((c) => c.url.path.endsWith('/toll')).toList();
    expect(sent, hasLength(2));
    expect(sent[1].body['clientRef'], sent[0].body['clientRef']);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    await shell.teardown(tester);
  });

  testWidgets('removing a toll asks first, then sends its id', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(tolls: _two), log: log, override: server(after: [_two[1]]));
    await shell.scrollSheet(tester);
    await shell.act(() async {
      await tester.tap(find.byTooltip('Remove toll 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Remove toll 1?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    expect(last(log, '/toll')!.body, {'action': 'remove', 'tollId': 't1'});
    expect(find.textContaining('Toll 2'), findsNothing);
    expect(find.text('₹85'), findsWidgets);
    await shell.teardown(tester);
  });

  // ── Ending the trip ──
  testWidgets('cash: the fare and the tolls are collected together', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(tolls: _two), log: log);
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe to collect ₹125169');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Fare + tolls'), findsOneWidget);
      expect(find.text('₹125169.0'), findsOneWidget);
      await collectFare(tester);
      await tester.pump(const Duration(milliseconds: 500));
    });
    expect(shell.posts(log, '/complete'), hasLength(1));
    expect(find.text('INVOICE toll ₹170'), findsOneWidget);
    await shell.teardown(tester);
  });

  testWidgets('online: the tolls are collected in hand, then payment is requested', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(payment: 'online', tolls: _two), log: log);
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe to collect toll & request payment');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Collect tolls from the rider'), findsOneWidget);
      expect(find.text('₹170.0'), findsOneWidget);
      expect(shell.posts(log, '/request-payment'), isEmpty, reason: 'not before the tolls are in hand');
      await collectFare(tester);
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(shell.posts(log, '/request-payment'), hasLength(1));
    await shell.teardown(tester);
  });

  testWidgets('online with no tolls requests payment straight away', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, onRide: outstation(payment: 'online'), log: log);
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe to request payment');
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.byType(CollectFarePage), findsNothing);
    expect(shell.posts(log, '/request-payment'), hasLength(1));
    await shell.teardown(tester);
  });

  testWidgets('backing out of collecting leaves the tolls editable', (tester) async {
    await shell.openScreen(tester, onRide: outstation(tolls: _two));
    await shell.act(() async {
      await shell.swipe(tester, 'Swipe to collect ₹125169');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
    await shell.scrollSheet(tester);
    expect(find.widgetWithText(TextButton, 'Add toll'), findsOneWidget);
    expect(find.byTooltip('Remove toll 1'), findsOneWidget);
    await shell.teardown(tester);
  });

  testWidgets('reopened after payment was requested: tolls are read-only', (tester) async {
    await shell.openScreen(tester, onRide: outstation(payment: 'online', tolls: _two, awaiting: true));
    await shell.scrollSheet(tester);
    expect(find.textContaining('Toll 1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add toll'), findsNothing);
    expect(find.byTooltip('Remove toll 1'), findsNothing);
    await shell.teardown(tester);
  });

  // ── The driver's invoice ──
  group('invoice', () {
    Future<void> open(WidgetTester tester, RideCompletionArgs args) async {
      await tester.pumpWidget(MaterialApp(
        routes: {'/home': (_) => const SizedBox()},
        home: Builder(builder: (c) {
          WidgetsBinding.instance.addPostFrameCallback((_) =>
              Navigator.push(c, MaterialPageRoute(builder: (_) => const InvoicePage(), settings: RouteSettings(arguments: args))));
          return const SizedBox();
        }),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('shows the tolls collected, apart from the earning', (tester) async {
      await open(tester, RideCompletionArgs(outstation(), driverEarning: 4000, adminProfit: 1000, tollCollected: 170));
      expect(find.text('₹4000'), findsOneWidget);
      expect(find.text('Toll collected from rider'), findsOneWidget);
      expect(find.text('₹170'), findsOneWidget);
    });

    testWidgets('no toll row when there were none', (tester) async {
      await open(tester, RideCompletionArgs(outstation(), driverEarning: 4000, adminProfit: 1000));
      expect(find.text('Toll collected from rider'), findsNothing);
    });
  });
}
