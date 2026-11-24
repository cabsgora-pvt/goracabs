// ─────────────────────────────────────────────────────────────────────────────
// What a rider pays for a ride — the SERVER's figure.
//
// The app used to work this out for itself (riderPayable), and to keep each
// ride's coupon discount on the phone (RideCouponStore) because the server did
// not record it. Both drifted from what the server settled: multi-stop waiting
// charges were left out, and a coupon was lost with the app's storage. The
// server now validates every coupon at booking, keeps `couponDiscount` on the
// ride, settles the ride itself, and stores `amountDue` — what the rider still
// owes — when the driver ends the trip or asks for payment.
// ─────────────────────────────────────────────────────────────────────────────

num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// True once the server has stated what this ride's rider owes.
bool hasServerAmountDue(Map<String, dynamic> ride) => ride['amountDue'] is num;

/// What the rider owes for [ride].
///
/// The server's `amountDue` whenever it has one (completed, or payment
/// requested). Before that — a ride still searching or under way — the
/// server's own fields are added up the way the server settles them
/// (lib/settlement.ts riderAmountDue): the service's final amount, else the
/// booked fare, plus waiting charges, less what co-riders already paid, plus
/// the tip, less the server's coupon discount (already inside a rental's fare)
/// and anything prepaid at booking. That figure is for display only; nothing
/// is ever charged from it.
num rideAmountDue(Map<String, dynamic> ride) {
  if (hasServerAmountDue(ride)) return _n(ride['amountDue']);
  final service = '${ride['service'] ?? ''}';
  final num serviceFinal = switch (service) {
    'rental' => _n(ride['finalFare']),
    'hire_driver' => _n(ride['hireFinalFare']),
    'delivery' => _n(ride['deliveryFinalFare']),
    _ => 0,
  };
  final billable = serviceFinal > 0 ? serviceFinal : _n(ride['fare']);
  final base = billable + _n(ride['waitingChargeTotal']);
  final split = _n(ride['splitCollected']).clamp(0, base);
  final remaining = base - split;
  final coupon = service == 'rental' ? 0 : _n(ride['couponDiscount']).clamp(0, remaining);
  final mode = '${ride['paymentMode'] ?? ''}';
  final prepaid = service == 'outstation' && (mode == 'wallet' || mode == 'online') ? _n(ride['prepaidAmount']) : 0;
  final due = remaining + _n(ride['tip']) - coupon - prepaid;
  return due < 0 ? 0 : due.round();
}

/// The coupon the server applied to [ride] (0 for none). A rental's discount
/// is already inside its fare.
num rideCouponDiscount(Map<String, dynamic> ride) => _n(ride['couponDiscount']);

/// How a finished ride was paid, in the rider's words, or null when there is
/// nothing to say. From the server's settlement: a wallet ride the server
/// debited (`riderWalletDebit`), one switched to cash because the wallet was
/// short (`paymentSwitchedToCash`), or a cash ride.
String? paymentOutcome(Map<String, dynamic> ride) {
  final rupee = String.fromCharCode(0x20B9);
  final due = rideAmountDue(ride);
  String money(num v) => '$rupee${v.round()}';
  final mode = '${ride['paymentMode'] ?? ''}';
  final debit = _n(ride['riderWalletDebit']);
  if (ride['paymentSwitchedToCash'] == true && mode == 'cash') {
    final cash = ride['cashToCollect'] is num ? _n(ride['cashToCollect']) : due;
    if (ride['cashCollectedAt'] != null) return 'Paid ${money(cash)} in cash to your driver.';
    return 'Your Gora wallet balance was too low, so this ride is paid in cash. Please pay ${money(cash)} to your driver.';
  }
  if (debit > 0) return 'Paid ${money(debit)} from your Gora wallet.';
  if (mode == 'online' && ride['paymentStatus'] == 'paid') {
    return due > 0 ? 'Paid ${money(due)} online.' : 'Paid online.';
  }
  if ((mode == 'cash' || mode == 'cod') && due > 0) return 'Please pay ${money(due)} in cash to your driver.';
  return null;
}
