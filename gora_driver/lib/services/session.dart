import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/ride/logic/dismissed_requests.dart';
import 'driver_api_service.dart';
import 'ride_alert_service.dart';

/// Ends the driver's session — on Logout, and when the server says the session
/// is no longer valid (401).
///
/// Logout used to only navigate to the login screen: the token stayed saved,
/// the "You're online" service kept polling, and the server still had the
/// driver online — dispatch kept offering them trips nobody would see.
class Session {
  /// The app's navigator, so a 401 seen anywhere (a poller, a background
  /// reply) can take the driver to login.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const loginRoute = '/login';

  /// Preferences that belong to the signed-in driver. Device settings (theme,
  /// voice guidance, the background-location disclosure) are kept.
  static const sessionKeys = [
    'driver_token', 'driver_online', 'logged_in', 'driver_upi',
    'sos_default_contact', 'sos_call_default',
  ];

  static bool _ending = false;

  /// Wires the API's 401 hook to [expired]. Called once at startup.
  static void install() {
    DriverApiService.onUnauthorized = expired;
  }

  /// Logout: tells the server the driver is offline (while the token still
  /// works), then [_end].
  static Future<void> logout({BuildContext? context}) async {
    final nav = context != null && context.mounted ? Navigator.of(context) : null;
    try {
      await DriverApiService.setOnline(false).timeout(const Duration(seconds: 6));
    } catch (_) {/* offline or already signed out: the server's own staleness check takes it */}
    await _end(fallback: nav);
  }

  /// Stops the online service and clears the signed-in driver's data, without
  /// navigating.
  static Future<void> clearSession() async {
    try { await RideAlertService.stop(); } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in sessionKeys) {
        await prefs.remove(k);
      }
    } catch (_) {}
    DismissedRequests.clear();
  }

  /// The server refused the session token (401). The token is dead, so the
  /// server is not called; everything local is cleared and the driver is sent
  /// to login — once, however many replies come back 401.
  static Future<void> expired() async {
    await _end(message: 'Your session has expired. Please log in again.');
  }

  static Future<void> _end({String? message, NavigatorState? fallback}) async {
    if (_ending) return;
    _ending = true;
    try {
      await clearSession();
      final nav = navigatorKey.currentState ?? fallback;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil(loginRoute, (_) => false);
        final ctx = nav.context;
        if (message != null && ctx.mounted) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } finally {
      _ending = false;
    }
  }
}
