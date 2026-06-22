import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/polyline_utils.dart';
import 'home_screen.dart';
import 'rating_screen.dart';
import 'booking_screen.dart';
import 'booking_inquiry_screen.dart';
import 'outstation_ride_details_screen.dart';

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

    // Fetch both one-way and round-trip in parallel so user can switch trip type freely
    final oneWayF = ApiService.estimateFare(
      pickupLat: _fromLat!, pickupLng: _fromLng!,
      dropLat: _toLat!, dropLng: _toLng!,
      service: 'outstation',
    );
    final roundF = ApiService.post('/fare/estimate', {
      'pickupLat': _fromLat, 'pickupLng': _fromLng,
      'dropLat': _toLat, 'dropLng': _toLng,
      'service': 'outstation', 'tripType': 'round_trip',
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
            'extras': ow['extras'] ?? 0,
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
    final fare = isRoundTrip ? selVehicle['roundTripFare'] : selVehicle['oneWayFare'];

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
        'paymentMode': 'cash',
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
              color: Colors.white,
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
                                  color: Colors.white,
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
                                          color: _fromController.text.isEmpty && _toController.text.isEmpty ? Colors.grey[600] : Colors.black87,
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
                                  backgroundColor: Color(0xFF2196F3),
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
                        color: const Color(0xFF1976D2),
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
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [
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
                                  if (_showTripDetails)
                                    Row(
                                      children: [
                                        Expanded(child: _buildTripTypeButton('One Way')),
                                        const SizedBox(width: 12),
                                        Expanded(child: _buildTripTypeButton('Round Trip')),
                                      ],
                                    ),
                                  if (_showTripDetails)
                                    const SizedBox(height: 16),
                                  if (_showTripDetails)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildDateInput(_departureDateController, 'Departure Date', Icons.calendar_today),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildTimeInput(_departureTimeController, 'Time', Icons.access_time),
                                        ),
                                      ],
                                    ),
                                  if (_showTripDetails && _tripType == 'Round Trip')
                                    const SizedBox(height: 12),
                                  if (_showTripDetails && _tripType == 'Round Trip')
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildDateInput(_returnDateController, 'Return Date', Icons.calendar_today),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildTimeInput(_returnTimeController, 'Time', Icons.access_time),
                                        ),
                                      ],
                                    ),
                                  if (_showTripDetails)
                                    const SizedBox(height: 12),
                                  // Passengers picker — affects vehicle suitability (3 vs 6 seats)
                                  if (_showTripDetails)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
                                      child: Row(children: [
                                        Icon(Icons.group, color: Colors.grey[600], size: 18),
                                        const SizedBox(width: 10),
                                        const Text('Passengers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF2196F3)),
                                          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                          onPressed: _numPassengers > 1 ? () => setState(() => _numPassengers--) : null,
                                        ),
                                        const SizedBox(width: 14),
                                        Text('$_numPassengers', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                        const SizedBox(width: 14),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2196F3)),
                                          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                          onPressed: _numPassengers < 12 ? () => setState(() => _numPassengers++) : null,
                                        ),
                                      ]),
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
                                        color: Colors.grey[50],
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
                                          const Icon(Icons.route, size: 13, color: Color(0xFF2196F3)),
                                          const SizedBox(width: 4),
                                          Text('${_distanceKm.toStringAsFixed(0)} km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2196F3))),
                                          const SizedBox(width: 14),
                                          const Icon(Icons.access_time, size: 13, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(_durationMin > 60 ? '${(_durationMin / 60).toStringAsFixed(1)} hr' : '$_durationMin min', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                            child: Text(_tripType, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2196F3))),
                                          ),
                                        ]),
                                      ]),
                                    ),
                                  if (_showVehicleSelection)
                                    Column(
                                      children: _vehicles.map((v) => _buildVehicleCard(v)).toList(),
                                    ),
                                  if (_showVehicleSelection)
                                    const SizedBox(height: 20),
                                  if (_showVehicleSelection)
                                    _buildTripConditions(),
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
                color: Colors.white,
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
                      backgroundColor: Color(0xFF2196F3),
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
      onTap: () => setState(() {
        _tripType = type;
        if (type == 'One Way') {
          _returnDateController.clear();
          _returnTimeController.clear();
        }
        // Auto-expand vehicle selection after trip details are set
        if (!_showVehicleSelection && (_departureDateController.text.isNotEmpty || type == 'One Way')) {
          _showVehicleSelection = true;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF2196F3) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Color(0xFF2196F3) : Colors.grey[300]!),
        ),
        child: Center(
          child: Text(
            type,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // Clean full-screen From/To picker — mirrors the taxi screen UX so behaviour is consistent
  Widget _buildOutstationLocationScreen() {
    // Whichever field is empty drives the suggestion list shown below
    final activeIsFrom = _fromController.text.trim().isEmpty || _toController.text.trim().isNotEmpty == false;
    final suggestions = activeIsFrom ? _fromSuggestions : _toSuggestions;
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text('Outstation', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600)),
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
                    decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.my_location, color: Color(0xFF2196F3), size: 20),
                  ),
                  title: const Text('Use my current location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2196F3))),
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
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))]),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => setState(() => _showMapPicker = false)),
        title: Text(_pickingFrom ? 'Pick From location' : 'Pick To location',
            style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)),
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
          mini: true, backgroundColor: Colors.white,
          onPressed: () async {
            final pos = await LocationService.getCurrentLocation();
            if (pos == null) return;
            final ll = LatLng(pos.latitude, pos.longitude);
            _pickerMapController?.animateCamera(CameraUpdate.newLatLngZoom(ll, 14));
          },
          child: const Icon(Icons.my_location, color: Color(0xFF2196F3)),
        )),
        // Bottom card: address preview + Confirm
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))]),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
        color: Colors.grey[50],
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
        color: Colors.grey[50],
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
        color: Colors.grey[50],
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
    
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicle = v['name']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF2196F3).withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Color(0xFF2196F3) : Colors.grey[300]!, 
            width: isSelected ? 2 : 1
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60, height: 50,
              child: (v['networkImage'] as String?)?.isNotEmpty == true
                  ? Image.network(v['networkImage'] as String, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(v['icon'], color: const Color(0xFF2196F3), size: 40))
                  : Image.asset(v['image'] as String? ?? 'assets/images/economy.png', fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(v['icon'], color: const Color(0xFF2196F3), size: 40)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('${v['type']} • ${v['capacity']} seats', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(currentPrice, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4CAF50))),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Available', style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripConditions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline, color: Color(0xFF2196F3), size: 20),
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
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
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
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF2196F3)),
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
                          color: Colors.grey[50],
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
                                Text(currentPrice, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
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
                      
                      const SizedBox(height: 24),
                      
                      // Inclusions
                      const Text('What\'s Included', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            _buildDialogConditionItem(Icons.check_circle, 'Professional verified driver'),
                            const SizedBox(height: 8),
                            _buildDialogConditionItem(Icons.check_circle, 'Fuel included in base fare'),
                            const SizedBox(height: 8),
                            _buildDialogConditionItem(Icons.check_circle, 'AC vehicle with comfortable seats'),
                            const SizedBox(height: 8),
                            _buildDialogConditionItem(Icons.check_circle, 'Live GPS tracking'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Conditions
                      const Text('Additional Charges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      
                      if (_tripType == 'One Way') ...[
                        _buildDialogConditionItem(Icons.toll, 'Tolls and state taxi extra pay'),
                        const SizedBox(height: 8),
                        _buildDialogConditionItem(Icons.local_parking, 'Parking charges extra'),
                      ] else ...[
                        _buildDialogConditionItem(Icons.toll, 'Tolls and state taxi extra pay'),
                        const SizedBox(height: 8),
                        _buildDialogConditionItem(Icons.local_parking, 'Parking charges extra'),
                        const SizedBox(height: 8),
                        _buildDialogConditionItem(Icons.route, 'Minimum per day 250km running'),
                        const SizedBox(height: 8),
                        _buildDialogConditionItem(Icons.person, 'Driver allowance per 24 hours - ₹250'),
                        const SizedBox(height: 8),
                        _buildDialogConditionItem(Icons.nightlight, 'Night drive allowance - ₹250/night'),
                      ],
                      
                      const SizedBox(height: 16),
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
                ),
              ),
              
              // Book button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                      backgroundColor: const Color(0xFF2196F3),
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

  Widget _buildDialogConditionItem(IconData icon, String text) {
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
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  void _cancelSearch(BuildContext sheetCtx) {
    const reasons = ['Taking too long', 'Booked by mistake', 'Plan changed', 'Found another ride', 'Other'];
    showModalBottomSheet(context: context, backgroundColor: Colors.white,
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

  void _showFindingDriverDialog() {
    setState(() {
      _isSearching = true;
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
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

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3))),
              const SizedBox(height: 16),
              const Text('Finding your Outstation Pilot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please wait while we connect you with a nearby pilot for your outstation trip.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _cancelSearch(context),
                icon: const Icon(Icons.close, color: Colors.red), label: const Text('Cancel Trip', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), side: const BorderSide(color: Colors.red)))),
            ],
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
          ),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const Text('Pilot Assigned for Outstation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 12),
              // Prominent OTP/PIN box — driver asks for this to start the ride
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFF1976D2).withOpacity(0.08), const Color(0xFF1976D2).withOpacity(0.02)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: Color(0xFF1976D2), size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Share OTP with pilot', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                    const SizedBox(height: 2),
                    const Text('Driver will ask for this 4-digit PIN to start the trip', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1976D2))),
                    child: Text(_rideOtp ?? '----', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1976D2))),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
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
                      Text(_driverName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
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
                        ? Image.network(_driverVehicleImageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, color: Color(0xFF2196F3), size: 40))
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
                    decoration: BoxDecoration(color: const Color(0xFF1976D2).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.workspace_premium, color: Color(0xFF1976D2), size: 14),
                      const SizedBox(width: 4),
                      Text('${_driverYearsActive}+ yr exp', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1976D2))),
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
                    icon: const Icon(Icons.call, color: Colors.green), label: const Text('Call', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () {
                      if (_rideId != null) {
                        Share.share('I\'m on a Gora outstation trip — follow me: ${AppConfig.serverBaseUrl}/track/$_rideId');
                      }
                    },
                    icon: const Icon(Icons.share, color: Color(0xFF2196F3)), label: const Text('Share', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2),
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
                    backgroundColor: const Color(0xFF2196F3),
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
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const Text('Cancel Trip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Please select a reason for cancellation', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 20),
                  ...reasons.map((reason) => RadioListTile<String>(title: Text(reason, style: const TextStyle(fontSize: 15)), value: reason, groupValue: selectedReason, activeColor: const Color(0xFF2196F3), contentPadding: EdgeInsets.zero, onChanged: (value) => setDialogState(() => selectedReason = value))),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: selectedReason == null ? null : () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Confirm Cancellation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
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
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Trip Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your outstation trip has been completed successfully.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => RatingScreen(driverName: 'Rahul Sharma', vehicleName: _selectedVehicle!, selectedTip: 0))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate Your Experience', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
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
