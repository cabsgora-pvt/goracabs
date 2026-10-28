/// One line of a fare breakdown, as shown to the rider.
class FareLine {
  final String label;
  final num amount;
  const FareLine(this.label, this.amount);

  @override
  String toString() => '$label: $amount';
}

/// The itemised lines of an outstation quote, built from the `breakdown` map the
/// fare API returns — every component it charged, so the lines add up to
/// [total].
///
/// The API adds a component to `breakdown` only when it charged it (empty
/// return, night halt, driver allowance, GST ...). Anything in the total that
/// the breakdown does not itemise — the minimum-fare top-up, or a component a
/// newer server adds — is shown as one "Other charges" line of the difference.
/// Display only: [total] is never changed, and no line is ever invented beyond
/// that difference.
List<FareLine> outstationFareLines(
  Map bk,
  num total, {
  num distanceKm = 0,
  num emptyReturnPercent = 0,
}) {
  num n(String k) => (bk[k] as num?) ?? 0;
  final lines = <FareLine>[];
  void add(String label, num v, {bool always = false}) {
    if (v > 0 || always) lines.add(FareLine(label, v));
  }

  final km = n('totalKm') > 0 ? n('totalKm') : distanceKm;
  add('Base fare', n('base'), always: true);
  add('Fare for ${km.toStringAsFixed(0)} km @ ₹${n('perKm').toStringAsFixed(0)}/km', n('kmCharge'), always: true);
  if (n('perHour') > 0) {
    add('Driving time (${n('totalHrs').toStringAsFixed(0)} hr × ₹${n('perHour').toStringAsFixed(0)}/hr)', n('hourCharge'));
  }
  add(emptyReturnPercent > 0 ? 'Empty return (${emptyReturnPercent.toStringAsFixed(0)}%)' : 'Empty return charge', n('emptyReturn'));
  final nights = n('nights');
  add(nights > 1 ? 'Night halt ($nights nights)' : 'Night halt', n('nightHalt'));
  final days = n('days');
  add(days > 1 ? 'Driver allowance ($days days)' : 'Driver allowance', n('driverAllowance'));
  add('Tolls', n('tollCharge'));
  add(n('gstPercent') > 0 ? 'GST (${n('gstPercent').toStringAsFixed(0)}%)' : 'GST', n('gst'));

  final sum = lines.fold<num>(0, (a, l) => a + l.amount);
  final rest = total - sum;
  if (rest.abs() >= 1) lines.add(FareLine(rest > 0 ? 'Other charges' : 'Adjustment', rest));
  return lines;
}
