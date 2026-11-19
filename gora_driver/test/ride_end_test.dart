import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/auth/bloc/auth_bloc.dart';
import 'package:gora_driver/features/ride/bloc/ride_bloc.dart';
import 'package:gora_driver/models/models.dart';

// Pins down ending and starting a taxi trip on a bad network.
//
// Ending used to emit "ended" on any failure, so the Order Complete page showed
// the whole fare as earnings at 0% commission while the server still had the
// trip ongoing. Found live on a lossy connection.

RideRequestModel ride() => const RideRequestModel(
  id: 'ride123', userName: 'Rider', userPhone: '+91 98765 43210', userRating: '5.0',
  pickupAddress: 'Pickup', dropAddress: 'Drop', distance: '5 km', fare: 'Rs 90',
  eta: '5 min', rideType: 'Cab', pickupLat: 22.30, pickupLng: 70.80,
  dropLat: 22.32, dropLng: 70.82,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'driver_token': 't'}));

  Future<List<RideState>> run(RideEvent event, http.Client Function() client) {
    return http.runWithClient(() async {
      final bloc = RideBloc()..currentRide = ride();
      final states = <RideState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(event);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await bloc.close();
      return states;
    }, client);
  }

  group('RideBloc end', () {
    test('a network failure keeps the trip open, with no invoice', () async {
      final states = await run(EndRideEvent(), () => MockClient((_) async => throw Exception('offline')));
      expect(states.whereType<RideEndedState>(), isEmpty,
          reason: 'No Order Complete for a ride the server has not completed');
      expect(states.whereType<EndFailedState>(), hasLength(1));
    });

    test('a server refusal keeps the trip open and says why', () async {
      final states = await run(EndRideEvent(), () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'Ride is not ongoing'}), 400)));
      expect(states.whereType<RideEndedState>(), isEmpty);
      expect(states.whereType<EndFailedState>().single.message, 'Ride is not ongoing');
    });

    test('a proxy error page is a failure, not a zero-commission invoice', () async {
      final states = await run(EndRideEvent(), () => MockClient((_) async =>
          http.Response('<html>502 Bad Gateway</html>', 502)));
      expect(states.whereType<RideEndedState>(), isEmpty);
      expect(states.whereType<EndFailedState>(), hasLength(1));
    });

    test('a completed ride shows the server split', () async {
      final states = await run(EndRideEvent(), () => MockClient((_) async => http.Response(
          jsonEncode({'success': true, 'adminProfit': 18, 'driverEarning': 72}), 200)));
      final ended = states.whereType<RideEndedState>().single;
      expect(ended.driverEarning, 72);
      expect(ended.adminProfit, 18);
    });

    test('a retry after a lost reply reads the settled ride', () async {
      // The first swipe completed it but the answer never arrived.
      final states = await run(EndRideEvent(), () => MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(jsonEncode({'error': 'Already completed'}), 400);
        }
        return http.Response(jsonEncode({'_id': 'ride123', 'status': 'completed',
            'commissionAmount': 18, 'driverEarning': 72}), 200);
      }));
      final ended = states.whereType<RideEndedState>().single;
      expect(ended.driverEarning, 72);
      expect(ended.adminProfit, 18);
    });
  });

  group('RideBloc start', () {
    test('a network failure is not called a wrong OTP', () async {
      final states = await run(StartRideEvent('1234'), () => MockClient((_) async => throw Exception('offline')));
      expect(states.whereType<RideStartedState>(), isEmpty);
      expect(states.whereType<OtpErrorState>().single.message, isNot('Invalid OTP'));
    });

    test('a wrong OTP says so', () async {
      final states = await run(StartRideEvent('0000'), () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'Invalid OTP'}), 400)));
      expect(states.whereType<OtpErrorState>().single.message, 'Invalid OTP');
    });

    test('two wrong OTPs in a row both reach the screen', () async {
      final a = OtpErrorState(ride());
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = OtpErrorState(ride());
      expect(a == b, isFalse, reason: 'Bloc drops a state equal to the current one');
    });
  });

  group('AuthBloc session check', () {
    Future<List<AuthState>> check(http.Client Function() client) {
      return http.runWithClient(() async {
        final bloc = AuthBloc();
        final states = <AuthState>[];
        final sub = bloc.stream.listen(states.add);
        bloc.add(CheckAuthEvent());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        await bloc.close();
        return states;
      }, client);
    }

    test('a dropped connection offers a retry instead of logging out', () async {
      final states = await check(() => MockClient((_) async => throw Exception('offline')));
      expect(states.whereType<UnauthenticatedState>(), isEmpty,
          reason: 'A signed-in driver must not be sent back to a (paid) OTP');
      expect(states.whereType<AuthOfflineState>(), hasLength(1));
    });

    test('a server error page offers a retry too', () async {
      final states = await check(() => MockClient((_) async => http.Response('<html>502</html>', 502)));
      expect(states.whereType<AuthOfflineState>(), hasLength(1));
    });

    test('a rejected token still signs out', () async {
      final states = await check(() => MockClient((_) async =>
          http.Response(jsonEncode({'error': 'Unauthorized'}), 401)));
      expect(states.whereType<UnauthenticatedState>(), hasLength(1));
      expect(states.whereType<AuthOfflineState>(), isEmpty);
    });
  });
}
