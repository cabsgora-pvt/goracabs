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
import 'package:gora_driver/features/ride/widgets/voice_guide.dart';
import 'package:gora_driver/features/ride/widgets/voice_settings_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// #9 — voice guidance: Hindi, settings, reroutes, and never talking over Google
// Maps. The speech engine is a mock channel that records every call, so each
// test checks what the driver would actually hear.
// ─────────────────────────────────────────────────────────────────────────────

class Tts {
  final calls = <MethodCall>[];
  Set<String> voices = {'en-IN', 'hi-IN'};

  List<String> get spoken => calls
      .where((c) => c.method == 'speak')
      .map((c) => c.arguments is Map ? (c.arguments as Map)['text'] as String : c.arguments as String)
      .toList();

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        calls.add(call);
        if (call.method == 'isLanguageAvailable') return voices.contains(call.arguments);
        return 1;
      },
    );
  }
}

NavStep step(String instruction) => const NavStep(
  instruction: '',
  maneuver: 'turn-right',
  distanceM: 500,
  durationSec: 60,
  start: LatLng(23.0225, 72.5714),
  end: LatLng(23.0275, 72.5764),
).copyWithInstruction(instruction);

extension on NavStep {
  NavStep copyWithInstruction(String text) => NavStep(
    instruction: text, maneuver: maneuver, distanceM: distanceM,
    durationSec: durationSec, start: start, end: end);
}

/// Google's polyline encoding, for a directions response the map will follow.
String encodePolyline(List<List<double>> pts) {
  final out = StringBuffer();
  var lastLat = 0, lastLng = 0;
  void emit(int v) {
    v = v < 0 ? ~(v << 1) : v << 1;
    while (v >= 0x20) { out.writeCharCode((0x20 | (v & 0x1f)) + 63); v >>= 5; }
    out.writeCharCode(v + 63);
  }
  for (final p in pts) {
    final lat = (p[0] * 1e5).round(), lng = (p[1] * 1e5).round();
    emit(lat - lastLat); emit(lng - lastLng);
    lastLat = lat; lastLng = lng;
  }
  return out.toString();
}

void main() {
  late Tts tts;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tts = Tts()..install();
  });

  // ── What is said ──
  group('Hindi phrases', () {
    test('the first prompt counts down in Hindi', () {
      final a = NavAnnouncer(language: VoiceLanguage.hindi);
      final p = a.update(step: step('S G Hwy पर दाएँ मुड़ें'), toManeuverM: 380, arrived: false, destinationLabel: 'Drop');
      expect(p, '400 मीटर बाद, S G Highway पर दाएँ मुड़ें');
    });

    test('distances are spoken in Hindi units', () {
      expect(NavAnnouncer.spokenDistance(1260, language: VoiceLanguage.hindi), '1.3 किलोमीटर');
      expect(NavAnnouncer.spokenDistance(412, language: VoiceLanguage.hindi), '400 मीटर');
    });

    test('arrival names the place in Hindi', () {
      expect(NavAnnouncer(language: VoiceLanguage.hindi)
          .update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Pickup'),
          'आप पिकअप पर पहुँच गए हैं');
      expect(NavAnnouncer(language: VoiceLanguage.hindi)
          .update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Stop 2'),
          'आप स्टॉप 2 पर पहुँच गए हैं');
    });

    test('highway numbers are read as words, not letters', () {
      expect(NavAnnouncer.spokenInstruction('NH48 पर दाएँ मुड़ें', language: VoiceLanguage.hindi),
          'नेशनल हाईवे 48 पर दाएँ मुड़ें');
    });

    test('English is unchanged', () {
      final a = NavAnnouncer();
      expect(a.update(step: step('Turn right onto S G Hwy'), toManeuverM: 380, arrived: false, destinationLabel: 'Drop'),
          'In 400 metres, turn right onto S G Highway');
    });
  });

  group('reroutes', () {
    test('announced, but not again within the quiet period', () {
      final a = NavAnnouncer();
      final t0 = DateTime(2026, 9, 17, 10);
      expect(a.rerouted(now: t0), 'Rerouting');
      expect(a.rerouted(now: t0.add(const Duration(seconds: 10))), isNull);
      expect(a.rerouted(now: t0.add(const Duration(seconds: 31))), 'Rerouting');
    });

    test('in Hindi', () {
      expect(NavAnnouncer(language: VoiceLanguage.hindi).rerouted(), 'नया रास्ता ढूँढा जा रहा है');
    });
  });

  // ── Which voice speaks ──
  group('voice language', () {
    test('Hindi chosen and installed: a Hindi voice', () async {
      SharedPreferences.setMockInitialValues({VoiceGuide.languageKey: 'hi'});
      final v = VoiceGuide();
      await v.init();
      expect(v.language, VoiceLanguage.hindi);
      expect(tts.calls.where((c) => c.method == 'setLanguage').last.arguments, 'hi-IN');
    });

    test('Hindi chosen but not installed: English, not Hindi read by an English voice', () async {
      SharedPreferences.setMockInitialValues({VoiceGuide.languageKey: 'hi'});
      tts.voices = {'en-IN'};
      final v = VoiceGuide();
      await v.init();
      expect(v.preferredLanguage, VoiceLanguage.hindi);
      expect(v.language, VoiceLanguage.english);
      expect(v.hindiAvailable, isFalse);
      expect(tts.calls.where((c) => c.method == 'setLanguage').last.arguments, 'en-IN');
    });

    test('a muted guide stays silent, except for a sample the driver asked for', () async {
      final v = VoiceGuide();
      await v.init();
      await v.setMuted(true);
      await v.say('Turn left');
      expect(tts.spoken, isEmpty);
      await v.say('Sample', evenIfMuted: true);
      expect(tts.spoken, ['Sample']);
    });
  });

  // ── Settings ──
  group('voice settings', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VoiceSettingsCard())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('choosing हिंदी saves it and plays the Hindi sample', (tester) async {
      await open(tester);
      await tester.tap(find.text('हिंदी'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VoiceGuide.languageKey), 'hi');
      expect(tts.spoken.last, NavAnnouncer.samplePhrase(VoiceLanguage.hindi));
      expect(find.textContaining('no Hindi voice'), findsNothing);
    });

    testWidgets('without a Hindi voice it says so, and the sample stays English', (tester) async {
      tts.voices = {'en-IN'};
      await open(tester);
      await tester.tap(find.text('हिंदी'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('no Hindi voice'), findsOneWidget);
      expect(tts.spoken.last, NavAnnouncer.samplePhrase(VoiceLanguage.english));
    });

    testWidgets('the switch is the same setting as the map\'s mute button', (tester) async {
      await open(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(VoiceGuide.mutedKey), isTrue);
      // A sample still plays when asked for.
      await tester.tap(find.text('Play a sample'));
      await tester.pump();
      expect(tts.spoken, isNotEmpty);
    });
  });

  // ── On the real navigation map ──
  group('navigation map', () {
    const pickup = NavLeg(label: 'Pickup', destLat: 23.0225, destLng: 72.5714, destAddress: 'Navrangpura');
    const drop = NavLeg(label: 'Drop', destLat: 23.0732, destLng: 72.6208, destAddress: 'Bodakdev');

    late List<Uri> requests;
    MockStreamHandlerEventSink? gps;
    late bool launched;

    // Installed from inside each test body: a mock stream handler set in setUp
    // never reaches a testWidgets body, so the map would receive no GPS at all.
    void installMocks() {
      requests = [];
      launched = false;
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => call.method == 'isLocationServiceEnabled' ? false : null);
      m.setMockStreamHandler(const EventChannel('flutter.baseflow.com/geolocator_updates'),
          MockStreamHandler.inline(onListen: (_, sink) { gps = sink; }, onCancel: (_) { gps = null; }));
      m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async { launched = true; return true; });
    }

    Map<String, dynamic> fix(double lat, double lng) => {
      'latitude': lat, 'longitude': lng, 'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 5.0, 'altitude': 0.0, 'altitude_accuracy': 0.0, 'heading': 0.0,
      'heading_accuracy': 0.0, 'speed': 0.0, 'speed_accuracy': 0.0, 'is_mocked': false,
    };

    MockClient api() => MockClient((req) async {
      requests.add(req.url);
      return http.Response(jsonEncode({'error': 'No route found'}), 200);
    });

    Widget map(NavLeg leg) => MaterialApp(home: Scaffold(body: NavMapPanel(leg: leg, height: 600)));

    Future<void> drive(WidgetTester tester, Future<void> Function() body) =>
        http.runWithClient(body, api);

    Future<void> arriveAt(WidgetTester tester, NavLeg leg) async {
      gps!.success(fix(leg.destLat!, leg.destLng!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    // A route whose second stretch is a toll road: reaching it tells the host
    // and says so aloud.
    Future<List<NavStep>> onTollRoute(WidgetTester tester, {required bool handled}) async {
      final reached = <NavStep>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavMapPanel(
          leg: const NavLeg(label: 'Drop', destLat: 23.05, destLng: 72.5),
          height: 600,
          onTollRoad: handled ? reached.add : null,
        ))));
        await tester.pump(const Duration(milliseconds: 300));
        gps!.success(fix(23.001, 72.5));      // start: the route is fetched
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        gps!.success(fix(23.03, 72.5));       // on the toll road
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }, () => MockClient((req) async {
        if (!req.url.path.endsWith('/directions')) return http.Response('{}', 200);
        return http.Response(jsonEncode({
          'polyline': encodePolyline([[23.0, 72.5], [23.02, 72.5], [23.05, 72.5]]),
          'durationMin': 6, 'distanceKm': 5.5,
          'steps': [
            {'instruction': 'Head north', 'maneuver': '', 'distanceM': 2200, 'durationSec': 120,
             'startLat': 23.0, 'startLng': 72.5, 'endLat': 23.02, 'endLng': 72.5, 'toll': false},
            {'instruction': 'Continue onto NH48. Toll road', 'maneuver': 'straight', 'distanceM': 3300, 'durationSec': 200,
             'startLat': 23.02, 'startLng': 72.5, 'endLat': 23.05, 'endLng': 72.5, 'toll': true},
          ],
        }), 200);
      }));
      return reached;
    }

    testWidgets('reaching a toll road: the screen is told, and it is said aloud', (tester) async {
      installMocks();
      final reached = await onTollRoute(tester, handled: true);
      expect(reached, hasLength(1));
      expect(reached.single.toll, isTrue);
      expect(tts.spoken, contains(NavAnnouncer.tollPhrase(VoiceLanguage.english)));
      await close(tester);
    });

    testWidgets('where tolls are not recorded, no toll prompt is spoken', (tester) async {
      installMocks();
      await onTollRoute(tester, handled: false);
      expect(tts.spoken, isNot(contains(NavAnnouncer.tollPhrase(VoiceLanguage.english))));
      await close(tester);
    });

    testWidgets('control: arriving is announced', (tester) async {
      installMocks();
      await drive(tester, () async {
        await tester.pumpWidget(map(pickup));
        await tester.pump(const Duration(milliseconds: 300));
        await arriveAt(tester, pickup);
      });
      expect(tts.spoken, contains('You have arrived at the pickup'));
      await close(tester);
    });

    testWidgets('after handing off to Google Maps it stays silent, and speaks again on return', (tester) async {
      installMocks();
      await drive(tester, () async {
        await tester.pumpWidget(map(pickup));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Navigate to Pickup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(launched, isTrue);

        // Google Maps is guiding: its voice, not ours.
        await arriveAt(tester, pickup);
        expect(tts.spoken, isEmpty, reason: 'Two voices announcing the same turn');

        // The driver comes back; the next leg is ours again.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(map(drop));
        await tester.pump(const Duration(milliseconds: 100));
        await arriveAt(tester, drop);
      });
      expect(tts.spoken, ['You have arrived at the drop']);
      await close(tester);
    });

    // Nothing else is guiding when the hand-off fails, so this voice must not
    // go quiet on the strength of a tap alone.
    testWidgets('if Google Maps could not open, guidance carries on', (tester) async {
      installMocks();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'), (call) async => false);
      await drive(tester, () async {
        await tester.pumpWidget(map(pickup));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Navigate to Pickup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await arriveAt(tester, pickup);
      });
      expect(tts.spoken, contains('You have arrived at the pickup'));
      await close(tester);
    });

    testWidgets('in Hindi: Hindi directions and a Hindi voice', (tester) async {
      installMocks();
      SharedPreferences.setMockInitialValues({VoiceGuide.languageKey: 'hi'});
      await drive(tester, () async {
        await tester.pumpWidget(map(pickup));
        await tester.pump(const Duration(milliseconds: 300));
        await arriveAt(tester, pickup);
      });
      expect(tts.spoken, contains('आप पिकअप पर पहुँच गए हैं'));
      final directions = requests.where((u) => u.path.endsWith('/directions'));
      expect(directions, isNotEmpty);
      expect(directions.last.queryParameters['language'], 'hi');
      await close(tester);
    });

    testWidgets('muted from the map or settings: nothing is spoken', (tester) async {
      installMocks();
      SharedPreferences.setMockInitialValues({VoiceGuide.mutedKey: true});
      await drive(tester, () async {
        await tester.pumpWidget(map(pickup));
        await tester.pump(const Duration(milliseconds: 300));
        await arriveAt(tester, pickup);
      });
      expect(tts.spoken, isEmpty);
      await close(tester);
    });
  });
}
