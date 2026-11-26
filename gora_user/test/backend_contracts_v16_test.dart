import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/config/app_config.dart';
import 'package:customer_app/config/app_version.dart';
import 'package:customer_app/screens/active_ride_screen.dart' show trackingLinkFor;
import 'package:customer_app/screens/emergency_actions_screen.dart' show sosAlertStatusOf;
import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/services/payment_service.dart';
import 'package:customer_app/services/session_guard.dart';
import 'package:customer_app/services/session_refresh.dart';
import 'package:customer_app/services/update_gate.dart';
import 'package:customer_app/utils/active_ride.dart';
import 'package:customer_app/utils/ride_booking.dart' show excessRefundMessage;

// The rider app against the backend contracts of the v1.6.0 re-audit: exact
// field names and status codes as goraadmin's routes send them.

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// A JWT-shaped token whose payload carries [iat] (seconds). Unsigned: the
/// app only reads its age.
String _jwt(DateTime issued) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'id': 'u1', 'type': 'user', 'iat': issued.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sign-out codes (lib/auth activeDenied)', () {
    test('which answers sign the rider out, and why', () {
      expect(SessionGuard.signOutReasonFor(401, {'code': 'SESSION_REVOKED'}), SignOutReason.revoked);
      expect(SessionGuard.signOutReasonFor(401, {'code': 'ACCOUNT_DELETED'}), SignOutReason.deleted);
      expect(SessionGuard.signOutReasonFor(401, {'error': 'Unauthorized'}), SignOutReason.expired);
      expect(SessionGuard.signOutReasonFor(403, {'code': 'ACCOUNT_BLOCKED'}), SignOutReason.blocked);
      expect(SessionGuard.signOutReasonFor(403, {'code': 'ACCOUNT_DELETED'}), SignOutReason.deleted);
      // Left to the account deletion flow.
      expect(SessionGuard.signOutReasonFor(401, {'accountDeleted': true, 'code': 'ACCOUNT_DELETED'}), isNull);
      // A 403 about one request never signs out.
      expect(SessionGuard.signOutReasonFor(403, {'code': 'NOT_PARTICIPANT'}), isNull);
      expect(SessionGuard.signOutReasonFor(403, {'error': 'The driver must end the trip', 'driverMustEnd': true}), isNull);
      expect(SessionGuard.signOutReasonFor(403, {'accountHold': true, 'error': 'Your account is on hold'}), isNull);
      expect(SessionGuard.signOutReasonFor(403, {'error': 'Not a participant in this ride'}), isNull);
      expect(SessionGuard.signOutReasonFor(409, {'code': 'ACCOUNT_BLOCKED'}), isNull);
      expect(SessionGuard.messageFor(SignOutReason.blocked), 'Your account is blocked, contact support');
    });

    test('403 ACCOUNT_BLOCKED signs out once and clears the token', () async {
      await ApiService.saveToken('t');
      final before = SessionGuard.signOuts.value;
      await http.runWithClient(() => ApiService.post('/wallet/pay', {'rideId': 'r'}, auth: true),
          () => MockClient((_) async => _json({'error': 'Your account is blocked. Please contact support.', 'code': 'ACCOUNT_BLOCKED'}, 403)));
      await pumpEventQueue();
      expect(SessionGuard.signOuts.value, before + 1);
      expect(SessionGuard.lastReason, SignOutReason.blocked);
      expect(await ApiService.getToken(), isNull);
    });

    test('403 NOT_PARTICIPANT / driverMustEnd leave the rider signed in', () async {
      await ApiService.saveToken('t');
      final before = SessionGuard.signOuts.value;
      final res = await http.runWithClient(() => ApiService.get('/rides/x/share-token'),
          () => MockClient((_) async => _json({'error': 'Not your ride', 'code': 'NOT_PARTICIPANT'}, 403)));
      await http.runWithClient(() => ApiService.get('/rides/x'),
          () => MockClient((_) async => _json({'error': 'The driver ends this trip', 'driverMustEnd': true}, 403)));
      await pumpEventQueue();
      expect(res['httpStatus'], 403);
      expect(SessionGuard.signOuts.value, before);
      expect(SessionGuard.signedOut, isFalse);
      expect(await ApiService.getToken(), 't');
    });

    test('401 SESSION_REVOKED signs out with its own reason', () async {
      await ApiService.saveToken('t');
      await http.runWithClient(() => ApiService.get('/auth/user/profile'),
          () => MockClient((_) async => _json({'error': 'Your session has ended.', 'code': 'SESSION_REVOKED'}, 401)));
      await pumpEventQueue();
      expect(SessionGuard.lastReason, SignOutReason.revoked);
      expect(await ApiService.getToken(), isNull);
    });
  });

  group('sliding session (POST /api/auth/refresh)', () {
    final now = DateTime.utc(2026, 11, 25, 12);

    test('due when refreshAfter has passed, or — unknown — the token is over a day old', () {
      final old = _jwt(now.subtract(const Duration(days: 2)));
      final fresh = _jwt(now.subtract(const Duration(hours: 3)));
      expect(SessionRefresher.issuedAt(fresh), now.subtract(const Duration(hours: 3)));
      expect(SessionRefresher.isDue(old, at: now), isTrue);
      expect(SessionRefresher.isDue(fresh, at: now), isFalse);
      expect(SessionRefresher.isDue('not-a-jwt', at: now), isFalse);
      // The server's refreshAfter wins over the token's own age.
      expect(SessionRefresher.isDue(fresh, refreshAfter: now.subtract(const Duration(minutes: 1)), at: now), isTrue);
      expect(SessionRefresher.isDue(old, refreshAfter: now.add(const Duration(hours: 1)), at: now), isFalse);
    });

    test('a due token is swapped and the new one stored where the old one was', () async {
      final old = _jwt(DateTime.now().toUtc().subtract(const Duration(days: 2)));
      await ApiService.saveToken(old);
      String? sentAuth;
      final saved = await http.runWithClient(SessionRefresher.maybeRefresh, () => MockClient((req) async {
        expect(req.url.path, '/api/auth/refresh');
        expect(req.method, 'POST');
        sentAuth = req.headers['Authorization'];
        return _json({'token': 'NEW', 'type': 'user', 'expiresIn': 604800,
          'refreshAfter': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String()});
      }));
      expect(saved, isTrue);
      expect(sentAuth, 'Bearer $old');
      expect(await ApiService.getToken(), 'NEW');
      expect(SessionRefresher.refreshAfter!.isAfter(DateTime.now()), isTrue);
    });

    test('409 TOO_EARLY is ignored: the token stays, its refreshAfter is kept', () async {
      SessionRefresher.noteRefreshAfter(DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String());
      await ApiService.saveToken('keep');
      final later = DateTime.now().toUtc().add(const Duration(hours: 5));
      final saved = await http.runWithClient(SessionRefresher.maybeRefresh, () => MockClient((req) async =>
          _json({'error': 'Token is still fresh', 'code': 'TOO_EARLY', 'refreshAfter': later.toIso8601String()}, 409)));
      expect(saved, isFalse);
      expect(await ApiService.getToken(), 'keep');
      expect(SessionGuard.signedOut, isFalse);
      expect(SessionRefresher.refreshAfter, later);
    });

    test('a token not yet due makes no call', () async {
      await ApiService.saveToken(_jwt(DateTime.now().toUtc().subtract(const Duration(hours: 1))));
      var calls = 0;
      await http.runWithClient(SessionRefresher.maybeRefresh, () => MockClient((_) async { calls++; return _json({}); }));
      expect(calls, 0);
    });
  });

  group('force update (config.version)', () {
    test('compareVersions', () {
      expect(compareVersions('1.6.0', '1.6.0'), 0);
      expect(compareVersions('1.6.0', '1.10.0'), -1);
      expect(compareVersions('1.6', '1.6.0'), 0);
      expect(compareVersions('2.0.0', '1.9.9'), 1);
      expect(compareVersions('1.6.0+12', '1.6.1'), -1);
      expect(compareVersions('abc', '1.0.0'), isNull);
    });

    test('below min → required; forceUpdate below latest → required; below latest → banner', () {
      AppVersionPolicy p({String latest = '1.6.0', String min = '1.0.0', bool force = false}) =>
          AppVersionPolicy(latestVersion: latest, minVersion: min, forceUpdate: force);
      expect(updateLevelFor('1.6.0', p()), UpdateLevel.none);
      expect(updateLevelFor('1.6.0', p(latest: '1.7.0')), UpdateLevel.optional);
      expect(updateLevelFor('1.6.0', p(latest: '1.7.0', force: true)), UpdateLevel.required);
      expect(updateLevelFor('1.6.0', p(latest: '1.7.0', min: '1.6.1')), UpdateLevel.required);
      // forceUpdate with nothing newer does not block.
      expect(updateLevelFor('1.6.0', p(force: true)), UpdateLevel.none);
      expect(updateLevelFor('1.6.0', null), UpdateLevel.none);
    });

    test('the banner shows once per session: closed, it stays closed', () {
      UpdateGate.currentVersion = '1.6.0';
      const p = AppVersionPolicy(latestVersion: '1.7.0', minVersion: '1.0.0');
      UpdateGate.apply(p);
      expect(UpdateGate.state.value.level, UpdateLevel.optional);
      UpdateGate.dismissBanner();
      expect(UpdateGate.state.value.level, UpdateLevel.none);
      UpdateGate.apply(p);
      expect(UpdateGate.state.value.level, UpdateLevel.none);
      // A required update is never dismissed by that.
      UpdateGate.apply(const AppVersionPolicy(latestVersion: '1.7.0', minVersion: '1.7.0'));
      expect(UpdateGate.state.value.level, UpdateLevel.required);
    });

    test('check() reads GET /app-config?app=user', () async {
      Uri? asked;
      await http.runWithClient(() => UpdateGate.check(force: true), () => MockClient((req) async {
        asked = req.url;
        return _json({'config': {'app': 'user', 'version': {'latestVersion': '9.0.0', 'minVersion': '9.0.0',
          'forceUpdate': false, 'message': 'Please update', 'storeUrl': 'https://example.com/app'}}});
      }));
      expect(asked!.path, '/api/app-config');
      expect(asked!.queryParameters['app'], 'user');
      expect(UpdateGate.state.value.level, UpdateLevel.required);
      expect(UpdateGate.state.value.policy!.message, 'Please update');
    });

    test('kAppVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec)!;
      expect(kAppVersion, m.group(1));
      expect(kAppVersion, '1.6.0');
    });
  });

  group('GET /rides/active', () {
    test('a live ride shows and blocks as the server says', () {
      final st = ActiveRideState.fromResponse({'ride': {'id': 'r1', 'status': 'accepted'}, 'blocksBooking': true})!;
      expect(st.ride!['id'], 'r1');
      expect(st.blocksBooking, isTrue);
      // Under review for over 30 min: shown, but booking is allowed.
      final rev = ActiveRideState.fromResponse(
          {'ride': {'id': 'r2', 'status': 'ongoing', 'needsReview': true}, 'blocksBooking': false})!;
      expect(rev.ride, isNotNull);
      expect(rev.blocksBooking, isFalse);
    });

    test('nothing, an error, and a cash ride awaiting the driver', () {
      expect(ActiveRideState.fromResponse({'ride': null, 'blocksBooking': false})!.ride, isNull);
      expect(ActiveRideState.fromResponse({'error': 'Server error', 'httpStatus': 500}), isNull);
      final cash = ActiveRideState.fromResponse({'ride': {'status': 'completed', 'awaitingPayment': true,
        'paymentMode': 'cash', 'paymentStatus': 'pending'}, 'blocksBooking': false})!;
      expect(cash.ride, isNull);
    });

    test('an unpaid online ride, and a prepaid shortfall by wallet / online, keep the rider on it', () {
      Map<String, dynamic> done(String mode, {bool shortfall = false, String service = 'taxi'}) => {
        'status': 'completed', 'awaitingPayment': true, 'paymentMode': mode, 'paymentStatus': 'pending',
        'service': service, if (shortfall) 'prepaidShortfall': true,
      };
      expect(riderMustPay(done('online')), isTrue);
      expect(riderMustPay(done('wallet')), isFalse, reason: 'debited by the server at End');
      expect(riderMustPay(done('wallet', shortfall: true, service: 'outstation')), isTrue);
      expect(riderMustPay(done('online', shortfall: true, service: 'outstation')), isTrue);
      expect(riderMustPay(done('cash', shortfall: true, service: 'outstation')), isFalse);
      expect(riderMustPay({...done('online'), 'paymentStatus': 'paid'}), isFalse);
      final st = ActiveRideState.fromResponse({'ride': done('online'), 'blocksBooking': false})!;
      expect(st.ride, isNotNull);
      expect(st.blocksBooking, isTrue, reason: 'as before: pay the last ride first');
    });

    test('the paths: /rides/active, /rides/user?limit&page, /rides/{id}?lite=1', () async {
      final asked = <Uri>[];
      await http.runWithClient(() async {
        await ApiService.getActiveRide();
        await ApiService.getMyRides(limit: 20, page: 3);
        await ApiService.getRide('abc', lite: true);
        await ApiService.getRide('abc');
      }, () => MockClient((req) async { asked.add(req.url); return _json({}); }));
      expect(asked[0].path, '/api/rides/active');
      expect(asked[1].path, '/api/rides/user');
      expect(asked[1].queryParameters, {'limit': '20', 'page': '3'});
      expect(asked[2].queryParameters, {'lite': '1'});
      expect(asked[3].query, isEmpty);
    });
  });

  group('share trip (GET /rides/{id}/share-token)', () {
    test('the link carries the share token', () async {
      final link = await http.runWithClient(() => trackingLinkFor('ride1'), () => MockClient((req) async {
        expect(req.url.path, '/api/rides/ride1/share-token');
        return _json({'shareToken': 'tok_AbC123', 'path': '/track/tok_AbC123', 'status': 'accepted'});
      }));
      expect(link, '${AppConfig.serverBaseUrl}/track/tok_AbC123');
    });

    test('falls back to the ride-id link only when the token cannot be had', () async {
      final a = await http.runWithClient(() => trackingLinkFor('ride1'),
          () => MockClient((_) async => _json({'error': 'Server error'}, 500)));
      expect(a, '${AppConfig.serverBaseUrl}/track/ride1');
      final b = await http.runWithClient(() => trackingLinkFor('ride1'),
          () => MockClient((_) async => throw const SocketException('offline')));
      expect(b, '${AppConfig.serverBaseUrl}/track/ride1');
    });
  });

  group('extension confirm body', () {
    test('confirm sends requestedAt and amount of the request seen; decline sends neither', () async {
      final bodies = <Map<String, dynamic>>[];
      final paths = <String>[];
      final ext = {'kind': 'hire', 'hours': 2, 'amount': 300, 'requestedAt': '2026-11-24T09:00:00.000Z'};
      await http.runWithClient(() async {
        await ApiService.answerExtension('r1', 'hire_driver', confirm: true, extension: ext);
        await ApiService.answerExtension('r1', 'rental', confirm: false, extension: ext);
      }, () => MockClient((req) async {
        paths.add(req.url.path);
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({'success': true});
      }));
      expect(paths, ['/api/rides/r1/hire', '/api/rides/r1/rental']);
      expect(bodies[0], {'action': 'confirm_extend', 'requestedAt': '2026-11-24T09:00:00.000Z', 'amount': 300});
      expect(bodies[1], {'action': 'decline_extend'});
    });
  });

  group('payment robustness', () {
    setUp(() {
      PaymentService.openCheckout = (opts) async =>
          CheckoutOutcome.paid(paymentId: 'pay_1', orderId: '${opts['order_id']}', signature: 'sig_1');
    });

    test('verifyIsFinal', () {
      expect(PaymentService.verifyIsFinal({'success': true}), isTrue);
      expect(PaymentService.verifyIsFinal({'success': true, 'alreadyCredited': true}), isTrue);
      expect(PaymentService.verifyIsFinal({'success': false, 'alreadyProcessed': true}), isTrue);
      expect(PaymentService.verifyIsFinal({'error': 'Payment verification failed', 'httpStatus': 400}), isTrue);
      expect(PaymentService.verifyIsFinal({'error': 'x', 'code': 'amountShort', 'httpStatus': 402}), isTrue);
      expect(PaymentService.verifyIsFinal({'error': 'Could not confirm', 'httpStatus': 502}), isFalse);
      expect(PaymentService.verifyIsFinal({'error': 'Payment not completed yet', 'httpStatus': 400}), isFalse);
      expect(PaymentService.verifyIsFinal({'error': 'no connection'}), isFalse);
      expect(PaymentService.verifyIsFinal({'error': 'Unauthorized', 'httpStatus': 401}), isFalse);
    });

    test('the proof is saved BEFORE verify, kept when verify fails, and retried until it settles', () async {
      await ApiService.saveToken('t');
      List<Map<String, dynamic>>? savedAtVerify;
      var verifyOk = false;
      final api = MockClient((req) async {
        if (req.url.path.endsWith('/payment/razorpay/order')) {
          return _json({'orderId': 'order_1', 'keyId': 'rzp_test', 'amount': 50000, 'currency': 'INR'});
        }
        if (req.url.path.endsWith('/payment/razorpay/verify')) {
          savedAtVerify ??= await PendingPaymentProofs.load();
          final b = jsonDecode(req.body);
          expect(b, {'orderId': 'order_1', 'paymentId': 'pay_1', 'signature': 'sig_1', 'purpose': 'wallet'});
          return verifyOk
              ? _json({'success': true, 'alreadyCredited': true, 'balance': 500})
              : _json({'error': 'Could not confirm the payment with Razorpay'}, 502);
        }
        return _json({});
      });
      final r = await http.runWithClient(() => PaymentService.topUpWallet(amount: 500), () => api);
      expect(r.success, isFalse);
      expect(r.error, PaymentService.confirmingLater);
      expect(savedAtVerify, hasLength(1));
      expect(savedAtVerify!.single['paymentId'], 'pay_1');
      expect(savedAtVerify!.single['orderId'], 'order_1');
      expect(await PendingPaymentProofs.load(), hasLength(1), reason: 'kept for the next start / resume');

      // Next resume, still down: kept.
      expect(await http.runWithClient(PaymentService.retryPendingProofs, () => api), 0);
      expect(await PendingPaymentProofs.load(), hasLength(1));
      // Back up: settled (alreadyCredited) and cleared.
      verifyOk = true;
      expect(await http.runWithClient(PaymentService.retryPendingProofs, () => api), 1);
      expect(await PendingPaymentProofs.load(), isEmpty);
    });

    test('a ride payment proof carries the ride id, and a verified payment leaves nothing behind', () async {
      await ApiService.saveToken('t');
      Map<String, dynamic>? body;
      final api = MockClient((req) async {
        if (req.url.path.endsWith('/order')) return _json({'orderId': 'order_9', 'keyId': 'k', 'amount': 100});
        if (req.url.path.endsWith('/verify')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'success': true, 'paymentStatus': 'paid', 'amountPaid': 1, 'amountDue': 1});
        }
        return _json({});
      });
      final r = await http.runWithClient(() => PaymentService.payRide(rideId: 'ride9', amountDue: 1), () => api);
      expect(r.paid, isTrue);
      expect(body!['rideId'], 'ride9');
      expect(body!['purpose'], 'ride');
      expect(await PendingPaymentProofs.load(), isEmpty);
    });

    test('a payment-config error is not cached; a real config is', () async {
      var calls = 0;
      var fail = true;
      final api = MockClient((req) async {
        calls++;
        return fail
            ? _json({'error': 'Bad gateway'}, 502)
            : _json({'razorpay': {'enabled': true, 'keyId': 'k', 'mode': 'live'}, 'cashEnabled': true, 'walletEnabled': true});
      });
      final a = await http.runWithClient(() => ApiService.getPaymentConfig(), () => api);
      expect((a['razorpay'] as Map)['enabled'], false);
      fail = false;
      final b = await http.runWithClient(() => ApiService.getPaymentConfig(), () => api);
      expect((b['razorpay'] as Map)['enabled'], true);
      await http.runWithClient(() => ApiService.getPaymentConfig(), () => api);
      expect(calls, 2, reason: 'the error was asked again; the real answer was cached');
    });

    test('wallet/pay for a ride: notPayableYet → "Pay after the trip ends."', () async {
      await ApiService.saveToken('t');
      Map<String, dynamic>? sent;
      final msg = await http.runWithClient(() => PaymentService.payRideFromWallet('r5'), () => MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'error': 'This ride can be paid once it has ended', 'code': 'notPayableYet', 'rideStatus': 'ongoing'}, 409);
      }));
      expect(sent, {'rideId': 'r5'});
      expect(msg, 'Pay after the trip ends.');
      final ok = await http.runWithClient(() => PaymentService.payRideFromWallet('r5'),
          () => MockClient((_) async => _json({'success': true, 'amount': 120, 'balance': 30})));
      expect(ok, isNull);
    });
  });

  group('promo preview, report-issue, SOS, excess refund', () {
    test('POST /promos/preview body', () async {
      Map<String, dynamic>? body;
      final res = await http.runWithClient(
          () => ApiService.previewPromo(code: 'GORA10', service: 'outstation', fare: 5400, tip: 0, pickupLat: 23.0, pickupLng: 72.5),
          () => MockClient((req) async {
            expect(req.url.path, '/api/promos/preview');
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return _json({'valid': true, 'discount': 540, 'code': 'GORA10', 'fare': 5400, 'tip': 0, 'payable': 4860});
          }));
      expect(body, {'code': 'GORA10', 'service': 'outstation', 'fare': 5400, 'tip': 0, 'pickupLat': 23.0, 'pickupLng': 72.5});
      expect(res['payable'], 4860);
    });

    test('POST /rides/{id}/report-issue body', () async {
      Map<String, dynamic>? body;
      await http.runWithClient(() => ApiService.reportRideIssue('r1', 'other', note: '  wrong car  '),
          () => MockClient((req) async {
            expect(req.url.path, '/api/rides/r1/report-issue');
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return _json({'success': true, 'needsReview': true, 'status': 'accepted'});
          }));
      expect(body, {'kind': 'other', 'note': 'wrong car'});
    });

    test('SOS: deduped and 429 both mean the team has it', () {
      expect(sosAlertStatusOf({'success': true, 'id': 'a1'}).sent, isTrue);
      expect(sosAlertStatusOf({'success': true, 'id': 'a1', 'deduped': true}).sent, isTrue);
      final limited = sosAlertStatusOf({'error': 'SOS already sent.', 'code': 'RATE_LIMITED', 'httpStatus': 429});
      expect(limited.sent, isTrue);
      expect(limited.message, contains('already sent'));
      expect(sosAlertStatusOf({'error': 'Server error', 'httpStatus': 500}).sent, isFalse);
    });

    test('prepaidExcessRefunded → "₹X extra refunded to wallet"', () {
      expect(excessRefundMessage(150), '₹150 extra refunded to wallet');
      expect(excessRefundMessage(12.5), '₹12.50 extra refunded to wallet');
      expect(excessRefundMessage(0), isNull);
      expect(excessRefundMessage(null), isNull);
    });
  });
}
