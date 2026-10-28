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
import 'package:gora_driver/features/account/pages/account_page.dart';
import 'package:gora_driver/features/account/pages/documents_page.dart';
import 'package:gora_driver/features/account/pages/misc_pages.dart';
import 'package:gora_driver/features/account/pages/settings_page.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/auth/pages/driver_otp_page.dart';
import 'package:gora_driver/features/auth/pages/login_page.dart';
import 'package:gora_driver/features/earnings/pages/earnings_page.dart';
import 'package:gora_driver/features/history/pages/history_page.dart';
import 'package:gora_driver/features/history/pages/trip_detail_page.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/onboarding/onboarding_page.dart';
import 'package:gora_driver/features/registration/bank_details_page.dart';
import 'package:gora_driver/features/registration/document_detail_page.dart';
import 'package:gora_driver/features/registration/document_upload_page.dart';
import 'package:gora_driver/features/registration/face_capture_page.dart';
import 'package:gora_driver/features/registration/kyc_pending_page.dart';
import 'package:gora_driver/features/registration/kyc_success_page.dart';
import 'package:gora_driver/features/registration/personal_details_page.dart';
import 'package:gora_driver/features/registration/rejection_page.dart';
import 'package:gora_driver/features/registration/vehicle_details_page.dart';
import 'package:gora_driver/features/registration/vehicle_selection_page.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/delivery_progress_page.dart';
import 'package:gora_driver/features/ride/pages/hire_progress_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/pages/on_ride_page.dart';
import 'package:gora_driver/features/ride/pages/rental_progress_page.dart';
import 'package:gora_driver/features/wallet/pages/wallet_page.dart';
import 'package:gora_driver/features/wallet/pages/withdraw_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Overflow sweep for the Rapido-Captain / Uber-Driver redesign.
//
// Unlike screen_overflow_test.dart (initial, pre-network state), every screen
// here is pumped WITH data: a mock API answers each call with deliberately
// awkward but realistic content — long Indian names and addresses, six-figure
// fares, a negative wallet, long vehicle names — at the three widths the
// redesign has to hold: 320x568, 360x640 and 412x915.
// ─────────────────────────────────────────────────────────────────────────────

const _sizes = [Size(320, 568), Size(360, 640), Size(412, 915)];

final _now = DateTime.now().toUtc().toIso8601String();

const _longName = 'Chandrashekhar Venkatasubramanian Balasubramanian';
const _pickup = 'Shop 14, Ground Floor, Sardar Patel Complex - Near Municipal Market, Navrangpura, Ahmedabad, Gujarat 380009';
const _drop = 'Block C, Tower 3, Flat 1802, Silver Oak Residency - Off S.G. Highway, Bodakdev, Ahmedabad, Gujarat 380054';

/// Server-side approval status the mock profile reports. The KYC screens poll
/// it and leave as soon as it is 'approved', so they are pumped as 'pending'.
String _status = 'approved';

/// One pending request (full-screen single card) or two (list).
bool _singleRequest = false;

RideRequestModel _ride({String service = 'taxi', String status = 'accepted', double cod = 0}) => RideRequestModel(
  id: '65f0c1a2b3d4e5f6a7b8c9d0', userName: _longName, userPhone: '+91 98765 43210', userRating: '4.9',
  pickupAddress: _pickup, dropAddress: _drop, distance: '18.4 km', fare: '₹ 1,24,999', eta: '42 min',
  rideType: 'Cab Premium SUV 7 Seater', pickupLat: 23.0225, pickupLng: 72.5714, dropLat: 23.0732, dropLng: 72.6208,
  service: service, status: status, codAmount: cod, packageHours: 4, packageKm: 60, hireTotalHours: 8,
  senderName: 'Venkataraman Subramanian Iyer', senderPhone: '+91 90000 11111',
  receiverName: 'Lakshminarayanan Venkatasubramanian', receiverPhone: '+91 90000 22222',
  itemType: 'Refrigerated pharmaceutical consignment', distanceKm: 18.4, durationMin: 42, totalFareValue: 124999,
);

Map<String, dynamic> get _driver => {
  '_id': 'd1', 'name': _longName, 'phone': '9876543210', 'email': 'chandrashekhar.balasubramanian@example.com',
  'state': 'Andaman and Nicobar Islands', 'status': _status, 'rating': 4.87, 'totalRides': 128456,
  'vehicleModel': 'Maruti Suzuki Ertiga ZXi Plus CNG Automatic', 'vehicleRegistrationNumber': 'GJ 01 AB 1234',
  'selectedVehicleTypeName': 'Cab Premium SUV 7 Seater', 'acceptsRental': true, 'acceptsDelivery': true,
  'documents': [
    {'name': 'Vehicle Insurance Certificate (Comprehensive)', 'fileUrl': '', 'status': 'pending', 'number': 'POL-9988776655443322110'},
    {'name': 'Aadhaar Card', 'fileUrl': '', 'status': 'verified', 'number': '1234 5678 9012'},
    {'name': 'Driving License', 'fileUrl': '', 'status': 'rejected'},
  ],
};

Map<String, dynamic> _request(String id, String service, {Map<String, dynamic> extra = const {}}) => {
  'id': id, 'service': service, 'riderName': _longName, 'vehicleType': 'Cab Premium SUV 7 Seater Extra Long',
  'pickupAddress': _pickup, 'dropAddress': _drop,
  'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
  'fare': 124999, 'tip': 9999, 'totalFare': 134998, 'distance': 418.4, 'pickupDistanceKm': 12.6,
  'paymentMode': 'cash', 'status': 'pending', ...extra,
};

Object? _body(String path) {
  if (path.endsWith('/auth/driver/profile')) return {'driver': _driver};
  if (path.endsWith('/auth/driver/wallet')) {
    return {'balance': -1250.5, 'transactions': [
      {'_id': 't1', 'type': 'ride_earning', 'amount': 124999, 'createdAt': _now,
        'description': 'Trip from Navrangpura to Bodakdev, Ahmedabad including two tolls and waiting'},
      {'_id': 't2', 'type': 'commission', 'amount': -12499, 'createdAt': _now, 'description': ''},
      {'_id': 't3', 'type': 'subscription_renewal_with_a_long_type', 'amount': -999, 'createdAt': _now, 'description': 'Gold'},
    ]};
  }
  if (path.endsWith('/rides/driver/summary')) {
    return {'today': 1249999, 'week': 98765432, 'totalRides': 128456, 'todayDistance': 12345.6};
  }
  if (path.endsWith('/rides/driver/history')) {
    return {'rides': [
      {'_id': 'h1', 'status': 'completed', 'riderName': _longName, 'pickupAddress': _pickup, 'dropAddress': _drop,
        'totalFare': 124999, 'driverEarning': 112499, 'distance': 418.4, 'duration': 512, 'riderRating': 4,
        'service': 'outstation', 'tripType': 'round_trip', 'cityFrom': 'Ahmedabad, Gujarat',
        'cityTo': 'Mount Abu Hill Station, Sirohi, Rajasthan', 'vehicleType': 'Cab Premium SUV 7 Seater',
        'numPassengers': 6, 'paymentMode': 'cash', 'createdAt': _now},
      {'_id': 'h2', 'status': 'cancelled', 'riderName': 'R', 'pickupAddress': 'Law Garden', 'dropAddress': '',
        'totalFare': 0, 'service': 'delivery', 'createdAt': _now},
    ]};
  }
  if (path.endsWith('/vehicles/types')) {
    // The six types the server has, with images, seats and services as it
    // sends them — plus one deliberately over-long name.
    return {'types': [
      {'_id': 'v1', 'name': 'Bike', 'capacity': 1, 'imageUrl': '/uploads/bike.png', 'services': ['taxi', 'parcel'], 'isActive': true},
      {'_id': 'v2', 'name': 'Auto', 'capacity': 3, 'imageUrl': '/uploads/auto.png', 'services': ['taxi', 'parcel', 'rental'], 'isActive': true},
      {'_id': 'v3', 'name': 'Cab', 'capacity': 4, 'imageUrl': '/uploads/cab.png',
        'services': ['taxi', 'rental', 'outstation', 'hire_driver', 'parcel'], 'isActive': true},
      {'_id': 'v4', 'name': 'Prime Sedan', 'capacity': 4, 'imageUrl': '/uploads/sedan.png', 'services': ['taxi', 'rental', 'outstation'], 'isActive': true},
      {'_id': 'v5', 'name': 'Prime SUV', 'capacity': 7, 'imageUrl': '/uploads/suv.png', 'services': ['taxi', 'rental', 'outstation', 'hire_driver'], 'isActive': true},
      {'_id': 'v6', 'name': 'Mini Truck', 'imageUrl': '/uploads/truck.png', 'services': ['parcel'], 'isActive': true},
      {'_id': 'v7', 'name': 'Cab Premium SUV 7 Seater Extra Long Wheelbase', 'capacity': 7,
        'services': ['taxi', 'rental', 'outstation', 'hire_driver', 'parcel'], 'isActive': true},
    ]};
  }
  if (path.endsWith('/zones')) {
    return {'zones': [{'_id': 'z1', 'name': 'Ahmedabad Metropolitan Region — West Zone (Bopal, Ghuma, Shela)'}]};
  }
  if (path.endsWith('/rides/driver/pending')) {
    return {'rides': [
      if (_singleRequest) _request('s1', 'taxi', extra: {'tip': 0}) else
      _request('p1', 'delivery', extra: {'itemType': 'Refrigerated pharmaceutical consignment', 'weightKg': 24.5,
        'packageSize': 'XL', 'isFragile': true, 'codAmount': 99999}),
      if (!_singleRequest) _request('o1', 'outstation', extra: {'paymentMode': 'wallet'}),
    ]};
  }
  if (path.endsWith('/rides/driver/active')) return {'ride': null};
  return <String, dynamic>{};
}

MockClient get _api => MockClient((req) async => http.Response(jsonEncode(_body(req.url.path)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'}));

Widget _wrap(Widget child, {Object? args, DriverProvider? dp}) => MultiProvider(
  providers: [
    if (dp != null) ChangeNotifierProvider.value(value: dp) else ChangeNotifierProvider(create: (_) => DriverProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: BlocProvider(
    create: (_) => AuthBloc(),
    child: MaterialApp(
      theme: AppTheme.light,
      // Only the first route is the screen under test; anything it navigates
      // to is a blank page, so a redirect cannot masquerade as the screen.
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => settings.name == '/' ? child : const Scaffold(body: SizedBox()),
      ),
    ),
  ),
);

/// Pumps [screen] at [size] with the mock API, optionally drives it, and
/// returns every layout overflow reported.
Future<List<String>> _overflows(
  WidgetTester tester,
  Widget screen,
  Size size, {
  Object? args,
  bool withProfile = false,
  Future<void> Function(WidgetTester)? interact,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final found = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      final where = details.toString().split('\n')
          .firstWhere((l) => l.contains('file:///'), orElse: () => '').trim();
      found.add('${text.split('\n').first}  <$where>');
      return;
    }
    previous?.call(details);
  };

  try {
    await http.runWithClient(() async {
      DriverProvider? dp;
      if (withProfile) {
        dp = DriverProvider();
        await dp.loadProfile();
      }
      await tester.pumpWidget(_wrap(screen, args: args, dp: dp));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Guard: the screen really is on screen, so an empty result means
      // "no overflow", not "nothing was laid out".
      expect(find.byType(screen.runtimeType), findsOneWidget, reason: '${screen.runtimeType} did not render');
      if (interact != null) await interact(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, () => _api);
  } finally {
    FlutterError.onError = previous;
  }
  while (tester.takeException() != null) {}
  return found;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) return;
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _status = 'approved';
    _singleRequest = false;
    SharedPreferences.setMockInitialValues({'driver_token': 'test'});
    for (final name in const ['flutter.baseflow.com/geolocator', 'flutter.baseflow.com/geolocator_android']) {
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
              'latitude': 23.0225, 'longitude': 72.5714, 'accuracy': 5.0, 'altitude': 0.0, 'heading': 90.0,
              'speed': 8.0, 'speed_accuracy': 1.0, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'is_mocked': true,
            };
        }
        return null;
      });
    }
  });

  const insurance = DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number',
      needsBack: true, needsExpiry: true);

  const trip = TripModel(
    id: 'h1', userName: _longName, pickupAddress: _pickup, dropAddress: _drop, distance: '418.4 km',
    fare: '₹ 1249999', date: '27 Oct 2026, 11:45 PM', status: 'completed', paymentMode: 'wallet', duration: '512 min',
    rating: 4, service: 'outstation', vehicleType: 'Cab Premium SUV 7 Seater', tripType: 'round_trip',
    cityFrom: 'Ahmedabad', cityTo: 'Mount Abu', numPassengers: 6,
  );

  final screens = <String, ({Widget Function() build, Object? args, bool profile,
      Future<void> Function(WidgetTester)? interact})>{
    'Onboarding': (build: () => const OnboardingPage(), args: null, profile: false, interact: (t) async {
      await _tapText(t, 'Next');
      await _tapText(t, 'Next');
    }),
    'Login': (build: () => const LoginPage(), args: null, profile: false, interact: (t) async {
      await t.enterText(find.byType(TextField), '9876543210');
      await t.pump();
    }),
    'OTP': (build: () => const DriverOtpPage(), args: '9876543210', profile: false, interact: null),
    'PersonalDetails': (build: () => const PersonalDetailsPage(), args: {'phone': '9876543210'}, profile: false, interact: null),
    'FaceCapture': (build: () => const FaceCapturePage(), args: null, profile: false, interact: null),
    'VehicleSelection': (build: () => const VehicleSelectionPage(), args: null, profile: false, interact: (t) async {
      // All six real types plus the long one are listed (not the empty state).
      expect(find.text('Mini Truck'), findsOneWidget);
      await _tapText(t, 'Bike');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -2000), warnIfMissed: false);
      await t.pump();
      await _tapText(t, 'Cab Premium SUV 7 Seater Extra Long Wheelbase');
    }),
    'VehicleDetails': (build: () => const VehicleDetailsPage(),
        args: {'vehicle': {'_id': 'v1', 'name': 'Cab Premium SUV 7 Seater Extra Long Wheelbase'}}, profile: false, interact: null),
    'VehicleDetails with image': (build: () => const VehicleDetailsPage(),
        args: {'vehicle': {'_id': 'v6', 'name': 'Mini Truck', 'imageUrl': '/uploads/truck.png'}}, profile: false, interact: null),
    'DocumentUpload': (build: () => const DocumentUploadPage(), args: null, profile: false, interact: null),
    'DocumentDetail empty': (build: () => DocumentDetailPage(spec: insurance, initial: DocData()), args: null, profile: false, interact: null),
    'DocumentDetail filled': (build: () => DocumentDetailPage(spec: insurance, initial: DocData(
        number: 'POL-9988776655443322110', expiry: '05-07-2030',
        frontUrl: 'https://example.invalid/front.jpg', backUrl: 'https://example.invalid/back.jpg')),
        args: null, profile: false, interact: null),
    'BankDetails': (build: () => const BankDetailsPage(), args: null, profile: false, interact: (t) async {
      await _tapText(t, 'Current');
    }),
    'KycSuccess': (build: () => const KycSuccessPage(), args: null, profile: false, interact: null),
    'KycPending': (build: () => const KycPendingPage(), args: null, profile: false, interact: null),
    'Rejection': (build: () => const RejectionPage(), args: {
      'reason': 'Your driving licence photo is blurred and the expiry date cannot be read. The RC book name does '
          'not match the name on your Aadhaar card. Please upload clear photos of both and resubmit.',
      'driver': {'name': _longName}}, profile: false, interact: null),
    'Home offline': (build: () => const HomePage(), args: null, profile: true, interact: (t) async {
      await t.tap(find.text('Today').first, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 200));
    }),
    'IncomingRequests': (build: () => const IncomingRequestsPage(), args: null, profile: false, interact: null),
    'IncomingRequests single': (build: () => const IncomingRequestsPage(), args: null, profile: false, interact: null),
    'OnRide to pickup': (build: () => const OnRidePage(), args: _ride(), profile: false, interact: null),
    'OnRide on trip': (build: () => const OnRidePage(), args: _ride(status: 'ongoing'), profile: false, interact: null),
    'RentalProgress': (build: () => RentalProgressPage(ride: _ride(service: 'rental', status: 'ongoing')),
        args: null, profile: false, interact: null),
    'HireProgress': (build: () => HireProgressPage(ride: _ride(service: 'hire_driver', status: 'ongoing')),
        args: null, profile: false, interact: null),
    'DeliveryProgress': (build: () => DeliveryProgressPage(ride: _ride(service: 'delivery', status: 'ongoing', cod: 99999)),
        args: null, profile: false, interact: null),
    'CollectFare': (build: () => const CollectFarePage(amount: 1249999), args: null, profile: false, interact: null),
    'Account': (build: () => const AccountPage(), args: null, profile: true, interact: (t) async {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -2000), warnIfMissed: false);
      await t.pump();
    }),
    'Earnings': (build: () => const EarningsPage(), args: null, profile: false, interact: (t) async {
      await _tapText(t, 'Week');
      await _tapText(t, 'Month');
    }),
    'Wallet': (build: () => const WalletPage(), args: null, profile: false, interact: null),
    'Withdraw': (build: () => const WithdrawPage(balance: 1249999.75), args: null, profile: false, interact: null),
    'History': (build: () => const HistoryPage(), args: null, profile: false, interact: null),
    'TripDetail': (build: () => const TripDetailPage(trip: trip), args: null, profile: false, interact: null),
    'Documents': (build: () => const DocumentsPage(), args: null, profile: true, interact: null),
    'Settings': (build: () => const SettingsPage(), args: null, profile: false, interact: null),
    'DriverLevels': (build: () => const DriverLevelsPage(), args: null, profile: true, interact: null),
    'Rewards': (build: () => const RewardsPage(), args: null, profile: false, interact: null),
  };

  group('captain UI redesign - no overflow with real-shaped data', () {
    for (final size in _sizes) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      screens.forEach((name, s) {
        testWidgets('$name $tag', (tester) async {
          if (name.startsWith('Kyc')) _status = 'pending';
          if (name == 'IncomingRequests single') _singleRequest = true;
          final o = await _overflows(tester, s.build(), size,
              args: s.args, withProfile: s.profile, interact: s.interact);
          expect(o, isEmpty, reason: '$name overflowed at $tag: $o');
        });
      });
    }
  });

  testWidgets('home shows real earnings, the GO button and the low-balance banner', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      final dp = DriverProvider();
      await dp.loadProfile();
      await tester.pumpWidget(_wrap(const HomePage(), dp: dp));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('₹ 1249999'), findsOneWidget, reason: "today's earnings from /rides/driver/summary");
      expect(find.text('GO'), findsOneWidget);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Low wallet balance'), findsOneWidget, reason: 'wallet is negative');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }, () => _api);
    while (tester.takeException() != null) {}
  });

  testWidgets('registration steps carry the 5-step checklist header', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      for (final (screen, step) in [
        (const PersonalDetailsPage(), 'Step 1 of 5'),
        (const VehicleSelectionPage(), 'Step 3 of 5'),
        (const DocumentUploadPage(), 'Step 4 of 5'),
        (const BankDetailsPage(), 'Step 5 of 5'),
      ]) {
        await tester.pumpWidget(KeyedSubtree(key: ValueKey(step), child: _wrap(screen, args: {'phone': '9876543210'})));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(step), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => _api);
    while (tester.takeException() != null) {}
  });
}
