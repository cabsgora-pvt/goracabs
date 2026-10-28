import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';
import '../services/location_service.dart';
import '../utils/map_markers.dart';
import '../utils/place_names.dart';
import '../services/payment_service.dart';
import '../utils/polyline_utils.dart';
import '../utils/fare_lines.dart';
import '../utils/ride_booking.dart';

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
  String _tripType = 'One Way';
  bool _showTripDetails = false;
  bool _showVehicleSelection = false;
  bool _locationConfirmed = false;

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

  // A booked trip is tracked on ActiveRideScreen (see _confirmOutstation), so
  // this screen holds no live ride state.

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
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Format DateTime as "DD/MM, h:MM AM/PM"
  String _formatDateTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}, $h:$mm $ampm';
  }

  /// How much of the screen the bottom sheet covers at rest.
  double get _sheetRestFraction => _locationConfirmed ? 0.4 : 0.15;

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
        Widget pickRow(String label, DateTime? dt, bool isReturn) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PickerPill(
            icon: isReturn ? Icons.event_repeat : Icons.event_outlined,
            label: label,
            value: dt != null ? _fmtDateShort(dt) : 'Select date & time',
            placeholder: dt == null,
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
          ),
        );
        final isRT = _tripType == 'Round Trip';
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(bottom: 14),
            Text(isRT ? 'Schedule round trip' : 'Schedule trip', style: RideUi.title(ctx, size: 22)),
            const SizedBox(height: 16),
            pickRow('Leave on', _departureDateTime, false),
            if (isRT) pickRow('Return by', _returnDateTime, true),
            const SizedBox(height: 6),
            PrimaryRideButton(
              label: 'Confirm',
              onPressed: () { if (mounted && _fromLat != null && _toLat != null) _loadOutstationFares(); Navigator.pop(ctx); },
            ),
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
        padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(bottom: 14),
          Text('Add a city / stop', style: RideUi.title(ctx, size: 20)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: RideUi.fieldBox(ctx),
            child: Row(children: [
              Icon(Icons.search, size: 20, color: RideUi.muted(ctx)),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: ctrl, autofocus: true,
                decoration: RideUi.bareInput(ctx, 'Search city or place', vertical: 14),
                style: RideUi.body(ctx, size: 14.5, weight: FontWeight.w600),
                onChanged: (q) {
                  deb?.cancel();
                  if (q.trim().length < 2) { setSheet(() => sugg = []); return; }
                  deb = Timer(const Duration(milliseconds: 350), () async {
                    final r = await ApiService.placesAutocomplete(q);
                    setSheet(() => sugg = r);
                  });
                })),
            ]),
          ),
          const SizedBox(height: 8),
          ...sugg.take(5).map((s) => PlaceSuggestionTile(
            title: s['mainText']?.toString() ?? s['description']?.toString() ?? '',
            subtitle: s['mainText'] != null ? s['secondaryText']?.toString() : null,
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
      if (oneWay['available'] == false) {
        if (!mounted) return;
        setState(() { _vehicles = []; _loadingFares = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((oneWay['message'] as String?) ?? 'Outstation not available from here')));
        return;
      }
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
            // Shown on the empty-return line of the breakdown (display only).
            'owEmptyReturnPct': ow['emptyReturnPercent'] ?? 0,
            'rtEmptyReturnPct': rt?['emptyReturnPercent'] ?? 0,
            'etaMin': ow['etaMin'],
            // One signed quote per trip type — booking replays the matching one.
            'owQuoteToken': ow['quoteToken'],
            'rtQuoteToken': rt?['quoteToken'],
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

  /// Razorpay order/payment/signature of the payment made for this booking.
  Map<String, String>? _prepaidProof;

  /// Books the outstation trip and returns the server's answer; [bookAndTrack]
  /// reports a failure and opens the live ride screen on success.
  Future<Map<String, dynamic>> _bookOutstationRide() async {
    if (_fromLat == null || _toLat == null || _selectedVehicle == null) {
      return {'error': 'Choose where from, where to and a vehicle first'};
    }
    final isRoundTrip = _tripType == 'Round Trip';
    final selVehicle = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final rawFare = (isRoundTrip ? selVehicle['roundTripFare'] : selVehicle['oneWayFare']) as num? ?? 0;
    final fare = (rawFare - _couponDiscount).clamp(0, rawFare);

    return ApiService.bookRide({
        'pickupAddress': _fromController.text,
        'dropAddress': _toController.text,
        'pickupLat': _fromLat, 'pickupLng': _fromLng,
        'dropLat': _toLat, 'dropLng': _toLng,
        'service': 'outstation',
        'tripType': isRoundTrip ? 'round_trip' : 'one_way',
        'vehicleType': _selectedVehicle,
        'fare': fare,
        'quoteToken': isRoundTrip ? selVehicle['rtQuoteToken'] : selVehicle['owQuoteToken'],
        'distance': _distanceKm,
        'duration': _durationMin,
        // The towns, not the addresses: these label the trip "Gurugram → Jaipur"
        // on the ride screens, the driver's request and the admin list.
        'cityFrom': cityOf(_fromController.text),
        'cityTo': cityOf(_toController.text),
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
        if (_prepaidProof != null) 'prepaid': _prepaidProof,
      });
  }

  @override
  Widget build(BuildContext context) {
    // Use the clean full-screen From/To picker (same as taxi) before confirmation —
    // avoids the buggy in-place panel + Stack layout that was causing hit-test errors.
    if (_showMapPicker) return _buildOutstationMapPicker();
    if (!_locationConfirmed) return _buildOutstationLocationScreen();
    final dur = _durationMin >= 60 ? '${_durationMin ~/ 60}h ${(_durationMin % 60).toString().padLeft(2, '0')}m' : '$_durationMin min';
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: RideUi.surface(context),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) => Stack(
              children: [
                PlaceGlyphs(builder: (context, glyphs) => GoogleMap(
                  initialCameraPosition: const CameraPosition(target: LatLng(23.0225, 72.5714), zoom: 6),
                  onMapCreated: (c) {
                    _mapController = c;
                    _fitMapToRoute();
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  // The route fit lands in the band the sheet leaves visible.
                  // Without this the bounds were fitted to the WHOLE map, most of
                  // it under the sheet, and the strip still showing was the
                  // country north of the route (Sirohi / Mount Abu for a
                  // Rajkot → Ahmedabad trip).
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    bottom: box.maxHeight * _sheetRestFraction,
                  ),
                  markers: {
                    if (_fromLat != null && _fromLng != null)
                      Marker(
                        markerId: const MarkerId('from'),
                        position: LatLng(_fromLat!, _fromLng!),
                        anchor: glyphs.pickupAnchor,
                        icon: glyphs.pickup,
                        infoWindow: InfoWindow(title: 'From', snippet: _fromController.text),
                      ),
                    if (_toLat != null && _toLng != null)
                      Marker(
                        markerId: const MarkerId('to'),
                        position: LatLng(_toLat!, _toLng!),
                        anchor: glyphs.dropAnchor,
                        icon: glyphs.drop,
                        infoWindow: InfoWindow(title: 'To', snippet: _toController.text),
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
                )),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 12,
                  child: MapCircleButton(icon: Icons.arrow_back, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
                ),
                DraggableScrollableSheet(
                  // Key forces the sheet to recreate when confirmed state flips,
                  // so initialChildSize is re-applied and the panel auto-expands
                  key: ValueKey('outstation-sheet-${_locationConfirmed ? 'confirmed' : 'pick'}'),
                  initialChildSize: _sheetRestFraction,
                  minChildSize: _sheetRestFraction,
                  maxChildSize: _locationConfirmed ? 0.85 : 0.15,
                  builder: (context, scrollController) {
                    return RideSheetContainer(
                      child: Column(
                        children: [
                          const Padding(padding: EdgeInsets.only(top: 10), child: SheetHandle(bottom: 10)),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              children: [
                                // Route at the top: from → (stops) → to, distance, add a stop
                                RouteInputBlock(
                                  rows: [
                                    RouteFieldRow(
                                      marker: RouteMarkerKind.pickup,
                                      child: Text(_fromController.text.isEmpty ? 'Pickup' : _fromController.text,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14, weight: FontWeight.w600)),
                                    ),
                                    // Multi-city stops (fare sums the legs pickup → stops → drop)
                                    ..._stops.asMap().entries.map((e) => RouteFieldRow(
                                      marker: RouteMarkerKind.stop,
                                      trailing: IconButton(
                                        tooltip: 'Remove stop',
                                        onPressed: () { setState(() => _stops.removeAt(e.key)); _loadOutstationFares(); },
                                        icon: Icon(Icons.close, size: 18, color: RideUi.muted(context)),
                                      ),
                                      child: Text(e.value['address'] as String? ?? 'Stop',
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14, weight: FontWeight.w600)),
                                    )),
                                    RouteFieldRow(
                                      marker: RouteMarkerKind.drop,
                                      child: Text(_toController.text.isEmpty ? 'Destination' : _toController.text,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 14, weight: FontWeight.w600)),
                                    ),
                                  ],
                                  footer: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Row(children: [
                                      Icon(Icons.route, size: 16, color: RideUi.ink(context)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _loadingFares
                                              ? 'Calculating distance & duration...'
                                              : _distanceKm > 0 ? '${_distanceKm.toStringAsFixed(0)} km · $dur' : 'Estimated distance: —',
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: RideUi.body(context, size: 13, weight: FontWeight.w700),
                                        ),
                                      ),
                                      Flexible(child: TextButton.icon(
                                        onPressed: _addStopCity,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add city / stop', maxLines: 1, overflow: TextOverflow.ellipsis),
                                        style: TextButton.styleFrom(
                                          foregroundColor: RideUi.accent(context),
                                          visualDensity: VisualDensity.compact,
                                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                      )),
                                    ]),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Trip type
                                ChoiceSegment<String>(
                                  options: const [
                                    ChoiceOption('One Way', 'One-way', subtitle: 'Get dropped off'),
                                    ChoiceOption('Round Trip', 'Round trip', subtitle: 'Keep the car till return'),
                                  ],
                                  selected: _tripType,
                                  onChanged: _selectTripType,
                                ),
                                const SizedBox(height: 4),
                                _sectionHeader('Trip Details', _showTripDetails, () => setState(() => _showTripDetails = !_showTripDetails)),
                                // "Booking for … SELECT" — opens the schedule drawer (Ola-style)
                                if (_showTripDetails)
                                  PickerPill(
                                    icon: Icons.event_outlined,
                                    label: 'Booking for',
                                    value: _departureDateTime != null
                                        ? '${_fmtDateShort(_departureDateTime!)}${_tripType == 'Round Trip' && _returnDateTime != null ? '  —  ${_fmtDateShort(_returnDateTime!)}' : ''}'
                                        : 'now',
                                    trailingText: 'SELECT',
                                    onTap: _showScheduleDrawer,
                                  ),
                                if (_showTripDetails && _departureDateTime != null && _durationMin > 0)
                                  Padding(padding: const EdgeInsets.only(top: 10), child: NoticeRow(
                                    'Arriving by ${_formatDateTime(_departureDateTime!.add(Duration(minutes: _durationMin)))}',
                                    icon: Icons.flag_outlined,
                                    tone: NoticeTone.success,
                                  )),
                                if (_showTripDetails)
                                  const SizedBox(height: 8),
                                _sectionHeader('Select Vehicle', _showVehicleSelection, () => setState(() => _showVehicleSelection = !_showVehicleSelection)),
                                // Ola-style horizontal category chips
                                if (_showVehicleSelection && _vehicles.isNotEmpty)
                                  SizedBox(
                                    height: 40,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: () {
                                        final cats = ['All', ...{for (final v in _vehicles) v['cat'] as String}];
                                        return cats.map((c) => Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: ServiceChip(label: c, selected: _vehCategory == c, onTap: () => setState(() => _vehCategory = c)),
                                        )).toList();
                                      }(),
                                    ),
                                  ),
                                if (_showVehicleSelection && _vehicles.isNotEmpty)
                                  const SizedBox(height: 12),
                                if (_showVehicleSelection && _loadingFares && _vehicles.isEmpty)
                                  const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                                if (_showVehicleSelection)
                                  Column(
                                    children: _vehicles
                                        .where((v) => _vehCategory == 'All' || v['cat'] == _vehCategory)
                                        .map((v) => _buildVehicleCard(v)).toList(),
                                  ),
                                if (_showVehicleSelection)
                                  const SizedBox(height: 12),
                                if (_showVehicleSelection)
                                  _buildTripConditions(context),
                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                    },
                  ),
              ],
            )),
          ),
          if (_locationConfirmed)
            PrimaryCtaBar(
              label: _selectedVehicle == null ? 'Select a vehicle' : 'Book Trip',
              onPressed: _selectedVehicle == null ? null : () {
                _showBookingConfirmationDialog();
              },
            ),
        ],
      ),
    );
  }

  /// A one-tap section header: the whole row is the target, not just the
  /// title text and the chevron.
  Widget _sectionHeader(String title, bool open, VoidCallback onTap) => GestureDetector(
    // Opaque: a tap on the empty middle of the row used to fall through
    // (deferToChild), so it took a second, better-aimed tap to open.
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(title, style: RideUi.title(context, size: 18)),
          const Spacer(),
          Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: RideUi.muted(context)),
        ],
      ),
    ),
  );

  void _selectTripType(String type) {
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
  }

  Future<void> _confirmLocations() async {
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
      _locationConfirmed = true;
      _showTripDetails = true;
    });
    _loadOutstationFares();
  }

  // Clean full-screen From/To picker — mirrors the taxi screen UX so behaviour is consistent
  Widget _buildOutstationLocationScreen() {
    // Whichever field is empty drives the suggestion list shown below
    final activeIsFrom = _fromController.text.trim().isEmpty || _toController.text.trim().isNotEmpty == false;
    final suggestions = activeIsFrom ? _fromSuggestions : _toSuggestions;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: RideUi.surface(context),
      body: Column(children: [
        const ServiceHeader(title: 'Intercity', subtitle: 'Outstation trips — one way or round trip'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: RouteInputBlock(rows: [
            RouteFieldRow(
              marker: RouteMarkerKind.pickup,
              trailing: MapPickAction(tooltip: 'Pick From on map', onTap: () => _openMapPicker(forFrom: true)),
              child: _buildLocationInput(_fromController, 'From city'),
            ),
            RouteFieldRow(
              marker: RouteMarkerKind.drop,
              trailing: MapPickAction(tooltip: 'Pick To on map', onTap: () => _openMapPicker(forFrom: false)),
              child: _buildLocationInput(_toController, 'To city'),
            ),
          ]),
        ),
        const RideDivider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              // Always-visible quick action: use GPS to set From field
              if (activeIsFrom)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
                    child: Icon(Icons.my_location, color: RideUi.ink(context), size: 18),
                  ),
                  title: Text('Use my current location', style: RideUi.body(context, size: 14, weight: FontWeight.w700)),
                  subtitle: Text('Fetch GPS and fill From', style: RideUi.caption(context, size: 12)),
                  onTap: _initCurrentLocation,
                ),
              if (activeIsFrom) const RideDivider(indent: 56),
              if (suggestions.isNotEmpty) ...[
                ...suggestions.map((s) => PlaceSuggestionTile(
                  title: s['mainText']?.toString() ?? '',
                  subtitle: s['secondaryText']?.toString(),
                  onTap: () => _selectSuggestion(s, isFrom: activeIsFrom),
                )),
              ] else if (!activeIsFrom)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
                      child: Icon(Icons.search, size: 30, color: RideUi.muted(context)),
                    ),
                    const SizedBox(height: 12),
                    Text('Type a destination city', style: RideUi.caption(context, size: 14)),
                  ]),
                ),
            ],
          ),
        ),
        PrimaryCtaBar(label: 'Confirm Location', onPressed: _confirmLocations),
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
    return ServiceMapPicker(
      title: _pickingFrom ? 'Pick From location' : 'Pick To location',
      forPickup: _pickingFrom,
      address: _pickerAddress,
      onBack: () => setState(() => _showMapPicker = false),
      onLocate: () async {
        final pos = await LocationService.getCurrentLocation();
        if (pos == null) return;
        final ll = LatLng(pos.latitude, pos.longitude);
        _pickerMapController?.animateCamera(CameraUpdate.newLatLngZoom(ll, 14));
      },
      map: GoogleMap(
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
      onConfirm: _pickerAddress.isEmpty ? null : () {
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
    );
  }

  Widget _buildLocationInput(TextEditingController controller, String hint) {
    final isFrom = identical(controller, _fromController);
    return TextField(
      controller: controller,
      onChanged: (q) => _searchPlaces(q, isFrom: isFrom),
      textAlignVertical: TextAlignVertical.center,
      decoration: RideUi.bareInput(context, hint, fontSize: 15),
      style: RideUi.body(context, size: 15, weight: FontWeight.w600),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    final currentPrice = _tripType == 'One Way' ? v['oneWayPrice'] : v['roundTripPrice'];
    // Pick the breakdown for the current trip type
    final Map bk = (_tripType == 'Round Trip' ? v['rtBreakdown'] : v['owBreakdown']) as Map? ?? {};
    final num perKm = (bk['perKm'] as num?) ?? 0;

    final img = (v['networkImage'] as String?) ?? '';
    final tagline = vehicleTagline(v['name'] as String? ?? '');
    // Round trip → show the per-km rate; one-way → show the total fare (Ola behaviour)
    final priceLabel = _tripType == 'Round Trip' ? '₹${perKm.toStringAsFixed(0)}/km' : currentPrice.toString();

    return VehicleOptionRow(
      selected: isSelected,
      onTap: () => setState(() => _selectedVehicle = v['name']),
      leading: VehicleThumb(
        networkUrl: img.isNotEmpty ? img : null,
        asset: img.isNotEmpty ? null : (v['image'] as String? ?? 'assets/images/economy.png'),
        fallbackIcon: (v['icon'] as IconData?) ?? Icons.directions_car,
      ),
      name: v['name'] as String,
      seats: v['capacity'] != null ? '${v['capacity']}' : null,
      subtitle: tagline,
      // ⓘ details (fleet, features, fare breakdown, inclusions)
      badge: InkWell(
        onTap: () => _showCabDetailSheet(v, bk),
        customBorder: const CircleBorder(),
        child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.info_outline, size: 17, color: RideUi.muted(context))),
      ),
      price: priceLabel,
    );
  }

  /// Every component of the quote for the chosen trip type, summing to its fare.
  List<FareLine> _fareLines(Map<String, dynamic> v, Map bk) {
    final rt = _tripType == 'Round Trip';
    final total = ((rt ? v['roundTripFare'] : v['oneWayFare']) as num?) ?? 0;
    return outstationFareLines(bk, total,
        distanceKm: _distanceKm,
        emptyReturnPercent: ((rt ? v['rtEmptyReturnPct'] : v['owEmptyReturnPct']) as num?) ?? 0);
  }

  static String _money(num v) => v < 0 ? '−₹${(-v).toStringAsFixed(0)}' : '₹${v.toStringAsFixed(0)}';

  // Ola-style cab detail sheet — fleet, features, fare breakdown, inclusions
  void _showCabDetailSheet(Map<String, dynamic> v, Map bk) {
    final currentPrice = _tripType == 'One Way' ? v['oneWayPrice'] : v['roundTripPrice'];
    final img = (v['networkImage'] as String?) ?? '';
    final cap = int.tryParse('${v['capacity']}') ?? 4;
    final fleet = cap >= 6 ? 'Ertiga, Innova, Marazzo or similar' : (cap >= 4 ? 'Swift Dzire, Etios, Aura or similar' : 'WagonR, Celerio or similar');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.92, expand: false,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 10, 16, 20), children: [
          const SheetHandle(bottom: 14),
          SummaryVehicleTile(
            leading: VehicleThumb(
              networkUrl: img.isNotEmpty ? img : null,
              asset: img.isNotEmpty ? null : (v['image'] as String? ?? 'assets/images/economy.png'),
              fallbackIcon: (v['icon'] as IconData?) ?? Icons.directions_car,
              size: 56,
            ),
            name: v['name'] as String? ?? '',
            caption: '$cap seats • AC • Outstation',
            price: currentPrice.toString(),
          ),
          const SizedBox(height: 16),
          // Feature icons row
          Row(children: [
            Expanded(child: _featBig(Icons.ac_unit, 'Comfy ride')),
            Expanded(child: _featBig(Icons.account_balance_wallet_outlined, 'Pocket-friendly')),
            Expanded(child: _featBig(Icons.verified_user_outlined, 'Verified driver')),
          ]),
          const SizedBox(height: 16),
          // Our fleet
          InfoLine(Icons.directions_car_outlined, 'Our fleet', subtitle: fleet),
          const ServiceSection('Fare breakup', top: 12),
          ..._fareLines(v, bk).map((l) => _bkRow(context, l.label, _money(l.amount))),
          const RideDivider(vertical: 6),
          _bkRow(context, 'Estimated total', currentPrice.toString(), bold: true),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () { Navigator.pop(ctx); _showInclusionsSheet(bk); },
              style: TextButton.styleFrom(foregroundColor: RideUi.accent(context)),
              icon: const Icon(Icons.info_outline, size: 16), label: const Text('View inclusions & exclusions')),
          ),
          const SizedBox(height: 6),
          PrimaryRideButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
        ]),
      ),
    );
  }

  Widget _featBig(IconData ic, String label) => Column(children: [
    Container(width: 46, height: 46, decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
      child: Icon(ic, color: RideUi.ink(context), size: 22)),
    const SizedBox(height: 6),
    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 11, weight: FontWeight.w700)),
  ]);

  // Ola-style inclusions & exclusions bottom sheet
  void _showInclusionsSheet(Map bk) {
    final num kmLimit = (bk['kmLimit'] as num?) ?? 0;
    final num extraKmRate = (bk['extraKmRate'] as num?) ?? 0;
    final num driverAllowance = (bk['driverAllowance'] as num?) ?? 0;
    final num gstPercent = (bk['gstPercent'] as num?) ?? 0;
    final num nightHalt = (bk['nightHalt'] as num?) ?? 0;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(bottom: 14),
          Text('Fare Inclusions', style: RideUi.title(ctx, size: 18)),
          const SizedBox(height: 8),
          _incRow(true, kmLimit > 0 ? '${kmLimit.toStringAsFixed(0)} km included in fare' : 'Distance-based fare'),
          _incRow(true, 'Base fare + per-km + driving time'),
          if (driverAllowance > 0) _incRow(true, 'Driver allowance (₹${driverAllowance.toStringAsFixed(0)})'),
          if (nightHalt > 0) _incRow(true, 'Night halt charge included'),
          _incRow(true, 'Pickup & drop at your chosen points'),
          const SizedBox(height: 16),
          Text('Exclusions (pay extra)', style: RideUi.title(ctx, size: 18)),
          const SizedBox(height: 8),
          if (extraKmRate > 0) _incRow(false, 'Extra distance beyond limit — ₹${extraKmRate.toStringAsFixed(0)}/km'),
          _incRow(false, 'Toll, parking & state permit charges'),
          if (gstPercent == 0) _incRow(false, 'GST as applicable'),
          _incRow(false, 'Any waiting beyond free time'),
          const SizedBox(height: 18),
          PrimaryRideButton(label: 'Got it', onPressed: () => Navigator.pop(ctx)),
        ]),
      ),
    );
  }

  Widget _incRow(bool included, String text) => InfoLine(
    included ? Icons.check : Icons.close,
    text,
    iconColor: included ? const Color(0xFF15803D) : const Color(0xFFB45309),
  );

  Widget _bkRow(BuildContext context, String l, String v, {bool bold = false, Color? color}) =>
      SummaryRow(l, v, bold: bold, valueColor: color);

  Widget _buildTripConditions(BuildContext context) {
    return CollapsibleInfo(
      // Re-created per trip type so the list matches the chosen trip.
      key: ValueKey('conditions-$_tripType'),
      title: '$_tripType Trip Conditions',
      icon: Icons.info_outline,
      children: [
        const InfoLine(Icons.toll, 'Tolls and state taxi extra pay'),
        const InfoLine(Icons.local_parking, 'Parking charges extra'),
        if (_tripType != 'One Way') ...const [
          InfoLine(Icons.route, 'Minimum per day 250km running'),
          InfoLine(Icons.add_road, 'Per km will be charged for extra km'),
          InfoLine(Icons.person_outline, 'Driver allowance per 24 hours - ₹250'),
          InfoLine(Icons.nightlight_outlined, 'Night time drive allowance (11:00PM - 06:00AM) - ₹250/night'),
        ],
        const SizedBox(height: 6),
        const NoticeRow('Customer - pay the driver directly', icon: Icons.payments_outlined, tone: NoticeTone.warning),
      ],
    );
  }

  void _showBookingConfirmationDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final currentPrice = _tripType == 'One Way' ? selectedVehicleData['oneWayPrice'] : selectedVehicleData['roundTripPrice'];
    // Fare breakdown for the chosen trip type → drives the Ola breakup + rules
    final Map cbk = (_tripType == 'Round Trip' ? selectedVehicleData['rtBreakdown'] : selectedVehicleData['owBreakdown']) as Map? ?? {};
    final num cPerHour = (cbk['perHour'] as num?) ?? 0;
    final num cDriverAllow = (cbk['driverAllowance'] as num?) ?? 0;
    final num cNightHalt = (cbk['nightHalt'] as num?) ?? 0;
    final num cExtraKm = (cbk['extraKmRate'] as num?) ?? 0;
    final String cityTo = cityOf(_toController.text);
    // Dynamic Rules & Restrictions (all values come from admin zone pricing)
    final List<String> rules = [
      'Excludes toll costs, parking, permits and state tax',
      if (cPerHour > 0) '₹${cPerHour.toStringAsFixed(0)}/hr will be charged for additional hours',
      if (cExtraKm > 0) '₹${cExtraKm.toStringAsFixed(0)}/km will be charged for extra km',
      if (cDriverAllow > 0) 'Driver allowance per 24 hours - ₹${cDriverAllow.toStringAsFixed(0)}',
      if (cNightHalt > 0) 'Night time allowance (11:00 PM - 06:00 AM) - ₹${cNightHalt.toStringAsFixed(0)}/night',
      'Extra fare may apply if you don\'t end trip at ${cityTo.isEmpty ? "drop city" : cityTo}',
    ];
    final img = (selectedVehicleData['networkImage'] as String?) ?? '';
    final dur = _durationMin >= 60 ? '${_durationMin ~/ 60}h ${(_durationMin % 60).toString().padLeft(2, "0")}m' : '$_durationMin min';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return RideSheetContainer(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SheetHandle(),
                    Row(children: [
                      Expanded(child: Text('$_tripType Trip', style: RideUi.title(context, size: 22))),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ]),
                  ]),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Vehicle and price
                        SummaryVehicleTile(
                          leading: VehicleThumb(
                            networkUrl: img.isNotEmpty ? img : null,
                            asset: img.isNotEmpty ? null : (selectedVehicleData['image'] as String? ?? 'assets/images/economy.png'),
                            fallbackIcon: Icons.directions_car,
                            size: 48,
                          ),
                          name: _selectedVehicle!,
                          caption: '${selectedVehicleData['type']} • ${selectedVehicleData['capacity']} seats',
                          price: currentPrice,
                        ),
                        const SizedBox(height: 16),
                        // Pickup and drop
                        TripRouteSummary(
                          pickup: _fromController.text.isEmpty ? 'Current Location' : _fromController.text,
                          drop: _toController.text.isEmpty ? 'Select destination' : _toController.text,
                          maxLines: 2,
                          fontSize: 14,
                        ),
                        const SizedBox(height: 14),
                        PickerPill(
                          icon: Icons.event_outlined,
                          label: 'Departure',
                          value: '${_departureDateController.text.isEmpty ? 'Today' : _departureDateController.text} • ${_departureTimeController.text.isEmpty ? 'Now' : _departureTimeController.text}',
                        ),
                        if (_tripType == 'Round Trip') ...[
                          const SizedBox(height: 8),
                          PickerPill(
                            icon: Icons.event_repeat,
                            label: 'Return',
                            value: '${_returnDateController.text.isEmpty ? 'Select date' : _returnDateController.text} • ${_returnTimeController.text.isEmpty ? 'Select time' : _returnTimeController.text}',
                          ),
                        ],
                        // Estimated arrival at destination
                        if (_departureDateTime != null && _durationMin > 0) ...[
                          const SizedBox(height: 8),
                          NoticeRow('Reach destination by ~${_fmtTime(_departureDateTime!.add(Duration(minutes: _durationMin)))}', icon: Icons.schedule),
                        ],

                        // Trip summary
                        const ServiceSection('Trip Summary', top: 20),
                        SummaryRow('Trip Type', _tripType),
                        SummaryRow('Estimated Distance', '${_distanceKm.toStringAsFixed(0)} km'),
                        SummaryRow('Estimated Duration', dur),

                        // ── Estimated fare + breakup (Ola-style) ──
                        ServiceSection('Estimated fare',
                            subtitle: '${_distanceKm.toStringAsFixed(0)} km, ${_durationMin >= 60 ? "${_durationMin ~/ 60} hour" : "$_durationMin min"}',
                            top: 16),
                        RideTile(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Column(children: [
                            ..._fareLines(selectedVehicleData, cbk).map((l) => _bkRow(context, l.label, _money(l.amount))),
                            const RideDivider(vertical: 6),
                            _bkRow(context, 'Total Fare', currentPrice, bold: true),
                          ]),
                        ),

                        const SizedBox(height: 16),
                        // ── Rules & Restrictions (dynamic from admin) ──
                        CollapsibleInfo(
                          title: 'Rules & Restrictions',
                          icon: Icons.gavel_outlined,
                          initiallyExpanded: true,
                          children: rules.map((r) => InfoLine(Icons.chevron_right, r)).toList(),
                        ),
                        const SizedBox(height: 10),
                        // ── Terms and Conditions ──
                        CollapsibleInfo(
                          title: 'Terms and Conditions',
                          icon: Icons.description_outlined,
                          children: rules.map((r) => InfoLine(Icons.circle, r, iconColor: RideUi.muted(context))).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Payment · Coupon · Who's travelling
                        StatefulBuilder(builder: (context, setSheet) {
                          final payLabel = _paymentMode == 'online' ? 'Online' : (_paymentMode == 'wallet' ? 'Wallet' : 'Cash');
                          final payIcon = _paymentMode == 'online' ? Icons.credit_card : (_paymentMode == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined);
                          return Row(children: [
                            Expanded(child: RidePillChip(icon: payIcon, label: payLabel, onTap: () async {
                              final m = await _pickPayment();
                              if (m != null) setSheet(() => _paymentMode = m);
                            })),
                            const SizedBox(width: 8),
                            Expanded(child: RidePillChip(
                              icon: Icons.local_offer_outlined,
                              label: _couponDiscount > 0 ? '−₹$_couponDiscount' : 'Coupon',
                              labelColor: _couponDiscount > 0 ? Colors.green[700] : null,
                              onTap: () async {
                                await _pickCoupon(selectedVehicleData);
                                setSheet(() {});
                              },
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: RidePillChip(icon: Icons.person_outline, label: _bookingFor, onTap: () async {
                              final who = await _pickBookingFor();
                              if (who != null) setSheet(() => _bookingFor = who);
                            })),
                          ]);
                        }),
                      ],
                    ),
                  ),
                ),

                // Book button
                PrimaryCtaBar(
                  label: 'Confirm Booking',
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmOutstation();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Charge, book once, then track the trip on the live ride screen.
  ///
  /// Outstation is paid before it is booked, as it always has been. What changes
  /// is the failure after payment: the booking error used to be swallowed, so a
  /// rider who had just paid was left on "Finding your driver" for a trip that
  /// did not exist, with nothing to tell support. They are now told plainly,
  /// told not to pay again, and stay on this screen.
  Future<void> _confirmOutstation() async {
    var paidUpfront = false;
    _prepaidProof = null;
    if (_selectedVehicle != null) {
      final selV = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => <String, dynamic>{});
      final rawFare = ((_tripType == 'Round Trip' ? selV['roundTripFare'] : selV['oneWayFare']) as num?) ?? 0;
      final payable = (rawFare - _couponDiscount).clamp(0, rawFare);
      final paid = await PaymentService.chargeDetailed(context, method: _paymentMode, amount: payable);
      if (!mounted || !paid.success) return;
      paidUpfront = _paymentMode != 'cash' && payable > 0;
      // Sent with the booking so the server can tie this payment to the ride
      // (and refund it if no driver is ever found). Wallet needs nothing: the
      // server finds the rider's own debit itself.
      _prepaidProof = paid.bookingProof;
    }
    await bookAndTrack(
      context,
      book: _bookOutstationRide,
      // Shown on the ride screen as the amount already paid.
      couponDiscount: _couponDiscount,
      failureMessage: paidUpfront
          ? (error) => 'Your payment went through, but the trip could not be booked ($error). '
              'Please contact support with this message. Do not pay again.'
          : null,
    );
  }
}

/// The one-line description under a vehicle's name, from the vehicle type
/// itself — the same wording as the taxi list. It used to come from seat count
/// alone, so every 4-seater (Cab, Prime Sedan) read "Top sedans".
String vehicleTagline(String name) {
  final n = name.toLowerCase();
  if (n.contains('bike')) return 'Quick rides';
  if (n.contains('auto')) return 'Affordable';
  if (n.contains('suv')) return 'Spacious';
  if (n.contains('prime') || n.contains('premium') || n.contains('luxury')) return 'Luxury sedan';
  if (n.contains('mini')) return 'Economical';
  return 'Comfortable';
}
