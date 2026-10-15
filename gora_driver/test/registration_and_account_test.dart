import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/providers/driver_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Launch routing for a driver part-way through registration, and the Account
// tab's live figures.
// ─────────────────────────────────────────────────────────────────────────────

MockClient _api(Map<String, dynamic> driver, {num balance = 0}) => MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/auth/driver/profile')) return http.Response(jsonEncode({'driver': driver}), 200);
  if (p.endsWith('/auth/driver/wallet')) return http.Response(jsonEncode({'balance': balance, 'transactions': []}), 200);
  return http.Response('{}', 200);
});

Future<AuthState> _launchState(Map<String, dynamic> driver) => http.runWithClient(() async {
  final bloc = AuthBloc();
  final next = bloc.stream.first;
  bloc.add(CheckAuthEvent());
  final s = await next;
  await bloc.close();
  return s;
}, () => _api(driver));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'driver_token': 't'}));

  group('relaunch routing', () {
    test('submitted, not yet approved → Under Review', () async {
      expect(await _launchState({'_id': 'd1', 'status': 'pending', 'registrationStep': 'submitted'}),
          isA<RegistrationSubmittedState>());
    });
    test('approved → home', () async {
      expect(await _launchState({'_id': 'd1', 'status': 'approved', 'registrationStep': 'submitted'}),
          isA<AuthenticatedState>());
    });
    test('documents saved, bank step left → bank details, not onboarding', () async {
      expect(await _launchState({'_id': 'd1', 'status': 'pending', 'registrationStep': 'bank'}),
          isA<RegistrationBankPendingState>());
    });
    test('rejected → rejection', () async {
      expect(await _launchState({'_id': 'd1', 'status': 'rejected', 'registrationStep': 'submitted'}),
          isA<RejectionState>());
    });
  });

  testWidgets('Account tab shows the wallet balance and the real rating', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dp = DriverProvider();
    await http.runWithClient(() async {
      await dp.loadProfile();
    }, () => _api({'_id': 'd1', 'name': 'Suresh Kumar', 'status': 'approved', 'rating': 5, 'totalRides': 3}, balance: 982));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: dp,
      child: const MaterialApp(home: AccountPage()),
    ));
    await tester.pump();
    expect(find.text('₹ 982.00'), findsOneWidget);
    expect(find.textContaining('2,450'), findsNothing);
    expect(find.text('5.0'), findsNWidgets(2)); // header chip + quick stat
    while (tester.takeException() != null) {}
  });
}
