import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/registration/document_detail_page.dart';
import 'package:gora_driver/features/registration/document_upload_page.dart';
import 'package:gora_driver/features/registration/kyc_success_page.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin-configured registration documents: category, description, photo-only
// documents, photo labels, per-vehicle-type lists and the server's own check
// of required documents.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final calls = <http.Request>[];
http.Response? Function(http.Request req) api = (_) => null;

Future<void> withApi(Future<void> Function() body) => http.runWithClient(body, () => MockClient((req) async {
      calls.add(req);
      return api(req) ?? _json({});
    }));

bool _is(http.Request r, String method, String pathEnd) => r.method == method && r.url.path.endsWith(pathEnd);
List<http.Request> _sent(String method, String pathEnd) => calls.where((r) => _is(r, method, pathEnd)).toList();

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget home, {DriverProvider? dp, Object? args, Map<String, WidgetBuilder>? routes}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dp ?? DriverProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        routes: {...AppRoutes.routes, ...?routes},
        // Only the page under test (no splash underneath), with [args] as its route arguments.
        initialRoute: '/doc-test',
        onGenerateInitialRoutes: (name) => [
          MaterialPageRoute(settings: RouteSettings(name: name, arguments: args), builder: (_) => home),
        ],
      ),
    );

const _vehiclePhoto = {
  'id': 'v1', 'key': 'vehicle_photo', 'name': 'Vehicle photo', 'category': 'vehicle',
  'description': 'Number plate must be readable.', 'needsNumber': false, 'numberLabel': '',
  'frontLabel': 'Photo', 'backLabel': 'Side view', 'needsBack': true, 'needsExpiry': false,
  'required': true, 'isActive': true, 'order': 3, 'vehicleTypes': ['Cab', 'Auto'],
};

void main() {
  setUp(() {
    calls.clear();
    api = (_) => null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
  });

  group('DocSpec.fromJson', () {
    test('an old payload gets the old behaviour as defaults', () {
      final s = DocSpec.fromJson({'key': 'pan', 'name': 'PAN Card', 'numberLabel': 'PAN Number', 'required': true})!;
      expect(s.category, 'other');
      expect(s.description, '');
      expect(s.needsNumber, isTrue);
      expect(s.frontLabel, 'Front side');
      expect(s.backLabel, 'Back side');
      expect(s.vehicleTypes, isEmpty);
      expect(s.appliesTo('Bike'), isTrue);
    });

    test('new fields are parsed; blanks and unknown categories fall back', () {
      final s = DocSpec.fromJson(Map<String, dynamic>.from(_vehiclePhoto))!;
      expect(s.category, 'vehicle');
      expect(s.description, 'Number plate must be readable.');
      expect(s.needsNumber, isFalse);
      expect(s.frontLabel, 'Photo');
      expect(s.backLabel, 'Side view');
      expect(s.vehicleTypes, ['Cab', 'Auto']);
      final odd = DocSpec.fromJson({'key': 'x', 'name': 'X', 'category': 'Weird', 'frontLabel': ' ', 'backLabel': null})!;
      expect(odd.category, 'other');
      expect(odd.frontLabel, 'Front side');
      expect(odd.backLabel, 'Back side');
      expect(DocSpec.fromJson({'key': 'dl', 'name': 'DL', 'category': 'DRIVING'})!.category, 'driving');
    });

    test('needsNumber=false is complete without a number; true still needs one', () {
      final photo = DocSpec.fromJson(Map<String, dynamic>.from(_vehiclePhoto))!;
      final d = DocData(frontUrl: 'https://x/f.jpg', backUrl: 'https://x/b.jpg');
      expect(d.isComplete(photo), isTrue);
      const pan = DocSpec(key: 'pan', name: 'PAN Card', numberLabel: 'PAN Number');
      expect(DocData(frontUrl: 'https://x/f.jpg').isComplete(pan), isFalse);
      expect(DocData(number: 'ABCDE1234F', frontUrl: 'https://x/f.jpg').isComplete(pan), isTrue);
    });
  });

  group('vehicle type', () {
    final rows = {'documents': [
      _vehiclePhoto,
      {'key': 'helmet', 'name': 'Helmet photo', 'vehicleTypes': ['bike']},
      {'key': 'pan', 'name': 'PAN Card'},
    ]};

    test('client-side filter drops documents for other vehicle types (case-insensitive)', () {
      expect(docSpecsFromApi(rows, vehicleType: 'BIKE').map((s) => s.key), ['helmet', 'pan']);
      expect(docSpecsFromApi(rows, vehicleType: 'cab').map((s) => s.key), ['vehicle_photo', 'pan']);
      expect(docSpecsFromApi(rows).map((s) => s.key), ['vehicle_photo', 'helmet', 'pan'], reason: 'unknown type: keep all');
    });

    testWidgets('the route\'s vehicle type is sent as ?vehicleType', (tester) async {
      phone(tester);
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage(), args: {'vehicleType': 'Bike'}));
        await pumpFor(tester);
      });
      final get = _sent('GET', '/document-types');
      expect(get, hasLength(1));
      expect(get.single.url.queryParameters['vehicleType'], 'Bike');
    });

    testWidgets('no route argument: the profile\'s selectedVehicleTypeName is used', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/auth/driver/profile')
          ? _json({'driver': {'_id': 'd1', 'selectedVehicleTypeName': 'Auto'}})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      expect(_sent('GET', '/document-types').single.url.queryParameters['vehicleType'], 'Auto');
    });

    testWidgets('a loaded provider is used without fetching the profile', (tester) async {
      phone(tester);
      final dp = DriverProvider()..setData({'selectedVehicleTypeName': 'Cab'});
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage(), dp: dp));
        await pumpFor(tester);
      });
      expect(_sent('GET', '/document-types').single.url.queryParameters['vehicleType'], 'Cab');
      expect(_sent('GET', '/auth/driver/profile'), isEmpty);
    });

    testWidgets('unknown vehicle type: called without the param', (tester) async {
      phone(tester);
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      final get = _sent('GET', '/document-types').single;
      expect(get.url.queryParameters.containsKey('vehicleType'), isFalse);
      expect(get.url.path, endsWith('/document-types'));
    });
  });

  group('list page groups by category', () {
    testWidgets('headers in order Identity, Vehicle, Driving licence, Other; only for used categories', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/document-types')
          ? _json({'documents': [
              {'key': 'misc', 'name': 'Police Verification', 'category': 'other', 'required': false},
              {'key': 'dl', 'name': 'Driving License', 'category': 'driving'},
              _vehiclePhoto,
              {'key': 'aadhaar', 'name': 'Aadhaar Card', 'category': 'identity', 'needsBack': true},
            ]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage(), args: {'vehicleType': 'Cab'}));
        await pumpFor(tester);
      });
      final ys = [
        for (final c in ['identity', 'vehicle', 'driving', 'other']) tester.getTopLeft(find.byKey(ValueKey('doc_section_$c'))).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Driving licence'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      // Each document sits under its header.
      expect(tester.getTopLeft(find.text('Aadhaar Card')).dy, lessThan(ys[1]));
      expect(tester.getTopLeft(find.text('Vehicle photo')).dy, inExclusiveRange(ys[1], ys[2]));
      expect(tester.getTopLeft(find.text('Driving License')).dy, inExclusiveRange(ys[2], ys[3]));
      expect(tester.getTopLeft(find.text('Police Verification')).dy, greaterThan(ys[3]));
      // Photo-only document: no "Number" in its hint, its own photo labels instead.
      expect(find.text('Needs: Photo, Side view'), findsOneWidget);
      expect(find.text('0 of 3 required uploaded'), findsOneWidget);
    });

    testWidgets('a missing category gets no header', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/document-types')
          ? _json({'documents': [
              {'key': 'aadhaar', 'name': 'Aadhaar Card', 'category': 'identity'},
              {'key': 'misc', 'name': 'Police Verification'},
            ]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      expect(find.byKey(const ValueKey('doc_section_identity')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc_section_other')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc_section_vehicle')), findsNothing);
      expect(find.byKey(const ValueKey('doc_section_driving')), findsNothing);
    });

    testWidgets('every document "other" (old server): no headers at all', (tester) async {
      phone(tester);
      api = (r) => _is(r, 'GET', '/document-types')
          ? _json({'documents': [
              {'key': 'aadhaar', 'name': 'Aadhaar Card'},
              {'key': 'pan', 'name': 'PAN Card'},
            ]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage()));
        await pumpFor(tester);
      });
      expect(find.text('Aadhaar Card'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('doc_section_')),
          findsNothing);
      expect(find.text('Other'), findsNothing);
    });
  });

  group('detail page', () {
    testWidgets('description note, no number field, custom photo labels', (tester) async {
      phone(tester);
      final spec = DocSpec.fromJson(Map<String, dynamic>.from(_vehiclePhoto))!;
      await tester.pumpWidget(app(DocumentDetailPage(spec: spec, initial: DocData())));
      await tester.pump();
      expect(find.text('Vehicle photo'), findsOneWidget, reason: 'title');
      expect(find.descendant(of: find.byKey(const ValueKey('doc_description')),
          matching: find.text('Number plate must be readable.')), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'needsNumber=false hides the number field');
      expect(find.text('Photo'), findsWidgets);
      expect(find.text('Side view'), findsWidgets);
      expect(find.text('Front side'), findsNothing);
      expect(find.text('Back side'), findsNothing);
    });

    testWidgets('an old spec: number field, default labels, no description', (tester) async {
      phone(tester);
      const spec = DocSpec(key: 'aadhaar', name: 'Aadhaar Card', numberLabel: 'Aadhaar Number', needsBack: true);
      await tester.pumpWidget(app(DocumentDetailPage(spec: spec, initial: DocData())));
      await tester.pump();
      expect(find.byKey(const ValueKey('doc_description')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Front side'), findsWidgets);
      expect(find.text('Back side'), findsWidgets);
    });

    testWidgets('photo-only document saves without a number', (tester) async {
      phone(tester);
      final spec = DocSpec.fromJson(Map<String, dynamic>.from(_vehiclePhoto))!;
      DocData? result;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => DriverProvider()), ChangeNotifierProvider(create: (_) => ThemeProvider())],
        child: MaterialApp(navigatorKey: nav, theme: AppTheme.light, home: const Scaffold(body: Text('LIST'))),
      ));
      final pushed = nav.currentState!.push<DocData>(MaterialPageRoute(builder: (_) => DocumentDetailPage(
          spec: spec, initial: DocData(number: 'stale', frontUrl: 'https://x/f.jpg', backUrl: 'https://x/b.jpg'))));
      unawaited(pushed.then((d) => result = d));
      await pumpFor(tester, 500);
      await tester.tap(find.text('Save'));
      await pumpFor(tester, 500);
      expect(result, isNotNull);
      expect(result!.number, '');
      expect(result!.isComplete(spec), isTrue);
      expect(find.text('LIST'), findsOneWidget);
      while (tester.takeException() != null) {}
    });
  });

  group('server check on submit', () {
    testWidgets('a 400 "Please upload: …" is shown and the driver stays on the page', (tester) async {
      phone(tester);
      const msg = 'Please upload: Police Verification, RC Book';
      api = (r) {
        if (_is(r, 'GET', '/document-types')) {
          return _json({'documents': [{'key': 'police_verification', 'name': 'Police Verification', 'required': false}]});
        }
        if (_is(r, 'POST', '/register/documents')) return _json({'error': msg, 'missing': ['police_verification', 'rc']}, 400);
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(app(const DocumentUploadPage(),
            routes: {KycSuccessPage.route: (_) => const Scaffold(body: Text('SUBMITTED PAGE'))}));
        await pumpFor(tester);
        await tester.tap(find.text('Submit documents'));
        await pumpFor(tester);
      });
      expect(_sent('POST', '/register/documents'), hasLength(1));
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(msg)), findsOneWidget);
      expect(find.text('SUBMITTED PAGE'), findsNothing);
      expect(find.byType(DocumentUploadPage), findsOneWidget);
      expect(find.text('Submit documents'), findsOneWidget, reason: 'button usable again');
    });
  });
}

