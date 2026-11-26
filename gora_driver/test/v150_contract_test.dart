import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/config/app_version.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/account/pages/face_reverify_page.dart';
import 'package:gora_driver/features/account/pages/zone_page.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/home/logic/feed_status.dart';
import 'package:gora_driver/features/ride/bloc/ride_bloc.dart';
import 'package:gora_driver/features/ride/logic/job_settlement.dart';
import 'package:gora_driver/features/ride/logic/ride_actions.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/ride/pages/on_ride_page.dart';
import 'package:gora_driver/features/ride/pages/ride_chat_page.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';
import 'package:gora_driver/features/wallet/pages/withdraw_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';
import 'package:gora_driver/services/app_update.dart';
import 'package:gora_driver/services/driver_api_service.dart';
import 'package:gora_driver/services/ride_alert_service.dart';
import 'package:gora_driver/services/session.dart';
import 'package:gora_driver/services/token_store.dart';
import 'package:gora_driver/widgets/update_gate.dart';

// ─────────────────────────────────────────────────────────────────────────────
// v1.5.0: the app against the backend contracts of the re-audit (goraadmin
// f17d7fe). Every reply is shaped like the route that sends it.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final calls = <http.BaseRequest>[];
final bodies = <String>[];
typedef Api = FutureOr<http.Response?> Function(http.Request req);
Api api = (_) => null;

MockClient get _client => MockClient((req) async {
      calls.add(req);
      bodies.add(req.body);
      return await api(req) ?? _json({});
    });

Future<T> withApi<T>(Future<T> Function() body) => http.runWithClient(body, () => _client);

List<int> _sentIdx(String method, String pathEnd) => [
      for (var i = 0; i < calls.length; i++)
        if (calls[i].method == method && calls[i].url.path.endsWith(pathEnd)) i,
    ];
Map<String, dynamic> _bodyAt(int i) => jsonDecode(bodies[i]) as Map<String, dynamic>;

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

Widget app(Widget home, {Map<String, WidgetBuilder>? routes}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => DriverProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: BlocProvider(
    create: (_) => AuthBloc(),
    child: MaterialApp(
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

RideRequestModel ride({String service = 'taxi', String payment = 'cash', num fare = 85, Map<String, dynamic> extra = const {}}) =>
    RideRequestModel.fromJson({
      'id': 'ride-1', 'service': service, 'riderName': 'Rahul', 'vehicleType': 'Bike',
      'pickupAddress': 'Law Garden', 'dropAddress': 'Prahlad Nagar',
      'pickupLat': 23.02, 'pickupLng': 72.56, 'dropLat': 23.01, 'dropLng': 72.51,
      'fare': fare, 'totalFare': fare, 'paymentMode': payment, 'status': 'ongoing', ...extra,
    });

/// A fake JWT with the given iat (the app only reads iat; it never verifies).
String jwt(DateTime iat) {
  String b(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'HS256'})}.${b({'id': 'd1', 'type': 'driver', 'iat': iat.millisecondsSinceEpoch ~/ 1000})}.sig';
}

/// flutter_secure_storage's channel, backed by a map.
Map<String, String>? secure;
void mockSecureStorage() {
  secure = {};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
      final key = (c.arguments as Map?)?['key'] as String?;
      switch (c.method) {
        case 'read': return secure![key];
        case 'write': secure![key!] = (c.arguments as Map)['value'] as String; return null;
        case 'delete': secure!.remove(key); return null;
        case 'containsKey': return secure!.containsKey(key);
      }
      return null;
    });
}

void unmockSecureStorage() {
  secure = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null);
}

/// Pushes [run]'s screen flow from a button, so Navigator.push works.
Widget launcher(Future<void> Function(BuildContext) run) => Builder(builder: (context) => Scaffold(
  body: Center(child: TextButton(onPressed: () => run(context), child: const Text('go'))),
));

void main() {
  setUp(() {
    calls.clear();
    bodies.clear();
    api = (_) => null;
    DriverApiService.onUnauthorized = null;
    DriverApiService.onProfile = null;
    DriverApiService.resetUnauthorized();
    DriverApiService.signOutReason = sessionExpiredText;
    Session.resetRefreshForTest();
    TokenStore.resetForTest();
    AppUpdate.resetForTest();
    RideAlertService.startImpl = () async => true;
    RideAlertService.stopImpl = () async {};
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
        (c) async => c.method == 'isLocationServiceEnabled' ? false : null);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
  });
  tearDown(unmockSecureStorage);

  // ── 0. Version ────────────────────────────────────────────────────────────
  test('appVersion matches pubspec.yaml, which is 1.5.1 with a newer build', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)\s*$', multiLine: true).firstMatch(pub)!;
    expect(m.group(1), appVersion);
    expect(appVersion, '1.5.1');
    expect(int.parse(m.group(2)!), greaterThan(10), reason: 'v1.5.0 was build 10');
  });

  // ── 1. Sessions ───────────────────────────────────────────────────────────
  group('which replies end the session', () {
    test('any 401, and only the account codes of a 403', () {
      expect(sessionEndReason(401, {'error': 'Unauthorized'}), sessionExpiredText);
      expect(sessionEndReason(401, {'code': 'SESSION_REVOKED'}), contains('sign in again'));
      expect(sessionEndReason(401, {'code': 'ACCOUNT_DELETED', 'accountDeleted': true}), accountDeletedText);
      expect(sessionEndReason(403, {'code': 'ACCOUNT_BLOCKED'}), accountBlockedText);
      expect(sessionEndReason(403, {'code': 'ACCOUNT_DELETED'}), accountDeletedText);
      for (final code in ['NOT_PARTICIPANT', 'OUT_OF_RANGE', 'driverMustEnd', 'notApproved', 'accountHold',
          'ZONE_AUTO_ADMIN_ONLY', 'ACCOUNT_HOLD', 'FACE_VERIFICATION_REQUIRED', '']) {
        expect(sessionEndReason(403, {'code': code}), isNull, reason: '403 $code must not sign out');
      }
      expect(sessionEndReason(409, {'code': 'TOO_EARLY'}), isNull);
      expect(sessionEndReason(429, {}), isNull);
    });

    test('a 403 OUT_OF_RANGE / NOT_PARTICIPANT does not sign out; ACCOUNT_BLOCKED does, with its reason', () async {
      var fired = 0;
      DriverApiService.onUnauthorized = () { fired++; };
      api = (r) => r.url.path.endsWith('/accept')
          ? _json({'error': 'This ride is too far from you', 'code': 'OUT_OF_RANGE'}, 403)
          : _json({'error': 'Not a participant in this ride', 'code': 'NOT_PARTICIPANT'}, 403);
      await withApi(() async {
        await DriverApiService.acceptRide('r1');
        await DriverApiService.collectCash('r1');
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fired, 0);

      api = (r) => _json({'error': 'Your account is blocked. Please contact support.', 'code': 'ACCOUNT_BLOCKED'}, 403);
      await withApi(() => DriverApiService.getWallet());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fired, 1);
      expect(DriverApiService.signOutReason, accountBlockedText);
    });

    test('the background service tells the app why', () {
      expect(unauthorizedReasonOf('$unauthorizedMessage:$accountBlockedText'), accountBlockedText);
      expect(unauthorizedReasonOf(unauthorizedMessage), sessionExpiredText, reason: 'older format');
      expect(unauthorizedReasonOf('app-foreground'), isNull);
      expect(unauthorizedReasonOf(42), isNull);
    });
  });

  group('sliding refresh', () {
    final now = DateTime.utc(2026, 11, 25, 12);
    test('due once refreshAfter has passed; without it, once the token is over a day old', () {
      expect(shouldRefreshToken(now: now, refreshAfter: now.subtract(const Duration(minutes: 1))), isTrue);
      expect(shouldRefreshToken(now: now, refreshAfter: now.add(const Duration(hours: 3))), isFalse);
      expect(shouldRefreshToken(now: now, issuedAt: now.subtract(const Duration(days: 2))), isTrue);
      expect(shouldRefreshToken(now: now, issuedAt: now.subtract(const Duration(hours: 5))), isFalse);
      expect(shouldRefreshToken(now: now), isFalse);
      expect(jwtIssuedAt(jwt(DateTime.utc(2026, 11, 20, 8)))!.toUtc(), DateTime.utc(2026, 11, 20, 8));
      expect(jwtIssuedAt('not-a-jwt'), isNull);
    });

    test('due: POST /auth/refresh with the token, and the new token is saved', () async {
      final old = jwt(now.subtract(const Duration(days: 2)));
      SharedPreferences.setMockInitialValues({'driver_token': old});
      api = (r) => r.url.path.endsWith('/auth/refresh')
          ? _json({'token': 'fresh-token', 'type': 'driver', 'expiresIn': 604800, 'refreshAfter': '2026-11-26T12:00:00.000Z'})
          : null;
      await withApi(() => Session.maybeRefresh(refreshAfter: '2026-11-24T12:00:00.000Z', now: now));
      final i = _sentIdx('POST', '/auth/refresh');
      expect(i, hasLength(1));
      expect(calls[i.single].headers['Authorization'], 'Bearer $old');
      expect(await DriverApiService.getToken(), 'fresh-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Session.refreshAfterKey), '2026-11-26T12:00:00.000Z');
    });

    test('not due: nothing is sent', () async {
      await withApi(() => Session.maybeRefresh(refreshAfter: '2026-11-25T18:00:00.000Z', now: now));
      expect(_sentIdx('POST', '/auth/refresh'), isEmpty);
    });

    test('409 TOO_EARLY is ignored: the token stays, the next try moves to its refreshAfter', () async {
      var fired = 0;
      DriverApiService.onUnauthorized = () { fired++; };
      api = (r) => _json({'error': 'Token is still fresh', 'code': 'TOO_EARLY', 'refreshAfter': '2026-11-25T20:00:00.000Z'}, 409);
      await withApi(() => Session.maybeRefresh(refreshAfter: '2026-11-25T11:00:00.000Z', now: now));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await DriverApiService.getToken(), 't');
      expect(fired, 0);
      expect((await SharedPreferences.getInstance()).getString(Session.refreshAfterKey), '2026-11-25T20:00:00.000Z');
    });

    test('a profile reply with a passed refreshAfter triggers the refresh', () async {
      Session.install();
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/profile')) {
          return _json({'driver': {'_id': 'd1', 'status': 'approved'}, 'refreshAfter': '2020-01-01T00:00:00.000Z'});
        }
        if (r.url.path.endsWith('/auth/refresh')) return _json({'token': 'fresh', 'refreshAfter': '2099-01-01T00:00:00.000Z'});
        return null;
      };
      await withApi(() async {
        await DriverApiService.getProfile();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(_sentIdx('POST', '/auth/refresh'), hasLength(1));
      expect(await DriverApiService.getToken(), 'fresh');
    });
  });

  group('token storage', () {
    test('an older build\'s token moves from SharedPreferences into secure storage, once', () async {
      mockSecureStorage();
      SharedPreferences.setMockInitialValues({'driver_token': 'legacy'});
      expect(await TokenStore.read(), 'legacy');
      expect(secure!['driver_token'], 'legacy');
      expect((await SharedPreferences.getInstance()).getString('driver_token'), isNull,
          reason: 'no plain copy is left behind');
      expect(await TokenStore.read(), 'legacy', reason: 'read from secure storage now');
    });

    test('write and clear go to secure storage; the background isolate reads the same store', () async {
      mockSecureStorage();
      SharedPreferences.setMockInitialValues({});
      await DriverApiService.saveToken('new');
      expect(secure!['driver_token'], 'new');
      expect((await SharedPreferences.getInstance()).getString('driver_token'), isNull);
      // A fresh read (as the background isolate does on every request).
      TokenStore.resetForTest();
      expect(await DriverApiService.getToken(), 'new');
      await DriverApiService.clearToken();
      expect(secure!.containsKey('driver_token'), isFalse);
      expect(await DriverApiService.getToken(), isNull);
    });

    test('a refreshed token reaches the next request without a restart', () async {
      mockSecureStorage();
      SharedPreferences.setMockInitialValues({});
      await DriverApiService.saveToken('one');
      await withApi(() => DriverApiService.getWallet());
      await DriverApiService.saveToken('two');
      await withApi(() => DriverApiService.getWallet());
      expect(calls.map((c) => c.headers['Authorization']).toList(), ['Bearer one', 'Bearer two']);
    });

    test('logout clears the secure token too', () async {
      mockSecureStorage();
      secure!['driver_token'] = 'abc';
      await Session.clearSession();
      expect(secure!.containsKey('driver_token'), isFalse);
    });
  });

  // ── 7. Private uploads ────────────────────────────────────────────────────
  group('private uploads', () {
    test('KYC and face photos go to ?private=1&purpose=…; the /api/files url comes back', () async {
      expect(DriverApiService.uploadUri(private: true, purpose: 'kyc').toString(),
          'https://goracabs.com/api/upload?private=1&purpose=kyc');
      expect(DriverApiService.uploadUri().toString(), 'https://goracabs.com/api/upload');
      api = (r) => _json({'url': '/api/files/1732520000000-abcdef012345.jpg', 'private': true});
      final url = await withApi(() => DriverApiService.uploadBytes(Uint8List.fromList([1, 2, 3]), 'face.jpg',
          private: true, purpose: 'face'));
      expect(url, 'https://goracabs.com/api/files/1732520000000-abcdef012345.jpg');
      expect(calls.single.url.queryParameters, {'private': '1', 'purpose': 'face'});
      expect(calls.single.headers['Authorization'], 'Bearer t');
    });

    test('429 says so', () async {
      api = (r) => _json({'error': 'Too many uploads. Please try again in a while.', 'code': 'UPLOAD_RATE_LIMIT'}, 429);
      final url = await withApi(() => DriverApiService.uploadBytes(Uint8List.fromList([1]), 'x.jpg', private: true));
      expect(url, isNull);
      expect(DriverApiService.lastUploadError, 'Too many uploads. Please try again in a while.');
    });

    test('a private image is requested with the token; a public one is not', () async {
      await TokenStore.read(); // as every request does
      expect(imageHeadersFor('https://goracabs.com/api/files/1-aaaaaaaaaaaa.jpg'), {'Authorization': 'Bearer t'});
      expect(imageHeadersFor('https://goracabs.com/uploads/1-aaaaaaaaaaaa.jpg'), isNull);
    });

    test('the profile picture may be a private face photo', () {
      final dp = DriverProvider()..setData({'profilePicUrl': '/api/files/1732520000000-abcdef012345.jpg'});
      expect(dp.profilePicUrl, 'https://goracabs.com/api/files/1732520000000-abcdef012345.jpg');
    });
  });

  // ── 6. Face re-verify ─────────────────────────────────────────────────────
  test('face re-verify: success only when cleared; adminHold / 429 explained', () {
    expect(reverifyOutcome({'matched': true, 'cleared': true}).cleared, isTrue);
    final hold = reverifyOutcome({'matched': true, 'cleared': false, 'adminHold': true});
    expect(hold.cleared, isFalse);
    expect(hold.message, 'Your account is on hold. Please contact support.');
    expect(reverifyOutcome({'matched': true, 'cleared': false}).cleared, isFalse,
        reason: 'a match alone is not a success');
    expect(reverifyOutcome({'error': 'Too many attempts.', 'code': 'RATE_LIMITED', '_status': 429}).message,
        startsWith('Too many attempts'));
    expect(reverifyOutcome({'matched': false, 'cleared': false}).message, contains("didn't match"));
  });

  // ── 2. Cash amount ────────────────────────────────────────────────────────
  group('cash to collect is the server\'s figure', () {
    Future<RideCompletionArgs?> run(WidgetTester tester, RideRequestModel r, Map<String, dynamic> res,
        {num tolls = 0, Future<void> Function()? inside}) async {
      phone(tester);
      RideCompletionArgs? out;
      await tester.pumpWidget(app(launcher((c) async {
        out = await afterComplete(c, r, res, tollsInHand: tolls, tollCollected: tolls);
      })));
      await tester.tap(find.text('go'));
      await pumpFor(tester, 500);
      if (inside != null) await inside();
      return out;
    }

    testWidgets('cash: /complete\'s cashToCollect, not the booked fare', (tester) async {
      await run(tester, ride(fare: 85), {'success': true, 'paymentMode': 'cash', 'paymentStatus': 'paid',
        'amountDue': 70, 'cashToCollect': 70, 'couponDiscount': 15, 'driverEarning': 60}, inside: () async {
        expect(find.byType(CollectFarePage), findsOneWidget);
        expect(find.text('₹70'), findsOneWidget);
        expect(find.text('₹85'), findsNothing);
        expect(find.text('Collect from the rider'), findsOneWidget);
      });
      await teardown(tester);
    });

    testWidgets('cash with tolls: the server figure plus the tolls', (tester) async {
      await run(tester, ride(fare: 85), {'success': true, 'paymentMode': 'cash', 'cashToCollect': 100}, tolls: 40,
          inside: () async {
        expect(find.text('₹140'), findsOneWidget);
        expect(find.text('Fare + tolls — collect from the rider'), findsOneWidget);
      });
      await teardown(tester);
    });

    testWidgets('prepaid shortfall: "Collect ₹X" with the collect-cash action', (tester) async {
      api = (r) => r.url.path.endsWith('/collect-cash')
          ? _json({'success': true, 'paymentMode': 'cash', 'paymentStatus': 'paid', 'cashToCollect': 120, 'commission': 0})
          : _json({'ride': {'paymentStatus': 'pending'}});
      RideCompletionArgs? out;
      await withApi(() async {
        out = await run(tester, ride(service: 'outstation', payment: 'online', fare: 3000), {
          'success': true, 'paymentMode': 'online', 'paymentStatus': 'pending', 'awaitingPayment': true,
          'amountDue': 120, 'prepaidShortfall': true, 'cashToCollect': 120, 'driverEarning': 2500,
        }, inside: () async {
          expect(find.text('Collect ₹120'), findsOneWidget);
          await tester.tap(find.text('Cash collected'));
          await pumpFor(tester, 300);
          await tester.tap(find.widgetWithText(ElevatedButton, 'Cash collected').last);
          await pumpFor(tester, 500);
        });
      });
      expect(_sentIdx('POST', '/rides/ride-1/collect-cash'), hasLength(1));
      expect(out?.earningPending, isFalse);
      await teardown(tester);
    });

    testWidgets('online, rider pays later: the earning is "Pending"', (tester) async {
      RideCompletionArgs? out;
      api = (r) => _json({'ride': {'paymentStatus': 'pending'}});
      await withApi(() async {
        out = await run(tester, ride(payment: 'online'), {'success': true, 'paymentMode': 'online',
          'paymentStatus': 'pending', 'awaitingPayment': true, 'amountDue': 85, 'driverEarning': 68}, inside: () async {
          await tester.tap(find.text('Later'));
          await pumpFor(tester, 300);
        });
      });
      expect(out?.earningPending, isTrue);
      await tester.pumpWidget(MaterialApp(
        routes: {'/home': (_) => const SizedBox()},
        home: Builder(builder: (c) {
          WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.push(c, MaterialPageRoute(
              builder: (_) => const InvoicePage(), settings: RouteSettings(arguments: out))));
          return const SizedBox();
        }),
      ));
      await pumpFor(tester, 500);
      expect(find.text(earningPendingText), findsOneWidget);
      await teardown(tester);
    });

    test('rental / hire bills: cashToCollect first; non-cash collects nothing', () {
      expect(rentalCashToCollect({'alreadyEnded': true, 'cashToCollect': 1180, 'rental': {'finalFare': 1200}}, cash: true), 1180);
      expect(rentalCashToCollect({'rental': {'finalFare': 1200}}, cash: true), 1200, reason: 'older server');
      expect(rentalCashToCollect({'cashToCollect': 1180}, cash: false), 0);
      expect(hireCashToCollect({'amountDue': 950, 'cashToCollect': 900}, cash: true), 900);
      expect(hireCashToCollect({'amountDue': 950}, cash: true), 950);
    });

    test('trip history: an unpaid online ride is "Pending"', () {
      TripModel t(String mode, String st) => TripModel(id: '1', userName: 'a', pickupAddress: '', dropAddress: '',
          distance: '', fare: '', date: '', status: 'completed', paymentMode: mode, duration: '', rating: 0,
          paymentStatus: st);
      expect(t('online', 'pending').earningPending, isTrue);
      expect(t('online', 'paid').earningPending, isFalse);
      expect(t('cash', 'paid').earningPending, isFalse);
    });
  });

  // ── 3. Extensions ─────────────────────────────────────────────────────────
  test('extension refusals are explained', () {
    expect(rideActionError({'code': 'EXTENSION_PENDING', 'error': 'x'}), contains('already waiting'));
    expect(rideActionError({'code': 'EXTENSION_LIMIT', 'error': 'x'}), contains('at most 3'));
  });

  // ── 4. Dispatch ───────────────────────────────────────────────────────────
  group('dispatch', () {
    test('offer cooldown: a clear line with the time; a past one is ignored', () {
      final now = DateTime.now();
      final until = DateTime(now.year, now.month, now.day, 23, 59).add(const Duration(days: 1));
      expect(offerCooldownUntilOf({'offerCooldownUntil': until.toUtc().toIso8601String()}), until);
      expect(offerCooldownUntilOf({'offerCooldownUntil': now.subtract(const Duration(minutes: 1)).toIso8601String()}), isNull);
      expect(cooldownText(DateTime(2026, 11, 25, 18, 5)), 'Too many rejections — new requests paused until 18:05');
      final b = feedBlockFrom({'rides': [], 'offerCooldownUntil': until.toUtc().toIso8601String()})!;
      expect(b.kind, 'cooldown');
      expect(b.message, contains('Open requests are still shown'));
    });

    test('an advance booking is due at its departure / hire start; upcoming until an hour before', () {
      final now = DateTime(2026, 11, 25, 12);
      final r = RideRequestModel.fromJson({'id': 'o', 'service': 'outstation',
        'departureAt': DateTime(2026, 11, 26, 18).toUtc().toIso8601String()});
      expect(r.dueAt, DateTime(2026, 11, 26, 18));
      expect(showsScheduledTime(r, now: now), isTrue);
      expect(isUpcomingTrip(r.dueAt, now: now), isTrue);
      expect(isUpcomingTrip(DateTime(2026, 11, 25, 12, 45), now: now), isFalse, reason: 'within the hour: busy');
      final h = RideRequestModel.fromJson({'id': 'h', 'service': 'hire_driver',
        'hireStartAt': DateTime(2026, 11, 25, 16).toUtc().toIso8601String()});
      expect(h.dueAt, DateTime(2026, 11, 25, 16));
      final now2 = RideRequestModel.fromJson({'id': 'n', 'service': 'taxi'});
      expect(now2.dueAt, isNull);
      expect(showsScheduledTime(now2, now: now), isFalse);
    });

    Map<String, dynamic> request(String id, Map<String, dynamic> extra) => {
      'id': id, 'service': 'outstation', 'riderName': 'Rahul', 'vehicleType': 'Sedan',
      'pickupAddress': 'Law Garden', 'dropAddress': 'Surat', 'pickupLat': 23.02, 'pickupLng': 72.56,
      'dropLat': 21.17, 'dropLng': 72.83, 'fare': 3200, 'totalFare': 3200, 'paymentMode': 'cash',
      'status': 'pending', ...extra,
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

    testWidgets('accepting tomorrow\'s outstation trip does not open the trip screen', (tester) async {
      phone(tester);
      final due = DateTime.now().add(const Duration(hours: 30));
      final row = request('adv', {'departureAt': due.toUtc().toIso8601String()});
      var accepted = false;
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) return _json({'rides': accepted ? [] : [row]});
        if (r.url.path.endsWith('/accept')) { accepted = true; return _json({'success': true, 'ride': {...row, 'status': 'accepted'}}); }
        if (r.url.path.endsWith('/rides/driver/active')) return _json({'ride': {...row, 'status': 'accepted'}});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(Builder(builder: (c) => Scaffold(body: TextButton(
            onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const IncomingRequestsPage())),
            child: const Text('HOME')))), routes: {
          OnRidePage.route: (_) => const Scaffold(body: Text('TRIP SCREEN')),
        }));
        await tester.tap(find.text('HOME'));
        await pumpFor(tester, 600);
        expect(find.text(scheduledLabel(due)), findsOneWidget, reason: 'the card says when');
        await slideAccept(tester);
        await pumpFor(tester, 800);
      });
      expect(_sentIdx('POST', '/rides/adv/accept'), hasLength(1));
      expect(find.text('TRIP SCREEN'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('Trip accepted for'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a reject that starts the cooldown says until when', (tester) async {
      phone(tester);
      final until = DateTime.now().add(const Duration(minutes: 10));
      api = (r) {
        if (r.url.path.endsWith('/rides/driver/pending')) {
          return _json({'rides': [request('a', {'service': 'taxi'}), request('b', {'service': 'taxi'})]});
        }
        if (r.url.path.endsWith('/reject')) return _json({'success': true, 'offerCooldownUntil': until.toUtc().toIso8601String()});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const IncomingRequestsPage()));
        await pumpFor(tester, 600);
        await tester.tap(find.byIcon(Icons.close).first);
        await pumpFor(tester, 600);
      });
      expect(find.text(cooldownText(until)), findsWidgets);
      await teardown(tester);
    });

    test('/start 409 RIDE_CANCELLED closes the trip', () async {
      api = (r) => _json({'error': 'This ride was cancelled', 'code': 'RIDE_CANCELLED'}, 409);
      final states = <RideState>[];
      // The bloc is created INSIDE withApi: its handlers run in the zone it was
      // made in, so a bloc made outside would send to the real server.
      await withApi(() async {
        final bloc = RideBloc()..currentRide = ride(extra: {'status': 'arrived'});
        final sub = bloc.stream.listen(states.add);
        bloc.add(StartRideEvent('1234'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        await bloc.close();
      });
      expect(states.whereType<RideCancelledState>(), hasLength(1));
      expect(states.whereType<OtpErrorState>(), isEmpty);
    });
  });

  // ── 5. Zone ───────────────────────────────────────────────────────────────
  group('automatic zone is admin-only', () {
    Map<String, dynamic> zone(bool auto) => {'zoneId': 'z1', 'zoneName': 'Ahmedabad West', 'zoneAuto': auto,
      'zones': [{'id': 'z1', 'name': 'Ahmedabad West'}], 'pendingRequest': null, 'history': []};

    testWidgets('off: no switch to turn it on', (tester) async {
      phone(tester);
      api = (r) => r.url.path.endsWith('/auth/driver/zone') ? _json(zone(false)) : null;
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
      });
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Managed by admin'), findsNothing);
      await teardown(tester);
    });

    testWidgets('on: read-only "Managed by admin", and it can only be turned off', (tester) async {
      phone(tester);
      var auto = true;
      api = (r) {
        if (r.method == 'GET' && r.url.path.endsWith('/auth/driver/zone')) return _json(zone(auto));
        if (r.method == 'PUT' && r.url.path.endsWith('/auth/driver/zone')) { auto = false; return _json({'success': true, 'zoneAuto': false}); }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
        expect(find.byType(Switch), findsNothing);
        expect(find.textContaining('Managed by admin'), findsOneWidget);
        await tester.tap(find.text('Turn off'));
        await pumpFor(tester, 300);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Turn off'));
        await pumpFor(tester);
      });
      final put = _sentIdx('PUT', '/auth/driver/zone');
      expect(put, hasLength(1));
      expect(_bodyAt(put.single), {'zoneAuto': false});
      expect(find.textContaining('Managed by admin'), findsNothing);
      expect(find.text('Automatic zone change turned off'), findsOneWidget);
      await teardown(tester);
    });
  });

  // ── 8. Withdrawals ────────────────────────────────────────────────────────
  group('withdrawals', () {
    test('the body names the saved account, not bank details', () {
      expect(withdrawalBody(500.0, {'_id': 'acc1', 'accountNumber': '123', 'ifscCode': 'SBIN0001', 'bankName': 'SBI'}),
          {'amount': 500, 'accountId': 'acc1'});
      expect(withdrawalBody(500, {'accountNumber': '123', 'ifscCode': 'SBIN0001'}),
          {'amount': 500, 'accountNumber': '123', 'ifscCode': 'SBIN0001'}, reason: 'the registration account has no _id');
    });

    test('refusal codes', () {
      expect(withdrawalRefusal({'code': 'bankAccountRequired'}), 'Add a bank account to withdraw to.');
      expect(withdrawalRefusal({'code': 'bankAccountNotFound'}), contains('no longer saved'));
      expect(withdrawalRefusal({'code': 'notApproved'}), contains('once your account is approved'));
      expect(withdrawalRefusal({'code': 'accountHold', 'error': 'Your account is on hold: payout review.'}),
          'Your account is on hold: payout review.');
      expect(withdrawalRefusal({'error': 'x'}), isNull);
    });

    testWidgets('sends accountId; bankAccountNotFound offers to add an account', (tester) async {
      phone(tester);
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/banks')) {
          return _json({'driverName': 'Suresh', 'banks': [
            {'_id': 'acc1', 'accountHolderName': 'Suresh', 'bankName': 'SBI', 'accountNumber': '12345678', 'ifscCode': 'SBIN0001'},
          ]});
        }
        if (r.method == 'POST' && r.url.path.endsWith('/auth/driver/withdraw')) {
          return _json({'error': 'Select one of your saved bank accounts', 'code': 'bankAccountNotFound'}, 400);
        }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const WithdrawPage(balance: 1000)));
        await pumpFor(tester, 500);
        await tester.enterText(find.byType(TextField).first, '500');
        await tester.ensureVisible(find.text('Withdraw now'));
        await tester.tap(find.text('Withdraw now'));
        await pumpFor(tester, 500);
      });
      final post = _sentIdx('POST', '/auth/driver/withdraw');
      expect(_bodyAt(post.single), {'amount': 500, 'accountId': 'acc1'});
      expect(find.textContaining('no longer saved'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      await teardown(tester);
    });
  });

  // ── 10. Chat ──────────────────────────────────────────────────────────────
  test('chat 429 is a friendly line', () {
    expect(chatSendError({'error': 'You are sending messages too fast.', 'code': 'RATE_LIMITED', '_status': 429}),
        'You are sending messages too fast. Wait a moment and try again.');
    expect(chatSendError({'code': 'CHAT_CLOSED'}), 'Chat is closed for this trip.');
  });

  // ── 11. Force update ──────────────────────────────────────────────────────
  group('force update', () {
    test('version comparison', () {
      expect(compareVersions('1.5.0', '1.5.0'), 0);
      expect(compareVersions('1.4.9', '1.5.0'), lessThan(0));
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.5', '1.5.0'), 0);
    });

    test('below minVersion or forced → required; newer → optional; else none', () {
      Map<String, dynamic> v(String latest, String min, {bool force = false}) =>
          {'latestVersion': latest, 'minVersion': min, 'forceUpdate': force, 'message': 'm', 'storeUrl': 'https://x.example/app'};
      expect(updateNoticeFor('1.5.0', v('1.6.0', '1.5.1')).level, UpdateLevel.required);
      expect(updateNoticeFor('1.5.0', v('1.6.0', '1.0.0', force: true)).level, UpdateLevel.required);
      expect(updateNoticeFor('1.5.0', v('1.6.0', '1.0.0')).level, UpdateLevel.optional);
      expect(updateNoticeFor('1.5.0', v('1.5.0', '1.0.0', force: true)).level, UpdateLevel.none);
      expect(updateNoticeFor('1.5.0', null).level, UpdateLevel.none);
      expect(updateNoticeFor('1.5.0', {'latestVersion': '2.0.0', 'storeUrl': 'http://bad'}).storeUrl, defaultStoreUrl);
    });

    test('reads GET /api/app-config?app=driver', () async {
      api = (r) => _json({'config': {'app': 'driver', 'version': {'latestVersion': '9.0.0', 'minVersion': '9.0.0',
        'forceUpdate': false, 'message': 'Please update', 'storeUrl': ''}}});
      await withApi(() => AppUpdate.check(force: true));
      expect(calls.single.url.path, '/api/app-config');
      expect(calls.single.url.queryParameters['app'], 'driver');
      expect(AppUpdate.notice.value.level, UpdateLevel.required);
    });

    testWidgets('required blocks the app; optional is a banner that can be closed', (tester) async {
      phone(tester, const Size(400, 900));
      await tester.pumpWidget(MaterialApp(builder: (c, child) => UpdateGate(child: child!),
          home: const Scaffold(body: Text('APP'))));
      AppUpdate.apply(const UpdateNotice(UpdateLevel.required, latestVersion: '2.0.0'));
      await tester.pump();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.byKey(const ValueKey('update_banner_close')), findsNothing, reason: 'cannot be dismissed');

      AppUpdate.apply(const UpdateNotice(UpdateLevel.optional, latestVersion: '1.6.0'));
      await tester.pump();
      expect(find.text('Update required'), findsNothing);
      expect(find.text('A new version (1.6.0) is available.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update_banner_close')));
      await tester.pump();
      expect(find.text('A new version (1.6.0) is available.'), findsNothing);
      // The same optional version does not come back on the next check.
      AppUpdate.apply(const UpdateNotice(UpdateLevel.optional, latestVersion: '1.6.0'));
      await tester.pump();
      expect(find.text('A new version (1.6.0) is available.'), findsNothing);
      expect(find.text('APP'), findsOneWidget);
    });
  });

  // ── 12. Reliability ───────────────────────────────────────────────────────
  test('ringtone fallbacks: admin file, then the bundled one', () {
    final s = ringtoneSources('/uploads/ring.mp3');
    expect(s, hasLength(2));
    expect(s.first.toString(), contains('/uploads/ring.mp3'));
    expect(s.last.toString(), contains(defaultRingtoneAsset));
    expect(ringtoneSources(''), hasLength(1));
  });

  test('reopened while online: the online service is started again on resume', () async {
    var starts = 0;
    RideAlertService.startImpl = () async { starts++; return true; };
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
    await withApi(() => Session.onResumed());
    expect(starts, 1);
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': false});
    await withApi(() => Session.onResumed());
    expect(starts, 1, reason: 'offline: nothing started');
  });
}
