import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/call_util.dart';
import '../utils/emergency_contacts_store.dart';
import 'active_ride_screen.dart' show trackingLinkFor;
import 'settings_screen.dart' show EmergencyContactsScreen;

/// How long the rider has to cancel an SOS opened by mistake before the
/// safety team is alerted.
const kSosCountdown = Duration(seconds: 5);

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
  // What happened to the alert to the safety team: null while it is being
  // sent, then the line shown at the top of the screen.
  SosAlertStatus? _alert;
  // Seconds left before the alert goes out; null once it is sent / sending.
  int? _countdown = kSosCountdown.inSeconds;
  bool _cancelled = false;
  Timer? _countdownTimer;
  // Looked up while the countdown runs, so the alert carries it at once.
  late final Future<({double? lat, double? lng, String address})> _where;
  // The live ride to share: this screen's ride, or the rider's active one.
  String? _shareRideId;

  @override
  void initState() {
    super.initState();
    _shareRideId = widget.rideId;
    _where = _locate();
    _load();
    _startCountdown();
    if (_shareRideId == null) _findActiveRide();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = (_countdown ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        _sendNow();
      } else {
        setState(() => _countdown = left);
      }
    });
  }

  /// The countdown ended or the rider tapped "Send now".
  void _sendNow() {
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _countdown = null;
      _cancelled = false;
      _alert = null;
    });
    _raiseAlert();
    // Auto-call waits for the countdown too, so a mistaken tap rings no one.
    if (_autoCall && _contacts.isNotEmpty) dialPhone(_contacts.first['phone'] ?? '');
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = null;
      _cancelled = true;
    });
  }

  Future<void> _findActiveRide() async {
    try {
      final res = await ApiService.getActiveRide();
      final ride = res['ride'];
      if (ride is Map && mounted) {
        final id = (ride['_id'] ?? ride['id'] ?? '').toString();
        if (id.isNotEmpty) setState(() => _shareRideId = id);
      }
    } catch (_) {}
  }

  Future<({double? lat, double? lng, String address})> _locate() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 8));
      final address = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
      return (lat: pos.latitude, lng: pos.longitude, address: address);
    } catch (_) {
      return (lat: null, lng: null, address: '');
    }
  }

  // Notify admin + safety team (with ride + location) once the countdown ends.
  Future<void> _raiseAlert() async {
    final user = context.read<UserProvider>();
    final w = await _where;
    Map<String, dynamic> res;
    try {
      res = await ApiService.sendSosAlert({
        'rideId': widget.rideId,
        'triggeredBy': 'user',
        'name': user.name,
        'phone': user.phone,
        if (w.lat != null) 'lat': w.lat,
        if (w.lng != null) 'lng': w.lng,
        'address': w.address,
      });
    } catch (_) {
      res = const {'error': 'no connection'};
    }
    if (mounted) setState(() => _alert = sosAlertStatusOf(res));
  }

  // Loads the same contacts list Settings manages: the cached copy at once
  // (it works offline), then the server's.
  Future<void> _load() async {
    final contacts = await EmergencyContactsStore.load();
    bool autoCall = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoCall = prefs.getBool('sos_auto_call') ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _autoCall = autoCall;
    });
    final synced = await EmergencyContactsStore.sync();
    if (mounted) setState(() => _contacts = synced);
  }

  Future<void> _manageContacts() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
    final c = await EmergencyContactsStore.load(); // pick up any add/remove made there
    if (mounted) setState(() => _contacts = c);
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

  /// "Share live trip with contacts": the public tracking page (share-token
  /// link) by SMS to the saved contacts, WhatsApp, or the system share sheet.
  Future<void> _shareTrip() async {
    final id = _shareRideId;
    if (id == null) return;
    final link = await trackingLinkFor(id);
    if (!mounted) return;
    final text = sosShareMessage(link);
    final phones = _contacts.map((c) => c['phone'] ?? '').where((p) => p.isNotEmpty).toList();
    final how = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Share live trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: const Icon(Icons.sms_outlined, color: AppTheme.primaryBlue),
            title: Text(phones.isEmpty ? 'Text message' : 'Text my emergency contacts (${phones.length})'),
            onTap: () => Navigator.pop(ctx, 'sms'),
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
            title: const Text('WhatsApp'),
            onTap: () => Navigator.pop(ctx, 'wa'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined, color: AppTheme.primaryBlue),
            title: const Text('More options'),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
        ]),
      ),
    );
    if (how == null || !mounted) return;
    var opened = false;
    try {
      if (how == 'sms') {
        opened = await launchUrl(sosSmsUri(phones, text));
      } else if (how == 'wa') {
        opened = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      opened = false;
    }
    if (how == 'share' || !opened) {
      await Share.share(text, subject: 'My live Gora trip');
    }
  }

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

  // A text action with a full 48 dp tap target (it used to be a bare 12 pt
  // line about 16 dp tall).
  Widget _linkButton(String label, VoidCallback onTap, {Key? key, IconData? icon}) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: key,
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          icon: Icon(icon ?? Icons.chevron_right_rounded, size: 18),
          label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = theme.cardColor;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: card, elevation: 0.5,
        foregroundColor: theme.colorScheme.onSurface,
        title: const Text('Emergency Actions', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Emergency', style: TextStyle(color: muted, fontSize: 14)),
        const SizedBox(height: 12),
        _alertBanner(),
        if (_shareRideId != null) ...[
          const SizedBox(height: 12),
          Material(
            color: card,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              key: const ValueKey('sos-share-trip'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Icon(Icons.share_location_rounded, color: theme.colorScheme.primary),
              title: const Text('Share live trip with contacts', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('SMS or WhatsApp a link that tracks this ride live'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _shareTrip,
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Emergency contacts — same list Settings manages.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
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
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(child: Text(
                      (c['relation'] ?? '').isNotEmpty ? '${c['name']} (${c['relation']})' : '${c['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  IconButton(tooltip: 'Call ${c['name']}', icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () => dialPhone(c['phone'] ?? '')),
                ]),
              ),
            )),
        _linkButton(_contacts.isEmpty ? 'Add an emergency contact' : 'Manage emergency contacts', _manageContacts,
            key: const ValueKey('sos-manage-contacts'), icon: Icons.person_add_alt_1_outlined),
        const SizedBox(height: 8),
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
          const SizedBox(height: 4),
          _linkButton('Share last recording',
              () => Share.shareXFiles([XFile(_lastRecordingPath!)], text: 'SOS audio recording'),
              icon: Icons.ios_share_rounded),
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

  /// The countdown (with Cancel / Send now), then whether the safety team has
  /// the alert. A repeat SOS within a minute is the same alert (deduped) — it
  /// was sent; 429 means one already went.
  Widget _alertBanner() {
    final left = _countdown;
    if (left != null) {
      return Container(
        key: const ValueKey('sos-countdown'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Alerting our safety team in $left s…',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.red)),
          const SizedBox(height: 4),
          const Text('Opened SOS by mistake? Cancel now.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(
              key: const ValueKey('sos-cancel'),
              onPressed: _cancelCountdown,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              key: const ValueKey('sos-send-now'),
              onPressed: _sendNow,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(0, 48)),
              child: const Text('Send now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            )),
          ]),
        ]),
      );
    }
    if (_cancelled) {
      final grey = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
      return Container(
        key: const ValueKey('sos-alert-status'),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: grey.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.cancel_outlined, color: grey, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('SOS alert cancelled — nothing was sent.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: grey))),
          TextButton(
            key: const ValueKey('sos-send-anyway'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _sendNow,
            child: const Text('Send alert'),
          ),
        ]),
      );
    }
    final a = _alert;
    final sent = a?.sent;
    final color = sent == false ? Colors.red : (sent == true ? Colors.green[700]! : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7));
    final text = a == null ? 'Alerting our safety team…' : a.message;
    return Container(
      key: const ValueKey('sos-alert-status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(sent == false ? Icons.error_outline : (sent == true ? Icons.check_circle : Icons.sos),
            color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
        if (sent == false)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () { setState(() => _alert = null); _raiseAlert(); },
            child: const Text('Retry'),
          ),
      ]),
    );
  }

  Widget _actionCard(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return Material(
      color: active ? Colors.red.withValues(alpha: 0.1) : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? Colors.red : theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 26, color: active ? Colors.red : ink),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _moreCard(IconData icon, String title, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 20, color: theme.colorScheme.onSurface), const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))]),
            const SizedBox(height: 8),
            Text('Call Police, Record Audio, Siren, Call Safety Team',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
      ),
    );
  }
}

/// The text sent to contacts with the live-tracking link.
String sosShareMessage(String link) =>
    'I need help. Follow my Gora ride live here: $link';

/// An `sms:` link to [phones] (comma-separated; none opens the composer
/// without a recipient) with [body]. The body is percent-encoded by hand:
/// Uri.queryParameters writes spaces as "+", which SMS apps show literally.
Uri sosSmsUri(List<String> phones, String body) {
  final to = phones.map((p) => p.replaceAll(RegExp(r'[^0-9+]'), '')).where((p) => p.isNotEmpty).join(',');
  return Uri.parse('sms:$to?body=${Uri.encodeComponent(body)}');
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

/// What the SOS alert call came back with, in the rider's words.
class SosAlertStatus {
  /// True: the safety team has it. False: it did not go (retry).
  final bool sent;
  final String message;
  const SosAlertStatus(this.sent, this.message);
}

/// POST /support/sos-alert → {success, id, deduped?} or 429 RATE_LIMITED.
/// deduped (the same alert within the minute) and 429 (one was just sent)
/// both mean the team already has it.
SosAlertStatus sosAlertStatusOf(Map<String, dynamic> res) {
  if (res['success'] == true) {
    return const SosAlertStatus(true, 'Our safety team has been alerted with your ride and location.');
  }
  if (res['code'] == 'RATE_LIMITED' || res['httpStatus'] == 429) {
    return const SosAlertStatus(true, 'SOS already sent — our safety team has been alerted. If you are in danger, call 112.');
  }
  return const SosAlertStatus(false, 'Could not alert our safety team. Call 112 or the safety team below.');
}
