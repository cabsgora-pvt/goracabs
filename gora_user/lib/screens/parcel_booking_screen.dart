import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'rating_screen.dart';

// Parcel / Delivery — sender books a driver to carry a package to a receiver.
// Two OTPs: pickup OTP (sender → driver to collect) + drop OTP (receiver → driver to hand over).
class ParcelBookingScreen extends StatefulWidget {
  const ParcelBookingScreen({super.key});
  @override
  State<ParcelBookingScreen> createState() => _ParcelBookingScreenState();
}

class _ParcelBookingScreenState extends State<ParcelBookingScreen> {
  final _pickupCtrl = TextEditingController(), _dropCtrl = TextEditingController();
  final _senderName = TextEditingController(), _senderPhone = TextEditingController();
  final _receiverName = TextEditingController(), _receiverPhone = TextEditingController();
  final _weight = TextEditingController();
  double? _pLat, _pLng, _dLat, _dLng;
  String _itemType = 'Documents';
  String _packageSize = 'S';
  bool _isFragile = false;
  bool _cod = false;
  final _itemValue = TextEditingController();
  final _codAmount = TextEditingController();
  final List<String> _photoUrls = [];   // relative urls of uploaded parcel photos
  bool _uploading = false;
  final _imgPicker = ImagePicker();
  String? _selectedVehicle;
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = false;
  String? _error;

  final _itemTypes = ['Documents', 'Electronics', 'Clothing', 'Food', 'Fragile', 'Other'];

  List<Map<String, dynamic>> _pickSug = [], _dropSug = [];
  Timer? _debounce;
  bool _showMap = false, _pickingPickup = true;
  LatLng _center = const LatLng(23.0225, 72.5714);
  GoogleMapController? _mapCtrl;
  String _mapAddr = '';

  String? _rideId, _pickupOtp, _dropOtp;
  String _driverName = 'Driver', _driverPhone = '', _driverPic = '', _vModel = '', _vNumber = '';
  double _driverRating = 0;
  String _deliveryPhase = 'pending';
  Timer? _poll;
  void Function(void Function())? _dialogSet;
  // Send / Receive tabs
  String _tab = 'Send';
  List<Map<String, dynamic>> _myParcels = [];
  bool _loadingParcels = false;

  @override
  void initState() { super.initState(); _initLocation(); }

  @override
  void dispose() { _poll?.cancel(); _debounce?.cancel(); _dialogSet = null;
    for (final c in [_pickupCtrl, _dropCtrl, _senderName, _senderPhone, _receiverName, _receiverPhone, _weight, _itemValue, _codAmount]) { c.dispose(); }
    super.dispose(); }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted) return;
    _pLat = pos.latitude; _pLng = pos.longitude;
    final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
    if (mounted && addr.isNotEmpty) setState(() => _pickupCtrl.text = addr);
    _loadFares();
  }

  void _search(String q, {required bool pickup}) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() { if (pickup) _pickSug = []; else _dropSug = []; }); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await ApiService.placesAutocomplete(q);
      if (mounted) setState(() { if (pickup) _pickSug = r; else _dropSug = r; });
    });
  }

  Future<void> _pick(Map<String, dynamic> s, {required bool pickup}) async {
    final d = await ApiService.placeDetails(s['placeId'] as String? ?? '');
    if (d == null || !mounted) return;
    setState(() {
      if (pickup) { _pLat = (d['lat'] as num).toDouble(); _pLng = (d['lng'] as num).toDouble(); _pickupCtrl.text = d['address'] ?? ''; _pickSug = []; }
      else { _dLat = (d['lat'] as num).toDouble(); _dLng = (d['lng'] as num).toDouble(); _dropCtrl.text = d['address'] ?? ''; _dropSug = []; }
    });
    _loadFares();
  }

  Future<void> _loadFares() async {
    if (_pLat == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.estimateFare(
        pickupLat: _pLat!, pickupLng: _pLng!, dropLat: _dLat, dropLng: _dLng, service: 'delivery',
        weightKg: double.tryParse(_weight.text) ?? 0);
      if (res['available'] != true || res['vehicles'] is! List) { setState(() { _loading = false; _error = (res['message'] ?? 'Delivery not available here').toString(); }); return; }
      setState(() {
        _vehicles = (res['vehicles'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
        _loading = false;
        _error = _vehicles.isEmpty ? 'No delivery pricing configured for this zone' : null;
      });
    } catch (_) { setState(() { _loading = false; _error = 'Failed to load'; }); }
  }

  Future<void> _book() async {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    try {
      final res = await ApiService.bookRide({
        'pickupAddress': _pickupCtrl.text, 'dropAddress': _dropCtrl.text,
        'pickupLat': _pLat, 'pickupLng': _pLng, 'dropLat': _dLat ?? _pLat, 'dropLng': _dLng ?? _pLng,
        'service': 'delivery', 'vehicleType': _selectedVehicle, 'fare': v['fare'] ?? 0,
        'senderName': _senderName.text, 'senderPhone': _senderPhone.text,
        'receiverName': _receiverName.text, 'receiverPhone': _receiverPhone.text,
        'itemType': _itemType, 'weightKg': double.tryParse(_weight.text) ?? 0,
        'packageSize': _packageSize, 'isFragile': _isFragile,
        'itemValue': double.tryParse(_itemValue.text) ?? 0,
        'codAmount': _cod ? (double.tryParse(_codAmount.text) ?? 0) : 0,
        'parcelPhotos': _photoUrls,
        'paymentMode': _cod ? 'cod' : 'cash',
      });
      if (res['ride'] != null) { _rideId = res['ride']['id']?.toString(); _pickupOtp = res['ride']['otp']?.toString(); _dropOtp = res['ride']['dropOtp']?.toString(); }
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
          _vModel = (dr['vehicleModel'] ?? _vModel).toString(); _vNumber = (dr['vehicleNumber'] ?? _vNumber).toString();
          final p = (dr['profilePicUrl'] ?? '').toString(); if (p.isNotEmpty) _driverPic = AppConfig.imageUrl(p);
          if (dr['rating'] is num) _driverRating = (dr['rating'] as num).toDouble();
        }
        if (ride['dropOtp'] != null) _dropOtp = ride['dropOtp'].toString();
        _deliveryPhase = (ride['deliveryPhase'] ?? _deliveryPhase).toString();
        _dialogSet?.call(() {});
        if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
          if (Navigator.canPop(context)) { Navigator.pop(context); _showAssigned(); }
        } else if (status == 'completed') {
          t.cancel(); if (!mounted) return;
          Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
          Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(driverName: _driverName, vehicleName: _selectedVehicle ?? 'Delivery', selectedTip: 0, rideId: _rideId)));
        }
      } catch (_) {}
    });
  }

  Future<void> _addPhoto() async {
    final x = await _imgPicker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (x == null) return;
    setState(() => _uploading = true);
    final url = await ApiService.uploadImage(x);
    if (!mounted) return;
    setState(() { if (url != null) _photoUrls.add(url); _uploading = false; });
  }

  bool get _formValid => _pLat != null && _dLat != null && _selectedVehicle != null
      && _senderName.text.isNotEmpty && _senderPhone.text.isNotEmpty
      && _receiverName.text.isNotEmpty && _receiverPhone.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapPicker();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Gora Parcel', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0),
      body: Column(children: [
        // Send / Receive tabs
        Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(child: _tabBtn('Send', 'Send Parcel')),
            const SizedBox(width: 12),
            Expanded(child: _tabBtn('Receive', 'Track Parcel')),
          ])),
        Expanded(child: _tab == 'Send' ? _buildSend() : _buildReceive()),
      ]),
    );
  }

  Widget _tabBtn(String tab, String label) {
    final sel = _tab == tab;
    return GestureDetector(onTap: () { setState(() => _tab = tab); if (tab == 'Receive') _loadMyParcels(); },
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: sel ? AppTheme.primaryBlue : Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? AppTheme.primaryBlue : Colors.grey[300]!)),
        child: Center(child: Text(label, style: TextStyle(color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)))));
  }

  Future<void> _loadMyParcels() async {
    setState(() => _loadingParcels = true);
    try {
      final res = await ApiService.getMyRides();
      final list = (res['rides'] as List?) ?? [];
      setState(() {
        _myParcels = list.where((r) => (r['service'] ?? '') == 'delivery').map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loadingParcels = false;
      });
    } catch (_) { setState(() => _loadingParcels = false); }
  }

  Widget _buildReceive() {
    if (_loadingParcels) return const Center(child: CircularProgressIndicator());
    if (_myParcels.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.local_shipping, size: 64, color: Colors.grey[300]), const SizedBox(height: 12),
      Text('No parcels yet', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
      const SizedBox(height: 4), Text('Your sent parcels appear here for tracking', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
    ]));
    return ListView(padding: const EdgeInsets.all(16), children: _myParcels.map((p) {
      final status = (p['status'] ?? '').toString();
      final phase = (p['deliveryPhase'] ?? '').toString();
      final done = status == 'completed' || phase == 'delivered';
      return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: done ? Colors.green[50] : Colors.blue[50], borderRadius: BorderRadius.circular(6)),
              child: Text(done ? 'DELIVERED' : (phase.isNotEmpty ? phase.toUpperCase() : status.toUpperCase()),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: done ? Colors.green : AppTheme.primaryBlue))),
            const Spacer(),
            Text('₹${p['totalFare'] ?? p['fare'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          ]),
          const SizedBox(height: 8),
          Text('${p['itemType'] ?? 'Parcel'} → ${p['receiverName'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Text('${p['pickupAddress'] ?? ''} → ${p['dropAddress'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (p['driverName'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Driver: ${p['driverName']}', style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ]));
    }).toList());
  }

  Widget _buildSend() {
    return Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          _title('Delivery Route'),
          _locField(Icons.radio_button_checked, const Color(0xFF4CAF50), _pickupCtrl, 'Pickup location', pickup: true),
          ..._pickSug.map((s) => _sugTile(s, pickup: true)),
          const SizedBox(height: 8),
          _locField(Icons.location_on, const Color(0xFFFF5252), _dropCtrl, 'Drop location', pickup: false),
          ..._dropSug.map((s) => _sugTile(s, pickup: false)),

          const SizedBox(height: 16), _title('Parcel Details'),
          Wrap(spacing: 8, runSpacing: 8, children: _itemTypes.map(_chip).toList()),
          const SizedBox(height: 12),
          _field('Weight (approx. kg)', _weight, Icons.fitness_center, num: true, onChange: _loadFares),
          const SizedBox(height: 12),
          // Package size
          Row(children: [
            const Text('Size:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), const SizedBox(width: 10),
            ...['S', 'M', 'L'].map((s) => Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () => setState(() => _packageSize = s),
              child: Container(width: 40, height: 36, alignment: Alignment.center,
                decoration: BoxDecoration(color: _packageSize == s ? AppTheme.primaryBlue : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _packageSize == s ? AppTheme.primaryBlue : Colors.grey[300]!)),
                child: Text(s, style: TextStyle(color: _packageSize == s ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)))))),
          ]),
          const SizedBox(height: 10),
          // Fragile + COD toggles
          Row(children: [
            Expanded(child: _toggleTile('Fragile', Icons.warning_amber, _isFragile, (v) => setState(() => _isFragile = v))),
            const SizedBox(width: 8),
            Expanded(child: _toggleTile('COD', Icons.payments, _cod, (v) => setState(() => _cod = v))),
          ]),
          const SizedBox(height: 10),
          _field('Item value ₹ (for insurance)', _itemValue, Icons.shield, num: true),
          if (_cod) ...[const SizedBox(height: 10), _field('COD amount ₹ (receiver pays)', _codAmount, Icons.account_balance_wallet, num: true)],
          const SizedBox(height: 12),
          // Parcel photos
          _title('Parcel Photos (proof)'),
          SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal, children: [
            ..._photoUrls.map((u) => Container(width: 84, height: 84, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), image: DecorationImage(image: NetworkImage(AppConfig.imageUrl(u)), fit: BoxFit.cover)))),
            GestureDetector(onTap: _uploading ? null : _addPhoto, child: Container(width: 84, height: 84,
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[300]!)),
              child: _uploading ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.add_a_photo, color: AppTheme.primaryBlue, size: 28))),
          ])),

          const SizedBox(height: 16), _title('Sender'),
          _field('Sender name', _senderName, Icons.person_outline),
          const SizedBox(height: 10),
          _field('Sender phone', _senderPhone, Icons.phone_android, phone: true),

          const SizedBox(height: 16), _title('Receiver'),
          _field('Receiver name', _receiverName, Icons.person),
          const SizedBox(height: 10),
          _field('Receiver phone', _receiverPhone, Icons.phone, phone: true),

          const SizedBox(height: 16), _title('Choose Vehicle'),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_error != null) _info(_error!)
          else if (_vehicles.isEmpty) _info('Enter pickup to see delivery vehicles')
          else ..._vehicles.map(_vehicleCard),
          const SizedBox(height: 16),
        ])),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))]),
          child: SafeArea(top: false, child: SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _formValid ? _showConfirm : null,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 16), disabledBackgroundColor: Colors.grey[300]),
            child: const Text('Proceed to Book', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)))))),
      ]);
  }

  void _showConfirm() {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Confirm Parcel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _row('Item', _itemType), _row('Vehicle', _selectedVehicle ?? ''),
          _row('From', _senderName.text), _row('To', _receiverName.text),
          const Divider(),
          _row('Total', '₹${v['fare'] ?? 0}', bold: true),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _showFinding(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Confirm & Find Driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
        ])));
  }

  void _showFinding() {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, builder: (ctx) {
      () async { await _book(); _startPolling(); }();
      return Container(padding: const EdgeInsets.all(28), child: const Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryBlue)),
        SizedBox(height: 16), Text('Finding delivery partner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 8), Text('Connecting you with a nearby rider', style: TextStyle(fontSize: 13, color: Colors.grey)),
      ]));
    });
  }

  void _showAssigned() {
    showModalBottomSheet(context: context, isDismissible: false, enableDrag: false, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        _dialogSet = setSheet;
        final collected = _deliveryPhase == 'in_transit';
        return Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(collected ? 'Parcel in Transit' : 'Delivery Partner Assigned', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Two OTPs — pickup (sender) shown until collected, then drop (receiver)
          _otpBox(collected ? 'DELIVERY OTP — receiver shares to confirm handover' : 'PICKUP OTP — give to driver to collect',
            collected ? (_dropOtp ?? '----') : (_pickupOtp ?? '----')),
          const SizedBox(height: 14),
          Row(children: [
            CircleAvatar(radius: 26, backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
              backgroundImage: _driverPic.isNotEmpty ? NetworkImage(_driverPic) : null,
              child: _driverPic.isEmpty ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'D', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)) : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_driverName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Row(children: [const Icon(Icons.star, color: Colors.amber, size: 15), const SizedBox(width: 3),
                Text(_driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—', style: const TextStyle(fontSize: 12, color: Colors.grey))]),
              if (_vNumber.isNotEmpty) Text([_vModel, _vNumber].where((s) => s.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: () { if (_driverPhone.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_driverName • $_driverPhone'))); },
              icon: const Icon(Icons.call, color: Colors.white), label: const Text('Call', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), padding: const EdgeInsets.symmetric(vertical: 14)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () { if (_rideId != null) Share.share('Track my parcel live: ${AppConfig.serverBaseUrl}/track/$_rideId'); },
              icon: const Icon(Icons.share, color: Colors.white), label: const Text('Share', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14)))),
          ]),
          const SizedBox(height: 10),
          Center(child: TextButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
            child: const Text('Close', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)))),
        ]));
      }));
  }

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
                  if (_pickingPickup) { _pLat = _center.latitude; _pLng = _center.longitude; _pickupCtrl.text = _mapAddr; }
                  else { _dLat = _center.latitude; _dLng = _center.longitude; _dropCtrl.text = _mapAddr; }
                  _showMap = false;
                });
                _loadFares();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))),
          ]))))]));
  }

  // ── builders ──
  Widget _title(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)));
  Widget _info(String t) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10)),
    child: Row(children: [Icon(Icons.info_outline, color: Colors.orange[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: Colors.orange[800])))]));

  Widget _otpBox(String label, String otp) => Container(padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFF1976D2).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3))),
    child: Row(children: [const Icon(Icons.lock_outline, color: Color(0xFF1976D2)), const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54))),
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1976D2))),
        child: Text(otp, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF1976D2))))]));

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
    onTap: () => _pick(s, pickup: pickup));

  Widget _chip(String t) {
    final sel = _itemType == t;
    return GestureDetector(onTap: () => setState(() => _itemType = t),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: sel ? AppTheme.primaryBlue : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppTheme.primaryBlue : Colors.grey[300]!)),
        child: Text(t, style: TextStyle(color: sel ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600))));
  }

  Widget _field(String hint, TextEditingController ctrl, IconData icon, {bool num = false, bool phone = false, VoidCallback? onChange}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
    child: Row(children: [Icon(icon, color: Colors.grey[600], size: 18), const SizedBox(width: 10),
      Expanded(child: TextField(controller: ctrl, onChanged: (_) { setState(() {}); onChange?.call(); },
        keyboardType: num ? TextInputType.number : phone ? TextInputType.phone : TextInputType.text,
        decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12), hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14)), style: const TextStyle(fontSize: 14)))]));

  Widget _vehicleCard(Map<String, dynamic> v) {
    final sel = _selectedVehicle == v['name'];
    final raw = (v['imageUrl'] as String?) ?? '';
    final img = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    return GestureDetector(onTap: () => setState(() => _selectedVehicle = v['name'] as String?),
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? AppTheme.primaryBlue : Colors.grey[200]!, width: sel ? 2 : 1)),
        child: Row(children: [
          SizedBox(width: 60, height: 44, child: img.isNotEmpty ? Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.local_shipping, color: AppTheme.primaryBlue, size: 34)) : const Icon(Icons.local_shipping, color: AppTheme.primaryBlue, size: 34)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (v['etaMin'] != null) Text('Pickup in ~${v['etaMin']} min', style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
          ])),
          Text('₹${v['fare'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.primaryBlue)),
        ])));
  }

  Widget _toggleTile(String label, IconData icon, bool val, ValueChanged<bool> onChanged) => GestureDetector(
    onTap: () => onChanged(!val),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: val ? AppTheme.primaryBlue.withOpacity(0.08) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: val ? AppTheme.primaryBlue : Colors.grey[300]!)),
      child: Row(children: [Icon(icon, size: 16, color: val ? AppTheme.primaryBlue : Colors.grey), const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: val ? AppTheme.primaryBlue : Colors.black87)),
        const Spacer(), Icon(val ? Icons.check_circle : Icons.circle_outlined, size: 16, color: val ? AppTheme.primaryBlue : Colors.grey)])));

  Widget _row(String l, String v, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? const Color(0xFF1976D2) : null))]));
}
