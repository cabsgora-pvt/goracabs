import 'package:flutter/material.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import 'widgets/reg_ui.dart';
import 'widgets/vehicle_visuals.dart';
import '../../services/driver_api_service.dart';
import 'vehicle_details_page.dart';

export 'widgets/vehicle_visuals.dart' show VehicleTypeImage, vehicleAssetFor;

class VehicleSelectionPage extends StatefulWidget {
  static const route = '/registration/vehicle-selection';
  const VehicleSelectionPage({super.key});
  @override
  State<VehicleSelectionPage> createState() => _VehicleSelectionPageState();
}

class _VehicleSelectionPageState extends State<VehicleSelectionPage> {
  List<Map<String, dynamic>> _vehicleTypes = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;

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
      if (mounted) setState(() { _vehicleTypes = active; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle type')),
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
    return RegStepScaffold(
      step: CapRegSteps.vehicle,
      stepLabel: 'Vehicle',
      title: 'Which vehicle will you drive?',
      subtitle: 'Pick the type that matches your RC book. It decides which trips you get.',
      // Grey until a type is picked, but still tappable: it then says what
      // is missing.
      bottom: RegCta(label: 'Continue', dimmed: _selected == null, onPressed: _next),
      children: [
        if (_loading)
          // Static placeholders in the shape of the cards (no spinner).
          for (var i = 0; i < 3; i++)
            Container(
              height: 104,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
            )
        else if (_vehicleTypes.isEmpty)
          const CapEmpty(icon: Icons.directions_car_rounded, title: 'No vehicle types available',
              message: 'Please try again in a little while.')
        else
          // One full-width card per type, arriving one after another.
          for (final vt in _vehicleTypes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: VehicleTypeTile(
                vt: vt,
                selected: _isSelected(vt),
                onTap: () => setState(() => _selected = vt),
              ),
            ),
      ],
    );
  }

  bool _isSelected(Map<String, dynamic> vt) {
    final vtId = (vt['_id'] ?? vt['id'] ?? '').toString();
    final selId = (_selected?['_id'] ?? _selected?['id'] ?? '').toString();
    return vtId.isNotEmpty && vtId == selId;
  }
}

/// One selectable vehicle type: the real vehicle photo large on a soft tinted
/// backdrop, the name in bold, "4 seats" from `capacity`, service chips from
/// `services`, and a radio on the right. Selected: brand border, tinted card,
/// the photo slides forward and grows a little, the check pops in.
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
                  final photoW = (box.maxWidth * 0.36).clamp(88.0, 138.0);
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
        height: 84,
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
              child: VehicleTypeImage(vt: vt, width: w - 14, height: 70),
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
