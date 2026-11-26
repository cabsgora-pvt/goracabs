import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_version.dart';

/// Gora Cabs on the Play Store.
const kRiderPlayStoreId = 'com.gora.gora_cabs';
const kRiderPlayStoreUrl = 'https://play.google.com/store/apps/details?id=$kRiderPlayStoreId';

/// Opens the Play Store page (the Play Store app, else the browser).
Future<void> openRiderStorePage(BuildContext context) async {
  for (final u in [Uri.parse('market://details?id=$kRiderPlayStoreId'), Uri.parse(kRiderPlayStoreUrl)]) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the Play Store')));
  }
}

/// The text "Share App" sends.
String shareAppText() => 'Book bikes, autos and cabs with Gora Cabs — safe, fast and reliable. Download: $kRiderPlayStoreUrl';

Future<void> shareRiderApp() => Share.share(shareAppText(), subject: 'Gora Cabs');

void showAboutGora(BuildContext context) => showAboutDialog(
      context: context,
      applicationName: 'Gora Cabs',
      applicationVersion: 'Version $kAppVersion',
      applicationLegalese: 'Bike, auto, cab, rental, outstation, parcel and hire-a-driver rides.\nSupport: support@goracabs.com',
    );

class RiderPrivacyScreen extends StatelessWidget {
  const RiderPrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Privacy Policy',
        sections: [
          ['Information We Collect',
              'Your name, phone number, email (optional), the places you book rides to and from, payments and wallet activity, and your location while you use the app.'],
          ['How We Use It',
              'To find you a driver, show the route and fare, process payments and refunds, keep trips safe and give you support.'],
          ['Location Data',
              'We use your location to set the pickup and show nearby vehicles and places. During a trip your driver sees the pickup and drop you chose.'],
          ['Sharing',
              'Your driver sees your first name, pickup and drop during an active trip. Payments go through certified payment partners. We never sell your personal data.'],
          ['Safety',
              'If you use SOS, we share your trip and location with our safety team and the emergency contacts you choose.'],
          ['Your Rights',
              'You can ask to see, correct or delete your data from Help & Support, or close your account from Settings → Delete Account.'],
          ['Contact',
              'For privacy questions, write to us from Help & Support or email support@goracabs.com.'],
        ],
      );
}

class RiderTermsScreen extends StatelessWidget {
  const RiderTermsScreen({super.key});
  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Terms & Conditions',
        sections: [
          ['Using Gora Cabs',
              'Gora Cabs connects you with independent drivers for rides, rentals, outstation trips, parcels and hire-a-driver. Bookings are made at the fare shown in the app.'],
          ['Fares & Payment',
              'The app shows the fare before you book. Waiting time, extra stops, extensions, tolls and tips are added as shown during the trip. Pay by cash, wallet or online.'],
          ['Cancellations',
              'Cancelling before a driver accepts is free. After a driver is on the way a cancellation fee may apply — the app shows it before you confirm.'],
          ['Parcels',
              'Do not send illegal, dangerous or restricted items. You are responsible for what you send and for sharing the delivery PIN only with the receiver.'],
          ['Your Conduct',
              'Treat drivers with respect, be at the pickup on time and do not damage the vehicle. Accounts can be held or blocked for misuse.'],
          ['Refunds',
              'Refunds for cancelled or prepaid trips go back to your Gora wallet. Raise any payment issue in Help & Support.'],
          ['Changes',
              'We may update these terms and fares. Continuing to use the app means you accept the changes.'],
          ['Contact',
              'Questions? Reach us via Help & Support or email support@goracabs.com.'],
        ],
      );
}

class _LegalScaffold extends StatelessWidget {
  final String title;
  final List<List<String>> sections;
  const _LegalScaffold({required this.title, required this.sections});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), elevation: 0),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final s in sections) ...[
              Text(s[0], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(s[1], style: const TextStyle(fontSize: 14.5, height: 1.45)),
              const SizedBox(height: 18),
            ],
          ],
        ),
      );
}
