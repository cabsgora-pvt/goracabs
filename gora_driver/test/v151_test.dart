import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/earnings/bloc/earnings_bloc.dart';
import 'package:gora_driver/features/home/bloc/home_bloc.dart';
import 'package:gora_driver/features/home/pages/home_page.dart';
import 'package:gora_driver/features/registration/document_detail_page.dart';
import 'package:gora_driver/features/registration/registration_draft.dart';
import 'package:gora_driver/features/registration/rejection_page.dart';
import 'package:gora_driver/features/ride/logic/request_announcement.dart';
import 'package:gora_driver/features/ride/pages/collect_fare_page.dart';
import 'package:gora_driver/features/ride/pages/incoming_requests_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/features/ride/widgets/nav_engine.dart';
import 'package:gora_driver/features/ride/widgets/nav_map.dart';
import 'package:gora_driver/features/ride/widgets/otp_dialog.dart';
import 'package:gora_driver/features/ride/widgets/ride_shell.dart';
import 'package:gora_driver/features/ride/widgets/voice_guide.dart';
import 'package:gora_driver/features/ride/widgets/voice_settings_card.dart';
import 'package:gora_driver/features/wallet/bloc/wallet_bloc.dart';
import 'package:gora_driver/features/wallet/pages/withdraw_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/providers/driver_provider.dart';
import 'package:gora_driver/services/location_service.dart';
import 'package:gora_driver/services/ride_alert_service.dart';
import 'package:gora_driver/services/session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// v1.5.1: request alerts (sound, buzz, voice, lock screen), what a request
// card shows, the driver's real UPI QR, the invoice split, earnings / wallet /
// withdrawals from the server with errors that are not ₹0, going online that
// can fail, lighter polling, KYC, and registration drafts.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

final calls = <http.Request>[];
typedef Api = FutureOr<http.Response?> Function(http.Request req);
Api api = (_) => null;

MockClient get _client => MockClient((req) async {
      calls.add(req);
      return await api(req) ?? _json({});
    });

Future<T> withApi<T>(Future<T> Function() body) => http.runWithClient(body, () => _client);

List<http.Request> sent(String method, String pathEnd) =>
    calls.where((c) => c.method == method && c.url.path.endsWith(pathEnd)).toList();

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void phone(WidgetTester tester, [Size size = const Size(400, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
  while (tester.takeException() != null) {}
}

Map<String, dynamic> request(String id, String service, [Map<String, dynamic> extra = const {}]) => {
  'id': id, 'service': service, 'riderName': 'Rahul', 'vehicleType': 'Cab',
  'pickupAddress': 'Law Garden', 'dropAddress': 'Prahlad Nagar',
  'pickupLat': 23.02, 'pickupLng': 72.56, 'dropLat': 23.01, 'dropLng': 72.51,
  'fare': 140, 'tip': 0, 'totalFare': 140, 'distance': 6.2, 'paymentMode': 'cash', 'status': 'pending',
  ...extra,
};

RideRequestModel model(String service, [Map<String, dynamic> extra = const {}]) =>
    RideRequestModel.fromJson(request('r1', service, extra));

class Tts {
  final calls = <MethodCall>[];
  Set<String> voices = {'en-IN', 'hi-IN', 'gu-IN'};
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

/// gora/device: records every call.
final device = <MethodCall>[];

void main() {
  late Tts tts;
  setUp(() {
    calls.clear();
    device.clear();
    api = (_) => null;
    RideAlertService.startImpl = () async => true;
    RideAlertService.stopImpl = () async {};
    RideAlertService.lastStartFailure = null;
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'),
        (c) async => c.method == 'isLocationServiceEnabled' ? false : null);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
    m.setMockMethodCallHandler(const MethodChannel('gora/device'), (c) async {
      device.add(c);
      return true;
    });
    tts = Tts()..install();
  });

  // ── 1. The ringtone, the buzz ────────────────────────────────────────────
  group('request alert', () {
    test('the ringtone plays as an alarm, not media', () {
      final a = requestRingContext.android;
      expect(a.usageType, AndroidUsageType.alarm);
      expect(a.contentType, AndroidContentType.sonification);
      expect(a.stayAwake, isTrue);
    });

    testWidgets('a request vibrates and is read out; declining stops both', (tester) async {
      phone(tester);
      api = (r) => r.url.path.endsWith('/rides/driver/pending')
          ? _json({'rides': [request('t1', 'taxi', {'pickupDistance': 1.2})]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (c) => TextButton(
            onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const IncomingRequestsPage())),
            child: const Text('open'))),
        ));
        await tester.tap(find.text('open'));
        await pumpFor(tester, 800);
        expect(device.where((c) => c.method == 'startVibration'), hasLength(1));
        expect(tts.spoken, ['New ride, 140 rupees, 1.2 kilometres away']);
        // Decline: the last request goes, so the page closes and stops it all.
        await tester.tap(find.byTooltip('Decline'));
        await pumpFor(tester, 800);
        expect(device.where((c) => c.method == 'stopVibration'), isNotEmpty);
        expect(find.byType(IncomingRequestsPage), findsNothing);
      });
      await teardown(tester);
    });

    testWidgets('announcements off: rings, says nothing', (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'driver_token': 't', RequestAnnouncer.enabledKey: false});
      api = (r) => r.url.path.endsWith('/rides/driver/pending') ? _json({'rides': [request('t1', 'taxi')]}) : null;
      await withApi(() async {
        await tester.pumpWidget(const MaterialApp(home: IncomingRequestsPage()));
        await pumpFor(tester, 800);
      });
      expect(tts.spoken, isEmpty);
      expect(device.where((c) => c.method == 'startVibration'), hasLength(1));
      await teardown(tester);
    });

    test('the open request page re-reads the feed every 5 s, not 3', () {
      expect(requestRefreshEvery, const Duration(seconds: 5));
    });
  });

  // ── 2. Lock-screen alert ──────────────────────────────────────────────────
  group('lock-screen alert', () {
    final now = DateTime.utc(2026, 11, 26, 10);
    test('comes down when the offer lapses', () {
      expect(incomingTimeoutMs(now.add(const Duration(seconds: 18)), now: now), 18000);
      expect(incomingTimeoutMs(now.subtract(const Duration(seconds: 3)), now: now), 5000, reason: 'at least 5 s');
      expect(incomingTimeoutMs(null, now: now), openPoolAlertFor.inMilliseconds, reason: 'open pool');
      expect(incomingTimeoutMs(now.add(const Duration(hours: 1)), now: now), 180000);
    });

    test('one request, or "N requests" with the nearest fare', () {
      final one = incomingAlertText([request('a', 'taxi')]);
      expect(one.title, 'New Ride Request  ₹140');
      expect(one.body, 'Law Garden → Prahlad Nagar');
      final three = incomingAlertText([request('a', 'taxi'), request('b', 'taxi'), request('c', 'taxi')]);
      expect(three.title, '3 new ride requests');
      expect(three.body, 'Nearest ₹140 · Law Garden → Prahlad Nagar');
    });

    test('the channel buzzes and plays the bundled sound', () {
      expect(incomingVibration, isNotEmpty);
      expect(incomingSound.sound, 'ride_request');
    });
  });

  // ── 3. Spoken announcement, Gujarati ──────────────────────────────────────
  group('announcement', () {
    test('in English, Hindi and Gujarati', () {
      final r = model('taxi');
      expect(RequestAnnouncer.phrase(r, VoiceLanguage.english, pickupKm: 1.24), 'New ride, 140 rupees, 1.2 kilometres away');
      expect(RequestAnnouncer.phrase(r, VoiceLanguage.hindi, pickupKm: 0.4), 'नई राइड, 140 रुपये, 400 मीटर दूर');
      expect(RequestAnnouncer.phrase(r, VoiceLanguage.gujarati, pickupKm: 2), 'નવી રાઇડ, 140 રૂપિયા, 2 કિલોમીટર દૂર');
      expect(RequestAnnouncer.phrase(model('delivery'), VoiceLanguage.english), 'New parcel delivery, 140 rupees',
          reason: 'no distance when it is not known');
    });

    test('Gujarati is a voice language', () async {
      expect(VoiceLanguage.all, contains(VoiceLanguage.gujarati));
      expect(VoiceLanguage.locale(VoiceLanguage.gujarati), 'gu-IN');
      SharedPreferences.setMockInitialValues({VoiceGuide.languageKey: 'gu'});
      final v = VoiceGuide();
      await v.init();
      expect(v.language, VoiceLanguage.gujarati);
      expect(tts.calls.where((c) => c.method == 'setLanguage').last.arguments, 'gu-IN');
      expect(NavAnnouncer(language: VoiceLanguage.gujarati).rerouted(), 'નવો રસ્તો શોધાઈ રહ્યો છે');
      expect(NavAnnouncer.spokenDistance(450, language: VoiceLanguage.gujarati), '450 મીટર');
    });

    test('Gujarati chosen but not installed: English, and it says so', () async {
      tts.voices = {'en-IN', 'hi-IN'};
      SharedPreferences.setMockInitialValues({VoiceGuide.languageKey: 'gu'});
      final v = VoiceGuide();
      await v.init();
      expect(v.language, VoiceLanguage.english);
      expect(v.preferredMissing, isTrue);
    });

    testWidgets('settings offer ગુજરાતી and the read-out switch', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VoiceSettingsCard()))));
      await pumpFor(tester, 200);
      await tester.tap(find.text('ગુજરાતી'));
      await pumpFor(tester, 200);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VoiceGuide.languageKey), 'gu');
      expect(tts.spoken.last, NavAnnouncer.samplePhrase(VoiceLanguage.gujarati));
      await tester.tap(find.byKey(const ValueKey('announce_requests')));
      await pumpFor(tester, 200);
      expect(prefs.getBool(RequestAnnouncer.enabledKey), isFalse);
    });
  });

  // ── 4/5. What the card shows ──────────────────────────────────────────────
  group('request card', () {
    test('the feed\'s rating and estimate are read; no rating is not 5.0', () {
      final r = model('taxi', {'riderRating': 4.66, 'estDriverEarning': 118});
      expect(r.riderRating, closeTo(4.66, 0.001));
      expect(r.estDriverEarning, 118);
      final none = model('taxi', {'riderRating': null});
      expect(none.riderRating, 0);
      expect(none.estDriverEarning, isNull);
      expect(youGetText(117.6), 'You get ≈ ₹118');
    });

    test('facts per service', () {
      final now = DateTime(2026, 11, 26, 9);
      final out = model('outstation', {
        'riderRating': 4.8, 'cityFrom': 'Ahmedabad', 'cityTo': 'Surat', 'tripType': 'round_trip',
        'returnAt': DateTime(2026, 11, 27, 18, 30).toUtc().toIso8601String(), 'numPassengers': 3,
      });
      expect(requestFacts(out, now: now).map((f) => f.text),
          ['4.8', 'Ahmedabad → Surat', 'Round trip · back Tomorrow, 6:30 PM', '3 passengers']);
      final rental = model('rental', {'packageHours': 4, 'packageKm': 40});
      expect(requestFacts(rental).map((f) => f.text), ['4 hr · 40 km']);
      final hire = model('hire_driver', {'hireTotalHours': 8, 'transmission': 'automatic'});
      expect(requestFacts(hire).map((f) => f.text), ['8 hr hire', 'Automatic']);
      final stops = model('taxi', {'stops': [{'address': 'A'}, {'address': 'B'}], 'numPassengers': 1});
      expect(requestFacts(stops).map((f) => f.text), ['2 stops', '1 passenger']);
      expect(requestFacts(model('taxi')), isEmpty);
    });

    testWidgets('the card shows "You get ≈" and the chips', (tester) async {
      phone(tester);
      api = (r) => r.url.path.endsWith('/rides/driver/pending')
          ? _json({'rides': [request('o1', 'outstation', {
              'riderRating': 4.7, 'estDriverEarning': 112, 'cityFrom': 'Rajkot', 'cityTo': 'Morbi'})]})
          : null;
      await withApi(() async {
        await tester.pumpWidget(const MaterialApp(home: IncomingRequestsPage()));
        await pumpFor(tester, 600);
      });
      expect(find.text('You get ≈ ₹112'), findsOneWidget);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('Rajkot → Morbi'), findsOneWidget);
      await teardown(tester);
    });
  });

  // ── 6. Cash QR ───────────────────────────────────────────────────────────
  group('cash QR', () {
    Widget host(Widget child, {DriverProvider? dp}) => ChangeNotifierProvider.value(
      value: dp ?? DriverProvider(),
      child: MaterialApp(routes: {'/support-tickets': (_) => const Scaffold(body: Text('SUPPORT'))}, home: child),
    );

    test('UPI IDs are checked, never guessed', () {
      expect(normaliseUpiId(' Ravi.K@OkHdfcBank '), 'ravi.k@okhdfcbank');
      expect(normaliseUpiId('9876543210'), isNull);
      expect(normaliseUpiId('a@1bank'), isNull);
      expect(upiPayUri('ravi@okaxis', 'Ravi K', 140), 'upi://pay?pa=ravi%40okaxis&pn=Ravi%20K&am=140&cu=INR');
    });

    testWidgets('no UPI ID on the server: no QR, "Set your UPI ID"; saving goes to the server', (tester) async {
      phone(tester);
      final dp = DriverProvider()..setData({'name': 'Ravi', 'phone': '9876543210'});
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/profile')) return _json({'driver': {'name': 'Ravi', 'phone': '9876543210'}});
        if (r.method == 'PUT' && r.url.path.endsWith('/auth/driver/banks')) {
          return _json({'success': true, 'upiId': 'ravi@okaxis'});
        }
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(host(const CollectFarePage(amount: 140), dp: dp));
        await pumpFor(tester, 300);
        expect(find.byType(QrImageView), findsNothing, reason: 'never a QR for a guessed <phone>@ibl');
        expect(find.byKey(const ValueKey('upi_missing')), findsOneWidget);
        await tester.tap(find.text('Set UPI ID'));
        await pumpFor(tester, 300);
        await tester.enterText(find.byType(TextField), 'not-a-upi');
        await tester.tap(find.text('Save'));
        await pumpFor(tester, 300);
        expect(find.textContaining('like name@okhdfcbank'), findsOneWidget);
        expect(sent('PUT', '/auth/driver/banks'), isEmpty);
        await tester.enterText(find.byType(TextField), 'Ravi@OkAxis');
        await tester.tap(find.text('Save'));
        await pumpFor(tester, 400);
      });
      expect(jsonDecode(sent('PUT', '/auth/driver/banks').single.body), {'upiId': 'ravi@okaxis'});
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('ravi@okaxis'), findsOneWidget);
      expect(dp.data?['upiId'], 'ravi@okaxis');
      await teardown(tester);
    });

    testWidgets('the server\'s UPI ID makes the QR; Help opens support', (tester) async {
      phone(tester);
      api = (r) => r.url.path.endsWith('/auth/driver/profile')
          ? _json({'driver': {'name': 'Ravi', 'upiId': 'ravi@okaxis'}})
          : null;
      await withApi(() async {
        await tester.pumpWidget(host(const CollectFarePage(amount: 140)));
        await pumpFor(tester, 300);
        expect(find.byKey(const ValueKey('upi_qr')), findsOneWidget);
        await tester.tap(find.text('Help'));
        await pumpFor(tester, 400);
      });
      expect(find.text('SUPPORT'), findsOneWidget);
      await teardown(tester);
    });
  });

  // ── 7. Invoice ───────────────────────────────────────────────────────────
  group('invoice', () {
    Future<void> show(WidgetTester tester, RideCompletionArgs args) async {
      phone(tester, const Size(400, 1200));
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (_) => MaterialPageRoute(settings: RouteSettings(arguments: args), builder: (_) => const InvoicePage()),
      ));
      await tester.pump();
    }

    test('the figures: never the gross fare as earning', () {
      final r = model('taxi', {'fare': 100, 'tip': 20, 'totalFare': 120});
      final f = InvoiceFigures.of(RideCompletionArgs(r, driverEarning: 100, adminProfit: 20, fare: 120));
      expect(f.tripFare, 100);
      expect(f.tip, 20);
      expect(f.commission, 20);
      expect(f.net, 100);
      // No driverEarning from an old reply: fare − commission, not the fare.
      final g = InvoiceFigures.of(RideCompletionArgs(r, adminProfit: 20));
      expect(g.net, 100);
    });

    testWidgets('a cash ride: fare, tip, commission, net, and the wallet note', (tester) async {
      final r = model('taxi', {'fare': 100, 'tip': 20, 'totalFare': 120, 'paymentMode': 'cash'});
      await show(tester, RideCompletionArgs(r, driverEarning: 100, adminProfit: 20, fare: 120, paymentMode: 'cash'));
      expect(find.text('₹100'), findsNWidgets(2), reason: 'net headline and the trip fare line');
      expect(find.text('+ ₹20'), findsOneWidget);
      expect(find.text('- ₹20'), findsOneWidget);
      expect(find.text(commissionFromWalletText(20)), findsOneWidget);
    });

    testWidgets('online, unpaid: Pending; no wallet note', (tester) async {
      final r = model('taxi', {'paymentMode': 'online'});
      await show(tester, RideCompletionArgs(r, driverEarning: 112, adminProfit: 28, earningPending: true));
      expect(find.text('Net earning · Pending'), findsOneWidget);
      expect(find.text(earningPendingText), findsOneWidget);
      expect(find.byKey(const ValueKey('commission_from_wallet')), findsNothing);
    });
  });

  // ── 8/10. Trip screen ─────────────────────────────────────────────────────
  test('rider messages are counted for the chat badge', () {
    expect(riderMessageCount([
      {'sender': 'driver', 'text': 'On my way'},
      {'sender': 'rider', 'text': 'At the gate'},
      {'sender': 'rider', 'text': 'Blue shirt'},
      'junk',
    ]), 2);
    expect(chatBadgePollEvery, greaterThanOrEqualTo(const Duration(seconds: 10)), reason: 'no fast polling');
  });

  // ── 9. OTP ───────────────────────────────────────────────────────────────
  testWidgets('the OTP goes in by itself at the 4th digit', (tester) async {
    late Future<String?> result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => result = OtpDialog.show(context, title: 'Enter Ride OTP', label: 'OTP', hint: '', action: 'Start'),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);
    expect(field.keyboardType, TextInputType.number);
    await tester.enterText(find.byType(TextField), '73');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Enter Ride OTP'), findsOneWidget, reason: 'not before 4 digits');
    await tester.enterText(find.byType(TextField), '7390');
    await tester.pump(otpAutoSubmitAfter + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(await result, '7390');
    expect(find.text('Enter Ride OTP'), findsNothing);
  });

  // ── 16. Polling and location ──────────────────────────────────────────────
  group('battery and data', () {
    test('feed polling backs off to 30 s on errors', () {
      expect(feedPollDelay(0), const Duration(seconds: 4));
      expect(feedPollDelay(1), const Duration(seconds: 8));
      expect(feedPollDelay(2), const Duration(seconds: 16));
      expect(feedPollDelay(3), const Duration(seconds: 30));
      expect(feedPollDelay(9), const Duration(seconds: 30));
    });

    test('the route is refetched every 2 min, or on a reroute past 50 m', () {
      expect(routeRefreshEvery, const Duration(minutes: 2));
      expect(NavThresholds.offRouteM, 50);
    });

    test('a ping reuses the fix the map just streamed', () async {
      final now = DateTime.utc(2026, 11, 26, 10);
      Position at(DateTime t) => Position(latitude: 22.3, longitude: 70.8, timestamp: t, accuracy: 5, altitude: 0,
          altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
      LocationService.lastStreamedForTest = at(now.subtract(const Duration(seconds: 5)));
      expect(LocationService.recentFix(now: now), isNotNull);
      expect((await LocationService.fixForPing(now: now))!.latitude, 22.3);
      LocationService.lastStreamedForTest = at(now.subtract(const Duration(minutes: 2)));
      expect(LocationService.recentFix(now: now), isNull, reason: 'too old to reuse');
      LocationService.lastStreamedForTest = null;
    });
  });

  // ── 12. Earnings ─────────────────────────────────────────────────────────
  group('earnings', () {
    final breakdown = {
      'today': {'earning': 820, 'rides': 6, 'cash': 500, 'online': 320, 'commission': 180, 'tips': 40, 'distanceKm': 42.5, 'durationMin': 150},
      'days': [
        for (var d = 20; d <= 26; d++)
          {'date': '2026-11-$d', 'earning': d == 26 ? 820 : 100, 'rides': d == 26 ? 6 : 1, 'cash': 0, 'online': 0, 'commission': 0, 'tips': 0},
      ],
      'months': [
        for (var m = 1; m <= 11; m++) {'month': m, 'year': 2026, 'earning': m * 1000, 'rides': m, 'commission': m * 100},
      ],
    };

    test('from the server buckets, with the split', () {
      final s = earningsFrom({'breakdown': breakdown}, incentives: {'day': 150}, now: DateTime(2026, 11, 26));
      expect(s.today.amount, 820);
      expect(s.today.cash, 500);
      expect(s.today.online, 320);
      expect(s.today.commission, 180);
      expect(s.today.tips, 40);
      expect(s.weekly, hasLength(7));
      expect(s.weekly.last.isCurrent, isTrue);
      expect(s.weekly.last.label, 'Thu');
      expect(s.monthly, hasLength(11));
      expect(s.monthly.last.label, 'Nov');
      expect(s.incentives['day'], 150);
    });

    test('an older server: its 7 days, no split', () {
      final s = earningsFrom({'daily': [for (var i = 0; i < 7; i++) {'amount': '${i * 10}', 'rides': '1'}]},
          now: DateTime(2026, 3, 10));
      expect(s.weekly.last.amount, 60);
      expect(s.today.amount, 60);
      expect(s.monthly, hasLength(3));
    });

    test('reached incentives add up per period', () {
      expect(incentivesReached({'incentives': [
        {'achieved': true, 'reward': 100, 'period': 'day'},
        {'achieved': false, 'reward': 500, 'period': 'day'},
        {'achieved': true, 'reward': 250, 'period': 'week'},
      ]}), {'day': 100, 'week': 250});
    });

    test('a server error is an error with Retry, never ₹0', () async {
      api = (r) => r.url.path.endsWith('/rides/driver/earnings') ? _json({'error': 'Server down'}, 500) : null;
      final state = await withApi(() async {
        final bloc = EarningsBloc();
        final next = bloc.stream.firstWhere((s) => s is EarningsLoaded || s is EarningsError);
        bloc.add(LoadEarningsEvent());
        final s = await next;
        await bloc.close();
        return s;
      });
      expect(state, isA<EarningsError>());
    });

    test('it reads GET /rides/driver/earnings, not trip history', () async {
      api = (r) => r.url.path.endsWith('/rides/driver/earnings') ? _json({'breakdown': breakdown}) : null;
      final state = await withApi(() async {
        final bloc = EarningsBloc();
        final next = bloc.stream.firstWhere((s) => s is EarningsLoaded || s is EarningsError);
        bloc.add(LoadEarningsEvent());
        final s = await next;
        await bloc.close();
        return s;
      });
      expect((state as EarningsLoaded).today.amount, 820);
      expect(sent('GET', '/rides/driver/history'), isEmpty);
    });
  });

  // ── 13. Wallet ───────────────────────────────────────────────────────────
  test('a wallet {error} is WalletError, not a ₹0 balance', () async {
    api = (r) => r.url.path.endsWith('/auth/driver/wallet') ? _json({'error': 'Driver not found'}, 404) : null;
    final state = await withApi(() async {
      final bloc = WalletBloc();
      final next = bloc.stream.firstWhere((s) => s is WalletLoaded || s is WalletError);
      bloc.add(LoadWalletEvent());
      final s = await next;
      await bloc.close();
      return s;
    });
    expect(state, isA<WalletError>());
  });

  // ── 14. Withdrawals ──────────────────────────────────────────────────────
  group('withdrawals', () {
    final history = {
      'minWithdrawal': 200,
      'pendingHeld': 500,
      'withdrawals': [
        {'_id': 'w2', 'amount': 500, 'status': 'pending', 'holdPlaced': true, 'createdAt': '2026-11-25T10:00:00Z',
          'bankName': 'SBI', 'accountNumber': '12345678'},
        {'_id': 'w1', 'amount': 300, 'status': 'rejected', 'note': 'Wrong IFSC', 'holdPlaced': true, 'holdReleased': true},
        {'_id': 'w0', 'amount': 800, 'status': 'approved', 'payoutRef': 'UTR123'},
      ],
    };

    test('history, held amount and the minimum are read', () {
      final w = WithdrawalsInfo.fromJson(history);
      expect(w.items.map((x) => x.statusLabel), ['Pending', 'Rejected', 'Paid']);
      expect(w.pendingHeld, 500);
      expect(w.minWithdrawal, 200);
      expect(w.items.first.accountLast4, '5678');
      // An older server: the held amount from the pending held rows.
      expect(WithdrawalsInfo.fromJson({'withdrawals': history['withdrawals']}).pendingHeld, 500);
      expect(WithdrawalsInfo.fromJson({'withdrawals': history['withdrawals']}).minWithdrawal, isNull);
    });

    test('the amount is checked before it is sent', () {
      expect(withdrawalAmountProblem(150, balance: 1000, min: 200), 'Minimum withdrawal is ₹200');
      expect(withdrawalAmountProblem(1500, balance: 1000, min: 200), 'You can withdraw up to ₹1000');
      expect(withdrawalAmountProblem(250.5, balance: 1000, min: 200), 'Enter a whole amount');
      expect(withdrawalAmountProblem(250, balance: 1000, min: 200), isNull);
    });

    testWidgets('the page shows Min, the held money and the history; below Min is not sent', (tester) async {
      phone(tester);
      api = (r) {
        if (r.url.path.endsWith('/auth/driver/banks')) {
          return _json({'driverName': 'Suresh', 'banks': [
            {'_id': 'acc1', 'accountHolderName': 'Suresh', 'bankName': 'SBI', 'accountNumber': '12345678', 'ifscCode': 'SBIN0001'},
          ]});
        }
        if (r.method == 'GET' && r.url.path.endsWith('/auth/driver/withdraw')) return _json(history);
        return null;
      };
      await withApi(() async {
        await tester.pumpWidget(const MaterialApp(home: WithdrawPage(balance: 1000)));
        await pumpFor(tester, 500);
        expect(find.text('Min ₹200'), findsOneWidget);
        expect(find.byKey(const ValueKey('withdraw_pending_held')), findsOneWidget);
        expect(find.byKey(const ValueKey('withdrawal_w1')), findsOneWidget);
        expect(find.text('Wrong IFSC'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '150');
        await tester.ensureVisible(find.text('Withdraw now'));
        await tester.tap(find.text('Withdraw now'));
        await pumpFor(tester, 300);
      });
      expect(find.text('Minimum withdrawal is ₹200'), findsOneWidget);
      expect(sent('POST', '/auth/driver/withdraw'), isEmpty);
      await teardown(tester);
    });
  });

  // ── 15. Going online ─────────────────────────────────────────────────────
  group('going online', () {
    Future<List<HomeState>> toggle() => withApi(() async {
      final bloc = HomeBloc();
      final states = <HomeState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(ToggleOnlineEvent(true));
      await bloc.stream.firstWhere((s) => s is GoOnlineFailedState || s is OnlineStatusChanged)
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.isOnline, states.last is OnlineStatusChanged);
      await sub.cancel();
      await bloc.close();
      return states;
    });

    test('a server error keeps the driver offline, with the reason', () async {
      api = (r) => r.url.path.endsWith('/auth/driver/online') ? _json({'error': 'Zone is closed'}, 400) : null;
      final states = await toggle();
      expect(states.last, isA<GoOnlineFailedState>());
      expect((states.last as GoOnlineFailedState).message, 'Could not go online: Zone is closed');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('driver_online'), isNot(true));
    });

    test('no location permission (service will not start): offline again on the server too', () async {
      RideAlertService.startImpl = () async {
        RideAlertService.lastStartFailure = 'You are still offline: ride alerts need location access.';
        return false;
      };
      api = (r) => r.url.path.endsWith('/auth/driver/online') ? _json({'success': true, 'isOnline': true}) : null;
      final states = await toggle();
      expect(states.last, isA<GoOnlineFailedState>());
      expect((states.last as GoOnlineFailedState).message, contains('location access'));
      final posts = sent('POST', '/auth/driver/online').map((r) => jsonDecode(r.body)['isOnline']).toList();
      expect(posts, [true, false], reason: 'the server is told we are offline again');
    });

    test('all well: online', () async {
      api = (r) => r.url.path.endsWith('/auth/driver/online') ? _json({'success': true, 'isOnline': true}) : null;
      final states = await toggle();
      expect(states.last, isA<OnlineStatusChanged>());
    });
  });

  // ── 17/19. KYC ───────────────────────────────────────────────────────────
  test('the rejection reason goes to the rejection page; review polls slowly', () {
    expect(rejectionArgs({'status': 'rejected', 'rejectionReason': ' Blurred RC '}), {'reason': 'Blurred RC'});
    expect(rejectionArgs({'status': 'rejected'}), isEmpty);
    expect(kycStatusPollEvery, const Duration(seconds: 45));
  });

  // ── 18. KYC photo source ─────────────────────────────────────────────────
  testWidgets('a document photo: camera first, gallery too', (tester) async {
    ImageSource? picked;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => TextButton(
      onPressed: () async => picked = await pickPhotoSource(c), child: const Text('pick')))));
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    final camera = tester.getTopLeft(find.byKey(const ValueKey('photo_source_camera')));
    final gallery = tester.getTopLeft(find.byKey(const ValueKey('photo_source_gallery')));
    expect(camera.dy, lessThan(gallery.dy), reason: 'camera is the first choice');
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(picked, ImageSource.camera);
  });

  // ── 20. Registration drafts ──────────────────────────────────────────────
  group('registration drafts', () {
    test('saved per step, restored only into empty fields, cleared on submit', () async {
      SharedPreferences.setMockInitialValues({});
      RegistrationDraft.sealed = false;
      await RegistrationDraft.save(RegistrationDraft.personal, {'name': 'Ravi', 'email': '', 'state': 'Gujarat'});
      await RegistrationDraft.save(RegistrationDraft.vehicle, {'model': 'Dzire', 'regNumber': 'GJ03AB1234'});
      expect(await RegistrationDraft.load(RegistrationDraft.personal), {'name': 'Ravi', 'state': 'Gujarat'});
      final typed = TextEditingController(text: 'Ravi Kumar');
      final empty = TextEditingController();
      final d = await RegistrationDraft.load(RegistrationDraft.vehicle);
      RegistrationDraft.restoreInto(typed, d, 'model');
      RegistrationDraft.restoreInto(empty, d, 'regNumber');
      expect(typed.text, 'Ravi Kumar', reason: 'server data / what is there wins');
      expect(empty.text, 'GJ03AB1234');
      await RegistrationDraft.clear();
      expect(await RegistrationDraft.load(RegistrationDraft.personal), isEmpty);
      expect(await RegistrationDraft.load(RegistrationDraft.vehicle), isEmpty);
      // A page closing after the submit does not write its draft back.
      await DraftSaver(RegistrationDraft.vehicle, () => {'model': 'Late'}).flush();
      expect(await RegistrationDraft.load(RegistrationDraft.vehicle), isEmpty);
      RegistrationDraft.sealed = false;
    });

    test('drafts are signed-in data: cleared with the session', () {
      expect(Session.sessionKeys, containsAll(RegistrationDraft.keys));
    });
  });
}
