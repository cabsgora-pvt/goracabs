import 'package:flutter/material.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// "Application under review" body shared by the KYC-submitted and
/// KYC-pending screens. Purely visual: both screens keep their own polling.
///
/// No promised turnaround times or "24/7" claims here — the app has no data
/// behind them, so the copy only states what actually happens next.
class UnderReviewView extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool justSubmitted;
  const UnderReviewView({
    super.key,
    required this.title,
    required this.subtitle,
    this.justSubmitted = false,
  });

  void _support(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support: support@goracabs.com')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cap.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: CapIllustration(
                    icon: justSubmitted ? Icons.task_alt_rounded : Icons.hourglass_top_rounded,
                    color: justSubmitted ? Cap.green : Cap.orange,
                  ),
                ),
                const SizedBox(height: 22),
                CapHeading(title, subtitle: subtitle, size: 24, align: TextAlign.center),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Cap.accent)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Waiting for admin approval…',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Cap.body(size: 12.5, weight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 26),
                Text('What happens next', style: Cap.title(size: 16.5)),
                const SizedBox(height: 12),
                const _NextStep(icon: Icons.fact_check_outlined, done: true,
                    title: 'Application submitted', text: 'Your details, documents and bank account are with us.'),
                const _NextStep(icon: Icons.manage_search_rounded,
                    title: 'Document verification', text: 'Our team checks your documents and selfie.'),
                const _NextStep(icon: Icons.notifications_active_outlined, last: true,
                    title: 'You get approved', text: 'This screen opens Home on its own once you are approved.'),
                const SizedBox(height: 22),
                CapButton(
                  label: 'Contact support',
                  icon: Icons.support_agent_rounded,
                  tone: CapButtonTone.secondary,
                  onPressed: () => _support(context),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final bool done, last;
  const _NextStep({required this.icon, required this.title, required this.text, this.done = false, this.last = false});

  @override
  Widget build(BuildContext context) {
    final c = done ? Cap.green : Cap.muted;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(done ? Icons.check_rounded : icon, size: 18, color: done ? Cap.green : Cap.ink),
            ),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: Cap.divider)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Cap.body(size: 14.5, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text, style: Cap.caption(size: 12.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}
