import 'dart:async';
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
import 'package:customer_app/screens/active_ride_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/map_markers.dart';
import 'package:customer_app/widgets/driver_waiting_timer.dart';
import 'package:customer_app/widgets/ride_service_panels.dart';
import 'package:customer_app/widgets/rental_stops_panel.dart';
import 'package:customer_app/widgets/cancel_reasons_sheet.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The live ride screen, driven through every phase with realistic data.
//
// The generic overflow sweep cannot reach this screen: it renders nothing but a
// spinner until /rides/{id} answers. So these serve canned API responses and
// assert, per phase and per screen width, that
//   * nothing overflows, and
//   * the controls a rider depends on are actually present.
//
// Data is deliberately awkward — long Indian names and addresses — because
// tidy placeholder strings are exactly what hid the overflows fixed elsewhere.
// ─────────────────────────────────────────────────────────────────────────────

const kSmall = Size(320, 568);
const kCommon = Size(360, 640);

Map<String, dynamic> rideJson({
  required String status,
  required String uiPhase,
  String uiPhaseLabel = '',
  bool awaitingPayment = false,
  String service = 'taxi',
}) => {
  '_id': 'ride123',
  'status': status,
  'uiPhase': uiPhase,
  'uiPhaseLabel': uiPhaseLabel,
  'uiPhaseOverrun': false,
  'service': service,
  'vehicleType': 'Cab Premium SUV 7 Seater',
  'otp': '4821',
  'fare': 124999,
  'totalFare': 124999,
  'awaitingPayment': awaitingPayment,
  'paymentMode': 'cash',
  'pickupLat': 23.0225, 'pickupLng': 72.5714,
  'dropLat': 23.0732, 'dropLng': 72.6208,
  'pickupAddress': 'Shop 14, Ground Floor, Sardar Patel Complex, Near Municipal '
      'Market, Navrangpura, Ahmedabad, Gujarat 380009',
  'dropAddress': 'Block C, Tower 3, Flat 1802, Silver Oak Residency, Off S.G. '
      'Highway, Bodakdev, Ahmedabad, Gujarat 380054',
  'driverPhone': '+91 98765 43210',
  'driver': {
    'id': 'drv1',
    'name': 'Chandrashekhar Balasubramanian',
    'phone': '+91 98765 43210',
    'vehicleModel': 'Mahindra XUV700 AX7 Luxury',
    'vehicleNumber': 'GJ 01 AB 1234',
    'profilePicUrl': '',
    'vehicleTypeName': 'Cab Premium SUV 7 Seater',
  },
};

/// A rental past its package, booked without a destination — so, as the rental
/// screen sends it, the drop is the pickup and there is no drop address.
Map<String, dynamic> rentalOngoing() => rideJson(status: 'ongoing', uiPhase: 'ongoing',
    uiPhaseLabel: 'Extra time', service: 'rental')
  ..addAll({
    'uiPhaseOverrun': true,
    'fare': 1499, 'totalFare': 1499,
    'actualHours': 5.4, 'packageHours': 4,
    'actualKm': 62.3, 'packageKm': 40,
    'liveExtraCharge': 480,
    'dropLat': 23.0225, 'dropLng': 72.5714, 'dropAddress': '',
  });

Map<String, dynamic> hireOngoing() => rideJson(status: 'ongoing', uiPhase: 'ongoing',
    uiPhaseLabel: 'Overtime', service: 'hire_driver')
  ..addAll({
    'uiPhaseOverrun': true,
    'fare': 600, 'totalFare': 600,
    'hireActualHours': 9.5, 'hireTotalHours': 8, 'hirePerHour': 150,
    'liveExtraCharge': 300,
    'dropLat': 23.0225, 'dropLng': 72.5714, 'dropAddress': '',
  });

Map<String, dynamic> parcel({
  required String status,
  required String uiPhase,
  required String deliveryPhase,
}) => rideJson(status: status, uiPhase: uiPhase, service: 'delivery',
    uiPhaseLabel: const {
      'pending': 'Collecting parcel',
      'in_transit': 'Out for delivery',
      'returned': 'Returning to sender',
    }[deliveryPhase] ?? '')
  ..addAll({
    'deliveryPhase': deliveryPhase,
    'dropOtp': '7390',
    'fare': 120, 'totalFare': 120,
    if (deliveryPhase == 'returned')
      'failReason': 'Receiver not answering the phone and the gate was locked '
          'when the driver reached the address after three attempts',
  });

Map<String, dynamic> outstation({required String status, required String uiPhase}) =>
    rideJson(status: status, uiPhase: uiPhase, service: 'outstation',
        uiPhaseLabel: 'Driver on the way')
  ..addAll({
    'cityFrom': 'Ahmedabad, Gujarat',
    'cityTo': 'Mount Abu Hill Station, Sirohi District, Rajasthan',
    'tripType': 'round_trip',
    'fare': 5400, 'totalFare': 5400,
    'paymentMode': 'online',
  });

/// Two destinations already sent to the driver, with the kind of address a
/// place search really returns.
Map<String, dynamic> rentalWithStops() => rentalOngoing()
  ..['rentalStops'] = [
    {'address': 'Terminal 2 Departures, Sardar Vallabhbhai Patel International '
        'Airport, Hansol, Ahmedabad, Gujarat 382475', 'lat': 23.0772, 'lng': 72.6347},
    {'address': 'Gate 3, Gujarat University Convention Centre, Navrangpura', 'lat': 23.0364, 'lng': 72.5460},
  ];

Map<String, dynamic> scheduledRental(DateTime at) =>
    rideJson(status: 'pending', uiPhase: 'finding', uiPhaseLabel: 'Finding a driver', service: 'rental')
  ..addAll({'scheduledAt': at.toUtc().toIso8601String(), 'driver': null});

/// One request the screen made, for asserting what it asked the server for.
class ApiCall {
  final String method;
  final Uri url;
  final String body;
  ApiCall(this.method, this.url, this.body);
}

/// Routes each request the screen makes to a canned response.
///
/// [log] records every call. [rideDelay] holds each /rides/{id} answer back, to
/// make polls overlap the way they do on a slow network.
/// [override] answers a request first when it returns non-null — for a test that
/// needs one endpoint to fail, or to change the ride when an action is taken.
MockClient mockApi(
  Map<String, dynamic> ride, {
  List<ApiCall>? log,
  Duration rideDelay = Duration.zero,
  Future<http.Response?> Function(http.Request req)? override,
}) => MockClient((req) async {
  log?.add(ApiCall(req.method, req.url, req.body));
  final custom = await override?.call(req);
  if (custom != null) return custom;
  final path = req.url.path;
  if (path.endsWith('/wallet/pay')) {
    return http.Response(jsonEncode({'success': true, 'balance': 1000}), 200);
  }
  if (path.endsWith('/driver-location')) {
    // Mirrors the real route: a ride with no driver yet returns driver: null.
    // Returning a position here would draw a driver who cannot exist.
    final hasDriver = ride['status'] != 'pending';
    return http.Response(jsonEncode({
      'status': ride['status'],
      'driver': hasDriver ? {'lat': 23.0400, 'lng': 72.5900, 'heading': 45} : null,
    }), 200);
  }
  if (path.endsWith('/directions')) {
    // A short, valid encoded polyline, so the route and progress paths run.
    return http.Response(jsonEncode({
      'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      'durationMin': 14,
      'distanceKm': 6.2,
    }), 200);
  }
  if (path.contains('/rides/')) {
    if (rideDelay > Duration.zero) await Future<void>.delayed(rideDelay);
    return http.Response(jsonEncode(ride), 200);
  }
  return http.Response('{}', 200);
});

/// [pushed] opens the ride screen on top of a stand-in home screen, as the app
/// does, so a test can tell "closed the ride screen" from "closed everything".
Widget _app(String rideId, {bool pushed = false}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: pushed ? _Launcher(rideId) : ActiveRideScreen(rideId: rideId),
  ),
);

class _Launcher extends StatefulWidget {
  final String rideId;
  const _Launcher(this.rideId);
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.push(context,
        MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: widget.rideId))));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('HOME')));
}

/// Pumps the screen with [ride] and returns every layout overflow message.
///
/// [rideId] defaults to the fixture's. The online payment prompt keeps a
/// process-wide "already prompting" set keyed by ride, so a test that must see
/// the prompt uses a ride id no earlier test has opened.
Future<List<String>> pumpRide(
  WidgetTester tester,
  Map<String, dynamic> ride,
  Size size, {
  String rideId = 'ride123',
  List<ApiCall>? log,
  Duration rideDelay = Duration.zero,
  Duration settle = const Duration(milliseconds: 1200),
  Future<http.Response?> Function(http.Request req)? override,
  bool pushed = false,
  bool scrollSheet = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      overflows.add(text.split(String.fromCharCode(10)).first);
      return;
    }
    previous?.call(details);
  };

  try {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(rideId, pushed: pushed));
      // Let the first /rides/{id} poll land and the phase-driven sheet build.
      final steps = settle.inMilliseconds ~/ 200;
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // Inside the capture, so overflows BELOW the fold are caught too: the
      // sheet is a lazy list, and unscrolled, its lower half is never laid out.
      if (scrollSheet) await scrollSheetToEnd(tester);
    }, () => _api = mockApi(ride, log: log, rideDelay: rideDelay, override: override));
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

/// The mock the last [pumpRide] installed.
MockClient? _api;

/// Runs a test's interactions against the same mock API as the screen.
///
/// http.runWithClient is zone-scoped. The screen's polls work because their
/// timers were created inside the zone, but a request fired from a tap belongs
/// to the test's own zone — and there it reaches a real HttpClient, which the
/// test binding answers with a 400 for every call.
Future<void> act(Future<void> Function() body) =>
    http.runWithClient(body, () => _api!);

/// Drags the sheet fully open and scrolls its content to the end.
///
/// The sheet is a lazy ListView: anything below the fold is never built, so an
/// "is not shown" assertion about the bottom of the sheet passes whether the
/// widget is there or not. Every such assertion scrolls here first.
Future<void> scrollSheetToEnd(WidgetTester tester) async {
  final list = find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: find.byType(Scrollable),
  ).first;
  for (var i = 0; i < 4; i++) {
    await tester.drag(list, const Offset(0, -600), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Tears the screen down so its 3s/5s/30s poll timers are cancelled.
Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  while (tester.takeException() != null) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A tap that misses its widget only warns by default, and a test asserting
  // that nothing happened then passes without having done anything.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    // url_launcher is not exercised here, but share_plus and friends register
    // channels at startup; answering generically keeps them quiet.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'),
            (call) async => true);
  });

  final phases = <String, Map<String, dynamic>>{
    'finding': rideJson(status: 'pending', uiPhase: 'finding', uiPhaseLabel: 'Finding a driver'),
    'assigned': rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way'),
    'arrived': rideJson(status: 'arrived', uiPhase: 'arrived', uiPhaseLabel: 'Driver has arrived')
      ..['waitingSec'] = 135,
    'ongoing': rideJson(status: 'ongoing', uiPhase: 'ongoing', uiPhaseLabel: 'On trip'),
    'payment': rideJson(status: 'ongoing', uiPhase: 'payment', uiPhaseLabel: 'Payment due', awaitingPayment: true),
    'rental extra time': rentalOngoing(),
    'hire overtime': hireOngoing(),
    'parcel assigned': parcel(status: 'accepted', uiPhase: 'assigned', deliveryPhase: 'pending'),
    'parcel in transit': parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'in_transit'),
    'parcel returned': parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'returned'),
    'outstation assigned': outstation(status: 'accepted', uiPhase: 'assigned'),
    'payment online': rideJson(status: 'ongoing', uiPhase: 'payment',
        uiPhaseLabel: 'Payment due', awaitingPayment: true)..['paymentMode'] = 'online',
    'rental with stops': rentalWithStops(),
    'outstation at destination': outstation(status: 'ongoing', uiPhase: 'ongoing')
      ..['outstationPhase'] = 'at_destination',
    'scheduled rental': scheduledRental(DateTime.now().add(const Duration(days: 3))),
  };

  for (final size in const [kSmall, kCommon]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    group('ActiveRideScreen $tag', () {
      phases.forEach((phase, ride) {
        testWidgets('$phase — no overflow', (tester) async {
          final overflows = await pumpRide(tester, ride, size, scrollSheet: true);
          expect(overflows, isEmpty, reason: '$phase overflowed at $tag: $overflows');
          await teardown(tester);
        });
      });

      // #4 — the opaque AppBar is gone and the controls float over the map.
      testWidgets('floating controls present, no AppBar', (tester) async {
        await pumpRide(tester, phases['assigned']!, size);
        expect(find.byType(AppBar), findsNothing,
            reason: 'The map should not lose its top to an AppBar');
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byTooltip('Share trip'), findsOneWidget);
        expect(find.byTooltip('Emergency SOS'), findsOneWidget);
        await teardown(tester);
      });

      // #1 — chat and a real call are reachable from the ride card.
      testWidgets('chat and call reachable from the driver card', (tester) async {
        await pumpRide(tester, phases['assigned']!, size);
        expect(find.byTooltip('Message driver'), findsOneWidget);
        expect(find.byTooltip('Call driver'), findsOneWidget);
        await teardown(tester);
      });

      // #4 phase behaviour — the PIN is the hero at arrival and gone once moving.
      testWidgets('PIN is the hero at arrival', (tester) async {
        await pumpRide(tester, phases['arrived']!, size);
        expect(find.text('SHARE THIS PIN WITH YOUR DRIVER'), findsOneWidget);
        await teardown(tester);
      });

      // #5 — the rider sees how long the driver has waited, from the server count.
      testWidgets('waiting timer shows at arrival, seeded from the server', (tester) async {
        await pumpRide(tester, phases['arrived']!, size);
        expect(find.byType(DriverWaitingTimer), findsOneWidget);
        // Seeded at 135s; ~1.2s of pumping has passed, so it reads 2:15 or 2:16.
        expect(find.textContaining(RegExp(r'^2:1[56]$')), findsOneWidget);
        await teardown(tester);
      });

      testWidgets('waiting timer gone once the trip starts', (tester) async {
        await pumpRide(tester, phases['ongoing']!, size);
        expect(find.byType(DriverWaitingTimer), findsNothing);
        await teardown(tester);
      });

      testWidgets('PIN is hidden once the trip is under way', (tester) async {
        await pumpRide(tester, phases['ongoing']!, size);
        expect(find.text('SHARE THIS PIN WITH YOUR DRIVER'), findsNothing);
        expect(find.text('4821'), findsNothing);
        await teardown(tester);
      });

      // #8 — the radar shows only while searching, and the big spinner is gone.
      testWidgets('radar shows while searching', (tester) async {
        await pumpRide(tester, phases['finding']!, size);
        expect(find.byType(SearchRadar), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'The radar replaces the spinner; showing both competes');
        await teardown(tester);
      });

      testWidgets('radar gone once a driver is assigned', (tester) async {
        await pumpRide(tester, phases['assigned']!, size);
        expect(find.byType(SearchRadar), findsNothing);
        await teardown(tester);
      });

      // #3 — no recenter button while the camera is following.
      testWidgets('recenter hidden while following', (tester) async {
        await pumpRide(tester, phases['ongoing']!, size);
        expect(find.byTooltip('Recenter on driver'), findsNothing);
        await teardown(tester);
      });
    });
  }

  // #7 — rental, hire, parcel and outstation tracked on this screen must keep
  // everything their own booking screens showed, and charge what they charged.
  group('services on the live ride screen', () {
    // ── Rental / hire: a meter, not a destination ──
    testWidgets('rental shows package usage and the extras accruing', (tester) async {
      await pumpRide(tester, rentalOngoing(), kCommon);
      expect(find.byType(RentalUsagePanel), findsOneWidget);
      expect(find.text('5.4 / 4 hr'), findsOneWidget);
      expect(find.text('62.3 / 40 km'), findsOneWidget);
      expect(find.text('+₹480'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('hire shows hours on duty and overtime', (tester) async {
      await pumpRide(tester, hireOngoing(), kCommon);
      expect(find.byType(HireUsagePanel), findsOneWidget);
      expect(find.text('9.5 / 8 hr'), findsOneWidget);
      expect(find.text('+₹300'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('past the package the heading turns orange', (tester) async {
      await pumpRide(tester, hireOngoing(), kCommon);
      final title = tester.widget<Text>(find.text('Overtime'));
      expect(title.style?.color, Colors.orange[800]);
      await teardown(tester);
    });

    testWidgets('within the package the heading keeps its normal colour', (tester) async {
      await pumpRide(tester, hireOngoing()..['uiPhaseOverrun'] = false, kCommon);
      final title = tester.widget<Text>(find.text('Overtime'));
      // The normal heading colour (ink), no longer null: a null colour fell
      // through to the theme's grey body text and looked disabled.
      expect(title.style?.color, const Color(0xFF111111));
      await teardown(tester);
    });

    // Past the first driver fix (5s), when a taxi asks for its route and ETA.
    const pastFirstFix = Duration(milliseconds: 6400);

    testWidgets('a taxi under way routes to its drop and shows an ETA', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, phases['ongoing']!, kCommon, log: log, settle: pastFirstFix);
      final dirs = log.where((c) => c.url.path.endsWith('/directions')).toList();
      expect(dirs, isNotEmpty, reason: 'control: the taxi must fetch a route');
      expect(dirs.last.url.queryParameters['destLat'], '23.0732');
      expect(find.text('14 min'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a rental under way asks for no route and shows no ETA', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, rentalOngoing(), kCommon, log: log, settle: pastFirstFix);
      expect(log.where((c) => c.url.path.endsWith('/directions')), isEmpty,
          reason: 'A rental has no destination; each call is a billed Directions request');
      expect(find.text('14 min'), findsNothing);
      await teardown(tester);
    });

    testWidgets('a rental booked without a destination draws no drop pin', (tester) async {
      await pumpRide(tester, rentalOngoing(), kCommon);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final ids = map.markers.map((m) => m.markerId.value).toSet();
      expect(ids, contains('p'));
      expect(ids, isNot(contains('d')));
      await teardown(tester);
    });

    testWidgets('a taxi still draws its drop pin', (tester) async {
      await pumpRide(tester, phases['ongoing']!, kCommon);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.markers.map((m) => m.markerId.value), contains('d'));
      await teardown(tester);
    });

    // ── Cancel ──
    testWidgets('cancel is offered while the driver is on the way', (tester) async {
      await pumpRide(tester, phases['assigned']!, kCommon);
      await scrollSheetToEnd(tester);
      expect(find.text('Cancel Ride'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('cancel is gone once the trip has started', (tester) async {
      await pumpRide(tester, phases['ongoing']!, kCommon);
      await scrollSheetToEnd(tester);
      expect(find.text('Cancel Ride'), findsNothing);
      await teardown(tester);
    });

    testWidgets('a rental under way cannot be cancelled out of paying', (tester) async {
      await pumpRide(tester, rentalOngoing(), kCommon);
      await scrollSheetToEnd(tester);
      expect(find.text('Cancel Ride'), findsNothing);
      await teardown(tester);
    });

    // ── Parcel: two PINs ──
    testWidgets('parcel before pickup shows the pickup PIN, labelled as such', (tester) async {
      await pumpRide(tester, parcel(status: 'accepted', uiPhase: 'assigned', deliveryPhase: 'pending'), kCommon);
      expect(find.text('Pickup PIN — give it to the driver when they collect'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('7390'), findsNothing);
      await teardown(tester);
    });

    testWidgets('parcel on its way shows the delivery PIN, not the spent pickup PIN', (tester) async {
      await pumpRide(tester, parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'in_transit'), kCommon);
      expect(find.text('Delivery PIN — share it with the receiver'), findsOneWidget);
      expect(find.text('7390'), findsOneWidget);
      expect(find.text('4821'), findsNothing);
      await teardown(tester);
    });

    testWidgets('parcel on its way routes to the receiver', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'in_transit'),
          kCommon, log: log, settle: pastFirstFix);
      final dirs = log.where((c) => c.url.path.endsWith('/directions')).toList();
      expect(dirs, isNotEmpty);
      expect(dirs.last.url.queryParameters['destLat'], '23.0732');
      await teardown(tester);
    });

    testWidgets('parcel being returned routes back to the sender', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'returned'),
          kCommon, log: log, settle: pastFirstFix);
      final dirs = log.where((c) => c.url.path.endsWith('/directions')).toList();
      expect(dirs, isNotEmpty);
      expect(dirs.last.url.queryParameters['destLat'], '23.0225');
      await teardown(tester);
    });

    testWidgets('parcel being returned says so, and hides the delivery PIN', (tester) async {
      await pumpRide(tester, parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'returned'), kCommon);
      expect(find.text('Your parcel is coming back to you'), findsOneWidget);
      expect(find.textContaining('Receiver not answering'), findsOneWidget);
      expect(find.text('7390'), findsNothing);
      await teardown(tester);
    });

    // ── Outstation ──
    testWidgets('outstation shows the cities and the trip type', (tester) async {
      await pumpRide(tester, outstation(status: 'accepted', uiPhase: 'assigned'), kCommon);
      await scrollSheetToEnd(tester);
      expect(find.byType(OutstationTripPanel), findsOneWidget);
      expect(find.text('ROUND TRIP'), findsOneWidget);
      await teardown(tester);
    });

    // ── Payment ──
    testWidgets('online payment due offers a Pay button for the right amount', (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'test', 'ride_coupon_pay-hire': 50.0});
      final ride = hireOngoing()
        ..addAll({'uiPhase': 'payment', 'uiPhaseLabel': 'Payment due', 'awaitingPayment': true,
          'paymentMode': 'online', 'hireFinalFare': 900});
      await pumpRide(tester, ride, kCommon, rideId: 'pay-hire');
      // 900 with overtime, less the ₹50 coupon the ride was booked with.
      expect(find.text('Pay ₹850'), findsOneWidget);
      expect(find.text('₹850'), findsOneWidget);
      // The automatic prompt shows the same figure, not the pre-coupon total.
      expect(find.text('Please pay ₹850 to finish this ride.'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('cash payment due says to pay the driver, with no Pay button', (tester) async {
      await pumpRide(tester, phases['payment']!, kCommon, rideId: 'pay-cash');
      expect(find.text('Please pay ₹124999 to your driver in cash.'), findsOneWidget);
      expect(find.textContaining('Pay ₹'), findsNothing);
      await teardown(tester);
    });

    testWidgets('prepaid outstation does not ask to be paid again', (tester) async {
      final ride = outstation(status: 'ongoing', uiPhase: 'payment')
        ..addAll({'awaitingPayment': true, 'uiPhaseLabel': 'Payment due'});
      await pumpRide(tester, ride, kCommon, rideId: 'pay-outstation');
      expect(find.text('PAID AT BOOKING'), findsOneWidget);
      expect(find.text('Already paid when you booked. Nothing more to pay.'), findsOneWidget);
      expect(find.text('Pay ₹5400'), findsNothing);
      await teardown(tester);
    });

    // ── Completion ──
    // Polls overlap whenever /rides/{id} takes longer than the 3s interval, and
    // the wallet endpoint debits on every call. Both polls here see 'completed'.
    testWidgets('completion charges exactly once, even when polls overlap', (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'test', 'ride_coupon_done-hire': 50.0});
      final log = <ApiCall>[];
      final ride = hireOngoing()
        ..addAll({'status': 'completed', 'uiPhase': 'completed', 'paymentMode': 'wallet',
          'hireFinalFare': 900, 'hireExtraCharge': 300, 'hireExtraHours': 2});
      await pumpRide(tester, ride, kCommon, rideId: 'done-hire', log: log,
          rideDelay: const Duration(milliseconds: 3500),
          settle: const Duration(seconds: 9));
      final rideGets = log.where((c) => c.url.path.endsWith('/rides/done-hire'));
      expect(rideGets.length, greaterThanOrEqualTo(2),
          reason: 'control: at least two polls must have been in flight');
      final pays = log.where((c) => c.url.path.endsWith('/wallet/pay')).toList();
      expect(pays, hasLength(1), reason: 'The rider must be debited once');
      expect(jsonDecode(pays.single.body)['amount'], 850);
      await teardown(tester);
    });

    testWidgets('a hire closes with its itemised bill, total matching the charge', (tester) async {
      SharedPreferences.setMockInitialValues({'token': 'test', 'ride_coupon_bill-hire': 50.0});
      final ride = hireOngoing()
        ..addAll({'status': 'completed', 'uiPhase': 'completed', 'paymentMode': 'cash',
          'hireFinalFare': 900, 'hireExtraCharge': 300, 'hireExtraHours': 2});
      await pumpRide(tester, ride, kCommon, rideId: 'bill-hire');
      expect(find.text('Hire Bill'), findsOneWidget);
      expect(find.text('Overtime (2 hr)'), findsOneWidget);
      expect(find.text('−₹50'), findsOneWidget);
      expect(find.text('₹850'), findsOneWidget);
      await teardown(tester);
    });

    // ── Rental destinations ──
    testWidgets('a rental lists the destinations already sent to the driver', (tester) async {
      await pumpRide(tester, rentalWithStops(), kCommon, scrollSheet: true);
      expect(find.byType(RentalStopsPanel), findsOneWidget);
      expect(find.text('2 added'), findsOneWidget);
      expect(find.textContaining('Gujarat University Convention Centre'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('each rental destination is pinned on the map', (tester) async {
      await pumpRide(tester, rentalWithStops(), kCommon);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final ids = map.markers.map((m) => m.markerId.value).toSet();
      expect(ids, containsAll(['stop0', 'stop1']));
      await teardown(tester);
    });

    Future<http.Response?> places(http.Request req) async {
      if (req.url.path.endsWith('/places/autocomplete')) {
        return http.Response(jsonEncode({'predictions': [
          {'description': 'Kankaria Lake, Maninagar, Ahmedabad', 'placeId': 'pl1'},
        ]}), 200);
      }
      if (req.url.path.endsWith('/places/details')) {
        return http.Response(jsonEncode(
            {'address': 'Kankaria Lake, Maninagar, Ahmedabad', 'lat': 23.0063, 'lng': 72.6012}), 200);
      }
      return null;
    }

    Future<void> addKankaria(WidgetTester tester) => act(() async {
      await tester.tap(find.text('Add destination'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'Kankaria');
      await tester.pump(const Duration(milliseconds: 400)); // past the debounce
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Kankaria Lake, Maninagar, Ahmedabad'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('adding a destination sends it to the server', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, rentalOngoing(), kCommon, log: log, scrollSheet: true,
          override: (req) async => await places(req) ??
              (req.url.path.endsWith('/rental') ? http.Response(jsonEncode({'success': true}), 200) : null));
      await addKankaria(tester);
      final add = log.where((c) => c.url.path.endsWith('/rides/ride123/rental')).toList();
      expect(add, hasLength(1));
      expect(jsonDecode(add.single.body), {
        'action': 'addStop', 'address': 'Kankaria Lake, Maninagar, Ahmedabad',
        'lat': 23.0063, 'lng': 72.6012,
      });
      expect(find.text('Destination added — driver notified'), findsOneWidget);
      await teardown(tester);
    });

    // The booking screen's version reported success whatever the server said.
    testWidgets('a destination the server refuses is reported as a failure', (tester) async {
      await pumpRide(tester, rentalOngoing(), kCommon, scrollSheet: true,
          override: (req) async => await places(req) ??
              (req.url.path.endsWith('/rental')
                  ? http.Response(jsonEncode({'error': 'Not your ride'}), 403) : null));
      await addKankaria(tester);
      expect(find.text('Could not add destination: Not your ride'), findsOneWidget);
      expect(find.text('Destination added — driver notified'), findsNothing);
      await teardown(tester);
    });

    // ── Outstation leg ──
    testWidgets('a round trip says when the driver is waiting at the destination', (tester) async {
      final ride = outstation(status: 'ongoing', uiPhase: 'ongoing')..['outstationPhase'] = 'at_destination';
      await pumpRide(tester, ride, kCommon, scrollSheet: true);
      expect(find.text('At destination — your driver is waiting'), findsOneWidget);
      await teardown(tester);
    });

    // ── Scheduled ──
    testWidgets('a ride booked for later is shown as scheduled, not searching', (tester) async {
      final now = DateTime.now();
      final at = DateTime(now.year, now.month, now.day + 1, 9, 30);
      await pumpRide(tester, scheduledRental(at), kCommon);
      expect(find.text('Ride scheduled'), findsOneWidget);
      expect(find.text('Tomorrow, 9:30 AM'), findsOneWidget);
      expect(find.byType(SearchRadar), findsNothing);
      expect(find.text('Connecting you with nearby drivers'), findsNothing);
      await teardown(tester);
    });

    testWidgets('a ride due within minutes searches as normal', (tester) async {
      await pumpRide(tester, scheduledRental(DateTime.now().add(const Duration(minutes: 3))), kCommon);
      expect(find.text('Ride scheduled'), findsNothing);
      expect(find.byType(SearchRadar), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a scheduled ride further out shows its weekday and date', (tester) async {
      final now = DateTime.now();
      final at = DateTime(now.year, now.month, now.day + 5, 18, 5);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      await pumpRide(tester, scheduledRental(at), kCommon);
      expect(find.text('${days[at.weekday - 1]} ${at.day} ${months[at.month - 1]}, 6:05 PM'), findsOneWidget);
      await teardown(tester);
    });

    // ── Driver card ──
    testWidgets('the driver card shows rating and trips', (tester) async {
      final ride = rideJson(status: 'accepted', uiPhase: 'assigned');
      ride['driver'] = {...(ride['driver'] as Map), 'rating': 4.84, 'totalRides': 1240};
      await pumpRide(tester, ride, kCommon);
      expect(find.text('4.8 · 1,240 trips'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a driver with no rating yet shows no star', (tester) async {
      final ride = rideJson(status: 'accepted', uiPhase: 'assigned');
      ride['driver'] = {...(ride['driver'] as Map), 'rating': 0, 'totalRides': 12};
      await pumpRide(tester, ride, kCommon);
      expect(find.text('12 trips'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      await teardown(tester);
    });

    // ── SOS ──
    testWidgets('SOS opens the emergency screen and alerts the safety team', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, phases['ongoing']!, kCommon, log: log, rideId: 'sos-ride');
      await act(() async {
        await tester.tap(find.byTooltip('Emergency SOS'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(seconds: 9)); // the location lookup gives up
      });
      expect(find.text('Emergency Actions'), findsOneWidget);
      final alerts = log.where((c) => c.url.path.endsWith('/support/sos-alert')).toList();
      expect(alerts, hasLength(1), reason: 'Opening SOS must raise the alert');
      expect(jsonDecode(alerts.single.body)['rideId'], 'sos-ride');
      await teardown(tester);
    });

    // ── Share ──
    group('share', () {
      late List<MethodCall> shared;
      setUp(() {
        shared = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
            shared.add(call);
            return 'dev.fluttercommunity.plus/share/unavailable';
          },
        );
      });

      testWidgets('a ride shares the live tracking page', (tester) async {
        await pumpRide(tester, phases['ongoing']!, kCommon);
        await tester.tap(find.byTooltip('Share trip'));
        await tester.pump();
        final text = (shared.single.arguments as Map)['text'] as String;
        expect(text, contains('/track/ride123'));
        expect(text, isNot(contains('google.com/maps')));
        await teardown(tester);
      });

      testWidgets('a parcel shares the delivery PIN for the receiver, not the pickup PIN', (tester) async {
        await pumpRide(tester, parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'in_transit'), kCommon);
        await tester.tap(find.byTooltip('Share trip'));
        await tester.pump();
        final text = (shared.single.arguments as Map)['text'] as String;
        expect(text, contains('/track/ride123'));
        expect(text, contains('Delivery PIN: 7390'));
        expect(text, isNot(contains('4821')));
        await teardown(tester);
      });
    });

    // ── Cancel ──
    testWidgets('cancel asks why, sends the reason, and closes only the ride screen', (tester) async {
      final log = <ApiCall>[];
      final ride = rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way');
      await pumpRide(tester, ride, kCommon, log: log, pushed: true, scrollSheet: true,
          override: (req) async {
            if (req.url.path.endsWith('/cancel')) {
              ride['status'] = 'cancelled';
              return http.Response(jsonEncode({'success': true, 'cancellationFee': 0}), 200);
            }
            return null;
          });
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await tester.pump(); // the sheet's slide-in starts on this frame
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Please select a reason for cancellation'), findsOneWidget);
        await tester.tap(find.text('Wrong pickup location'));
        await tester.pump(const Duration(milliseconds: 100));
        // The shared sheet asks for a confirm; a reason alone no longer cancels.
        await tester.tap(find.text('Confirm Cancellation'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
      });
      final cancels = log.where((c) => c.url.path.endsWith('/rides/ride123/cancel')).toList();
      expect(cancels, hasLength(1));
      expect(jsonDecode(cancels.single.body)['reason'], 'Wrong pickup location');
      expect(find.byType(ActiveRideScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      await teardown(tester);
    });

    // ── No driver found (server-side close) ──
    // The server cancels a ride nobody took (cancelledBy 'system', reason
    // 'No driver found'). The screen only reacts to that state on a poll.
    testWidgets('no driver found: message, polling stops, Try again closes back to the booking origin', (tester) async {
      final log = <ApiCall>[];
      final ride = rideJson(status: 'pending', uiPhase: 'finding', uiPhaseLabel: 'Finding a driver')
        ..['service'] = 'rental';
      await pumpRide(tester, ride, kCommon, log: log, pushed: true);
      await act(() async {
        // Searching for as long as the server says pending.
        await tester.pump(const Duration(seconds: 7));
        expect(find.text('No driver found'), findsNothing);
        expect(find.byType(ActiveRideScreen), findsOneWidget);

        ride['status'] = 'cancelled';
        ride['cancelledBy'] = 'system';
        ride['cancellationReason'] = 'No driver found';
        await tester.pump(const Duration(milliseconds: 3100));
        await tester.pump(const Duration(milliseconds: 300));
      });
      expect(find.text('No driver found'), findsOneWidget);
      expect(find.text('No drivers available right now. Please try again.'), findsOneWidget);

      final polls = log.where((c) => c.method == 'GET' && c.url.path.endsWith('/rides/ride123')).length;
      await act(() => tester.pump(const Duration(seconds: 10)));
      expect(log.where((c) => c.method == 'GET' && c.url.path.endsWith('/rides/ride123')).length, polls,
          reason: 'polling stops once the server closed the ride');
      expect(log.where((c) => c.url.path.endsWith('/cancel')), isEmpty, reason: 'the app never cancels it itself');
      expect(find.byType(ActiveRideScreen), findsOneWidget, reason: 'stays until the rider acts');

      await act(() async {
        await tester.tap(find.text('Try again'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
      expect(find.byType(ActiveRideScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget, reason: 'only the ride screen closes');
      await teardown(tester);
    });

    testWidgets('a system cancel for another reason closes without the no-driver message', (tester) async {
      final ride = rideJson(status: 'ongoing', uiPhase: 'ongoing', uiPhaseLabel: 'On trip');
      await pumpRide(tester, ride, kCommon, pushed: true);
      await act(() async {
        ride['status'] = 'cancelled';
        ride['cancelledBy'] = 'system';
        ride['cancellationReason'] = 'face_verification_failed';
        await tester.pump(const Duration(milliseconds: 3100));
        await tester.pump(const Duration(seconds: 1));
      });
      expect(find.text('No driver found'), findsNothing);
      expect(find.byType(ActiveRideScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a cancel the server refuses keeps the ride on screen', (tester) async {
      await pumpRide(tester, phases['assigned']!, kCommon, pushed: true, scrollSheet: true,
          override: (req) async => req.url.path.endsWith('/cancel')
              ? http.Response(jsonEncode({'error': 'Ride already completed'}), 400)
              : null);
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await tester.pump(); // the sheet's slide-in starts on this frame
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Plan changed'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Confirm Cancellation'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));
      });
      expect(find.text('Could not cancel: Ride already completed'), findsOneWidget);
      expect(find.byType(ActiveRideScreen), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('backing out of the reasons does not cancel', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, phases['assigned']!, kCommon, log: log, pushed: true, scrollSheet: true);
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await tester.pump(); // the sheet's slide-in starts on this frame
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text("Don't cancel"));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(log.where((c) => c.url.path.endsWith('/cancel')), isEmpty);
      expect(find.byType(ActiveRideScreen), findsOneWidget);
      await teardown(tester);
    });

    // A cancel pops the screen, and so does a poll that sees 'cancelled'. The
    // route stays mounted through its pop animation, so a poll answering inside
    // it used to pop a SECOND time — the home screen — leaving a black screen.
    // The gate holds a poll in flight, then answers it mid-animation.
    testWidgets('a poll landing mid-close does not pop the home screen too', (tester) async {
      final ride = rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way');
      Completer<void>? gate;
      await pumpRide(tester, ride, kCommon, pushed: true, scrollSheet: true,
          override: (req) async {
            if (req.url.path.endsWith('/cancel')) {
              ride['status'] = 'cancelled';
              return http.Response(jsonEncode({'success': true}), 200);
            }
            final held = gate;
            if (req.method == 'GET' && req.url.path.endsWith('/rides/ride123') && held != null) {
              await held.future;
              return http.Response(jsonEncode(ride), 200);
            }
            return null;
          });
      await act(() async {
        gate = Completer<void>();
        await tester.pump(const Duration(milliseconds: 3100)); // a poll is now held open
        await tester.tap(find.text('Cancel Ride'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Plan changed'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Confirm Cancellation'));
        await tester.pump();                                   // the cancel's close begins
        await tester.pump(const Duration(milliseconds: 50));   // mid-animation
        gate!.complete();                                      // the held poll answers 'cancelled'
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(seconds: 1));
      });
      expect(find.text('HOME'), findsOneWidget, reason: 'Only the ride screen may close');
      expect(find.byType(ActiveRideScreen), findsNothing);
      await teardown(tester);
    });

    testWidgets('a returned parcel is not billed as delivered', (tester) async {
      final ride = parcel(status: 'completed', uiPhase: 'completed', deliveryPhase: 'returned')
        ..['deliveryFinalFare'] = 120;
      await pumpRide(tester, ride, kCommon, rideId: 'bill-parcel');
      expect(find.text('Parcel Returned'), findsOneWidget);
      expect(find.text('Parcel Delivered'), findsNothing);
      await teardown(tester);
    });
  });

  // On a device the sheet could be neither dragged nor scrolled, so the route,
  // payment and Cancel rows sat below the screen. Every rebuild handed the sheet
  // a NEW snapSizes list, which it answers by re-snapping — cancelling the drag
  // in progress — and the screen rebuilds every frame while the driver glides.
  // tester.drag delivers a whole gesture without a frame in between, so these
  // use timedDrag, which pumps frames during the gesture as a finger would.
  group('sheet can be dragged and scrolled to its end', () {
    for (final size in const [kSmall, Size(412, 915)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('driver on the way: Cancel reachable at $tag', (tester) async {
        await pumpRide(tester, rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way'), size);
        final list = find.descendant(
          of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
        final top0 = tester.getTopLeft(find.byType(DraggableScrollableSheet)).dy;
        final sheetTop0 = tester.getTopLeft(list).dy;
        await tester.timedDrag(list, const Offset(0, -300), const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getTopLeft(list).dy, lessThan(sheetTop0 - 100),
            reason: 'the sheet did not follow the finger (top $top0)');
        for (var i = 0; i < 4; i++) {
          await tester.timedDrag(list, const Offset(0, -400), const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 500));
        }
        final cancel = find.text('Cancel Ride');
        expect(cancel, findsOneWidget);
        expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(size.height),
            reason: 'Cancel is still below the screen');
        await teardown(tester);
      });
    }

    testWidgets('the snap sizes are one list across rebuilds', (tester) async {
      await pumpRide(tester, rideJson(status: 'accepted', uiPhase: 'assigned'), kCommon);
      final before = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet)).snapSizes;
      await tester.pump(const Duration(seconds: 4)); // polls land, screen rebuilds
      final after = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet)).snapSizes;
      expect(identical(before, after), isTrue);
      await teardown(tester);
    });
  });

  group('driver at the pickup', () {
    // Driver standing on the pickup; Directions says 0 minutes.
    Future<http.Response?> atPickup(http.Request req) async {
      if (req.url.path.endsWith('/driver-location')) {
        return http.Response(jsonEncode({'status': 'accepted', 'driver': {'lat': 23.0226, 'lng': 72.5715, 'heading': 0}}), 200);
      }
      if (req.url.path.endsWith('/directions')) {
        return http.Response(jsonEncode({'polyline': '', 'durationMin': 0, 'distanceKm': 0.01}), 200);
      }
      return null;
    }

    testWidgets('reads "Arriving now", never a "0 min" badge', (tester) async {
      await pumpRide(tester, rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way'),
          kCommon, override: atPickup, settle: const Duration(milliseconds: 6000));
      expect(find.text('Arriving now'), findsOneWidget);
      expect(find.text('0 min'), findsNothing);
      expect(find.text('Driver on the way'), findsNothing);
      await teardown(tester);
    });

    testWidgets('a driver still minutes away keeps the title and the ETA', (tester) async {
      await pumpRide(tester, rideJson(status: 'accepted', uiPhase: 'assigned', uiPhaseLabel: 'Driver on the way'),
          kCommon, settle: const Duration(milliseconds: 6000));
      expect(find.text('Driver on the way'), findsOneWidget);
      expect(find.text('14 min'), findsOneWidget);
      expect(find.text('Arriving now'), findsNothing);
      await teardown(tester);
    });
  });

  group('round 3', () {
    testWidgets('the search says "Looking for nearby drivers", whatever the server label', (tester) async {
      await pumpRide(tester, rideJson(status: 'pending', uiPhase: 'finding', uiPhaseLabel: 'Finding a driver'), kCommon);
      expect(find.text('Looking for nearby drivers'), findsOneWidget);
      expect(find.text('Finding a driver'), findsNothing);
      expect(find.text('Ride'), findsOneWidget); // the same chip as the booking search
      await teardown(tester);
    });

    testWidgets('cancel uses the shared sheet: a reason alone does not cancel', (tester) async {
      final log = <ApiCall>[];
      await pumpRide(tester, rideJson(status: 'accepted', uiPhase: 'assigned'), kCommon,
          log: log, pushed: true, scrollSheet: true);
      await act(() async {
        await tester.tap(find.text('Cancel Ride'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Plan changed'));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(find.byType(CancelReasonsSheet), findsOneWidget);
      expect(log.where((c) => c.url.path.endsWith('/cancel')), isEmpty);
      await teardown(tester);
    });

    group('camera framing', () {
      const pickup = LatLng(23.0225, 72.5714);
      test('driver at the pickup: street-level zoom on the pickup, not a zero-size fit', () {
        final u = frameDriverAndTarget(const LatLng(23.02251, 72.57141), pickup).toJson() as List;
        expect(u[0], 'newLatLngZoom');
        expect(u[1], [pickup.latitude, pickup.longitude]);
        expect(u[2], kFrameCloseZoom);
      });
      test('driver ~150 m out: still street level', () {
        final u = frameDriverAndTarget(const LatLng(23.0238, 72.5714), pickup).toJson() as List;
        expect(u[0], 'newLatLngZoom');
      });
      test('driver kilometres away: both in a fitted frame', () {
        final u = frameDriverAndTarget(const LatLng(23.0400, 72.5900), pickup).toJson() as List;
        expect(u[0], 'newLatLngBounds');
      });
      test('a route only metres long is not fitted either', () {
        final u = frameRoute(const [LatLng(23.02251, 72.57141), pickup])!.toJson() as List;
        expect(u[0], 'newLatLngZoom');
        expect(u[2], kFrameCloseZoom);
      });
    });
  });

  group('round 4', () {
    testWidgets('phase headings are drawn in the heading colour, not the grey body text', (tester) async {
      for (final r in [
        rideJson(status: 'pending', uiPhase: 'finding'),
        rentalOngoing()..['uiPhaseOverrun'] = false,
        hireOngoing()..['uiPhaseOverrun'] = false,
        parcel(status: 'ongoing', uiPhase: 'ongoing', deliveryPhase: 'in_transit'),
      ]) {
        await pumpRide(tester, r, kCommon);
        final heading = find.byWidgetPredicate((w) =>
            w is Text && w.style?.fontSize == 18 && w.style?.fontWeight == FontWeight.w800);
        expect(heading, findsWidgets);
        for (final t in tester.widgetList<Text>(heading)) {
          expect(t.style?.color, const Color(0xFF111111), reason: '"${t.data}" in ${r['uiPhase']}');
        }
        await teardown(tester);
      }
    });

    Map<String, dynamic> cab() {
      final r = rideJson(status: 'accepted', uiPhase: 'assigned', service: 'rental')
        ..['vehicleType'] = 'Cab';
      (r['driver'] as Map<String, dynamic>)
        ..['vehicleModel'] = 'Maruti Dzire'
        ..['vehicleTypeName'] = 'Cab';
      return r;
    }

    Future<http.Response?> types(http.Request req) async => req.url.path.endsWith('/vehicles/types')
        ? http.Response(jsonEncode({'types': [
            {'name': 'Prime SUV', 'imageUrl': '/uploads/xuv700.png'},
            {'name': 'Cab', 'imageUrl': '/uploads/dzire.png'},
          ]}), 200)
        : null;

    Iterable<String> networkImages(WidgetTester tester) => tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<NetworkImage>()
        .map((n) => n.url);

    testWidgets('the driver card shows the photo of the ride vehicle type', (tester) async {
      await pumpRide(tester, cab(), kCommon, override: types);
      final urls = networkImages(tester).toList();
      expect(urls.where((u) => u.endsWith('/uploads/dzire.png')), isNotEmpty);
      expect(urls.where((u) => u.endsWith('/uploads/xuv700.png')), isEmpty);
      // No bundled guess (the old fallback for any car was an SUV photo).
      final assets = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image).whereType<AssetImage>()
          .map((a) => a.assetName);
      expect(assets.where((a) => a.contains('economy') || a.contains('texi')), isEmpty);
      await teardown(tester);
    });

    testWidgets('an unknown vehicle type shows a neutral icon, not a stock photo', (tester) async {
      await pumpRide(tester, cab(), kCommon); // /vehicles/types answers nothing
      expect(find.byIcon(Icons.directions_car_outlined), findsOneWidget);
      final assets = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image).whereType<AssetImage>();
      expect(assets, isEmpty);
      await teardown(tester);
    });
  });

  group('round 5', () {
    testWidgets('a long trip ETA reads "4 h 22 min", not "262 min"', (tester) async {
      await pumpRide(tester, outstation(status: 'ongoing', uiPhase: 'ongoing'), kCommon,
          settle: const Duration(milliseconds: 6400),
          override: (req) async => req.url.path.endsWith('/directions')
              ? http.Response(jsonEncode({'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@', 'durationMin': 262, 'distanceKm': 220}), 200)
              : null);
      expect(find.text('4 h 22 min'), findsOneWidget);
      expect(find.textContaining('262'), findsNothing);
      await teardown(tester);
    });

    testWidgets('the rental "Where to next?" heading uses the heading colour', (tester) async {
      await pumpRide(tester, rentalWithStops(), kCommon, scrollSheet: true);
      final t = tester.widget<Text>(find.text('Where to next?'));
      expect(t.style?.color, const Color(0xFF111111));
      await teardown(tester);
    });
  });
}
