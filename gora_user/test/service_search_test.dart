import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/hire_driver_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/parcel_booking_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/net_errors.dart';

// Place search on the service screens (parcel, rental, intercity, hire):
// location bias + one Places session per search, the empty-list states
// (searching / rate limited / nothing found), the stale-answer guard, and the
// fare / package loads saying offline vs server with a Retry. Also the parcel
// receiver's phone check.

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

const _rajkot = 'Sadar, Rajkot, Gujarat 360001, India';
const _ahmedabad = 'Ahmedabad, Gujarat, India';

Map<String, dynamic> _v(String name, int fare) => {
      'name': name, 'capacity': 4, 'fare': fare, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-$name', 'perHour': 150,
    };

Future<http.Response> _base(http.Request req) async {
  final p = req.url.path;
  if (p.endsWith('/places/reverse')) return _json({'address': _rajkot});
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'amd', 'description': _ahmedabad, 'mainText': 'Ahmedabad', 'secondaryText': 'Gujarat, India'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 23.0225, 'lng': 72.5714, 'address': _ahmedabad});
  if (p.endsWith('/rental/packages')) {
    return _json({'available': true, 'packages': [
      {'vehicleTypeName': 'Cab', 'hours': 4, 'km': 40, 'basePrice': 848, 'capacity': 4, 'extraHourRate': 180, 'extraKmRate': 14, 'imageUrl': ''},
    ]});
  }
  if (p.endsWith('/fare/estimate')) return _json({'available': true, 'vehicles': [_v('Bike', 90), _v('Cab', 400)]});
  return _json({});
}

Widget _app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => UserProvider()..setUser({'name': 'Test Rider', 'phone': '9876500000'})),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

Future<void> wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await wait(tester, 1000);
  while (tester.takeException() != null) {}
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
  }
  await tester.ensureVisible(f);
  await wait(tester, 200);
  await tester.tap(f);
  await wait(tester, 300);
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled': return true;
        case 'checkPermission':
        case 'requestPermission': return 3;
        case 'getCurrentPosition':
        case 'getLastKnownPosition':
          return <String, dynamic>{
            'latitude': 22.3039, 'longitude': 70.8022, 'accuracy': 5.0, 'altitude': 0.0, 'heading': 0.0,
            'speed': 0.0, 'speed_accuracy': 1.0, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'is_mocked': false,
          };
      }
      return null;
    });
  });

  group('helpers', () {
    test('PlacesResult names the problem only for a rate limit or a failure', () {
      expect(const PlacesResult([]).problem, isNull);
      expect(const PlacesResult([], rateLimited: true).problem, 'Too many searches, try again in a moment');
      expect(const PlacesResult([], failed: true).problem, contains("Couldn't search"));
    });

    test('PlacesSession renews to a different token', () {
      final s = PlacesSession();
      final first = s.token;
      expect(first, matches(RegExp(r'^[a-z0-9]{32}$')));
      s.renew();
      expect(s.token, isNot(first));
    });

    test('offline vs server failures', () {
      expect(classifyFailure(const SocketException('no route')), LoadFailure.offline);
      expect(classifyFailure(TimeoutException('slow')), LoadFailure.offline);
      expect(classifyFailure(const FormatException('bad')), LoadFailure.server);
      expect(classifyResponse({'error': 'Server error (502). Please try again.', 'httpStatus': 502}), LoadFailure.server);
      expect(classifyResponse({'error': 'Could not read the server response. Check your connection.'}), LoadFailure.offline);
      expect(loadFailureMessage(LoadFailure.offline), contains("You're offline"));
      expect(loadFailureMessage(LoadFailure.server, what: 'hire prices'), contains("Couldn't load hire prices"));
    });
  });

  group('parcel search', () {
    testWidgets('sends the pickup bias + one session token, reused by details, renewed after the pick', (tester) async {
      _size(tester);
      final auto = <Uri>[];
      final details = <Uri>[];
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/places/autocomplete')) auto.add(req.url);
        if (req.url.path.endsWith('/places/details')) details.add(req.url);
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await tester.enterText(find.byType(TextField).at(1), 'Ahme');
        await wait(tester, 600);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
        await wait(tester, 800);
        await tester.enterText(find.byType(TextField).at(1), 'Rajkot');
        await wait(tester, 800);
      }, () => client);
      expect(auto, hasLength(3));
      final t1 = auto[0].queryParameters['sessiontoken'];
      expect(t1, isNotNull);
      expect(auto[1].queryParameters['sessiontoken'], t1, reason: 'one token for the whole search');
      expect(auto[0].queryParameters['lat'], '22.303900');
      expect(auto[0].queryParameters['lng'], '70.802200');
      expect(details.single.queryParameters['sessiontoken'], t1, reason: 'the pick ends the session');
      expect(auto[2].queryParameters['sessiontoken'], isNot(t1), reason: 'a new search, a new session');
      await _teardown(tester);
    });

    testWidgets('a 429 says "Too many searches" instead of no places', (tester) async {
      _size(tester);
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/places/autocomplete')) {
          return _json({'error': 'Too many requests, please slow down', 'code': 'RATE_LIMITED'}, 429);
        }
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
      }, () => client);
      expect(find.text('Too many searches, try again in a moment'), findsOneWidget);
      expect(find.textContaining('No places found'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('nothing matched shows an empty state', (tester) async {
      _size(tester);
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/places/autocomplete')) return _json({'predictions': []});
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await tester.enterText(find.byType(TextField).at(1), 'zzqx');
        await wait(tester, 800);
      }, () => client);
      expect(find.text('No places found for "zzqx"'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('parcel receiver phone', () {
    Future<void> fill(WidgetTester tester, String phone) async {
      await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
      await wait(tester, 800);
      await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
      await wait(tester, 800);
      await _tapVisible(tester, find.text('Add receiver contact'));
      await wait(tester, 400);
      await tester.enterText(find.widgetWithText(TextField, 'Receiver name'), 'Meera Patel');
      await tester.enterText(find.widgetWithText(TextField, 'Receiver phone'), phone);
      await wait(tester, 200);
    }

    testWidgets('a landline / short number is refused with a clear message', (tester) async {
      _size(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await fill(tester, '12345');
        expect(find.byKey(const ValueKey('receiver-phone-error')), findsOneWidget);
        await tester.tap(find.text('Done'));
        await wait(tester, 600);
        await _tapVisible(tester, find.text('Documents'));
        await _tapVisible(tester, find.text('Bike'));
      }, () => MockClient(_base));
      expect(find.text('Enter a valid receiver mobile number'), findsOneWidget);
      expect(find.text('Receiver · check the mobile number'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a pasted +91 number is accepted and booked as 10 digits', (tester) async {
      _size(tester);
      Map<String, dynamic>? booked;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/rides/book')) {
          booked = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'error': 'stop here'});
        }
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await fill(tester, '+91 91234 56780');
        expect(find.byKey(const ValueKey('receiver-phone-error')), findsNothing);
        await tester.tap(find.text('Done'));
        await wait(tester, 600);
        await _tapVisible(tester, find.text('Documents'));
        await _tapVisible(tester, find.text('Bike'));
        await _tapVisible(tester, find.text('Book Bike · ₹90'));
        await wait(tester, 600);
        final confirm = find.textContaining('Confirm');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.last);
          await wait(tester, 800);
        }
      }, () => client);
      expect(booked, isNotNull);
      expect(booked!['receiverPhone'], '9123456780');
      await _teardown(tester);
    });
  });

  group('intercity search', () {
    testWidgets('an older, slower answer never replaces a newer one', (tester) async {
      _size(tester);
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/places/autocomplete')) {
          final q = req.url.queryParameters['q'] ?? '';
          if (q == 'Sur') {
            await Future<void>.delayed(const Duration(seconds: 2));
            return _json({'predictions': [
              {'placeId': 'old', 'description': 'Old Answer', 'mainText': 'Old Answer', 'secondaryText': ''},
            ]});
          }
          return _json({'predictions': [
            {'placeId': 'srt', 'description': 'Surat, Gujarat', 'mainText': 'Surat', 'secondaryText': 'Gujarat'},
          ]});
        }
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const OutstationScreen()));
        await wait(tester, 1200);
        final to = find.widgetWithText(TextField, 'To city');
        await tester.enterText(to, 'Sur');
        await wait(tester, 500); // first request now in flight (2 s)
        expect(find.text('Searching…'), findsOneWidget);
        await tester.enterText(to, 'Surat');
        await wait(tester, 3000);
      }, () => client);
      expect(find.text('Surat'), findsWidgets);
      expect(find.text('Old Answer'), findsNothing);
      await _teardown(tester);
    });
  });

  group('fare and package loads', () {
    testWidgets('hire: offline says so and Retry reloads the prices', (tester) async {
      _size(tester);
      var offline = true;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/fare/estimate') && offline) throw const SocketException('no network');
        return _base(req);
      });
      final start = DateTime.now().add(const Duration(days: 1));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(HireDriverScreen(initialStartAt: start, initialEndAt: start.add(const Duration(hours: 4)))));
        await wait(tester, 1000);
        await tester.scrollUntilVisible(find.textContaining("You're offline"), 150, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining("You're offline"), findsOneWidget);
        offline = false;
        await tester.tap(find.text('Retry'));
        await wait(tester, 800);
      }, () => client);
      expect(find.textContaining("You're offline"), findsNothing);
      expect(find.text('Cab'), findsWidgets);
      await _teardown(tester);
    });

    testWidgets('rental: a server error is not "no packages" and offers Retry', (tester) async {
      _size(tester);
      var fail = true;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/rental/packages') && fail) return http.Response('<html>502</html>', 502);
        return _base(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RentalScreen()));
        await wait(tester, 1200);
        await tester.scrollUntilVisible(find.textContaining("Couldn't load rental packages"), 150,
            scrollable: find.byType(Scrollable).first);
        expect(find.textContaining("Couldn't load rental packages"), findsOneWidget);
        fail = false;
        await tester.tap(find.text('Retry'));
        await wait(tester, 800);
      }, () => client);
      expect(find.textContaining("Couldn't load rental packages"), findsNothing);
      await _teardown(tester);
    });
  });
}
