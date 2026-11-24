import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../widgets/captain_ui/captain_ui.dart';
import 'reg_motion.dart';
import 'reg_ui.dart';

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
    return RegHeroPage(
      hero: RegStatusHero(
        badge: RegStatusBadge(success: justSubmitted, onDark: true),
        title: title,
        subtitle: subtitle,
        footer: RegEntrance(index: 3, child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Reduced motion: a still clock instead of a spinner.
              if (regReduceMotion(context))
                const Icon(Icons.schedule_rounded, size: 14, color: Colors.white)
              else
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Waiting for admin approval…',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        )),
      ),
      sheetChildren: [
        RegEntrance(index: 4, child: Text('What happens next', style: Cap.title(size: 17))),
        const SizedBox(height: 14),
        // The timeline builds up one step at a time.
        const RegEntrance(index: 5, child: _NextStep(icon: Icons.fact_check_outlined, done: true,
            title: 'Application submitted', text: 'Your details and documents are with us.')),
        const RegEntrance(index: 6, child: _NextStep(icon: Icons.manage_search_rounded,
            title: 'Document verification', text: 'Our team checks your documents and selfie.')),
        const RegEntrance(index: 7, child: _NextStep(icon: Icons.notifications_active_outlined, last: true,
            title: 'You get approved', text: 'This screen opens Home on its own once you are approved.')),
        const SizedBox(height: 22),
        RegEntrance(index: 8, child: RegPressScale(child: CapButton(
          label: 'Contact support',
          icon: Icons.support_agent_rounded,
          tone: CapButtonTone.secondary,
          onPressed: () => _support(context),
        ))),
      ],
    );
  }
}

/// Centred status header for the hero: [badge], white title and subtitle,
/// and an optional [footer] (e.g. a "waiting" pill).
class RegStatusHero extends StatelessWidget {
  final Widget badge;
  final String title;
  final String? subtitle;
  final Widget? footer;
  const RegStatusHero({super.key, required this.badge, required this.title, this.subtitle, this.footer});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: badge),
          const SizedBox(height: 10),
          RegEntrance(
            index: 2,
            child: Column(children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
              ],
            ]),
          ),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ]),
      );
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

/// The big status mark on top of the under-review screens.
///
/// [success] (just submitted): a green disc springs in, a check mark draws
/// itself across it, then soft rings keep pulsing outwards. Otherwise
/// (pending): an orange hourglass springs in and turns over, with the same
/// gentle pulse. With reduced motion it is drawn finished and still — no
/// controller runs at all.
class RegStatusBadge extends StatefulWidget {
  final bool success;
  final double size;
  /// Drawn on the brand-blue hero: white halo and rings.
  final bool onDark;
  const RegStatusBadge({super.key, required this.success, this.size = 112, this.onDark = false});

  @override
  State<RegStatusBadge> createState() => _RegStatusBadgeState();
}

class _RegStatusBadgeState extends State<RegStatusBadge> with TickerProviderStateMixin {
  AnimationController? _intro;
  AnimationController? _pulse;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    if (regReduceMotion(context)) return;
    final pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    final intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) pulse.repeat();
    });
    _pulse = pulse;
    _intro = intro..forward();
  }

  @override
  void dispose() {
    _intro?.dispose();
    _pulse?.dispose();
    super.dispose();
  }

  Widget _frame(double pop, double draw, double? ring) {
    final c = widget.success ? Cap.green : Cap.orange;
    final halo = widget.onDark ? Colors.white : c;
    final size = widget.size;
    return SizedBox(
      width: size * 1.3,
      height: size * 1.3,
      child: Stack(alignment: Alignment.center, children: [
        // Pulse: two rings half a beat apart, growing and fading out.
        if (ring != null)
          for (final phase in const [0.0, 0.5])
            Opacity(
              opacity: (1 - (ring + phase) % 1.0) * 0.35,
              child: Container(
                width: size * (0.8 + 0.5 * ((ring + phase) % 1.0)),
                height: size * (0.8 + 0.5 * ((ring + phase) % 1.0)),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: halo, width: 2)),
              ),
            ),
        Transform.scale(
          scale: pop,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: halo.withValues(alpha: widget.onDark ? 0.14 : 0.10)),
            alignment: Alignment.center,
            child: Container(
              width: size * 0.66,
              height: size * 0.66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.success ? c : (widget.onDark ? Colors.white : c.withValues(alpha: 0.16)),
                boxShadow: widget.success
                    ? [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))]
                    : null,
              ),
              alignment: Alignment.center,
              child: widget.success
                  ? CustomPaint(
                      key: const ValueKey('status_check'),
                      size: Size.square(size * 0.34),
                      painter: _CheckPainter(progress: draw, color: Colors.white),
                    )
                  : Transform.rotate(
                      angle: (1 - draw) * math.pi,
                      child: Icon(Icons.hourglass_top_rounded, size: size * 0.34, color: c),
                    ),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intro = _intro, pulse = _pulse;
    if (intro == null || pulse == null) return _frame(1, 1, null);
    final pop = CurvedAnimation(parent: intro, curve: const Interval(0, 0.6, curve: Curves.elasticOut));
    final draw = CurvedAnimation(parent: intro, curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: Listenable.merge([intro, pulse]),
      builder: (_, __) => _frame(pop.value, draw.value, pulse.isAnimating ? pulse.value : null),
    );
  }
}

/// A check mark drawn up to [progress] (0..1) of its length.
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.12, h * 0.54)
      ..lineTo(w * 0.40, h * 0.80)
      ..lineTo(w * 0.90, h * 0.24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * p), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.progress != progress || old.color != color;
}
