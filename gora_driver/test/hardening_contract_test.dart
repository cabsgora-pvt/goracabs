import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/history/bloc/history_bloc.dart';
import 'package:gora_driver/features/history/pages/history_page.dart';
import 'package:gora_driver/features/home/bloc/home_bloc.dart';
import 'package:gora_driver/features/home/logic/feed_status.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/ride/bloc/ride_bloc.dart';
import 'package:gora_driver/features/ride/logic/accept_outcome.dart';
import 'package:gora_driver/features/ride/logic/dismissed_requests.dart';
import 'package:gora_driver/features/ride/logic/job_settlement.dart';
import 'package:gora_driver/features/ride/logic/ride_actions.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/pages/hire_progress_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/ride/pages/on_ride_page.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';
import 'package:gora_driver/features/wallet/bloc/wallet_bloc.dart';
import 'package:gora_driver/features/wallet/pages/withdraw_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';
import 'package:gora_driver/services/driver_api_service.dart';
import 'package:gora_driver/services/driver_payment_service.dart';
import 'package:gora_driver/services/location_ping.dart';
import 'package:gora_driver/services/ride_alert_service.dart';
import 'package:gora_driver/services/session.dart';

import 'ride_shell_test.dart' as shell;

// ─────────────────────────────────────────────────────────────────────────────
// The app against the hardened backend contracts, and the audit's bug fixes.
// Every server reply here is shaped like the goraadmin route that sends it.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final calls = <http.Request>[];
typedef Api = FutureOr<http.Response?> Function(http.Request req);
Api api = (_) => null;

MockClient get _client => MockClient((req) async {
      calls.add(req);
      return await api(req) ?? _json({});
    });

Future<T> withApi<T>(Future<T> Function() body) => http.runWithClient(body, () => _client);

bool _is(http.Request r, String method, String pathEnd) => r.method == method && r.url.path.endsWith(pathEnd);
List<http.Request> _sent(String method, String pathEnd) => calls.where((r) => _is(r, method, pathEnd)).toList();
Map<String, dynamic> _body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void phone(WidgetTester tester, [Size size = const Size(400, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget home, {Map<String, WidgetBuilder>? routes, GlobalKey<NavigatorState>? nav}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => DriverProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: BlocProvider(
    create: (_) => AuthBloc(),
    child: MaterialApp(
      navigatorKey: nav,
      theme: AppTheme.light,
      routes: {...AppRoutes.routes, ...?routes},
      home: home,
    ),
  ),
);

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
  while (tester.takeException() != null) {}
}

Map<String, dynamic> request(String id, {String service = 'taxi', Map<String, dynamic> extra = const {}}) => {
  'id': id, 'service': service, 'riderName': 'Rahul Mehta', 'vehicleType': 'Bike',
  'pickupAddress': 'Law Garden, Ellisbridge, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 85, 'totalFare': 85, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
  ...extra,
};

/// The trip screen stand-in: shows which ride it was opened with, and the
/// rider's phone (only the active-ride reply carries it now).
final tripRoute = <String, WidgetBuilder>{
  OnRidePage.route: (ctx) {
    final a = ModalRoute.of(ctx)!.settings.arguments as RideRequestModel;
    return Scaffold(body: Text('TRIP ${a.id} ${a.userPhone}'));
  },
};

Future<void> slideAccept(WidgetTester tester) async {
  final track = find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Slide to accept').first;
  await tester.ensureVisible(track);
  await tester.pump();
  final rect = tester.getRect(track);
  final g = await tester.startGesture(Offset(rect.left + 29, rect.center.dy));
  for (var i = 0; i < 10; i++) {
    await g.moveBy(Offset(rect.width / 10, 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await g.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Position fix({required DateTime at}) => Position(
  latitude: 23.03, longitude: 72.56, timestamp: at, accuracy: 5, altitude: 0,
  altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);

int starts = 0, stops = 0;

void main() {
  setUp(() {
    calls.clear();
    api = (_) => null;
    starts = 0;
    stops = 0;
    RideAlertService.startImpl = () async { starts++; return true; };
    RideAlertService.stopImpl = () async { stops++; };
    DriverApiService.onUnauthorized = null;
    DriverApiService.resetUnauthorized();
    DismissedRequests.clear();
    feedBlock.value = null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
        (c) async => c.method == 'isLocationServiceEnabled' ? false : null);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
  });

  // ── 1. Accept ───────────────────────────────────────────────────────────────
  group('accept refusals', () {
    test('each code: a clear message and what happens to the card', () {
      AcceptOutcome o(String code, int status, [Map<String, dynamic> extra = const {}]) =>
          acceptOutcome({'error': 'server text', 'code': code, '_status': status, ...extra});
      for (final c in ['NOT_APPROVED', 'FACE_VERIFICATION_REQUIRED', 'ACCOUNT_HOLD', 'OFFLINE', 'WALLET_BLOCKED']) {
        expect(o(c, 403).action, AcceptAction.closeAll, reason: c);
        expect(o(c, 403).message, acceptMessages[c], reason: c);
      }
      expect(o('DRIVER_BUSY', 409).action, AcceptAction.closeAll);
      for (final c in ['VEHICLE_MISMATCH', 'SERVICE_NOT_ALLOWED', 'SERVICE_NOT_ENABLED', 'WRONG_ZONE',
          'OUT_OF_RANGE', 'CASH_PAUSED', 'FEMALE_DRIVER_REQUESTED', 'REJECTED', 'OFFERED_TO_OTHER', 'RIDE_TAKEN']) {
        expect(o(c, c.startsWith('RE') || c.startsWith('OFF') || c == 'RIDE_TAKEN' ? 409 : 403).action,
            AcceptAction.dropCard, reason: c);
        expect(acceptMessages[c], isNotNull, reason: c);
      }
      expect(o('NOT_OPEN_YET', 409).action, AcceptAction.dismissCard);
      expect(o('ACCEPT_IN_PROGRESS', 409).action, AcceptAction.keepCard);
      expect(o('', 403, {'accountHold': true}).action, AcceptAction.closeAll);
      expect(o('SOMETHING_NEW', 409).message, 'server text', reason: 'an unknown code shows the server text');
      expect(acceptOutcome({'success': true, 'ride': {}, 'repeated': true}).action, AcceptAction.open);
      expect(acceptOutcome({'error': 'Server error', '_status': 500}).action, AcceptAction.keepCard);
    });

    Future<void> openRequests(WidgetTester tester, List<Map<String, dynamic>> rides) async {
      phone(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(const Scaffold(body: Text('HOME')), routes: tripRoute, nav: nav));
      nav.currentState!.pushNamed(IncomingRequestsPage.route);
      await pumpFor(tester, 600);
      expect(find.text('Slide to accept'), findsWidgets);
    }

    testWidgets('409 RIDE_TAKEN: says so and takes that card off', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a'), request('b')]});
        if (r.url.path.endsWith('/rides/a/accept')) return _json({'error': 'Ride already taken', 'code': 'RIDE_TAKEN'}, 409);
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        expect(find.text('2 new requests'), findsOneWidget);
        await slideAccept(tester);
        await pumpFor(tester, 300);
        expect(find.text(acceptMessages['RIDE_TAKEN']!), findsOneWidget);
        expect(find.text('New trip request'), findsOneWidget, reason: 'one card left');
        await teardown(tester);
      });
    });

    testWidgets('403 WALLET_BLOCKED: no request can be taken, the screen closes', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a'), request('b')]});
        if (r.url.path.endsWith('/accept')) return _json({'error': 'Low wallet', 'code': 'WALLET_BLOCKED'}, 403);
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        await slideAccept(tester);
        await pumpFor(tester, 500);
        expect(find.byType(IncomingRequestsPage), findsNothing);
        expect(find.text('HOME'), findsOneWidget);
        expect(find.text(acceptMessages['WALLET_BLOCKED']!), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('409 ACCEPT_IN_PROGRESS: the card stays to retry', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a')]});
        if (r.url.path.endsWith('/accept')) return _json({'error': 'busy', 'code': 'ACCEPT_IN_PROGRESS'}, 409);
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        await slideAccept(tester);
        await pumpFor(tester, 400);
        expect(find.text(acceptMessages['ACCEPT_IN_PROGRESS']!), findsOneWidget);
        expect(find.byType(IncomingRequestsPage), findsOneWidget);
        expect(find.text('Slide to accept'), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('accepted: the trip opens with the phone from /rides/driver/active', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a')]});
        if (r.url.path.endsWith('/accept')) return _json({'success': true, 'ride': {'_id': 'a', 'status': 'accepted'}});
        if (r.url.path.endsWith('/rides/driver/active')) {
          return _json({'ride': {...request('a'), 'status': 'accepted', 'riderPhone': '+919800000001'}});
        }
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        await slideAccept(tester);
        await pumpFor(tester, 500);
        expect(find.text('TRIP a +919800000001'), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('accept timed out but the server assigned it: the trip opens', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a')]});
        if (r.url.path.endsWith('/accept')) throw TimeoutException('slow network');
        if (r.url.path.endsWith('/rides/driver/active')) {
          return _json({'ride': {...request('a'), 'status': 'accepted', 'riderPhone': '+919800000002'}});
        }
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        await slideAccept(tester);
        await pumpFor(tester, 500);
        expect(_sent('GET', '/rides/driver/active'), isNotEmpty, reason: 'asks before saying it failed');
        expect(find.text('TRIP a +919800000002'), findsOneWidget);
        expect(find.textContaining('Could not reach'), findsNothing);
        await teardown(tester);
      });
    });

    testWidgets('accept failed and the server has no such trip: says so, the card stays', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [request('a')]});
        if (r.url.path.endsWith('/accept')) throw http.ClientException('no route');
        if (r.url.path.endsWith('/rides/driver/active')) return _json({'ride': null});
        return null;
      };
      await withApi(() async {
        await openRequests(tester, []);
        await slideAccept(tester);
        await pumpFor(tester, 500);
        expect(find.textContaining('Could not reach the server'), findsOneWidget);
        expect(find.textContaining('TRIP'), findsNothing);
        expect(find.text('Slide to accept'), findsOneWidget);
        await teardown(tester);
      });
    });
  });

  // ── 2. Pending feed ─────────────────────────────────────────────────────────
  group('pending feed', () {
    test('flags read as a reason, not an empty list', () {
      expect(feedBlockFrom({'rides': []}), isNull);
      expect(feedBlockFrom({'rides': [], 'notApproved': true})!.kind, 'notApproved');
      expect(feedBlockFrom({'rides': [], 'offline': true})!.kind, 'offline');
      expect(feedBlockFrom({'rides': [], 'hold': true})!.kind, 'hold');
      expect(feedBlockFrom({'rides': [], 'busy': true})!.kind, 'busy');
      final w = feedBlockFrom({'rides': [], 'walletBlocked': true, 'reason': 'Low wallet balance (₹-600).'})!;
      expect(w.kind, 'walletBlocked');
      expect(w.message, 'Low wallet balance (₹-600).');
    });

    test('a feed row without phones still makes a request; scheduledAt is read', () {
      final m = RideRequestModel.fromJson(request('a', extra: {'scheduledAt': '2026-11-28T03:35:00.000Z'}));
      expect(m.userPhone, isEmpty);
      expect(m.scheduledAt, DateTime.utc(2026, 11, 28, 3, 35).toLocal());
      expect(scheduledLabel(DateTime(2026, 11, 28, 9, 5), now: DateTime(2026, 11, 24, 10)), 'Scheduled for 28 Nov, 9:05 AM');
      expect(scheduledLabel(DateTime(2026, 11, 24, 18, 30), now: DateTime(2026, 11, 24, 10)), 'Scheduled for Today, 6:30 PM');
      expect(scheduledLabel(DateTime(2026, 11, 25, 0, 0), now: DateTime(2026, 11, 24, 10)), 'Scheduled for Tomorrow, 12:00 AM');
    });

    testWidgets('a scheduled request card says when', (tester) async {
      phone(tester);
      final at = DateTime.now().add(const Duration(days: 3));
      api = (r) => r.url.path.endsWith('/rides/driver/pending')
          ? _json({'rides': [request('s', extra: {'scheduledAt': at.toUtc().toIso8601String()})]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const IncomingRequestsPage()));
        await pumpFor(tester, 500);
        expect(find.text(scheduledLabel(at)), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('online with a blocked feed: the home map shows why', (tester) async {
      phone(tester, const Size(400, 900));
      SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) {
          return _json({'rides': [], 'walletBlocked': true, 'reason': 'Low wallet balance (₹-650). Please recharge to receive ride requests.'});
        }
        if (r.url.path.endsWith('/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
        if (r.url.path.endsWith('/rides/driver/active')) return _json({'ride': null});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const HomePage()));
        await pumpFor(tester, 5000);
        expect(find.byType(FeedBlockBanner), findsOneWidget);
        expect(find.text('Wallet balance too low'), findsOneWidget);
        expect(find.textContaining('Low wallet balance (₹-650)'), findsOneWidget);
        expect(find.byType(IncomingRequestsPage), findsNothing);
        await teardown(tester);
      });
    });
  });

  // ── 3. OTP ──────────────────────────────────────────────────────────────────
  group('start OTP refusals', () {
    test('attempts left, locked, rate limited, missing', () {
      expect(otpErrorMessage({'code': 'OTP_INVALID', 'attemptsLeft': 3}), 'Wrong OTP. 3 attempts left.');
      expect(otpErrorMessage({'code': 'OTP_INVALID', 'attemptsLeft': 1}), 'Wrong OTP. 1 attempt left.');
      expect(otpErrorMessage({'code': 'OTP_LOCKED'}), contains('Ask the rider to contact support'));
      expect(otpErrorMessage({'code': 'OTP_RATE_LIMITED'}), contains('Wait a few minutes'));
      expect(otpErrorMessage({'code': 'OTP_MISSING'}), contains('contact support'));
    });

    Future<List<RideState>> start(Map<String, dynamic> reply, int status) async {
      api = (r) => r.url.path.endsWith('/start') ? _json(reply, status) : null;
      return withApi(() async {
        final bloc = RideBloc()..currentRide = shell.ride(status: 'arrived');
        final states = <RideState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(StartRideEvent('1234'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        await bloc.close();
        return states;
      });
    }

    test('400 OTP_INVALID → attempts left', () async {
      final s = await start({'error': 'Invalid OTP', 'code': 'OTP_INVALID', 'attemptsLeft': 2}, 400);
      final e = s.single as OtpErrorState;
      expect(e.message, 'Wrong OTP. 2 attempts left.');
      expect(e.locked, isFalse);
    });

    test('423 OTP_LOCKED → locked', () async {
      final s = await start({'error': 'locked', 'code': 'OTP_LOCKED', 'otpLocked': true}, 423);
      final e = s.single as OtpErrorState;
      expect(e.locked, isTrue);
      expect(e.message, otpLockedMessage);
    });

    testWidgets('a ride reopened with otpLocked asks for no code', (tester) async {
      final r = RideRequestModel.fromJson({...request('ride-1'), 'status': 'arrived', 'otpLocked': true, 'riderPhone': '+91 9'});
      expect(r.otpLocked, isTrue);
      await shell.openScreen(tester, onRide: r);
      await shell.act(() async {
        await tester.ensureVisible(find.text('Enter OTP to start ride'));
        await tester.tap(find.text('Enter OTP to start ride'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });
      expect(find.text(otpLockedMessage), findsOneWidget);
      expect(find.text('Enter Ride OTP'), findsNothing);
      await shell.teardown(tester);
    });

    test('arrived too far: "You are X km from pickup"', () {
      expect(rideActionError({'error': 'x', 'code': 'TOO_FAR_FROM_PICKUP', 'distanceKm': 2.345}),
          'You are 2.3 km from pickup. Get closer to mark arrived.');
      expect(rideActionError({'error': 'x', 'code': 'STOP_NOT_REACHED'}), 'Mark the stop as reached first.');
      expect(rideActionError({'error': 'plain server text'}), 'plain server text');
    });
  });

  // ── 4. History paging ───────────────────────────────────────────────────────
  group('history paging', () {
    List<Map<String, dynamic>> rides(int from, int n) => [
      for (var i = from; i < from + n; i++)
        {'_id': 'r$i', 'status': 'completed', 'totalFare': 100, 'createdAt': '2026-11-01T10:00:00Z', 'riderName': 'Rider $i'},
    ];

    test('first page, then the next one appended', () async {
      api = (r) {
        if (!r.url.path.endsWith('/rides/driver/history')) return null;
        final page = int.parse(r.url.queryParameters['page']!);
        expect(int.parse(r.url.queryParameters['limit']!), lessThanOrEqualTo(50));
        return _json({'rides': page == 1 ? rides(0, 50) : rides(50, 10), 'page': page, 'limit': 50, 'hasMore': page == 1});
      };
      await withApi(() async {
        final bloc = HistoryBloc()..add(LoadHistoryEvent());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        var s = bloc.state as HistoryLoaded;
        expect(s.trips, hasLength(50));
        expect(s.hasMore, isTrue);
        bloc.add(LoadMoreHistoryEvent());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        s = bloc.state as HistoryLoaded;
        expect(s.trips, hasLength(60));
        expect(s.hasMore, isFalse);
        expect(s.trips.last.id, 'r59');
        await bloc.close();
      });
      expect(_sent('GET', '/rides/driver/history').map((r) => r.url.queryParameters['page']), ['1', '2']);
    });

    testWidgets('the trip list has "Load more trips" while there are more', (tester) async {
      phone(tester, const Size(400, 900));
      api = (r) {
        if (!r.url.path.endsWith('/rides/driver/history')) return null;
        final page = int.parse(r.url.queryParameters['page']!);
        return _json({'rides': page == 1 ? rides(0, 3) : rides(3, 2), 'page': page, 'limit': 50, 'hasMore': page == 1});
      };
      await withApi(() async {
        await tester.pumpWidget(app(const HistoryPage()));
        await pumpFor(tester, 300);
        expect(find.text('Load more trips'), findsOneWidget);
        await tester.tap(find.text('Load more trips'));
        await pumpFor(tester, 300);
        expect(find.text('Load more trips'), findsNothing, reason: 'no more pages');
        expect(find.text('Rider 4'), findsOneWidget);
        await teardown(tester);
      });
    });
  });

  // ── 5. Failed delivery needs a photo ────────────────────────────────────────
  testWidgets('a failed delivery whose photo did not upload is not sent, and says why', (tester) async {
    phone(tester, const Size(400, 1000));
    api = (r) => r.url.path.endsWith('/upload') ? _json({'error': 'File too large'}, 413) : null;
    await withApi(() async {
      await tester.pumpWidget(app(DeliveryProgressPage(
        ride: shell.ride(service: 'delivery', status: 'ongoing', progress: const RideProgress(deliveryPhase: 'in_transit')),
        pickPhoto: () async => XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'door.jpg'),
      )));
      await pumpFor(tester, 300);
      final fail = find.text('Receiver unavailable — return to sender');
      await tester.ensureVisible(fail);
      await tester.tap(fail);
      await pumpFor(tester, 400);
      await tester.tap(find.text('Wrong address'));
      await pumpFor(tester, 400);
      await tester.tap(find.text('Take photo'));
      await pumpFor(tester, 600);
      expect(find.text('File too large'), findsOneWidget);
      expect(_sent('POST', '/delivery'), isEmpty, reason: 'PHOTO_REQUIRED: never sent without the photo');
      await teardown(tester);
    });
  });

  test('delivery refusal codes read clearly', () {
    expect(rideActionError({'code': 'PHOTO_REQUIRED', 'error': 'x'}), 'Take a photo to mark the delivery as failed.');
    expect(rideActionError({'code': 'NOT_COLLECTED', 'error': 'x'}), 'Collect the parcel first.');
    expect(rideActionError({'code': 'DELIVERY_FINISHED', 'error': 'x'}), 'This delivery is already finished.');
    expect(rideActionError({'code': 'NOT_ONGOING', 'error': 'x'}), contains('not in progress'));
  });

  // ── 6. Extension waits for the rider ────────────────────────────────────────
  testWidgets('extending a hire waits for the rider; booked hours do not change yet', (tester) async {
    final log = <shell.ApiCall>[];
    await shell.openScreen(tester, log: log, page: HireProgressPage(ride: shell.ride(service: 'hire_driver', status: 'ongoing',
        progress: const RideProgress(hireElapsedSec: 60))),
        override: (req) async => req.url.path.endsWith('/hire') && req.body.contains('extend')
            ? http.Response(jsonEncode({'success': true, 'awaitingRiderConfirmation': true,
                'pendingExtension': {'hours': 2, 'amount': 300, 'addKm': 0,
                  'expiresAt': DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String()}}), 200)
            : null);
    await shell.act(() async {
      await tester.tap(find.text('Extend hours'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('+2 hours'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(shell.posts(log, '/hire').last.body, {'action': 'extend', 'extraHours': 2});
    expect(find.text('Waiting for rider to confirm (₹300) — +2 hr'), findsWidgets);
    expect(find.text('0h 01m / 8h'), findsOneWidget, reason: 'nothing changes until the rider confirms');
    await shell.teardown(tester);
  });

  test('extra hours must be 1..12 whole hours', () {
    expect(validExtraHours(0), isFalse);
    expect(validExtraHours(1), isTrue);
    expect(validExtraHours(12), isTrue);
    expect(validExtraHours(13), isFalse);
    expect(extendOptions.every(validExtraHours), isTrue);
    expect(extensionFrom({'success': true}), isNull);
    expect(PendingExtension.tryParse({'hours': 2, 'amount': 300,
        'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String()}), isNull, reason: 'lapsed');
  });

  // ── 7. Ending and payment ───────────────────────────────────────────────────
  group('complete outcomes', () {
    // Everything inside the mock API's zone: the payment dialog's poll timer
    // is created during a later frame.
    Future<void> settle(WidgetTester tester, RideRequestModel ride) => withApi(() async {
      phone(tester, const Size(400, 1000));
      await tester.pumpWidget(app(Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async {
          final inv = await settleForInvoice(context, ride);
          if (inv != null && context.mounted) Navigator.pushNamed(context, InvoicePage.route, arguments: inv);
        },
        child: const Text('finish'),
      ))), routes: {
        InvoicePage.route: (ctx) {
          final a = ModalRoute.of(ctx)!.settings.arguments as RideCompletionArgs;
          return Scaffold(body: Text('INVOICE ₹${a.driverEarning}'));
        },
      }));
      await tester.tap(find.text('finish'));
      await pumpFor(tester, 500);
    });

    Map<String, dynamic> done(String mode, {String status = 'paid', Map<String, dynamic> extra = const {}}) => {
      'success': true, 'paymentMode': mode, 'paymentStatus': status, 'amountDue': 250, 'couponDiscount': 0,
      'awaitingPayment': status != 'paid', 'fare': 250, 'commissionPercent': 20, 'adminProfit': 50,
      'driverEarning': 200, 'driverWalletBalance': 900, 'codSettled': 0, ...extra,
    };

    testWidgets('cash: straight to the invoice', (tester) async {
      api = (r) => r.url.path.endsWith('/complete') ? _json(done('cash')) : null;
      await settle(tester, shell.ride(status: 'ongoing'));
      expect(find.text('INVOICE ₹200'), findsOneWidget);
    });

    testWidgets("wallet short: collect the cash the server switched it to", (tester) async {
      api = (r) => r.url.path.endsWith('/complete')
          ? _json(done('cash', extra: {'paymentSwitchedToCash': true, 'cashToCollect': 250}))
          : null;
      await settle(tester, shell.ride(status: 'ongoing', paymentMode: 'wallet'));
      expect(find.byType(CollectFarePage), findsOneWidget);
      expect(find.text(walletShortTitle(250)), findsOneWidget);
      expect(find.text("Rider's wallet was short — collect ₹250 in cash"), findsOneWidget);
      expect(find.text('₹250'), findsWidgets);
    });

    testWidgets('online: waits for the payment, or records that the rider paid cash', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/complete')) return _json(done('online', status: 'pending'));
        if (r.url.path.endsWith('/collect-cash')) {
          return _json({'success': true, 'paymentMode': 'cash', 'paymentStatus': 'paid', 'cashToCollect': 250,
            'commission': 50, 'driverWalletBalance': 850});
        }
        if (r.method == 'GET' && r.url.path.endsWith('/rides/ride-1')) return _json({'status': 'completed', 'paymentStatus': 'pending'});
        return null;
      };
      await settle(tester, shell.ride(status: 'ongoing', paymentMode: 'online'));
      expect(find.text('Waiting for online payment ₹250'), findsOneWidget);
      expect(find.text('INVOICE ₹200'), findsNothing, reason: 'not before the rider has paid');
      await withApi(() async {
        await tester.tap(find.text('Rider paid cash'));
        await pumpFor(tester, 300);
        await tester.tap(find.text('Cash collected'));
        await pumpFor(tester, 500);
      });
      expect(_sent('POST', '/collect-cash'), hasLength(1));
      expect(find.text('INVOICE ₹200'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('online: the rider pays in the app → invoice', (tester) async {
      var polls = 0;
      api = (r) {
        if (r.url.path.endsWith('/complete')) return _json(done('online', status: 'pending'));
        if (r.method == 'GET' && r.url.path.endsWith('/rides/ride-1')) {
          return _json({'status': 'completed', 'paymentStatus': ++polls >= 2 ? 'paid' : 'pending'});
        }
        return null;
      };
      await settle(tester, shell.ride(status: 'ongoing', paymentMode: 'online'));
      await withApi(() => pumpFor(tester, 7000));
      expect(find.text('INVOICE ₹200'), findsOneWidget);
      expect(_sent('POST', '/collect-cash'), isEmpty);
      await teardown(tester);
    });

    testWidgets('online: "Rider paid cash" just after the rider paid online (409 paidOnline) → invoice', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/complete')) return _json(done('online', status: 'pending'));
        if (r.url.path.endsWith('/collect-cash')) return _json({'error': 'The rider has just paid online', 'code': 'paidOnline'}, 409);
        return null;
      };
      await settle(tester, shell.ride(status: 'ongoing', paymentMode: 'online'));
      await withApi(() async {
        await tester.tap(find.text('Rider paid cash'));
        await pumpFor(tester, 300);
        await tester.tap(find.text('Cash collected'));
        await pumpFor(tester, 500);
      });
      expect(find.text('INVOICE ₹200'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('on the trip screen: a wallet ride is ended by /complete (no "auto-deducted" guess)', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, log: log, onRide: shell.ride(status: 'ongoing', paymentMode: 'wallet'),
          override: (req) async => req.url.path.endsWith('/complete')
              ? http.Response(jsonEncode(done('cash', extra: {'paymentSwitchedToCash': true, 'cashToCollect': 400})), 200)
              : null);
      await shell.act(() async {
        await shell.swipe(tester, 'Swipe to end ride');
        await tester.pump(const Duration(milliseconds: 600));
      });
      expect(shell.posts(log, '/complete'), hasLength(1));
      expect(find.text("Rider's wallet was short — collect ₹400 in cash"), findsOneWidget);
      await shell.teardown(tester);
    });

    testWidgets('on the trip screen: an online ride is ended by the driver and waits for payment', (tester) async {
      final log = <shell.ApiCall>[];
      await shell.openScreen(tester, log: log, onRide: shell.ride(status: 'ongoing', paymentMode: 'online'),
          override: (req) async => req.url.path.endsWith('/complete')
              ? http.Response(jsonEncode(done('online', status: 'pending')), 200)
              : null);
      await shell.act(() async {
        await shell.swipe(tester, 'Swipe to request payment');
        await tester.pump(const Duration(milliseconds: 600));
      });
      expect(shell.posts(log, '/request-payment'), hasLength(1));
      expect(shell.posts(log, '/complete'), hasLength(1));
      expect(find.text('Waiting for online payment ₹250'), findsOneWidget);
      await shell.teardown(tester);
    });
  });

  // ── 8. Wallet & withdrawals ─────────────────────────────────────────────────
  test('new wallet history types are labelled', () {
    expect(walletTypeLabel('withdrawal_hold'), 'Withdrawal (on hold)');
    expect(walletTypeLabel('withdrawal_released'), 'Withdrawal returned');
    expect(walletTypeLabel('admin_credit'), 'Added by Gora');
    expect(walletTypeLabel('admin_debit'), 'Deducted by Gora');
    expect(walletTypeLabel('ride_earning'), 'Ride Earning');
  });

  test('the wallet list uses those labels', () async {
    api = (r) => r.url.path.endsWith('/auth/driver/wallet')
        ? _json({'balance': 100, 'transactions': [
            {'_id': '1', 'type': 'withdrawal_hold', 'amount': -500, 'createdAt': '2026-11-20T10:00:00Z'},
            {'_id': '2', 'type': 'admin_credit', 'amount': 50, 'createdAt': '2026-11-20T10:00:00Z'},
          ]})
        : null;
    await withApi(() async {
      final bloc = WalletBloc()..add(LoadWalletEvent());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = bloc.state as WalletLoaded;
      expect(s.transactions.map((t) => t.type), ['Withdrawal (on hold)', 'Added by Gora']);
      await bloc.close();
    });
  });

  group('withdrawal', () {
    Future<void> withdraw(WidgetTester tester) async {
      phone(tester, const Size(400, 1400));
      await tester.pumpWidget(app(Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WithdrawPage(balance: 1000))),
        child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await pumpFor(tester, 500);
      await tester.enterText(find.byType(TextField).first, '500');
      await tester.ensureVisible(find.text('Withdraw now'));
      await tester.tap(find.text('Withdraw now'));
      await pumpFor(tester, 500);
    }

    final banks = {'driverName': 'Suresh', 'banks': [
      {'accountHolderName': 'Suresh', 'bankName': 'SBI', 'accountNumber': '12345678', 'ifscCode': 'SBIN0001'},
    ]};

    testWidgets('a request holds the money at once and says so', (tester) async {
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/banks')) return _json(banks);
        if (r.method == 'POST' && r.url.path.endsWith('/auth/driver/withdraw')) {
          return _json({'success': true, 'withdrawal': {'_id': 'w1', 'status': 'pending'}, 'walletBalance': 500});
        }
        return null;
      };
      await withApi(() => withdraw(tester));
      expect(find.text('Withdrawal requested — ₹500 is on hold until it is paid out. Wallet balance: ₹500.'), findsOneWidget);
      await pumpFor(tester, 800);
      expect(find.byType(WithdrawPage), findsNothing);
      await teardown(tester);
    });

    testWidgets('a second request while one is pending (409) is explained', (tester) async {
      const msg = 'You already have a withdrawal request pending. Please wait for it to be processed.';
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/banks')) return _json(banks);
        if (r.method == 'POST' && r.url.path.endsWith('/auth/driver/withdraw')) return _json({'error': msg}, 409);
        return null;
      };
      await withApi(() => withdraw(tester));
      expect(find.text(msg), findsOneWidget);
      expect(find.byType(WithdrawPage), findsOneWidget);
      await teardown(tester);
    });
  });

  // ── 9. Subscription ─────────────────────────────────────────────────────────
  test('a plan is paid with a /subscription/order order, never a generic one', () async {
    api = (r) => r.url.path.endsWith('/auth/driver/subscription/order')
        ? _json({'error': 'Razorpay is not enabled'}, 400)
        : null;
    final res = await withApi(() => DriverPaymentService.paySubscription(planId: 'p1'));
    expect(res['error'], 'Razorpay is not enabled');
    expect(_sent('POST', '/auth/driver/subscription/order'), hasLength(1));
    expect(_body(_sent('POST', '/auth/driver/subscription/order').single), {'planId': 'p1'});
    expect(calls.where((r) => r.url.path.contains('/payment/razorpay/order')), isEmpty);
  });

  // ── 10. Logout ──────────────────────────────────────────────────────────────
  testWidgets('Logout: offline on the server, service stopped, session cleared, then login', (tester) async {
    phone(tester, const Size(400, 2400));
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true, 'logged_in': true,
      'driver_upi': 'x@upi', 'driver_dark': true});
    await withApi(() async {
      await tester.pumpWidget(app(const AccountPage(), routes: {'/login': (_) => const Scaffold(body: Text('LOGIN'))}));
      await tester.pump();
      await tester.ensureVisible(find.text('Logout'));
      await tester.tap(find.text('Logout'));
      await pumpFor(tester, 300);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await pumpFor(tester, 500);
    });
    final online = _sent('POST', '/auth/driver/online');
    expect(online, hasLength(1));
    expect(_body(online.single)['isOnline'], false);
    expect(stops, 1, reason: 'the online service is stopped');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('driver_token'), isNull);
    expect(prefs.getBool('driver_online'), isNull);
    expect(prefs.getBool('logged_in'), isNull);
    expect(prefs.getString('driver_upi'), isNull);
    expect(prefs.getBool('driver_dark'), isTrue, reason: 'device settings stay');
    expect(find.text('LOGIN'), findsOneWidget);
    await teardown(tester);
  });

  // ── 11. Online restore after the app was killed ─────────────────────────────
  test('reopened while online: alerts restart and online is re-posted', () async {
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
    await withApi(() async {
      final bloc = HomeBloc()..add(LoadHomeDataEvent());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.isOnline, isTrue);
      await bloc.close();
    });
    expect(starts, 1, reason: 'RideAlertService.start() again');
    final online = _sent('POST', '/auth/driver/online');
    expect(online, hasLength(1));
    expect(_body(online.single)['isOnline'], true);
  });

  test('reopened while offline: nothing is started', () async {
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': false});
    await withApi(() async {
      final bloc = HomeBloc()..add(LoadHomeDataEvent());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await bloc.close();
    });
    expect(starts, 0);
    expect(_sent('POST', '/auth/driver/online'), isEmpty);
  });

  test('reopened online but now on hold: back offline, service stopped', () async {
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
    api = (r) => r.url.path.endsWith('/auth/driver/online')
        ? _json({'error': 'Your account is on hold', 'accountHold': true, 'holdKind': 'manual'}, 403)
        : null;
    await withApi(() async {
      final bloc = HomeBloc()..add(LoadHomeDataEvent());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.isOnline, isFalse);
      expect(bloc.state, isA<AccountHoldState>());
      await bloc.close();
    });
    expect(starts, 0);
    expect(stops, 1);
    expect((await SharedPreferences.getInstance()).getBool('driver_online'), isFalse);
  });

  // ── 12. 401 → login once ────────────────────────────────────────────────────
  testWidgets('401 on the session token: service stopped, session cleared, login once', (tester) async {
    phone(tester);
    var logins = 0;
    Session.install();
    api = (r) => _json({'error': 'Unauthorized'}, 401);
    await tester.pumpWidget(app(const Scaffold(body: Text('HOME')), nav: Session.navigatorKey, routes: {
      '/login': (_) { logins++; return const Scaffold(body: Text('LOGIN')); },
    }));
    await withApi(() async {
      await Future.wait([
        DriverApiService.getPendingRequests(),
        DriverApiService.getProfile(),
        DriverApiService.getWallet(),
      ]);
      await pumpFor(tester, 300);
      await DriverApiService.getPendingRequests();
      await pumpFor(tester, 300);
    });
    expect(find.text('LOGIN'), findsOneWidget);
    expect(logins, 1, reason: 'one trip to login, however many 401s');
    expect(stops, 1);
    expect((await SharedPreferences.getInstance()).getString('driver_token'), isNull);
    await teardown(tester);
  });

  test('a 401 for a token that is no longer the session does not sign out', () async {
    var fired = 0;
    DriverApiService.onUnauthorized = () { fired++; };
    api = (r) async {
      // A re-login lands while this request is in flight.
      await DriverApiService.saveToken('new-token');
      return _json({'error': 'Unauthorized'}, 401);
    };
    await withApi(() => DriverApiService.getProfile());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fired, 0);
  });

  test('the background poller treats 401 as signed out, not as "no rides"', () async {
    api = (r) => _json({'error': 'Unauthorized'}, 401);
    final handler = RideAlertTaskHandler();
    await withApi(() => handler.pollOnce());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(handler.signedOut, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('driver_token'), isNull);
  });

  // ── 13. Stale fixes are not sent ────────────────────────────────────────────
  group('location pings', () {
    final now = DateTime(2026, 11, 24, 12);
    test('a fix older than 60 s is stale', () {
      expect(isFreshFix(fix(at: now.subtract(const Duration(seconds: 10))), now: now), isTrue);
      expect(isFreshFix(fix(at: now.subtract(const Duration(seconds: 61))), now: now), isFalse);
      expect(isFreshFix(fix(at: now.subtract(const Duration(hours: 3))), now: now), isFalse);
      expect(isFreshFix(null, now: now), isFalse);
    });

    test('only a fresh fix is pushed; INVALID_LOCATION / LOCATION_JUMP do not stop pinging', () async {
      api = (r) => _json({'error': 'Location jump ignored', 'code': 'LOCATION_JUMP', 'ignored': true}, 422);
      await withApi(() async {
        expect(await pushFreshLocation(fix(at: now.subtract(const Duration(minutes: 5))), now: now), isFalse);
        expect(_sent('POST', '/auth/driver/location'), isEmpty);
        expect(await pushFreshLocation(fix(at: now.subtract(const Duration(seconds: 5))), now: now), isTrue);
        expect(await pushFreshLocation(fix(at: now.subtract(const Duration(seconds: 2))), now: now), isTrue);
      });
      expect(_sent('POST', '/auth/driver/location'), hasLength(2));
    });
  });

  // ── 14. Uploads ─────────────────────────────────────────────────────────────
  group('uploads', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    test('a server refusal returns null with the reason', () async {
      api = (r) => _json({'error': 'Unsupported file type'}, 400);
      expect(await withApi(() => DriverApiService.uploadBytes(bytes, 'a.jpg')), isNull);
      expect(DriverApiService.lastUploadError, 'Unsupported file type');
    });
    test('a dropped connection returns null, never throws', () async {
      api = (r) => throw http.ClientException('reset');
      expect(await withApi(() => DriverApiService.uploadBytes(bytes, 'a.jpg')), isNull);
      expect(DriverApiService.lastUploadError, contains('Upload failed'));
    });
    test('an HTML error page returns null', () async {
      api = (r) => http.Response('<html>502</html>', 502);
      expect(await withApi(() => DriverApiService.uploadFile(XFile.fromData(bytes, name: 'a.jpg'))), isNull);
    });
    testWidgets('a stalled upload times out instead of spinning for ever', (tester) async {
      api = (r) => Completer<http.Response>().future; // never answers
      String? url = 'unset';
      var finished = false;
      await withApi(() async {
        unawaited(DriverApiService.uploadBytes(bytes, 'a.jpg').then((u) { url = u; finished = true; }));
        await tester.pump(DriverApiService.uploadTimeout + const Duration(seconds: 1));
        await tester.pump();
      });
      expect(finished, isTrue);
      expect(url, isNull);
      expect(DriverApiService.lastUploadError, contains('timed out'));
    });
    test('a good upload returns the full url', () async {
      api = (r) => _json({'url': '/uploads/x.jpg'});
      final u = await withApi(() => DriverApiService.uploadBytes(bytes, 'a.jpg'));
      expect(u, endsWith('/uploads/x.jpg'));
      expect(DriverApiService.lastUploadError, isNull);
    });
  });

  // ── 15. Ringtone, rating, chat ─────────────────────────────────────────────
  test('no admin ringtone: the bundled one plays', () async {
    final s = ringtoneSource('');
    expect(s.toString(), contains(defaultRingtoneAsset));
    expect(ringtoneSource('/uploads/ring.mp3').toString(), contains('/uploads/ring.mp3'));
    // The asset is really bundled.
    final data = await rootBundle.load('assets/$defaultRingtoneAsset');
    expect(data.lengthInBytes, greaterThan(1000));
  });

  test('rating and chat send no role: the server takes it from the token', () async {
    await withApi(() async {
      await DriverApiService.rateRide('r1', 5, 'Polite');
      await DriverApiService.sendRideMessage('r1', 'On my way');
    });
    expect(_body(_sent('POST', '/rides/r1/rate').single), {'rating': 5, 'review': 'Polite'});
    expect(_body(_sent('POST', '/rides/r1/messages').single), {'text': 'On my way'});
  });

  test('history asks for a page and a limit of at most 50', () async {
    await withApi(() => DriverApiService.getTripHistory(page: 3, limit: 500));
    final q = _sent('GET', '/rides/driver/history').single.url.queryParameters;
    expect(q['page'], '3');
    expect(q['limit'], '50');
  });
}
