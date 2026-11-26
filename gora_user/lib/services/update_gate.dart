import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_version.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'api_service.dart';

/// What the server's version settings mean for this build.
enum UpdateLevel { none, optional, required }

/// The admin's version settings for the rider app (GET /api/app-config?app=user
/// → config.version {latestVersion, minVersion, forceUpdate, message, storeUrl}).
class AppVersionPolicy {
  final String latestVersion;
  final String minVersion;
  final bool forceUpdate;
  final String message;
  final String storeUrl;
  const AppVersionPolicy({
    this.latestVersion = '',
    this.minVersion = '',
    this.forceUpdate = false,
    this.message = '',
    this.storeUrl = '',
  });

  static AppVersionPolicy? fromConfig(Map<String, dynamic> config) {
    final v = config['version'];
    if (v is! Map) return null;
    return AppVersionPolicy(
      latestVersion: '${v['latestVersion'] ?? ''}'.trim(),
      minVersion: '${v['minVersion'] ?? ''}'.trim(),
      forceUpdate: v['forceUpdate'] == true,
      message: '${v['message'] ?? ''}'.trim(),
      storeUrl: '${v['storeUrl'] ?? ''}'.trim(),
    );
  }
}

/// Compares two dotted versions ("1.6.0", "1.10"), numerically, segment by
/// segment; a missing segment is 0. Null when either is not a version.
int? compareVersions(String a, String b) {
  List<int>? parse(String v) {
    final core = v.trim().split('+').first;
    if (!RegExp(r'^\d{1,4}(\.\d{1,4}){0,3}$').hasMatch(core)) return null;
    return core.split('.').map(int.parse).toList();
  }
  final x = parse(a), y = parse(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < 4; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}

/// Below minVersion → required. Below latestVersion → required when
/// forceUpdate is on, else optional. Otherwise (or unreadable settings) none.
UpdateLevel updateLevelFor(String current, AppVersionPolicy? p) {
  if (p == null) return UpdateLevel.none;
  final belowMin = p.minVersion.isNotEmpty && (compareVersions(current, p.minVersion) ?? 0) < 0;
  if (belowMin) return UpdateLevel.required;
  final belowLatest = p.latestVersion.isNotEmpty && (compareVersions(current, p.latestVersion) ?? 0) < 0;
  if (!belowLatest) return UpdateLevel.none;
  return p.forceUpdate ? UpdateLevel.required : UpdateLevel.optional;
}

/// The update state the app shows: a blocking screen for a required update,
/// a dismissible banner (once per session) for an optional one.
class UpdateGate {
  UpdateGate._();

  static const _playStore = 'https://play.google.com/store/apps/details?id=com.gora.gora_cabs';

  /// What is shown now; [UpdateOverlay] listens.
  static final ValueNotifier<({UpdateLevel level, AppVersionPolicy? policy})> state =
      ValueNotifier((level: UpdateLevel.none, policy: null));

  /// The optional banner was closed: not shown again this session.
  static bool bannerDismissed = false;

  static DateTime? _lastCheck;

  /// Replaceable in tests.
  static String currentVersion = kAppVersion;

  /// Fetches the version settings and updates [state]. At most every
  /// [minGap] unless [force]; a failed fetch leaves the state as it was.
  static Future<void> check({bool force = false, Duration minGap = const Duration(minutes: 10)}) async {
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < minGap) return;
    _lastCheck = DateTime.now();
    try {
      final cfg = await ApiService.getAppConfig(force: true);
      final p = AppVersionPolicy.fromConfig(cfg);
      if (p == null) return;
      apply(p);
    } catch (_) {}
  }

  static void apply(AppVersionPolicy p) {
    var level = updateLevelFor(currentVersion, p);
    if (level == UpdateLevel.optional && bannerDismissed) level = UpdateLevel.none;
    state.value = (level: level, policy: p);
  }

  static void dismissBanner() {
    bannerDismissed = true;
    final s = state.value;
    if (s.level == UpdateLevel.optional) state.value = (level: UpdateLevel.none, policy: s.policy);
  }

  /// For tests.
  static void reset() {
    bannerDismissed = false;
    _lastCheck = null;
    currentVersion = kAppVersion;
    state.value = (level: UpdateLevel.none, policy: null);
  }

  static Future<void> openStore(AppVersionPolicy? p) async {
    final url = (p?.storeUrl ?? '').isNotEmpty ? p!.storeUrl : _playStore;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// Sits above every screen (MaterialApp.builder): a required update covers the
/// app — it is above the navigator, so no route change can take it away — and
/// an optional one shows a banner at the top that the rider can close.
class UpdateOverlay extends StatelessWidget {
  final Widget child;
  const UpdateOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({UpdateLevel level, AppVersionPolicy? policy})>(
      valueListenable: UpdateGate.state,
      builder: (context, s, _) => Stack(children: [
        child,
        if (s.level == UpdateLevel.optional)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(bottom: false, child: _UpdateBanner(policy: s.policy)),
          ),
        if (s.level == UpdateLevel.required) Positioned.fill(child: _UpdateRequired(policy: s.policy)),
      ]),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final AppVersionPolicy? policy;
  const _UpdateBanner({this.policy});

  @override
  Widget build(BuildContext context) {
    final msg = (policy?.message ?? '').isNotEmpty
        ? policy!.message
        : 'A new version of Gora Cabs is available.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        key: const ValueKey('update-banner'),
        elevation: 6,
        shadowColor: Colors.black38,
        color: RideUi.navy,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(children: [
            const Icon(Icons.system_update_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => UpdateGate.openStore(policy),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              key: const ValueKey('update-banner-close'),
              // No tooltip: this sits above the navigator, where no Overlay exists.
              onPressed: UpdateGate.dismissBanner,
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            ),
          ]),
        ),
      ),
    );
  }
}

class _UpdateRequired extends StatelessWidget {
  final AppVersionPolicy? policy;
  const _UpdateRequired({this.policy});

  @override
  Widget build(BuildContext context) {
    final msg = (policy?.message ?? '').isNotEmpty
        ? policy!.message
        : 'This version of Gora Cabs is no longer supported. Please update to continue.';
    return Material(
      key: const ValueKey('update-required'),
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.system_update_rounded, color: RideUi.navy, size: 44),
                const SizedBox(height: 12),
                Text('Update required', style: RideUi.title(context, size: 19)),
                const SizedBox(height: 8),
                Text(msg, textAlign: TextAlign.center,
                    style: RideUi.body(context, size: 14, weight: FontWeight.w500).copyWith(height: 1.4)),
                if ((policy?.latestVersion ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('You have ${UpdateGate.currentVersion} · latest ${policy!.latestVersion}',
                      style: RideUi.caption(context, size: 12)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => UpdateGate.openStore(policy),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideUi.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
