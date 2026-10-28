import 'package:flutter/material.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

// The registration checklist is driven by the server's linear registration
// flow (personal → face → vehicle → documents → bank → submitted), and the
// server only lets the app resume at 'bank' or 'submitted'. A tappable hub of
// independent steps would invent routing the backend does not have, so each
// step page instead carries the checklist as a "Step N of 5" header.
//
// Layout for every step page:
//   ← back
//   Step 2 of 5 · Face verification
//   ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
//   Big bold title
//   Grey subtitle
//   … form …
//   [ single bottom CTA ]
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
  });

  @override
  Widget build(BuildContext context) {
    final header = <Widget>[
      CapStepper(step: step, total: CapRegSteps.total, label: stepLabel),
      const SizedBox(height: 22),
      CapHeading(title, subtitle: subtitle, size: 25),
      const SizedBox(height: 24),
    ];
    return Scaffold(
      backgroundColor: Cap.surface,
      appBar: AppBar(
        backgroundColor: Cap.surface,
        foregroundColor: Cap.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: onBack ?? () => Navigator.maybePop(context),
              )
            : null,
      ),
      body: scroll
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...header, ...children]),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...header, ...children]),
            ),
      bottomNavigationBar: bottom == null ? null : CapBottomBar(child: bottom!),
    );
  }
}
