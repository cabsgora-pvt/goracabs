import 'package:flutter/material.dart';
import '../../../core/widgets/app_widgets.dart';

class PrivacyPolicyPage extends StatelessWidget {
  static const route = '/privacy';
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Privacy Policy',
        sections: [
          ['Information We Collect',
              'We collect your name, phone number, email, vehicle and bank details, uploaded documents, and your live location while you are online — to operate the Gora Captain driver service.'],
          ['How We Use It',
              'Your data is used to match you with ride requests, process payments and payouts, verify your identity, and provide support. Location is used only to assign nearby rides and enable navigation.'],
          ['Location Data',
              'We access your location while you are ONLINE so we can send you nearby requests and share your position with the rider during an active trip. You can go offline anytime to stop this.'],
          ['Sharing',
              'Riders see your name, photo, vehicle, and live location during an active trip. Bank details are shared only with our payment partner to process withdrawals. We never sell your personal data.'],
          ['Data Security',
              'Your information is stored securely with restricted access. Payment credentials are handled by certified payment gateways.'],
          ['Your Rights',
              'You may request access, correction, or deletion of your data by contacting support from within the app.'],
          ['Contact',
              'For any privacy questions, reach us via Support in the app or email support@goracaptain.com.'],
        ],
      );
}

class TermsPage extends StatelessWidget {
  static const route = '/terms';
  const TermsPage({super.key});
  @override
  Widget build(BuildContext context) => const _LegalScaffold(
        title: 'Terms of Service',
        sections: [
          ['Eligibility',
              'You must hold a valid driving licence and vehicle documents and be approved by Gora Captain to accept rides.'],
          ['Your Responsibilities',
              'Drive safely and lawfully, keep your documents valid, maintain your vehicle, and treat riders respectfully. You are responsible for the rides you accept.'],
          ['Payments & Commission',
              'Fares, platform commission, and any subscription are shown in the app. On cash rides the commission is deducted from your wallet; on online rides your earning is credited to your wallet after commission. Tips are 100% yours.'],
          ['Wallet & Withdrawals',
              'Earnings accumulate in your Gora wallet. Withdrawals are paid to your registered bank account after admin approval. A minimum withdrawal amount may apply.'],
          ['Account Suspension',
              'We may suspend or block accounts that violate these terms, submit false documents, or receive repeated complaints.'],
          ['Cancellations',
              'Excessive cancellations or not showing up for accepted rides may affect your rating and eligibility for requests.'],
          ['Changes',
              'We may update these terms and the applicable fares/commission from time to time. Continued use of the app means you accept the changes.'],
          ['Contact',
              'Questions? Reach us via Support in the app or email support@goracaptain.com.'],
        ],
      );
}

class _LegalScaffold extends StatelessWidget {
  final String title;
  final List<List<String>> sections;
  const _LegalScaffold({required this.title, required this.sections});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: blueAppBar(title),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Last updated: July 2026', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
        const SizedBox(height: 16),
        ...sections.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s[0], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
                const SizedBox(height: 6),
                Text(s[1], style: const TextStyle(fontSize: 13.5, height: 1.5)),
              ]),
            )),
        const SizedBox(height: 20),
      ]),
    );
  }
}
