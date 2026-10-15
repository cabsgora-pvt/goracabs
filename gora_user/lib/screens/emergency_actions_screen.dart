import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/call_util.dart';
import '../utils/emergency_contacts_store.dart';
import 'settings_screen.dart' show EmergencyContactsScreen;

// SOS / Emergency Actions screen (Ola-style). Call Police, Siren, Record Audio,
// Call Safety Team + the same emergency contacts Settings manages, with an
// optional auto-call to the first one.
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

  List<Map<String, String>> _contacts = [];
  bool _autoCall = false;
  final _recorder = AudioRecorder();
  bool _recording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  String? _lastRecordingPath;

  @override
  void initState() {
    super.initState();
    _load();
    _raiseAlert();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
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

  // Loads the same contacts list Settings manages — previously this screen
  // read a separate single "default contact" pref that Settings never wrote
  // to, so adding a contact there did nothing for what SOS would call.
  Future<void> _load() async {
    final contacts = await EmergencyContactsStore.load();
    final prefs = await SharedPreferences.getInstance();
    final autoCall = prefs.getBool('sos_auto_call') ?? false;
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _autoCall = autoCall;
    });
    if (autoCall && contacts.isNotEmpty) dialPhone(contacts.first['phone'] ?? '');
  }

  Future<void> _manageContacts() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
    _load(); // pick up any add/remove made there
  }

  Future<void> _toggleAutoCall(bool v) async {
    if (v && _contacts.isEmpty) {
      await _manageContacts();
      if (_contacts.isEmpty) return; // still none — nothing to auto-call
    }
    setState(() => _autoCall = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_auto_call', v);
  }

  void _callPolice() => dialPhone(_policeNumber);
  void _callSafety() => dialPhone(_safetyTeamNumber);

  void _siren() => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SirenScreen()));

  // Starts/stops a local audio recording — evidence the rider can keep or
  // share afterwards. Saved on the phone only; there is no upload yet.
  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      _recordTimer?.cancel();
      _lastRecordingPath = path;
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(path != null
              ? 'Recording saved (${_fmtDuration(_recordElapsed)}) on your phone.'
              : 'Recording could not be saved.'),
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed to record audio.')),
        );
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/sos_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() { _recording = true; _recordElapsed = Duration.zero; });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordElapsed += const Duration(seconds: 1));
    });
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

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
        // Emergency contacts — same list Settings manages.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Expanded(child: Text('Auto-call my first contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Switch(value: _autoCall, onChanged: _toggleAutoCall, activeColor: AppTheme.primaryBlue),
          ]),
        ),
        const SizedBox(height: 8),
        ..._contacts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(child: Text('${c['name']} (${c['relation']})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  IconButton(icon: const Icon(Icons.call, color: Colors.green), onPressed: () => dialPhone(c['phone'] ?? '')),
                ]),
              ),
            )),
        GestureDetector(
          onTap: _manageContacts,
          child: Padding(padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(_contacts.isEmpty ? 'Add an emergency contact' : 'Manage emergency contacts',
              style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))),
        ),
        const SizedBox(height: 16),
        // Action grid
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
          children: [
            _actionCard(Icons.notifications_active, 'Call Police', _callPolice),
            _actionCard(Icons.volume_up, 'Siren', _siren),
            _actionCard(Icons.headset_mic, 'Call Safety Team', _callSafety),
            _actionCard(_recording ? Icons.stop_circle : Icons.mic, _recording ? 'Stop (${_fmtDuration(_recordElapsed)})' : 'Record Audio', _toggleRecording, active: _recording),
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
        const SizedBox(height: 12),
        _moreCard(Icons.mic, 'Record Audio', _toggleRecording),
        if (_lastRecordingPath != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Share.shareXFiles([XFile(_lastRecordingPath!)], text: 'SOS audio recording'),
            child: const Padding(padding: EdgeInsets.only(left: 4),
              child: Text('Share last recording', style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))),
          ),
        ],
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
