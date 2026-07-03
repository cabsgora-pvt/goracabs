import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';

class FaqPage extends StatefulWidget {
  static const route = '/faq';
  const FaqPage({super.key});
  @override State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final _faqs = const [
    _Faq('How do I go online to receive rides?', 'Tap the "OFF DUTY" toggle on the home screen to switch to "ON DUTY". Once online, you\'ll start receiving ride requests near your location.'),
    _Faq('How is my fare calculated?', 'Fare = Base Fare + (Distance × Per km Rate) + (Time × Per min Rate). You can view exact rates on the Rate Card page under your account.'),
    _Faq('When will I receive my earnings?', 'Cash payments are received directly from riders. Wallet payments are credited to your in-app wallet immediately after ride completion.'),
    _Faq('How do I withdraw my wallet balance?', 'Go to Account → Wallet → Withdraw. Enter the amount and confirm. Transfers typically take 24–48 hours to reach your bank account.'),
    _Faq('What should I do if a rider cancels?', 'If the rider cancels after you\'ve arrived at pickup, you may be eligible for a cancellation fee. This will be auto-credited to your wallet.'),
    _Faq('How do I raise a complaint about a rider?', 'Go to Account → Support Tickets → New Ticket. Describe your issue. Our team will respond within 24 hours.'),
    _Faq('How is my rating calculated?', 'Your rating is the average of all rider reviews. Completing rides without cancellations and maintaining professionalism helps keep your rating high.'),
    _Faq('What documents do I need to drive?', 'You need: Driving License, Vehicle RC, Insurance Certificate, and Permit. Upload them under Account → Documents.'),
    _Faq('How does the referral program work?', 'Share your unique referral code with other drivers. When they join and complete 10 rides, you earn ₹200 bonus credited to your wallet.'),
    _Faq('What is the SOS feature?', 'SOS lets you instantly alert your emergency contacts and our support team in case of danger. Go to Account → SOS Contacts to set up your contacts.'),
  ];

  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('FAQ'),
      backgroundColor: AppColors.cardBg,
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search FAQs...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _faqs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final open = _expanded.contains(i);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: open ? Border.all(color: AppColors.primary.withOpacity(0.3)) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                ),
                child: InkWell(
                  onTap: () => setState(() => open ? _expanded.remove(i) : _expanded.add(i)),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(_faqs[i].q,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: open ? AppColors.primary : AppColors.textDark)),
                        ),
                        Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: open ? AppColors.primary : AppColors.textGrey),
                      ]),
                      if (open) ...[
                        const SizedBox(height: 10),
                        Divider(color: AppColors.divider, height: 1),
                        const SizedBox(height: 10),
                        Text(_faqs[i].a, style: TextStyle(fontSize: 13, color: AppColors.textGrey, height: 1.5)),
                      ],
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Faq {
  final String q, a;
  const _Faq(this.q, this.a);
}
