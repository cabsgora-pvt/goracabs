import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/app/app_routes.dart';
import 'package:gora_driver/core/theme/app_theme.dart';
import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/auth/pages/driver_otp_page.dart';
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
import 'package:gora_driver/features/registration/widgets/status_views.dart';
import 'package:gora_driver/features/splash/splash_page.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Registration without the bank step, and the redesigned flow's motion.
//
//  * The documents step submits the application (finish: true) and opens
//    "Application submitted" with nothing to go back to.
//  * A driver resuming at server step 'bank' (documents saved by an older
//    build) is never shown a bank form: the app calls /register/submit and goes
//    to "under review", or — on a 400 — back to the documents with the reason.
//  * Every step says "Step N of 4".
//  * Reduced motion: pages render their final state with no animation running.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final calls = <http.Request>[];
http.Response? Function(http.Request req) api = (_) => null;

MockClient get _client => MockClient((req) async {
      calls.add(req);
      return api(req) ?? _base(req) ?? _json({});
    });

/// Answers every page of the flow needs, unless a test overrides it.
http.Response? _base(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/zones')) return _json({'zones': [{'_id': 'z1', 'name': 'Rajkot'}]});
  if (p.endsWith('/vehicles/types')) {
    return _json({'types': [
      {'_id': 'v1', 'name': 'Bike', 'services': ['taxi'], 'isActive': true},
      {'_id': 'v2', 'name': 'Cab', 'services': ['taxi'], 'isActive': true},
    ]});
  }
  if (p.endsWith('/document-types')) {
    return _json({'documents': [
      {'key': 'police', 'name': 'Police Verification', 'required': false, 'category': 'identity'},
    ]});
  }
  if (p.endsWith('/auth/driver/profile')) {
    return _json({'driver': {'_id': 'd1', 'status': 'pending', 'registrationStep': 'submitted'}});
  }
  return null;
}

bool _is(http.Request r, String method, String pathEnd) => r.method == method && r.url.path.endsWith(pathEnd);
List<http.Request> _sent(String method, String pathEnd) => calls.where((r) => _is(r, method, pathEnd)).toList();
Map<String, dynamic> _bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

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

/// Unmounts everything (stops KYC polling timers) and drops stray exceptions.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  while (tester.takeException() != null) {}
}

final _navKey = GlobalKey<NavigatorState>();

/// The real route table, with [home] as the only route and [args] as its
/// arguments.
Widget _app(Widget home, {Object? args}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(),
        child: MaterialApp(
          navigatorKey: _navKey,
          theme: AppTheme.light,
          routes: {...AppRoutes.routes},
          initialRoute: '/reg-test',
          onGenerateInitialRoutes: (name) => [
            MaterialPageRoute(settings: RouteSettings(name: name, arguments: args), builder: (_) => home),
          ],
        ),
      ),
    );

void main() {
  setUp(() {
    calls.clear();
    api = (_) => null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
  });

  // ── A. Documents step submits the application ─────────────────────────────
  group('documents submit finishes registration', () {
    testWidgets('sends finish:true with the same documents and opens "Application submitted", stack cleared',
        (tester) async {
      _size(tester);
      api = (r) => _is(r, 'POST', '/register/documents')
          ? _json({'success': true, 'registrationStep': 'submitted'})
          : null;
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const DocumentUploadPage()));
        await _pumpFor(tester);
        await tester.tap(find.text('Submit documents'));
        await _pumpFor(tester);
        final sent = _sent('POST', '/register/documents');
        expect(sent, hasLength(1));
        final body = _bodyOf(sent.single);
        expect(body['finish'], isTrue);
        expect(body.keys.toSet(), {'documents', 'finish'}, reason: 'only the documents + the finish flag');
        expect(body['documents'], isEmpty, reason: 'an unfilled optional document is still not sent');
        expect(find.byType(KycSuccessPage), findsOneWidget);
        expect(find.text('Application submitted'), findsWidgets);
        expect(_navKey.currentState!.canPop(), isFalse, reason: 'nothing to go back to after submitting');
        expect(_sent('POST', '/register/bank'), isEmpty);
        await _teardown(tester);
      }, () => _client);
    });

    testWidgets('a filled document is sent exactly as before, plus finish:true', (tester) async {
      _size(tester);
      api = (r) {
        if (_is(r, 'GET', '/document-types')) {
          return _json({'documents': [{'key': 'pan', 'name': 'PAN Card', 'numberLabel': 'PAN Number', 'required': true}]});
        }
        if (_is(r, 'POST', '/register/documents')) return _json({'success': true, 'registrationStep': 'submitted'});
        return null;
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const DocumentUploadPage()));
        await _pumpFor(tester);
        // Fill the document through its detail page (Save returns the data).
        await tester.tap(find.text('PAN Card'));
        await _pumpFor(tester);
        expect(find.byType(DocumentDetailPage), findsOneWidget);
        // No image picker in tests: return what Save returns for a filled-in
        // number + uploaded photo.
        _navKey.currentState!.pop(DocData(number: 'ABCDE1234F', frontUrl: 'https://x/pan.jpg'));
        await _pumpFor(tester);
        expect(find.text('Uploaded'), findsOneWidget, reason: 'the card turns complete');
        await tester.tap(find.text('Submit documents'));
        await _pumpFor(tester);
      }, () => _client);
      final body = _bodyOf(_sent('POST', '/register/documents').single);
      expect(body['finish'], isTrue);
      expect(body['documents'], [
        {'type': 'pan', 'name': 'PAN Card', 'number': 'ABCDE1234F', 'frontUrl': 'https://x/pan.jpg',
          'fileUrl': 'https://x/pan.jpg'},
      ]);
      expect(find.byType(KycSuccessPage), findsOneWidget);
      await _teardown(tester);
    });
  });

  // ── B. Resuming at server step 'bank' ─────────────────────────────────────
  group("resume at 'bank' submits instead of showing a bank form", () {
    Map<String, dynamic> bankDriver() => {
          '_id': 'd1', 'name': 'Suresh Kumar', 'phone': '9876543210', 'status': 'pending',
          'registrationStep': 'bank', 'faceSignatureSavedAt': '2026-10-27T10:00:00.000Z',
          'selectedVehicleTypeName': 'Cab',
        };

    test('resumeStepFor maps bank to submit', () {
      expect(resumeStepFor({'registrationStep': 'bank'}), ResumeStep.submit);
    });

    testWidgets('relaunch: splash → /register/submit (empty body) → under review', (tester) async {
      _size(tester);
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/profile')) return _json({'driver': bankDriver()});
        if (_is(r, 'POST', '/register/submit')) return _json({'success': true, 'registrationStep': 'submitted'});
        return null;
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const SplashPage()));
        await _pumpFor(tester, 3200);
        final sent = _sent('POST', '/register/submit');
        expect(sent, hasLength(1));
        expect(_bodyOf(sent.single), isEmpty);
        expect(sent.single.headers['Authorization'], 'Bearer t');
        expect(find.byType(KycSuccessPage), findsOneWidget);
        expect(find.byType(SubmitApplicationPage), findsNothing);
        expect(_navKey.currentState!.canPop(), isFalse);
        expect(find.textContaining('bank', findRichText: true), findsNothing, reason: 'no bank form anywhere');
        expect(_sent('POST', '/register/bank'), isEmpty);
        await _teardown(tester);
      }, () => _client);
    });

    testWidgets('OTP login at step bank → /register/submit → under review', (tester) async {
      _size(tester);
      SharedPreferences.setMockInitialValues({});
      api = (r) {
        if (_is(r, 'POST', '/verify-otp')) {
          return _json({'token': 'tok', 'driver': bankDriver(), 'registrationStep': 'bank'});
        }
        if (_is(r, 'POST', '/register/submit')) return _json({'success': true, 'registrationStep': 'submitted'});
        return null;
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const DriverOtpPage(), args: '9876543210'));
        await _pumpFor(tester, 300);
        final boxes = find.byType(TextFormField);
        for (var i = 0; i < 6; i++) {
          await tester.enterText(boxes.at(i), '${i + 1}');
          await tester.pump();
        }
        await _pumpFor(tester, 1200);
        expect(_sent('POST', '/register/submit'), hasLength(1));
        expect(find.byType(KycSuccessPage), findsOneWidget);
        expect(_sent('POST', '/register/bank'), isEmpty);
        expect(_sent('POST', '/send-otp'), isEmpty);
        await _teardown(tester);
      }, () => _client);
    });

    testWidgets('a 400 opens the documents page with the server message, stack cleared', (tester) async {
      _size(tester);
      const msg = 'Please upload: RC Book';
      api = (r) {
        if (_is(r, 'GET', '/auth/driver/profile')) return _json({'driver': bankDriver()});
        if (_is(r, 'POST', '/register/submit')) return _json({'error': msg}, 400);
        return null;
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const SplashPage()));
        await _pumpFor(tester, 3200);
        expect(_sent('POST', '/register/submit'), hasLength(1));
        expect(find.byType(DocumentUploadPage), findsOneWidget);
        expect(find.byType(KycSuccessPage), findsNothing);
        expect(find.descendant(of: find.byKey(const ValueKey('doc_submit_error')), matching: find.text(msg)),
            findsOneWidget);
        expect(_navKey.currentState!.canPop(), isFalse);
        // The documents asked for are still those of the driver's vehicle type.
        final docTypeCall = _sent('GET', '/document-types').last;
        expect(docTypeCall.url.queryParameters['vehicleType'], 'Cab');
        await _teardown(tester);
      }, () => _client);
    });

    testWidgets('server error / offline: stays put with a retry that calls again', (tester) async {
      _size(tester);
      var n = 0;
      api = (r) {
        if (_is(r, 'POST', '/register/submit')) {
          n++;
          return n == 1
              ? http.Response('<html>502 Bad Gateway</html>', 502)
              : _json({'success': true, 'registrationStep': 'submitted'});
        }
        return null;
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const SubmitApplicationPage(), args: {'driver': bankDriver()}));
        await _pumpFor(tester);
        expect(find.byType(SubmitApplicationPage), findsOneWidget);
        expect(find.byType(DocumentUploadPage), findsNothing, reason: 'a 5xx is not "documents incomplete"');
        expect(find.byKey(const ValueKey('submit_error')), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await _pumpFor(tester);
        expect(_sent('POST', '/register/submit'), hasLength(2));
        expect(find.byType(KycSuccessPage), findsOneWidget);
        await _teardown(tester);
      }, () => _client);
    });
  });

  // ── C. No bank form in registration ───────────────────────────────────────
  group('no bank step left in registration', () {
    test('the route table has no registration bank route', () {
      expect(AppRoutes.routes.keys.where((k) => k.contains('bank')), isEmpty);
      expect(AppRoutes.routes.containsKey('/registration/bank'), isFalse);
      expect(AppRoutes.routes.containsKey(SubmitApplicationPage.route), isTrue);
    });

    test('no app code calls /register/bank or opens a bank page', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('/register/bank') || src.contains('BankDetailsPage') ||
            src.contains('bank_details_page')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    testWidgets('the under-review timeline no longer mentions a bank account', (tester) async {
      _size(tester);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
          home: const UnderReviewView(title: 'Application submitted', subtitle: 's', justSubmitted: true)));
      await _pumpFor(tester, 300);
      expect(find.text('Your details and documents are with us.'), findsOneWidget);
      expect(find.textContaining('bank'), findsNothing);
      await _teardown(tester);
    });
  });

  // ── D. "Step N of 4" everywhere ───────────────────────────────────────────
  testWidgets('every registration step says "of 4"', (tester) async {
    _size(tester);
    const insurance = DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number');
    final cases = <(Widget, Object?, String)>[
      (const PersonalDetailsPage(), {'phone': '9876543210'}, 'Step 1 of 4'),
      (FaceCaptureChrome(stepIndex: 0, stepShort: 'Look straight', instruction: 'Look straight at the camera',
          onCapture: () {}), null, 'Step 2 of 4'),
      (const VehicleSelectionPage(), null, 'Step 3 of 4'),
      (const VehicleDetailsPage(), {'vehicle': {'_id': 'v2', 'name': 'Cab'}}, 'Step 3 of 4'),
      (const DocumentUploadPage(), null, 'Step 4 of 4'),
      (DocumentDetailPage(spec: insurance, initial: DocData()), null, 'Step 4 of 4'),
    ];
    await http.runWithClient(() async {
      for (final (i, (page, args, label)) in cases.indexed) {
        // Unmount first: the shared navigator key would otherwise carry the
        // previous page's routes over.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(KeyedSubtree(key: ValueKey(i), child: _app(page, args: args)));
        await _pumpFor(tester, 600);
        expect(find.text(label), findsOneWidget, reason: '${page.runtimeType}');
        expect(find.textContaining('of 5'), findsNothing, reason: '${page.runtimeType}');
      }
      await _teardown(tester);
    }, () => _client);
  });

  // ── E. Reduced motion ─────────────────────────────────────────────────────
  group('reduced motion', () {
    const insurance = DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number',
        needsBack: true, needsExpiry: true);
    final pages = <String, (Widget Function(), Object?)>{
      'PersonalDetails': (() => const PersonalDetailsPage(), {'phone': '9876543210'}),
      'FaceCaptureChrome': (() => FaceCaptureChrome(stepIndex: 2, stepShort: 'Turn to the other side',
          instruction: 'Now turn to the other side', error: 'Turn to the OTHER side from before.', onCapture: () {}), null),
      'VehicleSelection': (() => const VehicleSelectionPage(), null),
      'VehicleDetails': (() => const VehicleDetailsPage(), {'vehicle': {'_id': 'v2', 'name': 'Cab'}}),
      'DocumentUpload': (() => const DocumentUploadPage(), {'error': 'Please upload: RC Book'}),
      'DocumentDetail': (() => DocumentDetailPage(spec: insurance, initial: DocData(
          number: 'P-1', expiry: '05-07-2030', frontUrl: 'https://x/f.jpg', backUrl: 'https://x/b.jpg')), null),
      'KycSuccess': (() => const KycSuccessPage(), null),
      'KycPending': (() => const KycPendingPage(), null),
      'Rejection': (() => const RejectionPage(), {'reason': 'Blurred licence photo.'}),
    };

    pages.forEach((name, p) {
      testWidgets('$name: final state at once, no animation left running', (tester) async {
        _size(tester, const Size(360, 800));
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await http.runWithClient(() async {
          await tester.pumpWidget(_app(p.$1(), args: p.$2));
          // First frame: already the final state. (Flutter itself only speeds
          // controllers up under this flag, so a page that still started an
          // entrance would show it here at opacity 0.)
          void allOpaque() {
            for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
              expect(o.opacity, 1.0, reason: 'an entrance is still fading in');
            }
          }
          allOpaque();
          await _pumpFor(tester, 300); // network replies land
          allOpaque();
          await tester.pump();
          expect(tester.binding.transientCallbackCount, 0,
              reason: 'no ticker (entrance, pulse, progress, spinner) may still be running');
          expect(tester.binding.hasScheduledFrame, isFalse);
          // Nothing is mid-fade: every entrance is fully opaque.
          for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
            expect(o.opacity, 1.0);
          }
          await _teardown(tester);
        }, () => _client);
      });
    });

    testWidgets('control: with motion on, the same pages do animate', (tester) async {
      _size(tester, const Size(360, 800));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const KycSuccessPage()));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await _teardown(tester);
        await tester.pumpWidget(_app(const PersonalDetailsPage(), args: {'phone': '9876543210'}));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await _pumpFor(tester, 1500);
        expect(tester.binding.transientCallbackCount, 0, reason: 'entrances are finite');
        await _teardown(tester);
      }, () => _client);
    });
  });

  // ── F. Fields are untouched by the redesign ───────────────────────────────
  testWidgets('personal details still sends the same body', (tester) async {
    _size(tester, const Size(400, 1600));
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const PersonalDetailsPage(), args: {
        'driver': {'name': 'Suresh Kumar', 'phone': '9876543210', 'email': 's@x.in', 'state': 'Gujarat',
          'gender': 'male', 'zoneId': 'z1', 'zoneName': 'Rajkot'},
      }));
      await _pumpFor(tester, 800);
      await tester.enterText(find.byType(TextFormField).last, 'ab12');
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester, 800);
    }, () => _client);
    final sent = _sent('POST', '/register/personal');
    expect(sent, hasLength(1));
    expect(_bodyOf(sent.single), {
      'name': 'Suresh Kumar', 'email': 's@x.in', 'state': 'Gujarat', 'zoneId': 'z1', 'zoneName': 'Rajkot',
      'referralCode': 'AB12', 'gender': 'male',
    });
    await _teardown(tester);
  });

  testWidgets('vehicle details sends the same body plus the model year, and validates the same', (tester) async {
    _size(tester);
    // Last year: always the second entry of the picker (next year comes first).
    final year = DateTime.now().year - 1;
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const VehicleDetailsPage(), args: {'vehicle': {'_id': 'v2', 'name': 'Cab'}}));
      await _pumpFor(tester, 800);
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester, 300);
      expect(find.text('Vehicle model is required'), findsOneWidget);
      expect(find.text('Registration number is required'), findsOneWidget);
      expect(find.text('Model year is required'), findsOneWidget, reason: 'v1.5.2: the year is asked for too');
      await tester.enterText(find.byType(TextFormField).at(0), 'Maruti Swift Dzire');
      await tester.enterText(find.byType(TextFormField).at(1), 'gj03ab1234');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await _pumpFor(tester, 500);
      await tester.tap(find.text('$year').last);
      await _pumpFor(tester, 500);
      await tester.tap(find.text('Continue'));
      await _pumpFor(tester, 800);
    }, () => _client);
    expect(_bodyOf(_sent('POST', '/register/vehicle').single), {
      'selectedVehicleTypeId': 'v2', 'selectedVehicleTypeName': 'Cab',
      'vehicleRegistrationNumber': 'GJ03AB1234', 'vehicleModel': 'Maruti Swift Dzire',
      'vehicleYear': year,
    });
    await _teardown(tester);
  });
}
