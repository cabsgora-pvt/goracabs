import 'package:url_launcher/url_launcher.dart';

// Open the phone dialer pre-filled with [phone] (does not auto-dial).
Future<void> dialPhone(String phone) async {
  if (phone.trim().isEmpty) return;
  final uri = Uri(scheme: 'tel', path: phone.trim());
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}
