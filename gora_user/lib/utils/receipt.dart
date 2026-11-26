/// The money on one trip's receipt, read from the ride record (display only:
/// nothing here is ever charged).
///
/// Accepts either the raw ride from the server (GET /rides/user, /rides/{id}:
/// `fare`, `totalFare`, `status: 'completed'`) or the summary map the history
/// screen builds from it (`baseFare`, `total`, `status: 'Completed'`), or the
/// two merged. The rules mirror the server's settlement (lib/settlement.ts):
///
///  * totalFare = the service's final amount (or the booked fare) + multi-stop
///    waiting + tip;
///  * couponDiscount comes off what the rider pays, except on a rental, whose
///    fare already had it taken off at booking (shown, not subtracted again);
///  * outstation tolls are paid to the driver outside the fare and added;
///  * a cancelled trip owes only its cancellation fee.
class TripReceipt {
  final String service;
  /// 'completed' | 'cancelled' | the raw status of a live / pending trip.
  final String status;
  /// 'paid' | 'pending' | '' when the record does not say.
  final String paymentStatus;
  final int billable;
  final int waiting;
  final int tip;
  final int couponDiscount;
  final String couponCode;
  final int tolls;
  final int cancellationFee;
  final String cancellationReason;
  final String cancelledBy;
  final List<String> stops;
  final int recordedTotal;
  final int? amountDue;

  const TripReceipt({
    required this.service,
    required this.status,
    required this.paymentStatus,
    required this.billable,
    required this.waiting,
    required this.tip,
    required this.couponDiscount,
    required this.couponCode,
    required this.tolls,
    required this.cancellationFee,
    required this.cancellationReason,
    required this.cancelledBy,
    required this.stops,
    required this.recordedTotal,
    required this.amountDue,
  });

  static int _n(dynamic v) {
    if (v is num) return v.isFinite ? v.round() : 0;
    return num.tryParse('${v ?? ''}')?.round() ?? 0;
  }

  static int? _nOrNull(dynamic v) {
    if (v is num) return v.isFinite ? v.round() : null;
    return num.tryParse('${v ?? ''}')?.round();
  }

  static String _s(dynamic v) => (v ?? '').toString().trim();

  /// Stop addresses from `stops` (taxi / outstation / rental) and
  /// `deliveryStops` (parcel), as maps or as already-extracted strings.
  static List<String> stopsOf(Map<String, dynamic> ride) {
    final out = <String>[];
    for (final key in const ['stops', 'deliveryStops']) {
      final list = ride[key];
      if (list is! List) continue;
      for (final s in list) {
        final a = s is Map ? _s(s['address']) : _s(s);
        if (a.isNotEmpty) out.add(a);
      }
    }
    return out;
  }

  factory TripReceipt.from(Map<String, dynamic> ride) {
    final service = _s(ride['service']).isEmpty ? 'taxi' : _s(ride['service']);
    final svcFinal = service == 'rental'
        ? _n(ride['finalFare'])
        : service == 'hire_driver'
            ? _n(ride['hireFinalFare'])
            : service == 'delivery'
                ? _n(ride['deliveryFinalFare'])
                : 0;
    return TripReceipt(
      service: service,
      status: _s(ride['status']).toLowerCase(),
      paymentStatus: _s(ride['paymentStatus']).toLowerCase(),
      billable: svcFinal > 0 ? svcFinal : _n(ride['baseFare'] ?? ride['fare']),
      waiting: _n(ride['waitingChargeTotal']),
      tip: _n(ride['tip']),
      couponDiscount: _n(ride['couponDiscount']),
      couponCode: _s(ride['couponCode']),
      tolls: service == 'outstation' ? _n(ride['tollCharge']) : 0,
      cancellationFee: _n(ride['cancellationFee']),
      cancellationReason: _s(ride['cancellationReason']),
      cancelledBy: _s(ride['cancelledBy']),
      stops: stopsOf(ride),
      recordedTotal: _n(ride['totalFare'] ?? ride['total']),
      amountDue: _nOrNull(ride['amountDue']),
    );
  }

  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isPaid => paymentStatus == 'paid';

  /// The fare before the coupon: what the server recorded, else its parts.
  int get gross => recordedTotal > 0 ? recordedTotal : billable + waiting + tip;

  /// The coupon actually taken off what the rider pays (0 on a rental, whose
  /// fare already has it off).
  int get couponOff {
    if (service == 'rental' || couponDiscount <= 0) return 0;
    return couponDiscount > gross ? gross : couponDiscount;
  }

  /// The trip's total: the fare less the coupon, plus tolls; for a cancelled
  /// trip, its cancellation fee.
  int get total => isCancelled ? cancellationFee : gross - couponOff + tolls;

  /// What the total row says: "Total Paid" only when the server says paid.
  /// [unknown] is used when the record carries no payment status at all.
  String totalLabel({String unknown = 'Total'}) {
    if (isCancelled) return cancellationFee > 0 ? 'Cancellation fee' : 'Cancelled';
    if (isPaid) return 'Total Paid';
    if (paymentStatus == 'pending') return isCompleted ? 'Amount due' : 'Estimated fare';
    return unknown;
  }

  /// The amount on the total row: what is still owed when the trip is
  /// completed but unpaid (amountDue, when the server sent it), else [total].
  int get totalValue {
    if (!isCancelled && isCompleted && paymentStatus == 'pending' && amountDue != null) {
      return amountDue! + tolls;
    }
    return total;
  }

  /// "Cancelled by you · Driver not moving" style line, or ''.
  String get cancellationLine {
    if (!isCancelled) return '';
    final who = switch (cancelledBy) {
      'rider' || 'user' => 'by you',
      'driver' => 'by the driver',
      'admin' || 'system' => 'by Gora',
      _ => '',
    };
    final head = who.isEmpty ? 'Cancelled' : 'Cancelled $who';
    return cancellationReason.isEmpty ? head : '$head · $cancellationReason';
  }

  /// Payment line, e.g. "CASH · Paid" / "WALLET · Pending".
  static String paymentLine(String mode, String paymentStatus) {
    final m = mode.trim().isEmpty ? 'CASH' : mode.trim().toUpperCase();
    final p = paymentStatus.trim().toLowerCase();
    if (p == 'paid') return '$m · Paid';
    if (p == 'pending') return '$m · Pending';
    return m;
  }
}
