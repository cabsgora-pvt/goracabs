import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/emergency_actions_screen.dart' show safetyNumberOr112;
import 'package:customer_app/screens/support_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Things that were on screen but did nothing:
//  • "Submit Ticket" only showed "created successfully" — nothing was sent.
//  • "My Tickets" listed three hard-coded tickets to every rider.
//  • "Call safety team" dialled a made-up 18001234567.
// ─────────────────────────────────────────────────────────────────────────────

Widget _app(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

http.Response _json(Object b, [int code = 200]) =>
    http.Response(jsonEncode(b), code, headers: {'content-type': 'application/json'});

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_token': 'rider-token'}));

  testWidgets('Submit Ticket really sends the ticket to the server', (tester) async {
    final sent = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const CreateTicketScreen(rideId: 'r42')));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('ticket-subject')), 'Driver took a long route');
      await tester.enterText(find.byKey(const ValueKey('ticket-message')), 'Charged ₹80 more than shown');
      await tester.tap(find.byKey(const ValueKey('ticket-submit')));
      await _settle(tester);
    }, () => MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/user/support/tickets')) {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({'success': true, 'ticket': {'id': 't1', 'subject': 'x', 'status': 'open', 'messages': []}}, 201);
      }
      return _json({});
    }));
    expect(sent, hasLength(1));
    expect(sent.single['subject'], 'Driver took a long route');
    expect(sent.single['message'], 'Charged ₹80 more than shown');
    expect(sent.single['rideId'], 'r42');
  });

  testWidgets('a failed ticket is NOT reported as created', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const CreateTicketScreen()));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('ticket-subject')), 'S');
      await tester.enterText(find.byKey(const ValueKey('ticket-message')), 'M');
      await tester.tap(find.byKey(const ValueKey('ticket-submit')));
      await _settle(tester);
    }, () => MockClient((req) async => _json({'error': 'Too many tickets. Please wait a few minutes.', 'code': 'RATE_LIMITED'}, 429)));
    expect(find.textContaining('successfully'), findsNothing);
    expect(find.text('Too many tickets. Please wait a few minutes.'), findsOneWidget);
    expect(find.byType(CreateTicketScreen), findsOneWidget, reason: 'the form stays open to retry');
  });

  testWidgets('My Tickets shows the rider\'s real tickets, never the old samples', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const MyTicketsScreen()));
      await _settle(tester);
    }, () => MockClient((req) async => _json({'tickets': [
          {'id': 'a1', 'subject': 'Refund not received', 'status': 'in_progress', 'updatedAt': '2026-11-20T10:00:00.000Z',
           'messages': [{'sender': 'user', 'message': 'hi'}, {'sender': 'admin', 'message': 'checking'}]},
        ]})));
    expect(find.text('Refund not received'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Support replied — tap to read'), findsOneWidget);
    expect(find.textContaining('TKT1234'), findsNothing);
    expect(find.text('Driver was rude'), findsNothing);
  });

  testWidgets('My Tickets with none shows an empty state, and errors show Retry', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const MyTicketsScreen()));
      await _settle(tester);
    }, () => MockClient((req) async => _json({'tickets': []})));
    expect(find.text('No tickets yet'), findsOneWidget);

    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const MyTicketsScreen(key: ValueKey('again'))));
      await _settle(tester);
    }, () => MockClient((req) async => _json({'error': 'Server error'}, 500)));
    expect(find.text('Retry'), findsOneWidget);
  });

  test('"Call safety team" uses the configured number, else 112 — never a placeholder', () {
    expect(safetyNumberOr112(null), '112');
    expect(safetyNumberOr112(''), '112');
    expect(safetyNumberOr112('  '), '112');
    expect(safetyNumberOr112('+91 98250 12345'), '+91 98250 12345');
    expect(safetyNumberOr112('1800-200-1234'), '1800-200-1234');
  });
}
