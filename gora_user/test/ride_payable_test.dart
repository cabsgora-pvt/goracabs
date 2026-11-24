import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/utils/ride_payable.dart';

// What the rider owes is the SERVER's figure. These pin rideAmountDue: the
// stored amountDue always wins, and before the server has one the estimate
// adds up the server's own fields exactly as lib/settlement.ts does —
// including the multi-stop waiting charges the old phone-side riderPayable
// left out, and the server's coupon (not one kept on the phone).
void main() {
  group('rideAmountDue', () {
    test("the server's amountDue wins over anything the phone could add up", () {
      expect(rideAmountDue({'service': 'taxi', 'fare': 250, 'tip': 20, 'amountDue': 180}), 180);
      // 0 is a real answer (prepaid, fully split): not "missing".
      expect(rideAmountDue({'service': 'outstation', 'fare': 5000, 'amountDue': 0}), 0);
    });

    test('waiting charges are included (riderPayable left them out)', () {
      expect(rideAmountDue({'service': 'taxi', 'fare': 250, 'waitingChargeTotal': 30}), 280);
    });

    test('tip is added, split shares come off the fare only', () {
      expect(rideAmountDue({'service': 'taxi', 'fare': 300, 'splitCollected': 200, 'tip': 20}), 120);
      expect(rideAmountDue({'service': 'taxi', 'fare': 300, 'splitCollected': 500}), 0);
    });

    test("the server's couponDiscount comes off, never below zero", () {
      expect(rideAmountDue({'service': 'taxi', 'fare': 250, 'couponDiscount': 50}), 200);
      expect(rideAmountDue({'service': 'taxi', 'fare': 250, 'couponDiscount': 400}), 0);
    });

    test("a rental's coupon is already inside its fare", () {
      expect(rideAmountDue({'service': 'rental', 'fare': 949, 'finalFare': 949, 'couponDiscount': 50}), 949);
    });

    test("each service's own final amount when it has one", () {
      expect(rideAmountDue({'service': 'rental', 'fare': 999, 'finalFare': 1479}), 1479);
      expect(rideAmountDue({'service': 'hire_driver', 'fare': 600, 'hireFinalFare': 900}), 900);
      expect(rideAmountDue({'service': 'delivery', 'fare': 120, 'deliveryFinalFare': 150}), 150);
      expect(rideAmountDue({'service': 'rental', 'fare': 999, 'finalFare': 0}), 999);
    });

    test('an outstation trip paid at booking owes only the difference', () {
      expect(rideAmountDue({'service': 'outstation', 'fare': 5000, 'paymentMode': 'online', 'prepaidAmount': 5000}), 0);
      expect(rideAmountDue({'service': 'outstation', 'fare': 5000, 'paymentMode': 'cash', 'prepaidAmount': 0}), 5000);
    });

    test('tolerates strings and missing fields', () {
      expect(rideAmountDue({'service': 'hire_driver', 'fare': '600', 'hireFinalFare': '900'}), 900);
      expect(rideAmountDue({}), 0);
    });
  });

  group('paymentOutcome', () {
    test('a wallet ride the server debited', () {
      expect(paymentOutcome({'paymentMode': 'wallet', 'riderWalletDebit': 240, 'paymentStatus': 'paid', 'amountDue': 240}),
          'Paid ₹240 from your Gora wallet.');
    });

    test('a wallet ride switched to cash because the wallet was short', () {
      final r = {'paymentMode': 'cash', 'paymentSwitchedToCash': true, 'amountDue': 240, 'paymentStatus': 'paid'};
      expect(paymentOutcome(r), contains('Please pay ₹240 to your driver'));
      expect(paymentOutcome(r), contains('wallet balance was too low'));
    });

    test('an online ride paid, and a cash ride', () {
      expect(paymentOutcome({'paymentMode': 'online', 'paymentStatus': 'paid', 'amountDue': 300}), 'Paid ₹300 online.');
      expect(paymentOutcome({'paymentMode': 'cash', 'amountDue': 180}), 'Please pay ₹180 in cash to your driver.');
    });

    test('an unpaid online ride the driver took cash for', () {
      expect(paymentOutcome({'paymentMode': 'cash', 'paymentSwitchedToCash': true, 'cashCollectedAt': '2026-11-24T10:00:00Z', 'amountDue': 300}),
          'Paid ₹300 in cash to your driver.');
    });
  });
}
