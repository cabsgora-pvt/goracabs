import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'rating_screen.dart';

// Generic live-tracking screen for ANY active ride (taxi/rental/outstation/hire/delivery).
// Shows status, OTP, driver card, live driver map + ETA, and cancel.
class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});
  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  Map<String, dynamic>? _ride;
  LatLng? _driverLatLng;
  double _driverHeading = 0;
  int? _etaMin;
  Timer? _statusPoll, _locPoll;

  @override
  void initState() { super.initState(); _poll(); _statusPoll = Timer.periodic(const Duration(seconds: 3), (_) => _poll()); _locPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loc()); }

  @override
  void dispose() { _statusPoll?.cancel(); _locPoll?.cancel(); super.dispose(); }

  Future<void> _poll() async {
    try {
      final r = await ApiService.getRide(widget.rideId);
      if (!mounted) return;
      final status = (r['status'] ?? '').toString();
      if (status == 'completed') {
        _statusPoll?.cancel(); _locPoll?.cancel();
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RatingScreen(
          driverName: (r['driverName'] ?? 'Driver').toString(), vehicleName: (r['vehicleType'] ?? '').toString(), selectedTip: 0, rideId: widget.rideId)));
        return;
      }
      if (status == 'cancelled') { _statusPoll?.cancel(); _locPoll?.cancel(); if (mounted) Navigator.pop(context); return; }
      setState(() => _ride = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  Future<void> _loc() async {
    try {
      final res = await ApiService.getDriverLocation(widget.rideId);
      final d = res['driver'] as Map<String, dynamic>?;
      if (d == null || d['lat'] == null || _ride == null) return;
      final la = (d['lat'] as num).toDouble(), ln = (d['lng'] as num).toDouble();
      final ongoing = (_ride!['status'] ?? '') == 'ongoing';
      final destLat = (ongoing ? _ride!['dropLat'] : _ride!['pickupLat']) as num?;
      final destLng = (ongoing ? _ride!['dropLng'] : _ride!['pickupLng']) as num?;
      if (destLat != null) {
        final dir = await ApiService.getDirections(originLat: la, originLng: ln, destLat: destLat.toDouble(), destLng: destLng!.toDouble());
        _etaMin = (dir['durationMin'] as num?)?.toInt();
      }
      if (!mounted) return;
      setState(() { _driverLatLng = LatLng(la, ln); _driverHeading = (d['heading'] as num?)?.toDouble() ?? 0; });
    } catch (_) {}
  }

  void _cancel() {
    showDialog(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Cancel ride?'),
      content: const Text('Are you sure you want to cancel this ride?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('No')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async { Navigator.pop(dctx); await ApiService.cancelRide(widget.rideId, 'Cancelled by rider'); if (mounted) Navigator.pop(context); },
          child: const Text('Yes, cancel', style: TextStyle(color: Colors.white))),
      ]));
  }

  // Share live trip details (driver + live location link) with anyone
  void _shareTrip(Map<String, dynamic> r) {
    final dr = r['driver'] as Map<String, dynamic>?;
    final name = (dr?['name'] ?? r['driverName'] ?? 'Driver').toString();
    final veh = [dr?['vehicleModel'], dr?['vehicleNumber']].where((s) => (s as String?)?.isNotEmpty == true).join(' ');
    final phone = (r['driverPhone'] ?? dr?['phone'] ?? '').toString();
    final otp = (r['otp'] ?? '').toString();
    String loc = '';
    if (_driverLatLng != null) {
      loc = '\nLive location: https://www.google.com/maps/search/?api=1&query=${_driverLatLng!.latitude},${_driverLatLng!.longitude}';
    }
    final msg = 'I\'m on a Gora ride 🚖\n'
        'Driver: $name${veh.isNotEmpty ? ' ($veh)' : ''}\n'
        '${phone.isNotEmpty ? 'Driver phone: $phone\n' : ''}'
        'From: ${r['pickupAddress'] ?? ''}\nTo: ${r['dropAddress'] ?? ''}'
        '${otp.isNotEmpty ? '\nOTP: $otp' : ''}'
        '$loc';
    Share.share(msg, subject: 'Track my Gora ride');
  }

  // Emergency: share live location to contacts + show emergency number
  void _sos(Map<String, dynamic> r) {
    showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: const [Icon(Icons.sos, color: Colors.red), SizedBox(width: 8), Text('Emergency')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Emergency helpline: 112', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Share your live ride location with family/police immediately.', style: TextStyle(fontSize: 13)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Close')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () { Navigator.pop(dctx); _shareTrip(r); },
          icon: const Icon(Icons.share_location, color: Colors.white, size: 18),
          label: const Text('Share live location', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final status = (r['status'] ?? '').toString();
    final otp = (r['otp'] ?? '').toString();
    final dr = r['driver'] as Map<String, dynamic>?;
    final pic = (dr?['profilePicUrl'] ?? '').toString();
    final pLat = (r['pickupLat'] as num?)?.toDouble() ?? 0, pLng = (r['pickupLng'] as num?)?.toDouble() ?? 0;
    final dLat = (r['dropLat'] as num?)?.toDouble() ?? 0, dLng = (r['dropLng'] as num?)?.toDouble() ?? 0;
    final label = {'pending': 'Finding your driver…', 'accepted': 'Driver on the way', 'arrived': 'Driver has arrived', 'ongoing': 'Trip in progress'}[status] ?? status;
    final svc = (r['service'] ?? 'taxi').toString();
    final vt = (r['vehicleType'] ?? '').toString().toLowerCase();
    IconData svcIcon = Icons.directions_car;
    if (svc == 'delivery') svcIcon = Icons.local_shipping;
    else if (svc == 'outstation') svcIcon = Icons.map;
    else if (svc == 'rental') svcIcon = Icons.access_time_filled;
    else if (svc == 'hire_driver') svcIcon = Icons.person_pin_circle;
    else if (vt.contains('bike')) svcIcon = Icons.two_wheeler;
    else if (vt.contains('auto')) svcIcon = Icons.electric_rickshaw;
    else if (vt.contains('suv')) svcIcon = Icons.airport_shuttle;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [Icon(svcIcon, size: 20), const SizedBox(width: 8), const Text('Your Ride')]),
        elevation: 1,
        actions: [
          IconButton(tooltip: 'Share trip', onPressed: () => _shareTrip(r), icon: const Icon(Icons.share)),
          IconButton(tooltip: 'SOS', onPressed: () => _sos(r), icon: const Icon(Icons.sos, color: Colors.red)),
        ]),
      body: Column(children: [
        SizedBox(height: 280, child: GoogleMap(
          initialCameraPosition: CameraPosition(target: _driverLatLng ?? LatLng(pLat, pLng), zoom: 13),
          markers: {
            Marker(markerId: const MarkerId('p'), position: LatLng(pLat, pLng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
            Marker(markerId: const MarkerId('d'), position: LatLng(dLat, dLng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
            if (_driverLatLng != null) Marker(markerId: const MarkerId('drv'), position: _driverLatLng!, rotation: _driverHeading, flat: true, anchor: const Offset(0.5, 0.5), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
          },
          zoomControlsEnabled: false, myLocationButtonEnabled: false)),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            if (_etaMin != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('$_etaMin min', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          if (otp.isNotEmpty && status != 'ongoing') Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1C2656).withOpacity(0.3))),
            child: Row(children: [const Icon(Icons.lock_outline, color: Color(0xFF1C2656)), const SizedBox(width: 10),
              const Expanded(child: Text('Share PIN with driver to start', style: TextStyle(fontSize: 12, color: Colors.black54))),
              Text(otp, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1C2656)))])),
          const SizedBox(height: 12),
          if (dr != null) Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[200]!)),
            child: Row(children: [
              CircleAvatar(radius: 26, backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                backgroundImage: pic.isNotEmpty ? NetworkImage(AppConfig.imageUrl(pic)) : null,
                child: pic.isEmpty ? Text((dr['name'] ?? 'D').toString()[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)) : null),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((dr['name'] ?? 'Driver').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text([dr['vehicleModel'], dr['vehicleNumber']].where((s) => (s as String?)?.isNotEmpty == true).join(' • '), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
              IconButton(onPressed: () { final ph = (r['driverPhone'] ?? '').toString(); if (ph.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ph))); }, icon: const Icon(Icons.call, color: Colors.green)),
            ])),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [const Icon(Icons.radio_button_checked, size: 14, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text((r['pickupAddress'] ?? '').toString(), style: const TextStyle(fontSize: 12)))])),
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text((r['dropAddress'] ?? '').toString(), style: const TextStyle(fontSize: 12)))])),
        ])),
        // Sticky bottom — Cancel always visible while the ride is active
        if (status != 'completed' && status != 'cancelled')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2))]),
            child: SafeArea(top: false, child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('Cancel Ride', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
            ))),
          ),
      ]),
    );
  }
}
