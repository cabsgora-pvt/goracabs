import 'package:flutter/material.dart';
import '../screens/welcome_screen.dart';
import 'api_service.dart';

/// What happens when the server stops accepting the rider's token.
///
/// There used to be no central handling: an expired or revoked token left the
/// rider on whatever screen they were on, with every poll failing quietly and
/// every action answering "Unauthorized". Now the shared HTTP layer reports a
/// 401 from any call that carried a token here, and the rider is signed out
/// ONCE — token cleared, every screen (and so every poll timer) taken off the
/// stack, the welcome screen shown. Later 401s from requests still in flight
/// are ignored until the rider signs in again ([ApiService.saveToken] re-arms).
///
/// A 401 that says {accountDeleted: true} is left to the existing account
/// deletion flow (UserProvider + home), which explains why the rider was
/// signed out.
class SessionGuard {
  SessionGuard._();

  /// The app's navigator, so a sign-out can leave from wherever the rider is.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _signedOut = false;

  /// True between a 401 sign-out and the next sign-in. Polls can check it.
  static bool get signedOut => _signedOut;

  /// Bumps on every sign-out, for anything that wants to react.
  static final ValueNotifier<int> signOuts = ValueNotifier<int>(0);

  /// Re-arms after a fresh sign-in.
  static void reset() => _signedOut = false;

  /// The server rejected the rider's token. Runs its effect once.
  static Future<void> onUnauthorized() async {
    if (_signedOut) return;
    _signedOut = true;
    // Taken before the await: the navigator outlives every screen it removes.
    final nav = navigatorKey.currentState;
    await ApiService.clearToken();
    signOuts.value++;
    if (nav == null || !nav.mounted) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
    if (!nav.mounted) return;
    ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(const SnackBar(
        content: Text('Your session has expired. Please sign in again.'),
        duration: Duration(seconds: 5),
      ));
  }
}
