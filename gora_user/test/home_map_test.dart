import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/home_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/ride_ui/ride_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The home map. On a device it was blank white and recreated about every 1.5s:
// it was keyed on the camera centre, which every camera move rewrites, so any
// rebuild after a pan built a brand-new map — and each new map started a little
// off the last, walking the centre pin away from the rider's GPS dot.
// ─────────────────────────────────────────────────────────────────────────────

final _api = MockClient((req) async => http.Response('{}', 200));
Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => _api);

Widget app() => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
);

Future<void> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await act(() async {
    await tester.pumpWidget(app());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 9));
  while (tester.takeException() != null) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'), (call) async => null);
  });

  testWidgets('moving the camera and rebuilding keeps the same map', (tester) async {
    await open(tester);
    final before = tester.element(find.byType(GoogleMap));
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    // The rider pans; then anything rebuilds the screen (the vehicle layer
    // does every few seconds).
    map.onCameraMove!(const CameraPosition(target: LatLng(22.3039, 70.8022), zoom: 16));
    tester.element(find.byType(HomeScreen)).markNeedsBuild();
    await act(() => tester.pump(const Duration(milliseconds: 100)));
    final after = tester.element(find.byType(GoogleMap));
    expect(identical(before, after), isTrue, reason: 'the map must not be recreated');
    expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).key, map.key);
    await teardown(tester);
  });

  testWidgets('the centre pin\'s tip sits on the camera target', (tester) async {
    await open(tester);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    final rect = tester.getRect(find.byType(GoogleMap));
    final pad = map.padding;
    // Google Maps centres the target in the padded region.
    final targetY = rect.top + pad.top + (rect.height - pad.top - pad.bottom) / 2;
    final pin = find.descendant(of: find.byType(CentrePin), matching: find.byIcon(Icons.location_on));
    final tipY = tester.getCenter(pin).dy + CentrePin.tipBelowCentre(tester.getSize(pin).height);
    expect(tipY, closeTo(targetY, 0.5));
    expect(tester.getCenter(pin).dx, closeTo(rect.center.dx, 0.5));
    await teardown(tester);
  });
}
