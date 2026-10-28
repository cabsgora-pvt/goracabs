import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../utils/vehicle_marker.dart';
import '../utils/map_markers.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/ride_booking.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'active_ride_screen.dart';

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
  double? _pLat, _pLng, _dLat, _dLng;
  /// What is being sent — one tap, required before booking.
  String? _itemType;
  /// Set once the rider opens the sender sheet: from then on their own text
  /// wins over the profile prefill.
  bool _senderTouched = false;
  String _packageSize = 'S';
  bool _isFragile = false;
  bool _cod = false;
  String _paymentMode = 'cash';
  String _couponCode = '';
  int _couponDiscount = 0;
  DateTime? _scheduledAt;   // null = deliver now
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
  static const _itemIcons = <String, IconData>{
    'Documents': Icons.description_outlined, 'Electronics': Icons.devices_other_outlined,
    'Clothing': Icons.checkroom_outlined, 'Food': Icons.restaurant_outlined,
    'Fragile': Icons.wine_bar_outlined, 'Other': Icons.category_outlined,
  };

  List<Map<String, dynamic>> _pickSug = [], _dropSug = [];
  Timer? _debounce;
  bool _showMap = false, _pickingPickup = true;
  LatLng _center = const LatLng(23.0225, 72.5714);
  GoogleMapController? _mapCtrl;
  String _mapAddr = '';

  // A parcel booked here is tracked on ActiveRideScreen (see _confirmParcel),
  // so this screen holds no live ride state.

  // Send / Receive tabs
  String _tab = 'Send';
  List<Map<String, dynamic>> _myParcels = [];
  bool _loadingParcels = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  /// The sender is almost always the rider: prefill from their profile (and
  /// again when the profile finishes loading) unless they have edited it.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = Provider.of<UserProvider>(context);
    if (_senderTouched) return;
    if (_senderName.text.isEmpty && u.name.isNotEmpty) _senderName.text = u.name;
    if (_senderPhone.text.isEmpty && u.phone.isNotEmpty) _senderPhone.text = u.phone;
  }

  @override
  void dispose() { _debounce?.cancel();
    for (final c in [_pickupCtrl, _dropCtrl, _senderName, _senderPhone, _receiverName, _receiverPhone, _itemValue, _codAmount]) { c.dispose(); }
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
        // Ola / Rapido style: no weight selection and no per-kg charge — the
        // parcel limits line covers weight, so the server's perKg term adds 0.
        weightKg: 0);
      if (res['available'] != true || res['vehicles'] is! List) { setState(() { _loading = false; _error = (res['message'] ?? 'Delivery not available here').toString(); }); return; }
      setState(() {
        _vehicles = (res['vehicles'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
        _loading = false;
        _error = _vehicles.isEmpty ? 'No delivery pricing configured for this zone' : null;
      });
    } catch (_) { setState(() { _loading = false; _error = 'Failed to load'; }); }
  }

  /// Books the parcel and returns the server's answer; [bookAndTrack] reports a
  /// failure and opens the live ride screen on success.
  Future<Map<String, dynamic>> _book() async {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    final num fare = (v['fare'] as num?) ?? 0;
    return ApiService.bookRide({
        'pickupAddress': _pickupCtrl.text, 'dropAddress': _dropCtrl.text,
        'pickupLat': _pLat, 'pickupLng': _pLng, 'dropLat': _dLat ?? _pLat, 'dropLng': _dLng ?? _pLng,
        'service': 'delivery', 'vehicleType': _selectedVehicle, 'fare': (fare - _couponDiscount).clamp(0, fare),
        'quoteToken': v['quoteToken'],
        'senderName': _senderName.text, 'senderPhone': _senderPhone.text,
        'receiverName': _receiverName.text, 'receiverPhone': _receiverPhone.text,
        'itemType': _itemType, 'weightKg': 0,
        'packageSize': _packageSize, 'isFragile': _isFragile,
        'itemValue': double.tryParse(_itemValue.text) ?? 0,
        'codAmount': _cod ? (double.tryParse(_codAmount.text) ?? 0) : 0,
        'parcelPhotos': _photoUrls,
        'scheduledAt': _scheduledAt?.toIso8601String(),
        // 'cash', not 'cod'. The server only accepts cash / wallet / online, so
        // every parcel booked with COD on failed validation — and the failure was
        // swallowed, leaving the sender on "Finding your driver" for a parcel
        // that was never booked. With COD on, the fare has always been charged
        // as cash; the booking now says the same thing.
        'paymentMode': _cod ? 'cash' : _paymentMode,
        'couponCode': _couponCode,
        'couponDiscount': _couponDiscount,
      });
  }

  /// Book once, from the button — never from a sheet builder — then track the
  /// parcel on the live ride screen. The coupon is stored with the ride: the
  /// server keeps a parcel's full quoted fare, so the discount is applied when
  /// the ride is charged.
  Future<void> _confirmParcel() => bookAndTrack(
    context,
    book: _book,
    couponDiscount: _couponDiscount,
  );

  /// A parcel the rider sent opens on the live ride screen, like any ride.
  void _openSentParcel(Map<String, dynamic> p) {
    final id = (p['_id'] ?? p['id'] ?? '').toString();
    if (id.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: id)))
        .then((_) { if (mounted) _loadMyParcels(); });
  }

  Future<void> _addPhoto() async {
    final x = await _imgPicker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (x == null) return;
    setState(() => _uploading = true);
    final url = await ApiService.uploadImage(x);
    if (!mounted) return;
    setState(() { if (url != null) _photoUrls.add(url); _uploading = false; });
  }

  bool get _formValid => _pLat != null && _dLat != null && _selectedVehicle != null && _itemType != null
      && _senderName.text.isNotEmpty && _senderPhone.text.isNotEmpty
      && _receiverName.text.isNotEmpty && _receiverPhone.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapPicker();
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(children: [
        const ServiceBackBar(),
        Expanded(child: _tab == 'Send' ? _buildSend() : _buildReceive()),
      ]),
    );
  }

  /// Title and the Send / Receive choice — the first thing in either tab's list.
  Widget _top() {
    final send = _tab == 'Send';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ServiceTitle(
        title: send ? 'Send a parcel' : 'Receive a parcel',
        subtitle: send ? 'Door-to-door delivery within the city' : 'Parcels you sent and parcels coming to you',
      ),
      ChoiceSegment<String>(
        options: const [
          ChoiceOption('Send', 'Send Parcel', subtitle: 'Send within city limit', icon: Icons.north_east),
          ChoiceOption('Receive', 'Receive Parcel', subtitle: 'Get parcel within city limit', icon: Icons.south_west),
        ],
        selected: _tab,
        onChanged: (tab) { setState(() => _tab = tab); if (tab == 'Receive') _loadMyParcels(); },
      ),
      const SizedBox(height: 16),
    ]);
  }

  List<Map<String, dynamic>> _incoming = [];
  Future<void> _loadMyParcels() async {
    setState(() => _loadingParcels = true);
    try {
      final sent = await ApiService.getMyRides();
      final inc = await ApiService.getIncomingParcels();
      if (!mounted) return;
      setState(() {
        _myParcels = ((sent['rides'] as List?) ?? []).where((r) => (r['service'] ?? '') == 'delivery').map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r as Map)).toList();
        _incoming = ((inc['rides'] as List?) ?? []).map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loadingParcels = false;
      });
    } catch (_) { setState(() => _loadingParcels = false); }
  }

  Widget _buildReceive() {
    const pad = EdgeInsets.fromLTRB(16, 4, 16, 16);
    if (_loadingParcels) return ListView(padding: pad, children: [_top(), const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
    if (_myParcels.isEmpty && _incoming.isEmpty) return ListView(padding: pad, children: [_top(), const SizedBox(height: 40), Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
        child: Icon(Icons.local_shipping_outlined, size: 34, color: RideUi.muted(context))),
      const SizedBox(height: 14),
      Text('No parcels yet', style: RideUi.title(context, size: 17)),
      const SizedBox(height: 4), Text('Sent & incoming parcels appear here', style: RideUi.caption(context, size: 13)),
    ])]);
    return ListView(padding: pad, children: [
      _top(),
      if (_incoming.isNotEmpty) ...[
        const ServiceSection('Incoming to you', top: 8),
        ..._incoming.map((p) => _parcelTile(p, incoming: true)),
        const SizedBox(height: 16),
      ],
      if (_myParcels.isNotEmpty)
        const ServiceSection('Sent by you', top: 8),
      ..._myParcels.map((p) => _parcelTile(p, incoming: false)),
    ]);
  }

  Widget _parcelTile(Map<String, dynamic> p, {required bool incoming}) {
      final status = (p['status'] ?? '').toString();
      final phase = (p['deliveryPhase'] ?? '').toString();
      // A returned parcel is finished, but it is NOT delivered. Both used to
      // fall under `done`, so a parcel that came back to the sender showed them
      // a green DELIVERED badge — the one thing they most need to not be told.
      final returned = phase == 'returned' || phase == 'failed';
      final delivered = !returned && (phase == 'delivered' || status == 'completed');
      final done = delivered || returned;
      final active = !done && (status == 'accepted' || status == 'arrived' || status == 'ongoing');
      final failReason = (p['failReason'] ?? '').toString();
      return GestureDetector(
        // The receiver is not the ride's rider: they get the view-only tracker,
        // without cancel or payment. The sender gets the full ride screen.
        onTap: active ? () => incoming ? _trackLive(p) : _openSentParcel(p) : null,
        child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(RideUi.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: returned ? Colors.orange[50] : (delivered ? Colors.green[50] : Colors.blue[50]),
                borderRadius: BorderRadius.circular(6)),
              child: Text(
                returned ? 'RETURNED' : (delivered ? 'DELIVERED' : (phase.isNotEmpty ? phase.toUpperCase() : status.toUpperCase())),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: returned ? Colors.orange[800] : (delivered ? Colors.green : AppTheme.primaryBlue)))),
            const Spacer(),
            Text('₹${p['totalFare'] ?? p['fare'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          ]),
          const SizedBox(height: 8),
          Text(incoming ? 'From ${p['senderName'] ?? 'Sender'} · ${p['itemType'] ?? 'Parcel'}' : '${p['itemType'] ?? 'Parcel'} → ${p['receiverName'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Text('${p['pickupAddress'] ?? ''} → ${p['dropAddress'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (p['driverName'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Driver: ${p['driverName']}', style: const TextStyle(fontSize: 11, color: Colors.grey))),
          // Receiver's delivery OTP — show it so they can hand it to the driver
          if (incoming && !done && (p['dropOtp'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1C2656).withOpacity(0.3))),
              child: Row(children: [const Icon(Icons.lock_outline, size: 18, color: Color(0xFF1C2656)), const SizedBox(width: 8),
                const Expanded(child: Text('Show this OTP to the driver to receive', style: TextStyle(fontSize: 11, color: Colors.black54))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1C2656))),
                  child: Text((p['dropOtp'] ?? '----').toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF1C2656))))]))),
          if (active) const Padding(padding: EdgeInsets.only(top: 6), child: Row(children: [Icon(Icons.my_location, size: 13, color: AppTheme.primaryBlue), SizedBox(width: 4),
            Text('Tap to track live', style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))])),
          // A RETURNED badge on its own tells the sender their parcel came back
          // but not why, so say it plainly, and note that no COD was taken.
          if (returned) Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.assignment_return, size: 18, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(incoming ? 'Returned to sender' : 'Returned to you',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.orange[900])),
                  if (failReason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text(failReason, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                  if (((p['codAmount'] as num?) ?? 0) > 0) Padding(padding: const EdgeInsets.only(top: 2),
                    child: Text('No COD was collected — the receiver did not accept the parcel.',
                      style: TextStyle(fontSize: 11, color: Colors.orange[900]))),
                ])),
              ]))),
          if (done && !incoming) Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => _reportIssue(p), icon: const Icon(Icons.report_problem, size: 14, color: Colors.orange),
            label: const Text('Report Issue', style: TextStyle(fontSize: 12, color: Colors.orange)))),
        ])));
  }

  // Live tracking sheet for any parcel (works for receiver's incoming too — by rideId)
  void _trackLive(Map<String, dynamic> p) {
    final id = (p['_id'] ?? p['id'] ?? '').toString();
    if (id.isEmpty) return;
    final pLat = (p['pickupLat'] as num?)?.toDouble() ?? 0, pLng = (p['pickupLng'] as num?)?.toDouble() ?? 0;
    final dLat = (p['dropLat'] as num?)?.toDouble() ?? 0, dLng = (p['dropLng'] as num?)?.toDouble() ?? 0;
    LatLng? drv; double hd = 0; int? eta;
    Timer? lt;
    // The parcel's own vehicle sprite. This borrowed the sender's booking-flow
    // icon, which was only ever loaded if they had just booked in this session.
    BitmapDescriptor? vehIcon;
    VehicleMarkers.descriptorFor((p['vehicleType'] ?? '').toString()).then((ic) => vehIcon = ic);
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        lt ??= Timer.periodic(const Duration(seconds: 5), (t) async {
          try {
            final res = await ApiService.getDriverLocation(id);
            final dd = res['driver'] as Map<String, dynamic>?;
            if (dd == null || dd['lat'] == null) return;
            final la = (dd['lat'] as num).toDouble(), ln = (dd['lng'] as num).toDouble();
            final toDrop = (p['deliveryPhase'] ?? '') == 'in_transit';
            final dir = await ApiService.getDirections(originLat: la, originLng: ln, destLat: toDrop ? dLat : pLat, destLng: toDrop ? dLng : pLng);
            drv = LatLng(la, ln); hd = (dd['heading'] as num?)?.toDouble() ?? 0; eta = (dir['durationMin'] as num?)?.toInt();
            setS(() {});
          } catch (_) {}
        });
        return Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const Text('Live Tracking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(),
              IconButton(onPressed: () { lt?.cancel(); Navigator.pop(ctx); }, icon: const Icon(Icons.close))]),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 220, child: PlaceGlyphs(builder: (context, glyphs) => GoogleMap(
              initialCameraPosition: CameraPosition(target: drv ?? LatLng(pLat, pLng), zoom: 13),
              markers: {
                Marker(markerId: const MarkerId('p'), position: LatLng(pLat, pLng), anchor: glyphs.pickupAnchor, icon: glyphs.pickup),
                Marker(markerId: const MarkerId('d'), position: LatLng(dLat, dLng), anchor: glyphs.dropAnchor, icon: glyphs.drop),
                if (drv != null) Marker(markerId: const MarkerId('drv'), position: drv!, rotation: hd, flat: true, anchor: const Offset(0.5, 0.5), icon: (vehIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure))),
              },
              zoomControlsEnabled: false, myLocationButtonEnabled: false)))),
            const SizedBox(height: 10),
            if (eta != null) Text('Arriving in $eta min', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue))
            else const Text('Locating driver...', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            if (p['driverName'] != null) Text('Driver: ${p['driverName']} ${p['driverPhone'] != null ? '· ${p['driverPhone']}' : ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]));
      })).whenComplete(() => lt?.cancel());
  }

  // Insurance / damage claim → opens a prefilled support enquiry
  void _reportIssue(Map<String, dynamic> p) {
    showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Report a Delivery Issue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      content: Text('Parcel "${p['itemType'] ?? 'Parcel'}" worth ₹${p['itemValue'] ?? 0}.\n\nOur support team will contact you for damage/loss claims and insurance.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { Navigator.pop(dctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Claim raised — support will contact you'), backgroundColor: Colors.green)); },
          child: const Text('Raise Claim')),
      ]));
  }

  /// One screen, Rapido-style: route → contacts → what → weight, the rest under
  /// "More options", and the vehicles with their prices once the drop is set.
  Widget _buildSend() {
    final selFare = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {})['fare'];
    // The button says what is still missing, in the order the form asks for
    // it, so a disabled button is never a mystery. The checks are exactly
    // _formValid's; this only names the first one that fails.
    final String cta;
    if (_pLat == null) {
      cta = 'Add pickup location';
    } else if (_dLat == null) {
      cta = 'Add drop location';
    } else if (_senderName.text.isEmpty || _senderPhone.text.isEmpty) {
      cta = 'Add sender details';
    } else if (_receiverName.text.isEmpty || _receiverPhone.text.isEmpty) {
      cta = 'Add receiver details';
    } else if (_itemType == null) {
      cta = "Select what you're sending";
    } else if (_selectedVehicle == null || selFare == null) {
      cta = 'Choose a vehicle';
    } else {
      cta = 'Book $_selectedVehicle · ₹$selFare';
    }
    return Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          _top(),
          RouteInputBlock(rows: [
            RouteFieldRow(
              marker: RouteMarkerKind.pickup,
              trailing: MapPickAction(tooltip: 'Pick pickup on map', onTap: () => _openMap(pickup: true)),
              child: _locField('Collect from', _pickupCtrl, 'Add sender address', pickup: true),
            ),
            RouteFieldRow(
              marker: RouteMarkerKind.drop,
              trailing: MapPickAction(tooltip: 'Pick drop on map', onTap: () => _openMap(pickup: false)),
              child: _locField('Deliver to', _dropCtrl, 'Add recipient address', pickup: false),
            ),
          ]),
          ..._pickSug.map((s) => _sugTile(s, pickup: true)),
          ..._dropSug.map((s) => _sugTile(s, pickup: false)),
          // Who hands it over and who receives it — one compact row per stop.
          if (_pLat != null) ...[const SizedBox(height: 10), _contactRow(sender: true)],
          if (_dLat != null) ...[const SizedBox(height: 8), _contactRow(sender: false)],

          const ServiceSection('What are you sending?'),
          Wrap(spacing: 8, runSpacing: 8, children: _itemTypes.map(_chip).toList()),

          const SizedBox(height: 10),
          Text('Max 20 kg · must fit in a backpack · no illegal, alcohol or restricted items',
            style: RideUi.caption(context, size: 12)),
          const SizedBox(height: 16),

          // Everything optional, closed by default.
          CollapsibleInfo(
            title: _moreTitle(),
            icon: Icons.tune,
            children: [
              const SizedBox(height: 4),
              const FieldLabel('Package size'),
              ChoiceSegment<String>(
                options: const [ChoiceOption('S', 'S'), ChoiceOption('M', 'M'), ChoiceOption('L', 'L')],
                selected: _packageSize,
                onChanged: (s) => setState(() => _packageSize = s),
              ),
              const SizedBox(height: 12),
              _toggleTile('Fragile', 'Handle with extra care', Icons.warning_amber, _isFragile, (v) => setState(() => _isFragile = v)),
              const SizedBox(height: 8),
              _toggleTile('COD', 'Receiver pays the amount below on delivery', Icons.payments_outlined, _cod, (v) => setState(() => _cod = v)),
              if (_cod) ...[const SizedBox(height: 12), _field('COD amount ₹ (receiver pays)', 'COD amount in ₹', _codAmount, Icons.account_balance_wallet_outlined, num: true)],
              const SizedBox(height: 12),
              _field('Item value ₹ (for insurance)', 'Item value in ₹', _itemValue, Icons.shield_outlined, num: true),
              const SizedBox(height: 4),
              Text('Avoid sending high value & fragile items', style: RideUi.caption(context, size: 12)),

              const ServiceSection('Parcel photos (proof)', subtitle: 'Photograph the parcel before handing it over'),
              SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal, children: [
                ..._photoUrls.map((u) => Container(width: 84, height: 84, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), image: DecorationImage(image: NetworkImage(AppConfig.imageUrl(u)), fit: BoxFit.cover)))),
                SizedBox(width: 84, height: 84, child: RideTile(
                  onTap: _uploading ? null : _addPhoto,
                  padding: EdgeInsets.zero,
                  child: Center(child: _uploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_a_photo_outlined, color: RideUi.ink(context), size: 24),
                        const SizedBox(height: 4),
                        Text('Add photo', style: RideUi.caption(context, size: 11)),
                      ])),
                )),
              ])),

              const ServiceSection('Pickup time'),
              PickerPill(
                icon: Icons.schedule,
                label: _scheduledAt == null ? 'Deliver now' : 'Scheduled',
                value: _scheduledAt == null ? 'Tap to schedule for later' : serviceDateTime(_scheduledAt!),
                placeholder: _scheduledAt == null,
                trailingText: _scheduledAt == null ? 'Schedule' : null,
                onClear: _scheduledAt != null ? () => setState(() => _scheduledAt = null) : null,
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _scheduledAt ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (d == null || !mounted) return;
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? DateTime.now()));
                  if (t == null) return;
                  setState(() => _scheduledAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
            ],
          ),

          // Vehicles and their real prices, once there is a route to price.
          if (_dLat == null)
            Padding(padding: const EdgeInsets.only(top: 20),
              child: Text('Add a drop location to see vehicles and prices', style: RideUi.caption(context, size: 13)))
          else ...[
            const ServiceSection('Choose vehicle'),
            if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            else if (_error != null) _info(_error!)
            else if (_vehicles.isEmpty) _info('No delivery vehicles available here')
            else ..._vehicles.map(_vehicleCard),
          ],
        ])),
        PrimaryCtaBar(
          top: PaymentCouponBar(
            baseFare: (selFare as num?) ?? 0,
            onChanged: (pm, cc, cd) => setState(() { _paymentMode = pm; _couponCode = cc; _couponDiscount = cd; }),
          ),
          label: cta,
          onPressed: _formValid ? _showConfirm : null,
        ),
      ]);
  }

  /// "More options", plus what is switched on inside it — so a COD or a
  /// schedule set there is never hidden behind a closed row.
  String _moreTitle() {
    final on = <String>[
      if (_cod) 'COD',
      if (_isFragile) 'Fragile',
      if (_scheduledAt != null) 'Scheduled',
      if (_photoUrls.isNotEmpty) '${_photoUrls.length} photo${_photoUrls.length == 1 ? '' : 's'}',
    ];
    return on.isEmpty ? 'More options' : 'More options · ${on.join(', ')}';
  }

  static String _kg(double kg) => kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toString();

  /// Sender / receiver under the route: name · phone, or a prompt to add them.
  Widget _contactRow({required bool sender}) {
    final name = (sender ? _senderName : _receiverName).text.trim();
    final phone = (sender ? _senderPhone : _receiverPhone).text.trim();
    final complete = name.isNotEmpty && phone.isNotEmpty;
    final shown = [name, phone].where((s) => s.isNotEmpty).join(' · ');
    return RideTile(
      onTap: () => _editContact(sender: sender),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Icon(sender ? Icons.person_outline : Icons.person_pin_circle_outlined, size: 20, color: RideUi.ink(context)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(sender ? 'Sender' : (complete ? 'Receiver' : 'Receiver · required'),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12)),
          Text(shown.isNotEmpty ? shown : (sender ? 'Add sender contact' : 'Add receiver contact'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: shown.isNotEmpty
              ? RideUi.body(context, size: 14, weight: FontWeight.w700)
              : RideUi.body(context, size: 14, weight: FontWeight.w600).copyWith(color: RideUi.muted(context))),
        ])),
        const SizedBox(width: 8),
        Text(complete ? 'Edit' : 'Add', style: RideUi.body(context, size: 12.5, weight: FontWeight.w800).copyWith(color: RideUi.accent(context))),
      ]),
    );
  }

  /// Name + phone in a small sheet, edited in place.
  Future<void> _editContact({required bool sender}) async {
    if (sender) _senderTouched = true;
    final name = sender ? _senderName : _receiverName;
    final phone = sender ? _senderPhone : _receiverPhone;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ParcelContactSheet(
        sender: sender, name: name, phone: phone,
        onChanged: () { if (mounted) setState(() {}); },
      ));
    if (mounted) setState(() {});
  }

  void _openMap({required bool pickup}) => setState(() { _pickingPickup = pickup; _mapAddr = ''; _showMap = true; });

  void _showConfirm() {
    final v = _vehicles.firstWhere((x) => x['name'] == _selectedVehicle, orElse: () => {});
    final raw = (v['imageUrl'] as String?) ?? '';
    final pay = _cod ? 'Cash' : (_paymentMode == 'online' ? 'Online' : (_paymentMode == 'wallet' ? 'Wallet' : 'Cash'));
    final codAmt = double.tryParse(_codAmount.text) ?? 0;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(bottom: 14),
          Text('Confirm parcel', style: RideUi.title(ctx, size: 22)),
          const SizedBox(height: 14),
          SummaryVehicleTile(
            leading: VehicleThumb(networkUrl: raw.isEmpty ? '' : AppConfig.imageUrl(raw), fallbackIcon: Icons.local_shipping, size: 48),
            name: _selectedVehicle ?? '',
            caption: _itemType ?? '',
            price: '₹${v['fare'] ?? 0}',
          ),
          const SizedBox(height: 14),
          TripRouteSummary(pickup: _pickupCtrl.text, drop: _dropCtrl.text, fontSize: 13.5),
          const RideDivider(vertical: 12),
          SummaryRow('From', '${_senderName.text} · ${_senderPhone.text}'),
          SummaryRow('To', '${_receiverName.text} · ${_receiverPhone.text}'),
          SummaryRow('Item', _itemType ?? ''),
          if (_cod) SummaryRow('COD (receiver pays)', '₹${_kg(codAmt)}'),
          if (_scheduledAt != null) SummaryRow('Pickup', serviceDateTime(_scheduledAt!)),
          SummaryRow('Payment', pay),
          const RideDivider(vertical: 6),
          SummaryRow('Total', '₹${v['fare'] ?? 0}', bold: true),
          const SizedBox(height: 16),
          PrimaryRideButton(
            label: 'Confirm & Find Driver',
            onPressed: () { Navigator.pop(ctx); _confirmParcel(); },
          ),
        ])));
  }

  Widget _buildMapPicker() {
    return ServiceMapPicker(
      title: _pickingPickup ? 'Pick pickup' : 'Pick drop',
      forPickup: _pickingPickup,
      address: _mapAddr,
      onBack: () => setState(() => _showMap = false),
      onLocate: () async {
        final pos = await LocationService.getCurrentLocation();
        if (pos == null) return;
        _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
      },
      map: GoogleMap(initialCameraPosition: CameraPosition(target: _center, zoom: 14),
        onMapCreated: (c) => _mapCtrl = c, onCameraMove: (p) => _center = p.target,
        onCameraIdle: () async { final a = await ApiService.reverseGeocode(_center.latitude, _center.longitude); if (mounted) setState(() => _mapAddr = a); },
        myLocationEnabled: true, myLocationButtonEnabled: false, zoomControlsEnabled: false),
      onConfirm: _mapAddr.isEmpty ? null : () {
        setState(() {
          if (_pickingPickup) { _pLat = _center.latitude; _pLng = _center.longitude; _pickupCtrl.text = _mapAddr; }
          else { _dLat = _center.latitude; _dLng = _center.longitude; _dropCtrl.text = _mapAddr; }
          _showMap = false;
        });
        _loadFares();
      },
    );
  }

  // ── builders ──
  Widget _info(String t) => NoticeRow(t, tone: NoticeTone.warning);

  /// A location field inside the route block, with its small label above.
  Widget _locField(String label, TextEditingController ctrl, String hint, {required bool pickup}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: RideUi.caption(context, size: 11.5).copyWith(fontWeight: FontWeight.w600)),
      TextField(controller: ctrl, onChanged: (q) => _search(q, pickup: pickup),
        decoration: RideUi.bareInput(context, hint, vertical: 8), style: RideUi.body(context, size: 14.5, weight: FontWeight.w600)),
    ]));

  Widget _sugTile(Map<String, dynamic> s, {required bool pickup}) => PlaceSuggestionTile(
    title: s['mainText']?.toString() ?? '',
    subtitle: s['secondaryText']?.toString(),
    onTap: () => _pick(s, pickup: pickup));

  Widget _chip(String t) => ServiceChip(label: t, icon: _itemIcons[t], selected: _itemType == t, onTap: () => setState(() => _itemType = t));

  Widget _field(String label, String hint, TextEditingController ctrl, IconData icon, {bool num = false, bool phone = false, VoidCallback? onChange}) => LabeledField(
    label: label, hint: hint, controller: ctrl, icon: icon,
    keyboardType: num ? TextInputType.number : phone ? TextInputType.phone : TextInputType.text,
    onChanged: (_) { setState(() {}); onChange?.call(); });

  Widget _vehicleCard(Map<String, dynamic> v) {
    final sel = _selectedVehicle == v['name'];
    final raw = (v['imageUrl'] as String?) ?? '';
    final img = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    return VehicleOptionRow(
      selected: sel,
      onTap: () => setState(() => _selectedVehicle = v['name'] as String?),
      leading: VehicleThumb(networkUrl: img, fallbackIcon: Icons.local_shipping),
      name: v['name']?.toString() ?? '',
      subtitle: v['etaMin'] != null ? 'Pickup in ~${v['etaMin']} min' : null,
      price: '₹${v['fare'] ?? 0}',
    );
  }

  Widget _toggleTile(String label, String caption, IconData icon, bool val, ValueChanged<bool> onChanged) => RideTile(
    onTap: () => onChanged(!val),
    padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
    child: Row(children: [
      Icon(icon, size: 20, color: RideUi.ink(context)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: RideUi.body(context, size: 14.5, weight: FontWeight.w700)),
        Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12)),
      ])),
      Switch(value: val, onChanged: onChanged, activeTrackColor: RideUi.navy),
    ]));
}

/// Name + phone of the sender or receiver, in a keyboard-safe sheet.
///
/// The sheet rides on top of the keyboard as one block (the inset is padding
/// OUTSIDE the scroll view), and the keyboard opens with the sheet on the first
/// empty field, so the layout has settled before the rider taps anything; the
/// keyboard action moves name to phone instead of a second tap on a field that
/// is still moving.
class ParcelContactSheet extends StatefulWidget {
  final bool sender;
  final TextEditingController name;
  final TextEditingController phone;
  final VoidCallback onChanged;
  const ParcelContactSheet({super.key, required this.sender, required this.name, required this.phone, required this.onChanged});

  @override
  State<ParcelContactSheet> createState() => _ParcelContactSheetState();
}

class _ParcelContactSheetState extends State<ParcelContactSheet> {
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();

  @override
  void dispose() {
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.sender;
    final mq = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16 + mq.viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(bottom: 14),
          Text(sender ? 'Sender contact' : 'Receiver contact', style: RideUi.title(context, size: 20)),
          const SizedBox(height: 4),
          Text(sender ? 'The driver collects the parcel from this person' : 'The driver hands the parcel to this person',
            style: RideUi.caption(context, size: 13)),
          const SizedBox(height: 16),
          LabeledField(label: 'Name', hint: sender ? 'Sender name' : 'Receiver name', controller: widget.name,
            icon: Icons.person_outline, focusNode: _nameFocus, autofocus: widget.name.text.isEmpty,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _phoneFocus.requestFocus(),
            onChanged: (_) => widget.onChanged()),
          const SizedBox(height: 12),
          LabeledField(label: 'Phone', hint: sender ? 'Sender phone' : 'Receiver phone', controller: widget.phone,
            icon: Icons.phone_outlined, keyboardType: TextInputType.phone, focusNode: _phoneFocus,
            autofocus: widget.name.text.isNotEmpty && widget.phone.text.isEmpty,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context),
            onChanged: (_) => widget.onChanged()),
          const SizedBox(height: 16),
          PrimaryRideButton(label: 'Done', onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}
