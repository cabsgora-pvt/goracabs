import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "Your driver has been waiting 2:05" — shown to the rider once the driver is at
// the pickup point.
//
// Display only; it charges nothing. Pickup waiting charges are one of the
// cancellation-policy decisions still open, and a rider must never be shown
// money accruing that nothing actually bills.
//
// Same rules as the driver's timer:
//  * rebuilds only itself each second — ticking the whole ride screen would
//    rebuild the map and re-send its markers every second;
//  * anchors once, from a SERVER-computed elapsed value, so neither phone's
//    clock enters into it and the 3-second status poll never resets it.
// ─────────────────────────────────────────────────────────────────────────────

class DriverWaitingTimer extends StatefulWidget {
  /// Seconds the driver had already waited when this first appeared.
  final int seedSeconds;

  /// After this long the rider is gently prompted to head out.
  final Duration nudgeAfter;

  const DriverWaitingTimer({
    super.key,
    this.seedSeconds = 0,
    this.nudgeAfter = const Duration(minutes: 3),
  });

  @override
  State<DriverWaitingTimer> createState() => _DriverWaitingTimerState();
}

class _DriverWaitingTimerState extends State<DriverWaitingTimer> {
  late final int _seed;
  // Monotonic: wall-clock time can jump on a clock sync or timezone change.
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _seed = widget.seedSeconds < 0 ? 0 : widget.seedSeconds;
    _clock.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = Duration(seconds: _seed) + _clock.elapsed;
    final nudge = elapsed >= widget.nudgeAfter;
    final color = nudge ? Colors.orange[800]! : AppTheme.primaryBlue;
    final mm = elapsed.inMinutes;
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Semantics(
      // One announcement a minute is informative; one a second is noise.
      label: 'Your driver has been waiting $mm minutes',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(children: [
          Icon(nudge ? Icons.directions_walk_rounded : Icons.hourglass_bottom_rounded,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nudge ? 'Please head to your pickup point' : 'Your driver is waiting',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$mm:$ss',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: color,
              // Tabular figures so the digits do not shuffle sideways each second.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
    );
  }
}
