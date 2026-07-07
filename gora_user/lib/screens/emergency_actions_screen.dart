import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/call_util.dart';

// SOS / Emergency Actions screen (Ola-style). Call Police, Siren, Record Audio,
// Call Safety Team + an optional auto-call to a saved default contact.
class EmergencyActionsScreen extends StatefulWidget {
  final String? rideId; // optional — which ride this SOS is for
  const EmergencyActionsScreen({super.key, this.rideId});
  @override
  State<EmergencyActionsScreen> createState() => _EmergencyActionsScreenState();
}

class _EmergencyActionsScreenState extends State<EmergencyActionsScreen> {
  // Change to your real safety-team / control-room number.
  static const _safetyTeamNumber = '18001234567';
  static const _policeNumber = '112'; // India single emergency number

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
    final user = context.read<UserProvider>();
    double? lat, lng;
    String address = '';
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 8));
      lat = pos.latitude; lng = pos.longitude;
      address = await ApiService.reverseGeocode(lat, lng);
    } catch (_) {}
    try {
      await ApiService.sendSosAlert({
        'rideId': widget.rideId,
        'triggeredBy': 'user',
        'name': user.name,
        'phone': user.phone,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'address': address,
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

  Future<void> _setDefaultContact() async {
    final ctrl = TextEditingController(text: _defaultContact);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Default emergency contact'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Phone number'),
        ),
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
      if (_defaultContact.isEmpty) return; // user cancelled
    }
    setState(() => _callDefault = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_call_default', v);
    if (v && _defaultContact.isNotEmpty) dialPhone(_defaultContact);
  }

  void _callPolice() => dialPhone(_policeNumber);
  void _callSafety() => dialPhone(_safetyTeamNumber);

  void _siren() => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SirenScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5,
        foregroundColor: Colors.black,
        title: const Text('Emergency Actions', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('emergency', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        const SizedBox(height: 12),
        // Default contact toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Expanded(child: Text('Place call to default contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Switch(value: _callDefault, onChanged: _toggleDefault, activeColor: AppTheme.primaryBlue),
          ]),
        ),
        if (_defaultContact.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6, left: 4),
            child: GestureDetector(onTap: _setDefaultContact,
              child: Text('Contact: $_defaultContact  (tap to change)', style: TextStyle(fontSize: 12, color: Colors.grey[600])))),
        const SizedBox(height: 16),
        // Action grid
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
          children: [
            _actionCard(Icons.notifications_active, 'Call Police', _callPolice),
            _actionCard(Icons.volume_up, 'Siren', _siren),
            _actionCard(Icons.headset_mic, 'Call Safety Team', _callSafety),
          ],
        ),
        const SizedBox(height: 20),
        const Text('More Emergency Actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 12),
        _moreCard(Icons.notifications_active, 'Call Police', _callPolice),
        const SizedBox(height: 12),
        _moreCard(Icons.volume_up, 'Siren', _siren),
        const SizedBox(height: 12),
        _moreCard(Icons.headset_mic, 'Call Safety Team', _callSafety),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
            color: active ? Colors.red.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? Colors.red : Colors.grey.shade200),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 26, color: active ? Colors.red : Colors.black87),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      );

  Widget _moreCard(IconData icon, String title, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 20, color: Colors.black87), const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))]),
            const SizedBox(height: 8),
            Text('Call Police, Record Audio, Siren, Call Safety Team', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ]),
        ),
      );
}

// Full-screen flashing siren (visual + system alert sound + strong haptics).
class _SirenScreen extends StatefulWidget {
  const _SirenScreen();
  @override
  State<_SirenScreen> createState() => _SirenScreenState();
}

class _SirenScreenState extends State<_SirenScreen> {
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
