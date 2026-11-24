import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

// Motion for the registration flow, built only on Flutter's own animation
// APIs. Purely visual: nothing here reads or changes any form value.
//
// Every widget checks [regReduceMotion] — the OS "remove animations" setting
// (MediaQuery.disableAnimations) — and then renders its final state at once,
// with no running controller.

/// True when the driver has asked the OS for less motion.
bool regReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or zero when motion is reduced.
Duration regDuration(BuildContext context, Duration d) => regReduceMotion(context) ? Duration.zero : d;

/// Fade + slight upward slide on first build. [index] staggers siblings:
/// each step starts 70 ms after the previous one (capped, so a long list does
/// not keep the driver waiting).
class RegEntrance extends StatefulWidget {
  final int index;
  final Widget child;
  final double offset;
  const RegEntrance({super.key, this.index = 0, required this.child, this.offset = 18});

  static const _base = 420;
  static const _step = 70;
  static const _maxIndex = 8;

  @override
  State<RegEntrance> createState() => _RegEntranceState();
}

class _RegEntranceState extends State<RegEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _t;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    if (regReduceMotion(context)) return; // final state, no controller at all
    final i = widget.index.clamp(0, RegEntrance._maxIndex);
    final delay = i * RegEntrance._step;
    final total = RegEntrance._base + delay;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: total));
    _ctrl = c;
    _t = CurvedAnimation(parent: c, curve: Interval(delay / total, 1, curve: Curves.easeOutCubic));
    c.forward();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - t.value)), child: child),
      ),
    );
  }
}

/// Shrinks its child slightly while a finger is down — press feedback for
/// primary buttons and selectable cards. Uses a [Listener], so it never takes
/// part in the gesture arena and the child's own onTap behaves as before.
class RegPressScale extends StatefulWidget {
  final Widget child;
  final double pressed;
  const RegPressScale({super.key, required this.child, this.pressed = 0.97});

  @override
  State<RegPressScale> createState() => _RegPressScaleState();
}

class _RegPressScaleState extends State<RegPressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? widget.pressed : 1,
          duration: regDuration(context, const Duration(milliseconds: 110)),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Pops in from nothing with a little overshoot — a check badge appearing.
class RegPopIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const RegPopIn({super.key, required this.child, this.duration = const Duration(milliseconds: 520)});

  @override
  Widget build(BuildContext context) {
    if (regReduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.elasticOut,
      child: child,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
    );
  }
}

/// White rounded card with a soft coloured icon badge and a bold title on
/// top — groups the fields of one form section.
class RegSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? caption;
  final Color? color;
  final List<Widget> children;
  const RegSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Cap.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
      decoration: BoxDecoration(
        color: Cap.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dark ? Cap.divider : const Color(0xFFE6EAF3)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.withValues(alpha: 0.18), c.withValues(alpha: 0.07)],
              ),
            ),
            child: Icon(icon, size: 20, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Cap.body(size: 15.5, weight: FontWeight.w800)),
              if (caption != null) ...[
                const SizedBox(height: 1),
                Text(caption!, style: Cap.caption(size: 12)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}
