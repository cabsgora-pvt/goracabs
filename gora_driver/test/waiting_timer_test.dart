import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/ride/bloc/ride_bloc.dart';
import 'package:gora_driver/features/ride/widgets/waiting_timer.dart';
import 'package:gora_driver/models/models.dart';

// Pins down the pickup waiting timer, and the arrival handling it depends on.
//
// The BLoC tests matter most: arrival used to swallow every server failure and
// report "arrived" anyway, so a driver on a dead network was shown as outside
// while the server and rider still had them on the way.

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: SizedBox(width: 320 - 32, child: child))),
);

RideRequestModel ride() => const RideRequestModel(
  id: 'ride123', userName: 'Rider', userPhone: '+91 98765 43210', userRating: '5.0',
  pickupAddress: 'Pickup', dropAddress: 'Drop', distance: '5 km', fare: 'Rs 200',
  eta: '5 min', rideType: 'Cab', pickupLat: 23.02, pickupLng: 72.57,
  dropLat: 23.07, dropLng: 72.62,
);

void main() {
  group('WaitingTimer', () {
    testWidgets('starts from the server-computed seed', (tester) async {
      await tester.pumpWidget(host(const WaitingTimer(seedSeconds: 125)));
      expect(find.text('2:05'), findsOneWidget);
    });

    testWidgets('a negative seed is treated as zero', (tester) async {
      // A server/device mismatch must never render a negative wait.
      await tester.pumpWidget(host(const WaitingTimer(seedSeconds: -40)));
      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('shows the call nudge only after the threshold', (tester) async {
      await tester.pumpWidget(host(WaitingTimer(
        seedSeconds: 60,
        nudgeAfter: const Duration(minutes: 5),
        onCallRider: () {},
      )));
      expect(find.byTooltip('Call rider'), findsNothing);
      expect(find.text('Waiting for rider'), findsOneWidget);

      await tester.pumpWidget(host(WaitingTimer(
        key: const ValueKey('late'),
        seedSeconds: 301,
        nudgeAfter: const Duration(minutes: 5),
        onCallRider: () {},
      )));
      expect(find.byTooltip('Call rider'), findsOneWidget);
      expect(find.text('Rider has not come out yet'), findsOneWidget);
    });

    testWidgets('does not reset when rebuilt with a new seed', (tester) async {
      // The ride screen rebuilds while the driver waits (arrived -> wrong OTP).
      // The timer must keep its original anchor, not jump to whatever seed the
      // rebuild happens to carry.
      await tester.pumpWidget(host(const WaitingTimer(seedSeconds: 200)));
      await tester.pumpWidget(host(const WaitingTimer(seedSeconds: 0)));
      expect(find.text('3:20'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('no overflow on a 320pt screen with the nudge showing', (tester) async {
      await tester.pumpWidget(host(WaitingTimer(
        seedSeconds: 3599, onCallRider: () {},
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('RideBloc arrival', () {
    setUp(() => SharedPreferences.setMockInitialValues({'driver_token': 't'}));

    Future<List<RideState>> arrive(http.Client Function() client) {
      return http.runWithClient(() async {
        final bloc = RideBloc()..currentRide = ride();
        final states = <RideState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(ArrivedEvent());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        await bloc.close();
        return states;
      }, client);
    }

    test('a server refusal is reported, not treated as arrival', () async {
      final states = await arrive(() => MockClient((_) async => http.Response(
          jsonEncode({'error': "Cannot mark arrived from status 'ongoing'"}), 409)));
      expect(states.whereType<ArrivedAtPickupState>(), isEmpty,
          reason: 'The driver must not be shown as arrived when the server said no');
      final failed = states.whereType<ArriveFailedState>().single;
      expect(failed.message, contains('Cannot mark arrived'));
    });

    test('a network failure is reported, not treated as arrival', () async {
      final states = await arrive(() => MockClient((_) async => throw Exception('offline')));
      expect(states.whereType<ArrivedAtPickupState>(), isEmpty);
      expect(states.whereType<ArriveFailedState>(), hasLength(1));
    });

    test('a real arrival starts the wait at zero', () async {
      final states = await arrive(() => MockClient((_) async =>
          http.Response(jsonEncode({'success': true, 'waitingSec': 0}), 200)));
      expect(states.whereType<ArrivedAtPickupState>().single.waitingSec, 0);
    });

    test('an already-arrived ride resumes the server wait', () async {
      final states = await arrive(() => MockClient((_) async => http.Response(
          jsonEncode({'success': true, 'alreadyArrived': true, 'waitingSec': 190}), 200)));
      expect(states.whereType<ArrivedAtPickupState>().single.waitingSec, 190);
    });
  });
}
