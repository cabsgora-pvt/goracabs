import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/utils/ride_payable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// What a rider is charged at completion.
//
// Each case pins the amount a booking screen charged before the live ride screen
// took over, so moving a service onto that screen cannot quietly change a bill.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('riderPayable', () {
    test('taxi charges the fare', () {
      expect(riderPayable({'service': 'taxi', 'fare': 250}), 250);
    });

    test('taxi takes the phone-side coupon off', () {
      expect(riderPayable({'service': 'taxi', 'fare': 250}, couponDiscount: 50), 200);
    });

    test('a coupon bigger than the fare charges nothing, never a negative', () {
      expect(riderPayable({'service': 'taxi', 'fare': 250}, couponDiscount: 400), 0);
    });

    // tip is billed like the server's totalFare (fare + tip); multi-stop
    // waiting is a separate, still-unbilled gap (see the doc comment).
    test('tip is added; multi-stop waiting is not', () {
      final ride = {
        'service': 'taxi', 'fare': 250, 'tip': 20,
        'waitingChargeTotal': 30, 'totalFare': 300,
      };
      expect(riderPayable(ride), 270);
    });

    test('no tip means no change', () {
      expect(riderPayable({'service': 'taxi', 'fare': 250, 'tip': 0}), 250);
    });

    test('split fare already collected is subtracted, tip is not', () {
      final ride = {'service': 'taxi', 'fare': 300, 'tip': 20, 'splitCollected': 200};
      expect(riderPayable(ride), 120); // (300-200) + 20
    });

    test('split fare cannot push the charge negative even if it overpays', () {
      expect(riderPayable({'service': 'taxi', 'fare': 300, 'splitCollected': 500}), 0);
    });

    test('rental charges finalFare, extras included', () {
      expect(riderPayable({'service': 'rental', 'fare': 999, 'finalFare': 1479}), 1479);
    });

    // The server already took a rental coupon off `fare` at booking.
    test('rental ignores the coupon, so it is not taken off twice', () {
      expect(
        riderPayable({'service': 'rental', 'fare': 949, 'finalFare': 949}, couponDiscount: 50),
        949,
      );
    });

    // Mongoose defaults finalFare to 0; a rental force-completed before 'end'
    // must not be charged nothing.
    test('rental with no final amount falls back to the fare, like the server', () {
      expect(riderPayable({'service': 'rental', 'fare': 999, 'finalFare': 0}), 999);
    });

    test('hire charges overtime and takes the coupon off', () {
      final ride = {'service': 'hire_driver', 'fare': 600, 'hireFinalFare': 900};
      expect(riderPayable(ride, couponDiscount: 100), 800);
    });

    test('hire before a final amount exists charges the booked fare', () {
      expect(riderPayable({'service': 'hire_driver', 'fare': 600}), 600);
    });

    test('delivery charges deliveryFinalFare less the coupon', () {
      final ride = {'service': 'delivery', 'fare': 120, 'deliveryFinalFare': 120};
      expect(riderPayable(ride, couponDiscount: 20), 100);
    });

    test('outstation matches what its booking screen charged', () {
      expect(riderPayable({'service': 'outstation', 'fare': 5000}, couponDiscount: 500), 4500);
    });

    test('numbers that arrive as strings still count', () {
      expect(riderPayable({'service': 'hire_driver', 'fare': '600', 'hireFinalFare': '900'}), 900);
    });

    test('a ride with no amounts at all charges nothing', () {
      expect(riderPayable({}), 0);
    });
  });

  group('RideCouponStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips a discount per ride', () async {
      await RideCouponStore.save('r1', 75);
      await RideCouponStore.save('r2', 20);
      expect(await RideCouponStore.load('r1'), 75);
      expect(await RideCouponStore.load('r2'), 20);
    });

    test('an unknown ride has no discount', () async {
      expect(await RideCouponStore.load('nope'), 0);
    });

    test('a zero discount is not stored', () async {
      await RideCouponStore.save('r1', 0);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), isEmpty);
    });

    test('clear removes it', () async {
      await RideCouponStore.save('r1', 75);
      await RideCouponStore.clear('r1');
      expect(await RideCouponStore.load('r1'), 0);
    });
  });
}
