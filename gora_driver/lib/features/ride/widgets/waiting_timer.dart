import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// How long the driver has been waiting at pickup.
//
// Display only. It charges nothing: pickup waiting charges are one of the
// cancellation-policy decisions still to be made, and showing money accruing
// that nothing actually bills would mislead the driver.
//
// Two properties matter more than the visuals:
//
//  * It rebuilds only ITSELF each second. Ticking the whole ride page instead
//    would rebuild the map widget every second and re-send every marker and
//    polyline across the platform channel.
//
//  * It anchors ONCE, when it first appears, and ignores later seeds. The ride
//    screen swaps states while the driver waits (arrived -> wrong OTP -> retry);
//    re-anchoring on each of those would reset the clock back to zero.
// ─────────────────────────────────────────────────────────────────────────────

class WaitingTimer extends StatefulWidget {
  /// Seconds already waited when this first appears — server-computed, so the
  /// phone's clock never enters into it. 0 on a fresh arrival.
  final int seedSeconds;

  /// After this long, the driver is prompted that they may contact the rider.
  final Duration nudgeAfter;

  final VoidCallback? onCallRider;

  const WaitingTimer({
    super.key,
    this.seedSeconds = 0,
    this.nudgeAfter = const Duration(minutes: 5),
    this.onCallRider,
  });

  @override
  State<WaitingTimer> createState() => _WaitingTimerState();
}

class _WaitingTimerState extends State<WaitingTimer> {
  late final int _seed;
  // A monotonic stopwatch, not DateTime.now(): wall-clock time can jump when the
  // phone syncs its clock or changes timezone mid-wait; elapsed time cannot.
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

  Duration get _elapsed => Duration(seconds: _seed) + _clock.elapsed;

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsed;
    final nudge = elapsed >= widget.nudgeAfter;
    final color = nudge ? AppColors.orange : AppColors.primary;

    return Semantics(
      liveRegion: false, // a per-second announcement would flood a screen reader
      label: 'Waiting for rider for ${elapsed.inMinutes} minutes',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_bottom_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                nudge ? 'Rider has not come out yet' : 'Waiting for rider',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
              ),
              if (nudge && widget.onCallRider != null)
                Text('You can call them to check',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ]),
          ),
          const SizedBox(width: 8),
          // Tabular figures, so the digits do not jitter sideways as they change.
          Text(
            _fmt(elapsed),
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (nudge && widget.onCallRider != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Call rider',
              onPressed: widget.onCallRider,
              icon: const Icon(Icons.call, color: AppColors.green),
            ),
          ],
        ]),
      ),
    );
  }
}
