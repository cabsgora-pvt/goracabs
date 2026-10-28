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
import 'package:gora_driver/core/widgets/app_widgets.dart';
import 'package:gora_driver/features/account/pages/misc_pages.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/auth/pages/driver_otp_page.dart';
import 'package:gora_driver/features/registration/document_upload_page.dart';
import 'package:gora_driver/features/registration/face_capture_page.dart';
import 'package:gora_driver/features/registration/vehicle_selection_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/splash/splash_page.dart';
import 'package:gora_driver/features/earnings/bloc/earnings_bloc.dart';
import 'package:gora_driver/features/history/pages/trip_detail_page.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/home/pages/map_placeholder.dart';
import 'package:gora_driver/features/registration/personal_details_page.dart';
import 'package:gora_driver/features/ride/logic/dismissed_requests.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/pages/hire_progress_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/pages/on_ride_page.dart';
import 'package:gora_driver/features/ride/pages/rental_progress_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';
import 'package:gora_driver/utils/format_minutes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regressions found running the redesigned driver app on an emulator against
// production. One group per reported bug.
// ─────────────────────────────────────────────────────────────────────────────

typedef Handler = Future<http.Response> Function(http.Request req);

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _app(Widget home, {Map<String, WidgetBuilder>? routes, DriverProvider? dp}) => MultiProvider(
  providers: [
    if (dp != null) ChangeNotifierProvider.value(value: dp) else ChangeNotifierProvider(create: (_) => DriverProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: BlocProvider(
    create: (_) => AuthBloc(),
    child: MaterialApp(theme: AppTheme.light, routes: {...AppRoutes.routes, ...?routes}, home: home),
  ),
);

void _setSize(WidgetTester tester, [Size size = const Size(360, 800)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFor(WidgetTester tester, Duration d, {Duration step = const Duration(milliseconds: 100)}) async {
  var t = Duration.zero;
  while (t < d) {
    await tester.pump(step);
    t += step;
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
  while (tester.takeException() != null) {}
}

Map<String, dynamic> _request(String id, String service, {String drop = 'Prahlad Nagar, Ahmedabad'}) => {
  'id': id, 'service': service, 'riderName': 'Rahul Mehta', 'vehicleType': 'Bike',
  'pickupAddress': 'Law Garden, Ellisbridge, Ahmedabad', 'dropAddress': drop,
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 85, 'totalFare': 85, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
  'packageHours': 4, 'packageKm': 40,
};

RideRequestModel _ride({String service = 'taxi', String status = 'ongoing', RideProgress progress = const RideProgress(),
    List<Map<String, dynamic>> stops = const [], String paymentMode = 'cash'}) => RideRequestModel(
  id: 'ride-1', userName: 'Rahul Mehta', userPhone: '+91 98765 43210', userRating: '4.9',
  pickupAddress: 'Law Garden, Ellisbridge, Ahmedabad', dropAddress: 'Prahlad Nagar, Ahmedabad',
  distance: '6.2 km', fare: '₹ 150', eta: '12 min', rideType: 'Bike',
  pickupLat: 23.0266, pickupLng: 72.5609, dropLat: 23.0120, dropLng: 72.5108,
  service: service, status: status, progress: progress, stops: stops, paymentMode: paymentMode,
  packageHours: 4, packageKm: 40, hireTotalHours: 8,
  senderName: 'Sender', senderPhone: '+91 90000 11111', receiverName: 'Receiver', receiverPhone: '+91 90000 22222',
  totalFareValue: 150,
);

/// Drags the request's "Slide to accept" knob [fraction] of the way along.
Future<void> _slide(WidgetTester tester, double fraction) async {
  final track = find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == 'Slide to accept');
  expect(track, findsOneWidget);
  await tester.ensureVisible(track);
  await tester.pump();
  final rect = tester.getRect(track);
  final travel = rect.width * fraction;
  final g = await tester.startGesture(Offset(rect.left + 29, rect.center.dy));
  for (var i = 0; i < 10; i++) {
    await g.moveBy(Offset(travel / 10, 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await g.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  setUp(() {
    DismissedRequests.clear();
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
        (c) async => c.method == 'isLocationServiceEnabled' ? false : null);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
  });

  // ── 1. Home goes blank as soon as the driver is online ──────────────────────
  testWidgets('#1 home ONLINE renders the map, status and go-offline control', (tester) async {
    _setSize(tester, const Size(360, 760));
    SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
    final layoutErrors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final t = d.exceptionAsString();
      if (t.contains('overflowed') || t.contains('RenderFlex') || t.contains('unbounded') ||
          t.contains('was not laid out') || t.contains('RenderBox')) {
        layoutErrors.add(t.split('\n').first);
        return;
      }
      prev?.call(d);
    };
    try {
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const HomePage()));
        await _pumpFor(tester, const Duration(milliseconds: 800));
        expect(find.text("You're online"), findsOneWidget);
        expect(find.text('Finding trips near you'), findsOneWidget);
        expect(find.text('Go offline'), findsOneWidget);
        expect(find.text('GO'), findsNothing);
        final map = tester.getSize(find.byType(MapPlaceholder));
        expect(map.height, greaterThan(500), reason: 'the map must fill the screen, not collapse to 0x0');
        expect(tester.getSize(find.text('Go offline')).height, greaterThan(0));
        await _teardown(tester);
      }, () => MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/rides/driver/pending')) return _json({'rides': []});
        if (p.endsWith('/rides/driver/active')) return _json({'ride': null});
        if (p.endsWith('/rides/driver/summary')) return _json({'today': 420, 'week': 900, 'totalRides': 3, 'todayDistance': 12});
        if (p.endsWith('/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
        if (p.endsWith('/auth/driver/wallet')) return _json({'balance': 500, 'transactions': []});
        return _json({});
      }));
    } finally {
      FlutterError.onError = prev;
    }
    expect(layoutErrors, isEmpty);
  });

  // ── 2. Accepting leaves an empty "New trip request" page ────────────────────
  group('#2 accepting opens the trip for every service', () {
    for (final service in ['taxi', 'delivery', 'outstation', 'rental', 'hire_driver']) {
      testWidgets(service, (tester) async {
        _setSize(tester);
        var accepts = 0;
        var accepted = false;
        await http.runWithClient(() async {
          await tester.pumpWidget(_app(Builder(builder: (context) => Scaffold(
            body: Center(child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, IncomingRequestsPage.route),
              child: const Text('HOME'),
            )),
          ))));
          await tester.tap(find.text('HOME'));
          await _pumpFor(tester, const Duration(milliseconds: 500));
          // Slide while the page's 3s refresh is in flight (each pending call
          // takes 1s), and the accept takes 2s — the refresh comes back after
          // the server has already taken the ride out of 'pending'.
          // First feed answer at 1.0s starts the 3s refresh timer, so a refresh
          // leaves at 4.0s and returns at 5.0s. The slide commits at ~4.4s.
          await _pumpFor(tester, const Duration(milliseconds: 3600));
          await _slide(tester, 1.0);
          await _pumpFor(tester, const Duration(seconds: 5));
          expect(accepts, 1);
          expect(find.byType(OnRidePage), findsOneWidget, reason: 'the trip opens after accepting a $service request');
          expect(find.byType(IncomingRequestsPage), findsNothing);
          expect(find.text('New trip request'), findsNothing);
          await _teardown(tester);
        }, () => MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/accept')) {
            accepts++;
            accepted = true;
            await Future<void>.delayed(const Duration(seconds: 2));
            return _json({'success': true, 'ride': {..._request('r1', service), 'status': 'accepted'}});
          }
          if (p.endsWith('/rides/driver/pending')) {
            await Future<void>.delayed(const Duration(seconds: 1));
            // Answered as the server would at reply time: once accepted, the
            // ride is no longer pending.
            return _json({'rides': !accepted ? [_request('r1', service, drop: service == 'rental' || service == 'hire_driver' ? '' : 'Prahlad Nagar')] : []});
          }
          return _json({});
        }));
      });
    }
  });

  // ── 2b. Rental accept left on an empty "New trip request" page ────────────
  // Production rows: rental/hire carry no drop (nulls), opt-in services stay in
  // the feed for 15 minutes, and the feed does not leave out a driver already
  // on a job — so after an accept the home poller kept finding other requests.
  Map<String, dynamic> prodRow(String id, String svc, {bool offered = true}) {
    final noDrop = svc == 'rental' || svc == 'hire_driver';
    return {
      'id': id, 'riderName': 'Demo Rider', 'riderPhone': '9999999999', 'riderProfilePicUrl': '', 'riderRating': null,
      'pickupAddress': 'Guruprasad Appartment, Sadar, Rajkot', 'dropAddress': noDrop ? null : 'Ahmedabad, Gujarat, India',
      'pickupLat': 22.30, 'pickupLng': 70.80, 'dropLat': noDrop ? null : 23.02, 'dropLng': noDrop ? null : 72.57,
      'fare': 899, 'tip': 0, 'totalFare': 899, 'distance': noDrop ? 0 : 220.4, 'duration': noDrop ? 0 : 246,
      'pickupEtaMin': 4, 'offeredToMe': offered,
      'offerExpiresAt': offered ? DateTime.now().add(const Duration(seconds: 20)).toUtc().toIso8601String() : null,
      'pickupDistance': 1.2, 'vehicleType': 'Cab', 'paymentMode': 'cash', 'routePolyline': null,
      'stops': [], 'service': svc, 'tripType': svc == 'outstation' ? 'one_way' : null,
      'departureAt': null, 'numPassengers': null, 'packageHours': 4, 'packageKm': 40,
      'hireTotalHours': svc == 'hire_driver' ? 8 : null, 'transmission': svc == 'hire_driver' ? 'manual' : null,
      'senderName': null, 'itemType': null, 'weightKg': null, 'isFragile': null, 'codAmount': null, 'parcelPhotos': null,
    };
  }

  group('#2b after an accept the trip stays on screen', () {
    for (final svc in ['rental', 'hire_driver', 'outstation']) {
      testWidgets(svc, (tester) async {
        _setSize(tester);
        SharedPreferences.setMockInitialValues({'driver_token': 't', 'driver_online': true});
        var accepted = false;
        await http.runWithClient(() async {
          await tester.pumpWidget(_app(const HomePage()));
          // The home poller (every 4s) opens the request page.
          await _pumpFor(tester, const Duration(seconds: 5));
          expect(find.byType(IncomingRequestsPage), findsOneWidget);
          await _slide(tester, 1.0);
          await _pumpFor(tester, const Duration(seconds: 1));
          expect(accepted, isTrue);
          expect(find.byType(OnRidePage), findsOneWidget);
          // Another booking is still pending. For 30s the request page must not
          // come back over the trip, and an empty one must never be left.
          for (var i = 0; i < 30; i++) {
            await _pumpFor(tester, const Duration(seconds: 1));
            expect(find.byType(IncomingRequestsPage), findsNothing, reason: 'request page reopened over the $svc trip at ${i}s');
            expect(find.text('New trip request'), findsNothing);
          }
          expect(find.byType(OnRidePage), findsOneWidget);
          await _teardown(tester);
        }, () => MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/accept')) {
            accepted = true;
            return _json({'success': true, 'ride': {...prodRow('r1', svc), '_id': 'r1', 'status': 'accepted'}, 'predictedEtaMin': 4});
          }
          if (p.endsWith('/rides/driver/pending')) {
            return _json({'rides': [accepted ? prodRow('other', svc, offered: false) : prodRow('r1', svc)]});
          }
          if (p.endsWith('/rides/driver/active')) return _json({'ride': null});
          if (p.endsWith('/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'name': 'Suresh', 'status': 'approved'}});
          if (p.endsWith('/auth/driver/wallet')) return _json({'balance': 500, 'transactions': []});
          return _json({});
        }));
      });
    }
  });

  testWidgets('#2b a request page that times out under something else removes itself', (tester) async {
    _setSize(tester);
    final nav = GlobalKey<NavigatorState>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, theme: AppTheme.light, routes: {...AppRoutes.routes},
          home: const Scaffold(body: Text('HOME'))));
      nav.currentState!.pushNamed(IncomingRequestsPage.route);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Slide to accept'), findsOneWidget);
      // Something opens above the request page (e.g. the trip's OTP dialog).
      showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('ON TOP')));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      // Its offer runs out: the page must remove ITSELF, not the dialog.
      await _pumpFor(tester, const Duration(seconds: 4));
      expect(find.text('ON TOP'), findsOneWidget, reason: 'the dialog above must not be the one closed');
      expect(find.byType(IncomingRequestsPage), findsNothing, reason: 'no orphaned empty request page');
      await _teardown(tester);
    }, () => MockClient((req) async => req.url.path.endsWith('/rides/driver/pending')
        ? _json({'rides': [{..._request('t1', 'taxi'), 'offeredToMe': true,
            'offerExpiresAt': DateTime.now().add(const Duration(seconds: 2)).toUtc().toIso8601String()}]})
        : _json({})));
  });

  testWidgets('collect fare shows whole rupees without ".0"', (tester) async {
    _setSize(tester);
    await tester.pumpWidget(_app(const CollectFarePage(amount: 40)));
    expect(find.text('₹40'), findsOneWidget);
    expect(find.text('₹40.0'), findsNothing);
    await tester.pumpWidget(_app(const CollectFarePage(amount: 40.5)));
    expect(find.text('₹40.50'), findsOneWidget);
    await _teardown(tester);
  });


  // ── R1. Unfinished registration resumes at the server's step ────────────────
  group('R1 registration resumes where the server says', () {
    // (server registrationStep, selfie saved?, the page that must open)
    final cases = <(String, bool, Type)>[
      ('otp', false, PersonalDetailsPage),
      ('vehicle', false, FaceCapturePage),
      ('vehicle', true, VehicleSelectionPage),
      ('documents', true, DocumentUploadPage),
    ];
    Map<String, dynamic> driver(String step, bool face) => {
      '_id': 'd1', 'name': 'Suresh Kumar', 'phone': '9876543210', 'status': 'pending',
      'registrationStep': step, 'zoneId': 'z1', 'zoneName': 'Rajkot',
      if (face) 'faceSignatureSavedAt': '2026-10-27T10:00:00.000Z',
    };
    Future<http.Response> api(http.Request req, Map<String, dynamic> d) async {
      final p = req.url.path;
      if (p.endsWith('/auth/driver/profile')) return _json({'driver': d});
      if (p.endsWith('/auth/driver/verify-otp')) {
        return _json({'token': 'tok', 'driver': d, 'registrationStep': d['registrationStep']});
      }
      if (p.endsWith('/zones')) return _json({'zones': []});
      if (p.endsWith('/vehicles/types')) return _json({'types': []});
      return _json({});
    }

    for (final (step, face, page) in cases) {
      final tag = '$step${face ? ' + selfie' : ''}';
      testWidgets('relaunch: $tag -> $page', (tester) async {
        _setSize(tester);
        await http.runWithClient(() async {
          await tester.pumpWidget(_app(const SplashPage()));
          await _pumpFor(tester, const Duration(milliseconds: 3000));
          expect(find.byType(page), findsOneWidget);
          await _teardown(tester);
        }, () => MockClient((req) => api(req, driver(step, face))));
      });

      testWidgets('OTP login: $tag -> $page', (tester) async {
        _setSize(tester);
        SharedPreferences.setMockInitialValues({});
        await http.runWithClient(() async {
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => DriverProvider()),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ],
            child: BlocProvider(create: (_) => AuthBloc(), child: MaterialApp(
              theme: AppTheme.light, routes: {...AppRoutes.routes},
              onGenerateRoute: (s) => MaterialPageRoute(
                settings: RouteSettings(name: s.name, arguments: '9876543210'),
                builder: (_) => const DriverOtpPage()),
            )),
          ));
          await _pumpFor(tester, const Duration(milliseconds: 300));
          final boxes = find.byType(TextFormField);
          for (var i = 0; i < 6; i++) {
            await tester.enterText(boxes.at(i), '${i + 1}');
            await tester.pump();
          }
          await _pumpFor(tester, const Duration(milliseconds: 800));
          expect(find.byType(page), findsOneWidget);
          await _teardown(tester);
        }, () => MockClient((req) => api(req, driver(step, face))));
      });
    }

    test('control: bank and submitted keep their own pages, not a resume', () {
      expect(resumeStepFor({'registrationStep': 'bank'}), isNull);
      expect(resumeStepFor({'registrationStep': 'submitted'}), isNull);
      expect(resumeStepFor({'registrationStep': 'documents'}), ResumeStep.documents);
    });
  });

  // ── R2. Parcel: the drop OTP goes through -> straight to the bill ───────────
  group('R2 after the drop OTP the page moves on', () {
    Future<void> deliver(WidgetTester tester, {required String payment, required Handler api}) async {
      _setSize(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(DeliveryProgressPage(
          ride: _ride(service: 'delivery', paymentMode: payment, progress: const RideProgress(deliveryPhase: 'in_transit')),
          initialProofPhoto: 'https://goracabs.com/uploads/proof.jpg',
        )));
        await _pumpFor(tester, const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('Delivered — enter receiver OTP'));
        await tester.tap(find.text('Delivered — enter receiver OTP'));
        await _pumpFor(tester, const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), '4821');
        await tester.tap(find.text('Deliver'));
        await _pumpFor(tester, const Duration(seconds: 1));
      }, () => MockClient(api));
    }

    // What /rides/:id/delivery answers for a cash parcel with COD.
    final deliveredCash = {'success': true, 'deliveryPhase': 'delivered', 'status': 'ongoing',
      'fareDue': 150, 'codDue': 500, 'amountDue': 650, 'failReason': null};

    testWidgets('cash: the collect-fare step opens for fare + COD', (tester) async {
      await deliver(tester, payment: 'cash', api: (req) async =>
          req.url.path.endsWith('/delivery') ? _json(deliveredCash) : _json({}));
      expect(find.byType(CollectFarePage), findsOneWidget);
      expect(find.text('₹650'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('online, no COD: settled and the invoice opens', (tester) async {
      await deliver(tester, payment: 'online', api: (req) async {
        final p = req.url.path;
        if (p.endsWith('/delivery')) {
          return _json({'success': true, 'deliveryPhase': 'delivered', 'status': 'ongoing',
            'fareDue': 0, 'codDue': 0, 'amountDue': 0, 'failReason': null});
        }
        if (p.endsWith('/complete')) return _json({'success': true, 'driverEarning': 120, 'adminProfit': 30});
        return _json({});
      });
      expect(find.byType(InvoicePage), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('the reply is lost but the server delivered it: still moves on', (tester) async {
      await deliver(tester, payment: 'cash', api: (req) async {
        final p = req.url.path;
        if (p.endsWith('/delivery')) return http.Response('<html>502 Bad Gateway</html>', 502);
        if (p.endsWith('/rides/ride-1')) {
          return _json({'_id': 'ride-1', 'service': 'delivery', 'status': 'ongoing', 'paymentMode': 'cash',
            'deliveryPhase': 'delivered', 'totalFare': 150, 'codCollected': 500});
        }
        return _json({});
      });
      expect(find.byType(CollectFarePage), findsOneWidget);
      expect(find.text('₹650'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('control: a wrong OTP stays put and says so', (tester) async {
      await deliver(tester, payment: 'cash', api: (req) async {
        final p = req.url.path;
        if (p.endsWith('/delivery')) return _json({'error': 'Invalid delivery OTP'}, 400);
        if (p.endsWith('/rides/ride-1')) return _json({'_id': 'ride-1', 'deliveryPhase': 'in_transit'});
        return _json({});
      });
      expect(find.text('Invalid delivery OTP'), findsOneWidget);
      expect(find.text('Delivered — enter receiver OTP'), findsOneWidget);
      expect(find.byType(CollectFarePage), findsNothing);
      await _teardown(tester);
    });
  });

  // ── R3. The last trip's Order Complete must not sit under the next trip ─────
  testWidgets('R3 accepting a request over Order Complete leaves only home under the trip', (tester) async {
    _setSize(tester);
    final nav = GlobalKey<NavigatorState>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DriverProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(navigatorKey: nav, theme: AppTheme.light, routes: {...AppRoutes.routes},
            home: const Scaffold(body: Text('HOME'))),
      ));
      nav.currentState!.pushNamed(InvoicePage.route, arguments: _ride());
      await _pumpFor(tester, const Duration(milliseconds: 400));
      nav.currentState!.pushNamed(IncomingRequestsPage.route);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await _slide(tester, 1.0);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(OnRidePage), findsOneWidget);
      expect(find.byType(InvoicePage, skipOffstage: false), findsNothing,
          reason: 'the previous trip Order Complete must not be under the new trip');
      // Back from the new trip lands on home, not on an old invoice.
      nav.currentState!.pop();
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('HOME'), findsOneWidget);
      await _teardown(tester);
    }, () => MockClient((req) async {
      if (req.url.path.endsWith('/accept')) return _json({'success': true, 'ride': _request('r2', 'taxi')});
      if (req.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [_request('r2', 'taxi')]});
      return _json({});
    }));
  });

  testWidgets('R3 Done on Order Complete returns to a clean home', (tester) async {
    _setSize(tester);
    final nav = GlobalKey<NavigatorState>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DriverProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(navigatorKey: nav, theme: AppTheme.light,
            routes: {...AppRoutes.routes, '/home': (_) => const Scaffold(body: Text('HOME PAGE'))},
            home: const Scaffold(body: Text('START'))),
      ));
      nav.currentState!.pushNamed(InvoicePage.route, arguments: _ride());
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await tester.tap(find.text('Done'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('HOME PAGE'), findsOneWidget);
      expect(find.byType(InvoicePage, skipOffstage: false), findsNothing);
      expect(nav.currentState!.canPop(), isFalse, reason: 'home is the only route left');
      await _teardown(tester);
    }, () => MockClient((req) async => _json({})));
  });


  // ── N. The "New Ride Request" heads-up comes down once the request is dealt with
  group('N the incoming-ride notification is cancelled', () {
    Future<List<MethodCall>> run(WidgetTester tester, String path, Future<void> Function() act) async {
      _setSize(tester);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'), (c) async {
        calls.add(c);
        return null;
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, IncomingRequestsPage.route),
            child: const Text('HOME'),
          )),
        ))));
        await tester.tap(find.text('HOME'));
        await _pumpFor(tester, const Duration(milliseconds: 500));
        expect(calls.where((c) => c.method == 'cancel'), isEmpty, reason: 'nothing cancelled before the driver acts');
        await act();
        await _teardown(tester);
      }, () => MockClient((req) async {
        if (req.url.path.endsWith('/accept')) return _json({'success': true, 'ride': _request('r1', 'taxi')});
        if (req.url.path.endsWith('/rides/driver/pending')) {
          return _json({'rides': [{..._request('r1', 'taxi'), 'offeredToMe': true,
            'offerExpiresAt': DateTime.now().add(const Duration(seconds: 3)).toUtc().toIso8601String()}]});
        }
        return _json({'success': true});
      }));
      return calls.where((c) => c.method == 'cancel').toList();
    }

    bool cancels1001(List<MethodCall> c) =>
        c.any((m) => (m.arguments is Map ? (m.arguments as Map)['id'] : m.arguments) == 1001);

    testWidgets('on accept', (tester) async {
      final c = await run(tester, 'accept', () async {
        await _slide(tester, 1.0);
        await _pumpFor(tester, const Duration(milliseconds: 500));
      });
      expect(cancels1001(c), isTrue);
    });

    testWidgets('on decline', (tester) async {
      final c = await run(tester, 'decline', () async {
        await tester.tap(find.byTooltip('Decline'));
        await _pumpFor(tester, const Duration(milliseconds: 500));
      });
      expect(cancels1001(c), isTrue);
    });

    testWidgets('on timeout', (tester) async {
      final c = await run(tester, 'timeout', () async {
        await _pumpFor(tester, const Duration(seconds: 5));
      });
      expect(cancels1001(c), isTrue);
    });
  });


  // ── W. Parcel weight is optional (riders no longer pick one) ────────────────
  group('W parcel weight shows only when there is one', () {
    Future<void> card(WidgetTester tester, num weight) async {
      _setSize(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const IncomingRequestsPage()));
        await _pumpFor(tester, const Duration(milliseconds: 500));
      }, () => MockClient((req) async => req.url.path.endsWith('/rides/driver/pending')
          ? _json({'rides': [{..._request('p1', 'delivery'), 'itemType': 'Documents', 'weightKg': weight, 'packageSize': 'S'}]})
          : _json({})));
    }

    testWidgets('request card, weight 0: no "0 kg"', (tester) async {
      await card(tester, 0);
      expect(find.text('Documents · Size S'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('request card, weight 1: still shown', (tester) async {
      await card(tester, 1);
      expect(find.text('Documents · 1 kg · Size S'), findsOneWidget);
      await _teardown(tester);
    });

    Future<void> delivery(WidgetTester tester, double weight) async {
      _setSize(tester, const Size(360, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(DeliveryProgressPage(ride: RideRequestModel(
          id: 'ride-1', userName: 'Rahul', userPhone: '', userRating: '4.9', pickupAddress: 'A', dropAddress: 'B',
          distance: '5 km', fare: '₹ 90', eta: '5 min', rideType: 'Bike', pickupLat: 23.02, pickupLng: 72.56,
          dropLat: 23.01, dropLng: 72.51, service: 'delivery', status: 'ongoing', itemType: 'Documents', weightKg: weight,
        ))));
        await _pumpFor(tester, const Duration(milliseconds: 300));
      }, () => MockClient((req) async => _json({})));
    }

    testWidgets('delivery page, weight 0: no Weight row', (tester) async {
      await delivery(tester, 0);
      expect(find.text('Weight'), findsNothing);
      expect(find.textContaining(' kg'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('delivery page, weight 0.5: shown as 0.5 kg', (tester) async {
      await delivery(tester, 0.5);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('0.5 kg'), findsOneWidget);
      await _teardown(tester);
    });
  });


  // ── G. Vehicle type page: a 2-column grid of image + name ───────────────────
  testWidgets('G vehicle types show as a 2-column grid, image + name only', (tester) async {
    _setSize(tester, const Size(360, 1400));
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const VehicleSelectionPage()));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      for (final n in ['Bike', 'Auto', 'Cab', 'Prime Sedan', 'Prime SUV', 'Mini Truck']) {
        expect(find.text(n), findsOneWidget);
      }
      // Two per row: Bike/Auto share a row, Cab starts the next.
      expect(tester.getCenter(find.text('Bike')).dy, tester.getCenter(find.text('Auto')).dy);
      expect(tester.getCenter(find.text('Cab')).dy, greaterThan(tester.getCenter(find.text('Bike')).dy));
      expect(tester.getCenter(find.text('Bike')).dx, lessThan(tester.getCenter(find.text('Auto')).dx));
      // Nothing but the name: no seats line, no service chips.
      expect(find.textContaining('seat'), findsNothing);
      expect(find.text('Taxi'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(find.text('Prime SUV'));
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: 'selected tile shows the check badge');
      await _teardown(tester);
    }, () => MockClient((req) async => req.url.path.endsWith('/vehicles/types')
        ? _json({'types': [
            for (final n in ['Bike', 'Auto', 'Cab', 'Prime Sedan', 'Prime SUV', 'Mini Truck'])
              {'_id': n, 'name': n, 'capacity': 4, 'services': ['taxi', 'parcel'], 'isActive': true},
          ]})
        : _json({})));
  });

  // ── B. Slide to accept ──────────────────────────────────────────────────────
  group('slide to accept', () {
    Future<List<http.Request>> open(WidgetTester tester, Future<void> Function() body) async {
      _setSize(tester);
      final calls = <http.Request>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, IncomingRequestsPage.route),
            child: const Text('HOME'),
          )),
        ))));
        await tester.tap(find.text('HOME'));
        await _pumpFor(tester, const Duration(milliseconds: 500));
        await body();
        await _teardown(tester);
      }, () => MockClient((req) async {
        calls.add(req);
        if (req.url.path.endsWith('/accept')) return _json({'success': true, 'ride': _request('r1', 'taxi')});
        if (req.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [_request('r1', 'taxi')]});
        return _json({'success': true});
      }));
      return calls;
    }

    testWidgets('a partial drag does NOT accept, and snaps back', (tester) async {
      final calls = await open(tester, () async {
        await _slide(tester, 0.5);
        await _pumpFor(tester, const Duration(milliseconds: 600));
        expect(find.byType(IncomingRequestsPage), findsOneWidget);
      });
      expect(calls.where((r) => r.url.path.endsWith('/accept')), isEmpty);
      expect(calls.where((r) => r.url.path.endsWith('/reject')), isEmpty);
    });

    testWidgets('a full drag accepts exactly once', (tester) async {
      final calls = await open(tester, () async {
        await _slide(tester, 1.0);
        await _pumpFor(tester, const Duration(seconds: 1));
        expect(find.byType(OnRidePage), findsOneWidget);
      });
      expect(calls.where((r) => r.url.path.endsWith('/accept')), hasLength(1));
    });

    testWidgets('a second slide while the accept is in flight does not accept again', (tester) async {
      _setSize(tester);
      var accepts = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const IncomingRequestsPage()));
        await _pumpFor(tester, const Duration(milliseconds: 500));
        await _slide(tester, 1.0);
        // Let the knob travel back, so the second slide really grabs it.
        await _pumpFor(tester, const Duration(milliseconds: 600));
        expect(accepts, 1);
        await _slide(tester, 1.0);
        await _pumpFor(tester, const Duration(seconds: 3));
        await _teardown(tester);
      }, () => MockClient((req) async {
        if (req.url.path.endsWith('/accept')) {
          accepts++;
          await Future<void>.delayed(const Duration(seconds: 2));
          return _json({'success': true, 'ride': _request('r1', 'taxi')});
        }
        if (req.url.path.endsWith('/rides/driver/pending')) return _json({'rides': [_request('r1', 'taxi')]});
        return _json({});
      }));
      expect(accepts, 1);
    });

    testWidgets('the card has no tap-to-accept button', (tester) async {
      await open(tester, () async {
        expect(find.text('Accept'), findsNothing);
        expect(find.text('Slide to accept'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsWidgets, reason: 'decline stays a tap');
      });
    });
  });

  // ── 7. Rental / hire request: no drop row ──────────────────────────────────
  testWidgets('#7 a request with no drop shows no DROP row', (tester) async {
    _setSize(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const IncomingRequestsPage()));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('PICKUP'), findsOneWidget);
      expect(find.text('DROP'), findsNothing);
      await _teardown(tester);
    }, () => MockClient((req) async => req.url.path.endsWith('/rides/driver/pending')
        ? _json({'rides': [_request('h1', 'hire_driver', drop: '')]}) : _json({})));
  });

  // ── 3 / 4. Banners and the Navigate button follow the phase ─────────────────
  group('#3 #4 navigation follows the phase', () {
    Future<NavMapPanel> openJob(WidgetTester tester, Widget page, {Handler? api}) async {
      _setSize(tester);
      late NavMapPanel map;
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(page));
        await _pumpFor(tester, const Duration(milliseconds: 400));
        map = tester.widget<NavMapPanel>(find.byType(NavMapPanel));
      }, () => MockClient(api ?? (req) async => _json({})));
      return map;
    }

    testWidgets('a parcel reopened after delivery: no route back to the sender', (tester) async {
      final map = await openJob(tester, DeliveryProgressPage(ride: _ride(service: 'delivery',
          progress: const RideProgress(deliveryPhase: 'delivered'))));
      expect(find.text('PARCEL · FINISHING'), findsOneWidget);
      expect(map.leg.isValid, isFalse);
      expect(map.onArrived, isNull);
      expect(find.textContaining('Navigate to'), findsNothing);
      expect(find.byTooltip('Call receiver'), findsOneWidget, reason: 'delivered implies collected');
      expect(find.byTooltip('Call sender'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('control: a parcel on its way still navigates to the receiver', (tester) async {
      final map = await openJob(tester, DeliveryProgressPage(ride: _ride(service: 'delivery',
          progress: const RideProgress(deliveryPhase: 'in_transit'))));
      expect(map.leg.isValid, isTrue);
      expect(map.leg.label, 'Receiver');
      expect(find.text('Navigate to Receiver'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a rental under way with no stop: no "Pickup" banner or button', (tester) async {
      final map = await openJob(tester, RentalProgressPage(ride: _ride(service: 'rental',
          progress: const RideProgress(rentalElapsedSec: 600))));
      expect(map.leg.isValid, isFalse);
      expect(map.onArrived, isNull);
      expect(find.text('Navigate to Pickup'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('control: a rental with a stop navigates to it', (tester) async {
      final map = await openJob(tester, RentalProgressPage(ride: _ride(service: 'rental',
          progress: const RideProgress(rentalElapsedSec: 600, rentalStops: [
            {'address': 'Iscon Mall', 'lat': 23.024, 'lng': 72.507},
          ]))));
      expect(map.leg.isValid, isTrue);
      expect(find.text('Navigate to Stop 1'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('hire on duty: no "Navigate to Customer"', (tester) async {
      final map = await openJob(tester, HireProgressPage(ride: _ride(service: 'hire_driver',
          progress: const RideProgress(hireElapsedSec: 600))));
      expect(map.leg.isValid, isFalse);
      expect(find.textContaining('Navigate to'), findsNothing);
      await _teardown(tester);
    });

    // The proof photo needs a real camera file, so the priced→collect
    // transition is driven from the other pricing call that ends a parcel job:
    // return-to-sender. Both set the priced answer and run the same
    // _collectAndSettle step that opens the cash screen.
    testWidgets('#3 a priced parcel moves on to collecting the fare', (tester) async {
      _setSize(tester);
      final actions = <String>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(DeliveryProgressPage(ride: _ride(service: 'delivery',
            progress: const RideProgress(deliveryPhase: 'in_transit')))));
        await _pumpFor(tester, const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('Receiver unavailable — return to sender'));
        await tester.tap(find.text('Receiver unavailable — return to sender'));
        await _pumpFor(tester, const Duration(milliseconds: 400));
        await tester.tap(find.text('Receiver unavailable'));
        await _pumpFor(tester, const Duration(milliseconds: 800));
        expect(find.byType(CollectFarePage), findsOneWidget, reason: 'the cash step follows pricing');
        expect(find.text('₹150'), findsOneWidget);
        await _teardown(tester);
      }, () => MockClient((req) async {
        if (req.url.path.endsWith('/delivery')) {
          actions.add((jsonDecode(req.body) as Map)['action'].toString());
          return _json({'success': true, 'fareDue': 150, 'codDue': 0, 'amountDue': 150});
        }
        return _json({});
      }));
      expect(actions, ['failed']);
    });
  });

  // ── 5. Resubmission: chosen state lost, phone missing ───────────────────────
  testWidgets('#5 resubmitting keeps the chosen state and shows the phone', (tester) async {
    _setSize(tester, const Size(360, 1600));
    Map<String, dynamic>? sent;
    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DriverProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          routes: {...AppRoutes.routes},
          onGenerateRoute: (s) => MaterialPageRoute(
            settings: RouteSettings(name: s.name, arguments: const {
              'driver': {'name': 'Suresh Kumar', 'phone': '9876543210', 'zoneId': 'z1', 'zoneName': 'Rajkot'},
            }),
            builder: (_) => s.name == '/' ? const PersonalDetailsPage() : const Scaffold(body: Text('NEXT')),
          ),
        ),
      ));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text('+91 9876543210'), findsOneWidget);
      // Pick a state from the dropdown. Closing its menu re-runs
      // didChangeDependencies, which used to wipe the choice.
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await tester.tap(find.text('Gujarat').last);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Please select a state'), findsNothing);
      expect(sent?['state'], 'Gujarat');
      await _teardown(tester);
    }, () => MockClient((req) async {
      if (req.url.path.endsWith('/zones')) return _json({'zones': [{'_id': 'z1', 'name': 'Rajkot'}]});
      if (req.url.path.endsWith('/register/personal')) {
        sent = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        return _json({'success': true});
      }
      return _json({});
    }));
  });

  // ── 8. Minutes over an hour ────────────────────────────────────────────────
  test('#8 minutes read as hours past 60', () {
    expect(formatMinutes(42), '42 min');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(246), '4 h 6 min');
  });

  // ── 9. Trip detail never shows the fare as earnings ─────────────────────────
  testWidgets('#9 trip detail: "You earned" is the driver earning, the fare is labelled fare', (tester) async {
    _setSize(tester);
    await tester.pumpWidget(_app(const TripDetailPage(trip: TripModel(
      id: 't1', userName: 'Rahul', pickupAddress: 'A', dropAddress: 'B', distance: '5 km', fare: '₹ 90',
      date: '27 Oct', status: 'completed', paymentMode: 'cash', duration: '12 min', rating: 5,
      driverEarning: 72, commission: 18,
    ))));
    expect(find.text('₹72'), findsOneWidget);
    expect(find.text('You earned'), findsOneWidget);
    expect(find.text('Fare'), findsOneWidget);
    expect(find.text('₹ 90'), findsOneWidget);
    expect(find.textContaining('earned', findRichText: true), findsOneWidget);
    expect(find.text('Total earned'), findsNothing);
  });

  testWidgets('#9 control: no recorded earning → only the fare, never called earnings', (tester) async {
    _setSize(tester);
    await tester.pumpWidget(_app(const TripDetailPage(trip: TripModel(
      id: 't1', userName: 'Rahul', pickupAddress: 'A', dropAddress: 'B', distance: '5 km', fare: '₹ 90',
      date: '27 Oct', status: 'completed', paymentMode: 'cash', duration: '12 min', rating: 5,
    ))));
    expect(find.textContaining('earned'), findsNothing);
    expect(find.text('Fare'), findsOneWidget);
  });

  // ── 10. Month list stops at the current month ──────────────────────────────
  test('#10 the month list has no future months', () async {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    final state = await http.runWithClient(() async {
      final bloc = EarningsBloc();
      final next = bloc.stream.firstWhere((s) => s is EarningsLoaded);
      bloc.add(LoadEarningsEvent());
      final s = await next as EarningsLoaded;
      await bloc.close();
      return s;
    }, () => MockClient((req) async => _json({'rides': []})));
    expect(state.monthly, hasLength(DateTime.now().month));
    expect(state.monthly.last.isCurrent, isTrue);
  });

  // ── 11. Tab title padding ──────────────────────────────────────────────────
  testWidgets('#11 a tab title without a back button is not flush to the edge', (tester) async {
    _setSize(tester);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
        home: Scaffold(appBar: blueAppBar('Earnings'), body: const SizedBox())));
    expect(tester.getTopLeft(find.text('Earnings')).dx, greaterThanOrEqualTo(16));
  });

  // ── 12. Rate card uses each vehicle's own image / icon ──────────────────────
  testWidgets('#12 rate card: Bike and Auto are not the same car', (tester) async {
    _setSize(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const RateCardPage()));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.two_wheeler), findsOneWidget);
      expect(find.byIcon(Icons.electric_rickshaw), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage &&
          (w.image as NetworkImage).url.endsWith('/uploads/cab.png')), findsOneWidget);
      await _teardown(tester);
    }, () => MockClient((req) async {
      if (req.url.path.endsWith('/ratecard')) {
        return _json({'zone': 'Rajkot', 'cards': [
          {'vehicleType': 'Bike', 'baseFare': 20}, {'vehicleType': 'Auto', 'baseFare': 30}, {'vehicleType': 'Cab', 'baseFare': 50},
        ]});
      }
      if (req.url.path.endsWith('/vehicles/types')) {
        return _json({'types': [{'name': 'Cab', 'imageUrl': '/uploads/cab.png'}, {'name': 'Bike'}, {'name': 'Auto'}]});
      }
      return _json({});
    }));
  });
}
