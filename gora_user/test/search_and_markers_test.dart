import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/taxi_booking_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/map_markers.dart';
import 'package:customer_app/utils/vehicle_marker.dart';
import 'package:customer_app/widgets/finding_driver_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// #8 — the searching radar and flat markers, everywhere a rider searches or
// watches a map, and real nearby vehicles instead of hard-coded ones.
// ─────────────────────────────────────────────────────────────────────────────

const kSmall = Size(320, 568);
const kCommon = Size(360, 640);

final _requests = <Uri>[];
MockClient? _api;
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => _api!);

MockClient mockApi({List<Map<String, dynamic>> nearby = const []}) => MockClient((req) async {
  _requests.add(req.url);
  if (req.url.path.endsWith('/rides/nearby-drivers')) {
    return http.Response(jsonEncode({'drivers': nearby}), 200);
  }
  return http.Response('{}', 200);
});

const _nearbyBikes = [
  {'id': 'd1', 'lat': 23.0231, 'lng': 72.5722, 'heading': 40, 'vehicleType': 'Bike'},
  {'id': 'd2', 'lat': 23.0219, 'lng': 72.5701, 'heading': 180, 'vehicleType': 'Bike'},
];

Widget finding({String vehicleType = 'Bike'}) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: FindingDriverView(
    pickupLat: 23.0225, pickupLng: 72.5714,
    dropLat: 23.0732, dropLng: 72.6208,
    pickupAddress: 'Shop 14, Ground Floor, Sardar Patel Complex, Near Municipal Market, Navrangpura, Ahmedabad',
    dropAddress: 'Block C, Tower 3, Flat 1802, Silver Oak Residency, Off S.G. Highway, Bodakdev, Ahmedabad',
    fareText: '₹1,24,999',
    serviceLabel: 'Finding your ride — Cab Premium SUV 7 Seater',
    serviceIcon: Icons.local_taxi,
    etaMin: 12,
    vehicleType: vehicleType,
    onCancel: () {},
  ),
);

Future<List<String>> pump(WidgetTester tester, Widget app, {Size size = kCommon,
    List<Map<String, dynamic>> nearby = const [], Duration settle = const Duration(milliseconds: 600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    final t = d.exceptionAsString();
    if (t.contains('overflowed') || t.contains('RenderFlex')) { overflows.add(t.split('\n').first); return; }
    previous?.call(d);
  };
  _requests.clear();
  _api = mockApi(nearby: nearby);
  // Vehicle sprites decode an image asset, which only progresses with real async
  // in a widget test. Decoded here, before any map exists (a map's platform view
  // cannot start in a test), they are cached for the screen to use at once.
  await tester.runAsync(() => VehicleMarkers.descriptorFor('Bike'));
  try {
    await act(() async {
      await tester.pumpWidget(app);
      final steps = settle.inMilliseconds ~/ 150;
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    });
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

/// True when [icon] is the flat glyph, or the fallback pin in [hue] shown for
/// the frame before it is drawn. Glyphs are cached across tests, so which of the
/// two a test sees depends on order — the colour is what must never be wrong.
Future<bool> isPlace(WidgetTester tester, BitmapDescriptor icon, Future<BitmapDescriptor> glyph, double hue) async {
  if (icon is DefaultMarker) return icon.hue == hue;
  return identical(icon, await tester.runAsync(() => glyph));
}

GoogleMap mapOf(WidgetTester tester) => tester.widget<GoogleMap>(find.byType(GoogleMap).first);
Set<String> markerIds(WidgetTester tester) => mapOf(tester).markers.map((m) => m.markerId.value).toSet();

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  group('taxi search screen', () {
    for (final size in const [kSmall, kCommon]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final overflows = await pump(tester, finding(), size: size);
        expect(overflows, isEmpty);
        await teardown(tester);
      });
    }

    testWidgets('searches with a radar on the pickup', (tester) async {
      await pump(tester, finding());
      expect(find.byType(SearchRadar), findsOneWidget);
      await teardown(tester);
    });

    // The radar is drawn at the centre of the band the camera centres the pickup
    // in — between the top padding and the measured card — or it floats off it.
    testWidgets('the radar sits where the camera puts the pickup', (tester) async {
      await pump(tester, finding());
      final pad = mapOf(tester).padding;
      expect(pad.bottom, greaterThan(200), reason: 'The card height must be measured, not guessed');
      final visibleCentreY = pad.top + (kCommon.height - pad.top - pad.bottom) / 2;
      expect(tester.getCenter(find.byType(SearchRadar)).dy, moreOrLessEquals(visibleCentreY, epsilon: 1));
      expect(tester.getCenter(find.byType(SearchRadar)).dx, moreOrLessEquals(kCommon.width / 2, epsilon: 1));
      await teardown(tester);
    });

    testWidgets('no straight line pretending to be the route', (tester) async {
      await pump(tester, finding());
      expect(mapOf(tester).polylines, isEmpty);
      await teardown(tester);
    });

    testWidgets('pickup is green and drop red, never the other way round', (tester) async {
      await pump(tester, finding());
      final markers = {for (final m in mapOf(tester).markers) m.markerId.value: m};
      expect(await isPlace(tester, markers['p']!.icon, PlaceMarkers.pickup(1.0), BitmapDescriptor.hueGreen), isTrue);
      expect(await isPlace(tester, markers['d']!.icon, PlaceMarkers.drop(1.0), BitmapDescriptor.hueRed), isTrue);
      await teardown(tester);
    });

    testWidgets('shows real nearby vehicles of the booked type', (tester) async {
      await pump(tester, finding(vehicleType: 'Bike'), nearby: _nearbyBikes);
      expect(markerIds(tester), containsAll(['veh_d1', 'veh_d2']));
      final q = _requests.firstWhere((u) => u.path.endsWith('/rides/nearby-drivers')).queryParameters;
      expect(q['vehicleType'], 'Bike');
      expect(double.parse(q['lat']!), 23.0225);
      await teardown(tester);
    });

    testWidgets('panning away hides the radar; recenter brings it back', (tester) async {
      await pump(tester, finding());
      // A finger on the map, then the camera starts moving: the rider panned.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(GoogleMap)) - const Offset(0, 150));
      mapOf(tester).onCameraMoveStarted!();
      await gesture.up();
      await tester.pump();
      expect(find.byType(SearchRadar), findsNothing);
      await act(() async {
        await tester.tap(find.byTooltip('Back to pickup'));
        await tester.pump();
      });
      expect(find.byType(SearchRadar), findsOneWidget);
      await teardown(tester);
    });

    // Our own animateCamera also fires onCameraMoveStarted; with no finger on
    // the map it must not count as the rider panning.
    testWidgets('the app moving its own camera keeps the radar', (tester) async {
      await pump(tester, finding());
      mapOf(tester).onCameraMoveStarted!();
      await tester.pump();
      expect(find.byType(SearchRadar), findsOneWidget);
      await teardown(tester);
    });
  });

  group('taxi booking map', () {
    Widget taxi() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      // Destination preset, as when the rider arrives from home with one — the
      // booking map shows once there is somewhere to go.
      child: MaterialApp(theme: AppTheme.lightTheme, home: const TaxiBookingScreen(
        fromLocation: 'Navrangpura', toLocation: 'Bodakdev', hideLocationInputs: true, preselectedVehicle: 'Bike')),
    );

    testWidgets('nearby vehicles are real drivers, not hard-coded Delhi positions', (tester) async {
      await pump(tester, taxi(), nearby: _nearbyBikes, settle: const Duration(milliseconds: 5400));
      final ids = markerIds(tester);
      expect(ids, containsAll(['veh_d1', 'veh_d2']));
      // The old fake layer used positional ids and fixed Delhi coordinates.
      expect(ids.where((i) => RegExp(r'^veh_\d+$').hasMatch(i)), isEmpty);
      final positions = mapOf(tester).markers.map((m) => m.position);
      expect(positions, isNot(contains(const LatLng(28.6150, 77.2100))));
      await teardown(tester);
    });

    testWidgets('pickup is green on the booking map too', (tester) async {
      await pump(tester, taxi());
      final markers = {for (final m in mapOf(tester).markers) m.markerId.value: m};
      // This map had pickup red and drop green — the reverse of every other map.
      expect(await isPlace(tester, markers['pickup']!.icon, PlaceMarkers.pickup(1.0, size: 34), BitmapDescriptor.hueGreen), isTrue);
      expect(await isPlace(tester, markers['drop']!.icon, PlaceMarkers.drop(1.0), BitmapDescriptor.hueRed), isTrue);
      await teardown(tester);
    });
  });

  group('glyphs', () {
    testWidgets('a numbered stop glyph is drawn at its logical size', (tester) async {
      final glyph = await tester.runAsync(() => PlaceMarkers.stop(2.0, 3));
      expect(glyph, isA<BytesMapBitmap>());
      expect((glyph! as BytesMapBitmap).width, 30);
    });

    testWidgets('the draggable pickup is drawn larger than a look-only one', (tester) async {
      final big = await tester.runAsync(() => PlaceMarkers.pickup(2.0, size: 34));
      final normal = await tester.runAsync(() => PlaceMarkers.pickup(2.0));
      expect((big! as BytesMapBitmap).width, 34);
      expect((normal! as BytesMapBitmap).width, PlaceMarkers.defaultSize);
    });
  });
}
