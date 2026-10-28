import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The always-visible state of the current job.
//
// Every on-ride screen showed its numbers somewhere different, and the ones that
// matter most were buried: a rental driver had to scroll a form to find out
// whether they had crossed into extra time, and the extra CHARGE was not shown
// at all until the closing bill. That is money accruing out of sight — the
// driver cannot tell the customer, and the customer is surprised at the end.
//
// One strip, one row, same position on every service screen:
//
//     [phase chip]   metric · metric · metric        [+₹ accruing]
//
// The accruing pill only appears once there is something to show, so a normal
// on-time job stays quiet.
// ─────────────────────────────────────────────────────────────────────────────

class RideStatusMetric {
  final IconData icon;
  final String value;
  /// Draws attention when this metric is the reason charges are accruing.
  final bool warn;
  const RideStatusMetric(this.icon, this.value, {this.warn = false});
}

class RideStatusStrip extends StatelessWidget {
  /// Short phase label — "On trip", "Extra time", "Overtime", "In transit".
  final String phase;

  /// True when the job has gone past what the customer booked. Turns the strip
  /// amber so the state is readable at a glance in a windscreen mount.
  final bool overrun;

  /// Two or three at most. A strip nobody can read at a glance is just a row.
  final List<RideStatusMetric> metrics;

  /// Extra money accrued so far, in rupees. Null or 0 hides the pill.
  final num? accruing;

  /// Optional label for the accruing pill — defaults to "extra".
  final String accruingLabel;

  const RideStatusStrip({
    super.key,
    required this.phase,
    required this.metrics,
    this.overrun = false,
    this.accruing,
    this.accruingLabel = 'extra',
  });

  static const _chipStyle = TextStyle(
    fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4, color: Colors.white,
  );
  static const _pillStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white);

  /// The width [text] takes on one line, drawn as a Text here would draw it.
  static double _widthOf(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final amber = overrun;
    // Neutral grey tile with near-black text; amber only when the job has
    // gone past what was booked.
    final fg = amber ? AppColors.orange : AppColors.textDark;
    final bg = amber ? AppColors.orange.withOpacity(0.10) : AppColors.cardBg;
    final showAccruing = (accruing ?? 0) > 0;
    final phaseLabel = phase.toUpperCase();
    final pillLabel = '+₹${(accruing ?? 0).round()} $accruingLabel';

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: amber ? AppColors.orange : const Color(0xFF111111), borderRadius: BorderRadius.circular(6)),
      child: Text(phaseLabel, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: _chipStyle),
    );
    // Ellipsis on the label: a long label next to a long phase chip overflowed
    // a 320pt screen by 67px. The amount is the part that must survive, so the
    // label is what gets truncated.
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(pillLabel, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: _pillStyle),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: amber ? Border.all(color: fg.withOpacity(0.25)) : null,
      ),
      child: LayoutBuilder(builder: (context, box) {
        // The pill takes what it needs and the metrics everything else. Only
        // when that leaves the metrics too little (a long phase, a five-figure
        // amount, a 320pt screen) do the two share the space and shrink. As a
        // plain Flexible the pill was handed half the free space whether it
        // needed it or not, and "310 min" was cut to "310" beside an empty gap.
        final roomy = !showAccruing || (box.hasBoundedWidth &&
            box.maxWidth
                - (_widthOf(context, phaseLabel, _chipStyle) + 17)
                - (_widthOf(context, pillLabel, _pillStyle) + 17)
                - 18 >= 72);
        return Row(children: [
          chip,
          const SizedBox(width: 10),
          // Metrics scroll rather than overflow: vehicle numbers and long
          // distances vary, and a RenderFlex overflow stripe across the driver's
          // screen mid-trip is worse than a scroll.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Text('·', style: TextStyle(color: fg.withOpacity(0.45))),
                    ),
                  Icon(metrics[i].icon,
                      size: 13,
                      color: metrics[i].warn ? AppColors.orange : fg.withOpacity(0.75)),
                  const SizedBox(width: 4),
                  Text(
                    metrics[i].value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: metrics[i].warn ? FontWeight.w800 : FontWeight.w600,
                      color: metrics[i].warn ? AppColors.orange : fg,
                    ),
                  ),
                ],
              ]),
            ),
          ),
          if (showAccruing) ...[
            const SizedBox(width: 8),
            roomy ? pill : Flexible(child: pill),
          ],
        ]);
      }),
    );
  }
}
