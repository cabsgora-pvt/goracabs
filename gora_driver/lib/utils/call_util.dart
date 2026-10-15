import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer pre-filled with [phone]. Does not auto-dial.
///
/// Returns true when the dialer opened.
///
/// This exists because the SOS screen's "Call Police" and "Call Safety Team"
/// buttons silently did nothing on modern Android. They launched only when
/// `canLaunchUrl('tel:...')` returned true, and on Android 11+ that returns false
/// unless the manifest declares a DIAL query — which it did not. An emergency
/// call that fails without a word is the worst possible failure mode.
///
/// So this deliberately:
///
///  * Does not gate on `canLaunchUrl`. It calls `launchUrl` and handles a false
///    result, as the url_launcher documentation recommends, so a missing or
///    wrong package-visibility declaration can never silently block a call.
///
///  * Never fails silently. With [context], an unreachable dialer shows the
///    number and copies it, so the driver can still dial it themselves.
Future<bool> dialPhone(String phone, {BuildContext? context}) async {
  // Keep only what a dialer understands: "+91 98765 43210" -> "+919876543210".
  // Short emergency codes such as 100 and 112 pass through unchanged.
  final cleaned = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available')),
      );
    }
    return false;
  }

  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: cleaned));
  } catch (_) {
    opened = false;
  }

  if (!opened && context != null && context.mounted) {
    await Clipboard.setData(ClipboardData(text: cleaned));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('Could not open the dialer. Dial $cleaned — number copied.'),
        ),
      );
    }
  }
  return opened;
}
