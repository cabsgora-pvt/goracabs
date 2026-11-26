import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/wallet_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Wallet: a failed load is an error with Retry, never "₹0.00"; transactions in
// rupees and paise with what they were and the balance after; source filter;
// top-up amount digits only, within the min / max.
// ─────────────────────────────────────────────────────────────────────────────

Widget _app(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

final _wallet = {
  'balance': 412.5,
  'transactions': [
    {'_id': 't1', 'type': 'debit', 'amount': 87.5, 'balanceAfter': 412.5, 'note': 'Ride to Station Rd', 'source': 'ride',
     'createdAt': '2026-10-20T10:00:00.000Z'},
    {'_id': 't2', 'type': 'credit', 'amount': 500, 'balanceAfter': 500, 'note': '', 'source': 'recharge',
     'createdAt': '2026-10-19T10:00:00.000Z'},
    {'_id': 't3', 'type': 'credit', 'amount': 0.75, 'balanceAfter': 0, 'note': 'Refund for cancelled ride', 'source': 'refund',
     'createdAt': '2026-10-18T10:00:00.000Z'},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a failed load shows an error and Retry, never ₹0', (tester) async {
    var fail = true;
    var calls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const WalletScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('wallet-error')), findsOneWidget);
      expect(find.textContaining('₹0'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('wallet-retry')));
      await settle(tester);
    }, () => MockClient((req) async {
      if (req.url.path.endsWith('/wallet')) {
        calls++;
        return fail ? http.Response('<html>502</html>', 502) : http.Response(jsonEncode(_wallet), 200);
      }
      return http.Response('{}', 200);
    }));
    expect(calls, 2);
    expect(find.byKey(const ValueKey('wallet-error')), findsNothing);
    expect(find.text('₹412.50'), findsOneWidget);
  });

  testWidgets('offline load says offline', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const WalletScreen()));
      await settle(tester);
    }, () => MockClient((req) async => throw http.ClientException('Failed host lookup')));
    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('transactions: 2 decimals, source label, balance after, filter', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const WalletScreen()));
      await settle(tester);
    }, () => MockClient((req) async => req.url.path.endsWith('/wallet')
        ? http.Response(jsonEncode(_wallet), 200)
        : http.Response('{}', 200)));
    expect(find.text('-₹87.50'), findsOneWidget);
    expect(find.text('+₹0.75'), findsOneWidget);
    expect(find.text('Bal ₹412.50'), findsOneWidget);
    expect(find.textContaining('Ride payment'), findsOneWidget);
    expect(find.textContaining('Money added'), findsOneWidget);
    // Empty note falls back to Credited.
    expect(find.text('Credited'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wallet-filter-refund')));
    await tester.pump();
    expect(find.text('Refund for cancelled ride'), findsOneWidget);
    expect(find.text('Ride to Station Rd'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wallet-filter-all')));
    await tester.pump();
    expect(find.text('Ride to Station Rd'), findsOneWidget);
  });

  group('TopupLimits', () {
    test('defaults and config', () {
      expect(TopupLimits.fromConfig(null).min, 10);
      expect(TopupLimits.fromConfig({}).max, 100000);
      final c = TopupLimits.fromConfig({'wallet': {'minTopup': 50, 'maxTopup': 5000}});
      expect((c.min, c.max), (50, 5000));
      // Never above what the server accepts.
      expect(TopupLimits.fromConfig({'wallet': {'maxTopup': 500000}}).max, 100000);
      expect(TopupLimits.fromConfig({'wallet': {'minTopup': 9000, 'maxTopup': 100}}).min, 10);
    });

    test('check', () {
      const l = TopupLimits(10, 1000);
      expect(l.check(''), isNotNull);
      expect(l.check('5'), 'Minimum top-up is ₹10');
      expect(l.check('1001'), 'Maximum top-up is ₹1000');
      expect(l.check('10.5'), isNotNull);
      expect(l.check('250'), isNull);
    });
  });

  testWidgets('top-up field takes digits only and shows the limits', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const Scaffold(body: AddMoneySheet())));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('wallet-topup-amount')), '-1e3.5 ');
      await tester.pump();
    }, () => MockClient((req) async => http.Response('{}', 200)));
    final tf = tester.widget<TextField>(find.byKey(const ValueKey('wallet-topup-amount')));
    expect(tf.controller!.text, '135');
    expect(find.text('Min ₹10 · Max ₹100000'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('wallet-topup-amount')), '5');
    await tester.tap(find.text('Add Money'));
    await tester.pump();
    expect(find.text('Minimum top-up is ₹10'), findsOneWidget);
  });
}
