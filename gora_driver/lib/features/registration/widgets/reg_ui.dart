import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import 'reg_motion.dart';

// Branded building blocks for the driver registration flow (Uber Driver /
// Rapido Captain onboarding look): a deep brand-blue hero with a numbered
// stepper, a white sheet that pulls up over it, tinted fields and a gradient
// CTA. Purely visual — nothing here reads or changes a form value.

/// Registration colours, all derived from the Gora brand in [AppColors].
class RegPalette {
  RegPalette._();

  /// Top of the hero gradient (also the status-bar strip).
  static const heroTop = Color(0xFF06134A);
  static const heroMid = Color(0xFF0A2C9E);
  static const heroBottom = AppColors.primary;

  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [heroTop, heroMid, heroBottom],
    stops: [0, 0.55, 1],
  );

  /// The primary CTA.
  static const LinearGradient cta = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, Color(0xFF2E62F0)],
  );

  static const LinearGradient ctaAction = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1749DD), AppColors.primary],
  );

  /// Section / category accents.
  static const blue = AppColors.primary;
  static const orange = AppColors.accent;
  static const green = Color(0xFF16A34A);
  static const purple = Color(0xFF7C3AED);
  static const teal = Color(0xFF0D9488);
  static const pink = Color(0xFFDB2777);

  /// Light field fill / hairline (dark mode falls back to the app tokens).
  static Color get field => AppColors.dark ? Cap.tile : const Color(0xFFF5F7FC);
  static Color get hairline => AppColors.dark ? Cap.divider : const Color(0xFFE4E9F2);
}

/// Short stepper labels, in [CapRegSteps] order.
const kRegStepLabels = ['Personal', 'Selfie', 'Vehicle', 'Documents'];

// ─────────────────────────────────────────────────────────────────────────────
// Hero + sheet page shell
// ─────────────────────────────────────────────────────────────────────────────

/// Deep-blue gradient with two soft decorative circles.
class RegHeroBackground extends StatelessWidget {
  final Widget child;
  const RegHeroBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: RegPalette.hero),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            right: -70,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -40,
            child: IgnorePointer(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.10)),
              ),
            ),
          ),
          child,
        ]),
      );
}

/// Page shell: the [hero] on the brand gradient, then a white [sheet] with
/// large rounded top corners pulled up over the hero, then (optionally) a
/// fixed [bottom] CTA bar.
///
/// The CTA bar lives in the body, not in bottomNavigationBar, so it rides up
/// with the keyboard instead of hiding behind it.
class RegHeroPage extends StatelessWidget {
  final Widget hero;
  final List<Widget> sheetChildren;
  final Widget? bottom;
  final Widget? bottomTop;
  final EdgeInsetsGeometry sheetPadding;

  /// How far the sheet pulls up over the hero.
  static const overlap = 26.0;

  const RegHeroPage({
    super.key,
    required this.hero,
    required this.sheetChildren,
    this.bottom,
    this.bottomTop,
    this.sheetPadding = const EdgeInsets.fromLTRB(16, 10, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Cap.surface,
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    RegHeroBackground(
                      child: Padding(
                        padding: EdgeInsets.only(top: top, bottom: overlap),
                        child: hero,
                      ),
                    ),
                    // Paint-only shift: the sheet overlaps the hero's bottom
                    // edge; what it leaves below is the same white surface.
                    Transform.translate(
                      offset: const Offset(0, -overlap),
                      child: RegSheet(padding: sheetPadding, children: sheetChildren),
                    ),
                  ]),
                ),
              ),
              // Keeps the light status-bar icons readable once the hero has
              // scrolled away.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top,
                child: const IgnorePointer(child: ColoredBox(color: RegPalette.heroTop)),
              ),
            ]),
          ),
          if (bottom != null) RegBottomBar(top: bottomTop, child: bottom!),
        ]),
      ),
    );
  }
}

/// White sheet with large rounded top corners and a soft upward shadow.
class RegSheet extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  const RegSheet({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 24)});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('reg_sheet'),
        padding: padding,
        decoration: BoxDecoration(
          color: Cap.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, -6)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(color: RegPalette.hairline, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ]),
      );
}

/// Fixed bottom bar for the page CTA: white, soft top shadow, safe-area aware.
class RegBottomBar extends StatelessWidget {
  final Widget child;
  final Widget? top;
  const RegBottomBar({super.key, required this.child, this.top});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Cap.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (top != null) ...[top!, const SizedBox(height: 8)],
              child,
            ]),
          ),
        ),
      );
}

/// Round translucent back button for the hero.
class RegHeroBack extends StatelessWidget {
  final VoidCallback onPressed;
  const RegHeroBack({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Back',
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 21),
            ),
          ),
        ),
      );
}

/// "Step 2 of 4" — small translucent pill.
class RegStepPill extends StatelessWidget {
  final int step;
  final int total;
  const RegStepPill({super.key, required this.step, this.total = CapRegSteps.total});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text('Step $step of $total',
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stepper
// ─────────────────────────────────────────────────────────────────────────────

enum RegStepState { done, current, upcoming }

/// The state of step [n] (1-based) when the driver is on [current].
RegStepState regStepStateOf(int n, int current) =>
    n < current ? RegStepState.done : (n == current ? RegStepState.current : RegStepState.upcoming);

/// One numbered circle of [RegStepper]. Done = white disc with a check,
/// current = orange disc with a soft glow, upcoming = muted outline.
class RegStepDot extends StatelessWidget {
  final int number;
  final RegStepState state;
  final double size;
  const RegStepDot({super.key, required this.number, required this.state, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color border, Color fg) = switch (state) {
      RegStepState.done => (Colors.white, Colors.white, AppColors.primary),
      RegStepState.current => (AppColors.accent, Colors.white, Colors.white),
      RegStepState.upcoming => (
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.70)
        ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: state == RegStepState.current ? 2.5 : 1.5),
        boxShadow: state == RegStepState.current
            ? [
                BoxShadow(color: AppColors.accent.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 2),
                BoxShadow(color: Colors.white.withValues(alpha: 0.18), blurRadius: 0, spreadRadius: 5),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: state == RegStepState.done
          ? Icon(Icons.done_rounded, size: size * 0.58, color: fg)
          : Text('$number',
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: fg, fontSize: size * 0.44, fontWeight: FontWeight.w800, height: 1)),
    );
  }
}

/// 4 numbered circles joined by a line, with short labels underneath
/// (Personal · Selfie · Vehicle · Documents). On first build the segment
/// leading into the current step fills in and the current circle pops; with
/// reduced motion both are drawn finished on the first frame.
///
/// Drawn for a dark background (the hero, or the camera on the selfie step).
class RegStepper extends StatelessWidget {
  /// 1-based current step.
  final int step;
  final double dotSize;
  const RegStepper({super.key, required this.step, this.dotSize = 30});

  @override
  Widget build(BuildContext context) {
    final reduce = regReduceMotion(context);
    final total = kRegStepLabels.length;
    return Semantics(
      label: 'Registration step $step of $total, ${kRegStepLabels[(step - 1).clamp(0, total - 1)]}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
        builder: (context, t, _) {
          final fill = Curves.easeInOutCubic.transform((t / 0.65).clamp(0.0, 1.0));
          final pop = Curves.easeOutBack.transform(((t - 0.5) / 0.5).clamp(0.0, 1.0));
          return LayoutBuilder(builder: (context, box) {
            final col = box.maxWidth / total;
            return Stack(children: [
              // Connector line, behind the circles, centre to centre.
              Positioned(
                left: col / 2,
                right: col / 2,
                top: dotSize / 2 - 1.5,
                height: 3,
                child: Row(children: [
                  for (var i = 1; i < total; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          key: ValueKey('reg_step_line_$i'),
                          alignment: Alignment.centerLeft,
                          widthFactor: i + 1 < step ? 1 : (i + 1 == step ? fill : 0),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var n = 1; n <= total; n++)
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Transform.scale(
                        scale: n == step ? 0.6 + 0.4 * pop : 1,
                        child: RegStepDot(
                          key: ValueKey('reg_step_dot_$n'),
                          number: n,
                          state: regStepStateOf(n, step),
                          size: dotSize,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            kRegStepLabels[n - 1],
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: n == step ? FontWeight.w800 : FontWeight.w600,
                              color: n <= step ? Colors.white : Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ]);
          });
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA
// ─────────────────────────────────────────────────────────────────────────────

/// Full-width 56px CTA: brand gradient, label and a trailing arrow, dips a
/// touch while pressed. Disabled ([onPressed] null) it is plainly grey with its
/// helper label; [dimmed] looks the same but stays tappable (e.g. to explain
/// what is missing).
class RegCta extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool dimmed;
  final IconData trailing;
  final IconData? leading;
  const RegCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.dimmed = false,
    this.trailing = Icons.arrow_forward_rounded,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final active = loading || (onPressed != null && !dimmed);
    final radius = BorderRadius.circular(16);
    final fg = active ? Colors.white : Cap.muted;
    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      child: RegPressScale(
        child: AnimatedContainer(
          duration: regDuration(context, const Duration(milliseconds: 240)),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: active ? RegPalette.cta : null,
            color: active ? null : Cap.tile,
            boxShadow: active
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.32), blurRadius: 16, offset: const Offset(0, 6))]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: loading ? null : onPressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            if (leading != null) ...[Icon(leading, size: 20, color: fg), const SizedBox(width: 8)],
                            Flexible(
                              child: Text(label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: active ? 16.5 : 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: fg,
                                      height: 1.2)),
                            ),
                            if (active) ...[
                              const SizedBox(width: 10),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
                                child: Icon(trailing, size: 17, color: Colors.white),
                              ),
                            ],
                          ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fields
// ─────────────────────────────────────────────────────────────────────────────

/// Tinted circle with an icon — the leading badge inside a field.
class RegFieldIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const RegFieldIcon(this.icon, {super.key, this.color = RegPalette.blue});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10)),
          child: Icon(icon, size: 17, color: AppColors.dark ? AppColors.primaryLight : color),
        ),
      );
}

/// Field decoration: light fill, 14px corners, a tinted icon badge inside on
/// the left, brand-blue border when focused, clear red error text.
InputDecoration regInput({String? hint, IconData? icon, Color iconColor = RegPalette.blue, Widget? suffix}) {
  OutlineInputBorder b(Color c, [double w = 1.2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Cap.muted, fontWeight: FontWeight.w500, fontSize: 14.5),
    filled: true,
    fillColor: RegPalette.field,
    counterText: '',
    prefixIcon: icon == null ? null : RegFieldIcon(icon, color: iconColor),
    prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 44),
    suffixIcon: suffix,
    contentPadding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 4, vertical: 16),
    border: b(RegPalette.hairline),
    enabledBorder: b(RegPalette.hairline),
    disabledBorder: b(RegPalette.hairline),
    focusedBorder: b(Cap.accent, 1.8),
    errorBorder: b(Cap.red),
    focusedErrorBorder: b(Cap.red, 1.8),
    errorStyle: const TextStyle(color: Cap.red, fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.3),
    errorMaxLines: 2,
  );
}

/// Label above a field; the field gets a soft brand glow while it (or
/// anything inside it) has focus.
class RegField extends StatefulWidget {
  final String label;
  final bool required;
  final Widget child;
  final double gap;
  const RegField({super.key, required this.label, required this.child, this.required = false, this.gap = 16});

  @override
  State<RegField> createState() => _RegFieldState();
}

class _RegFieldState extends State<RegField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: widget.gap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: widget.label),
                if (widget.required) const TextSpan(text: ' *', style: TextStyle(color: Cap.red)),
              ]),
              style: Cap.body(size: 13, weight: FontWeight.w700, color: _focused ? Cap.accent : Cap.ink),
            ),
          ),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) {
              if (mounted && f != _focused) setState(() => _focused = f);
            },
            child: AnimatedContainer(
              duration: regDuration(context, const Duration(milliseconds: 200)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: _focused
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 4))]
                    : const [],
              ),
              child: widget.child,
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Badges, rings, drop zones
// ─────────────────────────────────────────────────────────────────────────────

/// Soft coloured rounded-square icon badge.
class RegIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const RegIconBadge({super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.07)],
          ),
        ),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

/// Circular progress ring with "N/M" in the middle — animates from its old
/// value to the new one (from 0 on first build; drawn finished with reduced
/// motion). Drawn for the dark hero.
class RegProgressRing extends StatelessWidget {
  final int done;
  final int total;
  final double size;
  const RegProgressRing({super.key, required this.done, required this.total, this.size = 62});

  @override
  Widget build(BuildContext context) {
    final reduce = regReduceMotion(context);
    final value = total == 0 ? 1.0 : done / total;
    final complete = total == 0 || done >= total;
    final color = complete ? const Color(0xFF22C55E) : AppColors.accent;
    return Semantics(
      label: '$done of $total required documents uploaded',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? value : 0, end: value),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(progress: v, color: color, track: Colors.white.withValues(alpha: 0.18)),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$done/$total',
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * p,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Large rounded drop-zone with a dashed brand border — an empty photo slot.
class RegDropZone extends StatelessWidget {
  final Widget child;
  final double height;
  final VoidCallback? onTap;
  const RegDropZone({super.key, required this.child, this.height = 168, this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(color: Cap.accent.withValues(alpha: 0.45), radius: 18),
      child: Material(
        color: Cap.accent.withValues(alpha: 0.04),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(height: height, width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.8), Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) => old.color != color || old.radius != radius;
}
