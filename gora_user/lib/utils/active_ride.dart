/// Reading GET /api/rides/active → {ride: {...} | null, blocksBooking}.
///
/// Home used to download the rider's whole history (/rides/user) every 8 s to
/// find this one ride. The server now picks it: the newest live ride (pending /
/// accepted / arrived / ongoing), else one still awaiting payment.
library;

const _live = ['pending', 'accepted', 'arrived', 'ongoing'];

/// A completed ride the rider still has to pay from the ride screen: an
/// online ride the driver ended, or a prepaid trip whose prepayment did not
/// cover everything (prepaidShortfall) and is paid online / from the wallet.
/// A cash ride, and a shortfall paid in cash, are settled by the driver.
/// (An outstation trip booked online was paid in full at booking, unless it
/// carries prepaidShortfall.)
bool riderMustPay(Map<String, dynamic> r) {
  if ('${r['status'] ?? ''}' != 'completed') return false;
  if ('${r['paymentStatus'] ?? ''}' == 'paid') return false;
  if (r['awaitingPayment'] == false) return false;
  final mode = '${r['paymentMode'] ?? ''}';
  if (r['prepaidShortfall'] == true) return mode == 'online' || mode == 'wallet';
  return mode == 'online' && '${r['service'] ?? ''}' != 'outstation';
}

/// A completed prepaid trip with part of its fare still due (the prepayment
/// did not cover extras added during the trip).
bool hasPrepaidShortfall(Map<String, dynamic> r) =>
    r['prepaidShortfall'] == true && '${r['status'] ?? ''}' == 'completed' && '${r['paymentStatus'] ?? ''}' != 'paid';

/// What home shows and whether a new booking is refused.
class ActiveRideState {
  /// The ride to show in the "current ride" banner (and auto-open), or null.
  final Map<String, dynamic>? ride;

  /// Whether a new booking must wait: the server's `blocksBooking` (a ride
  /// under review for over 30 minutes does not block), or a ride the rider
  /// still has to pay.
  final bool blocksBooking;

  const ActiveRideState(this.ride, this.blocksBooking);

  /// Null when [res] is an error answer: the caller keeps what it had rather
  /// than dropping a live ride's banner on one failed poll.
  static ActiveRideState? fromResponse(Map<String, dynamic> res) {
    if (res['error'] != null || !res.containsKey('ride')) return null;
    final raw = res['ride'];
    final serverBlocks = res['blocksBooking'] == true;
    if (raw is! Map) return ActiveRideState(null, serverBlocks);
    final ride = Map<String, dynamic>.from(raw);
    final live = _live.contains('${ride['status'] ?? ''}');
    final unpaid = riderMustPay(ride);
    if (!live && !unpaid) return ActiveRideState(null, serverBlocks);
    return ActiveRideState(ride, serverBlocks || unpaid);
  }
}
