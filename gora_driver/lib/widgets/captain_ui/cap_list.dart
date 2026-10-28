import 'package:flutter/material.dart';
import 'cap_tokens.dart';

/// Small coloured pill — "PARCEL", "Fragile", "Paid online".
class CapChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;
  final double fontSize;
  const CapChip(this.label, {super.key, required this.color, this.icon, this.solid = false, this.fontSize = 11.5});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: solid ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: solid ? Colors.white : color)),
          ),
        ]),
      );
}

enum CapStatus { pending, done, review, rejected, expired }

/// Status chip for checklist / document rows.
class CapStatusChip extends StatelessWidget {
  final CapStatus status;
  final String? label;
  const CapStatusChip(this.status, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final (String text, Color c, IconData ic) = switch (status) {
      CapStatus.pending => ('Pending', Cap.muted, Icons.radio_button_unchecked_rounded),
      CapStatus.done => ('Done', Cap.green, Icons.check_circle_rounded),
      CapStatus.review => ('Under review', Cap.orange, Icons.schedule_rounded),
      CapStatus.rejected => ('Rejected', Cap.red, Icons.error_rounded),
      CapStatus.expired => ('Expired', Cap.red, Icons.event_busy_rounded),
    };
    return CapChip(label ?? text, color: c, icon: ic);
  }
}

/// A group of menu rows inside one white rounded card with hairlines between.
class CapMenuGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const CapMenuGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Padding(padding: const EdgeInsets.only(left: 62), child: Container(height: 1, color: Cap.divider)));
      rows.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(title!.toUpperCase(),
              style: Cap.caption(size: 11.5).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ),
      Container(
        decoration: BoxDecoration(
          color: Cap.surface,
          borderRadius: BorderRadius.circular(Cap.radius),
          border: Border.all(color: Cap.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      ),
    ]);
  }
}

/// One row: grey icon tile, label (+ optional sub), chevron.
class CapMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;
  final Color? iconColor;
  const CapMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.onTap,
    this.danger = false,
    this.trailing,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? Cap.red : (iconColor ?? Cap.ink);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: danger ? Cap.red.withValues(alpha: 0.10) : Cap.tile,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cap.body(size: 14.5, weight: FontWeight.w700, color: danger ? Cap.red : null)),
              if (sub != null && sub!.isNotEmpty)
                Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (!danger && onTap != null) Icon(Icons.chevron_right_rounded, color: Cap.muted, size: 22),
        ]),
      ),
    );
  }
}

/// Summary card with a big number — "₹ 1,240 · Today".
class CapStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;
  final bool compact;
  const CapStatCard({super.key, required this.label, required this.value, this.icon, this.accent, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = accent ?? Cap.accent;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Cap.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cap.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: c),
          const SizedBox(height: 8),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: Cap.title(size: compact ? 17 : 20)),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
      ]),
    );
  }
}

/// Grey pill segmented control — Today / Week / Month.
class CapSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const CapSegmented({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: List.generate(labels.length, (i) {
            final sel = i == index;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? Cap.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: sel ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)] : null,
                  ),
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Cap.body(size: 13.5, weight: sel ? FontWeight.w800 : FontWeight.w600, color: sel ? null : Cap.muted)),
                ),
              ),
            );
          }),
        ),
      );
}

/// Circular photo falling back to the person's initial.
class CapAvatar extends StatelessWidget {
  final String name;
  final String url;
  final double radius;
  final Color? background;
  const CapAvatar({super.key, required this.name, this.url = '', this.radius = 24, this.background});

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isNotEmpty ? t[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: background ?? Cap.tile,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(initial, style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w800, color: Cap.accent))
          : null,
    );
  }
}

/// Pickup → drop with an Uber-style dot / line / square connector. Each leg
/// can carry a bold heading (e.g. "2.4 km · 6 min").
class CapRoute extends StatelessWidget {
  final String pickup;
  final String drop;
  final String pickupHeading;
  final String dropHeading;
  final int maxLines;
  const CapRoute({
    super.key,
    required this.pickup,
    this.drop = '',
    this.pickupHeading = '',
    this.dropHeading = '',
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final hasDrop = drop.trim().isNotEmpty;
    Widget marker(bool square) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: square ? Cap.ink : Cap.green,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(1.5) : null,
          ),
        );
    Widget leg(String heading, String address, bool square) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading.isNotEmpty)
              Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 15.5, weight: FontWeight.w800)),
            Text(address,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: Cap.body(size: 13, weight: FontWeight.w500, color: heading.isEmpty ? null : Cap.muted)),
          ],
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 14,
          child: Column(children: [
            const SizedBox(height: 5),
            marker(false),
            if (hasDrop) ...[
              Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: Cap.divider)),
              marker(true),
              const SizedBox(height: 5),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leg(pickupHeading, pickup, false),
            if (hasDrop) ...[
              const SizedBox(height: 14),
              leg(dropHeading, drop, true),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Dashed rounded rectangle — the "upload here" slot.
class CapDashedBox extends StatelessWidget {
  final Widget child;
  final double height;
  final Color? color;
  final VoidCallback? onTap;
  const CapDashedBox({super.key, required this.child, this.height = 160, this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashPainter(color ?? Cap.muted.withValues(alpha: 0.6)),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(14)),
            child: child,
          ),
        ),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// Thin full-width hairline.
class CapDivider extends StatelessWidget {
  final double vertical;
  const CapDivider({super.key, this.vertical = 0});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.symmetric(vertical: vertical), child: Container(height: 1, color: Cap.divider));
}
