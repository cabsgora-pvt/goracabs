import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import '../service_prefs.dart';

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
      // Accept both shapes: { driver: {...} } or the driver object directly.
      final d = (res['driver'] ?? res) as Map?;
      if (d != null && mounted) {
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
      }
    } catch (_) {}
    // Always clear the loader — never leave the page stuck on the spinner.
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

  bool _valueOf(String key) =>
      key == 'rental' ? _rental : key == 'outstation' ? _outstation : key == 'hire_driver' ? _hireDriver : _delivery;
  bool _allowOf(String key) =>
      key == 'rental' ? _allowRental : key == 'outstation' ? _allowOutstation : key == 'hire_driver' ? _allowHireDriver : _allowDelivery;
  void _setValue(String key, bool v) => setState(() {
        if (key == 'rental') _rental = v;
        else if (key == 'outstation') _outstation = v;
        else if (key == 'hire_driver') _hireDriver = v;
        else _delivery = v;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Service Preferences'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Premium header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Choose your services', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      SizedBox(height: 3),
                      Text('Turn on the ride types you want to receive', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 18),
                // Taxi — always on
                if (_allowTaxi)
                  const ServiceToggleTile(title: 'Taxi / Cab', sub: 'Regular point-to-point rides', image: kTaxiImage, alwaysOn: true),
                // Opt-in services the admin allows
                ...kServiceDefs.where((s) => _allowOf(s.key)).map((s) => ServiceToggleTile(
                      title: s.title, sub: s.sub, image: s.image,
                      value: _valueOf(s.key),
                      onChanged: (v) => _setValue(s.key, v),
                    )),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: _saving ? 'Saving...' : 'Save Preferences',
                  onTap: _saving ? null : _savePrefs,
                ),
              ]),
            ),
    );
  }
}
