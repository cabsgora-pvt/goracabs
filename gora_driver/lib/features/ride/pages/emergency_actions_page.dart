import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';

// SOS / Emergency Actions for the driver (same as rider side).
class EmergencyActionsPage extends StatefulWidget {
  final String? rideId;
  const EmergencyActionsPage({super.key, this.rideId});
  @override
  State<EmergencyActionsPage> createState() => _EmergencyActionsPageState();
}

class _EmergencyActionsPageState extends State<EmergencyActionsPage> {
  static const _safetyTeamNumber = '18001234567';
  static const _policeNumber = '112';

  bool _callDefault = false;
  String _defaultContact = '';

  @override
  void initState() {
    super.initState();
    _load();
    _raiseAlert();
  }

  // Notify admin + safety team the moment SOS is opened (with ride + location).
  Future<void> _raiseAlert() async {
    final dp = context.read<DriverProvider>();
    double? lat, lng;
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null) { lat = pos.latitude; lng = pos.longitude; }
    } catch (_) {}
    try {
      await DriverApiService.sendSosAlert({
        'rideId': widget.rideId,
        'triggeredBy': 'driver',
        'name': dp.name,
        'phone': dp.phone,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultContact = prefs.getString('sos_default_contact') ?? '';
        _callDefault = prefs.getBool('sos_call_default') ?? false;
      });
    }
  }

  Future<void> _dial(String number) async {
    if (number.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number.trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _setDefaultContact() async {
    final ctrl = TextEditingController(text: _defaultContact);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Default emergency contact'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Phone number')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (saved == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sos_default_contact', saved);
    if (mounted) setState(() => _defaultContact = saved);
  }

  Future<void> _toggleDefault(bool v) async {
    if (v && _defaultContact.isEmpty) {
      await _setDefaultContact();
      if (_defaultContact.isEmpty) return;
    }
    setState(() => _callDefault = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_call_default', v);
    if (v && _defaultContact.isNotEmpty) _dial(_defaultContact);
  }

  void _siren() => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SirenPage()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white, elevation: 0.5, foregroundColor: AppColors.textDark,
        title: const Text('Emergency Actions', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('emergency', style: TextStyle(color: AppColors.textGrey, fontSize: 14)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Expanded(child: Text('Place call to default contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Switch(value: _callDefault, onChanged: _toggleDefault, activeColor: AppColors.primary),
          ]),
        ),
        if (_defaultContact.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6, left: 4),
            child: GestureDetector(onTap: _setDefaultContact,
              child: Text('Contact: $_defaultContact  (tap to change)', style: TextStyle(fontSize: 12, color: AppColors.textGrey)))),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
          children: [
            _actionCard(Icons.notifications_active, 'Call Police', () => _dial(_policeNumber)),
            _actionCard(Icons.volume_up, 'Siren', _siren),
            _actionCard(Icons.headset_mic, 'Call Safety Team', () => _dial(_safetyTeamNumber)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('More Emergency Actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 12),
        _moreCard(Icons.notifications_active, 'Call Police', () => _dial(_policeNumber)),
        const SizedBox(height: 12),
        _moreCard(Icons.headset_mic, 'Call Safety Team', () => _dial(_safetyTeamNumber)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _actionCard(IconData icon, String label, VoidCallback onTap, {bool active = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: active ? Colors.red.withOpacity(0.1) : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? Colors.red : AppColors.divider),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 26, color: active ? Colors.red : AppColors.textDark),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      );

  Widget _moreCard(IconData icon, String title, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 20, color: AppColors.textDark), const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))]),
            const SizedBox(height: 8),
            Text('Call Police, Record Audio, Siren, Call Safety Team', style: TextStyle(fontSize: 13, color: AppColors.textGrey)),
          ]),
        ),
      );
}

class _SirenPage extends StatefulWidget {
  const _SirenPage();
  @override
  State<_SirenPage> createState() => _SirenPageState();
}

class _SirenPageState extends State<_SirenPage> {
  Timer? _t;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 600), (_) {
      setState(() => _on = !_on);
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _on ? Colors.red : Colors.white,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.volume_up, size: 96, color: _on ? Colors.white : Colors.red),
          const SizedBox(height: 16),
          Text('SIREN ON', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _on ? Colors.white : Colors.red)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
            child: const Text('STOP', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
