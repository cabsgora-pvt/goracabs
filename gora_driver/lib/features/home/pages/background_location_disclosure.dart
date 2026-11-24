import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/location_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// Set once the driver has seen the disclosure and chosen, so going online
/// does not ask every time. Device setting: kept across logins.
const bgLocationAskedKey = 'bg_location_disclosure_seen';

/// Shows the in-app disclosure, then Android's background-location prompt, when
/// the driver has allowed location only "while using the app".
///
/// Google Play requires a prominent disclosure, in the app, before the system
/// "Allow all the time" prompt. Without background location the online service
/// cannot send the driver's position once the app is minimised.
Future<void> maybeAskBackgroundLocation(BuildContext context, {
  @visibleForTesting Future<LocationPermission> Function()? check,
  @visibleForTesting Future<bool> Function()? request,
}) async {
  LocationPermission p;
  try {
    p = await (check ?? Geolocator.checkPermission)();
  } catch (_) {
    return;
  }
  // Only the "while in use" case: no grant at all is asked for by the normal
  // location flow first (Android allows the upgrade only after it).
  if (p != LocationPermission.whileInUse) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(bgLocationAskedKey) == true) return;
    await prefs.setBool(bgLocationAskedKey, true);
  } catch (_) {}
  if (!context.mounted) return;
  final go = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const BackgroundLocationDisclosurePage(),
  ));
  if (go == true) {
    await (request ?? LocationService.ensureBackgroundPermission)();
  }
}

class BackgroundLocationDisclosurePage extends StatelessWidget {
  const BackgroundLocationDisclosurePage({super.key});

  static const body =
      'Gora Captain collects your location to match you with nearby trip requests and '
      'to share your live position with riders during a trip — even when the app is '
      'closed or not in use, while you are online.\n\n'
      'Your location is not collected while you are offline. You can go offline, or '
      'change this permission in Settings, at any time.';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Cap.surface,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 24),
          Icon(Icons.location_on_rounded, size: 64, color: Cap.orange),
          const SizedBox(height: 20),
          Text('Allow location all the time', textAlign: TextAlign.center, style: Cap.title(size: 22)),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Text(body, style: Cap.body(size: 15).copyWith(height: 1.45)),
            ),
          ),
          const SizedBox(height: 12),
          Text('On the next screen, choose "Allow all the time".',
              textAlign: TextAlign.center, style: Cap.caption(size: 13)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('Continue'),
          ),
          const SizedBox(height: 6),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        ]),
      ),
    ),
  );
}
