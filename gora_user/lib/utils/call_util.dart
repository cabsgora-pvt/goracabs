import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer pre-filled with [phone]. Does not auto-dial.
///
/// Returns true when the dialer opened.
///
/// Two things this deliberately does NOT do any more:
///
///  * Gate on `canLaunchUrl`. That call needs a matching package-visibility
///    declaration and gives false negatives in practice — iOS without a
///    `tel` entry in LSApplicationQueriesSchemes, some OEM Android builds, and
///    dialer-less tablets — so the button would silently do nothing. The
///    url_launcher documentation recommends calling `launchUrl` directly and
///    handling a false result instead, which is what this does.
///
///  * Fail silently. When the dialer cannot open, and [context] is supplied, the
///    rider is told and the number is copied to the clipboard, so they can
///    still reach the driver from their own phone app.
Future<bool> dialPhone(String phone, {BuildContext? context}) async {
  // Keep only what a dialer understands. Stored numbers arrive as
  // "+91 98765 43210", "098765-43210" and similar; spaces become %20 in a URI.
  final cleaned = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number is not available yet')),
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
        SnackBar(content: Text('Could not open the dialer. $cleaned copied to clipboard.')),
      );
    }
  }
  return opened;
}
