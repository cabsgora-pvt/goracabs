import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/account/pages/preferences_page.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/registration/vehicle_categories.dart';
import 'package:gora_driver/features/registration/vehicle_details_page.dart';
import 'package:gora_driver/features/registration/vehicle_selection_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/widgets/lower_tier_chip.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// v1.5.2 vehicle tiers: registration picks a CATEGORY (Bike, Auto, Cab …) and
// then its tier (Cab / Prime Sedan / Prime SUV) with the tier's rules; the
// details step sends the model year and shows why a vehicle does not qualify;
// a higher-tier driver may opt in to lower-tier rides, and such a ride is
// labelled on the request card.

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final _calls = <http.Request>[];
http.Response? Function(http.Request req) _api = (_) => null;
MockClient get _client => MockClient((req) async {
      _calls.add(req);
      return _api(req) ?? _base(req) ?? _json({});
    });

const _types = [
  {'_id': 'suv', 'name': 'Prime SUV', 'capacity': 6, 'services': ['taxi'], 'isActive': true,
    'category': 'cab', 'categoryLabel': 'Cab', 'rank': 3, 'tagline': 'Innova & Ertiga, top drivers',
    'requirements': {'minModelYear': 2018}, 'requirementsText': '2018 or newer'},
  {'_id': 'bike', 'name': 'Bike', 'capacity': 1, 'services': ['taxi'], 'isActive': true,
    'category': 'bike', 'categoryLabel': 'Bike', 'rank': 1, 'tagline': '', 'requirementsText': ''},
  {'_id': 'cab', 'name': 'Cab', 'capacity': 4, 'services': ['taxi'], 'isActive': true,
    'category': 'cab', 'categoryLabel': 'Cab', 'rank': 1, 'tagline': '', 'requirementsText': ''},
  {'_id': 'sedan', 'name': 'Prime Sedan', 'capacity': 4, 'services': ['taxi'], 'isActive': true,
    'category': 'cab', 'categoryLabel': 'Cab', 'rank': 2, 'tagline': 'Newer sedans',
    'requirements': {'minModelYear': 2019, 'allowedModels': ['Dzire', 'Aura']}, 'requirementsText': '2019 or newer · Dzire, Aura'},
  {'_id': 'off', 'name': 'Old Van', 'services': ['taxi'], 'isActive': false},
];

http.Response? _base(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/vehicles/types')) return _json({'types': _types});
  if (p.endsWith('/document-types')) return _json({'documents': []});
  return null;
}

Future<void> _pumpFor(WidgetTester tester, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _size(WidgetTester tester, [Size size = const Size(400, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  while (tester.takeException() != null) {}
}

Widget _app(Widget home, {Object? args, Map<String, dynamic>? driver}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => driver == null ? DriverProvider() : (DriverProvider()..setData(driver))),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(),
        child: MaterialApp(
          theme: AppTheme.light,
          routes: {...AppRoutes.routes},
          initialRoute: '/tier-test',
          onGenerateInitialRoutes: (name) => [
            MaterialPageRoute(settings: RouteSettings(name: name, arguments: args), builder: (_) => home),
          ],
        ),
      ),
    );

void main() {
  setUp(() {
    _calls.clear();
    _api = (_) => null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
  });

  // ── 1. Grouping (pure) ──────────────────────────────────────────────────
  group('grouping types into categories', () {
    test('categories keep server order; tiers inside sorted by rank', () {
      final cats = groupVehicleTypes(_types.where((t) => t['isActive'] != false).map((t) => Map<String, dynamic>.from(t)).toList());
      expect(cats.map((c) => c.key).toList(), ['cab', 'bike'], reason: 'Cab first: its first type (Prime SUV) came first');
      expect(cats.first.types.map((t) => t['name']).toList(), ['Cab', 'Prime Sedan', 'Prime SUV']);
      expect(cats.first.countText, '3 options');
      expect(cats.first.representative['name'], 'Cab', reason: 'the basic tier stands for the category');
      expect(cats.last.isSingle, isTrue);
      expect(cats.last.countText, '1 option');
    });

    test('an older server (no category/rank) is grouped exactly like the server infers', () {
      final cats = groupVehicleTypes([
        {'_id': '1', 'name': 'Prime SUV'}, {'_id': '2', 'name': 'Auto'}, {'_id': '3', 'name': 'Cab'},
        {'_id': '4', 'name': 'Mini Truck'}, {'_id': '5', 'name': 'Prime Sedan'}, {'_id': '6', 'name': 'Bike'},
        {'_id': '7', 'name': 'Scooty'},
      ]);
      expect({for (final c in cats) c.key: c.types.map((t) => t['name']).toList()}, {
        'cab': ['Cab', 'Prime Sedan', 'Prime SUV'],
        'auto': ['Auto'],
        'truck': ['Mini Truck'],
        'bike': ['Bike'],
        'scooter': ['Scooty'],
      });
      expect(vehicleCategoryLabelOf({'name': 'Mini Truck'}), 'Truck');
    });

    test("the admin's stored category / rank win over the name", () {
      expect(vehicleCategoryOf({'name': 'Swift', 'category': 'CAB'}), 'cab');
      expect(vehicleRankOf({'name': 'Cab', 'rank': 3}), 3);
      expect(vehicleRankOf({'name': 'Prime SUV', 'rank': null}), 3);
      expect(vehicleRankOf({'name': 'Cab', 'rank': '2'}), 2);
    });

    test('requirements text: the server one, or built from requirements', () {
      expect(vehicleRequirementsText({'requirementsText': '2019 or newer'}), '2019 or newer');
      expect(vehicleRequirementsText({'requirements': {'minModelYear': 2019, 'minDriverRating': 4.5,
        'allowedModels': ['Dzire', 'Aura'], 'note': 'AC must work'}}), '2019 or newer · rating 4.5+ · Dzire, Aura · AC must work');
      expect(vehicleRequirementsText({'name': 'Cab'}), '');
    });

    test('model years: next year down to 1995', () {
      final ys = modelYearOptions(now: DateTime.utc(2026, 11, 27));
      expect(ys.first, 2027);
      expect(ys.last, 1995);
      expect(ys, hasLength(2027 - 1995 + 1));
    });
  });

  // ── 2. Registration: category → tier ───────────────────────────────────
  group('registration vehicle step', () {
    testWidgets('grid of categories; Cab opens its tiers with tagline and rules; back returns', (tester) async {
      _size(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleSelectionPage()));
        await _pumpFor(tester);
        expect(find.text('Which vehicle will you drive?'), findsOneWidget);
        expect(find.byKey(const ValueKey('vehicle_category_cab')), findsOneWidget);
        expect(find.byKey(const ValueKey('vehicle_category_bike')), findsOneWidget);
        expect(find.text('3 options'), findsOneWidget);
        expect(find.text('Old Van'), findsNothing, reason: 'inactive types are not offered');
        expect(find.byType(VehicleTypeTile), findsNothing, reason: 'tiers only after picking a category');

        await tester.tap(find.byKey(const ValueKey('vehicle_category_cab')));
        await _pumpFor(tester, 600);
        expect(find.text('Which Cab?'), findsOneWidget);
        final ys = ['cab', 'sedan', 'suv'].map((id) => tester.getCenter(find.byKey(ValueKey('vehicle_type_$id'))).dy).toList();
        expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: 'basic first: Cab, Prime Sedan, Prime SUV');
        expect(find.text('Needs: 2019 or newer · Dzire, Aura'), findsOneWidget);
        expect(find.byKey(const ValueKey('vehicle_needs_suv')), findsOneWidget);
        expect(find.byKey(const ValueKey('vehicle_needs_cab')), findsNothing, reason: 'no rules → no "Needs" line');
        expect(find.text('Newer sedans'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('vehicle_back_to_categories')));
        await _pumpFor(tester, 600);
        expect(find.text('Which vehicle will you drive?'), findsOneWidget);
        expect(find.byType(VehicleTypeTile), findsNothing);
      }, () => _client);
      await _teardown(tester);
    });

    testWidgets('picking Prime Sedan and Continue opens details with that type and its rules', (tester) async {
      _size(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleSelectionPage()));
        await _pumpFor(tester);
        await tester.tap(find.byKey(const ValueKey('vehicle_category_cab')));
        await _pumpFor(tester, 600);
        await tester.tap(find.text('Continue'));
        await _pumpFor(tester, 400);
        expect(find.text('Please pick one Cab type'), findsOneWidget, reason: 'nothing picked in the open category');
        ScaffoldMessenger.of(tester.element(find.byType(VehicleSelectionPage))).hideCurrentSnackBar();
        await _pumpFor(tester, 600);
        await tester.tap(find.byKey(const ValueKey('vehicle_type_sedan')));
        await _pumpFor(tester, 300);
        await tester.tap(find.text('Continue'));
        await _pumpFor(tester, 1200);
        expect(find.byType(VehicleDetailsPage), findsOneWidget);
        expect(find.text('Prime Sedan'), findsWidgets);
        expect(find.text('Needs: 2019 or newer · Dzire, Aura'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<int>), findsOneWidget, reason: 'the model year picker');
      }, () => _client);
      await _teardown(tester);
    });

    testWidgets('a one-type category (Bike) is selected on tap, without a second level', (tester) async {
      _size(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleSelectionPage()));
        await _pumpFor(tester);
        await tester.tap(find.byKey(const ValueKey('vehicle_category_bike')));
        await _pumpFor(tester, 400);
        expect(find.byType(VehicleTypeTile), findsNothing);
        expect(find.text('Which vehicle will you drive?'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await _pumpFor(tester, 1200);
        expect(find.byType(VehicleDetailsPage), findsOneWidget);
      }, () => _client);
      await _teardown(tester);
    });

    Future<void> fillAndSubmit(WidgetTester tester, {int? year}) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'Maruti Alto');
      await tester.enterText(find.byType(TextFormField).at(1), 'gj03ab1234');
      final y = year ?? DateTime.now().year - 1;
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await _pumpFor(tester, 500);
      await tester.tap(find.text('$y').last);
      await _pumpFor(tester, 500);
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester, 1000);
    }

    testWidgets('vehicle not eligible: every reason listed, nothing else opens, "change type" offered', (tester) async {
      _size(tester);
      _api = (r) => r.url.path.endsWith('/register/vehicle')
          ? _json({'error': 'Prime Sedan needs a 2019 or newer vehicle (yours is 2016)', 'code': 'VEHICLE_NOT_ELIGIBLE',
              'problems': ['Prime Sedan needs a 2019 or newer vehicle (yours is 2016)', 'Prime Sedan allows these models: Dzire, Aura']}, 400)
          : null;
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleDetailsPage(), args: {'vehicle': Map<String, dynamic>.from(_types[3])}));
        await _pumpFor(tester);
        await fillAndSubmit(tester);
        expect(find.byKey(const ValueKey('vehicle_not_eligible')), findsOneWidget);
        expect(find.text('Your vehicle does not qualify for Prime Sedan'), findsOneWidget);
        expect(find.text('Prime Sedan needs a 2019 or newer vehicle (yours is 2016)'), findsOneWidget);
        expect(find.text('Prime Sedan allows these models: Dzire, Aura'), findsOneWidget);
        expect(find.byType(VehicleDetailsPage), findsOneWidget, reason: 'stays on the step');
        final body = jsonDecode(_calls.lastWhere((c) => c.url.path.endsWith('/register/vehicle')).body) as Map;
        expect(body['vehicleYear'], DateTime.now().year - 1);
        expect(body['selectedVehicleTypeId'], 'sedan');
      }, () => _client);
      await _teardown(tester);
    });

    testWidgets('BAD_YEAR: the message shows under the year picker', (tester) async {
      _size(tester);
      _api = (r) => r.url.path.endsWith('/register/vehicle')
          ? _json({'error': 'Enter a model year between 1990 and 2027', 'code': 'BAD_YEAR'}, 400)
          : null;
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleDetailsPage(), args: {'vehicle': Map<String, dynamic>.from(_types[2])}));
        await _pumpFor(tester);
        await fillAndSubmit(tester);
        expect(find.byKey(const ValueKey('vehicle_year_error')), findsOneWidget);
        expect(find.text('Enter a model year between 1990 and 2027'), findsOneWidget);
        expect(find.byKey(const ValueKey('vehicle_not_eligible')), findsNothing);
      }, () => _client);
      await _teardown(tester);
    });

    test('eligibility reasons from the reply', () {
      expect(vehicleEligibilityProblems({'code': 'VEHICLE_NOT_ELIGIBLE', 'problems': ['a', ' ', 'b']}), ['a', 'b']);
      expect(vehicleEligibilityProblems({'code': 'VEHICLE_NOT_ELIGIBLE', 'error': 'only this'}), ['only this']);
      expect(vehicleEligibilityProblems({'error': 'other'}), isEmpty);
    });
  });

  // ── 3. Preferences: "Also take Cab, Prime Sedan rides" ─────────────────
  group('lower-tier rides switch', () {
    final sent = <Map<String, dynamic>>[];
    MockClient api(List<String> lowerTiers, {bool on = false}) => MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/ride-preferences')) return _json({'preferences': []});
          if (p.endsWith('/auth/driver/profile')) {
            return _json({'driver': {'_id': 'd1', 'selectedVehicleTypeName': 'Prime SUV', 'lowerTiers': lowerTiers, 'acceptLowerTiers': on}});
          }
          if (p.endsWith('/auth/driver/preferences') && req.method == 'POST') {
            final b = jsonDecode(req.body) as Map<String, dynamic>;
            sent.add(b);
            return _json({'success': true, 'preferences': {...b, 'lowerTiers': lowerTiers, 'acceptLowerTiers': b['acceptLowerTiers'] == true}});
          }
          return _json({});
        });
    setUp(sent.clear);

    testWidgets('shown for a higher tier; switching on and saving sends acceptLowerTiers', (tester) async {
      _size(tester, const Size(400, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PreferencesPage()));
        await _pumpFor(tester);
        expect(find.byKey(const ValueKey('prefs_lower_tiers')), findsOneWidget);
        expect(find.text('Also take Cab, Prime Sedan rides'), findsOneWidget);
        expect(find.text(lowerTiersSubtitle), findsOneWidget);
        final sw = find.byKey(const ValueKey('prefs_lower_tiers_switch'));
        expect(tester.widget<Switch>(sw).value, isFalse, reason: 'off by default');
        await tester.tap(sw);
        await tester.pump();
        expect(tester.widget<Switch>(sw).value, isTrue);
        expect(find.text('You have unsaved changes'), findsOneWidget);
        await tester.tap(find.text('Save Preferences'));
        await _pumpFor(tester);
        expect(sent.single['acceptLowerTiers'], isTrue);
        expect(find.text('All changes saved'), findsOneWidget);
      }, () => api(['Cab', 'Prime Sedan']));
    });

    testWidgets('hidden for the lowest tier, and never sent', (tester) async {
      _size(tester, const Size(400, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PreferencesPage()));
        await _pumpFor(tester);
        expect(find.byKey(const ValueKey('prefs_lower_tiers')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('svc_card_outstation')));
        await tester.pump();
        await tester.tap(find.text('Save Preferences'));
        await _pumpFor(tester);
        expect(sent.single.containsKey('acceptLowerTiers'), isFalse);
      }, () => api(const []));
    });

    test('names from the reply', () {
      expect(lowerTierNames(['Cab', ' ', 'Prime Sedan']), ['Cab', 'Prime Sedan']);
      expect(lowerTierNames(null), isEmpty);
      expect(lowerTiersTitle(['Cab']), 'Also take Cab rides');
    });
  });

  // ── 4. Request card: a lower-tier ride says so ─────────────────────────
  group('lower-tier request card', () {
    test('label', () {
      expect(lowerTierRideLabel('Cab', 'Prime SUV'), 'Cab ride · lower tier');
      expect(lowerTierRideLabel('Prime SUV', 'prime suv '), isNull);
      expect(lowerTierRideLabel('', 'Prime SUV'), isNull);
      expect(lowerTierRideLabel('Cab', ''), isNull);
    });

    Map<String, dynamic> feed(String vt) => {
          'id': 'r1', 'service': 'taxi', 'riderName': 'Rahul', 'vehicleType': vt,
          'pickupAddress': 'Law Garden, Ahmedabad', 'dropAddress': 'Prahlad Nagar, Ahmedabad',
          'pickupLat': 23.0266, 'pickupLng': 72.5609, 'dropLat': 23.0120, 'dropLng': 72.5108,
          'fare': 120, 'totalFare': 120, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
        };

    for (final c in const [('Cab', true), ('Prime SUV', false)]) {
      testWidgets('Prime SUV driver, ${c.$1} ride → chip ${c.$2 ? 'shown' : 'not shown'}', (tester) async {
        _size(tester);
        await http.runWithClient(() async {
          await tester.pumpWidget(_app(const IncomingRequestsPage(), driver: {'selectedVehicleTypeName': 'Prime SUV'}));
          await _pumpFor(tester, 500);
          expect(find.byKey(const ValueKey('lower_tier_r1')), c.$2 ? findsOneWidget : findsNothing);
          expect(find.text('Cab ride · lower tier'), c.$2 ? findsOneWidget : findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        }, () => MockClient((req) async =>
            _json(req.url.path.endsWith('/rides/driver/pending') ? {'rides': [feed(c.$1)]} : {})));
        while (tester.takeException() != null) {}
      });
    }
  });
}
