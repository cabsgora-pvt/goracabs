import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/driver_api_service.dart';
import '../../widgets/captain_ui/captain_ui.dart';

// Shared definitions + UI for the driver's service preferences, used by the
// "Preference" top-sheet (opened from the home bar) and the Preferences page.

class ServiceDef {
  final String key;   // matches the backend accepts* / allow* keys
  final String title;
  final String sub;
  final String image; // asset (service images copied from the user app)
  const ServiceDef(this.key, this.title, this.sub, this.image);
}

// Taxi is always on and shown separately; these are the opt-in services.
const kServiceDefs = <ServiceDef>[
  ServiceDef('rental', 'Rental', 'Hourly rental packages', 'assets/images/services/rental.png'),
  ServiceDef('outstation', 'Outstation', 'City-to-city long trips', 'assets/images/services/outstation.png'),
  ServiceDef('hire_driver', 'Hire a Driver', "Drive customer's own car", 'assets/images/services/hire_driver.png'),
  ServiceDef('delivery', 'Parcel Delivery', 'Pick up & deliver packages', 'assets/images/services/delivery.png'),
];

const kTaxiImage = 'assets/images/services/taxi.png';

// A premium service row: service image + title/subtitle + a switch
// (or an "Always On" chip when [alwaysOn]).
class ServiceToggleTile extends StatelessWidget {
  final String title, sub, image;
  final bool value;
  final bool alwaysOn;
  final ValueChanged<bool>? onChanged;
  const ServiceToggleTile({
    super.key,
    required this.title,
    required this.sub,
    required this.image,
    this.value = false,
    this.alwaysOn = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final on = alwaysOn || value;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: on ? Cap.accent.withValues(alpha: 0.05) : Cap.tile,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? Cap.accent.withValues(alpha: 0.5) : Colors.transparent, width: 1.4),
      ),
      child: Row(children: [
        // Service image tile
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: Cap.surface, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            image, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(Icons.directions_car_rounded, color: Cap.accent),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 14.5, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
        ])),
        const SizedBox(width: 6),
        alwaysOn
            ? const CapChip('Always on', color: AppColors.green)
            : Switch(value: value, onChanged: onChanged, activeTrackColor: AppColors.primary),
      ]),
    );
  }
}

// ── "Preference" top sheet ───────────────────────────────────────────────────
// A unique panel that slides down from the top with just the service toggles.
// Opened by the single Preference icon in the home app bar.
Future<void> showServicePrefsTopSheet(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Preferences',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const Align(alignment: Alignment.topCenter, child: _ServicePrefsSheet()),
    transitionBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, -1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _ServicePrefsSheet extends StatefulWidget {
  const _ServicePrefsSheet();
  @override
  State<_ServicePrefsSheet> createState() => _ServicePrefsSheetState();
}

class _ServicePrefsSheetState extends State<_ServicePrefsSheet> {
  bool _rental = false, _outstation = false, _hire = false, _delivery = false;
  bool _allowTaxi = true, _allowRental = true, _allowOutstation = true, _allowHire = true, _allowDelivery = true;
  bool _saving = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DriverApiService.getProfile();
      final d = (res['driver'] ?? res) as Map?;
      if (d != null && mounted) {
        setState(() {
          _rental = d['acceptsRental'] == true;
          _outstation = d['acceptsOutstation'] == true;
          _hire = d['acceptsHireDriver'] == true;
          _delivery = d['acceptsDelivery'] == true;
          _allowTaxi = d['allowTaxi'] != false;
          _allowRental = d['allowRental'] != false;
          _allowOutstation = d['allowOutstation'] != false;
          _allowHire = d['allowHireDriver'] != false;
          _allowDelivery = d['allowDelivery'] != false;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  bool _valueOf(String key) =>
      key == 'rental' ? _rental : key == 'outstation' ? _outstation : key == 'hire_driver' ? _hire : _delivery;
  bool _allowOf(String key) =>
      key == 'rental' ? _allowRental : key == 'outstation' ? _allowOutstation : key == 'hire_driver' ? _allowHire : _allowDelivery;

  Future<void> _toggle(String key, bool v) async {
    setState(() {
      if (key == 'rental') _rental = v;
      else if (key == 'outstation') _outstation = v;
      else if (key == 'hire_driver') _hire = v;
      else _delivery = v;
      _saving = true;
    });
    Map<String, dynamic> res = {};
    try {
      res = await DriverApiService.updatePreferences({
        'acceptsRental': _rental,
        'acceptsOutstation': _outstation,
        'acceptsHireDriver': _hire,
        'acceptsDelivery': _delivery,
      });
    } catch (_) {}
    if (!mounted) return;
    final p = res['preferences'] as Map?;
    setState(() {
      if (p != null) {
        _rental = p['acceptsRental'] == true;
        _outstation = p['acceptsOutstation'] == true;
        _hire = p['acceptsHireDriver'] == true;
        _delivery = p['acceptsDelivery'] == true;
      }
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 6, left: 10, right: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: Cap.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trip preferences', style: Cap.title(size: 19)),
              const SizedBox(height: 2),
              Text('Choose the ride types you accept', style: Cap.caption(size: 12.5)),
            ])),
            if (_saving)
              Padding(padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Cap.accent)))
            else
              CapRoundAction(icon: Icons.close_rounded, size: 36, tooltip: 'Close', onTap: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          if (!_loaded)
            Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: Cap.accent, strokeWidth: 2.6))
          else ...[
            if (_allowTaxi)
              const ServiceToggleTile(title: 'Taxi / Cab', sub: 'Regular point-to-point rides', image: kTaxiImage, alwaysOn: true),
            ...kServiceDefs.where((s) => _allowOf(s.key)).map((s) => ServiceToggleTile(
                  title: s.title, sub: s.sub, image: s.image,
                  value: _valueOf(s.key),
                  onChanged: _saving ? null : (v) => _toggle(s.key, v),
                )),
          ],
        ]),
      ),
    );
  }
}
