import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';

class PreferencesPage extends StatefulWidget {
  static const route = '/preferences';
  const PreferencesPage({super.key});
  @override State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  bool _taxi = true, _rental = true, _outstation = false, _delivery = false;
  bool _bidding = true, _instantRide = true;
  String _maxDistance = '10 km';
  bool _acOnly = false, _femaleOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Preferences'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('Ride Types'),
          _switchRow('Taxi / Cab', 'Regular point-to-point rides', Icons.local_taxi, _taxi, (v) => setState(() => _taxi = v)),
          _switchRow('Rental', 'Hourly rental bookings', Icons.access_time, _rental, (v) => setState(() => _rental = v)),
          _switchRow('Outstation', 'Long-distance city-to-city rides', Icons.map, _outstation, (v) => setState(() => _outstation = v)),
          _switchRow('Delivery', 'Package & goods delivery', Icons.inventory_2, _delivery, (v) => setState(() => _delivery = v)),

          const SizedBox(height: 8),
          _section('Request Settings'),
          _switchRow('Accept Bidding Rides', 'Allow riders to bid on your ride', Icons.gavel, _bidding, (v) => setState(() => _bidding = v)),
          _switchRow('Instant Rides', 'Accept on-demand instant ride requests', Icons.flash_on, _instantRide, (v) => setState(() => _instantRide = v)),

          const SizedBox(height: 8),
          _section('Pickup Radius'),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Max Pickup Distance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(_maxDistance, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: ['5 km', '10 km', '15 km', '20 km'].map((d) {
                final sel = _maxDistance == d;
                return ChoiceChip(
                  label: Text(d),
                  selected: sel,
                  onSelected: (_) => setState(() => _maxDistance = d),
                  selectedColor: AppColors.primary.withOpacity(0.12),
                  labelStyle: TextStyle(color: sel ? AppColors.primary : AppColors.textGrey, fontWeight: sel ? FontWeight.w700 : FontWeight.normal),
                  side: BorderSide(color: sel ? AppColors.primary : AppColors.divider),
                );
              }).toList()),
            ]),
          ),

          const SizedBox(height: 8),
          _section('Ride Filters'),
          _switchRow('AC Rides Only', 'Only accept rides requiring AC vehicle', Icons.ac_unit, _acOnly, (v) => setState(() => _acOnly = v)),
          _switchRow('Female Riders Only', 'Accept rides only from female riders', Icons.person, _femaleOnly, (v) => setState(() => _femaleOnly = v)),

          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Save Preferences',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved!'), backgroundColor: AppColors.green));
              Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textGrey, letterSpacing: 0.5)),
  );

  Widget _switchRow(String title, String sub, IconData icon, bool val, ValueChanged<bool> onChanged) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)]),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: AppColors.primary)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
      ])),
      Switch(value: val, onChanged: onChanged, activeColor: AppColors.primary),
    ]),
  );
}
