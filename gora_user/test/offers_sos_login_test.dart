import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/emergency_actions_screen.dart';
import 'package:customer_app/screens/login_screen.dart';
import 'package:customer_app/screens/offers_screen.dart';
import 'package:customer_app/screens/otp_screen.dart';
import 'package:customer_app/utils/emergency_contacts_store.dart';
import 'package:customer_app/utils/pending_coupon.dart';
import 'package:customer_app/utils/phone_input_formatter.dart';
import 'package:customer_app/widgets/payment_coupon_bar.dart';

// Offers "Apply" → next booking's coupon pill, SOS countdown + server-kept
// contacts + live-trip sharing, and the login / OTP inputs. No real network:
// every call goes to a MockClient, and send-otp is never requested.

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

class _Call {
  final String method;
  final Uri url;
  final String body;
  _Call(this.method, this.url, this.body);
}

void main() {
  late List<_Call> calls;
  late Future<http.Response> Function(http.Request req) route;

  MockClient api() => MockClient((req) async {
        calls.add(_Call(req.method, req.url, req.body));
        if (req.url.path.endsWith('/auth/user/send-otp')) {
          fail('send-otp must never be called from tests');
        }
        return route(req);
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({'user_token': 't'});
    calls = [];
    route = (_) async => _json({});
  });

  Iterable<_Call> hits(String suffix, [String? method]) =>
      calls.where((c) => c.url.path.endsWith(suffix) && (method == null || c.method == method));

  // ── Phone input ──
  group('phone input', () {
    test('a pasted number in any common form becomes the 10 digits', () {
      expect(IndianPhoneInputFormatter.normalize('+91 98765 43210'), '9876543210');
      expect(IndianPhoneInputFormatter.normalize('098765-43210'), '9876543210');
      expect(IndianPhoneInputFormatter.normalize('919876543210'), '9876543210');
      expect(IndianPhoneInputFormatter.normalize('98a76'), '9876');
      expect(IndianPhoneInputFormatter.normalize('123456789012345'), '1234567890');
    });

    testWidgets('the login field keeps digits only and strips +91 on paste', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();
      final field = find.byType(TextField).first;
      await tester.enterText(field, '+91 98765 43210');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '9876543210');
      await tester.enterText(field, '98-76x5');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '98765');
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── OTP ──
  group('OTP screen', () {
    testWidgets('six digits verify once, by themselves; resend waits 30 s', (tester) async {
      route = (req) async => req.url.path.endsWith('/verify-otp')
          ? _json({'error': 'Invalid OTP'}, 400)
          : _json({});
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => UserProvider(),
          child: const MaterialApp(home: OtpScreen(phone: '9876543210')),
        ));
        await tester.pump();
        final field = find.byKey(const ValueKey('otp-field'));
        final field0 = tester.widget<TextField>(field);
        expect(field0.autofillHints, contains(AutofillHints.oneTimeCode));

        // Resend is disabled with a countdown.
        final resend = find.byKey(const ValueKey('otp-resend'));
        expect(tester.widget<TextButton>(resend).onPressed, isNull);
        expect(find.text('Resend code in 0:30'), findsOneWidget);

        // A pasted code (with junk) fills all six and verifies once.
        await tester.enterText(field, '12 34-56');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(hits('/verify-otp'), hasLength(1));
        expect(jsonDecode(hits('/verify-otp').single.body)['otp'], '123456');
        // The refused code is not sent again on its own.
        await tester.enterText(field, '123456');
        await tester.pump(const Duration(milliseconds: 50));
        expect(hits('/verify-otp'), hasLength(1));
        // A different code is.
        await tester.enterText(field, '654321');
        await tester.pump(const Duration(milliseconds: 50));
        expect(hits('/verify-otp'), hasLength(2));

        await tester.pump(const Duration(seconds: 10));
        expect(find.text('Resend code in 0:20'), findsOneWidget);
        await tester.pump(const Duration(seconds: 21));
        expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
        expect(find.textContaining('Resend'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5)); // let the snack bar go
        await tester.pumpWidget(const SizedBox());
      }, api);
    });
  });

  // ── Offers → pending coupon ──
  group('offers', () {
    test('coupons: active, unexpired, with a code; services normalised', () {
      final rows = activeCoupons([
        {'code': 'ride50', 'desc': 'd', 'service': 'taxi'},
        {'code': 'OLD', 'expiry': '2020-01-01T00:00:00Z'},
        {'code': 'OFF', 'isActive': false},
        {'code': ''},
        {'code': 'PARCEL', 'service': 'delivery'},
        {'code': 'ALL', 'service': 'all'},
      ], now: DateTime.utc(2026, 11, 26));
      expect(rows.map((r) => r['code']), ['RIDE50', 'PARCEL', 'ALL']);
      expect(rows.map((r) => r['service']), ['taxi', 'delivery', '']);
      expect(activeCoupons(null), isEmpty);
      expect(PendingCoupon.normalizeService('Ride'), 'taxi');
      expect(PendingCoupon.normalizeService('Delivery'), 'delivery');
      expect(PendingCoupon.normalizeService('All'), '');
    });

    test('a pending coupon expires after a day', () async {
      SharedPreferences.setMockInitialValues({});
      final t0 = DateTime(2026, 11, 26, 10);
      await PendingCoupon.save('gora10', service: 'Ride', now: t0);
      final p = await PendingCoupon.load(now: t0.add(const Duration(hours: 1)));
      expect(p!.code, 'GORA10');
      expect(p.appliesTo('taxi'), isTrue);
      expect(p.appliesTo('rental'), isFalse);
      expect(await PendingCoupon.load(now: t0.add(const Duration(hours: 25))), isNull);
      expect(await PendingCoupon.load(now: t0), isNull, reason: 'an expired one is removed');
    });

    testWidgets('no made-up codes: an empty config shows the empty state', (tester) async {
      route = (req) async => req.url.path.endsWith('/app-config')
          ? _json({'config': {'app': 'user', 'offers': [], 'coupons': []}})
          : _json({'error': 'x'}, 500);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OffersScreen()));
        await tester.pump();
        await tester.pump();
        expect(find.text('FIRST50'), findsNothing);
        expect(find.text('No offers right now'), findsOneWidget);
        await tester.tap(find.text('Promo Codes'));
        await tester.pumpAndSettle();
        expect(find.text('GORA50'), findsNothing);
        expect(find.text('No promo codes right now'), findsOneWidget);
      }, api);
    });

    testWidgets('offline: "couldn\'t load" with Retry, never a fallback list', (tester) async {
      var up = false;
      route = (req) async => req.url.path.endsWith('/app-config') && up
          ? _json({'config': {'app': 'user', 'coupons': [{'code': 'SAVE20', 'desc': '20% off', 'service': 'taxi'}]}})
          : http.Response('<html>', 502);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OffersScreen()));
        await tester.pump();
        await tester.pump();
        expect(find.text("Couldn't load offers"), findsOneWidget);
        up = true;
        await tester.tap(find.byKey(const ValueKey('offers-retry')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Promo Codes'));
        await tester.pumpAndSettle();
        expect(find.text('SAVE20'), findsOneWidget);
      }, api);
    });

    testWidgets('Apply keeps the code for the next booking', (tester) async {
      route = (req) async => req.url.path.endsWith('/app-config')
          ? _json({'config': {'app': 'user', 'coupons': [{'code': 'SAVE20', 'desc': '20% off', 'service': 'taxi'}]}})
          : _json({});
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: OffersScreen()));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Promo Codes'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('apply-SAVE20')));
        await tester.pump();
        final p = await PendingCoupon.load();
        expect(p?.code, 'SAVE20');
        expect(p?.service, 'taxi');
        await tester.pump(const Duration(seconds: 5));
      }, api);
    });
  });

  group('coupon pill takes up the pending coupon', () {
    late List<(String, String, int)> changes;
    late bool valid;

    setUp(() {
      changes = [];
      valid = true;
      route = (req) async {
        if (req.url.path.endsWith('/promos/preview')) {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          return valid
              ? _json({'valid': true, 'discount': 30, 'code': b['code'], 'payable': (b['fare'] as num) - 30})
              : _json({'valid': false, 'reason': 'Expired', 'discount': 0});
        }
        if (req.url.path.endsWith('/payment/config')) {
          return _json({'razorpay': {'enabled': false}, 'cashEnabled': true, 'walletEnabled': true});
        }
        if (req.url.path.endsWith('/wallet')) return _json({'balance': 0});
        return _json({});
      };
    });

    Future<void> pumpBar(WidgetTester tester, String service) => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PaymentCouponBar(
            baseFare: 300, service: service,
            onChanged: (a, b, c) => changes.add((a, b, c)),
          )),
        ));

    testWidgets('a valid one is applied and used up', (tester) async {
      await PendingCoupon.save('SAVE20', service: 'taxi');
      await http.runWithClient(() async {
        await pumpBar(tester, 'taxi');
        await tester.pump();
        await tester.pump(kCouponRecheckDelay + const Duration(milliseconds: 50));
        await tester.pump();
        expect(jsonDecode(hits('/promos/preview').single.body)['code'], 'SAVE20');
        expect(changes.last, ('cash', 'SAVE20', 30));
        expect(find.text('−₹30'), findsOneWidget);
        expect(await PendingCoupon.load(), isNull);
        await tester.pump(const Duration(seconds: 5));
      }, api);
    });

    testWidgets('a refused one is dropped and cleared', (tester) async {
      valid = false;
      await PendingCoupon.save('OLD10');
      await http.runWithClient(() async {
        await pumpBar(tester, 'rental');
        await tester.pump();
        await tester.pump(kCouponRecheckDelay + const Duration(milliseconds: 50));
        await tester.pump();
        expect(changes.last, ('cash', '', 0));
        expect(find.text('Coupon'), findsOneWidget);
        expect(await PendingCoupon.load(), isNull);
        await tester.pump(const Duration(seconds: 5));
      }, api);
    });

    testWidgets("another service's code waits for its own booking", (tester) async {
      await PendingCoupon.save('PARCEL', service: 'delivery');
      await http.runWithClient(() async {
        await pumpBar(tester, 'taxi');
        await tester.pump();
        await tester.pump(kCouponRecheckDelay + const Duration(milliseconds: 50));
        expect(hits('/promos/preview'), isEmpty);
        expect((await PendingCoupon.load())?.code, 'PARCEL');
      }, api);
    });
  });

  // ── Emergency contacts on the server ──
  group('emergency contacts', () {
    late List<Map<String, dynamic>> server;

    setUp(() {
      server = [];
      route = (req) async {
        final p = req.url.path;
        if (p.endsWith('/user/sos-contacts') && req.method == 'GET') {
          return _json({'contacts': server, 'max': 5});
        }
        if (p.endsWith('/user/sos-contacts') && req.method == 'POST') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final c = {'id': 'c${server.length + 1}', 'name': b['name'], 'phone': b['phone'], 'relation': b['relation'] ?? ''};
          server.add(c);
          return _json({'contact': c}, 201);
        }
        if (p.contains('/user/sos-contacts/') && req.method == 'DELETE') {
          final id = p.split('/').last;
          server.removeWhere((c) => c['id'] == id);
          return _json({'success': true});
        }
        return _json({});
      };
    });

    test('sync uploads contacts saved only on this phone, once', () async {
      SharedPreferences.setMockInitialValues({
        'user_token': 't',
        'sos_contacts_v1': jsonEncode([
          {'name': 'Mom', 'phone': '+91 98765 43210', 'relation': 'Mother'},
          {'name': 'Landline', 'phone': '0221234567', 'relation': ''},
        ]),
      });
      server = [{'id': 's1', 'name': 'Dad', 'phone': '9123456789', 'relation': 'Father'}];
      await http.runWithClient(() async {
        final list = await EmergencyContactsStore.sync();
        expect(list.map((c) => c['name']), ['Dad', 'Mom']);
        expect(list.every((c) => (c['id'] ?? '').isNotEmpty), isTrue);
        expect(jsonDecode(hits('/user/sos-contacts', 'POST').single.body)['phone'], '9876543210');
        // Cached for offline SOS, and nothing re-sent next time.
        expect((await EmergencyContactsStore.load()).length, 2);
        await EmergencyContactsStore.sync();
        expect(hits('/user/sos-contacts', 'POST'), hasLength(1));
      }, api);
    });

    test('offline: the cached list is used', () async {
      SharedPreferences.setMockInitialValues({
        'sos_contacts_v1': jsonEncode([{'id': 'x', 'name': 'Mom', 'phone': '9876543210', 'relation': ''}]),
      });
      final list = await http.runWithClient(() => EmergencyContactsStore.sync(),
          () => MockClient((_) async => throw http.ClientException('offline')));
      expect(list.single['name'], 'Mom');
    });

    test('add checks the number; remove deletes on the server', () async {
      await http.runWithClient(() async {
        expect(await EmergencyContactsStore.add('Mom', '12345'), 'Enter a valid 10-digit mobile number');
        expect(await EmergencyContactsStore.add('', '9876543210'), 'Enter a name');
        expect(await EmergencyContactsStore.add('Mom', '098765 43210', relation: 'Mother'), isNull);
        expect(await EmergencyContactsStore.add('Mom again', '9876543210'), 'This number is already saved');
        final saved = await EmergencyContactsStore.load();
        expect(saved.single['id'], 'c1');
        expect(await EmergencyContactsStore.remove(saved.single), isNull);
        expect(hits('/user/sos-contacts/c1', 'DELETE'), hasLength(1));
        expect(await EmergencyContactsStore.load(), isEmpty);
      }, api);
    });
  });

  // ── SOS screen ──
  group('SOS screen', () {
    setUp(() {
      route = (req) async {
        final p = req.url.path;
        if (p.endsWith('/support/sos-alert')) return _json({'success': true, 'id': 'a1'});
        if (p.endsWith('/rides/active')) return _json({'ride': {'_id': 'live1', 'status': 'ongoing'}, 'blocksBooking': true});
        if (p.endsWith('/user/sos-contacts')) return _json({'contacts': [], 'max': 5});
        return _json({});
      };
    });

    Future<void> pumpSos(WidgetTester tester, {String? rideId}) => tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => UserProvider(),
          child: MaterialApp(home: EmergencyActionsScreen(rideId: rideId)),
        ));

    testWidgets('the alert waits 5 s and can be cancelled', (tester) async {
      await http.runWithClient(() async {
        await pumpSos(tester);
        await tester.pump();
        expect(find.byKey(const ValueKey('sos-countdown')), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(hits('/support/sos-alert'), isEmpty);
        await tester.tap(find.byKey(const ValueKey('sos-cancel')));
        await tester.pump(const Duration(seconds: 10));
        expect(hits('/support/sos-alert'), isEmpty, reason: 'a cancelled SOS sends nothing');
        expect(find.textContaining('cancelled'), findsOneWidget);
        // Changing their mind, the rider can still send it.
        await tester.tap(find.byKey(const ValueKey('sos-send-anyway')));
        await tester.pump();
        await tester.pump();
        expect(hits('/support/sos-alert'), hasLength(1));
        // With an active ride, the trip can be shared.
        expect(find.byKey(const ValueKey('sos-share-trip')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, api);
    });

    testWidgets('without a cancel the alert goes out after the countdown', (tester) async {
      await http.runWithClient(() async {
        await pumpSos(tester, rideId: 'r9');
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(hits('/support/sos-alert'), isEmpty);
        // Sent once the location lookup (started with the countdown) gives up.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(jsonDecode(hits('/support/sos-alert').single.body)['rideId'], 'r9');
        expect(find.textContaining('safety team has been alerted'), findsOneWidget);
        // The "manage contacts" link is a full-size tap target.
        final size = tester.getSize(find.byKey(const ValueKey('sos-manage-contacts')));
        expect(size.height, greaterThanOrEqualTo(48));
        await tester.pumpWidget(const SizedBox());
      }, api);
    });

    test('the SMS link carries every contact and an encoded body', () {
      final u = sosSmsUri(['98765 43210', '+919123456789'], sosShareMessage('https://goracabs.com/track/abc'));
      final s = u.toString();
      expect(s, startsWith('sms:9876543210,+919123456789?body='));
      expect(s, contains('https%3A%2F%2Fgoracabs.com%2Ftrack%2Fabc'));
      expect(s, isNot(contains('+Follow')));
    });
  });
}
