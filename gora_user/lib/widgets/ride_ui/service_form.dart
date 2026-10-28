import 'package:flutter/material.dart';

import '../../utils/call_util.dart';
import 'driver_card.dart';
import 'ride_actions.dart';
import 'ride_sheet.dart';
import 'ride_tokens.dart';
import 'route_summary.dart';
import 'centre_pin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Form building blocks for the service booking screens (parcel, rental,
// intercity, hire a driver, inquiry) in the same Uber/Ola language as the taxi
// flow: big bold titles, light-grey rounded tiles, one strong navy accent.
//
// Every widget here only lays out what the caller passes in — none of them
// fetches, prices or validates anything.
// ─────────────────────────────────────────────────────────────────────────────

/// The fixed top row of a full-page service screen: just the back arrow, so the
/// big [ServiceTitle] can scroll away with the content (Uber style).
class ServiceBackBar extends StatelessWidget {
  final VoidCallback? onBack;
  final Widget? trailing;
  const ServiceBackBar({super.key, this.onBack, this.trailing});

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, color: RideUi.ink(context)),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            const Spacer(),
            ?trailing,
          ]),
        ),
      );
}

/// Big bold page title with a short grey subtitle.
class ServiceTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const ServiceTitle({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.title(context, size: 26)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 14)),
          ],
        ]),
      );
}

/// Back arrow + title together, for a screen whose content does not scroll.
///
///   (←)
///   Intercity
///   Outstation trips — one way or round trip
class ServiceHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  const ServiceHeader({super.key, required this.title, this.subtitle, this.onBack, this.trailing});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ServiceBackBar(onBack: onBack, trailing: trailing),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ServiceTitle(title: title, subtitle: subtitle),
        ),
      ]);
}

/// Bold 18px section title with the standard spacing above and below.
class ServiceSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double top;
  const ServiceSection(this.title, {super.key, this.subtitle, this.trailing, this.top = 24});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          RideSectionTitle(title, trailing: trailing),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: RideUi.caption(context, size: 13)),
          ],
        ]),
      );
}

/// Which marker a row of a [RouteInputBlock] carries.
enum RouteMarkerKind { pickup, drop, stop }

/// One row of a [RouteInputBlock]: the marker on the left, any field or text in
/// the middle and an optional action (e.g. "pick on map") on the right.
class RouteFieldRow extends StatelessWidget {
  final RouteMarkerKind marker;
  final Widget child;
  final Widget? trailing;
  const RouteFieldRow({super.key, required this.marker, required this.child, this.trailing});

  static const double minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final Widget dot = switch (marker) {
      RouteMarkerKind.pickup => const RouteDot(),
      RouteMarkerKind.drop => const RouteSquare(),
      RouteMarkerKind.stop => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RideUi.ink(context), width: 2)),
        ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Row(children: [
        SizedBox(width: 14, child: Center(child: dot)),
        const SizedBox(width: 12),
        Expanded(child: child),
        if (trailing != null) trailing! else const SizedBox(width: 12),
      ]),
    );
  }
}

/// The stacked pickup → drop block of the taxi search, as one grey rounded tile
/// with the dot–line–square connector. Rows are separated by hairlines.
class RouteInputBlock extends StatelessWidget {
  final List<RouteFieldRow> rows;
  final Widget? footer;
  const RouteInputBlock({super.key, required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(Padding(padding: const EdgeInsets.only(left: 26), child: Container(height: 1, color: RideUi.divider(context))));
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(RideUi.radius)),
      padding: const EdgeInsets.only(left: 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(children: [
          // The connector runs from the first marker's centre to the last one's.
          if (rows.length > 1)
            Positioned(
              left: 6,
              top: RouteFieldRow.minHeight / 2 + 7,
              bottom: RouteFieldRow.minHeight / 2 + 7,
              child: Container(width: 2, color: RideUi.muted(context).withValues(alpha: 0.45)),
            ),
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ]),
        if (footer != null) ...[
          Container(height: 1, color: RideUi.divider(context)),
          footer!,
        ],
      ]),
    );
  }
}

/// Small "map" action used at the end of a [RouteFieldRow].
class MapPickAction extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const MapPickAction({super.key, required this.onTap, this.tooltip = 'Pick on map'});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(Icons.map_outlined, size: 20, color: RideUi.muted(context)),
      );
}

/// A place suggestion under a location field: round grey pin + main / secondary
/// text — the rows of the taxi search screen. A [ListTile] on purpose, so the
/// row keeps its standard semantics and tap target.
class PlaceSuggestionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const PlaceSuggestionTile({super.key, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
          child: Icon(Icons.location_on, size: 18, color: RideUi.ink(context)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14, weight: FontWeight.w700)),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12)),
        onTap: onTap,
      );
}

/// One option of a [ChoiceSegment].
class ChoiceOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  const ChoiceOption(this.value, this.label, {this.subtitle, this.icon});
}

/// Side-by-side grey tiles where exactly one is chosen — Send / Receive,
/// One way / Round trip, Manual / Automatic. The chosen tile is navy.
class ChoiceSegment<T> extends StatelessWidget {
  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const ChoiceSegment({super.key, required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      if (i > 0) tiles.add(const SizedBox(width: 10));
      final o = options[i];
      final sel = o.value == selected;
      final fg = sel ? Colors.white : RideUi.ink(context);
      tiles.add(Expanded(
        child: Semantics(
          selected: sel,
          button: true,
          child: Material(
            color: sel ? RideUi.navy : RideUi.tile(context),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(o.value),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: o.subtitle == null ? 13 : 11),
                child: Row(children: [
                  if (o.icon != null) ...[Icon(o.icon, size: 18, color: fg), const SizedBox(width: 8)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: o.subtitle == null && o.icon == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: fg)),
                        if (o.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(o.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: sel ? Colors.white70 : RideUi.muted(context))),
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
  }
}

/// Selectable pill — item types, vehicle categories, package sizes.
class ServiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const ServiceChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : RideUi.ink(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? RideUi.navy : RideUi.tile(context),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tappable grey row for a date / time / schedule value:
///
///   [📅]  Pickup date                 ›
///         Tue, 28 Oct
class PickerPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool placeholder;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final String? trailingText;
  final bool chevron;
  const PickerPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder = false,
    this.onTap,
    this.onClear,
    this.trailingText,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) => RideTile(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Icon(icon, size: 20, color: RideUi.ink(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12)),
              const SizedBox(height: 1),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: placeholder
                      ? RideUi.body(context, size: 14.5, weight: FontWeight.w600).copyWith(color: RideUi.muted(context))
                      : RideUi.body(context, size: 14.5, weight: FontWeight.w700)),
            ]),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Clear',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: Icon(Icons.close, size: 18, color: RideUi.muted(context)),
            )
          else if (trailingText != null)
            Text(trailingText!, style: RideUi.body(context, size: 12.5, weight: FontWeight.w800).copyWith(color: RideUi.accent(context)))
          else if (onTap != null && chevron)
            Icon(Icons.chevron_right, color: RideUi.muted(context)),
        ]),
      );
}

/// Label on the left, a clean − value + pill on the right.
class StepperPill extends StatelessWidget {
  final String label;
  final String? caption;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const StepperPill({super.key, required this.label, this.caption, required this.value, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData ic, VoidCallback? onTap, String tip) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          icon: Icon(ic, size: 20, color: onTap == null ? RideUi.muted(context) : RideUi.ink(context)),
        );
    return RideTile(
      padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14.5, weight: FontWeight.w700)),
            if (caption != null && caption!.isNotEmpty)
              Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(color: RideUi.surface(context), borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            btn(Icons.remove, onMinus, 'Decrease'),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Text(value, textAlign: TextAlign.center, style: RideUi.body(context, size: 17, weight: FontWeight.w800)),
            ),
            btn(Icons.add, onPlus, 'Increase'),
          ]),
        ),
      ]),
    );
  }
}

/// Grey 13px label above a field.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: RideUi.caption(context, size: 13).copyWith(fontWeight: FontWeight.w600)),
      );
}

/// Label above one clean grey field ([RideUi.fieldBox] + [RideUi.bareInput]).
class LabeledField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  const LabeledField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.icon,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.validator,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final style = RideUi.body(context, size: 14.5, weight: FontWeight.w600);
    final deco = RideUi.bareInput(context, hint, vertical: 14);
    final Widget field = validator != null
        ? TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            validator: validator,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onFieldSubmitted: onSubmitted,
            decoration: deco,
            style: style,
          )
        : TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            decoration: deco,
            style: style,
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      FieldLabel(label),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: RideUi.fieldBox(context),
        child: Row(crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          if (icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 14 : 0),
              child: Icon(icon, size: 18, color: RideUi.muted(context)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: field),
        ]),
      ),
    ]);
  }
}

/// Tone of a [NoticeRow]: only the icon takes the colour; the tile stays grey.
enum NoticeTone { neutral, warning, success }

/// Compact grey notice with an icon — replaces the old orange / blue banners.
class NoticeRow extends StatelessWidget {
  final String text;
  final IconData icon;
  final NoticeTone tone;
  const NoticeRow(this.text, {super.key, this.icon = Icons.info_outline, this.tone = NoticeTone.neutral});

  @override
  Widget build(BuildContext context) {
    final c = switch (tone) {
      NoticeTone.warning => const Color(0xFFB45309),
      NoticeTone.success => const Color(0xFF15803D),
      NoticeTone.neutral => RideUi.ink(context),
    };
    return RideTile(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: RideUi.body(context, size: 13, weight: FontWeight.w500).copyWith(height: 1.35))),
      ]),
    );
  }
}

/// One rule / spec line: a small round grey icon and the text.
class InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtitle;
  final Color? iconColor;
  const InfoLine(this.icon, this.text, {super.key, this.subtitle, this.iconColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColor ?? RideUi.ink(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(text, style: RideUi.body(context, size: 13.5, weight: subtitle == null ? FontWeight.w500 : FontWeight.w700).copyWith(height: 1.3)),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: RideUi.caption(context, size: 12)),
            ]),
          ),
        ]),
      );
}

/// A titled list of [InfoLine]s behind a one-tap header, collapsed or open.
class CollapsibleInfo extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;
  const CollapsibleInfo({
    super.key,
    required this.title,
    required this.children,
    this.icon = Icons.info_outline,
    this.initiallyExpanded = false,
  });

  @override
  State<CollapsibleInfo> createState() => _CollapsibleInfoState();
}

class _CollapsibleInfoState extends State<CollapsibleInfo> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RideUi.radius),
          border: Border.all(color: RideUi.divider(context)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(RideUi.radius),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(widget.icon, size: 19, color: RideUi.ink(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14.5, weight: FontWeight.w700)),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: RideUi.muted(context)),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
            ),
        ]),
      );
}

/// Label → value line of a fare breakdown or a booking summary.
class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final IconData? icon;
  const SummaryRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: bold ? 6 : 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 17, color: RideUi.muted(context)), const SizedBox(width: 10)],
          Expanded(
            flex: 3,
            child: Text(label,
                style: bold
                    ? RideUi.body(context, size: 15.5, weight: FontWeight.w800)
                    : RideUi.caption(context, size: 13.5).copyWith(color: RideUi.muted(context))),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(value,
                textAlign: TextAlign.right,
                style: (bold
                        ? RideUi.body(context, size: 16, weight: FontWeight.w800)
                        : RideUi.body(context, size: 13.5, weight: FontWeight.w700))
                    .copyWith(color: valueColor)),
          ),
        ]),
      );
}

/// Grey rounded vehicle tile of a summary: image, name + caption, price.
class SummaryVehicleTile extends StatelessWidget {
  final Widget leading;
  final String name;
  final String? caption;
  final String? price;
  final String? priceCaption;
  const SummaryVehicleTile({super.key, required this.leading, required this.name, this.caption, this.price, this.priceCaption});

  @override
  Widget build(BuildContext context) => RideTile(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            decoration: BoxDecoration(color: RideUi.surface(context), borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(4),
            child: leading,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 16, weight: FontWeight.w800)),
              if (caption != null && caption!.isNotEmpty)
                Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12.5)),
            ]),
          ),
          if (price != null) ...[
            const SizedBox(width: 8),
            // Bounded, so a long caption or price ellipsises instead of
            // pushing the row past a narrow screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (priceCaption != null)
                  Text(priceCaption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 11.5)),
                Text(price!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 19, weight: FontWeight.w900)),
              ]),
            ),
          ],
        ]),
      );
}

/// Pickup → drop of a summary, in a grey tile.
class SummaryRouteTile extends StatelessWidget {
  final String pickup;
  final String? drop;
  final Widget? footer;
  const SummaryRouteTile({super.key, required this.pickup, this.drop, this.footer});

  @override
  Widget build(BuildContext context) => RideTile(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          TripRouteSummary(pickup: pickup, drop: drop, maxLines: 2, fontSize: 14),
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ]),
      );
}

/// Full-bleed map location picker: floating back button, fixed centre pin and a
/// white sheet with the address under the pin and one confirm button.
///
/// The caller owns the [map] (its camera callbacks and reverse geocoding); this
/// only lays it out.
class ServiceMapPicker extends StatelessWidget {
  final Widget map;
  final String title;
  final String address;
  final bool forPickup;
  final VoidCallback onBack;
  final VoidCallback? onConfirm;
  final VoidCallback? onLocate;
  final String confirmLabel;
  const ServiceMapPicker({
    super.key,
    required this.map,
    required this.title,
    required this.address,
    required this.onBack,
    required this.onConfirm,
    this.forPickup = true,
    this.onLocate,
    this.confirmLabel = 'Confirm Location',
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Stack(children: [
        Positioned.fill(child: map),
        const Center(child: IgnorePointer(child: CentrePin())),
        Positioned(
          top: top + 10,
          left: 12,
          child: MapCircleButton(icon: Icons.arrow_back, tooltip: 'Back', onTap: onBack),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            if (onLocate != null)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 12),
                child: MapCircleButton(icon: Icons.my_location, tooltip: 'My location', onTap: onLocate),
              ),
            RideSheetContainer(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SheetHandle(),
                    Text(title, style: RideUi.title(context, size: 20)),
                    const SizedBox(height: 4),
                    Text('Drag the map to move the pin', style: RideUi.caption(context, size: 13)),
                    const SizedBox(height: 12),
                    RideTile(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(children: [
                        SizedBox(width: 14, child: Center(child: forPickup ? const RouteDot() : const RouteSquare())),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            address.isEmpty ? 'Locating address…' : address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: address.isEmpty
                                ? RideUi.caption(context, size: 14)
                                : RideUi.body(context, size: 14, weight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    PrimaryRideButton(label: confirmLabel, onPressed: onConfirm),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A booking's summary page: title + booking id, a "confirmed" line, the
/// caller's sections, and one fixed "Back to Home" button. Leaving the page by
/// any route runs [onHome], as the old summary screens did.
class ServiceSummaryPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String status;
  final List<Widget> children;
  final VoidCallback onHome;
  final String homeLabel;
  const ServiceSummaryPage({
    super.key,
    required this.title,
    this.subtitle,
    this.status = 'Booking Confirmed!',
    required this.children,
    required this.onHome,
    this.homeLabel = 'Back to Home',
  });

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          onHome();
        },
        child: Scaffold(
          backgroundColor: RideUi.surface(context),
          body: Column(children: [
            ServiceBackBar(onBack: onHome),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                ServiceTitle(title: title, subtitle: subtitle),
                NoticeRow(status, icon: Icons.check_circle, tone: NoticeTone.success),
                const SizedBox(height: 16),
                ...children,
              ]),
            ),
            PrimaryCtaBar(label: homeLabel, onPressed: onHome),
          ]),
        ),
      );
}

/// The assigned driver on a summary page. Shows only what was passed; the
/// call action appears only when there is a number to call.
class AssignedDriverCard extends StatelessWidget {
  final String name;
  final String? rating;
  final String? experience;
  final String? phone;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehicleNumber;
  const AssignedDriverCard({
    super.key,
    required this.name,
    this.rating,
    this.experience,
    this.phone,
    this.vehicleModel,
    this.vehicleColor,
    this.vehicleNumber,
  });

  @override
  Widget build(BuildContext context) {
    String join(List<String?> parts) => parts.where((p) => p != null && p.trim().isNotEmpty).join(' · ');
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    final card = DriverInfoCard(
      name: name,
      stats: join([rating, experience]),
      vehicleModel: join([vehicleModel, vehicleColor]),
      plate: vehicleNumber ?? '',
    );
    if (!hasPhone) return card;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      card,
      const SizedBox(height: 10),
      Tooltip(
        message: 'Call driver',
        child: RidePillChip(
          icon: Icons.call,
          label: 'Call driver',
          showChevron: false,
          onTap: () => dialPhone(phone!, context: context),
        ),
      ),
    ]);
  }
}

/// "Wed, 29 Oct" — the short date used on the service screens.
String serviceDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

/// "Wed, 29 Oct · 9:30 AM".
String serviceDateTime(DateTime d) => '${serviceDate(d)} · ${RideUi.clock(d)}';
