import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Swipe to confirm a ride state change.
//
// A phone clamped to a windscreen on an Indian road gets tapped by accident.
// "I have Arrived" was a single tap — a misfire tells the rider their driver is
// outside when they are not — and "End Ride" was tap-then-tap-a-dialog, which a
// bump can still complete. Ride-hailing driver apps use a slide for exactly
// these transitions: it is one deliberate gesture, it cannot be triggered by a
// brush, and it is faster than tap-plus-dialog when intended.
//
// Accessibility is not optional here. A screen reader cannot perform a drag, so
// a swipe-only control would lock TalkBack users out of ending a trip. The
// control exposes a semantic tap action, which TalkBack/VoiceOver trigger with
// a double tap, and announces the outcome.
// ─────────────────────────────────────────────────────────────────────────────

enum SwipeTone { primary, danger, success }

class SwipeToConfirm extends StatefulWidget {
  /// What happens when confirmed, stated as an action: "Swipe to end ride".
  final String label;

  /// Called once the knob crosses the threshold (or on accessible activation).
  /// May be async; the control shows progress until it completes.
  final Future<void> Function() onConfirm;

  final SwipeTone tone;
  final IconData icon;

  /// Disables the control, e.g. while a previous request is still in flight.
  final bool enabled;

  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.tone = SwipeTone.primary,
    this.icon = Icons.arrow_forward_rounded,
    this.enabled = true,
  });

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _height = 58;
  static const double _knob = 50;
  static const double _inset = 4;
  // How far along the track counts as a deliberate swipe. High enough that a
  // partial brush never commits, low enough not to demand pixel-perfect aim.
  static const double _threshold = 0.85;

  // Created eagerly in initState, NOT as a lazy `late final` initialiser. A lazy
  // controller on a control that is shown but never swiped is first touched in
  // dispose(), which then constructs a ticker while the element is being
  // unmounted — an ancestor lookup on a deactivated element, which throws.
  late final AnimationController _anim;

  double _dx = 0;       // current knob offset, pixels
  double _maxDx = 0;    // travel available on this track width
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.tone) {
    SwipeTone.danger => AppColors.red,
    SwipeTone.success => AppColors.green,
    SwipeTone.primary => AppColors.primary,
  };

  bool get _active => widget.enabled && !_busy;

  /// Animates the knob to [target] pixels.
  Future<void> _animateTo(double target) async {
    final from = _dx;
    _anim.reset();
    final tween = Tween<double>(begin: from, end: target)
        .chain(CurveTween(curve: Curves.easeOutCubic));
    void tick() { if (mounted) setState(() => _dx = tween.evaluate(_anim)); }
    _anim.addListener(tick);
    try {
      await _anim.forward();
    } finally {
      _anim.removeListener(tick);
    }
  }

  Future<void> _commit() async {
    if (!_active) return;
    setState(() => _busy = true);
    // A physical confirmation that the gesture registered, felt through a
    // windscreen mount without looking.
    HapticFeedback.mediumImpact();
    await _animateTo(_maxDx);
    try {
      await widget.onConfirm();
    } finally {
      // The action may keep this screen open (a failed request, or a flow that
      // returns here), so the control resets rather than staying jammed at the
      // end of its track.
      if (mounted) {
        setState(() => _busy = false);
        await _animateTo(0);
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_active) return;
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _maxDx));
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_active) return;
    // A fast flick in the right direction commits even if the finger lifted a
    // little early; that is how the gesture naturally ends when done quickly.
    final flicked = d.velocity.pixelsPerSecond.dx > 900 && _dx > _maxDx * 0.5;
    if (_maxDx > 0 && (_dx / _maxDx >= _threshold || flicked)) {
      _commit();
    } else {
      HapticFeedback.selectionClick();
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _maxDx = (constraints.maxWidth - _knob - _inset * 2).clamp(0.0, double.infinity);
      final progress = _maxDx == 0 ? 0.0 : (_dx / _maxDx).clamp(0.0, 1.0);
      final color = _active ? _color : _color.withOpacity(0.45);

      return Semantics(
        // Its own node. Without this the button merges into its parent's
        // semantics, and the tap action lands on the wrong node entirely.
        container: true,
        button: true,
        enabled: _active,
        label: widget.label,
        hint: 'Double tap to confirm',
        // Screen readers cannot drag; this is their way to trigger it.
        onTap: _active
            ? () {
                SemanticsService.announce('${widget.label}, confirmed', TextDirection.ltr);
                _commit();
              }
            : null,
        excludeSemantics: true,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Stack(alignment: Alignment.centerLeft, children: [
            // Label fades as the knob covers it, so the text never sits under
            // the thumb looking cut off.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: _knob + _inset * 2, right: 16),
                child: Center(
                  child: Opacity(
                    opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: _inset + _dx,
              child: GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                  ),
                  child: _busy
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: _color),
                        )
                      : Icon(widget.icon, color: _color, size: 26),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}
