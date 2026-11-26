import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/account/pages/delete_account_page.dart';
import 'package:gora_driver/features/account/pages/preferences_page.dart';
import 'package:gora_driver/features/account/pages/settings_page.dart';
import 'package:gora_driver/features/account/pages/zone_page.dart';
import 'package:gora_driver/features/account/service_prefs.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/home/bloc/home_bloc.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/notifications/pages/notification_page.dart';
import 'package:gora_driver/features/registration/document_upload_page.dart';
import 'package:gora_driver/features/registration/kyc_success_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin-managed features in the driver app: document types, ride preferences,
// zone + zone requests, account deletion requests, account hold, the
// negative-wallet cash pause and notification images.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

/// Every request the app made, in order.
final calls = <http.Request>[];

/// Per-test API: return null for the default `{}`.
http.Response? Function(http.Request req) api = (_) => null;

MockClient get _client => MockClient((req) async {
      calls.add(req);
      return api(req) ?? _json({});
    });

Future<void> withApi(Future<void> Function() body) => http.runWithClient(body, () => _client);

bool _is(http.Request r, String method, String pathEnd) => r.method == method && r.url.path.endsWith(pathEnd);

List<http.Request> _sent(String method, String pathEnd) => calls.where((r) => _is(r, method, pathEnd)).toList();

Map<String, dynamic> _bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

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

Widget app(Widget home, {DriverProvider? dp, Map<String, WidgetBuilder>? routes, GlobalKey<NavigatorState>? nav}) =>
    MultiProvider(
      providers: [
        if (dp != null) ChangeNotifierProvider.value(value: dp) else ChangeNotifierProvider(create: (_) => DriverProvider()),
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
  await tester.pump(const Duration(seconds: 2));
  while (tester.takeException() != null) {}
}

/// The Switch inside the row that shows [label].
Switch switchFor(WidgetTester tester, String label) => tester.widget<Switch>(switchFinder(label));
Finder switchFinder(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first, matching: find.byType(Switch));

void main() {
  setUp(() {
    calls.clear();
    api = (_) => null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    // No GPS in a test: the location service reports "off".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
    // No foreground service either. Unanswered, its calls never return under
    // the test's fake clock and going online would never finish.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async => throw PlatformException(code: 'unavailable'),
    );
  });

  // ── 1. Documents ──────────────────────────────────────────────────────────
  group('registration documents come from the admin list', () {
    test('rows become specs in server order; inactive and keyless rows are skipped', () {
      final specs = docSpecsFromApi({
        'documents': [
          {'key': 'dl', 'name': 'Driving License', 'numberLabel': 'License Number', 'required': true},
          {'key': 'police', 'name': 'Police Verification', 'numberLabel': '', 'needsExpiry': true, 'required': false},
          {'key': 'old', 'name': 'Old one', 'isActive': false},
          {'key': '', 'name': 'No key'},
        ],
      });
      expect(specs.map((s) => s.key), ['dl', 'police']);
      expect(specs[1].required, isFalse);
      expect(specs[1].needsExpiry, isTrue);
      expect(specs[1].numberLabel, 'Document Number');
      expect(specs[0].required, isTrue);
    });

    test('an empty or broken reply falls back to the built-in five', () {
      expect(docSpecsFromApi({'documents': []}), kDefaultDocSpecs);
      expect(docSpecsFromApi({'error': 'Server error (502). Please try again.'}), kDefaultDocSpecs);
      expect(kDefaultDocSpecs.map((s) => s.key), ['aadhaar', 'pan', 'rc', 'insurance', 'dl']);
    });

    testWidgets('admin list is shown; optional ones say Optional and do not block', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/document-types')
          ? _json({'documents': [
              {'key': 'aadhaar', 'name': 'Aadhaar Card', 'numberLabel': 'Aadhaar Number', 'needsBack': true, 'required': true},
              {'key': 'police', 'name': 'Police Verification', 'numberLabel': 'Certificate No', 'required': false},
            ]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      expect(find.text('Aadhaar Card'), findsOneWidget);
      expect(find.text('Police Verification'), findsOneWidget);
      expect(find.text('PAN Card'), findsNothing, reason: 'the admin list replaces the built-in one');
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('0 of 1 required uploaded'), findsOneWidget);
      expect(find.text('Complete all required documents to continue'), findsOneWidget);
    });

    testWidgets('list call fails → the built-in five, all required', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/document-types') ? http.Response('<html>502</html>', 502) : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      for (final n in ['Aadhaar Card', 'PAN Card', 'RC Book', 'Vehicle Insurance', 'Driving License']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('Required'), findsNWidgets(5));
      expect(find.text('Optional'), findsNothing);
      expect(find.text('0 of 5 required uploaded'), findsOneWidget);
    });

    testWidgets('only optional documents: can continue, and unfilled ones are not sent', (tester) async {
      phone(tester);
      api = (r) {
        if (_is(r, 'GET', '/document-types')) {
          return _json({'documents': [{'key': 'police', 'name': 'Police Verification', 'required': false}]});
        }
        if (_is(r, 'POST', '/register/documents')) return _json({'success': true});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage(),
            routes: {KycSuccessPage.route: (_) => const Scaffold(body: Text('SUBMITTED PAGE'))}));
        await pumpFor(tester);
        await tester.tap(find.text('Submit documents'));
        await pumpFor(tester);
      });
      final sent = _sent('POST', '/register/documents');
      expect(sent, hasLength(1));
      expect(_bodyOf(sent.single)['documents'], isEmpty);
      expect(_bodyOf(sent.single)['finish'], isTrue);
      expect(find.text('SUBMITTED PAGE'), findsOneWidget);
    });
  });

  // ── 2. Ride preferences ───────────────────────────────────────────────────
  group('ride preferences you offer', () {
    final catalogue = {'preferences': [
      {'id': 'p1', 'key': 'pet_friendly', 'name': 'Pet friendly', 'description': 'Small pets in a carrier', 'icon': 'pets',
        'services': ['taxi']},
      {'id': 'p2', 'key': 'extra_luggage', 'name': 'Extra luggage', 'description': '', 'icon': 'luggage', 'services': ['taxi']},
    ]};

    void serve({List<String> mine = const ['pet_friendly'], Object? prefs}) {
      api = (r) {
        if (_is(r, 'GET', '/ride-preferences')) return _json(prefs ?? catalogue);
        if (_is(r, 'GET', '/auth/driver/profile')) {
          return _json({'driver': {'_id': 'd1', 'acceptsRental': true, 'ridePreferences': mine}});
        }
        if (_is(r, 'POST', '/auth/driver/preferences')) {
          final b = _bodyOf(r);
          return _json({'success': true, 'preferences': {
            'acceptsRental': b['acceptsRental'] ?? true, 'acceptsOutstation': false,
            'acceptsHireDriver': false, 'acceptsDelivery': false,
            'ridePreferences': b['ridePreferences'] ?? mine,
          }});
        }
        return null;
      };
    }

    test('icon names map to Material icons, star by default', () {
      expect(ridePrefIcon('pets'), Icons.pets_rounded);
      expect(ridePrefIcon('luggage'), Icons.luggage_rounded);
      expect(ridePrefIcon('accessible'), Icons.accessible_rounded);
      expect(ridePrefIcon('ac_unit'), Icons.ac_unit_rounded);
      expect(ridePrefIcon('smoke_free'), Icons.smoke_free_rounded);
      expect(ridePrefIcon('child_care'), Icons.child_care_rounded);
      expect(ridePrefIcon('music_note'), Icons.music_note_rounded);
      expect(ridePrefIcon('unknown'), Icons.star_rounded);
    });

    testWidgets('preferences page: switches show my choice and Save sends the keys', (tester) async {
      phone(tester);
      serve();
      await withApi(() async {
        await tester.pumpWidget(app(const PreferencesPage()));
        await pumpFor(tester);
        expect(find.text('Ride preferences you offer'), findsOneWidget);
        expect(find.byIcon(Icons.pets_rounded), findsOneWidget);
        expect(find.byIcon(Icons.luggage_rounded), findsOneWidget);
        expect(switchFor(tester, 'Pet friendly').value, isTrue);
        expect(switchFor(tester, 'Extra luggage').value, isFalse);
        await tester.tap(switchFinder('Extra luggage'));
        await tester.pump();
        expect(switchFor(tester, 'Extra luggage').value, isTrue);
        await tester.tap(find.text('Save Preferences'));
        await pumpFor(tester);
      });
      final sent = _sent('POST', '/auth/driver/preferences');
      expect(sent, hasLength(1));
      expect((_bodyOf(sent.single)['ridePreferences'] as List).toSet(), {'pet_friendly', 'extra_luggage'});
      expect(_bodyOf(sent.single)['acceptsRental'], isTrue, reason: 'service switches still saved alongside');
      expect(find.text('Preferences saved'), findsOneWidget);
    });

    testWidgets('no admin preferences → no section, and Save leaves them alone', (tester) async {
      phone(tester);
      serve(prefs: {'preferences': []});
      await withApi(() async {
        await tester.pumpWidget(app(const PreferencesPage()));
        await pumpFor(tester);
        expect(find.text('Ride preferences you offer'), findsNothing);
        await tester.tap(find.text('Save Preferences'));
        await pumpFor(tester);
      });
      expect(_bodyOf(_sent('POST', '/auth/driver/preferences').single).containsKey('ridePreferences'), isFalse);
    });

    testWidgets('home "Trip preferences" sheet: a switch saves at once', (tester) async {
      phone(tester);
      serve();
      await withApi(() async {
        await tester.pumpWidget(app(Scaffold(body: Builder(builder: (ctx) => Center(
          child: ElevatedButton(onPressed: () => showServicePrefsTopSheet(ctx), child: const Text('open')),
        )))));
        await tester.tap(find.text('open'));
        await pumpFor(tester);
        expect(find.text('Trip preferences'), findsOneWidget);
        expect(find.text('Ride preferences you offer'), findsOneWidget);
        expect(switchFor(tester, 'Pet friendly').value, isTrue);
        await tester.ensureVisible(switchFinder('Pet friendly'));
        await tester.tap(switchFinder('Pet friendly'));
        await pumpFor(tester);
      });
      final sent = _sent('POST', '/auth/driver/preferences');
      expect(sent, hasLength(1));
      expect(_bodyOf(sent.single), {'ridePreferences': <String>[]});
      expect(switchFor(tester, 'Pet friendly').value, isFalse);
    });
  });

  // ── 3. Zone ───────────────────────────────────────────────────────────────
  group('my zone', () {
    Map<String, dynamic> zone({bool auto = false, Map<String, dynamic>? pending}) => {
      'zoneId': 'z1', 'zoneName': 'Ahmedabad West', 'zoneAuto': auto,
      'zones': [{'id': 'z1', 'name': 'Ahmedabad West'}, {'id': 'z2', 'name': 'Gandhinagar'}, {'id': 'z3', 'name': 'Vadodara'}],
      'pendingRequest': pending,
      'history': [
        {'fromName': 'Ahmedabad East', 'toName': 'Ahmedabad West', 'by': 'auto', 'at': '2026-11-18T06:30:00.000Z'},
        {'fromName': '', 'toName': 'Ahmedabad East', 'by': 'admin:ops@example.com', 'at': '2026-10-02T06:30:00.000Z'},
      ],
    };

    testWidgets('shows the zone and history; automatic zone (admin-only) can only be turned off', (tester) async {
      phone(tester);
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/zone')) return _json(zone(auto: true));
        if (_is(r, 'PUT', '/auth/driver/zone')) return _json({'success': true, 'zoneAuto': _bodyOf(r)['zoneAuto']});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
        expect(find.text('Current zone'), findsOneWidget);
        expect(find.text('Ahmedabad West'), findsOneWidget);
        expect(find.text('Ahmedabad East → Ahmedabad West'), findsOneWidget);
        expect(find.text('Changed automatically by your location · 18 Nov 2026'), findsOneWidget);
        expect(find.text('No zone → Ahmedabad East'), findsOneWidget);
        expect(find.textContaining('ops@example.com'), findsNothing, reason: "the admin's email is not shown");
        // Turning it ON is for an admin (403 ZONE_AUTO_ADMIN_ONLY): no switch.
        expect(find.byType(Switch), findsNothing);
        expect(find.textContaining('Managed by admin'), findsOneWidget);
        await tester.tap(find.text('Turn off'));
        await pumpFor(tester, 300);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Turn off'));
        await pumpFor(tester);
      });
      final put = _sent('PUT', '/auth/driver/zone');
      expect(put, hasLength(1));
      expect(_bodyOf(put.single), {'zoneAuto': false});
      expect(find.textContaining('Managed by admin'), findsNothing);
      expect(find.text('Automatic zone change turned off'), findsOneWidget);
    });

    testWidgets('request a zone change: pick a zone, add a note, send', (tester) async {
      phone(tester);
      var requested = false;
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/zone')) {
          return _json(zone(pending: requested
              ? {'id': 'r1', 'kind': 'zone_change', 'status': 'pending', 'toZoneName': 'Gandhinagar',
                  'createdAt': '2026-11-20T06:30:00.000Z'}
              : null));
        }
        if (_is(r, 'POST', '/auth/driver/account-request')) {
          requested = true;
          return _json({'success': true, 'request': {'id': 'r1'}}, 201);
        }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
        await tester.tap(find.text('Request zone change'));
        await pumpFor(tester);
        // The current zone is not offered.
        expect(find.widgetWithText(RadioListTile<String>, 'Ahmedabad West'), findsNothing);
        expect(find.text('Gandhinagar'), findsOneWidget);
        expect(find.text('Vadodara'), findsOneWidget);
        await tester.tap(find.text('Gandhinagar'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Moving house');
        await tester.tap(find.text('Send request'));
        await pumpFor(tester);
      });
      final post = _sent('POST', '/auth/driver/account-request');
      expect(post, hasLength(1));
      expect(_bodyOf(post.single), {'kind': 'zone_change', 'toZoneId': 'z2', 'note': 'Moving house'});
      expect(find.text('Zone change requested'), findsOneWidget);
      expect(find.text('To Gandhinagar · 20 Nov 2026 — waiting for admin approval'), findsOneWidget);
      expect(find.text('Request a different zone'), findsOneWidget);
    });

    testWidgets('Send request stays off until a zone is picked', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/auth/driver/zone') ? _json(zone()) : null;
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
        await tester.tap(find.text('Request zone change'));
        await pumpFor(tester);
      });
      final btn = find.ancestor(of: find.text('Send request'), matching: find.byType(ElevatedButton));
      expect(tester.widget<ElevatedButton>(btn).onPressed, isNull);
    });

    testWidgets('a pending request can be withdrawn', (tester) async {
      phone(tester);
      var withdrawn = false;
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/zone')) {
          return _json(zone(pending: withdrawn
              ? null
              : {'id': 'req 42', 'kind': 'zone_change', 'status': 'pending', 'toZoneName': 'Vadodara', 'createdAt': ''}));
        }
        if (_is(r, 'DELETE', '/auth/driver/account-request')) {
          withdrawn = true;
          return _json({'success': true});
        }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const ZonePage()));
        await pumpFor(tester);
        expect(find.text('To Vadodara — waiting for admin approval'), findsOneWidget);
        await tester.tap(find.text('Withdraw'));
        await pumpFor(tester);
      });
      final del = _sent('DELETE', '/auth/driver/account-request');
      expect(del, hasLength(1));
      expect(del.single.url.queryParameters['id'], 'req 42');
      expect(find.text('Zone change requested'), findsNothing);
      expect(find.text('Request withdrawn'), findsOneWidget);
    });

    testWidgets('going online into another zone: the bloc reports the new zone', (tester) async {
      HomeState? last;
      await tester.runAsync(() => withApi(() async {
        api = (r) => _is(r, 'POST', '/auth/driver/online')
            ? _json({'success': true, 'isOnline': true, 'zoneChangedTo': 'Gandhinagar'})
            : null;
        final bloc = HomeBloc();
        final next = bloc.stream.firstWhere((s) => s is OnlineStatusChanged).timeout(const Duration(seconds: 5));
        bloc.add(ToggleOnlineEvent(true));
        last = await next;
        await bloc.close();
      }));
      expect(last, isA<OnlineStatusChanged>());
      final changed = last as OnlineStatusChanged;
      expect(changed.zoneChangedTo, 'Gandhinagar');
      expect(changed.isOnline, isTrue);
    });

    testWidgets('home shows "Your zone changed to …" after GO', (tester) async {
      phone(tester, const Size(400, 860));
      await withApi(() async {
        api = (r) {
          if (_is(r, 'POST', '/auth/driver/online')) {
            return _json({'success': true, 'isOnline': _bodyOf(r)['isOnline'], 'zoneChangedTo': 'Gandhinagar'});
          }
          if (_is(r, 'GET', '/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
          if (_is(r, 'GET', '/auth/driver/wallet')) return _json({'balance': 500, 'transactions': []});
          if (_is(r, 'GET', '/rides/driver/active')) return _json({'ride': null});
          return null;
        };
        await tester.pumpWidget(app(const HomePage()));
        await pumpFor(tester);
        await tester.tap(find.text('GO'));
        await pumpFor(tester);
        expect(find.text('Your zone changed to Gandhinagar'), findsOneWidget);
        await teardown(tester);
      });
    });
  });

  // ── 4. Delete account ─────────────────────────────────────────────────────
  group('delete account', () {
    const reasons = ['I no longer need the app', 'I have another account', 'Privacy concerns', 'Other'];

    testWidgets('pick a reason, confirm, and the request shows as waiting', (tester) async {
      phone(tester);
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/account-request')) return _json({'reasons': reasons, 'requests': []});
        if (_is(r, 'POST', '/auth/driver/account-request')) {
          return _json({'success': true, 'request': {'id': 'd9', 'kind': 'delete', 'status': 'pending',
            'reason': _bodyOf(r)['reason'], 'createdAt': '2026-11-20T06:30:00.000Z'}}, 201);
        }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const DeleteAccountPage()));
        await pumpFor(tester);
        expect(find.text('The admin reviews this request'), findsOneWidget);
        for (final r in reasons) {
          expect(find.text(r), findsOneWidget);
        }
        final btn = find.ancestor(of: find.text('Request account deletion'), matching: find.byType(ElevatedButton));
        expect(tester.widget<ElevatedButton>(btn).onPressed, isNull, reason: 'no reason chosen yet');
        await tester.tap(find.text('Privacy concerns'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Too many SMS');
        await tester.tap(find.text('Request account deletion'));
        await pumpFor(tester, 400);
        expect(find.text('Delete your account?'), findsOneWidget);
        await tester.tap(find.text('Yes, request deletion'));
        await pumpFor(tester);
      });
      final post = _sent('POST', '/auth/driver/account-request');
      expect(post, hasLength(1));
      expect(_bodyOf(post.single), {'kind': 'delete', 'reason': 'Privacy concerns', 'note': 'Too many SMS'});
      expect(find.text('Deletion requested on 20 Nov 2026 — waiting for admin'), findsOneWidget);
      expect(find.text('Withdraw request'), findsOneWidget);
    });

    testWidgets('Cancel in the confirm dialog sends nothing', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/auth/driver/account-request') ? _json({'reasons': reasons, 'requests': []}) : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DeleteAccountPage()));
        await pumpFor(tester);
        await tester.tap(find.text('Other'));
        await tester.pump();
        await tester.tap(find.text('Request account deletion'));
        await pumpFor(tester, 400);
        await tester.tap(find.text('Cancel'));
        await pumpFor(tester, 400);
      });
      expect(_sent('POST', '/auth/driver/account-request'), isEmpty);
      expect(find.text('Request account deletion'), findsOneWidget);
    });

    testWidgets('an open request shows its date and can be withdrawn', (tester) async {
      phone(tester);
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/account-request')) {
          return _json({'reasons': reasons, 'requests': [
            {'id': 'z1', 'kind': 'zone_change', 'status': 'pending', 'createdAt': '2026-11-19T06:30:00.000Z'},
            {'id': 'd1', 'kind': 'delete', 'status': 'pending', 'reason': 'Other', 'createdAt': '2026-11-12T06:30:00.000Z'},
          ]});
        }
        if (_is(r, 'DELETE', '/auth/driver/account-request')) return _json({'success': true});
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const DeleteAccountPage()));
        await pumpFor(tester);
        expect(find.text('Deletion requested on 12 Nov 2026 — waiting for admin'), findsOneWidget);
        await tester.tap(find.text('Withdraw request'));
        await pumpFor(tester);
      });
      final del = _sent('DELETE', '/auth/driver/account-request');
      expect(del.single.url.queryParameters['id'], 'd1', reason: 'the delete request, not the zone one');
      expect(find.text('Why are you leaving?'), findsOneWidget);
      expect(find.text('Request withdrawn. Your account stays active.'), findsOneWidget);
    });

    testWidgets('a closed (cancelled) delete request does not count as open', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/auth/driver/account-request')
          ? _json({'reasons': reasons, 'requests': [{'id': 'd1', 'kind': 'delete', 'status': 'cancelled'}]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DeleteAccountPage()));
        await pumpFor(tester);
      });
      expect(find.text('Why are you leaving?'), findsOneWidget);
      expect(find.text('Withdraw request'), findsNothing);
    });

    testWidgets('Account and Settings link to My zone and Delete account', (tester) async {
      phone(tester, const Size(400, 2400));
      await withApi(() async {
        await tester.pumpWidget(app(const AccountPage(),
            routes: {'/zone': (_) => const Scaffold(body: Text('ZONE PAGE'))}));
        await tester.pump();
        expect(find.text('My zone'), findsOneWidget);
        expect(find.text('Delete account'), findsOneWidget);
        await tester.tap(find.text('My zone'));
        await pumpFor(tester, 400);
        expect(find.text('ZONE PAGE'), findsOneWidget);
      });
      await withApi(() async {
        // A fresh tree: the Account test's navigator stack must not carry over.
        await tester.pumpWidget(KeyedSubtree(key: const ValueKey('settings'), child: app(const SettingsPage(),
            routes: {'/delete-account': (_) => const Scaffold(body: Text('DELETE PAGE'))})));
        await tester.pump();
        await tester.ensureVisible(find.text('Delete account'));
        await tester.tap(find.text('Delete account'));
        await pumpFor(tester, 400);
        expect(find.text('DELETE PAGE'), findsOneWidget);
      });
    });
  });

  // ── 5. Account hold ───────────────────────────────────────────────────────
  group('account hold', () {
    const holdMsg = 'Your account is on hold: Wallet mis-transaction. Please contact support.';
    http.Response? held(http.Request r, {bool profileHold = false}) {
      if (_is(r, 'POST', '/auth/driver/online')) {
        return _json({'error': holdMsg, 'accountHold': true, 'holdKind': 'wallet', 'holdReason': 'Wallet mis-transaction'}, 403);
      }
      if (_is(r, 'GET', '/auth/driver/profile')) {
        return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved',
          'hold': profileHold ? {'kind': 'wallet', 'reason': 'Wallet mis-transaction', 'message': holdMsg} : null}});
      }
      if (_is(r, 'GET', '/auth/driver/wallet')) return _json({'balance': 500, 'transactions': []});
      if (_is(r, 'GET', '/rides/driver/active')) return _json({'ride': null});
      if (_is(r, 'GET', '/rides/driver/pending')) return _json({'rides': [], 'hold': true});
      return null;
    }

    testWidgets('a refused GO does not go online, and each refusal is reported', (tester) async {
      final states = <HomeState>[];
      HomeBloc? bloc;
      await tester.runAsync(() => withApi(() async {
        api = held;
        bloc = HomeBloc();
        final sub = bloc!.stream.listen(states.add);
        bloc!.add(ToggleOnlineEvent(true));
        await bloc!.stream.firstWhere((s) => s is AccountHoldState || s is OnlineStatusChanged).timeout(const Duration(seconds: 5));
        bloc!.add(ToggleOnlineEvent(true));
        await bloc!.stream.firstWhere((s) => s is AccountHoldState || s is OnlineStatusChanged).timeout(const Duration(seconds: 5));
        await sub.cancel();
        await bloc!.close();
      }));
      final holds = states.whereType<AccountHoldState>().toList();
      expect(holds, hasLength(2), reason: 'tapping GO again shows the message again');
      expect(holds.first.message, holdMsg);
      expect(holds.first.kind, 'wallet');
      expect(states.whereType<OnlineStatusChanged>(), isEmpty);
      expect(bloc!.isOnline, isFalse);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool('driver_online'), isNot(true));
    });

    testWidgets('home: GO on a held account shows the hold dialog and stays offline', (tester) async {
      phone(tester, const Size(400, 860));
      await withApi(() async {
        api = held;
        await tester.pumpWidget(app(const HomePage()));
        await pumpFor(tester);
        await tester.tap(find.text('GO'));
        await pumpFor(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Account on hold')), findsOneWidget);
        expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(holdMsg)), findsOneWidget);
        await tester.tap(find.text('OK'));
        await pumpFor(tester, 400);
        expect(find.text("You're offline"), findsOneWidget);
        expect(find.text('GO'), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('home: a held profile shows the red banner with the message', (tester) async {
      phone(tester, const Size(400, 860));
      await withApi(() async {
        api = (r) => held(r, profileHold: true);
        final dp = DriverProvider();
        await dp.loadProfile();
        await tester.pumpWidget(app(const HomePage(), dp: dp));
        await pumpFor(tester);
        expect(find.text('Account on hold'), findsOneWidget);
        expect(find.text(holdMsg), findsOneWidget);
        await teardown(tester);
      });
    });

    test('hold message falls back to the reason', () async {
      final dp = DriverProvider();
      dp.setData({'hold': {'kind': 'manual', 'reason': 'Held by admin'}});
      expect(dp.holdMessage, 'Your account is on hold: Held by admin');
      dp.setData({'hold': null});
      expect(dp.hold, isNull);
      expect(dp.holdMessage, '');
    });
  });

  // ── 6. Negative wallet ────────────────────────────────────────────────────
  group('negative wallet pauses cash rides', () {
    Future<void> home(WidgetTester tester, num balance) async {
      phone(tester, const Size(400, 860));
      await withApi(() async {
        api = (r) {
          if (_is(r, 'GET', '/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
          if (_is(r, 'GET', '/auth/driver/wallet')) return _json({'balance': balance, 'transactions': []});
          if (_is(r, 'GET', '/rides/driver/active')) return _json({'ride': null});
          return null;
        };
        final dp = DriverProvider();
        await dp.loadProfile();
        await tester.pumpWidget(app(const HomePage(), dp: dp, routes: {'/wallet': (_) => const Scaffold(body: Text('WALLET PAGE'))}));
        await pumpFor(tester);
      });
    }

    testWidgets('below zero: "cash rides are paused", tap opens the wallet', (tester) async {
      await home(tester, -42.5);
      expect(find.text('Cash rides paused'), findsOneWidget);
      expect(find.text('Wallet negative — cash rides are paused. Recharge to get cash rides again; '
          'online and wallet rides still come.'), findsOneWidget);
      expect(find.text('Low wallet balance'), findsNothing);
      await withApi(() async {
        await tester.tap(find.text('Cash rides paused'));
        await pumpFor(tester, 400);
        expect(find.text('WALLET PAGE'), findsOneWidget);
        await teardown(tester);
      });
    });

    testWidgets('exactly zero: the old low-balance text', (tester) async {
      await home(tester, 0);
      expect(find.text('Low wallet balance'), findsOneWidget);
      expect(find.text('Cash rides paused'), findsNothing);
      await withApi(() => teardown(tester));
    });

    testWidgets('a cash ride refused on accept shows the server message', (tester) async {
      phone(tester, const Size(360, 800));
      const msg = 'Your wallet is negative, so cash rides are paused. Recharge your wallet to take cash rides again.';
      final nav = GlobalKey<NavigatorState>();
      await withApi(() async {
        api = (r) {
          if (_is(r, 'POST', '/accept')) return _json({'error': msg, 'cashPaused': true}, 403);
          if (_is(r, 'GET', '/rides/driver/pending')) {
            return _json({'rides': [{
              'id': 'c1', 'service': 'taxi', 'riderName': 'Rahul Mehta', 'vehicleType': 'Bike',
              'pickupAddress': 'Law Garden, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
              'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
              'fare': 85, 'totalFare': 85, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
            }]});
          }
          return null;
        };
        await tester.pumpWidget(app(const Scaffold(body: Text('HOME')), nav: nav));
        nav.currentState!.pushNamed(IncomingRequestsPage.route);
        await pumpFor(tester);
        final track = find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Slide to accept');
        expect(track, findsOneWidget);
        final rect = tester.getRect(track);
        final g = await tester.startGesture(Offset(rect.left + 29, rect.center.dy));
        for (var i = 0; i < 10; i++) {
          await g.moveBy(Offset(rect.width / 10, 0));
          await tester.pump(const Duration(milliseconds: 30));
        }
        await g.up();
        await pumpFor(tester);
        expect(_sent('POST', '/accept'), hasLength(1));
        expect(find.text(msg), findsOneWidget);
        expect(find.text('HOME'), findsOneWidget, reason: 'the refused request is dropped');
        await teardown(tester);
      });
    });
  });

  // ── 7. Notification images ────────────────────────────────────────────────
  group('notification images', () {
    testWidgets('relative and full image URLs are shown; none when empty', (tester) async {
      phone(tester);
      await withApi(() async {
        api = (r) => _is(r, 'GET', '/auth/driver/notifications')
            ? _json({'notifications': [
                {'id': 'n1', 'title': 'Diwali bonus', 'body': 'Earn 2x today', 'imageUrl': '/uploads/diwali.jpg',
                  'sentAt': DateTime.now().toUtc().toIso8601String()},
                {'id': 'n2', 'title': 'New zone', 'body': 'Gandhinagar is live', 'imageUrl': 'https://cdn.example.com/z.png'},
                {'id': 'n3', 'title': 'Plain', 'body': 'No picture', 'imageUrl': ''},
                {'id': 'n4', 'title': 'Old row', 'body': 'Field missing'},
              ]})
            : null;
        await tester.pumpWidget(app(const NotificationPage()));
        await pumpFor(tester);
      });
      final images = tester.widgetList<Image>(find.byKey(const ValueKey('notif_image'))).toList();
      expect(images, hasLength(2));
      expect((images[0].image as NetworkImage).url, 'https://goracabs.com/uploads/diwali.jpg');
      expect((images[1].image as NetworkImage).url, 'https://cdn.example.com/z.png');
      expect(find.text('Plain'), findsOneWidget);
      // Bounded and rounded.
      final box = tester.widget<ConstrainedBox>(
          find.ancestor(of: find.byKey(const ValueKey('notif_image')).first, matching: find.byType(ConstrainedBox)).first);
      expect(box.constraints.maxHeight, 180);
      expect(find.ancestor(of: find.byKey(const ValueKey('notif_image')).first, matching: find.byType(ClipRRect)), findsWidgets);
      while (tester.takeException() != null) {}
    });

    testWidgets('a broken image link leaves no error on screen', (tester) async {
      phone(tester);
      await withApi(() async {
        api = (r) => _is(r, 'GET', '/auth/driver/notifications')
            ? _json({'notifications': [{'id': 'n1', 'title': 'Broken', 'body': 'x', 'imageUrl': '/uploads/missing.jpg'}]})
            : null;
        await tester.pumpWidget(app(const NotificationPage()));
        await pumpFor(tester);
      });
      // Test HTTP answers every image with 400: the errorBuilder swaps it out.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.text('Broken'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
