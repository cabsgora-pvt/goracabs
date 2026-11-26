import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/widgets/payment_coupon_bar.dart';

// The booking screens' coupon pill: the discount is the SERVER's
// (POST /api/promos/preview for this trip), never worked out on the phone.

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

class _Host extends StatefulWidget {
  final num fare;
  final void Function(String, String, int) onChanged;
  const _Host({required this.fare, required this.onChanged});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late num fare = widget.fare;
  num tip = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          PaymentCouponBar(
            baseFare: fare, tip: tip, service: 'rental', pickupLat: 23.02, pickupLng: 72.57,
            onChanged: widget.onChanged,
          ),
          TextButton(onPressed: () => setState(() => fare += 10), child: const Text('bump fare')),
          TextButton(onPressed: () => setState(() => tip = 20), child: const Text('add tip')),
        ]),
      );
}

void main() {
  late List<Map<String, dynamic>> previews;
  late Future<http.Response> Function(Map<String, dynamic> body) answer;
  late List<(String, String, int)> changes;

  MockClient api() => MockClient((req) async {
        if (req.url.path.endsWith('/promos/preview')) {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          previews.add(b);
          return answer(b);
        }
        if (req.url.path.endsWith('/payment/config')) {
          return _json({'razorpay': {'enabled': false}, 'cashEnabled': true, 'walletEnabled': true});
        }
        if (req.url.path.endsWith('/wallet')) return _json({'balance': 0});
        return _json({});
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previews = [];
    changes = [];
    answer = (b) async => _json({'valid': true, 'discount': 40, 'code': b['code'], 'fare': b['fare'], 'tip': b['tip'],
      'payable': (b['fare'] as num) + (b['tip'] as num) - 40});
  });

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: _Host(fare: 400, onChanged: (a, b, c) => changes.add((a, b, c)))));
        await tester.pump();
        await body();
      }, api);

  Future<void> apply(WidgetTester tester, String code) async {
    await tester.tap(find.text('Coupon'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.byKey(const ValueKey('coupon-apply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets("the pill shows the server's discount for this trip", (tester) async {
    await run(tester, () async {
      await apply(tester, 'gora10');
      expect(previews.single, {'code': 'GORA10', 'service': 'rental', 'fare': 400, 'tip': 0,
        'pickupLat': 23.02, 'pickupLng': 72.57});
      expect(find.text('−₹40'), findsOneWidget);
      expect(find.text('Coupon applied: −₹40 · you pay ₹360'), findsOneWidget);
      expect(changes.last, ('cash', 'GORA10', 40));
    });
  });

  testWidgets("a refused code shows the server's reason and is dropped", (tester) async {
    answer = (b) async => _json({'valid': false, 'discount': 0, 'reason': 'Minimum fare ₹500', 'code': 'BIG',
      'fare': 400, 'tip': 0, 'payable': 400});
    await run(tester, () async {
      await apply(tester, 'BIG');
      expect(find.text('Coupon not applied: Minimum fare ₹500'), findsOneWidget);
      expect(find.text('Coupon'), findsOneWidget);
      expect(changes.last, ('cash', '', 0));
    });
  });

  testWidgets('offline: the code is kept, "checked at booking", no discount claimed', (tester) async {
    answer = (b) async => throw const SocketException('offline');
    await run(tester, () async {
      await apply(tester, 'GORA10');
      expect(find.textContaining('checked at booking'), findsWidgets);
      expect(find.text('GORA10 · checked at booking'), findsOneWidget);
      expect(changes.last, ('cash', 'GORA10', 0));
    });
  });

  testWidgets('a fare / tip change re-checks once, after it settles', (tester) async {
    await run(tester, () async {
      await apply(tester, 'GORA10');
      expect(previews, hasLength(1));
      // Three quick changes: one check, with the latest figures.
      await tester.tap(find.text('bump fare'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('bump fare'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('add tip'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(previews, hasLength(1));
      await tester.pump(kCouponRecheckDelay);
      await tester.pump();
      expect(previews, hasLength(2));
      expect(previews.last['fare'], 420);
      expect(previews.last['tip'], 20);
      // ScaffoldMessenger timers from the apply snack bar.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  test('CouponCheck reads the preview answer', () {
    final ok = CouponCheck.fromResponse({'valid': true, 'discount': 50, 'payable': 350});
    expect((ok.valid, ok.discount, ok.payable), (true, 50, 350));
    final no = CouponCheck.fromResponse({'valid': false, 'discount': 0, 'reason': 'Expired', 'payable': 400});
    expect((no.valid, no.discount, no.message()), (false, 0, 'Coupon not applied: Expired'));
    final err = CouponCheck.fromResponse({'error': 'Enter a code', 'code': 'codeRequired', 'httpStatus': 400});
    expect(err.valid, isNull);
    expect(err.message(), contains('checked at booking'));
  });
}
