import 'dart:convert';

import 'api_service.dart';
import 'session_guard.dart';

/// Sliding sessions: a rider's token lasts 7 days, and is swapped for a fresh
/// one (POST /api/auth/refresh) once it is a day old, so an active rider is
/// never signed out weekly.
///
/// When to refresh comes from the server: the profile response's
/// `refreshAfter`, kept here by [noteRefreshAfter]. Before the profile has been
/// read (the app just started), the token's own issue time is used — a token
/// more than a day old is due.
///
/// Called at app start and every resume ([maybeRefresh]). The new token goes
/// wherever the current one lives ([ApiService.saveToken]: secure storage; the
/// app keeps no other copy in memory). 409 TOO_EARLY is not an error: the
/// token is simply too fresh, and its answer says when to try. A 401 / 403
/// from here signs the rider out through [SessionGuard], like any other call.
class SessionRefresher {
  SessionRefresher._();

  static DateTime? _refreshAfter;
  static Future<bool>? _inFlight;

  /// Replaceable in tests.
  static DateTime Function() now = DateTime.now;

  /// When the server said the token may be refreshed, if known.
  static DateTime? get refreshAfter => _refreshAfter;

  /// Keeps a `refreshAfter` from a profile (or refresh) answer. Ignores
  /// anything that is not a date.
  static void noteRefreshAfter(dynamic value) {
    final d = DateTime.tryParse('${value ?? ''}');
    if (d != null) _refreshAfter = d;
  }

  /// Forgets what it knew (sign-out, tests).
  static void reset() {
    _refreshAfter = null;
    _inFlight = null;
  }

  /// The `iat` (issued at) of a JWT, or null when it cannot be read. The
  /// signature is not checked — only the server can — this is a hint of age.
  static DateTime? issuedAt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final iat = payload is Map ? payload['iat'] : null;
      if (iat is! num || iat <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch((iat * 1000).round(), isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Whether [token] is due for a refresh at [at]: the server's
  /// [refreshAfter] has passed, or — when it is not known — the token is more
  /// than a day old.
  static bool isDue(String token, {DateTime? refreshAfter, required DateTime at}) {
    if (refreshAfter != null) return !at.isBefore(refreshAfter);
    final iat = issuedAt(token);
    return iat != null && at.difference(iat) > const Duration(days: 1);
  }

  /// Refreshes the token when it is due. Returns true when a new token was
  /// saved. Never throws; one refresh at a time.
  static Future<bool> maybeRefresh() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  static Future<bool> _run() async {
    try {
      final token = await ApiService.getToken();
      if (token == null || token.isEmpty || SessionGuard.signedOut) return false;
      if (!isDue(token, refreshAfter: _refreshAfter, at: now())) return false;
      final res = await ApiService.refreshSession();
      final fresh = res['token'];
      if (fresh is String && fresh.isNotEmpty && res['error'] == null) {
        // A sign-out that landed while this was out wins.
        if (SessionGuard.signedOut) return false;
        await ApiService.saveToken(fresh);
        _refreshAfter = null;
        noteRefreshAfter(res['refreshAfter']);
        return true;
      }
      // 409 TOO_EARLY: not yet — its answer says when. 429 / 5xx / offline:
      // try again at the next start or resume. 401 / 403 were handled by the
      // HTTP layer (signed out).
      if (res['code'] == 'TOO_EARLY') noteRefreshAfter(res['refreshAfter']);
      return false;
    } catch (_) {
      return false;
    }
  }
}
