import 'package:flutter/material.dart';
import '../screens/welcome_screen.dart';
import 'api_service.dart';

/// Why the rider is being signed out, which decides what they are told.
enum SignOutReason {
  /// The token expired or is no longer valid (a plain 401).
  expired,

  /// The server ended this session (401 SESSION_REVOKED): signed out on
  /// another device, or by support.
  revoked,

  /// An admin blocked the account (403 ACCOUNT_BLOCKED).
  blocked,

  /// The account was deleted (401 / 403 ACCOUNT_DELETED).
  deleted,
}

/// What happens when the server stops accepting the rider's token.
///
/// There used to be no central handling: an expired or revoked token left the
/// rider on whatever screen they were on, with every poll failing quietly and
/// every action answering "Unauthorized". Now the shared HTTP layer reports a
/// refusal of the rider's token from any call that carried it, and the rider
/// is signed out ONCE — token cleared, every screen (and so every poll timer)
/// taken off the stack, the welcome screen shown with the reason. Later
/// refusals from requests still in flight are ignored until the rider signs in
/// again ([ApiService.saveToken] re-arms).
///
/// A 401 that says {accountDeleted: true} (the profile call) is left to the
/// existing account deletion flow (UserProvider + home), which explains why the
/// rider was signed out.
class SessionGuard {
  SessionGuard._();

  /// The app's navigator, so a sign-out can leave from wherever the rider is.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _signedOut = false;

  /// True between a sign-out and the next sign-in. Polls can check it.
  static bool get signedOut => _signedOut;

  /// Bumps on every sign-out, for anything that wants to react.
  static final ValueNotifier<int> signOuts = ValueNotifier<int>(0);

  /// The reason of the last sign-out (for tests and the welcome screen).
  static SignOutReason? lastReason;

  /// Re-arms after a fresh sign-in.
  static void reset() => _signedOut = false;

  /// Whether an answer to a request that carried the rider's token means the
  /// rider must be signed out, and why; null when it does not.
  ///
  ///   401 (any)                     → signed out (expired / revoked / deleted)
  ///   401 {accountDeleted: true}    → null: the account deletion flow owns it
  ///   403 {code: ACCOUNT_BLOCKED}   → blocked
  ///   403 {code: ACCOUNT_DELETED}   → deleted
  ///   any other 403 (NOT_PARTICIPANT, an account hold, driverMustEnd, ...)
  ///                                 → null: the rider stays signed in
  static SignOutReason? signOutReasonFor(int status, Map<String, dynamic> body) {
    final code = body['code']?.toString();
    if (status == 401) {
      if (body['accountDeleted'] == true) return null;
      if (code == 'SESSION_REVOKED') return SignOutReason.revoked;
      if (code == 'ACCOUNT_DELETED') return SignOutReason.deleted;
      return SignOutReason.expired;
    }
    if (status == 403) {
      if (code == 'ACCOUNT_BLOCKED') return SignOutReason.blocked;
      if (code == 'ACCOUNT_DELETED') return SignOutReason.deleted;
    }
    return null;
  }

  /// What the rider reads for [reason].
  static String messageFor(SignOutReason reason) => switch (reason) {
        SignOutReason.expired => 'Your session has expired. Please sign in again.',
        SignOutReason.revoked => 'Your session has ended. Please sign in again.',
        SignOutReason.blocked => 'Your account is blocked, contact support',
        SignOutReason.deleted => 'This account has been deleted. You have been signed out.',
      };

  /// The server refused the rider's token. Runs its effect once.
  static Future<void> onUnauthorized({SignOutReason reason = SignOutReason.expired}) async {
    if (_signedOut) return;
    _signedOut = true;
    lastReason = reason;
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
    final text = messageFor(reason);
    if (reason == SignOutReason.blocked) {
      // Not a blip to retry: a dialog the rider has to read, not a snack bar.
      showDialog<void>(
        context: nav.context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('account-blocked-dialog'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(Icons.block_rounded, color: Color(0xFFD32F2F), size: 36),
          title: const Text('Account blocked', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text(text, textAlign: TextAlign.center),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
    ));
  }
}
