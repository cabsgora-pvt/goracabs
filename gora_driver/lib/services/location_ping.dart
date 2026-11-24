import 'package:geolocator/geolocator.dart';
import 'driver_api_service.dart';

/// The oldest GPS fix still sent as the driver's position.
///
/// A backgrounded phone often hands back its last known fix — minutes or hours
/// old — and the server stamped it with the time it arrived. Dispatch then
/// matched riders to a driver who had long since moved on.
const maxFixAge = Duration(seconds: 60);

/// True when [pos] was taken within [maxFixAge] of [now].
bool isFreshFix(Position? pos, {DateTime? now}) {
  if (pos == null) return false;
  final age = (now ?? DateTime.now()).difference(pos.timestamp);
  // A fix stamped in the future (clock skew) is not trusted to be current either.
  return age <= maxFixAge && age >= const Duration(seconds: -maxFixSkewSeconds);
}

const maxFixSkewSeconds = 30;

/// Sends [pos] as the driver's location only when it is fresh. Returns whether
/// it was sent. A refused point (400 INVALID_LOCATION / 422 LOCATION_JUMP) is
/// simply not stored by the server; the caller keeps pinging either way.
Future<bool> pushFreshLocation(Position? pos, {DateTime? now}) async {
  if (!isFreshFix(pos, now: now)) return false;
  try {
    await DriverApiService.updateLocation(pos!.latitude, pos.longitude);
  } catch (_) {/* network blip: the next ping retries */}
  return true;
}

/// A position without prompting: no permission dialog, no settings screen —
/// safe to call from the background service. Null when there is no permission
/// or no fix.
Future<Position?> quietFix() async {
  try {
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.always && p != LocationPermission.whileInUse) return null;
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      // Last known is returned as-is; [pushFreshLocation] drops it if stale.
      return await Geolocator.getLastKnownPosition();
    }
  } catch (_) {
    return null;
  }
}
