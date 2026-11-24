import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/screens/offers_screen.dart';
import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/services/payment_service.dart';
import 'package:customer_app/services/session_guard.dart';
import 'package:customer_app/utils/phone.dart';

// The shared HTTP layer and the payment helpers, against canned answers:
// where the token is kept, what a 401 does, the outstation prepayment's
// purpose, and the calls that used to crash or hang.

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('auth token storage', () {
    test('a token saved by an older build moves from SharedPreferences to secure storage, once', () async {
      SharedPreferences.setMockInitialValues({'user_token': 'legacy-token'});
      expect(await ApiService.getToken(), 'legacy-token');
      expect(await const FlutterSecureStorage().read(key: 'user_token'), 'legacy-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_token'), isNull, reason: 'no plain copy left behind');
      // And it is read from secure storage from then on.
      expect(await ApiService.getToken(), 'legacy-token');
    });

    test('saveToken writes only to secure storage; clearToken removes every copy', () async {
      SharedPreferences.setMockInitialValues({'user_token': 'old'});
      await ApiService.saveToken('fresh');
      expect(await const FlutterSecureStorage().read(key: 'user_token'), 'fresh');
      expect((await SharedPreferences.getInstance()).getString('user_token'), isNull);
      expect(await ApiService.getToken(), 'fresh');
      await ApiService.clearToken();
      expect(await ApiService.getToken(), isNull);
      expect(await const FlutterSecureStorage().read(key: 'user_token'), isNull);
    });

    test('the token is sent as a Bearer header', () async {
      await ApiService.saveToken('tok-1');
      String? auth;
      await http.runWithClient(() => ApiService.get('/wallet'), () => MockClient((req) async {
        auth = req.headers['Authorization'];
        return _json({'balance': 0, 'transactions': []});
      }));
      expect(auth, 'Bearer tok-1');
    });
  });

  group('401', () {
    test('two 401s at once sign out once, and clear the token', () async {
      await ApiService.saveToken('expired');
      final before = SessionGuard.signOuts.value;
      final api = MockClient((req) async => _json({'error': 'Unauthorized'}, 401));
      final res = await http.runWithClient(
          () => Future.wait([ApiService.get('/rides/user'), ApiService.get('/wallet')]), () => api);
      await pumpEventQueue();
      expect(res.first['httpStatus'], 401);
      expect(SessionGuard.signOuts.value, before + 1);
      expect(SessionGuard.signedOut, isTrue);
      expect(await ApiService.getToken(), isNull);
      // Signing in again re-arms it.
      await ApiService.saveToken('new');
      expect(SessionGuard.signedOut, isFalse);
    });

    test('401 {accountDeleted} is left to the account-deletion flow', () async {
      await ApiService.saveToken('t');
      final before = SessionGuard.signOuts.value;
      await http.runWithClient(() => ApiService.get('/auth/user/profile'),
          () => MockClient((req) async => _json({'error': 'Unauthorized', 'accountDeleted': true}, 401)));
      expect(SessionGuard.signOuts.value, before);
    });

    test('a 402 / 409 keeps its status for the caller', () async {
      await ApiService.saveToken('t');
      final r = await http.runWithClient(() => ApiService.post('/rides/book', {}, auth: true),
          () => MockClient((req) async => _json({'error': 'x', 'code': 'prepaymentRequired'}, 402)));
      expect(r['httpStatus'], 402);
      expect(SessionGuard.signedOut, isFalse);
    });
  });

  group('outstation prepayment', () {
    late List<http.Request> calls;
    MockClient api() => MockClient((req) async {
      calls.add(req);
      final p = req.url.path;
      if (p.endsWith('/payment/razorpay/order')) return _json({'orderId': 'order_9', 'keyId': 'k', 'amount': 540000});
      if (p.endsWith('/payment/razorpay/verify')) return _json({'success': true, 'paymentId': 'pay_9'});
      if (p.endsWith('/wallet/pay')) return _json({'success': true, 'balance': 100});
      return _json({});
    });

    setUp(() {
      calls = [];
      PaymentService.openCheckout = (o) async =>
          const CheckoutOutcome.paid(paymentId: 'pay_9', orderId: 'order_9', signature: 'sig_9');
    });

    testWidgets("online: a Razorpay order with purpose 'outstation_prepay' and no ride id", (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      final ctx = tester.element(find.byType(SizedBox));
      PaymentResult? r;
      await http.runWithClient(() async {
        r = await PaymentService.prepayOutstation(ctx, method: 'online', amount: 5400);
      }, api);
      final order = calls.firstWhere((c) => c.url.path.endsWith('/order'));
      expect(jsonDecode(order.body), {'amount': 5400, 'purpose': 'outstation_prepay'});
      final verify = calls.firstWhere((c) => c.url.path.endsWith('/verify'));
      expect(jsonDecode(verify.body), {'orderId': 'order_9', 'paymentId': 'pay_9', 'signature': 'sig_9', 'purpose': 'outstation_prepay'});
      expect(r!.success, isTrue);
      expect(r!.bookingProof, {'orderId': 'order_9', 'paymentId': 'pay_9', 'signature': 'sig_9'},
          reason: 'sent with the booking as `prepaid`');
    });

    testWidgets('wallet: debited with no ride id (the booking links it)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      final ctx = tester.element(find.byType(SizedBox));
      await http.runWithClient(() async {
        await PaymentService.prepayOutstation(ctx, method: 'wallet', amount: 5400);
      }, api);
      final pay = calls.single;
      expect(pay.url.path, endsWith('/wallet/pay'));
      expect((jsonDecode(pay.body) as Map).containsKey('rideId'), isFalse);
      expect(jsonDecode(pay.body)['amount'], 5400);
    });

    testWidgets('cash: nothing is charged', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      final ctx = tester.element(find.byType(SizedBox));
      await http.runWithClient(() async {
        await PaymentService.prepayOutstation(ctx, method: 'cash', amount: 5400);
      }, api);
      expect(calls, isEmpty);
    });
  });

  group('calls that used to crash or hang', () {
    test('place details: an error answer is null, string coordinates become numbers', () async {
      final err = await http.runWithClient(() => ApiService.placeDetails('bad'),
          () => MockClient((req) async => _json({'error': 'Place not found'}, 404)));
      expect(err, isNull);
      final ok = await http.runWithClient(() => ApiService.placeDetails('ok'),
          () => MockClient((req) async => _json({'lat': '23.02', 'lng': 72.57, 'address': null})));
      expect(ok!['lat'], 23.02);
      expect(ok['lng'], 72.57);
      expect(ok['address'], '');
      final html = await http.runWithClient(() => ApiService.placeDetails('x'),
          () => MockClient((req) async => http.Response('<html>502</html>', 502)));
      expect(html, isNull);
    });

    testWidgets('an upload that never answers gives up instead of hanging', (tester) async {
      final never = Completer<http.Response>();
      String? url = 'pending';
      var done = false;
      http.runWithClient(() async {
        url = await ApiService.uploadImage(XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'p.jpg'));
        done = true;
      }, () => MockClient((req) => never.future));
      await tester.pump(const Duration(seconds: 30));
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 31));
      expect(done, isTrue, reason: 'timed out after ${ApiService.uploadTimeout.inSeconds}s');
      expect(url, isNull);
    });

    test('an upload answer without a url is null, not a cast error', () async {
      final r = await http.runWithClient(
          () => ApiService.uploadImage(XFile.fromData(Uint8List.fromList([1]), name: 'p.jpg')),
          () => MockClient((req) async => _json({'error': 'Too large'}, 413)));
      expect(r, isNull);
    });

    test('offer colours: every admin format, and junk falls back', () {
      expect(offerColor('0xFF0A3CC8'), const Color(0xFF0A3CC8));
      expect(offerColor('#E91E63'), const Color(0xFFE91E63));
      expect(offerColor('E91E63'), const Color(0xFFE91E63));
      expect(offerColor(0xFF112233), const Color(0xFF112233));
      expect(offerColor('red'), const Color(0xFF0A3CC8));
      expect(offerColor(null), const Color(0xFF0A3CC8));
      expect(offerColor(''), const Color(0xFF0A3CC8));
    });
  });

  group('OTP login numbers', () {
    test('only 10-digit Indian mobiles (6-9 first), tidied', () {
      expect(indianMobile('9876543210'), '9876543210');
      expect(indianMobile('+91 98765 43210'), '9876543210');
      expect(indianMobile('098765-43210'), '9876543210');
      expect(indianMobile('919876543210'), '9876543210');
      expect(indianMobile('5876543210'), isNull, reason: 'not a mobile');
      expect(indianMobile('98765'), isNull);
      expect(indianMobile('98765432101'), isNull);
      expect(indianMobile('abcdefghij'), isNull);
    });
  });
}
