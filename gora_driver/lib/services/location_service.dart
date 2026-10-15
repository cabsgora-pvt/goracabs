import 'dart:io' show Platform;
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

  /// Asks for "always" location, needed for tracking to survive backgrounding.
  ///
  /// Android requires the coarse/fine grant first and only then allows the
  /// background upgrade, so this is called after a normal permission flow —
  /// never as the first prompt a driver sees.
  static Future<bool> ensureBackgroundPermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;
      if (p == LocationPermission.whileInUse) {
        // Second request is what surfaces the "Allow all the time" option.
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Live position stream.
  ///
  /// [background] keeps the stream alive when the app is not in the foreground
  /// by running an Android foreground service (and enabling the iOS background
  /// location indicator). Without it, tracking silently stops the moment the
  /// driver switches apps — which is why the rental odometer under-counted and
  /// navigation froze mid-trip.
  ///
  /// The manifest already declares FOREGROUND_SERVICE_LOCATION,
  /// ACCESS_BACKGROUND_LOCATION, WAKE_LOCK and POST_NOTIFICATIONS.
  static Stream<Position> liveLocation({
    bool background = false,
    int distanceFilter = 10,
    String notificationTitle = 'Gora Driver',
    String notificationText = 'Tracking your trip',
  }) {
    if (background && Platform.isAndroid) {
      return Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      );
    }

    if (background && Platform.isIOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: distanceFilter,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        ),
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    );
  }
}
