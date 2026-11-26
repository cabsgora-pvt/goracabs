import 'package:flutter/foundation.dart';
import '../config/app_version.dart';
import 'driver_api_service.dart';

/// Compares dotted versions ("1.4.0" vs "1.10"): negative when [a] is older.
/// Missing parts count as 0; anything that is not a number counts as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.trim().split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}

enum UpdateLevel { none, optional, required }

/// What the server's force-update settings mean for this build.
class UpdateNotice {
  final UpdateLevel level;
  final String latestVersion;
  final String message;
  final String storeUrl;
  const UpdateNotice(this.level, {this.latestVersion = '', this.message = '', this.storeUrl = defaultStoreUrl});

  @override
  bool operator ==(Object other) =>
      other is UpdateNotice && other.level == level && other.latestVersion == latestVersion &&
      other.message == message && other.storeUrl == storeUrl;
  @override
  int get hashCode => Object.hash(level, latestVersion, message, storeUrl);
}

/// config.version {latestVersion, minVersion, forceUpdate, message, storeUrl}
/// against [current]: below minVersion — or forceUpdate with a newer
/// latestVersion — must update (blocking); a newer latestVersion otherwise is
/// offered (dismissible); else nothing.
UpdateNotice updateNoticeFor(String current, dynamic version) {
  if (version is! Map) return const UpdateNotice(UpdateLevel.none);
  final latest = (version['latestVersion'] ?? '').toString().trim();
  final min = (version['minVersion'] ?? '').toString().trim();
  final message = (version['message'] ?? '').toString().trim();
  final store = (version['storeUrl'] ?? '').toString().trim();
  final url = store.startsWith('https://') ? store : defaultStoreUrl;
  final newer = latest.isNotEmpty && compareVersions(current, latest) < 0;
  final belowMin = min.isNotEmpty && compareVersions(current, min) < 0;
  if (belowMin || (version['forceUpdate'] == true && newer)) {
    return UpdateNotice(UpdateLevel.required, latestVersion: latest, message: message, storeUrl: url);
  }
  if (newer) return UpdateNotice(UpdateLevel.optional, latestVersion: latest, message: message, storeUrl: url);
  return const UpdateNotice(UpdateLevel.none);
}

/// Checks the server's update settings at start and on resume (at most every
/// [checkEvery]); [notice] drives the UpdateGate over every screen.
class AppUpdate {
  static final notice = ValueNotifier<UpdateNotice>(const UpdateNotice(UpdateLevel.none));
  static DateTime? _lastCheck;
  static String? _dismissed;
  static const checkEvery = Duration(minutes: 30);

  static Future<void> check({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < checkEvery) return;
    _lastCheck = now;
    try {
      final res = await DriverApiService.getAppConfig();
      final cfg = res['config'];
      if (res['error'] != null || cfg is! Map) return; // offline: keep what we had
      apply(updateNoticeFor(appVersion, cfg['version']));
    } catch (_) {}
  }

  /// Shows [n] — unless it is the optional update the driver already closed.
  static void apply(UpdateNotice n) {
    if (n.level == UpdateLevel.optional && _dismissed == n.latestVersion) {
      notice.value = const UpdateNotice(UpdateLevel.none);
      return;
    }
    notice.value = n;
  }

  /// Closes the optional banner (for this version). A required update cannot
  /// be dismissed.
  static void dismiss() {
    final n = notice.value;
    if (n.level != UpdateLevel.optional) return;
    _dismissed = n.latestVersion;
    notice.value = const UpdateNotice(UpdateLevel.none);
  }

  @visibleForTesting
  static void resetForTest() {
    _lastCheck = null;
    _dismissed = null;
    notice.value = const UpdateNotice(UpdateLevel.none);
  }
}
