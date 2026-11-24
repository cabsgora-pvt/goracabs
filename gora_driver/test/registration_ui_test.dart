import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/registration/document_detail_page.dart';
import 'package:gora_driver/features/registration/document_upload_page.dart';
import 'package:gora_driver/features/registration/face_capture_page.dart';
import 'package:gora_driver/features/registration/kyc_pending_page.dart';
import 'package:gora_driver/features/registration/kyc_success_page.dart';
import 'package:gora_driver/features/registration/personal_details_page.dart';
import 'package:gora_driver/features/registration/rejection_page.dart';
import 'package:gora_driver/features/registration/submit_application_page.dart';
import 'package:gora_driver/features/registration/vehicle_details_page.dart';
import 'package:gora_driver/features/registration/vehicle_selection_page.dart';
import 'package:gora_driver/features/registration/widgets/reg_ui.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Branded registration UI: real vehicle photos with their fallbacks, the
// numbered stepper, the documents ring + thumbnails, the CTA staying above the
// keyboard, layout at small/large sizes and the reduced-motion first frame.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response? Function(http.Request r) api = (_) => null;

MockClient get _client => MockClient((r) async {
      final hit = api(r);
      if (hit != null) return hit;
      final p = r.url.path;
      if (p.endsWith('/zones')) return _json({'zones': [{'_id': 'z1', 'name': 'Rajkot'}]});
      if (p.endsWith('/vehicles/types')) {
        return _json({'types': [
          {'_id': 'v1', 'name': 'Bike', 'capacity': 1, 'imageUrl': '/uploads/vehicles/v2/bike.webp', 'services': ['taxi', 'parcel']},
          {'_id': 'v3', 'name': 'Cab', 'capacity': 4, 'services': ['taxi', 'rental', 'outstation', 'hire_driver', 'parcel']},
          {'_id': 'v6', 'name': 'Mini Truck', 'services': ['parcel']},
        ]});
      }
      if (p.endsWith('/auth/driver/profile')) return _json({'driver': {'_id': 'd1', 'status': 'pending'}});
      // Offline-style failure: the submit page stays put with its retry.
      if (p.endsWith('/register/submit')) return http.Response('<html>502</html>', 502);
      return _json({});
    });

final _nav = GlobalKey<NavigatorState>();

Widget _app(Widget home, {Object? args}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(),
        child: MaterialApp(
          navigatorKey: _nav,
          theme: AppTheme.light,
          onGenerateRoute: (s) => MaterialPageRoute(
            settings: RouteSettings(name: s.name, arguments: args),
            builder: (_) => s.name == '/' ? home : const Scaffold(body: Text('NEXT')),
          ),
        ),
      ),
    );

void _size(WidgetTester tester, Size size, {double dpr = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFor(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  while (tester.takeException() != null) {}
}

String? _assetOf(Widget w) => w is Image && w.image is AssetImage ? (w.image as AssetImage).assetName : null;

void main() {
  setUp(() {
    api = (_) => null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
  });

  // ── Vehicle photos ─────────────────────────────────────────────────────────
  group('vehicle photo', () {
    test('name → bundled asset mapping (case-insensitive)', () {
      const d = 'assets/images/vehicles';
      final cases = {
        'Bike': 'bike', 'SCOOTER': 'bike', 'e-Bike': 'bike',
        'Auto': 'auto', 'Auto Rickshaw': 'auto', 'e-rickshaw': 'auto',
        'Mini Truck': 'mini-truck', 'truck': 'mini-truck', 'Tempo': 'mini-truck',
        'Prime SUV': 'prime-suv', 'suv': 'prime-suv', 'Cab Premium SUV 7 Seater': 'prime-suv',
        'Prime Sedan': 'prime-sedan', 'Sedan': 'prime-sedan', 'Prime': 'prime-sedan',
        'Cab': 'cab', 'Mini': 'cab', '': 'cab', 'Hatchback': 'cab',
      };
      cases.forEach((name, file) => expect(vehicleAssetFor(name), '$d/$file.webp', reason: name));
    });

    test('every mapped asset exists and is listed in pubspec', () {
      for (final name in ['Bike', 'Auto', 'Cab', 'Prime Sedan', 'Prime SUV', 'Mini Truck']) {
        expect(File(vehicleAssetFor(name)).existsSync(), isTrue, reason: name);
      }
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/images/vehicles/'));
    });

    testWidgets('no imageUrl → the bundled photo, no network image', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(
          child: VehicleTypeImage(vt: {'name': 'Prime SUV', 'imageUrl': ''}, width: 120, height: 80))));
      final imgs = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(imgs, hasLength(1));
      expect(_assetOf(imgs.single), 'assets/images/vehicles/prime-suv.webp');
      expect(find.byIcon(Icons.airport_shuttle), findsNothing, reason: 'no icon while the photo exists');
    });

    testWidgets('network imageUrl → loading and error both show the bundled photo, not an icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(
          child: VehicleTypeImage(vt: {'name': 'Cab', 'imageUrl': '/uploads/vehicles/v2/cab.webp'}, width: 120, height: 80))));
      final net = tester.widget<Image>(find.byKey(const ValueKey('vehicle_network')));
      expect((net.image as NetworkImage).url, 'https://goracabs.com/uploads/vehicles/v2/cab.webp',
          reason: 'imageUrl goes through AppConfig.imageUrl');
      // While loading: the network image has no frame yet → bundled photo.
      expect(find.byKey(const ValueKey('vehicle_asset')), findsOneWidget);
      expect(_assetOf(tester.widget(find.byKey(const ValueKey('vehicle_asset')))), 'assets/images/vehicles/cab.webp');
      // The error path renders the bundled photo too.
      final ctx = tester.element(find.byKey(const ValueKey('vehicle_network')));
      final onError = net.errorBuilder!(ctx, Exception('404'), null);
      await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 120, height: 80, child: onError))));
      expect(_assetOf(tester.widget(find.byType(Image))), 'assets/images/vehicles/cab.webp');
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('a real failed network load ends on the bundled photo', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(
          child: VehicleTypeImage(vt: {'name': 'Bike', 'imageUrl': '/uploads/missing.png'}, width: 120, height: 80))));
      // flutter_test answers every HTTP request with 400: let it fail for real.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(_assetOf(tester.widget(find.byKey(const ValueKey('vehicle_asset')))), 'assets/images/vehicles/bike.webp');
      expect(find.byIcon(Icons.two_wheeler), findsNothing);
    });

    testWidgets('only if the bundled photo fails too: an icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(
          child: VehicleTypeImage(vt: {'name': 'Auto'}, width: 120, height: 80))));
      final asset = tester.widget<Image>(find.byKey(const ValueKey('vehicle_asset')));
      final fallback = asset.errorBuilder!(tester.element(find.byType(Image)), Exception('x'), null);
      await tester.pumpWidget(MaterialApp(home: fallback));
      expect(find.byIcon(Icons.electric_rickshaw), findsOneWidget);
    });

    testWidgets('selection page: full-width cards with photo, seats and chips; details page reuses the photo',
        (tester) async {
      _size(tester, const Size(411, 1400));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const VehicleSelectionPage()));
        await _pumpFor(tester);
        final assets = tester.widgetList<Image>(find.byKey(const ValueKey('vehicle_asset'))).map(_assetOf).toList();
        expect(assets, [
          'assets/images/vehicles/bike.webp', // network URL still loading → bundled photo
          'assets/images/vehicles/cab.webp',
          'assets/images/vehicles/mini-truck.webp',
        ]);
        expect(find.byKey(const ValueKey('vehicle_network')), findsOneWidget, reason: 'Bike has an imageUrl');
        expect(find.text('1 seat'), findsOneWidget);
        expect(find.text('4 seats'), findsOneWidget);
        expect(find.textContaining('seat'), findsNWidgets(2), reason: 'no seats line without a capacity');
        for (final s in ['Taxi', 'Rental', 'Outstation', 'Parcel', 'Hire driver']) {
          expect(find.text(s), findsWidgets, reason: s);
        }
        // Full width: each card spans (almost) the sheet.
        final card = tester.getSize(find.byType(VehicleTypeTile).first);
        expect(card.width, greaterThan(411 - 40));
        await _teardown(tester);

        await tester.pumpWidget(_app(const VehicleDetailsPage(), args: {'vehicle': {'_id': 'v6', 'name': 'Mini Truck'}}));
        await _pumpFor(tester);
        expect(_assetOf(tester.widget(find.byKey(const ValueKey('vehicle_asset')))),
            'assets/images/vehicles/mini-truck.webp');
        await _teardown(tester);
      }, () => _client);
    });
  });

  // ── Stepper ────────────────────────────────────────────────────────────────
  group('stepper', () {
    for (var step = 1; step <= 4; step++) {
      testWidgets('step $step: done before, current highlighted, future muted', (tester) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(
            backgroundColor: Colors.indigo, body: SizedBox(width: 360, child: RegStepper(step: step)))));
        await tester.pump(const Duration(seconds: 1));
        for (var n = 1; n <= 4; n++) {
          final dot = tester.widget<RegStepDot>(find.byKey(ValueKey('reg_step_dot_$n')));
          final want = n < step ? RegStepState.done : (n == step ? RegStepState.current : RegStepState.upcoming);
          expect(dot.state, want, reason: 'dot $n on step $step');
          // Done shows a check, the others their number.
          expect(find.descendant(of: find.byKey(ValueKey('reg_step_dot_$n')), matching: find.byIcon(Icons.done_rounded)),
              n < step ? findsOneWidget : findsNothing);
        }
        // The line is filled up to the current step, empty after it.
        for (var i = 1; i < 4; i++) {
          final line = tester.widget<FractionallySizedBox>(find.byKey(ValueKey('reg_step_line_$i')));
          expect(line.widthFactor, i + 1 <= step ? 1.0 : 0.0, reason: 'segment $i on step $step');
        }
        for (final l in kRegStepLabels) {
          expect(find.text(l), findsOneWidget);
        }
      });
    }

    testWidgets('the segment into the current step animates in, then settles', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: RegStepper(step: 3)))));
      await tester.pump(const Duration(milliseconds: 150));
      final mid = tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('reg_step_line_2'))).widthFactor!;
      expect(mid, inExclusiveRange(0.0, 1.0));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('reg_step_line_2'))).widthFactor, 1.0);
      expect(tester.binding.transientCallbackCount, 0);
    });

    test('regStepStateOf', () {
      expect([for (var n = 1; n <= 4; n++) regStepStateOf(n, 2)],
          [RegStepState.done, RegStepState.current, RegStepState.upcoming, RegStepState.upcoming]);
    });

    testWidgets('every step page shows the stepper on its own step and "Step N of 4"', (tester) async {
      _size(tester, const Size(411, 914));
      const insurance = DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number');
      final cases = <(Widget, Object?, int)>[
        (const PersonalDetailsPage(), {'phone': '9876543210'}, 1),
        (FaceCaptureChrome(stepIndex: 0, stepShort: 'Look straight', instruction: 'Look straight', onCapture: () {}), null, 2),
        (const VehicleSelectionPage(), null, 3),
        (const VehicleDetailsPage(), {'vehicle': {'_id': 'v3', 'name': 'Cab'}}, 3),
        (const DocumentUploadPage(), null, 4),
        (DocumentDetailPage(spec: insurance, initial: DocData()), null, 4),
      ];
      await http.runWithClient(() async {
        for (final (i, (page, args, step)) in cases.indexed) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(KeyedSubtree(key: ValueKey(i), child: _app(page, args: args)));
          await _pumpFor(tester);
          expect(tester.widget<RegStepper>(find.byType(RegStepper)).step, step, reason: '${page.runtimeType}');
          expect(find.text('Step $step of 4'), findsOneWidget, reason: '${page.runtimeType}');
        }
        await _teardown(tester);
      }, () => _client);
    });
  });

  // ── Documents ring + thumbnail ─────────────────────────────────────────────
  testWidgets('documents: ring shows N/M and a completed card shows its photo', (tester) async {
    _size(tester, const Size(411, 1400));
    api = (r) => r.url.path.endsWith('/document-types')
        ? _json({'documents': [
            {'key': 'pan', 'name': 'PAN Card', 'numberLabel': 'PAN Number', 'category': 'identity'},
            {'key': 'rc', 'name': 'RC Book', 'numberLabel': 'RC Number', 'category': 'vehicle'},
            {'key': 'police', 'name': 'Police Verification', 'required': false},
          ]})
        : null;
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const DocumentUploadPage()));
      await _pumpFor(tester);
      Finder inRing(String t) => find.descendant(of: find.byKey(const ValueKey('doc_progress_ring')), matching: find.text(t));
      expect(inRing('0/2'), findsOneWidget, reason: 'only required documents count');
      expect(find.text('0 of 2 required uploaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc_thumb_pan')), findsNothing);

      await tester.tap(find.text('PAN Card'));
      await _pumpFor(tester, 600);
      _nav.currentState!.pop(DocData(number: 'ABCDE1234F', frontUrl: 'https://x/pan.jpg'));
      await _pumpFor(tester);
      expect(inRing('1/2'), findsOneWidget);
      expect(find.text('1 of 2 required uploaded'), findsOneWidget);
      final thumb = find.descendant(of: find.byKey(const ValueKey('doc_thumb_pan')), matching: find.byType(Image));
      expect(thumb, findsOneWidget);
      expect((tester.widget<Image>(thumb).image as NetworkImage).url, 'https://x/pan.jpg');
      expect(find.byKey(const ValueKey('doc_done_pan')), findsOneWidget, reason: 'green check on the card');
      expect(find.byKey(const ValueKey('doc_thumb_rc')), findsNothing, reason: 'unfinished cards keep their icon');
      await _teardown(tester);
    }, () => _client);
  });

  // ── CTA above the keyboard ─────────────────────────────────────────────────
  testWidgets('the bottom CTA stays visible above the keyboard', (tester) async {
    _size(tester, const Size(360, 740));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const VehicleDetailsPage(), args: {'vehicle': {'_id': 'v3', 'name': 'Cab'}}));
      await _pumpFor(tester);
      final cta = tester.getRect(find.byType(RegCta));
      expect(cta.bottom, lessThanOrEqualTo(740 - 300 + 0.5));
      expect(cta.top, greaterThan(0));
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    }, () => _client);
  });

  // ── Layout at small + large sizes ──────────────────────────────────────────
  group('no overflow', () {
    const insurance = DocSpec(key: 'insurance', name: 'Vehicle Insurance Certificate (Comprehensive)',
        numberLabel: 'Insurance Number', needsBack: true, needsExpiry: true,
        description: 'Upload the current policy. The vehicle number must be visible on the first page.');
    final pages = <String, (Widget Function(), Object?)>{
      'PersonalDetails': (() => const PersonalDetailsPage(), {'phone': '9876543210'}),
      'FaceCaptureChrome': (() => FaceCaptureChrome(stepIndex: 3, stepShort: 'Tilt your head',
          instruction: 'Tilt your head up or down slightly', error: 'No single clear face found.', onCapture: () {}), null),
      'VehicleSelection': (() => const VehicleSelectionPage(), null),
      'VehicleDetails': (() => const VehicleDetailsPage(),
          {'vehicle': {'_id': 'v7', 'name': 'Cab Premium SUV 7 Seater Extra Long Wheelbase', 'imageUrl': '/uploads/x.png'}}),
      'DocumentUpload': (() => const DocumentUploadPage(), {'error': 'Please upload: RC Book, Vehicle Insurance'}),
      'DocumentDetail': (() => DocumentDetailPage(spec: insurance, initial: DocData(frontUrl: 'https://x/f.jpg')), null),
      'SubmitApplication': (() => const SubmitApplicationPage(), null),
      'KycSuccess': (() => const KycSuccessPage(), null),
      'KycPending': (() => const KycPendingPage(), null),
      'Rejection': (() => const RejectionPage(), {'reason': 'Blurred licence photo. ' * 6}),
    };
    final sizes = <String, (Size, double, double)>{
      '320x568 @1.3': (const Size(320, 568), 1, 1.3),
      '411x914': (const Size(411, 914), 1, 1),
      '1080x2400 @3x': (const Size(1080, 2400), 3, 1),
      '1080x2400 @3x text 1.3': (const Size(1080, 2400), 3, 1.3),
    };
    sizes.forEach((tag, sz) {
      pages.forEach((name, p) {
        testWidgets('$name $tag', (tester) async {
          _size(tester, sz.$1, dpr: sz.$2);
          tester.platformDispatcher.textScaleFactorTestValue = sz.$3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final found = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final t = d.exceptionAsString();
            if (t.contains('overflowed') || t.contains('RenderFlex')) {
              found.add(t.split('\n').first);
              return;
            }
            prev?.call(d);
          };
          try {
            await http.runWithClient(() async {
              await tester.pumpWidget(_app(p.$1(), args: p.$2));
              await _pumpFor(tester);
              expect(find.byType(p.$1().runtimeType), findsOneWidget);
              if (find.byType(Scrollable).evaluate().isNotEmpty) {
                await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000), warnIfMissed: false);
                await _pumpFor(tester, 300);
              }
              await _teardown(tester);
            }, () => _client);
          } finally {
            FlutterError.onError = prev;
          }
          expect(found, isEmpty, reason: '$name overflowed at $tag: $found');
        });
      });
    });
  });

  // ── Reduced motion: the branded pieces are final on the first frame ───────
  testWidgets('reduced motion: stepper, ring and CTA are final on the first frame', (tester) async {
    _size(tester, const Size(411, 914));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const DocumentUploadPage()));
      // First frame, before any time passes.
      expect(tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('reg_step_line_3'))).widthFactor, 1.0,
          reason: 'segment into the current step already full');
      final scale = tester.widget<Transform>(find.ancestor(
          of: find.byKey(const ValueKey('reg_step_dot_4')), matching: find.byType(Transform)).first);
      expect(scale.transform.getMaxScaleOnAxis(), closeTo(1.0, 1e-9), reason: 'current dot not mid-pop');
      expect(find.byType(RegProgressRing), findsOneWidget);
      for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
        expect(o.opacity, 1.0);
      }
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await _teardown(tester);
    }, () => _client);
  });

  testWidgets('RegCta: disabled is grey with its helper label and does nothing', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const RegCta(label: 'Complete all required documents to continue', onPressed: null),
      RegCta(label: 'Go', onPressed: () => taps++),
    ]))));
    await tester.tap(find.text('Complete all required documents to continue'));
    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
    expect(tester.getSize(find.byType(RegCta).first).height, greaterThanOrEqualTo(56));
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget, reason: 'arrow only on the active CTA');
  });
}
