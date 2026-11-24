import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/delete_account_screen.dart';
import 'package:customer_app/screens/settings_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// Delete account with a reason, through a mocked /auth/user/account-request.
// Nothing is deleted by the app: the request goes to the admin, and the rider
// can withdraw it while it is pending.

const _reasons = [
  'I no longer need the app',
  'I have another account',
  'Privacy concerns',
  'Too expensive',
  'Bad experience',
  'Other',
];

List<Map<String, dynamic>> requests = [];
final posts = <Map<String, dynamic>>[];
final deletes = <Uri>[];
bool failPost = false;

MockClient get client => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/auth/user/account-request')) {
        expect(req.headers['Authorization'], 'Bearer t');
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'reasons': _reasons, 'requests': requests}), 200);
        }
        if (req.method == 'POST') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          posts.add(b);
          if (failPost) return http.Response(jsonEncode({'error': 'Please choose a reason'}), 400);
          final r = {
            'id': 'req1', 'kind': 'delete', 'status': 'pending', 'reason': b['reason'], 'note': b['note'],
            'createdAt': '2026-11-20T09:30:00.000Z', 'handledAt': null, 'adminNote': '',
          };
          requests = [r, ...requests];
          return http.Response(jsonEncode({'success': true, 'request': r}), 201);
        }
        if (req.method == 'DELETE') {
          deletes.add(req.url);
          final id = req.url.queryParameters['id'];
          requests = requests.map((r) => r['id'] == id ? {...r, 'status': 'cancelled'} : r).toList();
          return http.Response(jsonEncode({'success': true}), 200);
        }
      }
      return http.Response('{}', 200);
    });

Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => client);

Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

Future<void> open(WidgetTester tester, {Widget home = const DeleteAccountScreen()}) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await act(() async {
    await tester.pumpWidget(app(home));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

Future<void> settle(WidgetTester tester) => act(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

ElevatedButton cta(WidgetTester tester) => tester.widget<ElevatedButton>(
    find.ancestor(of: find.byIcon(Icons.delete_outline_rounded), matching: find.byType(ElevatedButton)));

void main() {
  setUp(() {
    requests = [];
    posts.clear();
    deletes.clear();
    failPost = false;
    SharedPreferences.setMockInitialValues({'user_token': 't'});
  });

  testWidgets('Settings → Delete Account opens the request screen (no dead dialog)', (tester) async {
    await open(tester, home: const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Delete Account'), 200, scrollable: find.byType(Scrollable).first);
    await act(() async {
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
    });
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Why are you leaving?'), findsOneWidget);
  });

  testWidgets('lists the server reasons; the CTA waits for a reason', (tester) async {
    await open(tester);
    for (final r in _reasons) {
      expect(find.text(r), findsOneWidget);
    }
    expect(find.text('Choose a reason'), findsOneWidget);
    expect(cta(tester).onPressed, isNull);
    expect(find.textContaining('ride and payment history is kept'), findsOneWidget);
    await tester.tap(find.text('Privacy concerns'));
    await tester.pump();
    expect(find.text('Request account deletion'), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });

  testWidgets('reason + note → confirm → POST kind delete, then the pending state', (tester) async {
    await open(tester);
    // The request is sent from the continuation of the CTA tap, so that tap
    // must run inside the mocked client's zone too.
    await act(() async {
      await tester.tap(find.text('Too expensive'));
      await tester.enterText(find.byType(TextField), '  Moving abroad  ');
      await tester.pump();
      await tester.tap(find.text('Request account deletion'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(posts, isEmpty, reason: 'nothing is sent before the rider confirms');
      await tester.tap(find.text('Yes, request deletion'));
      await tester.pumpAndSettle();
    });
    expect(posts, [
      {'kind': 'delete', 'reason': 'Too expensive', 'note': 'Moving abroad'},
    ]);
    expect(find.byKey(const ValueKey('delete-pending')), findsOneWidget);
    expect(find.text('Deletion requested on 20 Nov 2026 — our team will review it'), findsOneWidget);
    expect(find.text('Reason: Too expensive'), findsOneWidget);
    expect(find.text('Withdraw request'), findsOneWidget);
    expect(find.text('Why are you leaving?'), findsNothing);
    expect(find.text('Deletion request sent'), findsOneWidget);
  });

  testWidgets('Cancel in the confirm dialog sends nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.tap(find.text('Request account deletion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    expect(find.text('Why are you leaving?'), findsOneWidget);
  });

  testWidgets('a server error is shown and the form stays', (tester) async {
    failPost = true;
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Other'));
      await tester.pump();
      await tester.tap(find.text('Request account deletion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, request deletion'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Please choose a reason'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-pending')), findsNothing);
    expect(find.text('Why are you leaving?'), findsOneWidget);
  });

  testWidgets('a pending request opens on its status; Withdraw sends DELETE ?id=', (tester) async {
    requests = [
      {'id': 'abc123', 'kind': 'delete', 'status': 'pending', 'reason': 'Bad experience', 'note': '',
        'createdAt': '2026-11-18T10:00:00.000Z', 'handledAt': null, 'adminNote': ''},
    ];
    await open(tester);
    expect(find.text('Deletion requested on 18 Nov 2026 — our team will review it'), findsOneWidget);
    expect(find.text('Why are you leaving?'), findsNothing);
    expect(find.text('Request account deletion'), findsNothing, reason: 'no second request while one is pending');
    await act(() async {
      await tester.tap(find.text('Withdraw request'));
      await tester.pumpAndSettle();
    });
    expect(deletes, hasLength(1));
    expect(deletes.single.path, endsWith('/auth/user/account-request'));
    expect(deletes.single.queryParameters['id'], 'abc123');
    expect(find.byKey(const ValueKey('delete-pending')), findsNothing);
    expect(find.text('Why are you leaving?'), findsOneWidget);
    expect(find.text('Request withdrawn. Your account stays active.'), findsOneWidget);
  });

  testWidgets('a declined request is explained above the form', (tester) async {
    requests = [
      {'id': 'r9', 'kind': 'delete', 'status': 'rejected', 'reason': 'Other', 'note': '',
        'createdAt': '2026-11-01T10:00:00.000Z', 'handledAt': '2026-11-02T10:00:00.000Z',
        'adminNote': 'You have an unpaid ride'},
    ];
    await open(tester);
    expect(find.text('Your request of 1 Nov 2026 was declined: You have an unpaid ride'), findsOneWidget);
    expect(find.text('Why are you leaving?'), findsOneWidget);
    await settle(tester);
  });
}
