import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/account/pages/preferences_page.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/home/widgets/driver_island.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/widgets/ride_shell.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';

// v1.5.2: booked for someone else, the home Dynamic Island + stat pills, the
// red top-up banner and the full-page trip preferences grid.

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> _feed({Map<String, dynamic> extra = const {}}) => {
  'id': 'r1', 'service': 'taxi', 'riderName': 'Rahul', 'vehicleType': 'Cab',
  'pickupAddress': 'Law Garden, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 120, 'totalFare': 120, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
  ...extra,
};

void _phone(WidgetTester tester, [Size size = const Size(400, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  // ── 1. Booked for someone else ──────────────────────────────────────────
  group('booked for someone else', () {
    test('feed: bookingFor other carries the passenger; the call goes to them', () {
      final m = RideRequestModel.fromJson(_feed(extra: {
        'bookingFor': 'other', 'passengerName': 'Asha', 'passengerPhone': '9000000002', 'riderPhone': '9000000001',
      }));
      expect(m.isForOther, isTrue);
      expect(m.travellerName, 'Asha');
      expect(m.callPhone, '9000000002');
      expect(m.userPhone, '9000000001', reason: 'the rider keeps their own phone');
    });

    test('no passenger phone (pending feed): the call falls back to the rider', () {
      final m = RideRequestModel.fromJson(_feed(extra: {
        'bookingFor': 'other', 'passengerName': 'Asha', 'riderPhone': '9000000001'}));
      expect(m.isForOther, isTrue);
      expect(m.callPhone, '9000000001');
    });

    test('self: passenger fields are ignored even when sent', () {
      final m = RideRequestModel.fromJson(_feed(extra: {
        'bookingFor': 'self', 'passengerName': 'Asha', 'passengerPhone': '9000000002', 'riderPhone': '9000000001'}));
      expect(m.isForOther, isFalse);
      expect(m.passengerName, '');
      expect(m.travellerName, 'Rahul');
      expect(m.callPhone, '9000000001');
      // An older server without the fields at all.
      final old = RideRequestModel.fromJson(_feed());
      expect(old.bookingFor, 'self');
      expect(old.isForOther, isFalse);
    });

    test('other with a blank passenger name is treated as self', () {
      final m = RideRequestModel.fromJson(_feed(extra: {'bookingFor': 'other', 'passengerName': '  '}));
      expect(m.isForOther, isFalse);
      expect(bookedForLabel(m), isNull);
    });

    test('request-card label', () {
      expect(bookedForLabel(RideRequestModel.fromJson(_feed(extra: {'bookingFor': 'other', 'passengerName': 'Asha'}))),
          'For: Asha (booked by Rahul)');
      expect(bookedForLabel(RideRequestModel.fromJson(_feed())), isNull);
    });

    test('trip contact: the passenger, called on their phone, with "booked by"', () {
      final other = RideContact.forRide(RideRequestModel.fromJson(_feed(extra: {
        'bookingFor': 'other', 'passengerName': 'Asha', 'passengerPhone': '9000000002', 'riderPhone': '9000000001'})));
      expect(other.name, 'Asha');
      expect(other.phone, '9000000002');
      expect(other.role, 'Passenger');
      expect(other.bookedBy, 'Rahul');
      final self = RideContact.forRide(
          RideRequestModel.fromJson(_feed(extra: {'riderPhone': '9000000001'})), role: 'Sender');
      expect(self.name, 'Rahul');
      expect(self.phone, '9000000001');
      expect(self.role, 'Sender');
      expect(self.bookedBy, '');
    });

    testWidgets('the request card shows "For: Asha (booked by Rahul)"', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: IncomingRequestsPage()));
        await _pumpFor(tester, 500);
        expect(find.text('For: Asha (booked by Rahul)'), findsOneWidget);
        expect(find.byKey(const ValueKey('booked_for_r1')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async => _json(req.url.path.endsWith('/rides/driver/pending')
          ? {'rides': [_feed(extra: {'bookingFor': 'other', 'passengerName': 'Asha'})]}
          : {})));
      while (tester.takeException() != null) {}
    });

    testWidgets('a self booking has no "For:" chip', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: IncomingRequestsPage()));
        await _pumpFor(tester, 500);
        expect(find.textContaining('For: '), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async =>
          _json(req.url.path.endsWith('/rides/driver/pending') ? {'rides': [_feed()]} : {})));
      while (tester.takeException() != null) {}
    });
  });

  // ── 2/3. Island stats ───────────────────────────────────────────────────
  group('island stats', () {
    final now = DateTime.utc(2026, 11, 26, 12);

    test('timeAgo', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 12)), now: now), '12m ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2d ago');
    });

    test('acceptance rate only when something was offered', () {
      expect(acceptanceRate({'offers': 10, 'accepts': 7}), 70);
      expect(acceptanceRate({'offers': 0, 'accepts': 0}), isNull);
      expect(acceptanceRate(null), isNull);
      expect(acceptanceRate({'offers': 3, 'accepts': 5}), 100, reason: 'clamped');
    });

    test('last trip: newest completed, driver earning over fare', () {
      final t = LastTrip.fromHistory({'rides': [
        {'status': 'cancelled', 'totalFare': 99, 'createdAt': '2026-11-26T11:00:00Z'},
        {'status': 'completed', 'driverEarning': 212, 'totalFare': 250, 'completedAt': '2026-11-26T11:30:00Z'},
      ]})!;
      expect(t.amount, 212);
      expect(t.isEarning, isTrue);
      expect(t.at!.isAtSameMomentAs(DateTime.utc(2026, 11, 26, 11, 30)), isTrue);
      final fareOnly = LastTrip.fromHistory({'rides': [{'status': 'completed', 'totalFare': 180}]})!;
      expect(fareOnly.amount, 180);
      expect(fareOnly.isEarning, isFalse);
      expect(LastTrip.fromHistory({'rides': []}), isNull);
      expect(LastTrip.fromHistory({}), isNull);
    });

    test('stats are real or plainly unknown — never invented', () {
      final loading = islandStats(summary: const {}, lastTripLoading: true, now: now);
      expect(loading.map((s) => s.id), ['today', 'last', 'week', 'wallet', 'rating']);
      expect(loading.firstWhere((s) => s.id == 'wallet').value, '…');
      expect(loading.firstWhere((s) => s.id == 'last').value, '…');
      expect(loading.firstWhere((s) => s.id == 'rating').value, '—');

      final full = islandStats(
        summary: const {'today': '₹ 356', 'week': '₹1900', 'todayRides': '4'},
        lastTrip: LastTrip(amount: 212, isEarning: true, at: now.subtract(const Duration(minutes: 8))),
        walletBalance: 540,
        dispatchStats: const {'offers': 20, 'accepts': 17},
        rating: '4.8',
        now: now,
      );
      String v(String id) => full.firstWhere((s) => s.id == id).value;
      String sub(String id) => full.firstWhere((s) => s.id == id).sub;
      expect(v('today'), '₹356');
      expect(sub('today'), '4 trips');
      expect(v('last'), '₹212');
      expect(sub('last'), '8m ago');
      expect(v('week'), '₹1900');
      expect(v('wallet'), '₹540');
      expect(v('accept'), '85%');
      expect(full.any((s) => s.id == 'rating'), isFalse, reason: 'acceptance takes the fifth pill when known');

      final none = islandStats(summary: const {'today': '₹ 0'}, walletBalance: -20, rating: '0');
      expect(none.firstWhere((s) => s.id == 'last').value, '—');
      expect(none.firstWhere((s) => s.id == 'last').sub, 'No trips yet');
      expect(none.firstWhere((s) => s.id == 'wallet').sub, 'top up');
    });

    // Home builds the island already open (a new element when it widens): the
    // last trip must still load — it used to sit on "loading" on a device.
    testWidgets('island built already open still loads the last trip', (tester) async {
      _phone(tester, const Size(400, 800));
      var historyCalls = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: DriverIsland(
          summary: const {'today': '₹ 356', 'week': '₹642', 'todayRides': '2', 'totalDistance': '12 km'},
          loaded: true,
          open: true,
          fullWidth: 372,
          onToggle: () {},
          onTopUp: () {},
          onSeeEarnings: () {},
          walletBalance: 540,
          rating: '4.8',
        )))));
        await _pumpFor(tester, 800);
      }, () => MockClient((req) async {
        if (req.url.path.endsWith('/rides/driver/history')) {
          historyCalls++;
          return _json({'rides': [
            {'status': 'completed', 'driverEarning': 164, 'completedAt': DateTime.now().toUtc().toIso8601String()},
          ]});
        }
        return _json({});
      }));
      expect(historyCalls, 1);
      expect(find.text('₹164'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    });

    testWidgets('island: tap expands into stats + Top up, tap again collapses', (tester) async {
      _phone(tester, const Size(400, 800));
      var topUps = 0;
      var open = false;
      var historyCalls = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (ctx, set) => Center(
          child: DriverIsland(
            summary: const {'today': '₹ 356', 'week': '₹1900', 'todayRides': '4', 'totalDistance': '23 km'},
            loaded: true,
            open: open,
            fullWidth: 372,
            onToggle: () => set(() => open = !open),
            onTopUp: () => topUps++,
            onSeeEarnings: () {},
            walletBalance: 540,
            rating: '4.8',
          ),
        )))));
        expect(find.text('₹ 356'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.byKey(const ValueKey('island_stats')), findsNothing);

        await tester.tap(find.text('Today'));
        await _pumpFor(tester, 800);
        expect(find.byKey(const ValueKey('island_expanded')), findsOneWidget);
        expect(find.text("TODAY'S EARNINGS"), findsOneWidget);
        expect(find.byKey(const ValueKey('island_stat_last')), findsOneWidget);
        expect(find.text('₹212'), findsOneWidget, reason: 'last trip from /rides/driver/history');
        expect(find.text('₹540', skipOffstage: false), findsOneWidget, reason: 'wallet balance');
        expect(historyCalls, 1);

        await tester.tap(find.byKey(const ValueKey('island_top_up')));
        expect(topUps, 1);

        await tester.tap(find.text("TODAY'S EARNINGS"));
        await _pumpFor(tester, 800);
        expect(find.byKey(const ValueKey('island_expanded')), findsNothing);
        expect(find.text('Today'), findsOneWidget);
      }, () => MockClient((req) async {
        if (req.url.path.endsWith('/rides/driver/history')) {
          historyCalls++;
          return _json({'rides': [
            {'status': 'completed', 'driverEarning': 212, 'completedAt': DateTime.now().toUtc().toIso8601String()},
          ]});
        }
        return _json({});
      }));
      expect(tester.takeException(), isNull);
    });

    testWidgets('home: the island opens and a tap outside closes it', (tester) async {
      _phone(tester, const Size(400, 860));
      await http.runWithClient(() async {
        final dp = DriverProvider();
        await dp.loadProfile();
        await tester.pumpWidget(ChangeNotifierProvider.value(value: dp, child: const MaterialApp(home: HomePage())));
        await _pumpFor(tester);
        await tester.tap(find.text('Today'));
        await _pumpFor(tester, 800);
        expect(find.byKey(const ValueKey('island_expanded')), findsOneWidget);
        expect(find.text('2 trips'), findsWidgets, reason: "today's trips, not the all-time count");
        await tester.tapAt(const Offset(200, 420));
        await _pumpFor(tester, 800);
        expect(find.byKey(const ValueKey('island_expanded')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/rides/driver/summary')) {
          return _json({'today': 356, 'week': 1900, 'todayRides': 2, 'totalRides': 812, 'todayDistance': 23});
        }
        if (p.endsWith('/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
        if (p.endsWith('/auth/driver/wallet')) return _json({'balance': 500, 'transactions': []});
        if (p.endsWith('/rides/driver/active')) return _json({'ride': null});
        return _json({});
      }));
      while (tester.takeException() != null) {}
    });
  });

  // ── 2. Top-up banner ────────────────────────────────────────────────────
  group('top-up banner', () {
    testWidgets('red gradient, white text, Top up pill and body tap are separate', (tester) async {
      var body = 0, topUp = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: TopUpBanner(negative: false, onTap: () => body++, onTopUp: () => topUp++),
      ))));
      expect(find.text('Low wallet balance'), findsOneWidget);
      final box = tester.widget<Container>(find.byKey(const ValueKey('top_up_banner')));
      final g = (box.decoration as BoxDecoration).gradient as LinearGradient;
      expect(g.colors, const [Color(0xFFE53935), Color(0xFFB71C1C)]);
      expect(tester.widget<Text>(find.text('Low wallet balance')).style?.color, Colors.white);
      await tester.tap(find.text('Top up'));
      expect(topUp, 1);
      expect(body, 0);
      await tester.tap(find.text('Low wallet balance'));
      expect(body, 1);
    });
  });

  // ── 4. Trip preferences page ────────────────────────────────────────────
  group('trip preferences grid', () {
    final sent = <Map<String, dynamic>>[];
    MockClient api({bool allowHire = true}) => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/ride-preferences')) return _json({'preferences': []});
      if (p.endsWith('/auth/driver/profile')) {
        return _json({'driver': {'_id': 'd1', 'acceptsRental': true, 'acceptsOutstation': false,
          'allowHireDriver': allowHire}});
      }
      if (p.endsWith('/auth/driver/preferences') && req.method == 'POST') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        sent.add(b);
        return _json({'success': true, 'preferences': b});
      }
      return _json({});
    });

    setUp(sent.clear);

    testWidgets('cards toggle, disallowed is locked, Save sends and shows saved', (tester) async {
      _phone(tester, const Size(400, 1000));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PreferencesPage()));
        await _pumpFor(tester);
        expect(find.text('Trip preferences'), findsOneWidget);
        expect(find.byType(GridView), findsNothing, reason: 'a SliverGrid inside the page scroll');
        for (final k in ['taxi', 'rental', 'outstation', 'hire_driver', 'delivery']) {
          expect(find.byKey(ValueKey('svc_card_$k')), findsOneWidget);
        }
        // Rental on (from the profile), outstation off.
        Finder check(String k, IconData i) =>
            find.descendant(of: find.byKey(ValueKey('svc_card_$k')), matching: find.byIcon(i));
        expect(check('rental', Icons.check_circle_rounded), findsOneWidget);
        expect(check('outstation', Icons.radio_button_unchecked_rounded), findsOneWidget);
        expect(find.text('All changes saved'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('svc_card_outstation')));
        await tester.pump();
        expect(check('outstation', Icons.check_circle_rounded), findsOneWidget);
        expect(find.text('You have unsaved changes'), findsOneWidget);

        await tester.tap(find.text('Save Preferences'));
        await _pumpFor(tester);
        expect(sent, hasLength(1));
        expect(sent.single['acceptsOutstation'], isTrue);
        expect(sent.single['acceptsRental'], isTrue);
        expect(find.text('All changes saved'), findsOneWidget);
      }, () => api());
    });

    testWidgets('a service the admin disallowed: "Not enabled by admin", not pickable', (tester) async {
      _phone(tester, const Size(400, 1000));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PreferencesPage()));
        await _pumpFor(tester);
        expect(find.text('Not enabled by admin'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('svc_card_hire_driver')),
            matching: find.byIcon(Icons.lock_rounded)), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('svc_card_hire_driver')));
        await tester.pump();
        expect(find.text('All changes saved'), findsOneWidget, reason: 'nothing changed');
      }, () => api(allowHire: false));
    });

    testWidgets('home "Trip preferences" opens the full page', (tester) async {
      _phone(tester, const Size(400, 860));
      await http.runWithClient(() async {
        final dp = DriverProvider();
        await tester.pumpWidget(ChangeNotifierProvider.value(value: dp, child: MaterialApp(
          home: const HomePage(),
          routes: {'/preferences': (_) => const Scaffold(body: Text('PREFS PAGE'))},
        )));
        await _pumpFor(tester);
        await tester.tap(find.text('Trip preferences'));
        await _pumpFor(tester, 500);
        expect(find.text('PREFS PAGE'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async => req.url.path.endsWith('/rides/driver/active')
          ? _json({'ride': null})
          : _json({})));
      while (tester.takeException() != null) {}
    });
  });

  // ── 5. Account hero keeps its live figures ──────────────────────────────
  testWidgets('account hero: name, rating and trips on the gradient card', (tester) async {
    _phone(tester, const Size(400, 2400));
    final dp = DriverProvider();
    await http.runWithClient(() => dp.loadProfile(), () => MockClient((req) async {
      if (req.url.path.endsWith('/auth/driver/profile')) {
        return _json({'driver': {'_id': 'd1', 'name': 'Suresh Kumar', 'rating': 4.7, 'totalRides': 12}});
      }
      if (req.url.path.endsWith('/auth/driver/wallet')) return _json({'balance': 75, 'transactions': []});
      return _json({});
    }));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: dp, child: const MaterialApp(home: AccountPage())));
    await tester.pump();
    expect(find.text('Suresh Kumar'), findsOneWidget);
    expect(find.text('CAPTAIN'), findsOneWidget);
    expect(find.text('4.7'), findsNWidgets(2));
    expect(find.text('12 trips'), findsOneWidget);
    expect(find.text('₹ 75.00'), findsOneWidget);
    while (tester.takeException() != null) {}
  });
}
