import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';

class PreferencesPage extends StatefulWidget {
  static const route = '/preferences';
  const PreferencesPage({super.key});
  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  // Service opt-ins
  bool _rental = false, _outstation = false, _hireDriver = false, _delivery = false;
  // Admin allow-gates (a disallowed service is hidden here)
  bool _allowTaxi = true, _allowRental = true, _allowOutstation = true, _allowHireDriver = true, _allowDelivery = true;
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final res = await DriverApiService.getProfile();
      final d = res['driver'] as Map<String, dynamic>?;
      if (d == null || !mounted) return;
      setState(() {
        _outstation = d['acceptsOutstation'] == true;
        _rental = d['acceptsRental'] == true;
        _hireDriver = d['acceptsHireDriver'] == true;
        _delivery = d['acceptsDelivery'] == true;
        _allowTaxi = d['allowTaxi'] != false;
        _allowRental = d['allowRental'] != false;
        _allowOutstation = d['allowOutstation'] != false;
        _allowHireDriver = d['allowHireDriver'] != false;
        _allowDelivery = d['allowDelivery'] != false;
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _savePrefs() async {
    setState(() => _saving = true);
    try {
      final res = await DriverApiService.updatePreferences({
        'acceptsOutstation': _outstation,
        'acceptsRental': _rental,
        'acceptsHireDriver': _hireDriver,
        'acceptsDelivery': _delivery,
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: ${res['error']}'), backgroundColor: AppColors.red));
        return;
      }
      final prefs = res['preferences'] as Map<String, dynamic>?;
      setState(() {
        _outstation = (prefs?['acceptsOutstation'] as bool?) ?? _outstation;
        _rental = (prefs?['acceptsRental'] as bool?) ?? _rental;
        _hireDriver = (prefs?['acceptsHireDriver'] as bool?) ?? _hireDriver;
        _delivery = (prefs?['acceptsDelivery'] as bool?) ?? _delivery;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved'), backgroundColor: AppColors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Preferences'),
      body: _loading
          ? const AppLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _section('Services you accept'),
                if (_allowTaxi)
                  _switchRow('Taxi / Cab', 'Regular point-to-point rides', Icons.local_taxi, true, null),
                if (_allowRental)
                  _switchRow('Rental', 'Hourly rental package bookings', Icons.access_time, _rental, (v) => setState(() => _rental = v)),
                if (_allowOutstation)
                  _switchRow('Outstation', 'Long-distance city-to-city rides', Icons.map, _outstation, (v) => setState(() => _outstation = v)),
                if (_allowHireDriver)
                  _switchRow('Hire a Driver', 'Drive customer\'s own car (hourly)', Icons.person_pin_circle, _hireDriver, (v) => setState(() => _hireDriver = v)),
                if (_allowDelivery)
                  _switchRow('Parcel Delivery', 'Pickup & deliver packages', Icons.local_shipping, _delivery, (v) => setState(() => _delivery = v)),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _saving ? 'Saving...' : 'Save Preferences',
                  onTap: _saving ? null : _savePrefs,
                ),
              ]),
            ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textGrey, letterSpacing: 0.5)),
      );

  // onChanged == null renders a disabled (always-on) switch (used for Taxi).
  Widget _switchRow(String title, String sub, IconData icon, bool val, ValueChanged<bool>? onChanged) => Container(
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
