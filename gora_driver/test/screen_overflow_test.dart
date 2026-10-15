import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/ride/pages/rental_progress_page.dart';
import 'package:gora_driver/features/ride/pages/hire_progress_page.dart';
import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/account/pages/documents_page.dart';
import 'package:gora_driver/features/account/pages/faq_page.dart';
import 'package:gora_driver/features/account/pages/id_card_page.dart';
import 'package:gora_driver/features/account/pages/incentive_page.dart';
import 'package:gora_driver/features/account/pages/leaderboard_page.dart';
import 'package:gora_driver/features/account/pages/preferences_page.dart';
import 'package:gora_driver/features/account/pages/profile_page.dart';
import 'package:gora_driver/features/account/pages/settings_page.dart';
import 'package:gora_driver/features/account/pages/sos_page.dart';
import 'package:gora_driver/features/account/pages/support_page.dart';
import 'package:gora_driver/features/auth/pages/login_page.dart';
import 'package:gora_driver/features/earnings/pages/earnings_page.dart';
import 'package:gora_driver/features/history/pages/history_page.dart';
import 'package:gora_driver/features/notifications/pages/notification_page.dart';
import 'package:gora_driver/features/registration/bank_details_page.dart';
import 'package:gora_driver/features/registration/kyc_pending_page.dart';
import 'package:gora_driver/features/registration/personal_details_page.dart';
import 'package:gora_driver/features/registration/vehicle_details_page.dart';
import 'package:gora_driver/features/registration/vehicle_selection_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/wallet/pages/wallet_page.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Screen-level layout-overflow audit.
//
// The widget-level tests in overflow_test.dart cover one component. This pumps
// whole SCREENS at the sizes that actually break layouts, because an overflow
// is a property of a screen's real content, not of a widget in isolation.
//
// Neither `flutter analyze` nor `flutter build` can see these: a RenderFlex
// overflow happens during layout, at runtime, at a specific width.
//
// Network calls fail in the test environment, which is fine and deliberate —
// these screens are pumped in their initial state, which is exactly the state a
// driver sees for the first second of every job, and the state most likely to
// be laid out with placeholder-width content.
// ─────────────────────────────────────────────────────────────────────────────

/// Real screens still in wide use. 320 is the narrowest (iPhone SE 1st gen and
/// a large slice of budget Android); 360 is the single most common Android width.
const kSmall = Size(320, 568);
const kCommon = Size(360, 640);

/// A ride with deliberately awkward, realistic content. Short tidy strings hide
/// overflows; real Indian addresses and names are what actually ship.
RideRequestModel ride({
  String service = 'taxi',
  double cod = 0,
  int packageHours = 0,
  int packageKm = 0,
  int hireHours = 0,
}) => RideRequestModel(
  id: '65f0c1a2b3d4e5f6a7b8c9d0',
  userName: 'Chandrashekhar Balasubramanian',
  userPhone: '+91 98765 43210',
  userRating: '4.9',
  pickupAddress: 'Shop 14, Ground Floor, Sardar Patel Complex, Near Municipal '
      'Market, Navrangpura, Ahmedabad, Gujarat 380009',
  dropAddress: 'Block C, Tower 3, Flat 1802, Silver Oak Residency, Off S.G. '
      'Highway, Bodakdev, Ahmedabad, Gujarat 380054',
  distance: '18.4 km',
  fare: '₹ 1,24,999',
  eta: '42 min',
  rideType: 'Cab Premium SUV 7 Seater',
  pickupLat: 23.0225, pickupLng: 72.5714,
  dropLat: 23.0732, dropLng: 72.6208,
  service: service,
  codAmount: cod,
  packageHours: packageHours,
  packageKm: packageKm,
  hireTotalHours: hireHours,
  senderName: 'Venkataraman Subramanian Iyer',
  receiverName: 'Lakshminarayanan Venkatasubramanian',
  itemType: 'Refrigerated pharmaceutical consignment',
  distanceKm: 18.4,
  durationMin: 42,
  totalFareValue: 124999,
);

/// Mirrors the real provider tree from app/app.dart, so screens are laid out in
/// the environment they actually run in rather than a simplified one.
Widget _wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => DriverProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: BlocProvider(
    create: (_) => AuthBloc(),
    child: MaterialApp(theme: AppTheme.light, home: child),
  ),
);

/// Pumps [screen] at [size] and returns the layout error, if any.
///
/// The screen is torn down before the test ends so its timers and location
/// subscriptions are cancelled in dispose() — otherwise every one of these
/// fails with "A Timer is still pending" instead of reporting the real result.
Future<String?> overflowOf(WidgetTester tester, Widget screen, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Capture LAYOUT errors specifically. These screens also throw network
  // errors in the test environment (there is no server), and takeException()
  // returns only the first exception — so without this filter a failed fetch
  // masks the overflow we are actually looking for.
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      // Ours to report; do not forward, or the test fails on it directly.
      // Keep the summary line plus the first few diagnostic lines: the widget
      // that overflowed is far more useful than just the pixel count.
      // details.toString() carries the offending RenderFlex and its ancestor
      // chain; exceptionAsString() is only the one-line summary.
      final full = details.toString();
      final nl = String.fromCharCode(10);
      final hint = full
          .split(nl)
          .where((l) => l.contains('creator:') || l.contains('parentData:'))
          .take(2)
          .join(' | ');
      overflows.add('${text.split(nl).first}  <<$hint>>');
      return;
    }
    // Everything else goes back to the binding. Swallowing it breaks the test
    // framework's own error bookkeeping and it asserts at teardown.
    previous?.call(details);
  };

  try {
    await tester.pumpWidget(_wrap(screen));
    await tester.pump(const Duration(milliseconds: 80));
    // Tear the screen down so its timers and location subscriptions are
    // cancelled in dispose(), or every test fails on a pending timer instead
    // of reporting its real result.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  } finally {
    FlutterError.onError = previous;
  }

  // Drain non-layout exceptions (failed HTTP, mostly) so they do not fail the
  // test at teardown. They are expected here and are not what we are auditing.
  while (tester.takeException() != null) {}

  return overflows.isEmpty ? null : overflows.join(' | ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'driver_token': 'test'});
    // Geolocator talks over platform channels that do not exist in a test
    // binding. Answering them keeps the screens in their normal code path
    // instead of failing before they have laid anything out.
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
            return 1; // whileInUse
          case 'getCurrentPosition':
          case 'getLastKnownPosition':
            return <String, dynamic>{
              'latitude': 23.0225, 'longitude': 72.5714,
              'accuracy': 5.0, 'altitude': 0.0, 'heading': 90.0,
              'speed': 8.0, 'speed_accuracy': 1.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'is_mocked': true,
            };
        }
        return null;
      });
    }
  });

  group('driver screens - no layout overflow', () {
    for (final size in const [kSmall, kCommon]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('RentalProgressPage $tag', (tester) async {
        final e = await overflowOf(tester,
            RentalProgressPage(ride: ride(service: 'rental', packageHours: 4, packageKm: 60)), size);
        expect(e, isNull, reason: 'RentalProgressPage overflowed at $tag');
      });

      testWidgets('HireProgressPage $tag', (tester) async {
        final e = await overflowOf(tester,
            HireProgressPage(ride: ride(service: 'hire_driver', hireHours: 4)), size);
        expect(e, isNull, reason: 'HireProgressPage overflowed at $tag');
      });

      testWidgets('DeliveryProgressPage $tag', (tester) async {
        final e = await overflowOf(tester,
            DeliveryProgressPage(ride: ride(service: 'delivery', cod: 99999)), size);
        expect(e, isNull, reason: 'DeliveryProgressPage overflowed at $tag');
      });

      testWidgets('CollectFarePage $tag', (tester) async {
        final e = await overflowOf(tester, const CollectFarePage(amount: 124999), size);
        expect(e, isNull, reason: 'CollectFarePage overflowed at $tag');
      });
    }
  });

  // ── Broad sweep ─────────────────────────────────────────────────────────────
  // Every driver screen that can be constructed without route arguments, at the
  // two widths that matter. These render in their initial (pre-network) state,
  // which is the state every driver sees first and the one most likely to lay
  // out with placeholder-width content.
  group('driver screens sweep - no layout overflow', () {
    final screens = <String, Widget Function()>{
      'AccountPage': () => const AccountPage(),
      'DocumentsPage': () => const DocumentsPage(),
      'FaqPage': () => const FaqPage(),
      'IdCardPage': () => const IdCardPage(),
      'IncentivePage': () => const IncentivePage(),
      'LeaderboardPage': () => const LeaderboardPage(),
      'PreferencesPage': () => const PreferencesPage(),
      'ProfilePage': () => const ProfilePage(),
      'SettingsPage': () => const SettingsPage(),
      'SosPage': () => const SosPage(),
      'SupportPage': () => const SupportPage(),
      'LoginPage': () => const LoginPage(),
      'EarningsPage': () => const EarningsPage(),
      'HistoryPage': () => const HistoryPage(),
      'NotificationPage': () => const NotificationPage(),
      'BankDetailsPage': () => const BankDetailsPage(),
      'KycPendingPage': () => const KycPendingPage(),
      'PersonalDetailsPage': () => const PersonalDetailsPage(),
      'VehicleDetailsPage': () => const VehicleDetailsPage(),
      'VehicleSelectionPage': () => const VehicleSelectionPage(),
      'IncomingRequestsPage': () => const IncomingRequestsPage(),
      'WalletPage': () => const WalletPage(),
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
