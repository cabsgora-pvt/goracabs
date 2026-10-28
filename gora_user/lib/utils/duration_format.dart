/// Minutes as a rider reads them: "45 min", "1 h", "4 h 22 min".
///
/// ETAs and trip times were printed as raw minutes everywhere, so an intercity
/// trip showed "262 min" in its ETA badge.
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
