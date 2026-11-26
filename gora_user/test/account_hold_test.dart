import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/home_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/taxi_booking_screen.dart';
import 'package:customer_app/screens/welcome_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/ride_booking.dart';
import 'package:customer_app/utils/vehicle_marker.dart';
import 'package:customer_app/widgets/finding_driver_view.dart';
import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/services/session_guard.dart';

// Account hold (profile.user.hold, 403 {accountHold} on /rides/book) and the
// sign-out after an approved deletion (401 {accountDeleted} on the profile).

const _holdMsg = 'Your account is on hold: Wallet mis-transaction. Please contact support.';

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

/// What the profile and booking endpoints answer in each test.
Map<String, dynamic> profile = {};
int profileStatus = 200;
http.Response Function() bookAnswer = () => _json({'ride': {'id': 'ride1', 'otp': '1234'}});
final requests = <http.Request>[];

Future<http.Response> _handle(http.Request req) async {
  requests.add(req);
  final p = req.url.path;
  if (p.endsWith('/auth/user/profile')) return _json(profile, profileStatus);
  if (p.endsWith('/rides/book')) return bookAnswer();
  if (p.endsWith('/fare/estimate') && !req.body.contains('outstation')) {
    return _json({'available': true, 'distance': 6.2, 'duration': 14, 'vehicles': [
      {'name': 'Bike', 'fare': 120, 'etaMin': 3, 'capacity': 1, 'quoteToken': 'q1'},
    ]});
  }
  if (p.endsWith('/places/reverse')) return _json({'address': 'DLF Cyber City, Gurugram, Haryana'});
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'hawa', 'description': 'Hawa Mahal Road, Jaipur, Rajasthan', 'mainText': 'Hawa Mahal',
        'secondaryText': 'Jaipur, Rajasthan'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 26.9239, 'lng': 75.8267, 'address': 'Hawa Mahal Road, Jaipur, Rajasthan'});
  if (p.endsWith('/payment/config')) return _json({'razorpay': {'enabled': false}, 'walletEnabled': true});
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 268, 'oneWayMin': 310, 'vehicles': [
      {'name': 'SUV', 'capacity': 6, 'fare': 5400, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-SUV',
        'breakdown': {'base': 5400, 'nightHalt': 0, 'emptyReturn': 0}},
    ]});
  }
  return _json({});
}

final _api = MockClient(_handle);
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => _api);

Widget _app(Widget home, {UserProvider? user}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => user ?? UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: home, navigatorKey: SessionGuard.navigatorKey),
);

Future<void> wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester tester, [Size s = const Size(400, 860)]) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 9));
  while (tester.takeException() != null) {}
}

void _gps({required bool on}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
    if (!on) return call.method == 'isLocationServiceEnabled' ? false : null;
    switch (call.method) {
      case 'isLocationServiceEnabled': return true;
      case 'checkPermission':
      case 'requestPermission': return 3;
      case 'getCurrentPosition':
      case 'getLastKnownPosition':
        return <String, dynamic>{
          'latitude': 28.4950, 'longitude': 77.0895, 'accuracy': 5.0, 'altitude': 0.0, 'heading': 0.0,
          'speed': 0.0, 'speed_accuracy': 1.0, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'is_mocked': false,
        };
    }
    return null;
  });
}

class _BookButton extends StatelessWidget {
  final Future<Map<String, dynamic>> Function() book;
  final String Function(String)? failureMessage;
  const _BookButton({required this.book, this.failureMessage});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ElevatedButton(
      onPressed: () => bookAndTrack(context, book: (_, _) => book(), failureMessage: failureMessage),
      child: const Text('Book'),
    )),
  );
}

void main() {
  setUp(() {
    requests.clear();
    profile = {'user': {'name': 'Asha', 'phone': '9000000001', 'hold': null}};
    profileStatus = 200;
    bookAnswer = () => _json({'ride': {'id': 'ride1', 'otp': '1234'}});
    SharedPreferences.setMockInitialValues({'token': 't', 'user_token': 't'});
    _gps(on: false);
  });

  group('bookAndTrack', () {
    testWidgets('403 accountHold → "Account on hold" dialog with the message, not a snackbar', (tester) async {
      await tester.pumpWidget(_app(_BookButton(
          book: () async => {'error': _holdMsg, 'accountHold': true, 'holdKind': 'wallet'})));
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('Account on hold'), findsOneWidget);
      expect(find.textContaining(_holdMsg), findsOneWidget);
      expect(find.textContaining("can't book rides"), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Contact support'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Account on hold'), findsNothing);
      expect(find.text('Book'), findsOneWidget, reason: 'still on the booking screen');
    });

    testWidgets('a paid-upfront failure keeps its "do not pay again" text in the hold dialog', (tester) async {
      await tester.pumpWidget(_app(_BookButton(
          book: () async => {'error': _holdMsg, 'accountHold': true},
          failureMessage: (e) => 'Your payment went through, but the trip could not be booked ($e). Do not pay again.')));
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('Account on hold'), findsOneWidget);
      expect(find.textContaining('Do not pay again.'), findsOneWidget);
    });

    testWidgets('a paid-upfront hold refusal that was refunded says the money is back', (tester) async {
      await tester.pumpWidget(_app(_BookButton(
          book: () async => {'error': _holdMsg, 'accountHold': true, 'refunded': 800, 'refundedTo': 'wallet'},
          failureMessage: (e) => 'Your payment went through, but the trip could not be booked ($e). Do not pay again.')));
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      expect(find.text('Account on hold'), findsOneWidget);
      expect(find.textContaining('₹800 has been returned to your Gora wallet'), findsOneWidget);
      expect(find.textContaining('Do not pay again.'), findsNothing);
    });

    testWidgets('other failures still use the snackbar', (tester) async {
      await tester.pumpWidget(_app(_BookButton(book: () async => {'error': 'No drivers in your area'})));
      await tester.tap(find.text('Book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Booking failed: No drivers in your area'), findsOneWidget);
      expect(find.text('Account on hold'), findsNothing);
    });
  });

  group('taxi booking', () {
    Future<void> bookTaxi(WidgetTester tester) async {
      _size(tester);
      await tester.runAsync(() => VehicleMarkers.descriptorFor('Bike'));
      await act(() async {
        await tester.pumpWidget(_app(const TaxiBookingScreen(
            fromLocation: 'Navrangpura', toLocation: 'Bodakdev', hideLocationInputs: true, preselectedVehicle: 'Bike')));
        await wait(tester, 1000);
        tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
        await wait(tester, 300);
        await tester.tap(find.text('Choose Bike'));
        await wait(tester, 600);
        await tester.tap(find.text('Confirm Pickup'));
        await wait(tester, 600);
        await tester.ensureVisible(find.text('Confirm Ride'));
        await tester.tap(find.text('Confirm Ride'));
        await wait(tester, 1000);
      });
    }

    testWidgets('a held rider gets the hold dialog and no "finding your ride"', (tester) async {
      bookAnswer = () => _json({'error': _holdMsg, 'accountHold': true, 'holdKind': 'wallet'}, 403);
      await bookTaxi(tester);
      expect(find.text('Account on hold'), findsOneWidget);
      expect(find.textContaining(_holdMsg), findsOneWidget);
      expect(find.byType(FindingDriverView), findsNothing);
      await _teardown(tester);
    });

    testWidgets('any other refused booking is reported instead of searching for nothing', (tester) async {
      bookAnswer = () => _json({'error': 'Pickup is outside our service area'}, 400);
      await bookTaxi(tester);
      expect(find.text('Booking failed: Pickup is outside our service area'), findsOneWidget);
      expect(find.byType(FindingDriverView), findsNothing);
      expect(find.text('Account on hold'), findsNothing);
      await _teardown(tester);
    });
  });

  testWidgets('outstation: a held rider is stopped before paying or booking', (tester) async {
    _gps(on: true);
    _size(tester, const Size(392, 850));
    final user = UserProvider()
      ..setUser({'name': 'Asha', 'hold': {'kind': 'wallet', 'reason': 'Wallet mis-transaction', 'message': _holdMsg}});
    await act(() async {
      await tester.pumpWidget(_app(const OutstationScreen(), user: user));
      await wait(tester, 800);
      await tester.enterText(find.byType(TextField).at(1), 'Hawa Mahal');
      await wait(tester, 800);
      await tester.tap(find.widgetWithText(ListTile, 'Hawa Mahal'));
      await wait(tester, 400);
      await tester.tap(find.text('Confirm Location'));
      await wait(tester, 1500);
      await tester.drag(find.text('Trip Details'), const Offset(0, -520), warnIfMissed: false);
      await wait(tester, 600);
      final list = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
      await tester.ensureVisible(find.text('Select Vehicle'));
      // The vehicle list is open by default now (it used to start collapsed).
      await wait(tester, 500);
      await tester.scrollUntilVisible(find.text('₹5400'), 150, scrollable: list);
      await tester.tap(find.text('₹5400').first);
      await wait(tester, 500);
      await tester.tap(find.text('Book Trip'));
      await wait(tester, 800);
      await tester.tap(find.text('Confirm Booking'));
      await wait(tester, 800);
    });
    expect(find.text('Account on hold'), findsOneWidget);
    expect(find.textContaining(_holdMsg), findsOneWidget);
    expect(requests.where((r) => r.url.path.endsWith('/rides/book')), isEmpty);
    expect(requests.where((r) => r.url.path.contains('/wallet') || r.url.path.contains('/razorpay')), isEmpty);
    await _teardown(tester);
  });

  group('home', () {
    Future<void> openHome(WidgetTester tester) async {
      _size(tester);
      await act(() async {
        await tester.pumpWidget(_app(const HomeScreen()));
        await wait(tester, 1000);
      });
    }

    testWidgets('a held profile shows the red banner with the message', (tester) async {
      profile = {'user': {'name': 'Asha', 'hold': {'kind': 'wallet', 'reason': 'Wallet mis-transaction', 'message': _holdMsg}}};
      await openHome(tester);
      expect(find.byKey(const ValueKey('account-hold-banner')), findsOneWidget);
      expect(find.text('Account on hold'), findsOneWidget);
      expect(find.text(_holdMsg), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('no hold → no banner', (tester) async {
      await openHome(tester);
      expect(find.byKey(const ValueKey('account-hold-banner')), findsNothing);
      await _teardown(tester);
    });

    testWidgets('401 accountDeleted signs the rider out to the welcome screen', (tester) async {
      profile = {'error': 'Unauthorized', 'accountDeleted': true};
      profileStatus = 401;
      await openHome(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Your account has been deleted. You have been signed out.'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_token'), isNull);
      await _teardown(tester);
    });

    // A token the server no longer accepts: every authenticated call answers a
    // plain 401. The rider used to stay on home with every poll failing; now
    // they are signed out once, to the welcome screen, and the token is gone.
    testWidgets('a plain 401 (expired token) signs out once to the welcome screen', (tester) async {
      profile = {'error': 'Unauthorized'};
      profileStatus = 401;
      await openHome(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Your session has expired. Please sign in again.'), findsOneWidget);
      expect(await ApiService.getToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_token'), isNull);
      // Later 401s (polls still in flight) do not navigate again.
      final pushes = SessionGuard.signOuts.value;
      await act(() async {
        await ApiService.get('/auth/user/profile');
        await wait(tester, 300);
      });
      expect(SessionGuard.signOuts.value, pushes);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a 401 to a request sent without a token does not sign anyone out', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final before = SessionGuard.signOuts.value;
      await act(() async {
        profile = {'error': 'Unauthorized'};
        profileStatus = 401;
        await ApiService.get('/auth/user/profile');
      });
      expect(SessionGuard.signOuts.value, before);
    });
  });

  test('UserProvider: accountDeleted clears the token and the user; hold is exposed', () async {
    await act(() async {
      final u = UserProvider();
      profile = {'user': {'name': 'Asha', 'hold': {'kind': 'manual', 'reason': 'Held by admin', 'message': 'm'}}};
      await u.loadProfile();
      expect(u.hold?['message'], 'm');
      expect(u.accountDeleted, isFalse);
      profile = {'error': 'Unauthorized', 'accountDeleted': true};
      profileStatus = 401;
      await u.loadProfile();
      expect(u.accountDeleted, isTrue);
      expect(u.user, isNull);
      expect(u.hold, isNull);
      expect((await SharedPreferences.getInstance()).getString('user_token'), isNull);
      u.clear();
      expect(u.accountDeleted, isFalse);
    });
  });
}
