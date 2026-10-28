import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_step_scaffold.dart';
import '../../services/driver_api_service.dart';
import 'vehicle_details_page.dart';

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
      bottom: CapButton(
        label: 'Continue',
        tone: _selected == null ? CapButtonTone.secondary : CapButtonTone.primary,
        onPressed: _next,
      ),
      children: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: Cap.accent, strokeWidth: 2.6)),
          )
        else if (_vehicleTypes.isEmpty)
          const CapEmpty(icon: Icons.directions_car_rounded, title: 'No vehicle types available',
              message: 'Please try again in a little while.')
        else
          // 2-column grid, Ola / Uber / Rapido Captain style: the vehicle's
          // own image and its name — nothing else.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // Fixed height: every tile, and so every image, is the same size.
              mainAxisExtent: 168,
            ),
            itemCount: _vehicleTypes.length,
            itemBuilder: (_, i) {
              final vt = _vehicleTypes[i];
              return VehicleTypeTile(
                vt: vt,
                selected: _isSelected(vt),
                onTap: () => setState(() => _selected = vt),
              );
            },
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

/// The vehicle type's own image (admin-uploaded), at one fixed visual size so
/// a bike and a truck sit in identical frames; an icon when there is none.
class VehicleTypeImage extends StatelessWidget {
  final Map<String, dynamic> vt;
  final double width, height;
  const VehicleTypeImage({super.key, required this.vt, this.width = 84, this.height = 64});

  static IconData iconFor(String name) {
    final s = name.toLowerCase();
    if (s.contains('bike') || s.contains('moto') || s.contains('scooter')) return Icons.two_wheeler;
    if (s.contains('auto') || s.contains('rickshaw')) return Icons.electric_rickshaw;
    if (s.contains('truck') || s.contains('tempo')) return Icons.local_shipping;
    if (s.contains('suv')) return Icons.airport_shuttle;
    return Icons.directions_car_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final raw = (vt['imageUrl'] as String? ?? '').trim();
    final url = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    final icon = Icon(iconFor((vt['name'] ?? '').toString()), size: height * 0.55, color: Cap.muted);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Cap.surface, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(6),
      child: url.isEmpty
          ? Center(child: icon)
          : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Center(child: icon)),
    );
  }
}

/// One selectable vehicle type: its real image, centred in a fixed-height area,
/// and its name. Light grey card; selected = navy 2px border + check badge.
class VehicleTypeTile extends StatelessWidget {
  final Map<String, dynamic> vt;
  final bool selected;
  final VoidCallback onTap;
  const VehicleTypeTile({super.key, required this.vt, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Cap.accent.withValues(alpha: 0.05) : Cap.tile,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Cap.radius),
          side: BorderSide(color: selected ? Cap.accent : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Cap.radius),
          onTap: onTap,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: Column(children: [
                // Same frame for every type, so a bike and a truck read at
                // the same visual size.
                SizedBox(
                  height: 92,
                  child: LayoutBuilder(
                    builder: (context, box) => VehicleTypeImage(vt: vt, width: box.maxWidth, height: 92),
                  ),
                ),
                const Spacer(),
                Text((vt['name'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Cap.body(size: 14.5, weight: FontWeight.w800).copyWith(height: 1.2)),
                const Spacer(),
              ]),
            ),
            if (selected)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: Cap.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
