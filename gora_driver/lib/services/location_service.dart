import 'package:geolocator/geolocator.dart';

class LocationService {
  // Robust location fetch:
  // (1) ensure GPS service is on (2) request permission (3) try cached lastKnownPosition for instant UI
  // (4) fetch fresh high-accuracy fix with 10s timeout. Returns cached on timeout, null on deny.
  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) return null;
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return null;
      }

      Position? cached;
      try { cached = await Geolocator.getLastKnownPosition(); } catch (_) {}

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } on Exception {
        return cached;
      }
    } catch (_) {
      return null;
    }
  }

  static Stream<Position> liveLocation() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }
}
