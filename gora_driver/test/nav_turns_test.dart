import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/widgets/nav_engine.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';

import 'voice_guidance_test.dart' show encodePolyline;

// ─────────────────────────────────────────────────────────────────────────────
// Turn-by-turn names the turn AHEAD. A route step's instruction is the
// manoeuvre that leads onto it; the banner and the voice used the step being
// driven, so they named the turn already taken — "Turn left onto the ring road"
// while on the ring road, with the distance to the right turn off it. And the
// step being driven was found with a test that held for almost every step
// already driven, so after a turn it stayed on the road before it.
// ─────────────────────────────────────────────────────────────────────────────

// North up CG Road, right along the Ring Road, left up Prahlad Nagar Road.
const _a = LatLng(23.000, 72.500);
const _b = LatLng(23.010, 72.500);
const _c = LatLng(23.010, 72.510);
const _d = LatLng(23.020, 72.510);
final _route = [_a, _b, _c, _d];

NavStep _step(String text, String maneuver, LatLng from, LatLng to) => NavStep(
  instruction: text, maneuver: maneuver, distanceM: metersBetween(from, to).round(),
  durationSec: 60, start: from, end: to);

final _steps = [
  _step('Head north on CG Road', '', _a, _b),
  _step('Turn right onto Ring Road', 'turn-right', _b, _c),
  _step('Turn left onto Prahlad Nagar Road', 'turn-left', _c, _d),
];

NavProgress _at(LatLng me) =>
    computeProgress(me: me, route: _route, remaining: remainingDistances(_route), steps: _steps);

void main() {
  group('where the driver is, and the turn ahead', () {
    test('at the start: on CG Road, the right turn ahead', () {
      final p = _at(const LatLng(23.001, 72.500));
      expect(p.activeStep!.instruction, 'Head north on CG Road');
      expect(p.nextStep!.instruction, 'Turn right onto Ring Road');
      expect(p.toManeuverM, closeTo(metersBetween(const LatLng(23.001, 72.5), _b), 5));
    });

    test('after the right turn: on the Ring Road, the left turn ahead', () {
      final p = _at(const LatLng(23.010, 72.503));   // 300 m past the turn
      expect(p.activeStep!.instruction, 'Turn right onto Ring Road');
      expect(p.nextStep!.instruction, 'Turn left onto Prahlad Nagar Road');
      expect(p.toManeuverM, closeTo(metersBetween(const LatLng(23.010, 72.503), _c), 5),
          reason: 'along the road to the next turn, not back to the last one');
    });

    test('on the last stretch: nothing but the destination ahead', () {
      final p = _at(const LatLng(23.015, 72.510));
      expect(p.activeStep!.instruction, 'Turn left onto Prahlad Nagar Road');
      expect(p.nextStep, isNull);
      expect(p.toManeuverM, closeTo(metersBetween(const LatLng(23.015, 72.510), _d), 5));
    });

    test('distance left is measured from the driver, not the segment start', () {
      final p = _at(const LatLng(23.005, 72.500));   // halfway up CG Road
      final exact = metersBetween(const LatLng(23.005, 72.5), _b) + metersBetween(_b, _c) + metersBetween(_c, _d);
      expect(p.remainingM, closeTo(exact, 5));
    });

    test('a route through the same junction twice is read in order', () {
      // Out along the Ring Road and back past where it began.
      final route = [_a, _b, _c, _b, _a];
      final steps = [
        _step('Head north on CG Road', '', _a, _b),
        _step('Turn right onto Ring Road', 'turn-right', _b, _c),
        _step('Make a U-turn', 'uturn-left', _c, _b),
        _step('Turn left onto CG Road', 'turn-left', _b, _a),
      ];
      final p = computeProgress(me: const LatLng(23.010, 72.506), route: route,
          remaining: remainingDistances(route), steps: steps, stepEnds: stepEndIndices(route, steps));
      expect(p.activeStep!.instruction, 'Turn right onto Ring Road', reason: 'on the way out, before the U-turn');
      expect(p.nextStep!.instruction, 'Make a U-turn');
    });
  });

  // ── On the real navigation map ──
  group('the banner and the voice', () {
    MockStreamHandlerEventSink? gps;
    late List<String> spoken;

    void installMocks() {
      spoken = [];
      SharedPreferences.setMockInitialValues({});
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => call.method == 'isLocationServiceEnabled' ? false : null);
      m.setMockStreamHandler(const EventChannel('flutter.baseflow.com/geolocator_updates'),
          MockStreamHandler.inline(onListen: (_, sink) { gps = sink; }, onCancel: (_) { gps = null; }));
      m.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (call) async {
        if (call.method == 'speak') spoken.add('${call.arguments}');
        if (call.method == 'getLanguages') return ['en-IN', 'en-US'];
        return 1;
      });
    }

    Map<String, dynamic> fix(LatLng p) => {
      'latitude': p.latitude, 'longitude': p.longitude, 'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 5.0, 'altitude': 0.0, 'altitude_accuracy': 0.0, 'heading': 0.0,
      'heading_accuracy': 0.0, 'speed': 10.0, 'speed_accuracy': 0.0, 'is_mocked': false,
    };

    MockClient api() => MockClient((req) async {
      if (!req.url.path.endsWith('/directions')) return http.Response('{}', 200);
      return http.Response(jsonEncode({
        'polyline': encodePolyline([for (final p in _route) [p.latitude, p.longitude]]),
        'durationMin': 8, 'distanceKm': 3.2,
        'steps': [
          for (final s in _steps)
            {'instruction': s.instruction, 'maneuver': s.maneuver, 'distanceM': s.distanceM, 'durationSec': 60,
             'startLat': s.start.latitude, 'startLng': s.start.longitude,
             'endLat': s.end.latitude, 'endLng': s.end.longitude},
        ],
      }), 200);
    });

    Future<void> driveTo(WidgetTester tester, LatLng p) async {
      gps!.success(fix(p));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> open(WidgetTester tester, Future<void> Function() drive) async {
      installMocks();
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavMapPanel(
          leg: NavLeg(label: 'Drop', destLat: _d.latitude, destLng: _d.longitude),
          height: 700,
        ))));
        await tester.pump(const Duration(milliseconds: 300));
        await driveTo(tester, const LatLng(23.0005, 72.500));   // the route is fetched
        await driveTo(tester, const LatLng(23.001, 72.500));
        await drive();
      }, api);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('setting off: where to go is said, and the first turn is shown', (tester) async {
      await open(tester, () async {});
      expect(find.text('Turn right onto Ring Road'), findsOneWidget);
      expect(find.byIcon(Icons.turn_right), findsOneWidget);
      expect(spoken, contains('Head north on CG Road'));
      await close(tester);
    });

    testWidgets('on the Ring Road: the left turn off it, not the right turn onto it', (tester) async {
      await open(tester, () async {
        await driveTo(tester, const LatLng(23.0095, 72.500));
        await driveTo(tester, const LatLng(23.010, 72.503));
      });
      expect(find.text('Turn left onto Prahlad Nagar Road'), findsOneWidget);
      expect(find.text('Turn right onto Ring Road'), findsNothing);
      expect(find.byIcon(Icons.turn_left), findsOneWidget);
      expect(find.text(formatDistance(metersBetween(const LatLng(23.010, 72.503), _c))), findsOneWidget);
      await close(tester);
    });

    testWidgets('coming up to a turn, the voice names that turn', (tester) async {
      await open(tester, () async {
        await driveTo(tester, const LatLng(23.0065, 72.500));   // ~390 m before the right turn
        await driveTo(tester, const LatLng(23.0095, 72.500));   // ~55 m before it
        await driveTo(tester, const LatLng(23.010, 72.5065));   // ~360 m before the left turn
        await driveTo(tester, const LatLng(23.010, 72.5095));   // ~50 m before it
      });
      expect(spoken, containsAllInOrder([
        'In 400 metres, turn right onto Ring Road',
        'Turn right onto Ring Road',
        'In 350 metres, turn left onto Prahlad Nagar Road',
        'Turn left onto Prahlad Nagar Road',
      ]));
      expect(spoken.where((s) => s.contains('Ring Road')), hasLength(2),
          reason: 'the right turn is not counted down again once taken');
      await close(tester);
    });

    testWidgets('on the last stretch: the destination is what lies ahead', (tester) async {
      await open(tester, () async {
        await driveTo(tester, const LatLng(23.010, 72.5095));
        await driveTo(tester, const LatLng(23.0125, 72.510));
      });
      expect(find.text('Arrive at the drop'), findsOneWidget);
      expect(find.byIcon(Icons.place), findsWidgets);
      expect(find.text('Turn left onto Prahlad Nagar Road'), findsNothing);
      await close(tester);
    });
  });
}
