import 'package:flutter/material.dart';
import 'cap_tokens.dart';

/// White app bar with a bold, left-aligned black title and a hairline under it
/// — the Uber/Rapido look used by every inner screen.
PreferredSizeWidget capAppBar(
  String title, {
  List<Widget>? actions,
  bool showBack = true,
  VoidCallback? onBack,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    backgroundColor: Cap.surface,
    foregroundColor: Cap.ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    // Default spacing: 16 from the edge with no back button (a tab such as
    // Earnings), the standard gap after one. A fixed 0 here put a tab's title
    // flush against the screen edge.
    titleSpacing: null,
    titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Cap.ink, letterSpacing: -0.2),
    iconTheme: IconThemeData(color: Cap.ink),
    actionsIconTheme: IconThemeData(color: Cap.ink),
    automaticallyImplyLeading: showBack,
    leading: showBack && onBack != null
        ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack)
        : null,
    actions: actions,
    bottom: bottom ??
        PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Cap.divider),
        ),
  );
}

/// Big bold title with a grey subtitle — the top of every form/step page.
class CapHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double size;
  final TextAlign align;
  const CapHeading(this.title, {super.key, this.subtitle, this.size = 26, this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(title, textAlign: align, style: Cap.title(size: size)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: align, style: Cap.caption(size: 14.5)),
          ],
        ],
      );
}

/// "Step 2 of 5 · Vehicle" with a segmented progress bar — the registration
/// checklist shown on top of every registration step page.
class CapStepper extends StatelessWidget {
  /// 1-based.
  final int step;
  final int total;
  final String label;
  const CapStepper({super.key, required this.step, required this.total, required this.label});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Step $step of $total', style: Cap.body(size: 12.5, weight: FontWeight.w800, color: Cap.accent)),
          const SizedBox(width: 6),
          Flexible(
            child: Text('· $label',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12.5)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            total,
            (i) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  color: i < step ? Cap.accent : Cap.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ]);
}

/// The registration checklist, in order. Used by [CapStepper] on each page.
class CapRegSteps {
  CapRegSteps._();
  static const total = 5;
  static const personal = 1;
  static const face = 2;
  static const vehicle = 3;
  static const documents = 4;
  static const bank = 5;
}

/// Small bold label above a field.
class CapLabel extends StatelessWidget {
  final String text;
  final bool required;
  const CapLabel(this.text, {super.key, this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: Cap.red)),
        ]), style: Cap.body(size: 13.5, weight: FontWeight.w700)),
      );
}

/// Label + field, with standard spacing under it.
class CapField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  final double gap;
  const CapField({super.key, required this.label, required this.child, this.required = false, this.gap = 18});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CapLabel(label, required: required),
          child,
        ]),
      );
}

enum CapTone { info, success, warning, danger, neutral }

Color capToneColor(CapTone t) => switch (t) {
      CapTone.info => Cap.accent,
      CapTone.success => Cap.green,
      CapTone.warning => Cap.orange,
      CapTone.danger => Cap.red,
      CapTone.neutral => Cap.muted,
    };

/// Tinted guidance / warning banner.
class CapBanner extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String text;
  final CapTone tone;
  final VoidCallback? onTap;
  final Widget? trailing;
  const CapBanner({
    super.key,
    required this.icon,
    required this.text,
    this.title,
    this.tone = CapTone.info,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = capToneColor(tone);
    return Material(
      color: c.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (title != null) ...[
                  Text(title!, style: Cap.body(size: 14, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                ],
                Text(text, style: Cap.caption(size: 12.8, color: title == null ? Cap.ink : null)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// Large soft circle with an icon — the "illustration" on status screens.
class CapIllustration extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const CapIllustration({super.key, required this.icon, this.color, this.size = 112});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Cap.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.10)),
      child: Center(
        child: Container(
          width: size * 0.66,
          height: size * 0.66,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.16)),
          child: Icon(icon, size: size * 0.36, color: c),
        ),
      ),
    );
  }
}

/// Friendly empty state.
class CapEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const CapEmpty({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CapIllustration(icon: icon, color: Cap.muted, size: 96),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: Cap.title(size: 18)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: Cap.caption(size: 13.5)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

/// White card with a hairline border (no heavy shadow).
class CapCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  const CapCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Cap.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Cap.radius),
          side: BorderSide(color: borderColor ?? Cap.divider, width: borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// Light-grey rounded tile.
class CapTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  const CapTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.onTap,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Cap.tile,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// The small grey drag handle at the top of a sheet.
class CapSheetHandle extends StatelessWidget {
  const CapSheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: Cap.divider, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

/// Section title used inside lists and sheets.
class CapSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const CapSectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.title(size: 16.5))),
          if (trailing != null) trailing!,
        ]),
      );
}
