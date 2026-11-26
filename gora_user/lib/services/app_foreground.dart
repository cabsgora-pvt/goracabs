import 'api_service.dart';
import 'payment_service.dart';
import 'session_guard.dart';
import 'session_refresh.dart';
import 'update_gate.dart';

/// What the app does each time it comes to the foreground — at start and on
/// every resume (GoraCabsApp's lifecycle observer):
///   • the force-update check (signed in or not),
///   • for a signed-in rider: refresh the session token when it is due, and
///     confirm any Razorpay payment whose verify never reached Gora.
class AppForeground {
  AppForeground._();

  /// Off under flutter_test (test/flutter_test_config.dart): a smoke test
  /// that pumps the whole app must not start network calls it never answers.
  static bool enabled = true;

  static Future<void>? _running;

  static Future<void> run() {
    if (!enabled) return Future.value();
    return _running ??= _run().whenComplete(() => _running = null);
  }

  static Future<void> _run() async {
    // Independent of each other; none of them throws.
    final update = UpdateGate.check();
    try {
      final token = await ApiService.getToken();
      if (token != null && token.isNotEmpty && !SessionGuard.signedOut) {
        await SessionRefresher.maybeRefresh();
        await PaymentService.retryPendingProofs();
      }
    } catch (_) {}
    await update;
  }
}
