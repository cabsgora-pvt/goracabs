import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/utils/book_again.dart';
import 'package:customer_app/utils/driver_distance.dart';
import 'package:customer_app/widgets/booking_for.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Return-trip "Book again", live driver distance + time, and booking a ride
// for someone else — the pure logic behind each.
// ─────────────────────────────────────────────────────────────────────────────

// Gondal → Rajkot, as the server stores a completed ride.
const _gondal = 'Station Road, Gondal, Gujarat 360311, India';
const _rajkot = 'Race Course, Sadar, Rajkot, Gujarat 360001, India';
const _gondalLL = (21.9612, 70.7939);
const _rajkotLL = (22.3039, 70.8022);

Map<String, dynamic> _lastRide() => {
      'pickupAddress': _gondal, 'pickupLat': _gondalLL.$1, 'pickupLng': _gondalLL.$2,
      'dropAddress': _rajkot, 'dropLat': _rajkotLL.$1, 'dropLng': _rajkotLL.$2,
      'vehicleType': 'Cab',
    };

void main() {
  group('haversine', () {
    test('Gondal to Rajkot is about 38 km', () {
      final m = haversineMeters(_gondalLL.$1, _gondalLL.$2, _rajkotLL.$1, _rajkotLL.$2);
      expect(m, inInclusiveRange(37000, 39000));
    });
    test('a point to itself is zero', () {
      expect(haversineMeters(22.3, 70.8, 22.3, 70.8), 0);
    });
  });

  group('book again', () {
    test('standing at the last drop offers the way back', () {
      // ~500 m from the Rajkot drop.
      final p = bookAgainPlan(_lastRide(), hereLat: 22.3080, hereLng: 70.8040)!;
      expect(p.isReturn, isTrue);
      expect(p.title, 'Return to Gondal');
      expect(p.dropAddress, _gondal);
      expect(p.dropLat, _gondalLL.$1);
      expect(p.dropLng, _gondalLL.$2);
      expect(p.fromLabel, _rajkot);
    });

    test('far from the last drop repeats the same trip', () {
      final p = bookAgainPlan(_lastRide(), hereLat: _gondalLL.$1, hereLng: _gondalLL.$2)!;
      expect(p.isReturn, isFalse);
      expect(p.title, 'Book again to Rajkot');
      expect(p.dropAddress, _rajkot);
      expect(p.dropLat, _rajkotLL.$1);
    });

    test('just outside 1.5 km is not a return', () {
      // ~2 km north of the drop.
      final p = bookAgainPlan(_lastRide(), hereLat: 22.3219, hereLng: 70.8022)!;
      expect(p.isReturn, isFalse);
    });

    test('no location fix keeps the old behaviour', () {
      expect(bookAgainPlan(_lastRide())!.isReturn, isFalse);
    });

    test('a return needs the old pickup coordinates', () {
      final r = _lastRide()..remove('pickupLat');
      final p = bookAgainPlan(r, hereLat: _rajkotLL.$1, hereLng: _rajkotLL.$2)!;
      expect(p.isReturn, isFalse);
    });

    test('a trip inside one town is named by the place, not the town', () {
      final r = {
        'pickupAddress': 'Crystal Mall, Kalavad Road, Rajkot, Gujarat, India',
        'pickupLat': 22.2900, 'pickupLng': 70.7700,
        'dropAddress': _rajkot, 'dropLat': _rajkotLL.$1, 'dropLng': _rajkotLL.$2,
      };
      final p = bookAgainPlan(r, hereLat: _rajkotLL.$1, hereLng: _rajkotLL.$2)!;
      expect(p.title, 'Return to Crystal Mall');
    });

    test('a ride without a drop pin offers nothing', () {
      expect(bookAgainPlan({'dropAddress': _rajkot}), isNull);
    });
  });

  group('driver distance', () {
    test('formats metres and kilometres', () {
      expect(formatDistanceM(452), '450 m');
      expect(formatDistanceM(1234), '1.2 km');
      expect(formatDistanceM(15400), '15 km');
    });

    test('the line reads like the brief', () {
      expect(driverAwayLine(meters: 1200, mins: 4, toPickup: true), 'Driver is 1.2 km · 4 min away');
      expect(driverAwayLine(meters: 5600, mins: 12, toPickup: false), '5.6 km · 12 min to drop');
      expect(driverAwayLine(meters: 800, toPickup: true), 'Driver is 800 m away');
    });

    test('distance follows each poll, scaled to road length', () {
      final (m, _) = liveDistanceAndEta(
          driverLat: 22.30, driverLng: 70.80, destLat: 22.31, destLng: 70.80, roadFactor: 1.3);
      final straight = haversineMeters(22.30, 70.80, 22.31, 70.80);
      expect(m, closeTo(straight * 1.3, 0.01));
    });

    test('time shrinks with the distance between ETA calls, never to 0', () {
      final at = haversineMeters(22.30, 70.80, 22.32, 70.80);
      final (_, half) = liveDistanceAndEta(
          driverLat: 22.31, driverLng: 70.80, destLat: 22.32, destLng: 70.80, etaMin: 8, etaAtM: at);
      expect(half, 4);
      final (_, close) = liveDistanceAndEta(
          driverLat: 22.3199, driverLng: 70.80, destLat: 22.32, destLng: 70.80, etaMin: 8, etaAtM: at);
      expect(close, 1);
    });

    test('no ETA yet gives distance only', () {
      final (_, mins) = liveDistanceAndEta(driverLat: 22.3, driverLng: 70.8, destLat: 22.31, destLng: 70.8);
      expect(mins, isNull);
    });
  });

  group('booking for someone else', () {
    test('body fields', () {
      expect(const BookingFor.self().toBody(), {'bookingFor': 'self'});
      expect(const BookingFor.other('Asha', '9825012345').toBody(),
          {'bookingFor': 'other', 'passengerName': 'Asha', 'passengerPhone': '9825012345'});
    });

    test('validation', () {
      expect(validatePassenger('A', '9825012345'), isNotNull);
      expect(validatePassenger('Asha', '12345'), 'Enter a valid 10-digit mobile number');
      expect(validatePassenger('Asha', '+91 98250 12345'), isNull);
      expect(validatePassenger('Asha', '098250 12345', riderPhone: '+919825012345'), contains('your own number'));
    });

    test('server codes become clear messages', () {
      expect(passengerErrorMessage({'code': 'PASSENGER_REQUIRED'}), contains('10-digit'));
      expect(passengerErrorMessage({'code': 'PASSENGER_IS_RIDER'}), contains('your own'));
      expect(passengerErrorMessage({'code': 'activeRide'}), isNull);
    });

    test('the live ride line', () {
      expect(passengerLine({'bookingFor': 'other', 'passengerName': 'Asha', 'passengerPhone': '9825012345'}),
          'Ride for Asha · +91 98250 12345');
      expect(passengerLine({'bookingFor': 'other', 'passengerName': 'Asha'}), 'Ride for Asha');
      expect(passengerLine({'bookingFor': 'self'}), isNull);
    });

    test('recent passengers: newest first, de-duplicated by phone, at most 5', () async {
      SharedPreferences.setMockInitialValues({});
      for (var i = 0; i < 7; i++) {
        await RecentPassengers.remember(BookingFor.other('P$i', '98250000${i}0'));
      }
      await RecentPassengers.remember(const BookingFor.other('P6 again', '9825000060'));
      final list = await RecentPassengers.load();
      expect(list, hasLength(5));
      expect(list.first.name, 'P6 again');
      expect(list.where((p) => p.phone == '9825000060'), hasLength(1));
      expect(list.map((p) => p.name), isNot(contains('P0')));
    });
  });
}
