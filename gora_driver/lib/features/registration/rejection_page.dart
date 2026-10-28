import 'package:flutter/material.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'personal_details_page.dart';

class RejectionPage extends StatelessWidget {
  static const route = '/registration/rejected';
  const RejectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final reason = args?['reason'] as String? ?? 'Your application was not approved.';
    final driver = args?['driver'] as Map?;

    return Scaffold(
      backgroundColor: Cap.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: CapIllustration(icon: Icons.report_gmailerrorred_rounded, color: Cap.red)),
            const SizedBox(height: 22),
            const CapHeading(
              'Application not approved',
              subtitle: 'Fix the issue below and resubmit — your details are kept.',
              size: 24,
              align: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Cap.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(Cap.radius),
                border: Border.all(color: Cap.red.withValues(alpha: 0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info_outline_rounded, color: Cap.red, size: 18),
                  const SizedBox(width: 8),
                  Text('Reason', style: Cap.body(size: 13, weight: FontWeight.w800, color: Cap.red)),
                ]),
                const SizedBox(height: 8),
                Text(reason, style: Cap.body(size: 14.5, weight: FontWeight.w600).copyWith(height: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: CapBottomBar(
        top: TextButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Support: support@goracabs.com')),
            );
          },
          icon: Icon(Icons.support_agent_rounded, color: Cap.ink, size: 19),
          label: Text('Contact support', style: Cap.body(size: 14, weight: FontWeight.w700)),
        ),
        child: CapButton(
          label: 'Fix and resubmit',
          icon: Icons.refresh_rounded,
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(
              context,
              PersonalDetailsPage.route,
              (_) => false,
              arguments: {'driver': driver},
            );
          },
        ),
      ),
    );
  }
}
