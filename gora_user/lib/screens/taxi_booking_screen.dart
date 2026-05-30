import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/polyline_utils.dart';
import 'booking_screen.dart';
import 'home_screen.dart';
import 'rating_screen.dart';

class TaxiBookingScreen extends StatefulWidget {
  final String? fromLocation;
  final String? toLocation;
  final bool hideLocationInputs;
  final String? preselectedVehicle;
  
  const TaxiBookingScreen({
    super.key,
    this.fromLocation,
    this.toLocation,
    this.hideLocationInputs = false,
    this.preselectedVehicle,
  });

  @override
  State<TaxiBookingScreen> createState() => _TaxiBookingScreenState();
}

class _TaxiBookingScreenState extends State<TaxiBookingScreen> {
  String? _selectedVehicle;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  bool _showLocationInputs = false;
  bool _showPickupConfirmation = false;
  bool _showWaitingPopup = false;
  int? _selectedTip;
  bool _isTaxiComing = false;
  LatLng? _comingTaxiLocation;
  bool _locationConfirmed = false;
  bool _showFullTripMap = false;
  bool _showArrivingButtons = false;
  bool _showMapPicker = false;
  LatLng _selectedMapLocation = const LatLng(28.6139, 77.2090);
  LatLng _myLocation = const LatLng(28.6139, 77.2090);
  GoogleMapController? _mapController;
  List<TextEditingController> _stopControllers = [];

  // ── Live ride state (wired to backend) ──────────────────────
  String? _rideId;
  String? _rideOtp;
  String _driverName = 'Driver';
  String _driverPhone = '';
  String _driverPicUrl = '';
  String _driverVehicleModel = '';
  String _driverVehicleNumber = '';
  double _driverRating = 0;
  Timer? _pollTimer;
  Timer? _driverLocTimer;
  Timer? _etaTimer;
  Timer? _fareRefreshTimer;

  // ── Route + live tracking state ─────────────────────────────
  List<LatLng> _routePoints = [];           // decoded pickup → drop polyline
  String _routePolylineEncoded = '';
  LatLng? _driverLatLng;                     // live driver position
  double _driverHeading = 0;                 // 0-360, for marker rotation
  int? _driverEtaMin;                        // driver → pickup minutes
  double? _driverDistanceKm;                 // driver → pickup km
  int? _tripEtaMin;                          // remaining time to destination during ride
  Map<String, dynamic>? _fareBreakdown;

  // ── Places autocomplete state ──
  List<Map<String, dynamic>> _dropSuggestions = [];
  List<Map<String, dynamic>> _mapPickerSuggestions = [];
  Timer? _searchDebounce;
  final _mapSearchController = TextEditingController();

  void _searchPlaces(String q, {required bool forMapPicker}) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        if (forMapPicker) _mapPickerSuggestions = [];
        else _dropSuggestions = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await ApiService.placesAutocomplete(q);
      if (!mounted) return;
      setState(() {
        if (forMapPicker) _mapPickerSuggestions = results;
        else _dropSuggestions = results;
      });
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s, {required bool forMapPicker}) async {
    final placeId = s['placeId'] as String? ?? '';
    final desc = s['description'] as String? ?? '';
    final details = await ApiService.placeDetails(placeId);
    if (!mounted) return;
    if (details == null) return;
    final lat = (details['lat'] as num).toDouble();
    final lng = (details['lng'] as num).toDouble();
    setState(() {
      _selectedMapLocation = LatLng(lat, lng);
      _dropController.text = details['address'] as String? ?? desc;
      if (forMapPicker) {
        _mapSearchController.text = details['address'] as String? ?? desc;
        _mapPickerSuggestions = [];
      } else {
        _dropSuggestions = [];
      }
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_selectedMapLocation, 16));
    // Drop changed → refresh fares using real distance
    _loadRealFares();
  }

  final List<int> _tipAmounts = [10, 20, 50, 100];

  // Vehicles to display, filtered by the service mode (bike/auto/cab)
  List<Map<String, dynamic>> get _displayVehicles {
    final pre = widget.preselectedVehicle;
    if (pre == null) return _vehicles;
    if (pre == 'Bike') return _vehicles.where((v) => v['name'] == 'Bike').toList();
    if (pre == 'Auto') return _vehicles.where((v) => v['name'] == 'Auto').toList();
    // Cab ride → all car types
    return _vehicles.where((v) => v['name'] == 'Cab Economy' || v['name'] == 'SUV' || v['name'] == 'Premium').toList();
  }

  @override
  void initState() {
    super.initState();
    // Set default locations
    _pickupController.text = widget.fromLocation ?? 'Current Location';
    // Empty so the hint/placeholder shows; user types to search
    _dropController.text = widget.toLocation ?? '';
    
    // Set preselected vehicle if provided
    if (widget.preselectedVehicle != null) {
      _selectedVehicle = widget.preselectedVehicle;
    }
    
    // If locations are already provided, consider it confirmed
    if (widget.fromLocation != null && widget.toLocation != null) {
      _locationConfirmed = true;
    }
    _initLocation();
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
        // Only set selected = pickup if no drop has been picked yet
        if (_dropController.text.trim().isEmpty) _selectedMapLocation = _myLocation;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 16));
      // Replace generic "Current Location" with the real street/area name
      if (_pickupController.text.trim().isEmpty || _pickupController.text == 'Current Location') {
        final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
        if (mounted && addr.isNotEmpty) setState(() => _pickupController.text = addr);
      }
    } else if (mounted) {
      // Show a clear message + retry button so the user understands why pickup is wrong
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not get your location. Check GPS/location permission.'),
        action: SnackBarAction(label: 'Retry', onPressed: _initLocation),
        duration: const Duration(seconds: 6),
      ));
    }
    _loadRealFares();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _driverLocTimer?.cancel();
    _etaTimer?.cancel();
    _fareRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _mapSearchController.dispose();
    for (var controller in _stopControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Bike locations near user
  final List<LatLng> _bikeLocations = [
    LatLng(28.6139, 77.2090),
    LatLng(28.6150, 77.2100),
    LatLng(28.6120, 77.2080),
    LatLng(28.6160, 77.2110),
    LatLng(28.6130, 77.2070),
    LatLng(28.6170, 77.2120),
  ];

  // Auto locations near user
  final List<LatLng> _autoLocations = [
    LatLng(28.6145, 77.2095),
    LatLng(28.6155, 77.2085),
    LatLng(28.6125, 77.2105),
    LatLng(28.6165, 77.2075),
    LatLng(28.6135, 77.2115),
  ];

  // Economy car locations (4 cars)
  final List<LatLng> _economyLocations = [
    LatLng(28.6140, 77.2095),
    LatLng(28.6158, 77.2088),
    LatLng(28.6122, 77.2102),
    LatLng(28.6162, 77.2078),
  ];

  // SUV locations (2 cars)
  final List<LatLng> _suvLocations = [
    LatLng(28.6148, 77.2092),
    LatLng(28.6152, 77.2098),
  ];

  // Premium car locations (1 car)
  final List<LatLng> _premiumLocations = [
    LatLng(28.6145, 77.2090),
  ];

  List<Map<String, dynamic>> _vehicles = [
    {'name': 'Bike', 'type': 'Quick Rides', 'price': '₹49', 'eta': '2 min', 'capacity': '1', 'icon': Icons.two_wheeler, 'color': Color(0xFF2196F3), 'image': 'assets/images/bike.png'},
    {'name': 'Auto', 'type': 'Affordable', 'price': '₹76', 'eta': '3 min', 'capacity': '3', 'icon': Icons.electric_rickshaw, 'color': Color(0xFF2196F3), 'image': 'assets/images/auto.jpg'},
    {'name': 'Cab Economy', 'type': 'Comfortable', 'price': '₹144', 'eta': '4 min', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF2196F3), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Spacious', 'price': '₹250', 'eta': '5 min', 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF2196F3), 'image': 'assets/images/texi.png'},
    {'name': 'Premium', 'type': 'Luxury Sedan', 'price': '₹320', 'eta': '6 min', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF2196F3), 'image': 'assets/images/texi2.png'},
  ];

  // Distance + duration from latest fare estimate (used at booking)
  double _rideDistance = 0;
  int _rideDuration = 0;

  // Fetch real fares from admin zone pricing — uses drop coords if available
  Future<void> _loadRealFares() async {
    try {
      // Only send drop coords if a real drop was picked (not equal to pickup)
      final hasDrop = _dropController.text.trim().isNotEmpty &&
          (_selectedMapLocation.latitude != _myLocation.latitude ||
              _selectedMapLocation.longitude != _myLocation.longitude);
      final res = await ApiService.estimateFare(
        pickupLat: _myLocation.latitude,
        pickupLng: _myLocation.longitude,
        dropLat: hasDrop ? _selectedMapLocation.latitude : null,
        dropLng: hasDrop ? _selectedMapLocation.longitude : null,
        service: 'taxi',
      );
      if (res['available'] == true && res['vehicles'] is List) {
        final apiVehicles = res['vehicles'] as List;
        setState(() {
          _rideDistance = (res['distance'] as num?)?.toDouble() ?? 0;
          _rideDuration = (res['duration'] as num?)?.toInt() ?? 0;
          for (final v in _vehicles) {
            final match = apiVehicles.firstWhere(
              (a) => (a['name'] as String?)?.toLowerCase() == (v['name'] as String).toLowerCase(),
              orElse: () => null,
            );
            if (match != null) {
              if (match['fare'] != null) v['price'] = '₹${match['fare']}';
              // Real driver ETA from backend; null when no driver of this type is online
              final eta = match['etaMin'];
              v['eta'] = eta is num ? '$eta min' : 'No driver';
            } else {
              v['eta'] = 'No driver';
            }
          }
        });
      }
      // Once we have a drop, also fetch real road directions for polyline + road distance
      if (hasDrop) await _loadDirections();
      // Keep ETAs/fares fresh while the user is picking a vehicle (until ride is booked)
      _startFareRefresh();
    } catch (_) {/* keep default prices */}
  }

  // Refresh fare estimate every 20s so driver ETA stays current. Stops once a ride is booked.
  void _startFareRefresh() {
    if (_fareRefreshTimer != null && _fareRefreshTimer!.isActive) return;
    _fareRefreshTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (!mounted || _rideId != null) { t.cancel(); _fareRefreshTimer = null; return; }
      _loadRealFares();
    });
  }

  // Fetch encoded polyline + road distance + duration; decode + draw + fit-bounds
  Future<void> _loadDirections() async {
    try {
      final d = await ApiService.getDirections(
        originLat: _myLocation.latitude,
        originLng: _myLocation.longitude,
        destLat: _selectedMapLocation.latitude,
        destLng: _selectedMapLocation.longitude,
      );
      if (d['polyline'] is String && (d['polyline'] as String).isNotEmpty) {
        final pts = decodePolyline(d['polyline'] as String);
        if (!mounted) return;
        setState(() {
          _routePolylineEncoded = d['polyline'] as String;
          _routePoints = pts;
          // Prefer road distance + duration from Directions over Haversine
          if (d['distanceKm'] != null) _rideDistance = (d['distanceKm'] as num).toDouble();
          if (d['durationMin'] != null) _rideDuration = (d['durationMin'] as num).toInt();
        });
        _fitMapToRoute();
      }
    } catch (_) {/* fallback to estimateFare values */}
  }

  // Fit map to pickup + drop + driver (if known) bounds
  void _fitMapToRoute() {
    final pts = <LatLng>[];
    pts.add(_myLocation);
    if (_routePoints.isNotEmpty) pts.addAll(_routePoints);
    if (_dropController.text.trim().isNotEmpty) pts.add(_selectedMapLocation);
    if (_driverLatLng != null) pts.add(_driverLatLng!);
    final b = boundsFromPoints(pts);
    if (b == null || _mapController == null) return;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(b, 60));
  }

  // Poll the assigned driver's live location every 5s during the ride
  void _startDriverLocationPolling() {
    _driverLocTimer?.cancel();
    if (_rideId == null) return;
    _driverLocTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      try {
        final res = await ApiService.getDriverLocation(_rideId!);
        final dr = res['driver'] as Map<String, dynamic>?;
        if (dr == null || dr['lat'] == null || dr['lng'] == null) return;
        if (!mounted) return;
        setState(() {
          _driverLatLng = LatLng((dr['lat'] as num).toDouble(), (dr['lng'] as num).toDouble());
          _driverHeading = ((dr['heading'] as num?) ?? 0).toDouble();
        });
      } catch (_) {/* keep last known */}
    });
  }

  // Periodically recompute ETA: driver → pickup (before start), or driver → drop (during ride)
  Future<void> _fetchEtaOnce() async {
    if (_driverLatLng == null || !mounted) return;
    try {
      final goingToDrop = _showFullTripMap;
      final dest = goingToDrop ? _selectedMapLocation : _myLocation;
      final d = await ApiService.getDirections(
        originLat: _driverLatLng!.latitude,
        originLng: _driverLatLng!.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
      );
      if (!mounted) return;
      final mins = (d['durationMin'] as num?)?.toInt();
      final km = (d['distanceKm'] as num?)?.toDouble();
      setState(() {
        if (goingToDrop) {
          _tripEtaMin = mins;
        } else {
          _driverEtaMin = mins;
          _driverDistanceKm = km;
        }
      });
    } catch (_) {/* keep last */}
  }

  void _startEtaPolling() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) { timer.cancel(); return; }
      _fetchEtaOnce();
    });
    // Fire once immediately so UI doesn't have to wait 30s
    Future.delayed(const Duration(seconds: 2), _fetchEtaOnce);
  }

  // Share live trip link via OS share sheet
  void _shareTrip() {
    if (_rideId == null) return;
    final url = '${AppConfig.serverBaseUrl}/track/$_rideId';
    Share.share('I\'m on a Gora ride — follow me live: $url', subject: 'My Gora Cabs trip');
  }

  // Book the ride against the backend (keeps UI; only sends real data)
  Future<void> _bookRide() async {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final basePrice = int.tryParse((selectedVehicleData['price'] as String).replaceAll('₹', '')) ?? 0;
    final tip = _selectedTip ?? 0;
    try {
      final res = await ApiService.bookRide({
        'pickupAddress': _pickupController.text,
        'dropAddress': _dropController.text,
        'pickupLat': _myLocation.latitude,
        'pickupLng': _myLocation.longitude,
        'dropLat': _selectedMapLocation.latitude,
        'dropLng': _selectedMapLocation.longitude,
        'service': 'taxi',
        'vehicleType': _selectedVehicle,
        'fare': basePrice,
        'tip': tip,
        'distance': _rideDistance,
        'duration': _rideDuration,
        'paymentMode': 'cash',
      });
      if (res['ride'] != null) {
        final r = res['ride'] as Map<String, dynamic>;
        _rideId = r['id']?.toString();
        _rideOtp = r['otp']?.toString();
        if (r['fareBreakdown'] is Map) {
          _fareBreakdown = Map<String, dynamic>.from(r['fareBreakdown'] as Map);
        }
        if (r['routePolyline'] is String && (r['routePolyline'] as String).isNotEmpty) {
          _routePolylineEncoded = r['routePolyline'] as String;
          _routePoints = decodePolyline(_routePolylineEncoded);
        }
      }
    } catch (_) {/* keep flow; polling will simply not find a ride */}
  }

  // Bottom sheet: show line-by-line fare breakdown
  void _showFareBreakdown() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final b = _fareBreakdown;
        Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? Colors.black87)),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? Colors.black87)),
          ]),
        );
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const Text('Fare Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (b == null) ...[
              // Pre-booking: show what we know
              row('Distance', '${_rideDistance.toStringAsFixed(1)} km'),
              row('Duration', '$_rideDuration min'),
              const Divider(height: 24),
              row('Estimated fare', _selectedVehicle != null
                ? (_vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => {'price': '—'})['price'] as String)
                : '—', bold: true, color: const Color(0xFF1976D2)),
              const SizedBox(height: 8),
              const Text('Full breakdown will be available after booking.', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]
            else ...[
              row('Base fare', '₹${(b['base'] ?? 0).toStringAsFixed(0)}'),
              row('Distance (${(b['distanceKm'] ?? 0).toStringAsFixed(1)} km × ₹${(b['perKm'] ?? 0)})', '₹${(b['distanceCharge'] ?? 0).toStringAsFixed(0)}'),
              row('Time (${(b['durationMin'] ?? 0)} min × ₹${(b['perMin'] ?? 0)})', '₹${(b['timeCharge'] ?? 0).toStringAsFixed(0)}'),
              if ((b['surge'] ?? 0) > 0) row('Surge', '+₹${(b['surge']).toStringAsFixed(0)}', color: Colors.orange),
              if ((b['tax'] ?? 0) > 0) row('Tax', '+₹${(b['tax']).toStringAsFixed(0)}'),
              const Divider(height: 24),
              row('Subtotal', '₹${(b['subtotal'] ?? 0).toStringAsFixed(0)}', bold: true),
              if (_selectedTip != null && _selectedTip! > 0) row('Tip', '+₹${_selectedTip!}', color: Colors.green),
              const Divider(height: 24),
              row('Total', '₹${((b['subtotal'] ?? 0) + (_selectedTip ?? 0)).toStringAsFixed(0)}', bold: true, color: const Color(0xFF1976D2)),
              const SizedBox(height: 8),
              Text('Admin commission: ₹${(b['commission'] ?? 0).toStringAsFixed(0)} (${b['perKm'] != null ? '' : ''}deducted from driver earnings)',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }

  // Poll ride status; invokes [onStatus] with the latest status string
  void _startStatusPolling(void Function(String status, Map<String, dynamic> ride) onStatus) {
    _pollTimer?.cancel();
    if (_rideId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      try {
        final ride = await ApiService.getRide(_rideId!);
        final status = (ride['status'] ?? 'pending').toString();
        if (ride['driverName'] != null) _driverName = ride['driverName'].toString();
        if (ride['driverPhone'] != null) _driverPhone = ride['driverPhone'].toString();
        // Pick up extra driver details (vehicle, pic, rating) as soon as driver is assigned
        final dr = ride['driver'] as Map<String, dynamic>?;
        if (dr != null) {
          _driverVehicleModel = (dr['vehicleModel'] ?? _driverVehicleModel).toString();
          _driverVehicleNumber = (dr['vehicleNumber'] ?? dr['vehicleRegistrationNumber'] ?? _driverVehicleNumber).toString();
          final pic = (dr['profilePicUrl'] ?? '').toString();
          if (pic.isNotEmpty) _driverPicUrl = AppConfig.imageUrl(pic);
          final r = dr['rating'];
          if (r is num) _driverRating = r.toDouble();
        }
        // Once a driver is assigned (status >= accepted), start live driver-location + ETA polling
        if (status != 'pending' && _driverLocTimer == null) {
          _startDriverLocationPolling();
          _startEtaPolling();
        }
        onStatus(status, ride);
      } catch (_) {}
    });
  }

  // Build Google Maps marker set
  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{};

    // Pickup (your location) — draggable so rider can fine-tune
    markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: _myLocation,
      draggable: true,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: const InfoWindow(title: 'Pickup (drag to adjust)'),
      onDragEnd: (LatLng p) async {
        setState(() => _myLocation = p);
        // Update pickup address via reverse geocode
        final addr = await ApiService.reverseGeocode(p.latitude, p.longitude);
        if (mounted && addr.isNotEmpty) setState(() => _pickupController.text = addr);
        // Recompute fares + polyline with new pickup
        _loadRealFares();
      },
    ));

    // Drop marker (whenever a drop is set)
    if (_dropController.text.trim().isNotEmpty) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: _selectedMapLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Drop', snippet: _dropController.text),
      ));
    }

    // Nearby available vehicles for selected type (only before a driver is assigned)
    if (_driverLatLng == null && !_isTaxiComing && _selectedVehicle != null) {
      List<LatLng> spots = [];
      if (_selectedVehicle == 'Bike') spots = _bikeLocations;
      else if (_selectedVehicle == 'Auto') spots = _autoLocations;
      else if (_selectedVehicle == 'Cab Economy') spots = _economyLocations;
      else if (_selectedVehicle == 'SUV') spots = _suvLocations;
      else if (_selectedVehicle == 'Premium') spots = _premiumLocations;
      for (var i = 0; i < spots.length; i++) {
        markers.add(Marker(
          markerId: MarkerId('veh_$i'),
          position: spots[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
        ));
      }
    }

    // Live driver marker (with heading rotation + ETA infoWindow)
    if (_driverLatLng != null) {
      final eta = _driverEtaMin;
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverLatLng!,
        rotation: _driverHeading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: eta != null ? '$eta min away' : 'Driver',
          snippet: _driverName,
        ),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildMapPolylines() {
    final lines = <Polyline>{};
    // Trip polyline (pickup → drop) — drawn whenever route is available
    if (_routePoints.isNotEmpty) {
      lines.add(Polyline(
        polylineId: const PolylineId('trip'),
        points: _routePoints,
        color: const Color(0xFF1976D2),
        width: 5,
      ));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    // Show full screen location selection first
    if (!_locationConfirmed) {
      return _buildLocationSelectionScreen();
    }
    
    // Show map and vehicle selection after location is confirmed
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _myLocation, zoom: 15),
                  onMapCreated: (c) {
                    _mapController = c;
                    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 15));
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  markers: _buildMapMarkers(),
                  polylines: _buildMapPolylines(),
                ),
                if (_showFullTripMap)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.black87, size: 24),
                      ),
                    ),
                  ),
                if (_showFullTripMap || _showArrivingButtons)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'support_btn_map',
                          onPressed: () {},
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.support_agent, color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton.small(
                          heroTag: 'share_btn_map',
                          onPressed: _shareTrip,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.share, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                if (!_showFullTripMap)
                  DraggableScrollableSheet(
                    initialChildSize: _showPickupConfirmation ? 0.18 : 0.4,
                    minChildSize: _showPickupConfirmation ? 0.18 : 0.4,
                    maxChildSize: _showPickupConfirmation ? 0.18 : 0.4,
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
                                physics: _showPickupConfirmation ? const NeverScrollableScrollPhysics() : null,
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                children: [
                                  if (_showPickupConfirmation) ...[
                                    const Text(
                                      'Double Check Pickup Point',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on, color: Colors.green[600], size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _pickupController.text,
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    // ── Pickup → Drop + Distance card ──
                                    _buildTripSummaryCard(),
                                    const SizedBox(height: 16),
                                    const Text('Select Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                  const SizedBox(height: 16),
                                  if (!_showPickupConfirmation) ...[
                                    ..._displayVehicles.map((v) => _buildVehicleCard(v)),
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
          if (!_showFullTripMap)
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
                    setState(() {
                      _locationConfirmed = true; // Ensure header is hidden when booking starts
                    });
                    if (_showPickupConfirmation) {
                      // Show waiting popup
                      _showWaitingDialog();
                    } else {
                      setState(() {
                        _showPickupConfirmation = true;
                      });
                    }
                  },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2196F3),
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _selectedVehicle == null ? 'Select a vehicle' : _showPickupConfirmation ? 'Confirm Pickup' : 'Book Now',
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

  Widget _buildLocationSelectionScreen() {
    if (_showMapPicker) {
      return _buildMapPickerScreen();
    }
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Drop',
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildLocationInput(Icons.radio_button_checked, _pickupController, const Color(0xFF4CAF50), 'Current Location'),
                // Stops
                ..._stopControllers.asMap().entries.map((entry) {
                  int index = entry.key;
                  TextEditingController controller = entry.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Row(
                          children: [
                            Column(
                              children: List.generate(3, (index) => Container(
                                margin: const EdgeInsets.symmetric(vertical: 1),
                                width: 2,
                                height: 4,
                                color: Colors.grey[400],
                              )),
                            ),
                          ],
                        ),
                      ),
                      _buildStopInput(controller, index),
                    ],
                  );
                }).toList(),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(
                    children: [
                      Column(
                        children: List.generate(3, (index) => Container(
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          width: 2,
                          height: 4,
                          color: Colors.grey[400],
                        )),
                      ),
                    ],
                  ),
                ),
                _buildLocationInput(Icons.location_on, _dropController, const Color(0xFFFF5252), 'Search destination',
                    onChanged: (q) => _searchPlaces(q, forMapPicker: false)),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showMapPicker = true;
                    });
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.map, color: Colors.grey[700], size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Select on map',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _stopControllers.add(TextEditingController(text: 'Add stop ${_stopControllers.length + 1}'));
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2196F3), size: 20),
                        label: const Text(
                          'Add stop',
                          style: TextStyle(color: Color(0xFF2196F3), fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_dropSuggestions.isNotEmpty) ...[
                  Text('SUGGESTIONS',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  ..._dropSuggestions.map((s) => _buildSuggestionTile(s, forMapPicker: false)),
                ] else if (_dropController.text.trim().isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Searching...', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(children: [
                      Icon(Icons.search, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('Search for your destination',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Type to see Google suggestions',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final dropText = _dropController.text.trim();
                    if (dropText.isEmpty || dropText == 'Select Destination') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter your destination')),
                      );
                      return;
                    }
                    // If drop coords are stale (still equal to pickup), resolve them now.
                    final coordsLookValid = _selectedMapLocation.latitude != _myLocation.latitude ||
                        _selectedMapLocation.longitude != _myLocation.longitude;
                    if (!coordsLookValid) {
                      // If there's a queued autocomplete suggestion, take the top one
                      if (_dropSuggestions.isNotEmpty) {
                        await _selectSuggestion(_dropSuggestions.first, forMapPicker: false);
                      } else {
                        // Otherwise try to autocomplete + take first hit
                        final results = await ApiService.placesAutocomplete(dropText);
                        if (results.isNotEmpty) {
                          await _selectSuggestion(results.first, forMapPicker: false);
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Couldn\'t find that place. Pick from the suggestions.')),
                          );
                          return;
                        }
                      }
                    }
                    if (!mounted) return;
                    setState(() => _locationConfirmed = true);
                    _loadRealFares();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Confirm Location',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPickerScreen() {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _myLocation, zoom: 15),
            onMapCreated: (c) {
              _mapController = c;
              // Always center on user's real location when picker opens
              c.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 16));
              _selectedMapLocation = _myLocation;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onCameraMove: (pos) {
              _selectedMapLocation = pos.target;
            },
            onCameraIdle: () async {
              setState(() {});
              // Reverse geocode the pin position → show real place name
              final addr = await ApiService.reverseGeocode(
                _selectedMapLocation.latitude, _selectedMapLocation.longitude);
              if (addr.isNotEmpty && mounted) {
                setState(() => _mapSearchController.text = addr);
              }
            },
          ),
          // Center pin
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on,
                  color: Color(0xFFFF5252),
                  size: 50,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 50),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showMapPicker = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: Row(children: [
                                const Icon(Icons.search, color: Colors.grey, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _mapSearchController,
                                    onChanged: (q) => _searchPlaces(q, forMapPicker: true),
                                    decoration: const InputDecoration(
                                      hintText: 'Search for a place',
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ]),
                            ),
                            if (_mapPickerSuggestions.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                                ),
                                constraints: const BoxConstraints(maxHeight: 260),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: _mapPickerSuggestions
                                      .map((s) => _buildSuggestionTile(s, forMapPicker: true))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom confirm button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
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
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Location',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  'Lat: ${_selectedMapLocation.latitude.toStringAsFixed(4)}, Lng: ${_selectedMapLocation.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Always reverse-geocode the actual pin position — typed search text
                          // may be stale if the user dragged the map after typing.
                          final addr = await ApiService.reverseGeocode(
                            _selectedMapLocation.latitude, _selectedMapLocation.longitude);
                          if (!mounted) return;
                          setState(() {
                            _dropController.text = addr.isNotEmpty
                                ? addr
                                : (_mapSearchController.text.trim().isNotEmpty
                                    ? _mapSearchController.text.trim()
                                    : 'Selected location');
                            _showMapPicker = false;
                            _locationConfirmed = true;
                          });
                          _loadRealFares();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Current location button (fetches fresh GPS, not cached)
          Positioned(
            bottom: 200,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () async {
                final pos = await LocationService.getCurrentLocation();
                if (pos == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enable GPS / location permission to use this')),
                  );
                  return;
                }
                final ll = LatLng(pos.latitude, pos.longitude);
                if (!mounted) return;
                setState(() {
                  _myLocation = ll;
                  _selectedMapLocation = ll;
                });
                _mapController?.animateCamera(CameraUpdate.newLatLngZoom(ll, 16));
              },
              child: const Icon(Icons.my_location, color: Color(0xFF2196F3)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopInput(TextEditingController controller, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Add stop ${index + 1}',
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                controller.dispose();
                _stopControllers.removeAt(index);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.red, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile(Map<String, dynamic> s, {required bool forMapPicker}) {
    final main = s['mainText'] as String? ?? s['description'] as String? ?? '';
    final sub = s['secondaryText'] as String? ?? '';
    return InkWell(
      onTap: () => _selectSuggestion(s, forMapPicker: forMapPicker),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
              child: Icon(Icons.location_on_outlined, color: Colors.grey[700], size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(main, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLocation(String title, String subtitle) {
    return InkWell(
      onTap: () {
        setState(() {
          _dropController.text = title;
          _locationConfirmed = true;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.access_time, color: Colors.grey[600], size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.favorite_border, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint, {ValueChanged<String>? onChanged}) {
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
              onChanged: onChanged,
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

  // Pickup → Drop + Distance summary shown above vehicle list
  Widget _buildTripSummaryCard() {
    final pickup = _pickupController.text.trim().isEmpty ? 'Current Location' : _pickupController.text;
    final drop = _dropController.text.trim().isEmpty ? 'Drop' : _dropController.text;
    final dist = _rideDistance > 0 ? '${_rideDistance.toStringAsFixed(1)} km' : '— km';
    final eta = _rideDuration > 0 ? '${_rideDuration} min' : '— min';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          // Pickup
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Icon(Icons.radio_button_checked, color: Color(0xFF4CAF50), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(pickup,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
            ),
          ]),
          // Connector
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 2, bottom: 2),
            child: SizedBox(
              height: 14,
              child: Column(children: List.generate(3, (_) => Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                width: 2, height: 2,
                color: Colors.grey[400],
              ))),
            ),
          ),
          // Drop
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(drop,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
            ),
          ]),
          // Divider + distance/time chips
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.grey[200]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.route, size: 14, color: Color(0xFF2196F3)),
            const SizedBox(width: 4),
            Text(dist, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2196F3))),
            const SizedBox(width: 16),
            const Icon(Icons.access_time, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(eta, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _locationConfirmed = false),
              icon: const Icon(Icons.edit, size: 14, color: Color(0xFF2196F3)),
              label: const Text('Change', style: TextStyle(fontSize: 12, color: Color(0xFF2196F3), fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicle = v['name']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? (v['color'] as Color).withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? (v['color'] as Color) : Colors.grey[300]!, 
            width: isSelected ? 2 : 1
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (v['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  v['image'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(v['icon'], color: v['color'] as Color, size: 24);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${v['type']} • ${v['capacity']} seats', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(v['price'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4CAF50))),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(v['eta'], style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showWaitingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Add Tip',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Support your driver by adding a tip',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _showFareBreakdown,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Text(
                              'Total Fare: ${selectedVehicleData['price']}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.info_outline, size: 16, color: Color(0xFF1976D2)),
                          ]),
                          Text(
                            _selectedTip != null ? '(₹$_selectedTip tip added)' : '(Tap to see breakdown)',
                            style: TextStyle(fontSize: 11, color: _selectedTip != null ? Colors.green : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: _tipAmounts.map((amount) {
                      final isSelected = _selectedTip == amount;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            _selectedTip = isSelected ? null : amount;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Color(0xFF2196F3) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? Color(0xFF2196F3) : Colors.grey[300]!,
                            ),
                          ),
                          child: Text(
                            '₹$amount',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.grey),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            'Back',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _bookRide();
                            _showFinalWaitingDialog();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF2196F3),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            _selectedTip != null ? 'Confirm with ₹$_selectedTip Tip' : 'Confirm Ride',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFinalWaitingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final basePrice = int.parse(selectedVehicleData['price'].replaceAll('₹', ''));
    final totalPrice = _selectedTip != null ? basePrice + _selectedTip! : basePrice;
    
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Poll backend: while pending keep searching; when accepted show driver
        _startStatusPolling((status, ride) {
          if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
              _showDriverArrivingDialog();
            }
          } else if (status == 'cancelled') {
            _pollTimer?.cancel();
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please Wait',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedTip != null 
                    ? 'Tip added! Finding your driver...'
                    : 'Finding your driver...',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Base Fare:',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          selectedVehicleData['price'],
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    if (_selectedTip != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tip:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '+₹$_selectedTip',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Fare:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹$totalPrice',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showCancelReasonDialog(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Cancel Booking',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Searching...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showDriverArrivingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    
    // Start tracking on map
    setState(() {
      _isTaxiComing = true;
      _showArrivingButtons = true;
      // Set a mock location for the coming taxi (nearby)
      _comingTaxiLocation = LatLng(28.6220, 77.2150);
    });
    
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // Don't dim the map
      builder: (BuildContext context) {
        // Poll backend: when ride starts switch to full trip map; when completed show summary
        _startStatusPolling((status, ride) {
          if (status == 'ongoing') {
            if (!_showFullTripMap && mounted) {
              setState(() {
                _showFullTripMap = true;
                _showArrivingButtons = false;
              });
            }
          } else if (status == 'completed') {
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
            _pollTimer?.cancel();
            setState(() {
              _showFullTripMap = false;
              _showArrivingButtons = false;
            });
            _showRideCompletedDialog();
          } else if (status == 'cancelled') {
            _pollTimer?.cancel();
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Your taxi on the way',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text('Ride PIN: ', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      _rideOtp ?? '----',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // ETA and Distance Info (live values populated by directions polling)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: Color(0xFF2196F3), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _driverEtaMin != null ? 'Arriving in $_driverEtaMin min' : 'Calculating ETA…',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 15, color: Colors.grey[300]),
                    const SizedBox(width: 12),
                    const Icon(Icons.location_on, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _driverDistanceKm != null ? '${_driverDistanceKm!.toStringAsFixed(1)} km away' : '— km away',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Driver Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    // Driver Profile Image (real photo if available, else initial)
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
                        ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'D',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54))
                        : null,
                    ),
                    const SizedBox(width: 12),
                    // Driver Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _driverName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [_driverVehicleModel, _driverVehicleNumber].where((s) => s.isNotEmpty).join(' • '),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    // Vehicle Image (Now on the right and larger)
                    SizedBox(
                      width: 90,
                      height: 70,
                      child: Image.asset(
                        selectedVehicleData['image'],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          selectedVehicleData['icon'], 
                          color: selectedVehicleData['color'],
                          size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (_driverPhone.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Driver: $_driverName • $_driverPhone')),
                          );
                        }
                      },
                      icon: const Icon(Icons.call, color: Colors.green),
                      label: const Text('Call', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareTrip,
                      icon: const Icon(Icons.share, color: Color(0xFF2196F3)),
                      label: const Text('Share', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _showArrivingButtons = false;
                    });
                    _showCancelReasonDialog();
                  },
                  child: const Text('Cancel Ride', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showCancelReasonDialog() {
    final List<String> reasons = [
      'Plan changed',
      'Driver is too far',
      'Found another ride',
      'Wait time is too long',
      'Wrong location selected',
      'Other'
    ];
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Cancel Ride',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason for cancellation',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ...reasons.map((reason) => RadioListTile<String>(
                    title: Text(reason, style: const TextStyle(fontSize: 15)),
                    value: reason,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFF2196F3),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedReason = value;
                      });
                    },
                  )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedReason == null ? null : () async {
                        _pollTimer?.cancel();
                        if (_rideId != null) {
                          try {
                            await ApiService.cancelRide(_rideId!, selectedReason!);
                          } catch (_) {}
                        }
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Confirm Cancellation',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    ),
                  ),
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Ride Completed!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have reached your destination safely.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RatingScreen(
                          driverName: _driverName,
                          vehicleName: _selectedVehicle!,
                          selectedTip: _selectedTip,
                          rideId: _rideId,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Rate Your Ride',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}