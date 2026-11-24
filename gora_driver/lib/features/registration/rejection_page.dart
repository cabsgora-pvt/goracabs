import 'package:flutter/material.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'personal_details_page.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_ui.dart';
import 'widgets/status_views.dart';

class RejectionPage extends StatelessWidget {
  static const route = '/registration/rejected';
  const RejectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final reason = args?['reason'] as String? ?? 'Your application was not approved.';
    final driver = args?['driver'] as Map?;

    return RegHeroPage(
      // Content arrives top to bottom: mark (springs in), heading, reason.
      hero: RegStatusHero(
        badge: RegPopIn(
          duration: const Duration(milliseconds: 800),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.14)),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Cap.surface),
              child: const CapIllustration(icon: Icons.report_gmailerrorred_rounded, color: Cap.red, size: 96),
            ),
          ),
        ),
        title: 'Application not approved',
        subtitle: 'Fix the issue below and resubmit — your details are kept.',
      ),
      sheetChildren: [
        RegEntrance(index: 3, child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Cap.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Cap.red.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const RegIconBadge(icon: Icons.info_rounded, color: Cap.red, size: 30),
              const SizedBox(width: 10),
              Text('Reason', style: Cap.body(size: 14, weight: FontWeight.w800, color: Cap.red)),
            ]),
            const SizedBox(height: 10),
            Text(reason, style: Cap.body(size: 14.5, weight: FontWeight.w600).copyWith(height: 1.45)),
          ]),
        )),
        const SizedBox(height: 22),
        RegEntrance(index: 4, child: Text('How to resubmit', style: Cap.title(size: 17))),
        const SizedBox(height: 12),
        for (final (i, (icon, text)) in const [
          (Icons.edit_note_rounded, 'Tap "Fix and resubmit" below.'),
          (Icons.fact_check_outlined, 'Go through each step and correct what the reason mentions.'),
          (Icons.send_rounded, 'Submit your documents again for review.'),
        ].indexed)
          RegEntrance(
            index: 5 + i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                RegIconBadge(icon: icon, color: RegPalette.blue, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: Cap.body(size: 13.5, weight: FontWeight.w600))),
              ]),
            ),
          ),
      ],
      bottomTop: TextButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Support: support@goracabs.com')),
          );
        },
        icon: Icon(Icons.support_agent_rounded, color: Cap.ink, size: 19),
        label: Text('Contact support', style: Cap.body(size: 14, weight: FontWeight.w700)),
      ),
      bottom: RegCta(
        label: 'Fix and resubmit',
        trailing: Icons.refresh_rounded,
        onPressed: () {
          Navigator.pushNamedAndRemoveUntil(
            context,
            PersonalDetailsPage.route,
            (_) => false,
            arguments: {'driver': driver},
          );
        },
      ),
    );
  }
}
