import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's own Android hooks (MainActivity.kt, channel "gora/device").
/// Every call is best-effort: no platform (tests, iOS) means nothing happens.
class DeviceChannel {
  static const _ch = MethodChannel('gora/device');

  /// Stops showing over the lock screen (set only for a launch from the
  /// full-screen ride-request alert).
  static Future<void> releaseLockScreen() => _call('releaseLockScreen');

  /// The phone's own notification sound — the last ringtone fallback.
  static Future<bool> playSystemAlert() async => (await _call('playSystemAlert')) == true;

  static Future<void> stopSystemAlert() => _call('stopSystemAlert');

  static Future<Object?> _call(String m) async {
    try {
      return await _ch.invokeMethod<Object?>(m);
    } catch (_) {
      return null;
    }
  }
}

/// Asks, once, to leave the app out of battery optimisation — with the reason
/// first. Doze otherwise stops the online service's polling on many phones,
/// and requests stop alerting while the screen is off.
///
/// Uses flutter_foreground_task's own request (the system dialog for
/// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS). Never asked again once answered,
/// whatever the answer.
class BatteryOptimisation {
  static const askedKey = 'battery_opt_asked';

  /// Test seams.
  @visibleForTesting
  static Future<bool> Function() isIgnoring = () => FlutterForegroundTask.isIgnoringBatteryOptimizations;
  @visibleForTesting
  static Future<bool> Function() request = () => FlutterForegroundTask.requestIgnoreBatteryOptimization();

  static Future<void> askOnce(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(askedKey) == true) return;
      if (await isIgnoring()) {
        await prefs.setBool(askedKey, true);
        return;
      }
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keep ride alerts on'),
          content: const Text(
            'Your phone may pause Gora Captain in the background to save battery, '
            'and then new ride requests do not ring while the screen is off.\n\n'
            'Allow Gora Captain to run without battery restrictions?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Allow')),
          ],
        ),
      );
      await prefs.setBool(askedKey, true);
      if (ok == true) await request();
    } catch (_) {}
  }
}
