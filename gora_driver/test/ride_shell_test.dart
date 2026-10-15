import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/ride/logic/job_settlement.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/pages/hire_progress_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/ride/pages/on_ride_page.dart';
import 'package:gora_driver/features/ride/pages/rental_progress_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/ride_shell.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// #6 — every on-ride screen in the shared RideShell.
//
// Each screen is driven through the states a driver actually meets, including
// the ones only reached by reopening the app mid-job, with a mock API so every
// request the screen makes can be checked.
// ─────────────────────────────────────────────────────────────────────────────

const kSmall = Size(320, 568);
const kCommon = Size(360, 640);

const _stops = [
  {'address': 'Gate 2, Ahmedabad Management Association, Vastrapur', 'lat': 23.035, 'lng': 72.529},
  {'address': 'Iscon Mega Mall parking, Sarkhej–Gandhinagar Highway', 'lat': 23.024, 'lng': 72.507},
  {'address': 'Terminal 2 Departures, Sardar Vallabhbhai Patel International Airport', 'lat': 23.077, 'lng': 72.634},
];

RideRequestModel ride({
  String id = 'ride-1',
  String service = 'taxi',
  String status = 'accepted',
  String paymentMode = 'cash',
  String tripType = 'one_way',
  List<Map<String, dynamic>> stops = const [],
  int? waitingSec,
  RideProgress progress = const RideProgress(),
  double cod = 0,
}) => RideRequestModel(
  id: id,
  userName: 'Chandrashekhar Balasubramanian',
  userPhone: '+91 98765 43210',
  userRating: '4.9',
  pickupAddress: 'Shop 14, Ground Floor, Sardar Patel Complex, Near Municipal Market, Navrangpura, Ahmedabad',
  dropAddress: 'Block C, Tower 3, Flat 1802, Silver Oak Residency, Off S.G. Highway, Bodakdev, Ahmedabad',
  distance: '18.4 km',
  fare: '₹ 1,24,999',
  eta: '42 min',
  rideType: 'Cab Premium SUV 7 Seater',
  pickupLat: 23.0225, pickupLng: 72.5714,
  dropLat: 23.0732, dropLng: 72.6208,
  service: service,
  status: status,
  paymentMode: paymentMode,
  tripType: tripType,
  cityFrom: service == 'outstation' ? 'Ahmedabad, Gujarat' : '',
  cityTo: service == 'outstation' ? 'Mount Abu Hill Station, Sirohi, Rajasthan' : '',
  stops: stops,
  waitingSec: waitingSec,
  packageHours: 4, packageKm: 40,
  hireTotalHours: 8, transmission: 'automatic',
  senderName: 'Venkataraman Subramanian Iyer', senderPhone: '+91 90000 11111',
  receiverName: 'Lakshminarayanan Venkatasubramanian', receiverPhone: '+91 90000 22222',
  itemType: 'Refrigerated pharmaceutical consignment',
  isFragile: true,
  codAmount: cod,
  distanceKm: 18.4, durationMin: 42, totalFareValue: 124999, baseFare: 124999,
  progress: progress,
);

class ApiCall {
  final String method;
  final Uri url;
  final Map<String, dynamic> body;
  ApiCall(this.method, this.url, this.body);
}

MockClient? _api;
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => _api!);

MockClient mockApi(List<ApiCall> log, Future<http.Response?> Function(http.Request)? override) =>
    MockClient((req) async {
      Map<String, dynamic> body = const {};
      try { if (req.body.isNotEmpty) body = Map<String, dynamic>.from(jsonDecode(req.body) as Map); } catch (_) {}
      log.add(ApiCall(req.method, req.url, body));
      final custom = await override?.call(req);
      return custom ?? http.Response('{"success":true}', 200);
    });

/// Opens [page] (or the on-ride route with [ride]) the way the app does: on top
/// of a stand-in home, with the real routes the screens navigate to.
Future<List<String>> openScreen(
  WidgetTester tester, {
  Widget? page,
  RideRequestModel? onRide,
  bool noArgs = false,
  Size size = kCommon,
  List<ApiCall>? log,
  Future<http.Response?> Function(http.Request)? override,
  bool scroll = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    final t = d.exceptionAsString();
    if (t.contains('overflowed') || t.contains('RenderFlex')) {
      // The creator chain names the widget that overflowed — far more useful
      // than the pixel count alone.
      final creator = d.toString().split('\n')
          .where((l) => l.contains('creator:')).take(1).join(' ');
      overflows.add('${t.split('\n').first} $creator');
      return;
    }
    previous?.call(d);
  };
  _api = mockApi(log ?? [], override);
  try {
    await act(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DriverProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: BlocProvider(
          create: (_) => AuthBloc(),
          child: MaterialApp(
            theme: AppTheme.light,
            routes: {
              OnRidePage.route: (_) => const OnRidePage(),
              // Shows the toll the invoice was given, so tests can check it.
              InvoicePage.route: (ctx) {
                final a = ModalRoute.of(ctx)?.settings.arguments;
                return Scaffold(body: Text(a is RideCompletionArgs && a.tollCollected > 0
                    ? 'INVOICE toll ₹${a.tollCollected}' : 'INVOICE'));
              },
              '/home': (_) => const Scaffold(body: Text('HOME')),
            },
            home: Builder(builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (page != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
                } else {
                  Navigator.pushNamed(context, OnRidePage.route, arguments: noArgs ? null : onRide);
                }
              });
              return const Scaffold(body: Text('HOME'));
            }),
          ),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      if (scroll) await scrollSheet(tester);
    });
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

/// Scrolls the sheet's detail area to its end, so an overflow or a widget below
/// the fold cannot hide from an assertion.
/// Opens the trip details, folded while driving so the map leads — as a driver
/// does, with the sheet's handle. Does nothing when they are already open.
Future<void> showDetails(WidgetTester tester) async {
  final handle = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Show trip details');
  if (handle.evaluate().isEmpty) return;
  await tester.tap(handle.first);
  await tester.pump();
}

Future<void> scrollSheet(WidgetTester tester) async {
  await showDetails(tester);
  final area = find.descendant(of: find.byType(RideShell), matching: find.byType(SingleChildScrollView));
  if (area.evaluate().isEmpty) return;
  for (var i = 0; i < 3; i++) {
    await tester.drag(area.first, const Offset(0, -400), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Swipes a SwipeToConfirm all the way, slowly, so it commits.
Future<void> swipe(WidgetTester tester, String label) async {
  final track = find.byWidgetPredicate((w) => w is SwipeToConfirm && w.label == label);
  expect(track, findsOneWidget, reason: 'No swipe labelled "$label"');
  final rect = tester.getRect(track);
  final gesture = await tester.startGesture(Offset(rect.left + 29, rect.center.dy));
  for (var i = 0; i < 12; i++) {
    await gesture.moveBy(Offset(rect.width / 12, 0));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
  while (tester.takeException() != null) {}
}

Iterable<ApiCall> posts(List<ApiCall> log, String suffix) =>
    log.where((c) => c.method == 'POST' && c.url.path.endsWith(suffix));

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    // Location off. Unanswered, the geolocator channel never replies inside a
    // widget test, so a screen that looks up the position before calling the
    // server — as rental 'start' does — would never make the call at all.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  // ── Every state, both sizes, sheet scrolled: nothing overflows ──
  final states = <String, ({Widget? page, RideRequestModel? onRide})>{
    'taxi to pickup': (page: null, onRide: ride()),
    'taxi waiting at pickup': (page: null, onRide: ride(status: 'arrived', waitingSec: 95)),
    'multi-stop waiting at stop 2': (page: null, onRide: ride(status: 'ongoing', stops: _stops,
        progress: const RideProgress(currentStopIndex: 1, waitingAtStop: true))),
    'round trip at destination': (page: null, onRide: ride(service: 'outstation', tripType: 'round_trip',
        status: 'ongoing', progress: const RideProgress(outstationPhase: 'at_destination'))),
    'rental resumed with stops': (page: RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing',
        progress: const RideProgress(rentalElapsedSec: 5400, actualKm: 62.4, rentalPhase: 'extra_time',
            rentalStops: _stops))), onRide: null),
    'rental priced earlier': (page: RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing',
        progress: const RideProgress(rentalElapsedSec: 5400, rentalPhase: 'completed'))), onRide: null),
    'hire in overtime': (page: HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing',
        progress: const RideProgress(hireElapsedSec: 32400, hirePhase: 'overtime'))), onRide: null),
    'parcel in transit with COD': (page: DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing',
        cod: 15000, progress: const RideProgress(deliveryPhase: 'in_transit'))), onRide: null),
    'parcel delivered, unsettled': (page: DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing',
        progress: const RideProgress(deliveryPhase: 'delivered'))), onRide: null),
  };

  for (final size in const [kSmall, kCommon]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    group('no overflow $tag', () {
      states.forEach((name, s) {
        testWidgets(name, (tester) async {
          final overflows = await openScreen(tester, page: s.page, onRide: s.onRide, size: size, scroll: true);
          expect(find.byType(RideShell), findsOneWidget);
          expect(overflows, isEmpty, reason: '$name overflowed at $tag: $overflows');
          await teardown(tester);
        });
      });
    });
  }

  // ── One layout: SOS, call and chat on every service ──
  group('every service can reach help and the customer', () {
    final cases = <String, (Widget? page, RideRequestModel? onRide, String callTooltip)>{
      'taxi': (null, ride(), 'Call rider'),
      'rental': (RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing',
          progress: const RideProgress(rentalElapsedSec: 60))), null, 'Call rider'),
      'hire': (HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing',
          progress: const RideProgress(hireElapsedSec: 60))), null, 'Call customer'),
      'parcel before pickup': (DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing')), null, 'Call sender'),
      'parcel on its way': (DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing',
          progress: const RideProgress(deliveryPhase: 'in_transit'))), null, 'Call receiver'),
    };
    cases.forEach((name, c) {
      testWidgets(name, (tester) async {
        final semantics = tester.ensureSemantics();
        await openScreen(tester, page: c.$1, onRide: c.$2);
        expect(find.bySemanticsLabel('Emergency SOS'), findsOneWidget);
        expect(find.byTooltip(c.$3), findsOneWidget);
        expect(find.byTooltip('Message rider'), findsOneWidget);
        semantics.dispose();
        await teardown(tester);
      });
    });
  });

  // ── Resume: carry on, never start over ──
  group('a reopened job carries on', () {
    testWidgets('a started rental is not started again, and its clock is the server\'s', (tester) async {
      final log = <ApiCall>[];
      await openScreen(tester, log: log, page: RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing',
          progress: const RideProgress(rentalElapsedSec: 5400, actualKm: 12.5))));
      expect(posts(log, '/rental').where((c) => c.body['action'] == 'start'), isEmpty);
      expect(find.text('1h 30m / 4h'), findsOneWidget);
      expect(find.text('12.5 / 40 km'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('control: a rental not yet started is started once', (tester) async {
      final log = <ApiCall>[];
      await openScreen(tester, log: log, page: RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing')));
      expect(posts(log, '/rental').where((c) => c.body['action'] == 'start'), hasLength(1));
      await teardown(tester);
    });

    testWidgets('a started hire is not started again — that reset its hours worked', (tester) async {
      final log = <ApiCall>[];
      await openScreen(tester, log: log, page: HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing',
          progress: const RideProgress(hireElapsedSec: 32400))));
      expect(posts(log, '/hire').where((c) => c.body['action'] == 'start'), isEmpty);
      expect(find.text('9h 00m / 8h'), findsOneWidget);
      expect(find.text('HIRE · OVERTIME'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('control: a hire not yet started is started once', (tester) async {
      final log = <ApiCall>[];
      await openScreen(tester, log: log, page: HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing')));
      expect(posts(log, '/hire').where((c) => c.body['action'] == 'start'), hasLength(1));
      await teardown(tester);
    });

    testWidgets('a parcel already on its way is not collected again', (tester) async {
      await openScreen(tester, page: DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing',
          progress: const RideProgress(deliveryPhase: 'in_transit'))));
      expect(find.text('Swipe once parcel is collected'), findsNothing);
      expect(find.text('Delivered — enter receiver OTP'), findsOneWidget);
      final map = tester.widget<NavMapPanel>(find.byType(NavMapPanel));
      expect(map.leg.label, 'Receiver');
      await teardown(tester);
    });

    testWidgets('a round trip at its destination is not asked to arrive again', (tester) async {
      await openScreen(tester, onRide: ride(service: 'outstation', tripType: 'round_trip', status: 'ongoing',
          progress: const RideProgress(outstationPhase: 'at_destination')));
      expect(find.text('Swipe at your destination'), findsNothing);
      expect(find.text('Swipe to start the return'), findsOneWidget);
      expect(find.text('AT DESTINATION'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('the return leg navigates back to the start, not to the destination', (tester) async {
      await openScreen(tester, onRide: ride(service: 'outstation', tripType: 'round_trip', status: 'ongoing',
          progress: const RideProgress(outstationPhase: 'returning')));
      expect(find.text('RETURN TRIP'), findsOneWidget);
      expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).leg.label, 'Start point');
      await teardown(tester);
    });

    testWidgets('a multi-stop ride resumes at its stop', (tester) async {
      await openScreen(tester, onRide: ride(status: 'ongoing', stops: _stops,
          progress: const RideProgress(currentStopIndex: 1, waitingAtStop: true)));
      expect(find.text('WAITING AT STOP 2'), findsOneWidget);
      expect(find.text('Continue to stop 3'), findsOneWidget);
      expect(tester.widget<NavMapPanel>(find.byType(NavMapPanel)).leg.label, 'Stop 2');
      await teardown(tester);
    });
  });

  // ── Per-ride state: nothing leaks into the next ride ──
  testWidgets('stop progress belongs to its ride, not to the next one', (tester) async {
    await openScreen(tester, onRide: ride(id: 'ride-A', status: 'ongoing', stops: _stops),
        override: (req) async => req.url.path.endsWith('/stop')
            ? http.Response(jsonEncode({'success': true, 'currentStopIndex': 2, 'isWaitingAtStop': false}), 200)
            : null);
    // Ride A advances to stop 3 on the server's word.
    await act(() async {
      await swipe(tester, 'Swipe at stop 1');
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('TO STOP 3'), findsOneWidget);
    await teardown(tester);

    // The next ride with stops starts at its own beginning.
    await openScreen(tester, onRide: ride(id: 'ride-B', status: 'ongoing', stops: _stops));
    expect(find.text('TO STOP 1'), findsOneWidget);
    await teardown(tester);
  });

  // ── Actions take the server's answer ──
  group('a refused action is not shown as done', () {
    testWidgets('reaching a stop', (tester) async {
      await openScreen(tester, onRide: ride(status: 'ongoing', stops: _stops),
          override: (req) async => req.url.path.endsWith('/stop')
              ? http.Response(jsonEncode({'error': 'Invalid stop index'}), 400) : null);
      await act(() => swipe(tester, 'Swipe at stop 1'));
      expect(find.text('Could not update the stop: Invalid stop index'), findsOneWidget);
      expect(find.text('TO STOP 1'), findsOneWidget);
      await teardown(tester);
    });

    // The case where ignoring the server would visibly move on: a refused
    // "continue" must not skip the driver to the next stop.
    testWidgets('continuing from a stop', (tester) async {
      await openScreen(tester, onRide: ride(status: 'ongoing', stops: _stops,
          progress: const RideProgress(waitingAtStop: true)),
          override: (req) async => req.url.path.endsWith('/stop')
              ? http.Response(jsonEncode({'error': 'Ride not found'}), 404) : null);
      expect(find.text('WAITING AT STOP 1'), findsOneWidget);
      await act(() async {
        await tester.tap(find.text('Continue to stop 2'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });
      expect(find.text('Could not update the stop: Ride not found'), findsOneWidget);
      expect(find.text('WAITING AT STOP 1'), findsOneWidget);
      expect(find.text('TO STOP 2'), findsNothing);
      await teardown(tester);
    });

    testWidgets('arriving at the destination on a round trip', (tester) async {
      await openScreen(tester, onRide: ride(service: 'outstation', tripType: 'round_trip', status: 'ongoing'),
          override: (req) async => req.url.path.endsWith('/phase')
              ? http.Response(jsonEncode({'error': 'Ride not found'}), 404) : null);
      await act(() => swipe(tester, 'Swipe at your destination'));
      expect(find.text('Could not update the trip: Ride not found'), findsOneWidget);
      expect(find.text('Swipe at your destination'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('collecting a parcel', (tester) async {
      await openScreen(tester, page: DeliveryProgressPage(ride: ride(service: 'delivery', status: 'ongoing')),
          override: (req) async => req.url.path.endsWith('/delivery')
              ? http.Response(jsonEncode({'error': 'Ride cancelled'}), 409) : null);
      await act(() => swipe(tester, 'Swipe once parcel is collected'));
      expect(find.text('Could not mark collected: Ride cancelled'), findsOneWidget);
      expect(find.text('Swipe once parcel is collected'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('extending a hire', (tester) async {
      await openScreen(tester, page: HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing',
          progress: const RideProgress(hireElapsedSec: 60))),
          override: (req) async => req.url.path.endsWith('/hire') && req.body.contains('extend')
              ? http.Response(jsonEncode({'error': 'Hire already completed'}), 409) : null);
      await act(() async {
        await tester.tap(find.text('Extend hours'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('+2 hours'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });
      expect(find.text('Could not extend: Hire already completed'), findsOneWidget);
      expect(find.text('0h 01m / 8h'), findsOneWidget, reason: 'Booked hours must not change');
      await teardown(tester);
    });
  });

  testWidgets('a screen opened without a ride shows no fake one', (tester) async {
    await openScreen(tester, noArgs: true);
    expect(find.text('No active ride'), findsOneWidget);
    expect(find.byType(RideShell), findsNothing);
    await teardown(tester);
  });

  // ── Settlement ──
  group('cashDueFor', () {
    test('rental cash: the final fare', () =>
        expect(cashDueFor({'service': 'rental', 'paymentMode': 'cash', 'finalFare': 1479, 'totalFare': 1479}), 1479));
    test('rental online: nothing in hand', () =>
        expect(cashDueFor({'service': 'rental', 'paymentMode': 'online', 'finalFare': 1479}), 0));
    test('hire cash: the total', () =>
        expect(cashDueFor({'service': 'hire_driver', 'paymentMode': 'cash', 'totalFare': 900}), 900));
    test('parcel delivered, cash: fare plus COD', () => expect(cashDueFor({'service': 'delivery',
        'paymentMode': 'cash', 'totalFare': 120, 'deliveryPhase': 'delivered', 'codCollected': 1500}), 1620));
    test('parcel delivered, online: COD only', () => expect(cashDueFor({'service': 'delivery',
        'paymentMode': 'online', 'totalFare': 120, 'deliveryPhase': 'delivered', 'codCollected': 1500}), 1500));
    test('parcel returned: no COD', () => expect(cashDueFor({'service': 'delivery',
        'paymentMode': 'cash', 'totalFare': 120, 'deliveryPhase': 'returned', 'codCollected': 1500}), 120));
  });

  Future<void> collectFare(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Collect Fare'), 300,
        scrollable: find.descendant(of: find.byType(CollectFarePage), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Collect Fare'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a rental priced before reopening collects the billed amount and settles', (tester) async {
    final log = <ApiCall>[];
    await openScreen(tester, log: log, page: RentalProgressPage(ride: ride(service: 'rental', status: 'ongoing',
        progress: const RideProgress(rentalElapsedSec: 5400, rentalPhase: 'completed'))),
        override: (req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/rides/ride-1')) {
            return http.Response(jsonEncode({'status': 'ongoing', 'service': 'rental', 'paymentMode': 'cash',
              'finalFare': 1479, 'totalFare': 1479}), 200);
          }
          return null;
        });
    // It used to press End again, which the server refuses for a priced rental.
    expect(find.text('Swipe to end rental'), findsNothing);
    await act(() async {
      await swipe(tester, 'Swipe to finish the rental');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('₹1479.0'), findsOneWidget);
      await collectFare(tester);
    });
    expect(posts(log, '/rental').where((c) => c.body['action'] == 'end'), isEmpty);
    expect(posts(log, '/complete'), hasLength(1));
    expect(find.text('INVOICE'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('a failed settlement is reported, and the retry does not collect the cash twice', (tester) async {
    final log = <ApiCall>[];
    var completes = 0;
    await openScreen(tester, log: log, page: HireProgressPage(ride: ride(service: 'hire_driver', status: 'ongoing',
        progress: const RideProgress(hireElapsedSec: 60))),
        override: (req) async {
          if (req.url.path.endsWith('/hire') && req.body.contains('"end"')) {
            return http.Response(jsonEncode({'success': true, 'amountDue': 900,
              'hire': {'finalFare': 900, 'extraCharge': 300, 'extraHours': 2, 'totalHours': 8, 'actualHours': 10}}), 200);
          }
          if (req.url.path.endsWith('/complete')) {
            completes++;
            return completes == 1
                ? http.Response(jsonEncode({'error': 'Server error'}), 500)
                : http.Response(jsonEncode({'success': true}), 200);
          }
          return null;
        });

    await act(() async {
      await swipe(tester, 'Swipe to end hire');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('₹900.0'), findsOneWidget);
      await collectFare(tester);
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('Could not finish the ride: Server error. Swipe again to retry.'), findsOneWidget);
    expect(find.byType(CollectFarePage), findsNothing);
    // The message asks for a swipe; it must not sit on top of that swipe.
    final snack = tester.getRect(find.byType(SnackBar));
    final action = tester.getRect(find.byWidgetPredicate((w) => w is SwipeToConfirm));
    expect(snack.overlaps(action), isFalse, reason: 'The snackbar covers the retry swipe');

    await act(() async {
      // Let the knob finish springing back from the first swipe.
      await tester.pump(const Duration(milliseconds: 800));
      await swipe(tester, 'Swipe to finish the hire');
      await tester.pump(const Duration(milliseconds: 500));
    });
    expect(find.byType(CollectFarePage), findsNothing, reason: 'The cash is already in hand');
    expect(completes, 2);
    expect(posts(log, '/hire').where((c) => c.body['action'] == 'end'), hasLength(1),
        reason: 'A retry must not re-price the job');
    expect(find.text('Hire Complete'), findsOneWidget);
    await teardown(tester);
  });
}
