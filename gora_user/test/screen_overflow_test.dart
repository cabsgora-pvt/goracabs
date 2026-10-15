import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/providers/theme_provider.dart';

import 'package:customer_app/screens/hire_driver_screen.dart';
import 'package:customer_app/screens/inquiry_screen.dart';
import 'package:customer_app/screens/login_screen.dart';
import 'package:customer_app/screens/offers_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/parcel_booking_screen.dart';
import 'package:customer_app/screens/parcel_history_screen.dart';
import 'package:customer_app/screens/profile_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/screens/ride_history_screen.dart';
import 'package:customer_app/screens/service_selection_screen.dart';
import 'package:customer_app/screens/settings_screen.dart';
import 'package:customer_app/screens/support_screen.dart';
import 'package:customer_app/screens/wallet_screen.dart';
import 'package:customer_app/screens/welcome_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen-level layout-overflow audit for the rider app.
//
// A RenderFlex overflow is invisible to `flutter analyze` and `flutter build` —
// it happens during layout, at runtime, at a specific width. These pump each
// screen at the two widths that actually matter and fail if anything overflows.
//
// Network calls fail here (there is no server), which is deliberate: this is the
// screen's initial state, which every rider sees for the first second and which
// is the state most likely to lay out with placeholder-width content.
// ─────────────────────────────────────────────────────────────────────────────

/// 320 is the narrowest screen still in real use; 360 is the most common
/// Android width. A layout that survives both survives nearly everything.
const kSmall = Size(320, 568);
const kCommon = Size(360, 640);

Widget _wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

/// Pumps [screen] at [size] and returns a description of any layout overflow.
///
/// The screen is torn down before the test ends so its timers and streams are
/// cancelled in dispose(); otherwise these fail on a pending timer rather than
/// reporting the layout result.
Future<String?> overflowOf(WidgetTester tester, Widget screen, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Capture LAYOUT errors only. These screens also raise network errors in the
  // test environment, and takeException() returns just the first exception — so
  // without this filter a failed fetch masks the overflow being audited.
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      // The summary line alone only gives a pixel count. The information
      // collector carries the creator chain, which names the actual widget.
      final info = (details.informationCollector?.call() ?? const [])
          .map((n) => n.toStringDeep())
          .join(' ');
      final nl = String.fromCharCode(10);
      // Keep the whole creator chain on one line: the widget class nearest the
      // top of the chain is what identifies the code that owns the layout.
      final creator = info.replaceAll(nl, ' ').replaceAll(RegExp(r'\s+'), ' ');
      // Printed as well as collected: expect() truncates long messages, and the
      // creator chain is the only thing that says WHICH widget overflowed.
      debugPrint('OVERFLOW>> ${text.split(nl).first} :: $creator');
      overflows.add(text.split(nl).first);
      return;
    }
    // Anything else goes back to the binding: swallowing it breaks the test
    // framework's own error bookkeeping and it asserts at teardown.
    previous?.call(details);
  };

  try {
    await tester.pumpWidget(_wrap(screen));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  } finally {
    FlutterError.onError = previous;
  }

  // Drain the expected non-layout exceptions so they do not fail teardown.
  while (tester.takeException() != null) {}

  return overflows.isEmpty ? null : overflows.join(' | ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'test'});
    for (final name in const [
      'flutter.baseflow.com/geolocator',
      'flutter.baseflow.com/geolocator_android',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
          case 'requestPermission':
            return 1;
          case 'getCurrentPosition':
          case 'getLastKnownPosition':
            return <String, dynamic>{
              'latitude': 23.0225, 'longitude': 72.5714,
              'accuracy': 5.0, 'altitude': 0.0, 'heading': 90.0,
              'speed': 0.0, 'speed_accuracy': 1.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'is_mocked': true,
            };
        }
        return null;
      });
    }
  });

  group('rider screens - no layout overflow', () {
    final screens = <String, Widget Function()>{
      'HireDriverScreen': () => const HireDriverScreen(),
      'InquiryScreen': () => const InquiryScreen(),
      'LoginScreen': () => const LoginScreen(),
      'OffersScreen': () => const OffersScreen(),
      'OutstationScreen': () => const OutstationScreen(),
      'ParcelBookingScreen': () => const ParcelBookingScreen(),
      'ParcelHistoryScreen': () => const ParcelHistoryScreen(),
      'ProfileScreen': () => const ProfileScreen(),
      'RentalScreen': () => const RentalScreen(),
      'RideHistoryScreen': () => const RideHistoryScreen(),
      'ServiceSelectionScreen': () => const ServiceSelectionScreen(),
      'SettingsScreen': () => const SettingsScreen(),
      'SupportScreen': () => const SupportScreen(),
      'WalletScreen': () => const WalletScreen(),
      'WelcomeScreen': () => const WelcomeScreen(),
    };

    for (final size in const [kSmall, kCommon]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      screens.forEach((name, build) {
        testWidgets('$name $tag', (tester) async {
          final e = await overflowOf(tester, build(), size);
          expect(e, isNull, reason: '$name overflowed at $tag');
        });
      });
    }
  });
}
