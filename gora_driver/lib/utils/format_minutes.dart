/// "42 min" under an hour, "4 h 6 min" (or "4 h") from an hour up — "246 min"
/// is not something a driver can read at a glance.
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
