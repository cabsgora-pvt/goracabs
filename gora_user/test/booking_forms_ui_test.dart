import 'dart:convert';

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
import 'package:customer_app/screens/hire_driver_screen.dart';
import 'package:customer_app/screens/outstation_screen.dart';
import 'package:customer_app/screens/parcel_booking_screen.dart';
import 'package:customer_app/screens/rental_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Booking forms after the redesign: one clean grey field (no theme outline
// drawn inside the box), and the outstation list — taglines from the real type,
// a section header that opens on one tap, the fare exactly as quoted and a map
// framed on the route rather than under the sheet.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

const _rajkot = 'Guruprasad Appartment, Sadar, Rajkot, Gujarat 360001, India';
const _ahmedabad = 'Ahmedabad, Gujarat, India';

Map<String, dynamic> _v(String name, int cap, int fare) => {
  'name': name, 'capacity': cap, 'fare': fare, 'etaMin': 6, 'imageUrl': '', 'quoteToken': 'q-$name',
  'breakdown': {'base': 300, 'perKm': 14, 'nightHalt': 0, 'emptyReturn': 0},
};

final _api = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/places/reverse')) return _json({'address': _rajkot});
  if (p.endsWith('/places/autocomplete')) {
    return _json({'predictions': [
      {'placeId': 'amd', 'description': _ahmedabad, 'mainText': 'Ahmedabad', 'secondaryText': 'Gujarat, India'},
    ]});
  }
  if (p.endsWith('/places/details')) return _json({'lat': 23.0225, 'lng': 72.5714, 'address': _ahmedabad});
  if (p.endsWith('/fare/estimate')) {
    return _json({'available': true, 'oneWayKm': 220, 'oneWayMin': 241, 'vehicles': [
      _v('Cab', 4, 3431), _v('Prime Sedan', 4, 3981), _v('Prime SUV', 6, 4983),
    ]});
  }
  if (p.endsWith('/directions')) {
    return _json({'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@', 'durationMin': 241, 'distanceKm': 220});
  }
  return _json({});
});

Widget _app(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: home),
);

Future<void> wait(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(392, 850);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await wait(tester, 1000);
  while (tester.takeException() != null) {}
}

Finder _fieldWithHint(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

/// The decoration the field is actually drawn with (theme defaults applied).
InputDecoration _drawn(WidgetTester tester, String hint) {
  final field = _fieldWithHint(hint);
  expect(field, findsOneWidget, reason: 'field "$hint"');
  return tester.widget<InputDecorator>(find.descendant(of: field, matching: find.byType(InputDecorator))).decoration;
}

void _expectSingleField(WidgetTester tester, String hint) {
  final d = _drawn(tester, hint);
  expect(d.enabledBorder, InputBorder.none, reason: '"$hint" drew the theme outline inside its box');
  expect(d.focusedBorder, InputBorder.none, reason: '"$hint" outlines itself when focused');
  expect(d.filled, isNot(true), reason: '"$hint" painted a second fill inside its box');
}

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

  group('single clean field, no outline inside the box', () {
    testWidgets('parcel', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const ParcelBookingScreen()));
        await wait(tester, 800);
      }, () => _api);
      for (final h in const ['Add sender address', 'Add recipient address']) {
        _expectSingleField(tester, h);
      }
      await _teardown(tester);
    });

    testWidgets('hire driver', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const HireDriverScreen()));
        await wait(tester, 800);
      }, () => _api);
      for (final h in const ['Pickup location', 'Drop location']) {
        _expectSingleField(tester, h);
      }
      await _teardown(tester);
    });

    testWidgets('rental: no outline, and the text is neither clipped nor off-centre', (tester) async {
      _phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const RentalScreen()));
        await wait(tester, 800);
      }, () => _api);
      for (final h in const ['Enter pickup location', 'Drop location (optional)']) {
        _expectSingleField(tester, h);
        final field = _fieldWithHint(h);
        final box = tester.getRect(field);
        final text = tester.getRect(find.descendant(of: field, matching: find.byType(EditableText)));
        expect(text.top, greaterThanOrEqualTo(box.top), reason: '"$h" text clipped at the top');
        expect(text.bottom, lessThanOrEqualTo(box.bottom), reason: '"$h" text clipped at the bottom');
        expect((text.center.dy - box.center.dy).abs(), lessThan(1.5), reason: '"$h" not vertically centred');
      }
      await _teardown(tester);
    });
  });

  group('outstation vehicle list', () {
    Future<void> openList(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const OutstationScreen()));
      await wait(tester, 800);
      await tester.enterText(find.byType(TextField).at(1), 'Ahmedabad');
      await wait(tester, 800);
      await tester.tap(find.widgetWithText(ListTile, 'Ahmedabad'));
      await wait(tester, 400);
      await tester.tap(find.text('Confirm Location'));
      await wait(tester, 1500);
    }

    Finder sheetList() => find.ancestor(of: find.text('Trip Details'), matching: find.byType(Scrollable)).first;

    Future<void> openVehicles(WidgetTester tester) async {
      await tester.drag(find.text('Trip Details'), const Offset(0, -520), warnIfMissed: false);
      await wait(tester, 600);
      await tester.ensureVisible(find.text('Select Vehicle'));
      await wait(tester, 300);
      // One tap on the EMPTY middle of the header row, between title and chevron.
      final title = tester.getRect(find.text('Select Vehicle'));
      final row = find.ancestor(of: find.text('Select Vehicle'), matching: find.byType(Row)).first;
      final chevron = tester.getRect(find.descendant(of: row, matching: find.byType(Icon)));
      await tester.tapAt(Offset((title.right + chevron.left) / 2, title.center.dy));
      await wait(tester, 500);
    }

    testWidgets('the header opens on the first tap, anywhere on the row', (tester) async {
      await http.runWithClient(() async {
        await openList(tester);
        await openVehicles(tester);
        await tester.scrollUntilVisible(find.text('Cab'), 150, scrollable: sheetList());
      }, () => _api);
      expect(find.text('Cab'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('taglines come from the type, and the fare is the one quoted', (tester) async {
      await http.runWithClient(() async {
        await openList(tester);
        await openVehicles(tester);
        await tester.scrollUntilVisible(find.text('Prime SUV'), 150, scrollable: sheetList());
        await wait(tester, 300);
      }, () => _api);
      expect(find.text('Top sedans'), findsNothing);
      expect(find.text('Comfortable'), findsOneWidget);   // Cab
      expect(find.text('Luxury sedan'), findsOneWidget);  // Prime Sedan
      expect(find.text('Spacious'), findsOneWidget);      // Prime SUV
      // Exactly the API's figure, not re-rounded or recomputed on the phone.
      expect(find.text('₹3431'), findsOneWidget);
      expect(find.text('₹3430'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('the route is framed above the sheet, not under it', (tester) async {
      await http.runWithClient(() => openList(tester), () => _api);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap).first);
      final h = tester.getSize(find.byType(GoogleMap).first).height;
      // Bounds fits honour the map padding: it must reserve the sheet's resting height.
      expect(map.padding.bottom, closeTo(h * 0.4, 1));
      await _teardown(tester);
    });

    test('tagline wording', () {
      expect(vehicleTagline('Cab'), 'Comfortable');
      expect(vehicleTagline('Prime Sedan'), 'Luxury sedan');
      expect(vehicleTagline('Prime SUV'), 'Spacious');
    });
  });
}
