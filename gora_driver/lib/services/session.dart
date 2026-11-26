import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/ride/logic/dismissed_requests.dart';
import 'app_update.dart';
import 'driver_api_service.dart';
import 'ride_alert_service.dart';

/// When the session token should be exchanged for a fresh one (sliding
/// sessions, POST /auth/refresh): once the server's [refreshAfter] has passed;
/// without one, once the token is more than a day old ([issuedAt], its `iat`).
bool shouldRefreshToken({required DateTime now, DateTime? refreshAfter, DateTime? issuedAt}) {
  if (refreshAfter != null) return !now.isBefore(refreshAfter);
  if (issuedAt != null) return now.difference(issuedAt) > const Duration(days: 1);
  return false;
}

/// The `iat` of a JWT, or null when it cannot be read. Read-only — the server
/// alone decides whether the token is valid.
DateTime? jwtIssuedAt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final iat = json is Map ? json['iat'] : null;
    return iat is num ? DateTime.fromMillisecondsSinceEpoch((iat * 1000).round()) : null;
  } catch (_) {
    return null;
  }
}

/// Ends the driver's session — on Logout, and when the server says the session
/// is no longer valid (401, or a blocked / deleted account) — and keeps it
/// alive meanwhile (sliding refresh).
///
/// Logout used to only navigate to the login screen: the token stayed saved,
/// the "You're online" service kept polling, and the server still had the
/// driver online — dispatch kept offering them trips nobody would see.
class Session {
  /// The app's navigator, so a 401 seen anywhere (a poller, a background
  /// reply) can take the driver to login.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const loginRoute = '/login';

  /// The server's latest `refreshAfter` (ISO), from a profile / refresh reply.
  static const refreshAfterKey = 'driver_refresh_after';

  /// Preferences that belong to the signed-in driver. Device settings (theme,
  /// voice guidance, the background-location disclosure) are kept. The token
  /// itself lives in secure storage and is cleared with it (clearToken).
  static const sessionKeys = [
    'driver_token', 'driver_online', 'logged_in', 'driver_upi',
    'sos_default_contact', 'sos_call_default', refreshAfterKey,
    // Registration drafts (features/registration/registration_draft.dart).
    'reg_draft_personal', 'reg_draft_vehicle',
  ];

  static bool _ending = false;
  static _Lifecycle? _lifecycle;

  /// Wires the API's session hooks: a 401 (or a blocked / deleted account)
  /// → [expired]; every profile reply → [maybeRefresh]. Also watches the app
  /// coming back to the front ([onResumed]). Called once at startup.
  static void install() {
    DriverApiService.onUnauthorized = expired;
    DriverApiService.onProfile = (p) => unawaited(maybeRefresh(refreshAfter: p['refreshAfter']));
    if (_lifecycle == null) {
      _lifecycle = _Lifecycle();
      WidgetsBinding.instance.addObserver(_lifecycle!);
    }
  }

  /// A message from the background service: its request was refused for the
  /// session ([unauthorizedMessage], with the reason after a colon).
  static void onTaskData(Object data) {
    final reason = unauthorizedReasonOf(data);
    if (reason == null) return;
    DriverApiService.signOutReason = reason;
    unawaited(expired());
  }

  static bool _refreshing = false;
  static DateTime? _lastRefreshTry;

  /// The least time between two refresh attempts (start and every resume ask).
  static const refreshRetryGap = Duration(minutes: 10);

  /// Exchanges the token for a fresh one when it is due ([shouldRefreshToken])
  /// and saves it where every part of the app reads it (TokenStore — the
  /// background service reads it from there on its next request).
  ///
  /// 409 TOO_EARLY only moves the next try to the server's refreshAfter. A 401
  /// or a blocked / deleted account ends the session through the usual hook;
  /// any other failure (offline, 5xx, 429) is ignored and tried again later —
  /// the current token keeps working until it expires.
  static Future<void> maybeRefresh({dynamic refreshAfter, DateTime? now}) async {
    if (_refreshing) return;
    final at = now ?? DateTime.now();
    _refreshing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromServer = DateTime.tryParse((refreshAfter ?? '').toString());
      if (fromServer != null) await prefs.setString(refreshAfterKey, fromServer.toUtc().toIso8601String());
      final token = await DriverApiService.getToken();
      if (token == null || token.isEmpty) return;
      final after = fromServer ?? DateTime.tryParse(prefs.getString(refreshAfterKey) ?? '');
      if (!shouldRefreshToken(now: at, refreshAfter: after, issuedAt: jwtIssuedAt(token))) return;
      if (_lastRefreshTry != null && at.difference(_lastRefreshTry!).abs() < refreshRetryGap) return;
      _lastRefreshTry = at;
      final res = await DriverApiService.refreshToken();
      final fresh = res['token'];
      if (fresh is String && fresh.isNotEmpty) {
        // Signed out, or signed in again, meanwhile: that session wins.
        if (await DriverApiService.getToken() != token) return;
        await DriverApiService.saveToken(fresh);
        final next = DateTime.tryParse((res['refreshAfter'] ?? '').toString());
        if (next != null) {
          await prefs.setString(refreshAfterKey, next.toUtc().toIso8601String());
        } else {
          await prefs.remove(refreshAfterKey);
        }
      } else if (res['code'] == 'TOO_EARLY') {
        final next = DateTime.tryParse((res['refreshAfter'] ?? '').toString());
        if (next != null) await prefs.setString(refreshAfterKey, next.toUtc().toIso8601String());
      }
    } catch (_) {
      // Offline: tried again on the next start / resume.
    } finally {
      _refreshing = false;
    }
  }

  /// Back in front: refresh the token if due, recheck for an app update and —
  /// when the driver is online — make sure the online service runs. After the
  /// app was killed while online the "You're online" service died with it;
  /// reopening restarts it here (and in HomeBloc's load), so requests keep
  /// alerting once the app is minimised again. start() leaves a running
  /// service alone.
  static Future<void> onResumed() async {
    unawaited(maybeRefresh());
    unawaited(AppUpdate.check());
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('driver_online') == true && await DriverApiService.getToken() != null) {
        await RideAlertService.start();
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void resetRefreshForTest() {
    _refreshing = false;
    _lastRefreshTry = null;
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
    try { await DriverApiService.clearToken(); } catch (_) {}
    DismissedRequests.clear();
  }

  /// The server refused the session token (401), or the account is blocked /
  /// deleted (403 ACCOUNT_BLOCKED / ACCOUNT_DELETED). The token is not used
  /// again; everything local is cleared and the driver is sent to login with
  /// the reason — once, however many replies come back refused.
  static Future<void> expired() async {
    await _end(message: DriverApiService.signOutReason);
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
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 6),
          ));
        }
      }
    } finally {
      _ending = false;
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(Session.onResumed());
  }
}
