import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the driver's session token lives.
///
/// It used to sit in plain SharedPreferences, which Android backs up and which
/// any root/backup extraction reads as text. It now lives in
/// flutter_secure_storage (keystore-encrypted). A token an older build left in
/// SharedPreferences is moved over once, on first read.
///
/// Nothing is cached between reads: the "You're online" background isolate is
/// a separate Dart heap, so a token refreshed by the app must be read fresh
/// there. flutter_foreground_task starts that isolate on a FlutterEngine that
/// registers every plugin (FlutterEngine(context) → automaticallyRegisterPlugins),
/// so secure storage works in it the same way SharedPreferences did.
///
/// When the secure store itself is unavailable (no plugin — widget tests — or
/// a broken keystore) the token falls back to SharedPreferences, so a driver
/// is never signed out by a storage failure.
class TokenStore {
  static const key = 'driver_token';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// The token as last read or written in THIS isolate — for places that need
  /// it synchronously (image request headers). API calls always use [read].
  static String? lastKnown;

  static Future<String?> read() async {
    String? v;
    try {
      v = await _secure.read(key: key);
    } catch (_) {
      v = await _prefsRead();
      lastKnown = v;
      return v;
    }
    if (v == null || v.isEmpty) {
      // One-time migration from an older build's SharedPreferences.
      final legacy = await _prefsRead();
      if (legacy != null && legacy.isNotEmpty) {
        v = legacy;
        try {
          await _secure.write(key: key, value: legacy);
          await _prefsRemove();
        } catch (_) {/* keep it in prefs; the next read tries again */}
      } else {
        v = null;
      }
    }
    lastKnown = v;
    return v;
  }

  static Future<void> write(String token) async {
    lastKnown = token;
    try {
      await _secure.write(key: key, value: token);
      // Never leave an older copy behind in plain prefs.
      await _prefsRemove();
      return;
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, token);
    } catch (_) {}
  }

  static Future<void> clear() async {
    lastKnown = null;
    try { await _secure.delete(key: key); } catch (_) {}
    await _prefsRemove();
  }

  static Future<String?> _prefsRead() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _prefsRemove() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(key);
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() => lastKnown = null;
}

/// Request headers for showing [url]. A private upload (/api/files/…: KYC
/// documents, face photos — and the profile picture, which is the face
/// capture) is served only to its owner, so it needs the session token.
/// Null for any other image.
Map<String, String>? imageHeadersFor(String url) {
  if (!url.contains('/api/files/')) return null;
  final t = TokenStore.lastKnown;
  if (t == null || t.isEmpty) return null;
  return {'Authorization': 'Bearer $t'};
}
