import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'home_screen.dart';
import 'rating_screen.dart';

// Hire a Driver — customer's own car, priced by hours (pickup time → drop time).
class HireDriverScreen extends StatefulWidget {
  const HireDriverScreen({super.key});
  @override
  State<HireDriverScreen> createState() => _HireDriverScreenState();
}

class _HireDriverScreenState extends State<HireDriverScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  double? _pickupLat, _pickupLng, _dropLat, _dropLng;
  DateTime? _startAt, _endAt;
  String _transmission = 'manual';
  String? _selectedVehicle;
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = false;
  String? _error;

  // Autocomplete
  List<Map<String, dynamic>> _pickSug = [], _dropSug = [];
  Timer? _debounce;
  // Map picker
  bool _showMap = false, _pickingPickup = true;
  LatLng _center = const LatLng(23.0225, 72.5714);
  GoogleMapController? _mapCtrl;
  String _mapAddr = '';
  // Live ride
  String? _rideId, _rideOtp;
  String _driverName = 'Driver', _driverPhone = '', _driverPic = '', _vModel = '', _vNumber = '';
  double _driverRating = 0;
  Timer? _poll;
  // Live hire status
  String _hirePhase = 'pending';
  double _hireActual = 0;
  int _hireBooked = 0;
  void Function(void Function())? _dialogSet;

  int get _totalHours {
    if (_startAt == null || _endAt == null) return 0;
    final h = _endAt!.difference(_startAt!).inMinutes / 60;
    return h <= 0 ? 0 : h.ceil();
  }

  @override
  void initState() { super.initState(); _initLocation(); }

  @override
  void dispose() { _poll?.cancel(); _debounce?.cancel(); _dialogSet = null; _pickupCtrl.dispose(); _dropCtrl.dispose(); super.dispose(); }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted) return;
    _pickupLat = pos.latitude; _pickupLng = pos.longitude;
    final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
    if (mounted && addr.isNotEmpty) setState(() => _pickupCtrl.text = addr);
  }

  void _search(String q, {required bool pickup}) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() { if (pickup) _pickSug = []; else _dropSug = []; }); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await ApiService.placesAutocomplete(q);
      if (mounted) setState(() { if (pickup) _pickSug = r; else _dropSug = r; });
    });
  }

  Future<void> _pickSuggestion(Map<String, dynamic> s, {required bool pickup}) async {
    final d = await ApiService.placeDetails(s['placeId'] as String? ?? '');
    if (d == null || !mounted) return;
    setState(() {
      if (pickup) { _pickupLat = (d['lat'] as num).toDouble(); _pickupLng = (d['lng'] as num).toDouble(); _pickupCtrl.text = d['address'] ?? ''; _pickSug = []; }
      else { _dropLat = (d['lat'] as num).toDouble(); _dropLng = (d['lng'] as num).toDouble(); _dropCtrl.text = d['address'] ?? ''; _dropSug = []; }
    });
  }

  Future<void> _loadFares() async {
    if (_pickupLat == null || _totalHours <= 0) { setState(() => _vehicles = []); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.post('/fare/estimate', {
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng, 'service': 'hire_driver', 'totalHours': _totalHours,
      });
      if (res['available'] != true) { setState(() { _loading = false; _error = (res['message'] ?? 'Not available').toString(); }); return; }
      setState(() {
        _vehicles = ((res['vehicles'] as List?) ?? []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
        _loading = false;
        _error = _vehicles.isEmpty ? 'No hire pricing configured for this zone' : null;
      });
    } catch (_) { setState(() { _loading = false; _error = 'Failed to load'; }); }
  }

  Future<void> _book() async {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    try {
      final res = await ApiService.bookRide({
        'pickupAddress': _pickupCtrl.text, 'dropAddress': _dropCtrl.text,
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng,
        'dropLat': _dropLat ?? _pickupLat, 'dropLng': _dropLng ?? _pickupLng,
        'service': 'hire_driver', 'vehicleType': _selectedVehicle,
        'fare': v['fare'] ?? 0, 'hirePerHour': v['perHour'] ?? 0,
        'hireTotalHours': _totalHours, 'transmission': _transmission,
        'hireStartAt': _startAt?.toIso8601String(), 'hireEndAt': _endAt?.toIso8601String(),
        'paymentMode': 'cash',
      });
      if (res['ride'] != null) { _rideId = res['ride']['id']?.toString(); _rideOtp = res['ride']['otp']?.toString(); }
    } catch (_) {}
  }

  void _startPolling() {
    _poll?.cancel();
    if (_rideId == null) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted) { t.cancel(); return; }
      try {
        final ride = await ApiService.getRide(_rideId!);
        final status = (ride['status'] ?? 'pending').toString();
        if (ride['driverName'] != null) _driverName = ride['driverName'].toString();
        if (ride['driverPhone'] != null) _driverPhone = ride['driverPhone'].toString();
        final dr = ride['driver'] as Map<String, dynamic>?;
        if (dr != null) {
          _vModel = (dr['vehicleModel'] ?? _vModel).toString();
          _vNumber = (dr['vehicleNumber'] ?? _vNumber).toString();
          final p = (dr['profilePicUrl'] ?? '').toString();
          if (p.isNotEmpty) _driverPic = AppConfig.imageUrl(p);
          if (dr['rating'] is num) _driverRating = (dr['rating'] as num).toDouble();
        }
        _hirePhase = (ride['hirePhase'] ?? _hirePhase).toString();
        _hireActual = (ride['hireActualHours'] as num?)?.toDouble() ?? _hireActual;
        _hireBooked = (ride['hireTotalHours'] as num?)?.toInt() ?? _hireBooked;
        _dialogSet?.call(() {});
        if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
          if (Navigator.canPop(context)) { Navigator.pop(context); _showAssigned(); }
        } else if (status == 'completed') {
          t.cancel(); if (!mounted) return;
          Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
          _showFinalBill(ride);
        }
      } catch (_) {}
    });
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = (isStart ? _startAt : _endAt) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { if (isStart) _startAt = dt; else _endAt = dt; });
    if (_totalHours > 0) _loadFares();
  }

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapPicker();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Hire a Driver'), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 1),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          _section('Pickup & Drop'),
          _locField(Icons.radio_button_checked, const Color(0xFF4CAF50), _pickupCtrl, 'Pickup location', pickup: true),
          ..._pickSug.map((s) => _sugTile(s, pickup: true)),
          const SizedBox(height: 8),
          _locField(Icons.location_on, const Color(0xFFFF5252), _dropCtrl, 'Drop location', pickup: false),
          ..._dropSug.map((s) => _sugTile(s, pickup: false)),

          const SizedBox(height: 16),
          _section('Pickup Time → Drop Time'),
          Row(children: [
            Expanded(child: _dtBtn('From', _startAt, () => _pickDateTime(isStart: true))),
            const SizedBox(width: 10),
            Expanded(child: _dtBtn('To', _endAt, () => _pickDateTime(isStart: false))),
          ]),
          if (_totalHours > 0) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('Total: $_totalHours hour${_totalHours > 1 ? 's' : ''} — driver paid for this duration',
              style: const TextStyle(fontSize: 13, color: Color(0xFF2196F3), fontWeight: FontWeight.w600))),

          const SizedBox(height: 16),
          _section('Car Transmission'),
          Row(children: [
            Expanded(child: _choice('Manual', 'manual')),
            const SizedBox(width: 10),
            Expanded(child: _choice('Automatic', 'automatic')),
          ]),

          const SizedBox(height: 16),
          _section('Select Vehicle Type'),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_error != null) _info(_error!)
          else if (_vehicles.isEmpty) _info('Set pickup + times to see hire prices')
          else ..._vehicles.map(_vehicleCard),
        ])),
        _bottomBar(),
      ]),
    );
  }

  Widget _bottomBar() {
    final ready = _selectedVehicle != null && _totalHours > 0 && _pickupLat != null;
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))]),
      child: SafeArea(top: false, child: SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: ready ? _showConfirm : null,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), disabledBackgroundColor: Colors.grey[300]),
        child: Text(ready ? 'Book Driver · ₹${v['fare'] ?? ''}' : 'Select time & vehicle', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
      ))),
    );
  }

  void _showConfirm() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
        return Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Confirm Hire', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _row('Vehicle', _selectedVehicle ?? ''),
            _row('Transmission', _transmission == 'manual' ? 'Manual' : 'Automatic'),
            _row('Duration', '$_totalHours hr'),
            _row('Rate', '₹${v['perHour'] ?? 0}/hr'),
            const Divider(),
            _row('Total', '₹${v['fare'] ?? 0}', bold: true),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _showFinding(); },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Confirm & Find Driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )),
          ]));
      });
  }

  void _showFinding() {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false,
      builder: (ctx) {
        () async { await _book(); _startPolling(); }();
        return Container(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF2196F3))),
          const SizedBox(height: 16), const Text('Finding your driver', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8), const Text('Connecting you with a nearby pilot', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _cancelSearch(ctx),
            icon: const Icon(Icons.close, color: Colors.red), label: const Text('Cancel Ride', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), side: const BorderSide(color: Colors.red)))),
        ]));
      });
  }

  // Cancel while searching — pick a reason then cancel the ride
  void _cancelSearch(BuildContext sheetCtx) {
    const reasons = ['Taking too long', 'Booked by mistake', 'Plan changed', 'Found another ride', 'Other'];
    showModalBottomSheet(context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (rc) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Why are you cancelling?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ...reasons.map((r) => ListTile(title: Text(r), onTap: () async {
          Navigator.pop(rc);
          _poll?.cancel();
          if (_rideId != null) await ApiService.cancelRide(_rideId!, r);
          if (mounted && Navigator.canPop(sheetCtx)) Navigator.pop(sheetCtx);
          if (mounted) Navigator.pop(context);
        })),
        const SizedBox(height: 8),
      ])));
  }

  void _showFinalBill(Map<String, dynamic> ride) {
    final base = (ride['fare'] as num?)?.toInt() ?? 0;
    final extra = (ride['hireExtraCharge'] as num?)?.toInt() ?? 0;
    final total = (ride['hireFinalFare'] as num?)?.toInt() ?? (base + extra);
    Widget r(String l, String v, {bool b = false, Color? c}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(fontSize: 14, fontWeight: b ? FontWeight.w800 : FontWeight.w500, color: c)),
        Text(v, style: TextStyle(fontSize: 14, fontWeight: b ? FontWeight.w800 : FontWeight.w600, color: c))]));
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Hire Bill', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          r('Booked', '${ride['hireTotalHours'] ?? 0} hr'),
          r('Worked', '${(ride['hireActualHours'] ?? 0).toStringAsFixed(1)} hr'),
          const Divider(),
          r('Base', '₹$base'),
          if (extra > 0) r('Overtime (${ride['hireExtraHours'] ?? 0}hr)', '₹$extra', c: Colors.orange),
          const Divider(),
          r('Total', '₹$total', b: true, c: const Color(0xFF1976D2)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(driverName: _driverName, vehicleName: _selectedVehicle ?? 'Hire', selectedTip: 0, rideId: _rideId))); },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Rate your trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
        ])));
  }

  void _showAssigned() {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        _dialogSet = setSheet;
        final inProgress = _hirePhase == 'ongoing' || _hirePhase == 'overtime';
        return Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(inProgress ? 'Hire in Progress' : 'Driver Assigned', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (inProgress) ...[
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _hirePhase == 'overtime' ? Colors.orange[50] : const Color(0xFF1976D2).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12), border: Border.all(color: _hirePhase == 'overtime' ? Colors.orange : const Color(0xFF1976D2).withOpacity(0.3))),
              child: Column(children: [
                Text('${_hireActual.toStringAsFixed(1)} hr', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _hirePhase == 'overtime' ? Colors.orange[800] : const Color(0xFF1976D2))),
                Text('of $_hireBooked hr booked', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (_hirePhase == 'overtime') const Padding(padding: EdgeInsets.only(top: 6), child: Text('⚠ Overtime — extra hours billed', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
              ])),
            const SizedBox(height: 12),
          ],
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF1976D2).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3))),
            child: Row(children: [const Icon(Icons.lock_outline, color: Color(0xFF1976D2)), const SizedBox(width: 10),
              const Expanded(child: Text('Share PIN with driver to start', style: TextStyle(fontSize: 12, color: Colors.black54))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1976D2))),
                child: Text(_rideOtp ?? '----', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1976D2)))),
            ])),
          const SizedBox(height: 14),
          Row(children: [
            CircleAvatar(radius: 26, backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
              backgroundImage: _driverPic.isNotEmpty ? NetworkImage(_driverPic) : null,
              child: _driverPic.isEmpty ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'D', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2196F3))) : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_driverName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Row(children: [const Icon(Icons.star, color: Colors.amber, size: 15), const SizedBox(width: 3),
                Text(_driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—', style: const TextStyle(fontSize: 12, color: Colors.grey))]),
              if (_vNumber.isNotEmpty) Text([_vModel, _vNumber].where((s) => s.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () { if (_driverPhone.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_driverName • $_driverPhone'))); },
            icon: const Icon(Icons.call, color: Colors.white), label: const Text('Call Driver', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), padding: const EdgeInsets.symmetric(vertical: 14)))),
          const SizedBox(height: 10),
          if (!inProgress) Center(child: TextButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
            child: const Text('Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)))),
        ]));
      }));
  }

  // ── Map picker ──
  Widget _buildMapPicker() {
    return Scaffold(backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => setState(() => _showMap = false)),
        title: Text(_pickingPickup ? 'Pick pickup' : 'Pick drop', style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)), centerTitle: true),
      body: Stack(children: [
        GoogleMap(initialCameraPosition: CameraPosition(target: _center, zoom: 14),
          onMapCreated: (c) => _mapCtrl = c, onCameraMove: (p) => _center = p.target,
          onCameraIdle: () async { final a = await ApiService.reverseGeocode(_center.latitude, _center.longitude); if (mounted) setState(() => _mapAddr = a); },
          myLocationEnabled: true, myLocationButtonEnabled: false, zoomControlsEnabled: false),
        const Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on, color: Color(0xFFFF5252), size: 48))),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_mapAddr.isEmpty ? 'Move map to set location' : _mapAddr, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _mapAddr.isEmpty ? null : () {
                setState(() {
                  if (_pickingPickup) { _pickupLat = _center.latitude; _pickupLng = _center.longitude; _pickupCtrl.text = _mapAddr; }
                  else { _dropLat = _center.latitude; _dropLng = _center.longitude; _dropCtrl.text = _mapAddr; }
                  _showMap = false;
                });
                if (_pickingPickup && _totalHours > 0) _loadFares();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
          ]))))]));
  }

  // ── Small builders ──
  Widget _section(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)));
  Widget _info(String t) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10)),
    child: Row(children: [Icon(Icons.info_outline, color: Colors.orange[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: Colors.orange[800])))]));

  Widget _locField(IconData i, Color c, TextEditingController ctrl, String hint, {required bool pickup}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
    child: Row(children: [Icon(i, color: c, size: 18), const SizedBox(width: 10),
      Expanded(child: TextField(controller: ctrl, onChanged: (q) => _search(q, pickup: pickup),
        decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12), hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14)), style: const TextStyle(fontSize: 14))),
      IconButton(icon: Icon(Icons.map, color: c, size: 20), onPressed: () => setState(() { _pickingPickup = pickup; _mapAddr = ''; _showMap = true; }))]));

  Widget _sugTile(Map<String, dynamic> s, {required bool pickup}) => ListTile(dense: true,
    leading: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 18),
    title: Text(s['mainText']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    subtitle: Text(s['secondaryText']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    onTap: () => _pickSuggestion(s, pickup: pickup));

  Widget _dtBtn(String label, DateTime? dt, VoidCallback onTap) => OutlinedButton(onPressed: onTap,
    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
    child: Column(children: [Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(dt == null ? 'Select' : '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]));

  Widget _choice(String label, String val) {
    final sel = _transmission == val;
    return GestureDetector(onTap: () => setState(() => _transmission = val),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: sel ? const Color(0xFF2196F3) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? const Color(0xFF2196F3) : Colors.grey[300]!)),
        child: Center(child: Text(label, style: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)))));
  }

  Widget _vehicleCard(Map<String, dynamic> v) {
    final sel = _selectedVehicle == v['name'];
    final raw = (v['imageUrl'] as String?) ?? '';
    final img = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    return GestureDetector(onTap: () => setState(() => _selectedVehicle = v['name'] as String?),
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? const Color(0xFF2196F3) : Colors.grey[200]!, width: sel ? 2 : 1)),
        child: Row(children: [
          SizedBox(width: 60, height: 44, child: img.isNotEmpty ? Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, color: Color(0xFF2196F3), size: 36)) : const Icon(Icons.directions_car, color: Color(0xFF2196F3), size: 36)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('₹${v['perHour'] ?? 0}/hr × $_totalHours hr', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (v['etaMin'] != null) Text('Driver ~${v['etaMin']} min away', style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
          ])),
          Text('₹${v['fare'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF2196F3))),
        ])));
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? const Color(0xFF1976D2) : null))]));
}
