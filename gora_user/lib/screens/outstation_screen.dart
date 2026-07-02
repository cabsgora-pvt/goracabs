import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../utils/polyline_utils.dart';
import 'home_screen.dart';
import 'rating_screen.dart';
import 'booking_screen.dart';
import 'booking_inquiry_screen.dart';
import 'outstation_ride_details_screen.dart';
import '../widgets/finding_driver_view.dart';

class OutstationScreen extends StatefulWidget {
  const OutstationScreen({super.key});

  @override
  State<OutstationScreen> createState() => _OutstationScreenState();
}

class _OutstationScreenState extends State<OutstationScreen> {
  String? _selectedVehicle;
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _departureDateController = TextEditingController();
  final _departureTimeController = TextEditingController();
  final _returnDateController = TextEditingController();
  final _returnTimeController = TextEditingController();
  bool _showLocationInputs = false;
  String _tripType = 'One Way';
  bool _showTripDetails = false;
  bool _showVehicleSelection = false;
  bool _locationConfirmed = false;
  bool _isSearching = false;
  bool _driverAssigned = false;

  // ── Backend-wired state ──
  double? _fromLat, _fromLng, _toLat, _toLng;
  double _distanceKm = 0;
  int _durationMin = 0;
  List<Map<String, dynamic>> _fromSuggestions = [];
  List<Map<String, dynamic>> _toSuggestions = [];
  Timer? _searchDebounce;
  bool _loadingFares = false;
  // Google Maps state
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = [];
  // Real DateTime values backing the date/time text controllers
  DateTime? _departureDateTime;
  DateTime? _returnDateTime;
  // Additional outstation form state
  int _numPassengers = 2;
  final List<TextEditingController> _stopControllers = [];
  final List<Map<String, dynamic>> _stops = []; // {address, lat, lng}
  // Ola-style category filter for the cab list
  String _vehCategory = 'All'; // All | Mini | Sedan | SUV
  // Ola-style: payment mode + coupon
  String _paymentMode = 'cash'; // cash | wallet | online
  bool _walletPayEnabled = true;
  bool _onlinePayEnabled = false;
  String _couponCode = '';
  int _couponDiscount = 0;
  String _bookingFor = 'Myself'; // Myself | Someone else
  // Map-picker state (for choosing From/To by dragging a pin)
  bool _showMapPicker = false;
  bool _pickingFrom = true; // which field the picker is currently filling
  LatLng _pickerCenter = const LatLng(23.0225, 72.5714); // Ahmedabad default
  GoogleMapController? _pickerMapController;
  String _pickerAddress = '';

  // Live ride state
  String? _rideId;
  String? _rideOtp;
  String _driverName = 'Pilot';
  String _driverPhone = '';
  String _driverPicUrl = '';
  String _driverVehicleModel = '';
  String _driverVehicleNumber = '';
  double _driverRating = 0;
  // Live driver location (polled every 5s once driver assigned)
  LatLng? _driverLatLng;
  double _driverHeading = 0;
  Timer? _driverLocTimer;
  // Outstation phase from backend (enroute / at_destination / returning / completed)
  String _outstationPhase = 'enroute';
  String _driverVehicleImageUrl = '';
  int _driverTotalRides = 0;
  int _driverYearsActive = 0;
  Timer? _pollTimer;

  // Vehicles list — populated from backend (admin-configured outstation-enabled VehicleTypes)
  List<Map<String, dynamic>> _vehicles = [];

  @override
  void initState() {
    super.initState();
    _fromController.text = '';
    _toController.text = '';
    _initCurrentLocation();
    _loadPaymentConfig();
  }

  Future<void> _loadPaymentConfig() async {
    final cfg = await ApiService.getPaymentConfig();
    if (!mounted) return;
    setState(() {
      _walletPayEnabled = cfg['walletEnabled'] != false;
      _onlinePayEnabled = (cfg['razorpay'] is Map) && (cfg['razorpay']['enabled'] == true);
    });
  }

  // Pre-fill From field with the user's real current location
  Future<void> _initCurrentLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null || !mounted) return;
    _fromLat = pos.latitude; _fromLng = pos.longitude;
    final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _fromController.text = addr.isNotEmpty ? addr : 'Current location';
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 11));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _driverLocTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Poll driver's live position every 5s during the ride; updates map marker
  void _startDriverLocationPolling() {
    _driverLocTimer?.cancel();
    if (_rideId == null) return;
    _driverLocTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (!mounted) { t.cancel(); return; }
      try {
        final res = await ApiService.getDriverLocation(_rideId!);
        final dr = res['driver'] as Map<String, dynamic>?;
        if (dr == null || dr['lat'] == null || dr['lng'] == null) return;
        if (!mounted) return;
        setState(() {
          _driverLatLng = LatLng((dr['lat'] as num).toDouble(), (dr['lng'] as num).toDouble());
          _driverHeading = ((dr['heading'] as num?) ?? 0).toDouble();
        });
      } catch (_) {}
    });
  }

  // Format DateTime as "DD/MM, h:MM AM/PM"
  String _formatDateTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}, $h:$mm $ampm';
  }

  // Animate Google Map to fit from + to + route polyline
  void _fitMapToRoute() {
    if (_mapController == null) return;
    final pts = <LatLng>[];
    if (_fromLat != null && _fromLng != null) pts.add(LatLng(_fromLat!, _fromLng!));
    if (_toLat != null && _toLng != null) pts.add(LatLng(_toLat!, _toLng!));
    pts.addAll(_routePoints);
    final b = boundsFromPoints(pts);
    if (b == null) return;
    Future.delayed(const Duration(milliseconds: 200), () {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(b, 80));
    });
  }

  // Debounced places autocomplete for From/To city inputs
  void _searchPlaces(String q, {required bool isFrom}) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        if (isFrom) _fromSuggestions = [];
        else _toSuggestions = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await ApiService.placesAutocomplete(q);
      if (!mounted) return;
      setState(() {
        if (isFrom) _fromSuggestions = results;
        else _toSuggestions = results;
      });
    });
  }

  // Payment method chooser (Ola-style bottom sheet)
  Future<String?> _pickPayment() {
    Widget tile(String mode, IconData ic, String label, String sub) => ListTile(
      leading: Icon(ic, color: const Color(0xFF1C2656)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
      trailing: _paymentMode == mode ? const Icon(Icons.check_circle, color: Color(0xFF1C2656)) : null,
      onTap: () => Navigator.pop(context, mode),
    );
    return showModalBottomSheet<String>(
      context: context, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Payment method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        tile('cash', Icons.payments_outlined, 'Cash', 'Pay the driver directly'),
        if (_walletPayEnabled) tile('wallet', Icons.account_balance_wallet_outlined, 'Gora Wallet', 'Pay from your wallet balance'),
        if (_onlinePayEnabled) tile('online', Icons.credit_card, 'Online', 'UPI / card / net banking'),
      ])),
    );
  }

  // "Who's travelling" chooser
  Future<String?> _pickBookingFor() {
    Widget tile(String who, IconData ic) => ListTile(
      leading: Icon(ic, color: const Color(0xFF1C2656)),
      title: Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: _bookingFor == who ? const Icon(Icons.check_circle, color: Color(0xFF1C2656)) : null,
      onTap: () => Navigator.pop(context, who),
    );
    return showModalBottomSheet<String>(
      context: context, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Who\'s travelling?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        tile('Myself', Icons.person),
        tile('Someone else', Icons.people_alt_outlined),
      ])),
    );
  }

  // Coupon dialog
  Future<void> _pickCoupon(Map selectedVehicleData) async {
    final ctrl = TextEditingController(text: _couponCode);
    await showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Apply coupon'),
      content: TextField(controller: ctrl, textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: 'e.g. FLAT100, GORA10', prefixIcon: const Icon(Icons.local_offer_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      actions: [
        TextButton(onPressed: () { _couponCode = ''; _couponDiscount = 0; Navigator.pop(dctx); }, child: const Text('Remove')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656)),
          onPressed: () async {
            _couponCode = ctrl.text.trim().toUpperCase();
            final f = (_tripType == 'One Way' ? selectedVehicleData['oneWayFare'] : selectedVehicleData['roundTripFare']) as num? ?? 0;
            final d = await _validateOutstationCoupon(_couponCode, f);
            _couponDiscount = d;
            if (dctx.mounted) Navigator.pop(dctx);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d > 0 ? 'Coupon applied: −₹$d' : 'Invalid coupon')));
          },
          child: const Text('Apply', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  // Validate against admin-managed coupons (returns ₹ discount, 0 if invalid)
  Future<int> _validateOutstationCoupon(String code, num fare) async {
    if (code.isEmpty) return 0;
    final cfg = await ApiService.getAppConfig();
    for (final c in (cfg['coupons'] as List?) ?? []) {
      if ((c['code'] ?? '').toString().toUpperCase() != code) continue;
      if (c['isActive'] == false) return 0;
      if ((c['minFare'] ?? 0) is num && fare < (c['minFare'] as num)) return 0;
      final val = (c['value'] as num?) ?? 0;
      if ((c['discountType'] ?? 'flat') == 'percent') {
        var d = (fare * val / 100).round();
        final cap = (c['maxDiscount'] as num?)?.toInt() ?? 0;
        if (cap > 0 && d > cap) d = cap;
        return d;
      }
      return val.round();
    }
    return 0;
  }

  // Ola-style red ▸ arrow rule row
  Widget _ruleArrowRow(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.play_arrow, size: 14, color: Color(0xFFFF5252))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75)))),
    ]),
  );

  // Grey • bullet terms row
  Widget _termBulletRow(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 5, left: 2, right: 10), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: Colors.grey[500], shape: BoxShape.circle))),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: Colors.grey[600]))),
    ]),
  );

  String _fmtDateShort(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]}, ${_fmtTime(d)}';
  }

  // Ola-style "Schedule trip" drawer (separate sheet) — Leave on / Return by
  Future<void> _showScheduleDrawer() async {
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget pickRow(String label, DateTime? dt, bool isReturn) => InkWell(
          onTap: () async {
            final date = await showDatePicker(context: ctx, initialDate: dt ?? DateTime.now(),
              firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (date == null) return;
            final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(dt ?? DateTime.now()));
            if (time == null) return;
            final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            setSheet(() {
              if (isReturn) { _returnDateTime = picked; _returnDateController.text = '${picked.day}/${picked.month}/${picked.year}'; _returnTimeController.text = time.format(ctx); }
              else { _departureDateTime = picked; _departureDateController.text = '${picked.day}/${picked.month}/${picked.year}'; _departureTimeController.text = time.format(ctx); }
            });
            setState(() {});
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
            child: Row(children: [
              const Icon(Icons.event, size: 20, color: Color(0xFF1C2656)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(dt != null ? _fmtDateShort(dt) : 'Select date & time', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ])),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ]),
          ),
        );
        final isRT = _tripType == 'Round Trip';
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 18, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(isRT ? 'Schedule round trip' : 'Schedule trip', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            pickRow('Leave on', _departureDateTime, false),
            if (isRT) pickRow('Return by', _returnDateTime, true),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () { if (mounted && _fromLat != null && _toLat != null) _loadOutstationFares(); Navigator.pop(ctx); },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)))),
          ]),
        );
      }),
    );
  }

  String _fmtTime(DateTime d) {
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  // Ola-style "add city" — search a place, append it as an intermediate stop, refresh fares.
  Future<void> _addStopCity() async {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> sugg = [];
    Timer? deb;
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add a city / stop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true,
            decoration: InputDecoration(hintText: 'Search city or place', prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (q) {
              deb?.cancel();
              if (q.trim().length < 2) { setSheet(() => sugg = []); return; }
              deb = Timer(const Duration(milliseconds: 350), () async {
                final r = await ApiService.placesAutocomplete(q);
                setSheet(() => sugg = r);
              });
            }),
          const SizedBox(height: 8),
          ...sugg.take(5).map((s) => ListTile(
            dense: true, leading: const Icon(Icons.location_on_outlined, color: Color(0xFFFF9800)),
            title: Text(s['description'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            onTap: () async {
              final d = await ApiService.placeDetails(s['placeId'] as String? ?? '');
              if (d == null) return;
              _stops.add({'address': d['address'] ?? s['description'], 'lat': (d['lat'] as num).toDouble(), 'lng': (d['lng'] as num).toDouble()});
              if (ctx.mounted) Navigator.pop(ctx);
            },
          )),
        ]),
      )),
    );
    if (mounted) { setState(() {}); _loadOutstationFares(); }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s, {required bool isFrom}) async {
    final desc = s['description'] as String? ?? '';
    final details = await ApiService.placeDetails(s['placeId'] as String? ?? '');
    if (details == null || !mounted) return;
    final lat = (details['lat'] as num).toDouble();
    final lng = (details['lng'] as num).toDouble();
    setState(() {
      if (isFrom) {
        _fromLat = lat; _fromLng = lng;
        _fromController.text = details['address'] as String? ?? desc;
        _fromSuggestions = [];
      } else {
        _toLat = lat; _toLng = lng;
        _toController.text = details['address'] as String? ?? desc;
        _toSuggestions = [];
      }
    });
  }

  // Fetch real outstation fares from backend (one-way + round-trip prices per vehicle)
  Future<void> _loadOutstationFares() async {
    if (_fromLat == null || _fromLng == null || _toLat == null || _toLng == null) return;
    setState(() => _loadingFares = true);

    // Stops payload for multi-city (fare sums the legs pickup → stops → drop)
    final stopsPayload = _stops.map((s) => {'lat': s['lat'], 'lng': s['lng']}).toList();
    // Fetch both one-way and round-trip in parallel so user can switch trip type freely
    final oneWayF = ApiService.estimateFare(
      pickupLat: _fromLat!, pickupLng: _fromLng!,
      dropLat: _toLat!, dropLng: _toLng!,
      service: 'outstation', stops: stopsPayload,
    );
    final roundF = ApiService.post('/fare/estimate', {
      'pickupLat': _fromLat, 'pickupLng': _fromLng,
      'dropLat': _toLat, 'dropLng': _toLng,
      'service': 'outstation', 'tripType': 'round_trip',
      if (stopsPayload.isNotEmpty) 'stops': stopsPayload,
    });

    try {
      final oneWay = await oneWayF;
      final round = await roundF;
      // Fetch actual road polyline so the map shows the real city-to-city route
      final dir = await ApiService.getDirections(
        originLat: _fromLat!, originLng: _fromLng!,
        destLat: _toLat!, destLng: _toLng!,
      );
      if (!mounted) return;
      final encoded = dir['polyline'] as String?;
      if (encoded != null && encoded.isNotEmpty) {
        _routePoints = decodePolyline(encoded);
      }
      setState(() {
        _distanceKm = (oneWay['oneWayKm'] as num?)?.toDouble() ?? (oneWay['distance'] as num?)?.toDouble() ?? 0;
        _durationMin = (oneWay['oneWayMin'] as num?)?.toInt() ?? (oneWay['duration'] as num?)?.toInt() ?? 0;

        // Build the vehicle list straight from backend — this picks up exactly what
        // admin has configured (Bike / Auto / Cab Economy / SUV / Premium / etc.)
        final oneWayVehicles = (oneWay['vehicles'] as List?) ?? [];
        final roundVehicles = (round['vehicles'] as List?) ?? [];
        final rtByName = {for (final v in roundVehicles) (v['name'] as String? ?? '').toLowerCase(): v};

        _vehicles = oneWayVehicles.map<Map<String, dynamic>>((ow) {
          final name = (ow['name'] as String?) ?? 'Vehicle';
          final rt = rtByName[name.toLowerCase()];
          final raw = (ow['imageUrl'] as String?) ?? '';
          final cap = (ow['capacity'] as num?)?.toInt() ?? 4;
          // Keep the active breakdown for the currently picked trip type so booking
          // can send the correct night-halt / empty-return values to backend.
          final Map? bk = _tripType == 'Round Trip' ? (rt?['breakdown'] as Map?) : (ow['breakdown'] as Map?);
          return {
            'name': name,
            'type': cap >= 6 ? 'Spacious' : (cap >= 4 ? 'Comfortable' : 'Quick'),
            'oneWayFare':    ow['fare'] ?? 0,
            'oneWayPrice':   '₹${ow['fare'] ?? 0}',
            'roundTripFare': rt?['fare'] ?? (ow['fare'] ?? 0),
            'roundTripPrice':'₹${rt?['fare'] ?? (ow['fare'] ?? 0)}',
            'capacity': cap.toString(),
            'icon': Icons.directions_car,
            'image': raw.isEmpty ? 'assets/images/economy.png' : '__network__',
            'networkImage': raw.isEmpty ? '' : AppConfig.imageUrl(raw),
            'breakdown': bk ?? {},
            'owBreakdown': ow['breakdown'] ?? {},
            'rtBreakdown': rt?['breakdown'] ?? {},
            'extras': ow['extras'] ?? 0,
            'etaMin': ow['etaMin'],
            'cat': cap >= 6 ? 'SUV' : (cap >= 4 ? 'Sedan' : 'Mini'),
          };
        }).toList();
        _loadingFares = false;
      });
      _fitMapToRoute();
    } catch (_) {
      if (mounted) setState(() => _loadingFares = false);
    }
  }

  // Book the outstation trip against the backend
  Future<void> _bookOutstationRide() async {
    if (_fromLat == null || _toLat == null || _selectedVehicle == null) return;
    final isRoundTrip = _tripType == 'Round Trip';
    final selVehicle = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final rawFare = (isRoundTrip ? selVehicle['roundTripFare'] : selVehicle['oneWayFare']) as num? ?? 0;
    final fare = (rawFare - _couponDiscount).clamp(0, rawFare);

    try {
      final res = await ApiService.bookRide({
        'pickupAddress': _fromController.text,
        'dropAddress': _toController.text,
        'pickupLat': _fromLat, 'pickupLng': _fromLng,
        'dropLat': _toLat, 'dropLng': _toLng,
        'service': 'outstation',
        'tripType': isRoundTrip ? 'round_trip' : 'one_way',
        'vehicleType': _selectedVehicle,
        'fare': fare,
        'distance': _distanceKm,
        'duration': _durationMin,
        'cityFrom': _fromController.text,
        'cityTo': _toController.text,
        'departureAt': _departureDateTime?.toIso8601String(),
        'returnAt': isRoundTrip ? _returnDateTime?.toIso8601String() : null,
        'numPassengers': _numPassengers,
        'multiStops': _stops,
        'nightHaltCharge': (selVehicle['breakdown'] as Map?)?['nightHalt'] ?? 0,
        'emptyReturnCharge': (selVehicle['breakdown'] as Map?)?['emptyReturn'] ?? 0,
        'paymentMode': _paymentMode,
        'couponCode': _couponCode,
        'couponDiscount': _couponDiscount,
        'bookingFor': _bookingFor,
      });
      if (res['ride'] != null) {
        _rideId = res['ride']['id']?.toString();
        _rideOtp = res['ride']['otp']?.toString();
      }
    } catch (_) {/* polling will just find no ride */}
  }

  // Poll backend for status; closes finding-dialog when driver accepts
  void _startStatusPolling(void Function(String status, Map<String, dynamic> ride) onStatus) {
    _pollTimer?.cancel();
    if (_rideId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted) { t.cancel(); return; }
      try {
        final ride = await ApiService.getRide(_rideId!);
        final status = (ride['status'] ?? 'pending').toString();
        if (ride['driverName'] != null) _driverName = ride['driverName'].toString();
        if (ride['driverPhone'] != null) _driverPhone = ride['driverPhone'].toString();
        final dr = ride['driver'] as Map<String, dynamic>?;
        if (dr != null) {
          _driverVehicleModel = (dr['vehicleModel'] ?? _driverVehicleModel).toString();
          _driverVehicleNumber = (dr['vehicleNumber'] ?? _driverVehicleNumber).toString();
          final pic = (dr['profilePicUrl'] ?? '').toString();
          if (pic.isNotEmpty) _driverPicUrl = AppConfig.imageUrl(pic);
          final r = dr['rating'];
          if (r is num) _driverRating = r.toDouble();
          _driverTotalRides = (dr['totalRides'] as num?)?.toInt() ?? _driverTotalRides;
          _driverYearsActive = (dr['yearsActive'] as num?)?.toInt() ?? _driverYearsActive;
        }
        // Pull outstation phase from ride for the UI status card
        final phase = (ride['outstationPhase'] as String?) ?? '';
        if (phase.isNotEmpty) _outstationPhase = phase;
        // Vehicle image url — read once when ride is accepted
        final selected = _selectedVehicle;
        if (selected != null && _driverVehicleImageUrl.isEmpty) {
          final v = _vehicles.firstWhere((x) => x['name'] == selected, orElse: () => {});
          final ni = (v['networkImage'] as String?) ?? '';
          if (ni.isNotEmpty) _driverVehicleImageUrl = ni;
        }
        // Start live driver location polling once driver is assigned (only once)
        if (status != 'pending' && _driverLocTimer == null) {
          _startDriverLocationPolling();
        }

        // ── COMPLETION at SCREEN level — works no matter which dialog is open ──
        if (status == 'completed') {
          t.cancel();
          _pollTimer = null;
          _driverLocTimer?.cancel();
          if (!mounted) return;
          // Close any open sheets (assigned dialog, etc.) then push rating
          Navigator.of(this.context, rootNavigator: true).popUntil((route) => route.isFirst);
          Navigator.of(this.context).push(MaterialPageRoute(builder: (_) => RatingScreen(
            driverName: _driverName.isNotEmpty ? _driverName : 'Pilot',
            vehicleName: _selectedVehicle ?? 'Outstation',
            selectedTip: 0,
            rideId: _rideId,
          )));
          return;
        }

        onStatus(status, ride);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use the clean full-screen From/To picker (same as taxi) before confirmation —
    // avoids the buggy in-place panel + Stack layout that was causing hit-test errors.
    if (_showMapPicker) return _buildOutstationMapPicker();
    if (!_locationConfirmed) return _buildOutstationLocationScreen();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          if (!_locationConfirmed)
            Container(
              color: Theme.of(context).cardColor,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.arrow_back, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showLocationInputs = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _fromController.text.isEmpty && _toController.text.isEmpty
                                            ? 'Current Location → Select Destination'
                                            : '${_fromController.text.isEmpty ? "Current Location" : _fromController.text} → ${_toController.text.isEmpty ? "Select Destination" : _toController.text}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: _fromController.text.isEmpty && _toController.text.isEmpty ? Colors.grey[600] : Theme.of(context).colorScheme.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showLocationInputs)
                      // Scrollable so suggestion lists + inputs + confirm button never overflow
                      // when the on-screen keyboard pushes the layout up
                      Flexible(child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                            _buildLocationInput(Icons.radio_button_checked, _fromController, Color(0xFF4CAF50), 'From (Pickup Location)'),
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Row(
                                children: [
                                  Column(
                                    children: List.generate(2, (index) => Container(
                                      margin: const EdgeInsets.symmetric(vertical: 1),
                                      width: 2,
                                      height: 3,
                                      color: Colors.grey[400],
                                    )),
                                  ),
                                ],
                              ),
                            ),
                            _buildLocationInput(Icons.location_on, _toController, Color(0xFFFF5252), 'To (Destination)'),
                            // Multi-city stops (Ola-style "add city")
                            ..._stops.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(children: [
                                const Icon(Icons.adjust, size: 18, color: Color(0xFFFF9800)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(e.value['address'] as String? ?? 'Stop', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                InkWell(onTap: () { setState(() => _stops.removeAt(e.key)); _loadOutstationFares(); },
                                  child: const Icon(Icons.close, size: 18, color: Colors.red)),
                              ]),
                            )),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _addStopCity,
                              child: Row(children: const [
                                Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF1C2656)),
                                SizedBox(width: 8),
                                Text('Add city / stop', style: TextStyle(fontSize: 13, color: Color(0xFF1C2656), fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (_toController.text.isEmpty || _fromController.text.isEmpty) return;
                                  // If user typed but never picked a suggestion, auto-pick top match
                                  if (_fromLat == null && _fromSuggestions.isNotEmpty) {
                                    await _selectSuggestion(_fromSuggestions.first, isFrom: true);
                                  }
                                  if (_toLat == null && _toSuggestions.isNotEmpty) {
                                    await _selectSuggestion(_toSuggestions.first, isFrom: false);
                                  }
                                  if (_fromLat == null || _toLat == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Pick a city from the suggestions for both From and To')),
                                    );
                                    return;
                                  }
                                  if (!mounted) return;
                                  setState(() {
                                    _showLocationInputs = false;
                                    _locationConfirmed = true;
                                    _showTripDetails = true;
                                  });
                                  // Fetch real outstation prices from backend
                                  _loadOutstationFares();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1C2656),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Confirm Location', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(target: LatLng(23.0225, 72.5714), zoom: 6),
                  onMapCreated: (c) {
                    _mapController = c;
                    _fitMapToRoute();
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  markers: {
                    if (_fromLat != null && _fromLng != null)
                      Marker(
                        markerId: const MarkerId('from'),
                        position: LatLng(_fromLat!, _fromLng!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                        infoWindow: InfoWindow(title: 'From', snippet: _fromController.text),
                      ),
                    if (_toLat != null && _toLng != null)
                      Marker(
                        markerId: const MarkerId('to'),
                        position: LatLng(_toLat!, _toLng!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: InfoWindow(title: 'To', snippet: _toController.text),
                      ),
                    // Live driver marker once assigned
                    if (_driverLatLng != null)
                      Marker(
                        markerId: const MarkerId('driver'),
                        position: _driverLatLng!,
                        rotation: _driverHeading,
                        flat: true,
                        anchor: const Offset(0.5, 0.5),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        infoWindow: InfoWindow(title: _driverName, snippet: _driverVehicleNumber),
                      ),
                  },
                  polylines: {
                    if (_routePoints.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _routePoints,
                        color: const Color(0xFF1C2656),
                        width: 5,
                      ),
                  },
                ),
                DraggableScrollableSheet(
                  // Key forces the sheet to recreate when confirmed state flips,
                  // so initialChildSize is re-applied and the panel auto-expands
                  key: ValueKey('outstation-sheet-${_locationConfirmed ? 'confirmed' : 'pick'}'),
                  initialChildSize: _locationConfirmed ? 0.4 : 0.15,
                  minChildSize: _locationConfirmed ? 0.4 : 0.15,
                  maxChildSize: _locationConfirmed ? 0.85 : 0.15,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              physics: _locationConfirmed ? null : const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              children: [
                                if (!_locationConfirmed) ...[
                                  const Text(
                                    'Plan Your Outstation Trip',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Set your pickup and destination to get started',
                                    style: TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                ] else ...[
                                  // Location section at the TOP (Ola-style green/red dots)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                                    child: Column(children: [
                                      Row(children: [
                                        const Icon(Icons.radio_button_checked, size: 14, color: Color(0xFF4CAF50)),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(_fromController.text.isEmpty ? 'Pickup' : _fromController.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                      ]),
                                      Padding(padding: const EdgeInsets.only(left: 6), child: Row(children: [
                                        Container(width: 2, height: 16, color: Colors.grey[300]),
                                      ])),
                                      Row(children: [
                                        const Icon(Icons.location_on, size: 14, color: Color(0xFFFF5252)),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(_toController.text.isEmpty ? 'Destination' : _toController.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                      ]),
                                    ]),
                                  ),
                                  const SizedBox(height: 14),
                                  // Trip type cards
                                  Row(children: [
                                    Expanded(child: _buildTripTypeButton('One Way')),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildTripTypeButton('Round Trip')),
                                  ]),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () => setState(() => _showTripDetails = !_showTripDetails),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Row(
                                        children: [
                                          const Text('Trip Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          Icon(
                                            _showTripDetails ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            color: Colors.grey[600],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showTripDetails)
                                    const SizedBox(height: 8),
                                  // "Booking for … SELECT" — opens the schedule drawer (Ola-style)
                                  if (_showTripDetails)
                                    InkWell(
                                      onTap: _showScheduleDrawer,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[300]!)),
                                        child: Row(children: [
                                          const Icon(Icons.event, size: 18, color: Color(0xFF1C2656)),
                                          const SizedBox(width: 10),
                                          Expanded(child: RichText(text: TextSpan(
                                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                                            children: [
                                              const TextSpan(text: 'Booking for  '),
                                              TextSpan(
                                                text: _departureDateTime != null
                                                  ? '${_fmtDateShort(_departureDateTime!)}${_tripType == 'Round Trip' && _returnDateTime != null ? '  —  ${_fmtDateShort(_returnDateTime!)}' : ''}'
                                                  : 'now',
                                                style: const TextStyle(color: Color(0xFF1C2656), fontWeight: FontWeight.w800)),
                                            ]))),
                                          const Text('SELECT', style: TextStyle(fontSize: 12, color: Color(0xFF1C2656), fontWeight: FontWeight.w900)),
                                        ]),
                                      ),
                                    ),
                                  if (_showTripDetails && _departureDateTime != null && _durationMin > 0)
                                    Padding(padding: const EdgeInsets.only(top: 10), child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3))),
                                      child: Row(children: [
                                        const Icon(Icons.flag, color: Color(0xFF4CAF50), size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(
                                          'Arriving by ${_formatDateTime(_departureDateTime!.add(Duration(minutes: _durationMin)))}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                                        )),
                                      ]),
                                    )),
                                  if (_showTripDetails)
                                    const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap: () => setState(() => _showVehicleSelection = !_showVehicleSelection),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Row(
                                        children: [
                                          const Text('Select Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          Icon(
                                            _showVehicleSelection ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            color: Colors.grey[600],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showVehicleSelection)
                                    const SizedBox(height: 8),
                                  if (_showVehicleSelection)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, color: Colors.blue[600], size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _loadingFares
                                                ? 'Calculating distance & duration...'
                                                : _distanceKm > 0
                                                  ? 'Estimated distance: ${_distanceKm.toStringAsFixed(0)} km • Duration: ${_durationMin >= 60 ? "${_durationMin ~/ 60}h ${(_durationMin % 60).toString().padLeft(2, "0")}m" : "$_durationMin min"}'
                                                  : 'Estimated distance: —',
                                              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_showVehicleSelection)
                                    const SizedBox(height: 16),
                                  // Route summary above vehicle list — From → To + km/duration/trip type
                                  if (_showVehicleSelection)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey[200]!),
                                      ),
                                      child: Column(children: [
                                        Row(children: [
                                          const Icon(Icons.radio_button_checked, size: 14, color: Color(0xFF4CAF50)),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(_fromController.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                        ]),
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          const Icon(Icons.location_on, size: 14, color: Color(0xFFFF5252)),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(_toController.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                        ]),
                                        const Divider(height: 16),
                                        Row(children: [
                                          const Icon(Icons.route, size: 13, color: Color(0xFF1C2656)),
                                          const SizedBox(width: 4),
                                          Text('${_distanceKm.toStringAsFixed(0)} km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1C2656))),
                                          const SizedBox(width: 14),
                                          const Icon(Icons.access_time, size: 13, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(_durationMin > 60 ? '${(_durationMin / 60).toStringAsFixed(1)} hr' : '$_durationMin min', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                            child: Text(_tripType, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1C2656))),
                                          ),
                                        ]),
                                      ]),
                                    ),
                                  // Ola-style horizontal category chips
                                  if (_showVehicleSelection && _vehicles.isNotEmpty)
                                    SizedBox(
                                      height: 38,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: () {
                                          final cats = ['All', ...{for (final v in _vehicles) v['cat'] as String}];
                                          return cats.map((c) {
                                            final sel = _vehCategory == c;
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 8),
                                              child: ChoiceChip(
                                                label: Text(c, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: sel ? Colors.white : null)),
                                                selected: sel,
                                                showCheckmark: false,
                                                selectedColor: const Color(0xFF1C2656),
                                                backgroundColor: Theme.of(context).cardColor,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sel ? const Color(0xFF1C2656) : Colors.grey[300]!)),
                                                onSelected: (_) => setState(() => _vehCategory = c),
                                              ),
                                            );
                                          }).toList();
                                        }(),
                                      ),
                                    ),
                                  if (_showVehicleSelection && _vehicles.isNotEmpty)
                                    const SizedBox(height: 12),
                                  if (_showVehicleSelection)
                                    Column(
                                      children: _vehicles
                                          .where((v) => _vehCategory == 'All' || v['cat'] == _vehCategory)
                                          .map((v) => _buildVehicleCard(v)).toList(),
                                    ),
                                  if (_showVehicleSelection)
                                    const SizedBox(height: 20),
                                  if (_showVehicleSelection)
                                    _buildTripConditions(context),
                                  const SizedBox(height: 80),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    },
                  ),
              ],
            ),
          ),
          if (_locationConfirmed)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedVehicle == null ? null : () {
                      _showBookingConfirmationDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1C2656),
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _selectedVehicle == null ? 'Select a vehicle' : 'Book Trip',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedVehicle == null ? Colors.grey[600] : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTripTypeButton(String type) {
    final isSelected = _tripType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tripType = type;
          if (type == 'One Way') {
            _returnDateController.clear();
            _returnTimeController.clear();
            _returnDateTime = null;
          }
          // Auto-expand vehicle selection after trip details are set
          if (!_showVehicleSelection && (_departureDateController.text.isNotEmpty || type == 'One Way')) {
            _showVehicleSelection = true;
          }
        });
        // Selecting a trip type opens the schedule drawer (Ola behaviour),
        // so the user picks Leave on / Return by right away.
        WidgetsBinding.instance.addPostFrameCallback((_) => _showScheduleDrawer());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFF1C2656) : Colors.grey[300]!, width: isSelected ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(type == 'One Way' ? 'One-way' : 'Round trip',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(type == 'One Way' ? 'Get dropped off' : 'Keep the car till return',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ])),
          Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20, color: isSelected ? const Color(0xFF1C2656) : Colors.grey[400]),
        ]),
      ),
    );
  }

  // Clean full-screen From/To picker — mirrors the taxi screen UX so behaviour is consistent
  Widget _buildOutstationLocationScreen() {
    // Whichever field is empty drives the suggestion list shown below
    final activeIsFrom = _fromController.text.trim().isEmpty || _toController.text.trim().isNotEmpty == false;
    final suggestions = activeIsFrom ? _fromSuggestions : _toSuggestions;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => Navigator.pop(context)),
        title: Text('Outstation', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _buildLocationInput(Icons.radio_button_checked, _fromController, const Color(0xFF4CAF50), 'From city'),
            const SizedBox(height: 12),
            _buildLocationInput(Icons.location_on, _toController, const Color(0xFFFF5252), 'To city'),
            const SizedBox(height: 12),
            // Quick action: pick either field via draggable map pin
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _openMapPicker(forFrom: true),
                icon: const Icon(Icons.map, size: 16, color: Color(0xFF4CAF50)),
                label: const Text('Pick From on map', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 10)),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _openMapPicker(forFrom: false),
                icon: const Icon(Icons.map, size: 16, color: Color(0xFFFF5252)),
                label: const Text('Pick To on map', style: TextStyle(fontSize: 12, color: Color(0xFFFF5252))),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 10)),
              )),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Always-visible quick action: use GPS to set From field
              if (activeIsFrom)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.my_location, color: Color(0xFF1C2656), size: 20),
                  ),
                  title: const Text('Use my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1C2656))),
                  subtitle: const Text('Fetch GPS and fill From', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: _initCurrentLocation,
                ),
              if (activeIsFrom) const Divider(),
              if (suggestions.isNotEmpty) ...[
                Text('SUGGESTIONS', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                ...suggestions.map((s) => ListTile(
                  leading: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 22),
                  title: Text(s['mainText']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(s['secondaryText']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  onTap: () => _selectSuggestion(s, isFrom: activeIsFrom),
                )),
              ] else if (!activeIsFrom)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [
                    Icon(Icons.search, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('Type a destination city', style: TextStyle(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                  ]),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))]),
          child: SafeArea(top: false, child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (_fromController.text.trim().isEmpty || _toController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both From and To cities')));
                  return;
                }
                if (_fromLat == null && _fromSuggestions.isNotEmpty) await _selectSuggestion(_fromSuggestions.first, isFrom: true);
                if (_toLat == null && _toSuggestions.isNotEmpty) await _selectSuggestion(_toSuggestions.first, isFrom: false);
                if (_fromLat == null || _toLat == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick cities from the suggestions')));
                  return;
                }
                if (!mounted) return;
                setState(() {
                  _showLocationInputs = false;
                  _locationConfirmed = true;
                  _showTripDetails = true;
                });
                _loadOutstationFares();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Confirm Location', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          )),
        ),
      ]),
    );
  }

  // Open the draggable-pin map for either From or To
  void _openMapPicker({required bool forFrom}) {
    final start = forFrom
        ? (_fromLat != null ? LatLng(_fromLat!, _fromLng!) : _pickerCenter)
        : (_toLat != null ? LatLng(_toLat!, _toLng!) : _pickerCenter);
    setState(() {
      _pickingFrom = forFrom;
      _pickerCenter = start;
      _pickerAddress = '';
      _showMapPicker = true;
    });
  }

  // Full-screen map with a fixed center pin; reverse-geocode on camera idle
  Widget _buildOutstationMapPicker() {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => setState(() => _showMapPicker = false)),
        title: Text(_pickingFrom ? 'Pick From location' : 'Pick To location',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _pickerCenter, zoom: 13),
          onMapCreated: (c) => _pickerMapController = c,
          onCameraMove: (pos) => _pickerCenter = pos.target,
          onCameraIdle: () async {
            final addr = await ApiService.reverseGeocode(_pickerCenter.latitude, _pickerCenter.longitude);
            if (!mounted) return;
            setState(() => _pickerAddress = addr);
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        // Center pin
        const Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on, color: Color(0xFFFF5252), size: 48))),
        // GPS button
        Positioned(bottom: 180, right: 16, child: FloatingActionButton(
          mini: true, backgroundColor: Theme.of(context).cardColor,
          onPressed: () async {
            final pos = await LocationService.getCurrentLocation();
            if (pos == null) return;
            final ll = LatLng(pos.latitude, pos.longitude);
            _pickerMapController?.animateCamera(CameraUpdate.newLatLngZoom(ll, 14));
          },
          child: const Icon(Icons.my_location, color: Color(0xFF1C2656)),
        )),
        // Bottom card: address preview + Confirm
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))]),
          child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(_pickingFrom ? Icons.radio_button_checked : Icons.location_on,
                color: _pickingFrom ? const Color(0xFF4CAF50) : const Color(0xFFFF5252), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _pickerAddress.isEmpty ? 'Move the map to set location...' : _pickerAddress,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              )),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _pickerAddress.isEmpty ? null : () {
                if (!mounted) return;
                setState(() {
                  if (_pickingFrom) {
                    _fromLat = _pickerCenter.latitude; _fromLng = _pickerCenter.longitude;
                    _fromController.text = _pickerAddress;
                    _fromSuggestions = [];
                  } else {
                    _toLat = _pickerCenter.latitude; _toLng = _pickerCenter.longitude;
                    _toController.text = _pickerAddress;
                    _toSuggestions = [];
                  }
                  _showMapPicker = false;
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            )),
          ])),
        )),
      ]),
    );
  }

  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint) {
    final isFrom = identical(controller, _fromController);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (q) => _searchPlaces(q, isFrom: isFrom),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateInput(TextEditingController controller, String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: true,
              onTap: () async {
                final isReturn = identical(controller, _returnDateController);
                final date = await showDatePicker(
                  context: context,
                  initialDate: (isReturn ? _returnDateTime : _departureDateTime) ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  controller.text = '${date.day}/${date.month}/${date.year}';
                  setState(() {
                    if (isReturn) {
                      final existing = _returnDateTime;
                      _returnDateTime = DateTime(date.year, date.month, date.day, existing?.hour ?? 9, existing?.minute ?? 0);
                    } else {
                      final existing = _departureDateTime;
                      _departureDateTime = DateTime(date.year, date.month, date.day, existing?.hour ?? 9, existing?.minute ?? 0);
                    }
                  });
                }
              },
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInput(TextEditingController controller, String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: true,
              onTap: () async {
                final isReturn = identical(controller, _returnTimeController);
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(
                    (isReturn ? _returnDateTime : _departureDateTime) ?? DateTime.now(),
                  ),
                );
                if (time != null) {
                  controller.text = time.format(context);
                  setState(() {
                    if (isReturn) {
                      final d = _returnDateTime ?? DateTime.now();
                      _returnDateTime = DateTime(d.year, d.month, d.day, time.hour, time.minute);
                    } else {
                      final d = _departureDateTime ?? DateTime.now();
                      _departureDateTime = DateTime(d.year, d.month, d.day, time.hour, time.minute);
                    }
                  });
                }
              },
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    final currentPrice = _tripType == 'One Way' ? v['oneWayPrice'] : v['roundTripPrice'];
    // Pick the breakdown for the current trip type
    final Map bk = (_tripType == 'Round Trip' ? v['rtBreakdown'] : v['owBreakdown']) as Map? ?? {};
    final num perKm = (bk['perKm'] as num?) ?? 0;

    final navy = const Color(0xFF1C2656);
    final img = (v['networkImage'] as String?) ?? '';
    final cat = (v['cat'] as String?) ?? 'Sedan';
    final tagline = cat == 'SUV' ? 'Spacious, premium cars' : (cat == 'Mini' ? 'Comfy, economical cars' : 'Top sedans');
    // Round trip → show the per-km rate; one-way → show the total fare (Ola behaviour)
    final priceLabel = _tripType == 'Round Trip' ? '₹${perKm.toStringAsFixed(0)}/km' : currentPrice.toString();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? navy : Colors.grey.withOpacity(0.2), width: isSelected ? 2 : 1),
        boxShadow: isSelected ? [BoxShadow(color: navy.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 5))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selectedVehicle = v['name']),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Photo with green accent corner (Ola)
              Stack(children: [
                Container(width: 72, height: 52, decoration: BoxDecoration(color: const Color(0xFF8BC34A).withOpacity(0.25), borderRadius: BorderRadius.circular(10))),
                Positioned.fill(child: Padding(padding: const EdgeInsets.all(4), child: img.isNotEmpty
                    ? Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(v['icon'], color: navy, size: 32))
                    : Image.asset(v['image'] as String? ?? 'assets/images/economy.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(v['icon'], color: navy, size: 32)))),
              ]),
              const SizedBox(width: 14),
              // Name + tagline
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Text(tagline, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
              const SizedBox(width: 6),
              // ⓘ details + price
              InkWell(
                onTap: () => _showCabDetailSheet(v, bk),
                customBorder: const CircleBorder(),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.info_outline, size: 18, color: Colors.grey[500])),
              ),
              const SizedBox(width: 4),
              Text(priceLabel, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: navy)),
              if (isSelected) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.check_circle, size: 18, color: navy)),
            ]),
          ),
        ),
      ),
    );
  }

  // Ola-style cab detail sheet — fleet, features, fare breakdown, inclusions
  void _showCabDetailSheet(Map<String, dynamic> v, Map bk) {
    final navy = const Color(0xFF1C2656);
    final currentPrice = _tripType == 'One Way' ? v['oneWayPrice'] : v['roundTripPrice'];
    final num base = (bk['base'] as num?) ?? 0;
    final num km = (bk['totalKm'] as num?) ?? 0;
    final num perKm = (bk['perKm'] as num?) ?? 0;
    final num kmCharge = (bk['kmCharge'] as num?) ?? 0;
    final num hrs = (bk['totalHrs'] as num?) ?? 0;
    final num perHour = (bk['perHour'] as num?) ?? 0;
    final num hourCharge = (bk['hourCharge'] as num?) ?? 0;
    final num driverAllowance = (bk['driverAllowance'] as num?) ?? 0;
    final num nightHalt = (bk['nightHalt'] as num?) ?? 0;
    final num gst = (bk['gst'] as num?) ?? 0;
    final num gstPercent = (bk['gstPercent'] as num?) ?? 0;
    final img = (v['networkImage'] as String?) ?? '';
    final cap = int.tryParse('${v['capacity']}') ?? 4;
    final fleet = cap >= 6 ? 'Ertiga, Innova, Marazzo or similar' : (cap >= 4 ? 'Swift Dzire, Etios, Aura or similar' : 'WagonR, Celerio or similar');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.92, expand: false,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Container(width: 100, height: 70, decoration: BoxDecoration(color: navy.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.all(6),
              child: img.isNotEmpty ? Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(v['icon'], color: navy, size: 40)) : Image.asset(v['image'] as String? ?? 'assets/images/economy.png', fit: BoxFit.contain)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['name'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 4),
              Text('$cap seats • AC • Outstation', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            Text(currentPrice.toString(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: navy)),
          ]),
          const SizedBox(height: 16),
          // Feature icons row
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _featBig(Icons.ac_unit, 'Comfy ride'),
            _featBig(Icons.account_balance_wallet_outlined, 'Pocket-friendly'),
            _featBig(Icons.verified_user_outlined, 'Verified driver'),
          ]),
          const SizedBox(height: 16),
          // Our fleet
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: navy.withOpacity(0.04), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.directions_car, color: Color(0xFF1C2656), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Our fleet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                Text(fleet, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ])),
            ])),
          const SizedBox(height: 18),
          const Text('Fare breakup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _bkRow(context, 'Base fare', '₹${base.toStringAsFixed(0)}'),
          _bkRow(context, 'Distance (${km.toStringAsFixed(0)} km × ₹${perKm.toStringAsFixed(0)}/km)', '₹${kmCharge.toStringAsFixed(0)}'),
          if (perHour > 0) _bkRow(context, 'Time (${hrs.toStringAsFixed(0)} hr × ₹${perHour.toStringAsFixed(0)}/hr)', '₹${hourCharge.toStringAsFixed(0)}'),
          if (driverAllowance > 0) _bkRow(context, 'Driver allowance', '₹${driverAllowance.toStringAsFixed(0)}'),
          if (nightHalt > 0) _bkRow(context, 'Night halt', '₹${nightHalt.toStringAsFixed(0)}', color: Colors.orange),
          if (gst > 0) _bkRow(context, 'GST (${gstPercent.toStringAsFixed(0)}%)', '₹${gst.toStringAsFixed(0)}'),
          Container(height: 1, color: Colors.grey.withOpacity(0.15), margin: const EdgeInsets.symmetric(vertical: 8)),
          _bkRow(context, 'Estimated total', currentPrice.toString(), bold: true),
          const SizedBox(height: 6),
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _showInclusionsSheet(bk); },
            icon: const Icon(Icons.info_outline, size: 16), label: const Text('View inclusions & exclusions')),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: navy, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)))),
        ]),
      ),
    );
  }

  Widget _featBig(IconData ic, String label) => Column(children: [
    Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.07), shape: BoxShape.circle),
      child: Icon(ic, color: const Color(0xFF1C2656), size: 22)),
    const SizedBox(height: 6),
    Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
  ]);

  // Ola-style inclusions & exclusions bottom sheet
  void _showInclusionsSheet(Map bk) {
    final num kmLimit = (bk['kmLimit'] as num?) ?? 0;
    final num extraKmRate = (bk['extraKmRate'] as num?) ?? 0;
    final num driverAllowance = (bk['driverAllowance'] as num?) ?? 0;
    final num gstPercent = (bk['gstPercent'] as num?) ?? 0;
    final num nightHalt = (bk['nightHalt'] as num?) ?? 0;
    showModalBottomSheet(
      context: context, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Fare Inclusions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF4CAF50))),
          const SizedBox(height: 10),
          _incRow(true, kmLimit > 0 ? '${kmLimit.toStringAsFixed(0)} km included in fare' : 'Distance-based fare'),
          _incRow(true, 'Base fare + per-km + driving time'),
          if (driverAllowance > 0) _incRow(true, 'Driver allowance (₹${driverAllowance.toStringAsFixed(0)})'),
          if (nightHalt > 0) _incRow(true, 'Night halt charge included'),
          _incRow(true, 'Pickup & drop at your chosen points'),
          const SizedBox(height: 18),
          const Text('Exclusions (pay extra)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.orange)),
          const SizedBox(height: 10),
          if (extraKmRate > 0) _incRow(false, 'Extra distance beyond limit — ₹${extraKmRate.toStringAsFixed(0)}/km'),
          _incRow(false, 'Toll, parking & state permit charges'),
          if (gstPercent == 0) _incRow(false, 'GST as applicable'),
          _incRow(false, 'Any waiting beyond free time'),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
        ]),
      ),
    );
  }

  Widget _incRow(bool included, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(included ? Icons.check_circle : Icons.cancel, size: 18, color: included ? Colors.green : Colors.orange),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface))),
    ]),
  );

  Widget _bkRow(BuildContext context, String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: color ?? Theme.of(context).colorScheme.onSurface)),
      Text(v, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? (bold ? const Color(0xFF1C2656) : Theme.of(context).colorScheme.onSurface))),
    ]),
  );

  Widget _buildTripConditions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF1C2656).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline, color: Color(0xFF1C2656), size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                '${_tripType} Trip Conditions',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tripType == 'One Way') ...[
            _buildConditionItem(
              Icons.toll,
              'Tolls and state taxi extra pay',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.local_parking,
              'Parking charges extra',
            ),
          ] else ...[
            _buildConditionItem(
              Icons.toll,
              'Tolls and state taxi extra pay',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.local_parking,
              'Parking charges extra',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.route,
              'Minimum per day 250km running',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.add_road,
              'Per km will be charged for extra km',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.person,
              'Driver allowance per 24 hours - ₹250',
            ),
            const SizedBox(height: 8),
            _buildConditionItem(
              Icons.nightlight,
              'Night time drive allowance (11:00PM - 06:00AM) - ₹250/night',
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payment, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Customer - pay the driver directly',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: Colors.grey[600]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  void _showBookingConfirmationDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final currentPrice = _tripType == 'One Way' ? selectedVehicleData['oneWayPrice'] : selectedVehicleData['roundTripPrice'];
    // Fare breakdown for the chosen trip type → drives the Ola breakup + rules
    final Map cbk = (_tripType == 'Round Trip' ? selectedVehicleData['rtBreakdown'] : selectedVehicleData['owBreakdown']) as Map? ?? {};
    final num cBase = (cbk['base'] as num?) ?? 0;
    final num cPerKm = (cbk['perKm'] as num?) ?? 0;
    final num cKmCharge = (cbk['kmCharge'] as num?) ?? 0;
    final num cPerHour = (cbk['perHour'] as num?) ?? 0;
    final num cHourCharge = (cbk['hourCharge'] as num?) ?? 0;
    final num cDriverAllow = (cbk['driverAllowance'] as num?) ?? 0;
    final num cNightHalt = (cbk['nightHalt'] as num?) ?? 0;
    final num cExtraKm = (cbk['extraKmRate'] as num?) ?? 0;
    final num cGst = (cbk['gst'] as num?) ?? 0;
    final num cGstPct = (cbk['gstPercent'] as num?) ?? 0;
    final String cityTo = _toController.text.split(',').first.trim();
    // Dynamic Rules & Restrictions (all values come from admin zone pricing)
    final List<String> rules = [
      'Excludes toll costs, parking, permits and state tax',
      if (cPerHour > 0) '₹${cPerHour.toStringAsFixed(0)}/hr will be charged for additional hours',
      if (cExtraKm > 0) '₹${cExtraKm.toStringAsFixed(0)}/km will be charged for extra km',
      if (cDriverAllow > 0) 'Driver allowance per 24 hours - ₹${cDriverAllow.toStringAsFixed(0)}',
      if (cNightHalt > 0) 'Night time allowance (11:00 PM - 06:00 AM) - ₹${cNightHalt.toStringAsFixed(0)}/night',
      'Extra fare may apply if you don\'t end trip at ${cityTo.isEmpty ? "drop city" : cityTo}',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF1C2656)),
                    const SizedBox(width: 8),
                    Text(
                      '$_tripType Trip',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup and Drop locations
                      Row(
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Container(
                                width: 2,
                                height: 40,
                                color: Colors.grey[300],
                              ),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5252),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('From', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _fromController.text.isEmpty ? 'Current Location' : _fromController.text,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 24),
                                const Text('To', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _toController.text.isEmpty ? 'Select destination' : _toController.text,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Trip Details
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Departure', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text(
                                    '${_departureDateController.text.isEmpty ? 'Today' : _departureDateController.text} • ${_departureTimeController.text.isEmpty ? 'Now' : _departureTimeController.text}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      if (_tripType == 'Round Trip') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.event_repeat, size: 16, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Return', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(
                                      '${_returnDateController.text.isEmpty ? 'Select date' : _returnDateController.text} • ${_returnTimeController.text.isEmpty ? 'Select time' : _returnTimeController.text}',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      // Vehicle and Price
                      const Text('Trip Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.directions_car, color: Colors.blue[700], size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_selectedVehicle!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      Text('${selectedVehicleData['type']} • ${selectedVehicleData['capacity']} seats', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                                Text(currentPrice, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C2656))),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Trip Type', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text(_tripType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Estimated Distance', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text('${_distanceKm.toStringAsFixed(0)} km', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Estimated Duration', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text(_durationMin >= 60 ? '${_durationMin ~/ 60}h ${(_durationMin % 60).toString().padLeft(2, "0")}m' : '$_durationMin min',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(0xFF4CAF50).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Fare', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              currentPrice,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 22),

                      // ── Estimated fare + breakup (Ola-style) ──
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Estimated fare', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('${_distanceKm.toStringAsFixed(0)} km, ${_durationMin >= 60 ? "${_durationMin ~/ 60} hour" : "$_durationMin min"}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ]),
                        Text(currentPrice, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1C2656))),
                      ]),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                        child: Column(children: [
                          _bkRow(context, 'Base fare', '₹${cBase.toStringAsFixed(0)}'),
                          _bkRow(context, 'Fare for ${_distanceKm.toStringAsFixed(0)} km @ ₹${cPerKm.toStringAsFixed(0)}/km', '₹${cKmCharge.toStringAsFixed(0)}'),
                          if (cPerHour > 0) _bkRow(context, 'Driving time', '₹${cHourCharge.toStringAsFixed(0)}'),
                          if (cDriverAllow > 0) _bkRow(context, 'Driver allowance', '₹${cDriverAllow.toStringAsFixed(0)}'),
                          if (cNightHalt > 0) _bkRow(context, 'Night time allowance', '₹${cNightHalt.toStringAsFixed(0)}'),
                          _bkRow(context, 'Taxes', cGst > 0 ? '₹${cGst.toStringAsFixed(0)} (${cGstPct.toStringAsFixed(0)}%)' : '₹0'),
                        ]),
                      ),

                      const SizedBox(height: 22),
                      // ── Rules & Restrictions (red arrows, dynamic from admin) ──
                      const Text('Rules & Restrictions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...rules.map((r) => _ruleArrowRow(r)),

                      const SizedBox(height: 20),
                      // ── Terms and Conditions (grey bullets) ──
                      const Text('Terms and Conditions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...rules.map((r) => _termBulletRow(r)),

                      const SizedBox(height: 16),
                      // Estimated arrival at destination
                      if (_departureDateTime != null && _durationMin > 0)
                        Row(children: [
                          const Icon(Icons.schedule, size: 18, color: Color(0xFF1C2656)),
                          const SizedBox(width: 8),
                          Text('Reach destination by ~${_fmtTime(_departureDateTime!.add(Duration(minutes: _durationMin)))}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      const SizedBox(height: 14),
                      // Compact Ola-style "Cash · Coupon · Mode" row
                      StatefulBuilder(builder: (context, setSheet) {
                        final payLabel = _paymentMode == 'online' ? 'Online' : (_paymentMode == 'wallet' ? 'Wallet' : 'Cash');
                        final payIcon = _paymentMode == 'online' ? Icons.credit_card : (_paymentMode == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined);
                        Widget item(IconData ic, String label, VoidCallback onTap, {Color? c}) => Expanded(child: InkWell(
                          onTap: onTap,
                          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(children: [
                              Icon(ic, size: 19, color: c ?? const Color(0xFF1C2656)),
                              const SizedBox(height: 4),
                              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
                            ])),
                        ));
                        Widget div() => Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2));
                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.withOpacity(0.22)),
                          ),
                          child: Row(children: [
                            item(payIcon, payLabel, () async {
                              final m = await _pickPayment();
                              if (m != null) setSheet(() => _paymentMode = m);
                            }),
                            div(),
                            item(Icons.local_offer_outlined, _couponDiscount > 0 ? '−₹$_couponDiscount' : 'Coupon', () async {
                              await _pickCoupon(selectedVehicleData);
                              setSheet(() {});
                            }, c: _couponDiscount > 0 ? Colors.green[700] : null),
                            div(),
                            item(Icons.person_outline, _bookingFor, () async {
                              final who = await _pickBookingFor();
                              if (who != null) setSheet(() => _bookingFor = who);
                            }),
                          ]),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              
              // Book button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showFindingDriverDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2656),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Confirm Booking',
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDialogConditionItem(BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey[600]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  void _cancelSearch(BuildContext sheetCtx) {
    const reasons = ['Taking too long', 'Booked by mistake', 'Plan changed', 'Found another ride', 'Other'];
    showModalBottomSheet(context: context, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (rc) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Why are you cancelling?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ...reasons.map((r) => ListTile(title: Text(r), onTap: () async {
          Navigator.pop(rc);
          _pollTimer?.cancel();
          if (_rideId != null) await ApiService.cancelRide(_rideId!, r);
          if (mounted && Navigator.canPop(sheetCtx)) Navigator.pop(sheetCtx);
          if (mounted) Navigator.pop(context);
        })),
        const SizedBox(height: 8),
      ])));
  }

  Future<void> _showFindingDriverDialog() async {
    // Charge the trip fare via the selected method before searching for a driver.
    if (_selectedVehicle != null) {
      final selV = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => <String, dynamic>{});
      final rawFare = ((_tripType == 'Round Trip' ? selV['roundTripFare'] : selV['oneWayFare']) as num?) ?? 0;
      final payable = (rawFare - _couponDiscount).clamp(0, rawFare);
      final paid = await PaymentService.charge(context, method: _paymentMode, amount: payable);
      if (!mounted) return;
      if (!paid) return;
    }
    setState(() {
      _isSearching = true;
    });

    // Selected vehicle's ETA, if reachable
    int? etaMin;
    if (_selectedVehicle != null) {
      final sel = _vehicles.where((v) => v['name'] == _selectedVehicle);
      if (sel.isNotEmpty) etaMin = (sel.first['etaMin'] as num?)?.toInt();
    }

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Actually book the outstation ride then poll backend for driver assignment + completion
        () async {
          await _bookOutstationRide();
          _startStatusPolling((status, ride) {
            if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
                _showDriverAssignedDialog();
              }
            } else if (status == 'completed') {
              _pollTimer?.cancel();
              if (Navigator.canPop(context)) Navigator.of(context).pop();
              // Send user to rating/review screen straight after ride completes
              Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(
                driverName: _driverName.isNotEmpty ? _driverName : 'Pilot',
                vehicleName: _selectedVehicle ?? 'Outstation',
                selectedTip: 0,
                rideId: _rideId,
              )));
            } else if (status == 'cancelled') {
              _pollTimer?.cancel();
            }
          });
        }();

        // Full-screen Ola-style finding-driver view; takes the whole sheet so the
        // map + radar fill the screen. Polling above still pops this sheet on accept.
        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: FindingDriverView(
            pickupLat: _fromLat!,
            pickupLng: _fromLng!,
            dropLat: _toLat,
            dropLng: _toLng,
            pickupAddress: _fromController.text,
            dropAddress: _toController.text,
            fareText: () {
              final sel = _vehicles.where((v) => v['name'] == _selectedVehicle);
              if (sel.isEmpty) return null;
              return (_tripType == 'One Way' ? sel.first['oneWayPrice'] : sel.first['roundTripPrice'])?.toString();
            }(),
            serviceLabel: 'Outstation',
            serviceIcon: Icons.map,
            etaMin: etaMin,
            onCancel: () => _cancelSearch(context),
          ),
        );
      },
    );
  }

  void _showDriverAssignedDialog() {
    setState(() {
      _isSearching = false;
      _driverAssigned = true;
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewPadding.bottom),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
          ),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              Text('Pilot Assigned for Outstation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 12),
              // Prominent OTP/PIN box — driver asks for this to start the ride
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFF1C2656).withOpacity(0.08), const Color(0xFF1C2656).withOpacity(0.02)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1C2656).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: Color(0xFF1C2656), size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Share OTP with pilot', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    const Text('Driver will ask for this 4-digit PIN to start the trip', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1C2656))),
                    child: Text(_rideOtp ?? '----', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1C2656))),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Row(
                  children: [
                    Container(
                      width: 55, height: 55,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(color: Colors.grey[200]!, width: 2),
                        image: _driverPicUrl.isNotEmpty
                            ? DecorationImage(image: NetworkImage(_driverPicUrl), fit: BoxFit.cover)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: _driverPicUrl.isEmpty
                          ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'P',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_driverName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(_rideOtp != null ? 'PIN: $_rideOtp' : 'Outstation pilot', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        [_driverVehicleModel, _driverVehicleNumber].where((s) => s.isNotEmpty).join(' • '),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ])),
                    SizedBox(width: 70, height: 50, child: _driverVehicleImageUrl.isNotEmpty
                        ? Image.network(_driverVehicleImageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, color: Color(0xFF1C2656), size: 40))
                        : Image.asset(_vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => {'image':'assets/images/economy.png'})['image'] as String, fit: BoxFit.contain)),
                  ],
                ),
              ),
              // Driver experience chips (years on platform + total rides)
              if (_driverYearsActive > 0 || _driverTotalRides > 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  if (_driverYearsActive > 0) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.workspace_premium, color: Color(0xFF1C2656), size: 14),
                      const SizedBox(width: 4),
                      Text('${_driverYearsActive}+ yr exp', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1C2656))),
                    ]),
                  ),
                  if (_driverTotalRides > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.directions_car, color: Color(0xFF4CAF50), size: 14),
                        const SizedBox(width: 4),
                        Text('${_driverTotalRides} trips', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4CAF50))),
                      ]),
                    ),
                  ],
                ]),
              ],
              // Trip phase status (only relevant for round-trip outstation in progress)
              if (_tripType == 'Round Trip' && _outstationPhase != 'enroute') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(
                      _outstationPhase == 'at_destination' ? Icons.flag :
                      _outstationPhase == 'returning' ? Icons.replay : Icons.directions_car,
                      color: AppTheme.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _outstationPhase == 'at_destination' ? 'At destination — driver waiting'
                      : _outstationPhase == 'returning' ? 'Return journey in progress'
                      : 'In transit',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                    )),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () {
                      if (_driverPhone.isEmpty) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Driver: $_driverName • $_driverPhone')));
                    },
                    icon: const Icon(Icons.call, color: Colors.green), label: Text('Call', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).colorScheme.onSurface, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () {
                      if (_rideId != null) {
                        Share.share('I\'m on a Gora outstation trip — follow me: ${AppConfig.serverBaseUrl}/track/$_rideId');
                      }
                    },
                    icon: const Icon(Icons.share, color: Color(0xFF1C2656)), label: Text('Share', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).colorScheme.onSurface, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2),
                  )),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
                    final currentPrice = _tripType == 'One Way' ? selectedVehicleData['oneWayPrice'] : selectedVehicleData['roundTripPrice'];
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OutstationRideDetailsScreen(
                          inquiryId: _rideId != null ? 'GC-OUT-${_rideId!.substring(_rideId!.length - 6).toUpperCase()}' : 'GC-OUT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                          fromLocation: _fromController.text.isEmpty ? 'Current Location' : _fromController.text,
                          toLocation: _toController.text.isEmpty ? 'Select Destination' : _toController.text,
                          vehicleName: _selectedVehicle!,
                          vehicleType: selectedVehicleData['type'] as String? ?? '',
                          capacity: selectedVehicleData['capacity'] as String? ?? '4',
                          tripType: _tripType,
                          departureDate: _departureDateController.text.isEmpty ? 'Today' : _departureDateController.text,
                          departureTime: _departureTimeController.text.isEmpty ? 'Now' : _departureTimeController.text,
                          returnDate: _tripType == 'Round Trip' ? (_returnDateController.text.isEmpty ? 'Not Set' : _returnDateController.text) : null,
                          returnTime: _tripType == 'Round Trip' ? (_returnTimeController.text.isEmpty ? 'Not Set' : _returnTimeController.text) : null,
                          price: currentPrice,
                          estimatedDistance: '${_distanceKm.toStringAsFixed(0)} km',
                          estimatedDuration: _durationMin >= 60 ? '${_durationMin ~/ 60}h ${(_durationMin % 60).toString().padLeft(2, "0")}m' : '$_durationMin min',
                          driverName: _driverName,
                          driverRating: _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—',
                          driverExperience: '—',
                          vehicleNumber: _driverVehicleNumber.isEmpty ? '—' : _driverVehicleNumber,
                          vehicleModel: _driverVehicleModel.isEmpty ? '—' : _driverVehicleModel,
                          vehicleColor: '—',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C2656),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Trip Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: TextButton(onPressed: () => _showCancelReasonDialog(), child: const Text('Cancel Trip', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)))),
            ],
          )),
        );
      },
    );
  }

  void _showCancelReasonDialog() {
    final List<String> reasons = ['Plan changed', 'Pilot is too far', 'Found another ride', 'Wait time is too long', 'Wrong location selected', 'Other'];
    String? selectedReason;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const Text('Cancel Trip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Please select a reason for cancellation', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 20),
                  ...reasons.map((reason) => RadioListTile<String>(title: Text(reason, style: const TextStyle(fontSize: 15)), value: reason, groupValue: selectedReason, activeColor: const Color(0xFF1C2656), contentPadding: EdgeInsets.zero, onChanged: (value) => setDialogState(() => selectedReason = value))),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: selectedReason == null ? null : () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Confirm Cancellation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)))),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRideCompletedDialog() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Trip Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your outstation trip has been completed successfully.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => RatingScreen(driverName: 'Rahul Sharma', vehicleName: _selectedVehicle!, selectedTip: 0))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate Your Experience', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
            ],
          ),
        );
      },
    );
  }

  void _navigateToBookingInquiry() {
    final inquiryId = '${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingInquiryScreen(
          inquiryId: inquiryId,
          pickupLocation: _fromController.text.isNotEmpty 
              ? _fromController.text 
              : '5Centers, 9, 5Centers, Jodhpur, Rajasthan, India, 342011',
          dropLocation: _toController.text.isNotEmpty 
              ? _toController.text 
              : 'Jaipur railway station, Gopalbari, Jaipur, Rajasthan, India',
          carType: '$_selectedVehicle Luxury',
          gearType: 'Automatic',
          tripType: _tripType,
          tripStartDate: _departureDateController.text.isNotEmpty 
              ? _departureDateController.text 
              : '2025-12-05',
          tripEndDate: _tripType == 'Round Trip' && _returnDateController.text.isNotEmpty
              ? _returnDateController.text 
              : '2025-12-06',
          tripTime: _departureTimeController.text.isNotEmpty 
              ? _departureTimeController.text 
              : '10:07 PM',
        ),
      ),
    );
  }
}
