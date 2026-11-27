import 'package:flutter/material.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import 'widgets/reg_ui.dart';
import 'widgets/vehicle_visuals.dart';
import '../../services/driver_api_service.dart';
import 'vehicle_categories.dart';
import 'vehicle_details_page.dart';

export 'widgets/vehicle_visuals.dart' show VehicleTypeImage, vehicleAssetFor;

/// Registration step 3, in two levels:
///   1. a grid of vehicle CATEGORIES (Bike, Auto, Cab, Truck …) — the
///      category's basic-tier photo, its name and how many options it has.
///      A category with one type selects it on tap;
///   2. a category with several tiers (Cab → Cab / Prime Sedan / Prime SUV)
///      opens their list, basic first: photo, name, seats, tagline and what a
///      vehicle needs to qualify ("Needs: 2019 or newer · Dzire, Aura").
/// Back (the hero arrow, the system back, or "All vehicle types") returns
/// from 2 to 1. Continue opens the vehicle details with the chosen type.
class VehicleSelectionPage extends StatefulWidget {
  static const route = '/registration/vehicle-selection';
  const VehicleSelectionPage({super.key});
  @override
  State<VehicleSelectionPage> createState() => _VehicleSelectionPageState();
}

class _VehicleSelectionPageState extends State<VehicleSelectionPage> {
  List<VehicleCategory> _categories = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;
  /// The category whose tiers are listed (level 2), or null for the grid.
  String? _openKey;

  VehicleCategory? get _open {
    for (final c in _categories) {
      if (c.key == _openKey) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final types = await DriverApiService.getVehicleTypes();
      // Every ACTIVE vehicle type, whatever services it offers. This used to
      // keep only types offering 'taxi', so a delivery-only type (Mini Truck)
      // could never be picked and delivery drivers could not register.
      // isActive defaults to true on the server model, so a missing flag counts
      // as active.
      final active = types.where((t) => t['isActive'] != false).toList();
      if (mounted) setState(() { _categories = groupVehicleTypes(active); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tapCategory(VehicleCategory c) {
    if (c.isSingle) {
      setState(() => _selected = c.types.single);
      return;
    }
    setState(() {
      // A type picked in another category does not carry into this list.
      if (!c.contains(_selected)) _selected = null;
      _openKey = c.key;
    });
  }

  void _backToCategories() => setState(() => _openKey = null);

  void _next() {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_open == null ? 'Please select a vehicle type' : 'Please pick one ${_open!.label} type')),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      VehicleDetailsPage.route,
      arguments: {'vehicle': _selected},
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _openKey != null) _backToCategories();
      },
      child: RegStepScaffold(
        step: CapRegSteps.vehicle,
        stepLabel: 'Vehicle',
        title: open == null ? 'Which vehicle will you drive?' : 'Which ${open.label}?',
        subtitle: open == null
            ? 'Pick the type that matches your RC book. It decides which trips you get.'
            : 'Premium types earn more per trip and need a vehicle that qualifies.',
        onBack: open == null ? null : _backToCategories,
        // Grey until a type is picked, but still tappable: it then says what
        // is missing.
        bottom: RegCta(label: 'Continue', dimmed: _selected == null, onPressed: _next),
        children: open == null ? _categoryGrid() : _typeList(open),
      ),
    );
  }

  /// Level 1: two categories per row (one on a very narrow screen).
  List<Widget> _categoryGrid() {
    if (_loading) {
      // Static placeholders in the shape of the cards (no spinner).
      return [
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              for (var j = 0; j < 2; j++) ...[
                if (j == 1) const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 156,
                    decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ]),
          ),
      ];
    }
    if (_categories.isEmpty) {
      return const [
        CapEmpty(icon: Icons.directions_car_rounded, title: 'No vehicle types available',
            message: 'Please try again in a little while.'),
      ];
    }
    return [
      LayoutBuilder(builder: (context, box) {
        final perRow = box.maxWidth < 280 ? 1 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < _categories.length; i += perRow) {
          final row = _categories.skip(i).take(perRow).toList();
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var j = 0; j < perRow; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(
                  child: j < row.length
                      ? VehicleCategoryCard(
                          key: ValueKey('vehicle_category_${row[j].key}'),
                          category: row[j],
                          selectedType: row[j].contains(_selected) ? _selected : null,
                          onTap: () => _tapCategory(row[j]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      }),
    ];
  }

  /// Level 2: the category's tiers, basic first.
  List<Widget> _typeList(VehicleCategory c) => [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextButton.icon(
              key: const ValueKey('vehicle_back_to_categories'),
              onPressed: _backToCategories,
              style: TextButton.styleFrom(
                foregroundColor: Cap.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(44, 40),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('All vehicle types', style: Cap.body(size: 13.5, weight: FontWeight.w800, color: Cap.accent)),
            ),
          ),
        ),
        for (final vt in c.types)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: VehicleTypeTile(
              key: ValueKey('vehicle_type_${vehicleTypeIdOf(vt)}'),
              vt: vt,
              selected: sameVehicleType(vt, _selected),
              onTap: () => setState(() => _selected = vt),
            ),
          ),
      ];
}

/// One category on the first level: its basic-tier photo on a soft tinted
/// backdrop, the category name and "3 options" (or, for a single type with
/// its own name, that name — "Mini Truck"). Selected — the type picked is in
/// this category — brand border, tinted card and a check on the photo.
class VehicleCategoryCard extends StatelessWidget {
  final VehicleCategory category;
  /// The type picked in this category, or null.
  final Map<String, dynamic>? selectedType;
  final VoidCallback onTap;
  const VehicleCategoryCard({super.key, required this.category, required this.onTap, this.selectedType});

  bool get selected => selectedType != null;

  String get subtitle {
    final c = category;
    final sel = (selectedType?['name'] ?? '').toString().trim();
    if (!c.isSingle) return sel.isNotEmpty ? sel : c.countText;
    final name = (c.representative['name'] ?? '').toString().trim();
    return name.isNotEmpty && name.toLowerCase() != c.label.toLowerCase() ? name : c.countText;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final dur = regDuration(context, const Duration(milliseconds: 260));
    return Semantics(
      selected: selected,
      button: true,
      label: '${category.label}, ${category.countText}',
      child: RegPressScale(
        pressed: 0.97,
        child: AnimatedContainer(
          duration: dur,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? Cap.accent.withValues(alpha: 0.06) : Cap.surface,
            borderRadius: radius,
            border: Border.all(color: selected ? Cap.accent : RegPalette.hairline, width: selected ? 2 : 1.2),
            boxShadow: [
              BoxShadow(
                color: selected ? Cap.accent.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.04),
                blurRadius: selected ? 18 : 10,
                offset: Offset(0, selected ? 6 : 3),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  _photo(dur),
                  const SizedBox(height: 10),
                  Text(category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Cap.body(size: 16, weight: FontWeight.w800, color: selected ? Cap.accent : null)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                      child: Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Cap.caption(size: 12.5, color: selected && !category.isSingle ? Cap.accent : null)),
                    ),
                    // More than one tier: this opens a list.
                    if (!category.isSingle) Icon(Icons.chevron_right_rounded, size: 18, color: Cap.muted),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photo(Duration dur) => Container(
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [Cap.accent.withValues(alpha: 0.16), Cap.accent.withValues(alpha: 0.05)]
                : [RegPalette.field, Cap.tile],
          ),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            bottom: 11,
            left: 24,
            right: 24,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.elliptical(60, 4)),
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: dur,
              curve: Curves.easeOutBack,
              child: VehicleTypeImage(vt: category.representative, width: double.infinity, height: 76),
            ),
          ),
          if (selected)
            Positioned(
              top: 6,
              right: 6,
              child: RegPopIn(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: Cap.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
        ]),
      );
}

/// One selectable vehicle type: the real vehicle photo large on a soft tinted
/// backdrop, the name in bold, "4 seats" from `capacity`, the tier's tagline,
/// what a vehicle needs for it ("Needs: 2019 or newer · Dzire, Aura"), service
/// chips from `services`, and a radio on the right. Selected: brand border,
/// tinted card, the photo slides forward and grows a little, the check pops in.
class VehicleTypeTile extends StatelessWidget {
  final Map<String, dynamic> vt;
  final bool selected;
  final VoidCallback onTap;
  const VehicleTypeTile({super.key, required this.vt, required this.selected, required this.onTap});

  int? get _seats {
    final c = vt['capacity'];
    final n = c is num ? c.toInt() : int.tryParse('${c ?? ''}'.trim());
    return n != null && n > 0 ? n : null;
  }

  /// Service keys with a label, one chip per label.
  List<String> get _services {
    final s = vt['services'];
    if (s is! List) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final k in s) {
      final label = vehicleServiceLabel('$k');
      if (label.isNotEmpty && seen.add(label)) out.add('$k');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final dur = regDuration(context, const Duration(milliseconds: 260));
    final seats = _seats;
    final services = _services;
    final tagline = vehicleTaglineOf(vt);
    final needs = vehicleRequirementsText(vt);
    return Semantics(
      selected: selected,
      button: true,
      child: RegPressScale(
        pressed: 0.97,
        child: AnimatedContainer(
          duration: dur,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? Cap.accent.withValues(alpha: 0.06) : Cap.surface,
            borderRadius: radius,
            border: Border.all(color: selected ? Cap.accent : RegPalette.hairline, width: selected ? 2 : 1.2),
            boxShadow: [
              BoxShadow(
                color: selected ? Cap.accent.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.04),
                blurRadius: selected ? 18 : 10,
                offset: Offset(0, selected ? 6 : 3),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: LayoutBuilder(builder: (context, box) {
                  final photoW = (box.maxWidth * 0.38).clamp(92.0, 150.0);
                  return Row(children: [
                    _photo(photoW, dur),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text((vt['name'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Cap.body(size: 16, weight: FontWeight.w800, color: selected ? Cap.accent : null)
                                .copyWith(height: 1.2)),
                        if (seats != null) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(Icons.person_rounded, size: 14, color: Cap.muted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(seats == 1 ? '1 seat' : '$seats seats',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12.5)),
                            ),
                          ]),
                        ],
                        if (tagline.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(tagline,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12.5)),
                        ],
                        if (needs.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(Icons.verified_outlined, size: 14, color: RegPalette.orange),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('Needs: $needs',
                                  key: ValueKey('vehicle_needs_${vehicleTypeIdOf(vt)}'),
                                  // The whole rule list: a driver must see every rule to pick right.
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cap.body(size: 12, weight: FontWeight.w700, color: RegPalette.orange)
                                      .copyWith(height: 1.25)),
                            ),
                          ]),
                        ],
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Wrap(spacing: 4, runSpacing: 4, children: [
                            for (final k in services) _ServiceChip(k),
                          ]),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 8),
                    _RadioMark(selected: selected),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The photo on a soft tinted backdrop with a ground shadow under it.
  Widget _photo(double w, Duration dur) => Container(
        width: w,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [Cap.accent.withValues(alpha: 0.16), Cap.accent.withValues(alpha: 0.05)]
                : [RegPalette.field, Cap.tile],
          ),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            bottom: 11,
            child: Container(
              width: w * 0.62,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.elliptical(60, 4)),
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          AnimatedSlide(
            offset: selected ? const Offset(0.05, 0) : Offset.zero,
            duration: dur,
            curve: Curves.easeOutBack,
            child: AnimatedScale(
              scale: selected ? 1.1 : 1,
              duration: dur,
              curve: Curves.easeOutBack,
              child: VehicleTypeImage(vt: vt, width: w - 14, height: 76),
            ),
          ),
        ]),
      );
}

class _ServiceChip extends StatelessWidget {
  final String service;
  const _ServiceChip(this.service);

  @override
  Widget build(BuildContext context) {
    final c = vehicleServiceColor(service);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
      child: Text(vehicleServiceLabel(service),
          maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Radio on the right of a vehicle card; the check pops in when selected.
class _RadioMark extends StatelessWidget {
  final bool selected;
  const _RadioMark({required this.selected});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: regDuration(context, const Duration(milliseconds: 220)),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Cap.accent : Colors.transparent,
          border: Border.all(color: selected ? Cap.accent : const Color(0xFFC5CDDC), width: 2),
        ),
        child: selected ? const RegPopIn(child: Icon(Icons.check_rounded, size: 16, color: Colors.white)) : null,
      );
}
