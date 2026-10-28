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
import 'package:customer_app/screens/hire_driver_booking_details_screen.dart';
import 'package:customer_app/screens/hire_driver_screen.dart';
import 'package:customer_app/screens/inquiry_screen.dart';
import 'package:customer_app/screens/outstation_ride_details_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/parcel_booking_details_screen.dart';
import 'package:customer_app/screens/parcel_booking_screen.dart';
import 'package:customer_app/screens/rental_booking_details_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/widgets/ride_ui/ride_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The service booking screens after the Uber-style redesign: parcel, rental,
// intercity, hire a driver, inquiry and the booking summaries.
//
//  * Overflow sweep with REAL (mocked) data loaded — vehicle lists, packages,
//    long addresses — at 320x568, 360x640 and 412x915, scrolled end to end so
//    every lazily built row is laid out.
//  * The redesigned controls still drive the same state: Send / Receive, the
//    hours stepper, trip type, transmission, COD, the CTA price.
//  * Summary pages show only what they were given — no invented driver, plate
//    or parcel PIN.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

const _rajkot = 'Guruprasad Appartment, Sadar, Rajkot, Gujarat 360001, India';
const _ahmedabad = 'Ahmedabad, Gujarat, India';

Map<String, dynamic> _v(String name, int cap, int fare) => {
  'name': name, 'capacity': cap, 'fare': fare, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-$name',
  'perHour': 150,
  'breakdown': {'base': 300, 'perKm': 14, 'kmCharge': 2800, 'nightHalt': 0, 'emptyReturn': 0, 'extraKmRate': 13},
};

Map<String, dynamic> _pkg(String vehicle, int hours, int km, int price) => {
  'vehicleTypeName': vehicle, 'hours': hours, 'km': km, 'basePrice': price, 'capacity': 4,
  'extraHourRate': 180, 'extraKmRate': 14, 'imageUrl': '',
};

Future<http.Response> _handle(http.Request req) async {
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
      _pkg('Auto', 4, 40, 500), _pkg('Cab', 4, 40, 848), _pkg('Cab', 8, 80, 1600), _pkg('Prime Sedan', 4, 40, 1100),
    ]});
  }
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 220, 'oneWayMin': 241, 'vehicles': [
      _v('Bike', 1, 90), _v('Cab', 4, 3431), _v('Prime Sedan', 4, 3981), _v('Prime SUV', 6, 4983),
    ]});
  }
  if (p.endsWith('/directions')) {
    return _json({'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@', 'durationMin': 241, 'distanceKm': 220});
  }
  if (p.endsWith('/rides/user')) {
    return _json({'rides': [
      {'_id': 'p1', 'service': 'delivery', 'status': 'completed', 'deliveryPhase': 'delivered', 'fare': 120,
        'itemType': 'Documents', 'receiverName': 'Meera', 'pickupAddress': _rajkot, 'dropAddress': _ahmedabad},
    ]});
  }
  if (p.endsWith('/rides/delivery/incoming')) {
    return _json({'rides': [
      {'_id': 'p2', 'service': 'delivery', 'status': 'accepted', 'deliveryPhase': 'in_transit', 'fare': 90,
        'itemType': 'Food', 'senderName': 'Ravi', 'dropOtp': '4821', 'pickupAddress': _rajkot, 'dropAddress': _ahmedabad},
    ]});
  }
  return _json({});
}

final _api = MockClient(_handle);

Widget _app(Widget home, {UserProvider? user}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => user ?? UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: home),
);

Future<void> wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await wait(tester, 1000);
  while (tester.takeException() != null) {}
}

/// Runs [body] while collecting layout overflows (and only those).
Future<List<String>> _collectOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('RenderFlex')) {
      final info = (details.informationCollector?.call() ?? const [])
          .map((n) => n.toStringDeep())
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      debugPrint('OVERFLOW>> ${text.split('\n').first} :: ${info.length > 2500 ? info.substring(0, 2500) : info}');
      overflows.add(text.split('\n').first);
      return;
    }
    previous?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

/// Scrolls the biggest vertical list on screen to its end, a page at a time.
Future<void> _scrollThrough(WidgetTester tester) async {
  final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  if (lists.evaluate().isEmpty) return;
  var best = lists.first;
  var bestH = 0.0;
  for (var i = 0; i < lists.evaluate().length; i++) {
    final h = tester.getSize(lists.at(i)).height;
    if (h > bestH) { bestH = h; best = lists.at(i); }
  }
  for (var i = 0; i < 14; i++) {
    await tester.drag(best, const Offset(0, -260), warnIfMissed: false);
    await wait(tester, 200);
  }
}

const _sizes = [Size(320, 568), Size(360, 640), Size(412, 915)];

/// A signed-in rider whose profile prefills the parcel's sender.
UserProvider _rider() => UserProvider()..setUser({'name': 'Yash Kathiriya', 'phone': '9876500000'});

/// Taps [f], scrolling the page down to it first when the lazy list has not
/// built it yet.
Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final page = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(f, 150, scrollable: page, maxScrolls: 20);
    } catch (_) {
      await tester.scrollUntilVisible(f, -150, scrollable: page, maxScrolls: 40);
    }
  }
  await tester.ensureVisible(f);
  await wait(tester, 200);
  await tester.tap(f);
  await wait(tester, 300);
}

/// Parcel Send tab: drop → receiver → item type → [vehicle]. Pickup comes from
/// the (mocked) GPS fix, the sender from the profile.
Future<void> _setParcelDrop(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
  await wait(tester, 800);
  await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
  await wait(tester, 800);
}

Future<void> _fillParcel(WidgetTester tester, {required String vehicle, bool receiver = true, bool item = true}) async {
  await _setParcelDrop(tester);
  if (receiver) {
    await _tapVisible(tester, find.text('Add receiver contact'));
    await wait(tester, 400);
    await tester.enterText(find.widgetWithText(TextField, 'Receiver name'), 'Meera Patel');
    await tester.enterText(find.widgetWithText(TextField, 'Receiver phone'), '9123456780');
    await tester.tap(find.text('Done'));
    await wait(tester, 600);
  }
  if (item) await _tapVisible(tester, find.text('Documents'));
  await _tapVisible(tester, find.text(vehicle));
}

ElevatedButton _ctaButton(WidgetTester tester, String label) =>
    tester.widget<ElevatedButton>(find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

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

  // ── Overflow sweep, data loaded ──
  group('no overflow with data loaded', () {
    final screens = <String, Widget Function()>{
      'parcel': () => const ParcelBookingScreen(),
      'rental': () => const RentalScreen(),
      'hire driver': () => const HireDriverScreen(),
      'intercity (where to)': () => const OutstationScreen(),
      'inquiry': () => const InquiryScreen(),
      'rental summary': () => const RentalBookingDetailsScreen(
        inquiryId: 'RNT48213', pickupLocation: _rajkot, dropLocation: _ahmedabad, duration: '8 Hours',
        vehicle: 'Prime Sedan', price: '₹1600', date: '28/10/2026', time: '9:00 AM',
        driverName: 'Ramesh Chandra Kumar', driverPhone: '+91 98765 43210', vehicleNumber: 'GJ03 AB 4521',
        vehicleModel: 'Maruti Suzuki Dzire', vehicleColor: 'White'),
      'hire summary': () => const HireDriverBookingDetailsScreen(
        inquiryId: 'HRD8A21F0', pickupLocation: _rajkot, dropLocation: _ahmedabad, carType: 'Prime Sedan',
        hireDuration: '10 hr', package: '1 Day', price: '₹1500', tripStartDate: '28/10/2026', tripTime: '9:00 AM',
        tripType: 'round_trip', gearType: 'Automatic', driverName: 'Ramesh', vehicleNumber: 'GJ03 AB 4521'),
      'intercity summary': () => const OutstationRideDetailsScreen(
        inquiryId: 'OUT1234', fromLocation: _rajkot, toLocation: _ahmedabad, vehicleName: 'Prime SUV',
        vehicleType: 'Spacious', capacity: '6', tripType: 'Round Trip', departureDate: '28/10/2026',
        departureTime: '6:00 AM', returnDate: '30/10/2026', returnTime: '8:00 PM', price: '₹4983',
        estimatedDistance: '220 km', estimatedDuration: '4h 01m', driverName: 'Ramesh', vehicleNumber: 'GJ03 AB 4521'),
      'parcel summary': () => const ParcelBookingDetailsScreen(
        inquiryId: 'PRC77', pickupLocation: _rajkot, dropLocation: _ahmedabad, itemType: 'Electronics',
        weight: '4', vehicle: 'Bike', receiverName: 'Meera Patel', receiverPhone: '9876543210', imagePaths: []),
    };
    for (final size in _sizes) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';
      screens.forEach((name, build) {
        testWidgets('$name $tag', (tester) async {
          _size(tester, size);
          final o = await _collectOverflows(() => http.runWithClient(() async {
            await tester.pumpWidget(_app(build()));
            await wait(tester, 1200);
            await _scrollThrough(tester);
          }, () => _api));
          expect(o, isEmpty, reason: '$name overflowed at $tag');
          await _teardown(tester);
        });
      });

      testWidgets('intercity vehicle sheet + confirm $tag', (tester) async {
        _size(tester, size);
        final o = await _collectOverflows(() => http.runWithClient(() async {
          await tester.pumpWidget(_app(const OutstationScreen()));
          await wait(tester, 800);
          await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
          await wait(tester, 800);
          await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
          await wait(tester, 400);
          await tester.tap(find.text('Confirm Location'));
          await wait(tester, 1500);
          final sheet = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
          await tester.drag(find.byType(RouteInputBlock), const Offset(0, -500), warnIfMissed: false);
          await wait(tester, 600);
          await tester.ensureVisible(find.text('Select Vehicle'));
          await wait(tester, 300);
          await tester.tap(find.text('Select Vehicle'));
          await wait(tester, 500);
          await tester.scrollUntilVisible(find.text('Prime SUV'), 150, scrollable: sheet);
          await tester.drag(sheet, const Offset(0, -120), warnIfMissed: false);
          await wait(tester, 300);
          await tester.tap(find.text('Prime SUV'));
          await wait(tester, 300);
          await _scrollThrough(tester);
          await tester.tap(find.text('Book Trip'));
          await wait(tester, 800);
          await _scrollThrough(tester);
        }, () => _api));
        expect(o, isEmpty, reason: 'intercity overflowed at $tag');
        await _teardown(tester);
      });

      testWidgets('parcel receive tab $tag', (tester) async {
        _size(tester, size);
        final o = await _collectOverflows(() => http.runWithClient(() async {
          await tester.pumpWidget(_app(const ParcelBookingScreen()));
          await wait(tester, 800);
          await tester.tap(find.text('Receive Parcel'));
          await wait(tester, 800);
          await _scrollThrough(tester);
        }, () => _api));
        expect(o, isEmpty, reason: 'parcel receive overflowed at $tag');
        await _teardown(tester);
      });

      testWidgets('parcel filled form, More options open, confirm sheet $tag', (tester) async {
        _size(tester, size);
        final o = await _collectOverflows(() => http.runWithClient(() async {
          await tester.pumpWidget(_app(const ParcelBookingScreen(), user: _rider()));
          await wait(tester, 1000);
          await _fillParcel(tester, vehicle: 'Prime SUV');
          await _tapVisible(tester, find.textContaining('More options'));
          await _tapVisible(tester, find.text('COD'));
          await _scrollThrough(tester);
          await _tapVisible(tester, find.text('Book Prime SUV · ₹4983'));
          await wait(tester, 600);
          await _scrollThrough(tester);
        }, () => _api));
        expect(o, isEmpty, reason: 'parcel filled form overflowed at $tag');
        await _teardown(tester);
      });
    }
  });

  // ── The controls still drive the same state ──
  group('parcel', () {
    testWidgets('Send / Receive switches the page; Receive lists sent + incoming', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 800);
        expect(find.text('Send a parcel'), findsOneWidget);
        await tester.tap(find.text('Receive Parcel'));
        await wait(tester, 800);
      }, () => _api);
      expect(find.text('Receive a parcel'), findsOneWidget);
      expect(find.text('Incoming to you'), findsOneWidget);
      expect(find.text('Sent by you'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget, reason: 'the receiver still sees their drop OTP');
      await _teardown(tester);
    });

    testWidgets('sender is prefilled from the profile; extras start under a closed More options', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen(), user: _rider()));
        await wait(tester, 1000);
      }, () => _api);
      expect(find.text('Yash Kathiriya · 9876500000'), findsOneWidget, reason: 'sender prefilled from UserProvider');
      // Receiver row only after a drop is chosen.
      expect(find.text('Add receiver contact'), findsNothing);
      // Nothing optional is on screen until More options is opened.
      for (final t in const ['COD', 'Handle with extra care', 'Package size', 'Item value ₹ (for insurance)', 'Pickup time', 'Add photo']) {
        expect(find.text(t, skipOffstage: false), findsNothing, reason: '$t should be under More options');
      }
      await tester.scrollUntilVisible(find.text('More options'), 150, scrollable: find.byType(Scrollable).first);
      // No weight picker (Ola / Rapido style) — just the one limits line.
      expect(find.text('Weight'), findsNothing);
      expect(find.text('Max 20 kg · must fit in a backpack · no illegal, alcohol or restricted items'), findsOneWidget);
      expect(find.textContaining('kg'), findsOneWidget, reason: 'the limits line is the only weight text');
      // No item type is chosen for the rider.
      ServiceChip chip(String l) => tester.widget<ServiceChip>(find.widgetWithText(ServiceChip, l));
      expect(chip('Documents').selected, isFalse);
      await _teardown(tester);
    });

    testWidgets('More options reveals COD and its amount; the header says COD is on', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 1000);
        await _tapVisible(tester, find.text('More options'));
        expect(find.text('COD amount ₹ (receiver pays)', skipOffstage: false), findsNothing);
        await _tapVisible(tester, find.text('COD'));
      }, () => _api);
      expect(find.text('COD amount ₹ (receiver pays)', skipOffstage: false), findsOneWidget);
      expect(find.text('More options · COD'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('CTA stays disabled until drop, receiver, item and vehicle are set; weightKg is always 0', (tester) async {
      _size(tester, const Size(392, 850));
      final estimates = <Map<String, dynamic>>[];
      Map<String, dynamic>? booked;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/fare/estimate')) estimates.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (req.url.path.endsWith('/rides/book')) {
          booked = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'error': 'stop here'});
        }
        return _handle(req);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen(), user: _rider()));
        await wait(tester, 1000);
        expect(_ctaButton(tester, 'Add drop location').onPressed, isNull);
        expect(estimates.last['weightKg'], 0, reason: 'no per-kg charge');

        // Drop + vehicle, but no receiver and no item yet.
        await _setParcelDrop(tester);
        expect(find.text('Receiver · required'), findsOneWidget);
        await _tapVisible(tester, find.text('Bike'));
        // The disabled button names what is missing.
        expect(_ctaButton(tester, 'Add receiver details').onPressed, isNull);

        await _tapVisible(tester, find.text('Documents'));
        expect(_ctaButton(tester, 'Add receiver details').onPressed, isNull, reason: 'receiver still missing');

        expect(estimates, isNotEmpty);
        expect(estimates.every((e) => e['weightKg'] == 0), isTrue, reason: 'every quote sends weightKg 0');

        await _tapVisible(tester, find.text('Add receiver contact'));
        await tester.enterText(find.widgetWithText(TextField, 'Receiver name'), 'Meera Patel');
        expect(_ctaButton(tester, 'Add receiver details').onPressed, isNull, reason: 'phone still missing');
        await tester.enterText(find.widgetWithText(TextField, 'Receiver phone'), '9123456780');
        await tester.tap(find.text('Done'));
        await wait(tester, 600);
        expect(find.text('Meera Patel · 9123456780'), findsOneWidget);
        expect(_ctaButton(tester, 'Book Bike · ₹90').onPressed, isNotNull);

        await tester.tap(find.text('Book Bike · ₹90'));
        await wait(tester, 600);
        expect(find.text('Confirm parcel'), findsOneWidget);
        final sheet = find.byType(BottomSheet);
        expect(find.descendant(of: sheet, matching: find.textContaining('kg')), findsNothing, reason: 'no weight on the confirm sheet');
        expect(find.descendant(of: sheet, matching: find.text('Documents')), findsWidgets, reason: 'the item type is shown instead');
        await tester.tap(find.text('Confirm & Find Driver'));
        await wait(tester, 800);
      }, () => client);
      expect(booked, isNotNull);
      expect(booked!['weightKg'], 0);
      expect(booked!['service'], 'delivery');
      expect(booked!['vehicleType'], 'Bike');
      expect(booked!['itemType'], 'Documents');
      expect(booked!['senderName'], 'Yash Kathiriya');
      expect(booked!['senderPhone'], '9876500000');
      expect(booked!['receiverName'], 'Meera Patel');
      expect(booked!['receiverPhone'], '9123456780');
      expect(booked!['quoteToken'], 'q-Bike');
      expect(booked!['codAmount'], 0);
      expect(booked!['packageSize'], 'S');
      expect(booked!['isFragile'], false);
      await _teardown(tester);
    });

    testWidgets('item type chips select one at a time', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 800);
        await tester.ensureVisible(find.text('Electronics'));
        await wait(tester, 200);
        await tester.tap(find.text('Electronics'));
        await wait(tester, 200);
      }, () => _api);
      ServiceChip chip(String l) => tester.widget<ServiceChip>(find.widgetWithText(ServiceChip, l));
      expect(chip('Electronics').selected, isTrue);
      expect(chip('Documents').selected, isFalse);
      await _teardown(tester);
    });
  });

  group('rental', () {
    testWidgets('stepper moves the hours, the rows and the CTA price follow the package', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RentalScreen()));
        await wait(tester, 1000);
        await tester.scrollUntilVisible(find.text('Cab'), 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.text('Cab'));
        await wait(tester, 200);
        await tester.tap(find.text('Cab'));
        await wait(tester, 200);
      }, () => _api);
      // 4 hr package of ₹848 → ₹212/hr × 4.
      expect(find.text('Book Package · ₹848'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase'));
      await wait(tester, 200);
      // 5 hr → nearest package is still 4 hr (₹212/hr) → ₹1060, 50 km.
      expect(find.text('Book Package · ₹1060'), findsOneWidget);
      expect(find.text('5 hr / 50 km'), findsWidgets);
      await tester.tap(find.byTooltip('Decrease'));
      await tester.tap(find.byTooltip('Decrease'));
      await wait(tester, 200);
      expect(find.text('Book Package · ₹636'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('confirm sheet shows the package\'s own extra rates, not made-up ones', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RentalScreen()));
        await wait(tester, 1000);
        await tester.scrollUntilVisible(find.text('Cab'), 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.text('Cab'));
        await wait(tester, 200);
        await tester.tap(find.text('Cab'));
        await wait(tester, 200);
        await tester.tap(find.text('Book Package · ₹848'));
        await wait(tester, 600);
      }, () => _api);
      expect(find.text('Confirm your rental'), findsOneWidget);
      expect(find.text('₹14/km'), findsOneWidget);
      expect(find.text('₹180/hr'), findsOneWidget);
      await tester.ensureVisible(find.text('Additional Charges'));
      await tester.tap(find.text('Additional Charges'));
      await wait(tester, 300);
      expect(find.textContaining('₹10/km'), findsNothing);
      expect(find.textContaining('₹100/hr'), findsNothing);
      expect(find.text('Beyond 40 km: ₹14/km'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('hire a driver', () {
    testWidgets('trip type and transmission are one-of choices with the right note', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const HireDriverScreen()));
        await wait(tester, 800);
      }, () => _api);
      expect(find.textContaining('you also pay the driver\'s return charge'), findsOneWidget);
      await tester.tap(find.text('Round Trip'));
      await wait(tester, 200);
      expect(find.textContaining('no extra return charge'), findsOneWidget);
      ChoiceSegment<String> seg(String label) => tester.widget<ChoiceSegment<String>>(
          find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ChoiceSegment<String>)));
      expect(seg('Round Trip').selected, 'round_trip');
      await tester.scrollUntilVisible(find.text('Automatic'), 150, scrollable: find.byType(Scrollable).first);
      expect(seg('Manual').selected, 'manual');
      await tester.tap(find.text('Automatic'));
      await wait(tester, 200);
      expect(seg('Automatic').selected, 'automatic');
      expect(find.text('Select time & vehicle'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('intercity', () {
    testWidgets('the confirmed sheet offers adding a stop, and the stop is listed on the route', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const OutstationScreen()));
        await wait(tester, 800);
        expect(find.text('Intercity'), findsOneWidget);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
        await wait(tester, 400);
        await tester.tap(find.text('Confirm Location'));
        await wait(tester, 1500);
        expect(find.text('220 km · 4h 01m'), findsOneWidget);
        await tester.tap(find.text('Add city / stop'));
        await wait(tester, 500);
        await tester.enterText(find.byType(TextField).last, 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad').last);
        await wait(tester, 1200);
      }, () => _api);
      expect(find.byTooltip('Remove stop'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('summaries show only real data', () {
    testWidgets('no invented driver, car or parcel PIN', (tester) async {
      _size(tester, const Size(392, 850));
      await tester.pumpWidget(_app(const ParcelBookingDetailsScreen(
        inquiryId: 'PRC77', pickupLocation: _rajkot, dropLocation: _ahmedabad, itemType: 'Electronics',
        weight: '4', vehicle: 'Bike', receiverName: 'Meera Patel', receiverPhone: '9876543210', imagePaths: [])));
      await tester.pump();
      expect(find.text('5294'), findsNothing);
      expect(find.text('Hero Splendor'), findsNothing);
      expect(find.text('Driver Details'), findsNothing);
      expect(find.text('Meera Patel'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.pumpWidget(_app(const RentalBookingDetailsScreen(
        inquiryId: 'RNT1', pickupLocation: _rajkot, dropLocation: _ahmedabad, duration: '4 Hours',
        vehicle: 'Cab', price: '₹848', date: '28/10/2026', time: '9:00 AM', driverName: 'Ramesh',
        vehicleNumber: 'GJ03 AB 4521')));
      await tester.pump();
      expect(find.text('Ramesh'), findsOneWidget);
      expect(find.text('GJ03 AB 4521'), findsOneWidget);
      expect(find.textContaining('4.9'), findsNothing);
      expect(find.textContaining('8 years'), findsNothing);
      expect(find.text('Maruti Swift Dzire'), findsNothing);
      expect(find.byTooltip('Call driver'), findsNothing, reason: 'no phone, no call button');
      expect(find.text('Back to Home'), findsOneWidget);
    });
  });
}
