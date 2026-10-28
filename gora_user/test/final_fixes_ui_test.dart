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
import 'package:customer_app/screens/inquiry_screen.dart';
import 'package:customer_app/screens/invoice_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/parcel_booking_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/screens/ride_history_screen.dart';
import 'package:customer_app/screens/trip_detail_screen.dart';
import 'package:customer_app/theme/app_theme.dart';
import 'package:customer_app/utils/fare_lines.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fixes from the final emulator run against production:
//  1. the intercity fare breakdown adds up to the quoted total;
//  2. "Your trips" lists every ride the API returns, parcels included;
//  3. the invoice in the new style;
//  4. rental confirm says when it really starts and that drop is optional;
//  5. the inquiry form is prefilled from the profile;
//  6. the parcel CTA names what is missing; the contact sheet is keyboard-safe.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

const _rajkot = 'Guruprasad Appartment, Sadar, Rajkot, Gujarat 360001, India';
const _ahmedabad = 'Ahmedabad, Gujarat, India';

/// The production quote from the emulator run: 300 + 2204 + 300 + 626 = 3430.
final _cabQuote = {
  'name': 'Cab', 'capacity': 4, 'fare': 3430, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-cab',
  'emptyReturnPercent': 25,
  'breakdown': {
    'totalKm': 220.4, 'totalHrs': 4, 'base': 300, 'perKm': 10, 'perHour': 0, 'kmCharge': 2204, 'hourCharge': 0,
    'tripType': 'one_way', 'kmLimit': 0, 'extraKmRate': 0, 'days': 1,
    'emptyReturn': 626, 'driverAllowance': 300, 'total': 3430,
  },
};

Map<String, dynamic> _ride(String id, String service, String status, int fare, {Map<String, dynamic> extra = const {}}) => {
  '_id': id, 'service': service, 'status': status, 'fare': fare, 'totalFare': fare,
  'pickupAddress': _rajkot, 'dropAddress': 'Race Course, Sadar, Rajkot, Gujarat 360001, India',
  'pickupLat': 22.30, 'pickupLng': 70.80, 'dropLat': 22.29, 'dropLng': 70.79,
  'vehicleType': 'Cab', 'paymentMode': 'cash', 'createdAt': '2026-10-27T10:29:00.000Z',
  ...extra,
};

final _history = [
  _ride('r1', 'taxi', 'completed', 90, extra: {'driver': {'name': 'Demo Driver', 'vehicleModel': 'Maruti Dzire', 'vehicleNumber': 'GJ03AB1234', 'rating': 5}}),
  _ride('r2', 'taxi', 'completed', 110),
  _ride('r3', 'delivery', 'completed', 40, extra: {'receiverName': 'Meera Patel', 'itemType': 'Documents', 'vehicleType': 'Bike'}),
  _ride('r4', 'rental', 'completed', 848, extra: {'packageHours': 4}),
  _ride('r5', 'outstation', 'cancelled', 3430, extra: {'dropAddress': _ahmedabad}),
  _ride('r6', 'hire_driver', 'pending', 600, extra: {'hireTotalHours': 4}),
  // A record with fields of unexpected types must not hide the others.
  {'_id': 'bad', 'service': 'taxi', 'status': 'completed', 'fare': 70, 'pickupLat': 'x'},
];

final _api = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/places/reverse')) return _json({'address': _rajkot});
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'amd', 'description': _ahmedabad, 'mainText': 'Ahmedabad', 'secondaryText': 'Gujarat, India'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 23.0225, 'lng': 72.5714, 'address': _ahmedabad});
  if (p.endsWith('/rides/user')) return _json({'rides': _history});
  if (p.endsWith('/rental/packages')) {
    return _json({'available': true, 'packages': [
      {'vehicleTypeName': 'Cab', 'hours': 4, 'km': 40, 'basePrice': 848, 'capacity': 4, 'extraHourRate': 180, 'extraKmRate': 14, 'imageUrl': ''},
    ]});
  }
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 220, 'oneWayMin': 241, 'vehicles': [_cabQuote]});
  }
  if (p.endsWith('/directions')) return _json({'polyline': '', 'durationMin': 241, 'distanceKm': 220});
  return _json({});
});

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

Future<List<String>> _overflows(Future<void> Function() body) async {
  final out = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    final t = d.exceptionAsString();
    if (t.contains('overflowed') || t.contains('RenderFlex')) {
      out.add(t.split('\n').first);
      return;
    }
    previous?.call(d);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return out;
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
  }
  await tester.ensureVisible(f);
  await wait(tester, 200);
  await tester.tap(f);
  await wait(tester, 300);
}

const _sizes = [Size(320, 568), Size(360, 640), Size(412, 915)];

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

  // ── 1. Intercity breakdown ──
  group('intercity fare lines add up to the quoted total', () {
    num sum(List<FareLine> l) => l.fold<num>(0, (a, x) => a + x.amount);

    test('the production quote: empty return is its own line', () {
      final lines = outstationFareLines(_cabQuote['breakdown'] as Map, 3430, emptyReturnPercent: 25);
      expect(lines.map((l) => l.label), [
        'Base fare', 'Fare for 220 km @ ₹10/km', 'Empty return (25%)', 'Driver allowance',
      ]);
      expect(lines.map((l) => l.amount), [300, 2204, 626, 300]);
      expect(sum(lines), 3430);
    });

    test('night halt, multi-day allowance and GST are itemised', () {
      final bk = {'totalKm': 400, 'base': 500, 'perKm': 12, 'kmCharge': 4800, 'perHour': 0, 'nightHalt': 300, 'nights': 1,
        'driverAllowance': 600, 'days': 2, 'gst': 310, 'gstPercent': 5};
      final lines = outstationFareLines(bk, 6510);
      expect(lines.map((l) => l.label), contains('GST (5%)'));
      expect(lines.map((l) => l.label), contains('Driver allowance (2 days)'));
      expect(lines.map((l) => l.label), contains('Night halt'));
      expect(lines.any((l) => l.label == 'Other charges'), isFalse);
      expect(sum(lines), 6510);
    });

    test('a component the breakdown does not itemise shows as "Other charges"; the total is never changed', () {
      // e.g. the minimum-fare top-up
      final lines = outstationFareLines({'base': 300, 'perKm': 10, 'kmCharge': 500}, 1000, distanceKm: 50);
      expect(lines.last.label, 'Other charges');
      expect(lines.last.amount, 200);
      expect(sum(lines), 1000);
    });

    testWidgets('confirm sheet lists every line and they sum to the total', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const OutstationScreen()));
        await wait(tester, 800);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
        await wait(tester, 400);
        await tester.tap(find.text('Confirm Location'));
        await wait(tester, 1500);
        final sheet = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first;
        await tester.drag(sheet, const Offset(0, -500), warnIfMissed: false);
        await wait(tester, 500);
        await tester.ensureVisible(find.text('Select Vehicle'));
        await tester.tap(find.text('Select Vehicle'));
        await wait(tester, 400);
        await tester.scrollUntilVisible(find.text('Cab'), 150, scrollable: sheet);
        await tester.drag(sheet, const Offset(0, -150), warnIfMissed: false);
        await wait(tester, 300);
        await tester.tap(find.text('Cab'));
        await wait(tester, 300);
        await tester.tap(find.text('Book Trip'));
        await wait(tester, 800);
      }, () => _api);
      for (final t in ['₹300', '₹2204', '₹626']) {
        expect(find.text(t, skipOffstage: false), findsWidgets, reason: t);
      }
      expect(find.text('Empty return (25%)', skipOffstage: false), findsOneWidget);
      expect(find.text('Driver allowance', skipOffstage: false), findsOneWidget);
      expect(find.text('Other charges', skipOffstage: false), findsNothing, reason: 'nothing left unexplained');
      await _teardown(tester);
    });
  });

  // ── 2. Your trips ──
  group('your trips', () {
    testWidgets('every ride from the API is listed, parcels included, newest style rows', (tester) async {
      _size(tester, const Size(412, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RideHistoryScreen()));
        await wait(tester, 800);
      }, () => _api);
      expect(find.text('Your trips'), findsOneWidget);
      expect(find.text('Trip Details'), findsNothing);
      for (final id in ['r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'bad']) {
        expect(find.byKey(ValueKey('trip-$id')), findsOneWidget, reason: id);
      }
      expect(find.text('Parcel to Meera Patel'), findsOneWidget);
      expect(find.text('Rental · 4 hr'), findsOneWidget);
      expect(find.text('₹110'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      for (final fake in ['Suresh Kumar', 'DL 01 AB 1234', 'MG Road, Delhi']) {
        expect(find.textContaining(fake), findsNothing, reason: fake);
      }
      // Filter chips narrow the list.
      await tester.tap(find.text('Parcels'));
      await tester.pump();
      expect(find.byKey(const ValueKey('trip-r3')), findsOneWidget);
      expect(find.byKey(const ValueKey('trip-r1')), findsNothing);
      await _teardown(tester);
    });

    testWidgets('a row opens the trip, the invoice button opens the invoice', (tester) async {
      _size(tester, const Size(412, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RideHistoryScreen()));
        await wait(tester, 800);
        await tester.tap(find.byKey(const ValueKey('trip-r2')));
        await wait(tester, 600);
        expect(find.byType(TripDetailScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(TripDetailScreen))).pop();
        await wait(tester, 600);
        await tester.tap(find.descendant(of: find.byKey(const ValueKey('trip-r2')), matching: find.text('Invoice')));
        await wait(tester, 600);
      }, () => _api);
      expect(find.byType(InvoiceScreen), findsOneWidget);
      await _teardown(tester);
    });

    for (final s in _sizes) {
      testWidgets('no overflow ${s.width.toInt()}x${s.height.toInt()}', (tester) async {
        _size(tester, s);
        final o = await _overflows(() => http.runWithClient(() async {
          await tester.pumpWidget(_app(const RideHistoryScreen()));
          await wait(tester, 800);
          for (var i = 0; i < 10; i++) {
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
            await wait(tester, 200);
          }
        }, () => _api));
        expect(o, isEmpty);
        await _teardown(tester);
      });
    }
  });

  // ── 3. Invoice ──
  group('invoice', () {
    for (final s in _sizes) {
      testWidgets('new style, bold total, no overflow ${s.width.toInt()}x${s.height.toInt()}', (tester) async {
        _size(tester, s);
        final o = await _overflows(() => http.runWithClient(() async {
          await tester.pumpWidget(_app(InvoiceScreen(ride: const {
            'id': '', 'from': _rajkot, 'to': _ahmedabad, 'date': '27/10/2026, 15:59', 'driver': 'Demo Driver',
            'driverVehicleModel': 'Maruti Dzire', 'driverVehicleNumber': 'GJ03AB1234', 'vehicle': 'Cab',
            'distance': 3.7, 'paymentMode': 'cash', 'baseFare': 90, 'tip': 10, 'total': 100, 'service': 'taxi',
          })));
          await wait(tester, 400);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -600), warnIfMissed: false);
          await wait(tester, 300);
        }, () => _api));
        expect(o, isEmpty);
        final total = tester.widget<Text>(find.text('₹100'));
        expect(total.style?.fontWeight, FontWeight.w900);
        expect(total.style?.color, isNot(Colors.blue), reason: 'the total is black, not the old blue');
        await _teardown(tester);
      });
    }
  });

  // ── 4. Rental confirm ──
  testWidgets('rental confirm: starts now, drop is optional', (tester) async {
    _size(tester, const Size(392, 850));
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const RentalScreen()));
      await wait(tester, 1000);
      await _tapVisible(tester, find.text('Cab'));
      await tester.tap(find.text('Book Package · ₹848'));
      await wait(tester, 600);
    }, () => _api);
    expect(find.text('Starting now'), findsOneWidget);
    expect(find.textContaining('Today at Now'), findsNothing);
    expect(find.text('Add destination (optional)'), findsOneWidget);
    expect(find.text('Select destination'), findsNothing);
    await _teardown(tester);
  });

  // ── 5. Inquiry prefill ──
  testWidgets('inquiry is prefilled from the profile, and an edit is kept', (tester) async {
    _size(tester, const Size(392, 850));
    final user = UserProvider()..setUser({'name': 'Yash Kathiriya', 'phone': '9876500000', 'email': 'yash@example.com'});
    await tester.pumpWidget(_app(const InquiryScreen(), user: user));
    await tester.pump();
    String value(String hint) => tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint)).controller!.text;
    expect(value('Enter your full name'), 'Yash Kathiriya');
    expect(value('Enter your mobile number'), '9876500000');
    expect(value('Enter your email'), 'yash@example.com');
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Enter your full name'), 'Someone Else');
    user.setUser({'name': 'Yash Kathiriya', 'phone': '9876500000'});
    await tester.pump();
    expect(value('Enter your full name'), 'Someone Else');
    await _teardown(tester);
  });

  // ── 6. Parcel ──
  group('parcel', () {
    UserProvider rider() => UserProvider()..setUser({'name': 'Yash Kathiriya', 'phone': '9876500000'});

    testWidgets('the disabled CTA names the missing item type', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen(), user: rider()));
        await wait(tester, 1000);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
        await wait(tester, 800);
        await _tapVisible(tester, find.text('Add receiver contact'));
        await wait(tester, 400);
        await tester.enterText(find.widgetWithText(TextField, 'Receiver name'), 'Meera Patel');
        await tester.enterText(find.widgetWithText(TextField, 'Receiver phone'), '9123456780');
        await tester.tap(find.text('Done'));
        await wait(tester, 600);
        await _tapVisible(tester, find.text('Cab'));
      }, () => _api);
      final btn = tester.widget<ElevatedButton>(find.ancestor(of: find.text("Select what you're sending"), matching: find.byType(ElevatedButton)));
      expect(btn.onPressed, isNull);
      await _tapVisible(tester, find.text('Documents'));
      expect(find.text('Book Cab · ₹3430'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('contact sheet: keyboard-safe, opens on the name, "next" moves to phone', (tester) async {
      _size(tester, const Size(392, 850));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen(), user: rider()));
        await wait(tester, 1000);
        await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
        await wait(tester, 800);
        await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
        await wait(tester, 800);
        await _tapVisible(tester, find.text('Add receiver contact'));
        await wait(tester, 400);
      }, () => _api);
      EditableText field(String hint) => tester.widget<EditableText>(find.descendant(
          of: find.widgetWithText(TextField, hint), matching: find.byType(EditableText)));
      expect(field('Receiver name').focusNode.hasFocus, isTrue, reason: 'keyboard opens on the first empty field');
      expect(field('Receiver name').textInputAction, TextInputAction.next);
      await tester.enterText(find.widgetWithText(TextField, 'Receiver name'), 'Meera');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(field('Receiver phone').focusNode.hasFocus, isTrue);

      // The keyboard lifts the whole sheet: the Done button stays above it.
      final before = tester.getRect(find.text('Done')).bottom;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await wait(tester, 400);
      final after = tester.getRect(find.text('Done')).bottom;
      expect(after, lessThanOrEqualTo(850 - 300));
      expect(before - after, closeTo(300, 40));
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  });
}
