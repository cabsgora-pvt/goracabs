import 'package:flutter/material.dart';
import 'reg_motion.dart';
import 'reg_ui.dart';

// The registration checklist is driven by the server's linear registration
// flow (personal → face → vehicle → documents → submitted). The documents
// step submits the application (finish: true); bank details are no longer
// asked for at registration. A tappable hub of independent steps would invent
// routing the backend does not have, so each step page instead carries the
// checklist in its header.
//
// Layout for every step page:
//   ┌ deep-blue gradient hero ───────────────────────┐
//   │ (←)                              [Step 2 of 4] │
//   │ Big white title                                │
//   │ one-line subtitle                              │
//   │ (✓)───(2)───(3)───(4)   numbered stepper       │
//   │ Personal Selfie Vehicle Documents              │
//   │ [optional hero extra, e.g. documents ring]     │
//   ╰─╮ white sheet, rounded top, pulled up ╭────────╯
//     … sections, each fading/sliding in a beat after the one above …
//   [ gradient CTA → ]  (stays above the keyboard)
class RegStepScaffold extends StatelessWidget {
  final int step;
  final String stepLabel;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;
  final bool scroll;
  /// Defaults to Navigator.maybePop: a step resumed straight from splash is
  /// the only route, and a bare pop would leave a blank screen.
  final VoidCallback? onBack;
  final bool showBack;
  /// Stagger each of [children] in. Pages that stagger their own sections
  /// (inside a Form) turn this off.
  final bool staggerChildren;
  /// Extra content on the hero under the stepper (e.g. a progress ring).
  final Widget? heroExtra;

  const RegStepScaffold({
    super.key,
    required this.step,
    required this.stepLabel,
    required this.title,
    this.subtitle,
    required this.children,
    this.bottom,
    this.scroll = true,
    this.onBack,
    this.showBack = true,
    this.staggerChildren = true,
    this.heroExtra,
  });

  /// Entrance index of the first child — the header takes 0 and 1.
  static const firstChildIndex = 2;

  @override
  Widget build(BuildContext context) {
    final hero = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (showBack) RegHeroBack(onPressed: onBack ?? () => Navigator.maybePop(context)) else const SizedBox(height: 40),
          const Spacer(),
          Semantics(label: stepLabel, child: RegStepPill(step: step)),
        ]),
        const SizedBox(height: 14),
        RegEntrance(
          index: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 20),
        RegEntrance(index: 1, child: RegStepper(step: step)),
        if (heroExtra != null) ...[
          const SizedBox(height: 18),
          RegEntrance(index: 1, child: heroExtra!),
        ],
      ]),
    );
    return RegHeroPage(
      hero: hero,
      bottom: bottom,
      sheetChildren: [
        for (final (i, c) in children.indexed)
          staggerChildren ? RegEntrance(index: firstChildIndex + i, child: c) : c,
      ],
    );
  }
}
