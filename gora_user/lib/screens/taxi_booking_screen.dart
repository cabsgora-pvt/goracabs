import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../utils/duration_format.dart';
import '../services/api_service.dart';
import '../utils/vehicle_marker.dart';
import '../utils/map_markers.dart';
import '../services/location_service.dart';
import '../utils/polyline_utils.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/ride_ui/ride_ui.dart';
import '../widgets/ride_preferences.dart';
import '../utils/ride_booking.dart';
import 'outstation_screen.dart';

class TaxiBookingScreen extends StatefulWidget {
  final String? fromLocation;
  final String? toLocation;
  final bool hideLocationInputs;
  final String? preselectedVehicle;
  // Real coordinates for [toLocation] — e.g. "Book Again" from a past ride —
  // so the drop pin and fare estimate are correct from the first frame
  // instead of waiting on a geocode of the address text.
  final double? initialDropLat;
  final double? initialDropLng;

  const TaxiBookingScreen({
    super.key,
    this.fromLocation,
    this.toLocation,
    this.hideLocationInputs = false,
    this.preselectedVehicle,
    this.initialDropLat,
    this.initialDropLng,
  });

  @override
  State<TaxiBookingScreen> createState() => _TaxiBookingScreenState();
}

class _TaxiBookingScreenState extends State<TaxiBookingScreen>
    // The nearby fleet's animation. The booked ride is tracked, and paid, on
    // ActiveRideScreen — this screen only books it.
    with TickerProviderStateMixin {
  String? _selectedVehicle;

  // Real available vehicles around the pickup, of the selected type. These were
  // hard-coded Delhi coordinates, so in any other city the "nearby" vehicles a
  // rider saw while choosing were not there at all — and in Delhi they never
  // moved and were never real.
  late final AmbientVehicleFleet _fleet;
  Timer? _nearbyTimer;

  // Flat pickup dot and drop square, as on every other ride map. The pickup is
  // drawn larger here because the rider presses and drags it.
  BitmapDescriptor? _pickupGlyph, _dropGlyph;
  double? _glyphDpr;

  // ── Ola-style payment + coupon selection (UI only) ──
  String _paymentMode = 'cash';
  bool _preferFemaleDriver = false;
  // Admin-defined ride preferences for taxi, and the keys the rider picked.
  List<RidePreference> _ridePrefs = const [];
  Set<String> _selectedPrefs = {};
  String _couponCode = '';
  int _couponDiscount = 0;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  bool _showPickupConfirmation = false;
  // At most kMaxTip (the server refuses more).
  int? _selectedTip;
  bool _locationConfirmed = false;
  bool _showMapPicker = false;
  LatLng _selectedMapLocation = const LatLng(28.6139, 77.2090);
  LatLng _myLocation = const LatLng(28.6139, 77.2090);
  GoogleMapController? _mapController;
  List<TextEditingController> _stopControllers = [];
  final List<LatLng?> _stopLatLng = [];   // resolved coords per stop (parallel to controllers)

  Timer? _fareRefreshTimer;

  // ── Route ───────────────────────────────────────────────────
  List<LatLng> _routePoints = [];           // decoded pickup → drop polyline

  // ── Places autocomplete state ──
  List<Map<String, dynamic>> _dropSuggestions = [];
  List<Map<String, dynamic>> _mapPickerSuggestions = [];
  Timer? _searchDebounce;
  final _mapSearchController = TextEditingController();

  // Drop search state. "Searching…" used to be shown whenever the field had
  // text and the list was empty — so it stuck after a suggestion was picked
  // (which empties the list) and whenever a search found nothing.
  bool _searchingDrop = false;
  bool _dropSearchEmpty = false;
  // Bumped per query and on selection, so a slow answer to an older query
  // cannot refill the list after the rider has moved on.
  int _searchSeq = 0;

  // Pickup search. The pickup field had no search at all: typing a new
  // address changed only the text, and the ride was still booked at the GPS
  // point (_myLocation), so the driver went to the wrong place.
  List<Map<String, dynamic>> _pickupSuggestions = [];
  bool _searchingPickup = false;
  bool _pickupSearchEmpty = false;
  // True while the pickup text was typed but no place was picked for it yet.
  bool _pickupEdited = false;
  // The rider set the pickup themselves (suggestion, pin drag): a late GPS
  // fix must not move it back to where the phone is.
  bool _pickupChosen = false;
  // Which field the list under the inputs belongs to.
  bool _listForPickup = false;

  void _searchPlaces(String q, {required bool forMapPicker, bool forPickup = false}) {
    _searchDebounce?.cancel();
    final seq = ++_searchSeq;
    if (!forMapPicker) _listForPickup = forPickup;
    if (q.trim().length < 2) {
      setState(() {
        if (forMapPicker) {
          _mapPickerSuggestions = [];
        } else if (forPickup) {
          _pickupSuggestions = [];
          _searchingPickup = false;
          _pickupSearchEmpty = false;
        } else {
          _dropSuggestions = [];
          _searchingDrop = false;
          _dropSearchEmpty = false;
        }
      });
      return;
    }
    if (!forMapPicker) {
      setState(() {
        if (forPickup) {
          _searchingPickup = true;
          _pickupSearchEmpty = false;
        } else {
          _searchingDrop = true;
          _dropSearchEmpty = false;
        }
      });
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      List<Map<String, dynamic>> results = const [];
      try {
        results = await ApiService.placesAutocomplete(q);
      } catch (_) {/* shown as "no places found" */}
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        if (forMapPicker) {
          _mapPickerSuggestions = results;
        } else if (forPickup) {
          _pickupSuggestions = results;
          _searchingPickup = false;
          _pickupSearchEmpty = results.isEmpty;
        } else {
          _dropSuggestions = results;
          _searchingDrop = false;
          _dropSearchEmpty = results.isEmpty;
        }
      });
    });
  }

  void _onPickupTyped(String q) {
    _pickupEdited = true;
    _searchPlaces(q, forMapPicker: false, forPickup: true);
  }

  void _clearPickupSearch() {
    _pickupSuggestions = [];
    _searchingPickup = false;
    _pickupSearchEmpty = false;
    _listForPickup = false;
  }

  // Sets the pickup to a place the rider picked (coordinates, not just text).
  Future<bool> _selectPickupSuggestion(Map<String, dynamic> s) async {
    _searchDebounce?.cancel();
    _searchSeq++;
    final placeId = s['placeId'] as String? ?? '';
    final desc = s['description'] as String? ?? '';
    final details = await ApiService.placeDetails(placeId);
    if (!mounted) return false;
    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that place. Please try again.')),
      );
      return false;
    }
    final ll = LatLng((details['lat'] as num).toDouble(), (details['lng'] as num).toDouble());
    setState(() {
      _myLocation = ll;
      _pickupController.text = details['address'] as String? ?? desc;
      _pickupEdited = false;
      _pickupChosen = true;
      _clearPickupSearch();
    });
    FocusScope.of(context).unfocus();
    _loadRealFares();
    return true;
  }

  // "Use current location" in the pickup list: back to the phone's GPS.
  Future<void> _useCurrentLocationForPickup() async {
    _searchDebounce?.cancel();
    _searchSeq++;
    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable GPS / location permission to use this')),
      );
      return;
    }
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _myLocation = ll;
      _pickupEdited = false;
      _pickupChosen = true;
      _clearPickupSearch();
      _pickupController.text = 'Current Location';
    });
    FocusScope.of(context).unfocus();
    final addr = await ApiService.reverseGeocode(ll.latitude, ll.longitude);
    if (mounted && addr.isNotEmpty) setState(() => _pickupController.text = addr);
    _loadRealFares();
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s, {required bool forMapPicker}) async {
    // A choice ends the search: drop any pending or in-flight query.
    _searchDebounce?.cancel();
    _searchSeq++;
    if (!forMapPicker && (_searchingDrop || _dropSearchEmpty)) {
      setState(() {
        _searchingDrop = false;
        _dropSearchEmpty = false;
      });
    }
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

  // Vehicles to display. Backend already returns only taxi-service vehicles, so we show
  // them all (the entry tab is just a hint). Filter loosely by name if a preselect is given.
  List<Map<String, dynamic>> get _displayVehicles {
    final pre = widget.preselectedVehicle;
    if (pre == null) return _vehicles;
    final p = pre.toLowerCase();
    if (p == 'bike') {
      final m = _vehicles.where((v) => (v['name'] as String).toLowerCase().contains('bike')).toList();
      return m.isNotEmpty ? m : _vehicles;
    }
    if (p == 'auto') {
      final m = _vehicles.where((v) => (v['name'] as String).toLowerCase().contains('auto')).toList();
      return m.isNotEmpty ? m : _vehicles;
    }
    // Cab → cars (everything that isn't bike/auto)
    final m = _vehicles.where((v) {
      final n = (v['name'] as String).toLowerCase();
      return !n.contains('bike') && !n.contains('auto');
    }).toList();
    return m.isNotEmpty ? m : _vehicles;
  }

  String _typeFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('bike')) return 'Quick Rides';
    if (n.contains('auto')) return 'Affordable';
    if (n.contains('suv')) return 'Spacious';
    if (n.contains('premium') || n.contains('prime')) return 'Luxury';
    return 'Comfortable';
  }
  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('bike')) return Icons.two_wheeler;
    if (n.contains('auto')) return Icons.electric_rickshaw;
    if (n.contains('suv')) return Icons.airport_shuttle;
    return Icons.directions_car;
  }
  String _assetFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('bike')) return 'assets/images/bike.png';
    if (n.contains('auto')) return 'assets/images/auto.jpg';
    if (n.contains('suv')) return 'assets/images/texi.png';
    return 'assets/images/economy.png';
  }

  @override
  void initState() {
    super.initState();
    _fleet = AmbientVehicleFleet(
      vsync: this,
      duration: const Duration(seconds: 4),
      onUpdate: () { if (mounted) setState(() {}); },
    );
    _nearbyTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadNearby());
    loadRidePreferences('taxi').then((p) {
      if (mounted) setState(() => _ridePrefs = p);
    });
    // Set default locations
    _pickupController.text = widget.fromLocation ?? 'Current Location';
    // Empty so the hint/placeholder shows; user types to search
    _dropController.text = widget.toLocation ?? '';
    // Passed in as real coordinates (not geocoded from the text) — the same
    // field _selectSuggestion sets when the rider picks a place themselves.
    if (widget.initialDropLat != null && widget.initialDropLng != null) {
      _selectedMapLocation = LatLng(widget.initialDropLat!, widget.initialDropLng!);
    }

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
    // The rider already set the pickup themselves while GPS was slow.
    if (_pickupChosen || _pickupEdited) {
      _loadRealFares();
      return;
    }
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr == _glyphDpr) return;
    _glyphDpr = dpr;
    PlaceMarkers.pickup(dpr, size: 34).then((d) { if (mounted) setState(() => _pickupGlyph = d); });
    PlaceMarkers.drop(dpr).then((d) { if (mounted) setState(() => _dropGlyph = d); });
  }

  /// Available vehicles of the selected type near the pickup, while the rider
  /// is choosing.
  Future<void> _loadNearby() async {
    if (!mounted) return;
    try {
      final drivers = await ApiService.getNearbyDrivers(
        _myLocation.latitude, _myLocation.longitude,
        radiusKm: 4, vehicleType: _selectedVehicle,
      );
      if (!mounted) return;
      if (drivers.isEmpty) {
        _fleet.clear();
      } else {
        await _fleet.update(drivers);
      }
    } catch (_) {/* decoration only — never let it break booking */}
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _fleet.dispose();
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

  List<Map<String, dynamic>> _vehicles = [
    {'name': 'Bike', 'type': 'Quick Rides', 'price': '—', 'eta': '—', 'capacity': '1', 'icon': Icons.two_wheeler, 'color': Color(0xFF0A3CC8), 'image': 'assets/images/bike.png'},
    {'name': 'Auto', 'type': 'Affordable', 'price': '—', 'eta': '—', 'capacity': '3', 'icon': Icons.electric_rickshaw, 'color': Color(0xFF0A3CC8), 'image': 'assets/images/auto.jpg'},
    {'name': 'Cab Economy', 'type': 'Comfortable', 'price': '—', 'eta': '—', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF0A3CC8), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Spacious', 'price': '—', 'eta': '—', 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF0A3CC8), 'image': 'assets/images/texi.png'},
    {'name': 'Premium', 'type': 'Luxury Sedan', 'price': '—', 'eta': '—', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF0A3CC8), 'image': 'assets/images/texi2.png'},
  ];

  // Distance + duration from latest fare estimate (used at booking)
  double _rideDistance = 0;
  int _rideDuration = 0;
  // Trip time to SHOW the rider. Kept separate from _rideDuration because that
  // one is sent back to /rides/book, where it feeds the fare — so it must keep
  // its original semantics and cannot be "improved" here.
  //
  // Preference order: real traffic-aware Directions time > the backend's learned
  // tripEtaMin > the crow-flies fallback. The old UI showed _rideDuration, i.e.
  // straight-line km x 3, which is a flat 20 km/h with no detour and no traffic.
  int _displayTripMin = 0;

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
      // Drop is outside the city zone — prompt the user to switch to Outstation
      if (res['outOfZone'] == true && mounted) {
        final zoneName = (res['zone'] as Map?)?['name']?.toString() ?? 'this city';
        _showOutOfZoneDialog(zoneName);
        return;
      }
      if (res['available'] == true && res['vehicles'] is List) {
        final apiVehicles = res['vehicles'] as List;
        setState(() {
          _rideDistance = (res['distance'] as num?)?.toDouble() ?? 0;
          _rideDuration = (res['duration'] as num?)?.toInt() ?? 0;
          _displayTripMin = (res['tripEtaMin'] as num?)?.toInt() ?? _rideDuration;
          // Build the vehicle list straight from backend (real admin VehicleType names,
          // so the booked vehicleType matches what the driver registered with).
          if (apiVehicles.isNotEmpty) {
            _vehicles = apiVehicles.map<Map<String, dynamic>>((a) {
              final name = (a['name'] as String?) ?? 'Vehicle';
              final eta = a['etaMin'];
              final raw = (a['imageUrl'] as String?) ?? '';
              return {
                'name': name,
                'type': _typeFor(name),
                'price': a['fare'] != null ? '₹${a['fare']}' : '—',
                'eta': eta is num ? '$eta min' : 'No driver',
                'capacity': '${a['capacity'] ?? 4}',
                'icon': _iconFor(name),
                'color': const Color(0xFF0A3CC8),
                'image': raw.isEmpty ? _assetFor(name) : '__net__',
                'networkImage': raw.isEmpty ? '' : AppConfig.imageUrl(raw),
                // Server-signed price — replayed at booking so the backend only
                // ever accepts a fare it produced itself.
                'quoteToken': a['quoteToken'],
              };
            }).toList();
            // Keep selection valid
            if (_selectedVehicle != null && !_vehicles.any((v) => v['name'] == _selectedVehicle)) {
              _selectedVehicle = null;
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
      if (!mounted) { t.cancel(); _fareRefreshTimer = null; return; }
      _loadRealFares();
    });
  }

  // Shown when user picks a drop OUTSIDE the pickup city zone — offers to switch to Outstation
  bool _outOfZoneDialogShown = false;
  void _showOutOfZoneDialog(String zoneName) {
    if (_outOfZoneDialogShown) return; // don't spam the user on every refresh
    _outOfZoneDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.swap_horizontal_circle, color: Color(0xFFFF9800), size: 28),
          SizedBox(width: 8),
          Expanded(child: Text('Out of City', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
        content: Text(
          'Your destination is outside the $zoneName zone. Local taxi rides aren\'t available across cities — please switch to Outstation (Intercity) ride.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () { _outOfZoneDialogShown = false; Navigator.pop(context); },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A3CC8), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); // close dialog
              // Navigate to Outstation screen — user picks From/To again there
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OutstationScreen()));
            },
            icon: const Icon(Icons.map, size: 16),
            label: const Text('Switch to Outstation'),
          ),
        ],
      ),
    );
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
          _routePoints = pts;
          // Prefer road distance + duration from Directions over Haversine
          if (d['distanceKm'] != null) _rideDistance = (d['distanceKm'] as num).toDouble();
          if (d['durationMin'] != null) {
            _rideDuration = (d['durationMin'] as num).toInt();
            // Measured and traffic-aware — better than any model estimate.
            _displayTripMin = _rideDuration;
          }
        });
        _fitMapToRoute();
      }
    } catch (_) {/* fallback to estimateFare values */}
  }

  /// The "Confirm pickup" step, before anything is booked.
  bool get _confirmingPickup => _showPickupConfirmation;

  /// Close in on the pickup, for the rider to check (and drag) the pin.
  void _focusPickup() =>
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 17));

  // Fit map to pickup + drop + driver (if known) bounds
  void _fitMapToRoute() {
    // While the rider checks the pickup the map stays on it: a fare refresh
    // (every 20s) used to zoom back out to the whole route.
    if (_confirmingPickup) {
      _focusPickup();
      return;
    }
    final pts = <LatLng>[];
    pts.add(_myLocation);
    if (_routePoints.isNotEmpty) pts.addAll(_routePoints);
    if (_dropController.text.trim().isNotEmpty) pts.add(_selectedMapLocation);
    final b = boundsFromPoints(pts);
    if (b == null || _mapController == null) return;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(b, 60));
  }

  // Book the ride against the backend (keeps UI; only sends real data)
  // Resolve each non-empty stop text to {address, lat, lng} (geocode if coords missing)
  Future<List<Map<String, dynamic>>> _resolveStops() async {
    final out = <Map<String, dynamic>>[];
    for (int i = 0; i < _stopControllers.length; i++) {
      final txt = _stopControllers[i].text.trim();
      if (txt.isEmpty) continue;
      LatLng? ll = i < _stopLatLng.length ? _stopLatLng[i] : null;
      if (ll == null) {
        final results = await ApiService.placesAutocomplete(txt);
        if (results.isNotEmpty) {
          final d = await ApiService.placeDetails(results.first['placeId'] as String? ?? '');
          if (d != null && d['lat'] != null) ll = LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
        }
      }
      if (ll != null) out.add({'address': txt, 'lat': ll.latitude, 'lng': ll.longitude});
    }
    return out;
  }

  // A booking request is out: every booking control is locked.
  bool _booking = false;

  /// True while a booking request is out. Booking controls are hidden and
  /// inert while it is. Once booked, the ride replaces this screen.
  bool get _bookingLocked => _booking;

  /// Books once, then tracks — and pays for — the ride on ActiveRideScreen,
  /// like every other service. This screen used to track the ride in its own
  /// sheets and charge it on completion itself, a second payment path beside
  /// the live ride screen's.
  Future<void> _startBooking() async {
    if (_bookingLocked) return;
    setState(() => _booking = true);
    try {
      await bookAndTrack(context, book: _bookRide);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// What /fare/estimate is asked for this trip. The quote is signed over it,
  /// so a ride with stops is quoted with the same stops it is booked with.
  Map<String, dynamic> _estimateBody({List<Map<String, dynamic>> stops = const []}) {
    final hasDrop = _dropController.text.trim().isNotEmpty &&
        (_selectedMapLocation.latitude != _myLocation.latitude ||
            _selectedMapLocation.longitude != _myLocation.longitude);
    return {
      'pickupLat': _myLocation.latitude,
      'pickupLng': _myLocation.longitude,
      'dropLat': hasDrop ? _selectedMapLocation.latitude : null,
      'dropLng': hasDrop ? _selectedMapLocation.longitude : null,
      'service': 'taxi',
      'weightKg': 0,
      'totalHours': 0,
      'tripType': 'one_way',
      if (stops.isNotEmpty) 'stops': [for (final s in stops) {'lat': s['lat'], 'lng': s['lng']}],
    };
  }

  /// Books the ride and returns the server's answer.
  ///
  /// A ride with stops, or a "Try again" ([freshQuote]), is quoted again first
  /// with exactly the inputs it is booked with. The fare sent is the quoted one
  /// in full: the server validates the coupon (only the code is sent) and
  /// takes its discount off what the rider pays.
  Future<Map<String, dynamic>> _bookRide(String clientRequestId, bool freshQuote) async {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final stops = await _resolveStops();
    if (freshQuote || stops.isNotEmpty) {
      final q = await freshQuoteFor(_estimateBody(stops: stops), _selectedVehicle);
      if (q != null) {
        selectedVehicleData['quoteToken'] = q['quoteToken'];
        if (q['fare'] != null) selectedVehicleData['price'] = '₹${q['fare']}';
      }
    }
    final basePrice = int.tryParse((selectedVehicleData['price'] as String).replaceAll('₹', '')) ?? 0;
    final tip = (_selectedTip ?? 0).clamp(0, kMaxTip);
    return ApiService.bookRide({
      'clientRequestId': clientRequestId,
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
      'stops': stops,
      'paymentMode': _paymentMode,
      if (_couponCode.isNotEmpty) 'couponCode': _couponCode,
      'quoteToken': selectedVehicleData['quoteToken'],
      'preferFemaleDriver': _preferFemaleDriver,
      // Only keys still on offer: the list may have changed since the pick.
      if (_selectedPrefs.isNotEmpty)
        'preferences': _ridePrefs.map((p) => p.key).where(_selectedPrefs.contains).toList(),
    });
  }

  // Bottom sheet: show line-by-line fare breakdown
  void _showFareBreakdown() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? Theme.of(context).colorScheme.onSurface)),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? Theme.of(context).colorScheme.onSurface)),
          ]),
        );
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const Text('Fare Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Before booking: what the quote is made of. The ride screen
            // shows the server's own figures once it is booked.
            row('Distance', '${_rideDistance.toStringAsFixed(1)} km'),
            row('Duration', formatMinutes(_displayTripMin)),
            const Divider(height: 24),
            row('Estimated fare', _selectedVehicle != null
              ? (_vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => {'price': '—'})['price'] as String)
              : '—', bold: true, color: const Color(0xFF0A3CC8)),
            const SizedBox(height: 8),
            const Text('The final fare, with any coupon, is confirmed by Gora when you book.', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A3CC8), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }

  // Build Google Maps marker set
  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{};

    // Pickup (your location) — draggable so rider can fine-tune.
    // Green, as pickup is everywhere else in the app; this map alone had pickup
    // red and drop green, the reverse of the ride screen it leads to.
    // On "Confirm pickup" it is a full green pin, drawn above the vehicles: the
    // small dot was hidden under the GPS dot and nearby cars, so the "drag the
    // green pin" the sheet asks for could not be found.
    final pickupPin = _confirmingPickup || _pickupGlyph == null;
    markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: _myLocation,
      draggable: true,
      zIndexInt: 5,
      anchor: pickupPin ? const Offset(0.5, 1.0) : const Offset(0.5, 0.5),
      icon: pickupPin ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen) : _pickupGlyph!,
      infoWindow: const InfoWindow(title: 'Pickup (drag to adjust)'),
      onDragEnd: (LatLng p) async {
        setState(() {
          _myLocation = p;
          _pickupChosen = true;
          _pickupEdited = false;
        });
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
        anchor: _dropGlyph != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
        icon: _dropGlyph ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Drop', snippet: _dropController.text),
      ));
    }

    // Real nearby vehicles of the selected type.
    markers.addAll(_fleet.markers);

    return markers;
  }

  Set<Polyline> _buildMapPolylines() {
    final lines = <Polyline>{};
    // Trip polyline (pickup → drop) — drawn whenever route is available
    if (_routePoints.isNotEmpty) {
      lines.add(Polyline(
        polylineId: const PolylineId('trip'),
        points: _routePoints,
        color: const Color(0xFF0A3CC8),
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

    // Sheet sizes: the vehicle list rests at ~45%, the pickup check is short.
    final sheetInit = _showPickupConfirmation ? 0.30 : 0.45;
    final sheetMin = _showPickupConfirmation ? 0.26 : 0.35;
    final sheetMax = _showPickupConfirmation ? 0.40 : 0.88;  // drag up to see full vehicle list

    // Show map and vehicle selection after location is confirmed
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) => Stack(
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
                  // Route fits land in the part of the map the sheet leaves visible.
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 56,
                    bottom: box.maxHeight * sheetInit,
                  ),
                  markers: _buildMapMarkers(),
                  polylines: _buildMapPolylines(),
                ),
                // Back — same as the system back button.
                Positioned(
                    top: 0, left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                        child: MapCircleButton(
                          icon: Icons.arrow_back,
                          tooltip: 'Back',
                          onTap: () => Navigator.maybePop(context),
                        ),
                      ),
                    ),
                  ),
                if (!_bookingLocked)
                  DraggableScrollableSheet(
                    // A new key per step, so switching to the pickup check
                    // rebuilds the sheet at its own resting size.
                    key: ValueKey(_showPickupConfirmation),
                    initialChildSize: sheetInit,
                    minChildSize: sheetMin,
                    maxChildSize: sheetMax,
                    builder: (context, scrollController) {
                      return RideSheetContainer(
                        radius: 24,
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          children: [
                            const SheetHandle(bottom: 14),
                            if (_showPickupConfirmation) ...[
                              Text('Confirm pickup', style: RideUi.title(context, size: 22)),
                              const SizedBox(height: 4),
                              Text('Double check your pickup point — press and hold the green pin, then drag to adjust.',
                                  style: RideUi.caption(context, size: 13)),
                              const SizedBox(height: 14),
                              RideTile(
                                child: Row(
                                  children: [
                                    const RouteDot(size: 12),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _pickupController.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: RideUi.body(context, size: 14.5, weight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // ── Pickup → Drop + Distance card ──
                              _buildTripSummaryCard(),
                              const SizedBox(height: 18),
                              const RideSectionTitle('Choose a ride', size: 20),
                              const SizedBox(height: 8),
                              ..._displayVehicles.map((v) => _buildVehicleCard(v)),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            )),
          ),
          if (!_bookingLocked)
            PrimaryCtaBar(
              // The method and coupon are picked on the confirm step (where the
              // vehicle, and so the fare, is fixed); this chip shows the choice.
              leading: _showPickupConfirmation ? null : _paymentChip(),
              label: _selectedVehicle == null
                  ? 'Select a vehicle'
                  : _showPickupConfirmation ? 'Confirm Pickup' : 'Choose $_selectedVehicle',
              onPressed: _selectedVehicle == null || _bookingLocked ? null : () {
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
                  // After the frame, so the map padding for the shorter sheet
                  // is in place and the pin lands in the visible part.
                  WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _focusPickup(); });
                }
              },
            ),
        ],
      ),
    );
  }

  // Read-only payment summary for the vehicle list's bottom bar.
  Widget _paymentChip() {
    final label = _paymentMode == 'online' ? 'Online' : (_paymentMode == 'wallet' ? 'Wallet' : 'Cash');
    final icon = _paymentMode == 'online'
        ? Icons.credit_card
        : (_paymentMode == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: RidePillChip(
        icon: icon,
        label: _couponDiscount > 0 ? '$label · −₹$_couponDiscount' : label,
        showChevron: false,
      ),
    );
  }

  Widget _buildLocationSelectionScreen() {
    if (_showMapPicker) {
      return _buildMapPickerScreen();
    }

    // Field rows, top to bottom: pickup, any stops, drop. Each is drawn with
    // its slot of the dot–line–square connector on the left (Uber style).
    final fields = <Widget>[
      _buildLocationInput(Icons.radio_button_checked, _pickupController, const Color(0xFF4CAF50), 'Search pickup location',
          onChanged: _onPickupTyped,
          // "Current Location" is a label, not an address: select it so typing replaces it.
          onTap: () {
            final t = _pickupController.text;
            _pickupController.selection = TextSelection(baseOffset: 0, extentOffset: t.length);
          }),
      ..._stopControllers.asMap().entries.map((entry) => _buildStopInput(entry.value, entry.key)),
      _buildLocationInput(Icons.location_on, _dropController, const Color(0xFFFF5252), 'Where to?',
          onChanged: (q) => _searchPlaces(q, forMapPicker: false)),
    ];
    final last = fields.length - 1;
    Widget marker(int i) => i == 0
        ? const RouteDot()
        : i == last
            ? const RouteSquare()
            : Container(
                width: 9, height: 9,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RideUi.ink(context), width: 2)),
              );
    Widget line({required bool show}) => show
        ? Container(width: 2, color: RideUi.muted(context).withValues(alpha: 0.5))
        : const SizedBox(width: 2);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: RideUi.surface(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: RideUi.surface(context),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Plan your ride', style: RideUi.title(context, size: 18)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Inputs + stops scroll so the keyboard never overflows them
          Flexible(child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0)
                    // Gap between fields, with the connector running through it.
                    SizedBox(height: 8, child: Row(children: [
                      SizedBox(width: 22, child: Center(child: line(show: true))),
                    ])),
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      SizedBox(
                        width: 22,
                        child: Column(children: [
                          Expanded(child: line(show: i > 0)),
                          marker(i),
                          Expanded(child: line(show: i < last)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: fields[i]),
                    ]),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _stopControllers.add(TextEditingController());
                        _stopLatLng.add(null);
                      });
                    },
                    icon: Icon(Icons.add_rounded, color: RideUi.ink(context), size: 20),
                    label: Text('Add stop', style: RideUi.body(context, size: 13.5, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ))),
          const RideDivider(),
          // "Set location on map"
          InkWell(
            onTap: () {
              setState(() {
                _showMapPicker = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
                    child: Icon(Icons.location_on_rounded, color: RideUi.ink(context), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Set location on map', style: RideUi.body(context, size: 15, weight: FontWeight.w700))),
                  Icon(Icons.chevron_right_rounded, color: RideUi.muted(context)),
                ],
              ),
            ),
          ),
          const RideDivider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                if (_listForPickup) ...[
                  // Pickup search: GPS first, then Google's places.
                  _buildCurrentLocationTile(),
                  if (_pickupSuggestions.isNotEmpty)
                    for (var i = 0; i < _pickupSuggestions.length; i++) ...[
                      const RideDivider(indent: 54),
                      _buildSuggestionTile(_pickupSuggestions[i], forMapPicker: false, forPickup: true),
                    ]
                  else if (_searchingPickup || _pickupSearchEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(_searchingPickup ? 'Searching…' : 'No places found — try another name',
                            style: RideUi.caption(context, size: 13)),
                      ),
                    ),
                ] else if (_dropSuggestions.isNotEmpty) ...[
                  for (var i = 0; i < _dropSuggestions.length; i++) ...[
                    if (i > 0) const RideDivider(indent: 54),
                    _buildSuggestionTile(_dropSuggestions[i], forMapPicker: false),
                  ],
                ] else if (_searchingDrop || _dropSearchEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(_searchingDrop ? 'Searching…' : 'No places found — try another name',
                          style: RideUi.caption(context, size: 13)),
                    ),
                  ),
                ] else if (_dropController.text.trim().isNotEmpty) ...[
                  // A destination is chosen: nothing more to list.
                  const SizedBox.shrink(),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Column(children: [
                      Icon(Icons.search_rounded, size: 44, color: RideUi.muted(context).withValues(alpha: 0.5)),
                      const SizedBox(height: 10),
                      Text('Search for your destination',
                          style: RideUi.body(context, size: 14, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Type to see Google suggestions', style: RideUi.caption(context, size: 12)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          PrimaryCtaBar(
            label: 'Confirm Location',
            onPressed: () async {
              // A typed pickup must become a real place, or the ride would be
              // booked at the GPS point under someone else's address.
              if (_pickupEdited) {
                final typed = _pickupController.text.trim();
                var picked = false;
                if (_pickupSuggestions.isNotEmpty) {
                  picked = await _selectPickupSuggestion(_pickupSuggestions.first);
                } else if (typed.length >= 2) {
                  final results = await ApiService.placesAutocomplete(typed);
                  if (results.isNotEmpty) picked = await _selectPickupSuggestion(results.first);
                }
                if (!mounted) return;
                if (!picked) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Couldn\'t find that pickup. Pick it from the suggestions.')),
                  );
                  return;
                }
              }
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
              color: Theme.of(context).cardColor,
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
                            color: Theme.of(context).cardColor,
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
                                color: Theme.of(context).cardColor,
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
                                  color: Theme.of(context).cardColor,
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
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The pin's reverse-geocoded address (falls back to coordinates).
                    RideTile(
                      child: Row(
                        children: [
                          const RouteSquare(size: 12),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Selected Location', style: RideUi.caption(context, size: 12)),
                                const SizedBox(height: 2),
                                Text(
                                  _mapSearchController.text.trim().isNotEmpty
                                      ? _mapSearchController.text.trim()
                                      : 'Lat: ${_selectedMapLocation.latitude.toStringAsFixed(4)}, Lng: ${_selectedMapLocation.longitude.toStringAsFixed(4)}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: RideUi.body(context, size: 14.5, weight: FontWeight.w700),
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
                          backgroundColor: const Color(0xFF0A3CC8),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              backgroundColor: Theme.of(context).cardColor,
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
              child: const Icon(Icons.my_location, color: Color(0xFF0A3CC8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopInput(TextEditingController controller, int index) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: RideUi.tile(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) { if (index < _stopLatLng.length) _stopLatLng[index] = null; }, // typed → re-geocode at booking
              decoration: InputDecoration(
                hintText: 'Add stop ${index + 1} (address)',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: RideUi.caption(context, size: 15),
              ),
              style: RideUi.body(context, size: 15, weight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Remove stop',
            onPressed: () {
              setState(() {
                controller.dispose();
                _stopControllers.removeAt(index);
                if (index < _stopLatLng.length) _stopLatLng.removeAt(index);
              });
            },
            icon: Icon(Icons.close_rounded, color: RideUi.muted(context), size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    return InkWell(
      onTap: _useCurrentLocationForPickup,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
            child: Icon(Icons.my_location_rounded, color: RideUi.ink(context), size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Use current location', style: RideUi.body(context, size: 15, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Pick up from where you are now', style: RideUi.caption(context, size: 12.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildSuggestionTile(Map<String, dynamic> s, {required bool forMapPicker, bool forPickup = false}) {
    final main = s['mainText'] as String? ?? s['description'] as String? ?? '';
    final sub = s['secondaryText'] as String? ?? '';
    return InkWell(
      onTap: () => forPickup ? _selectPickupSuggestion(s) : _selectSuggestion(s, forMapPicker: forMapPicker),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
              child: Icon(Icons.location_on_rounded, color: RideUi.ink(context), size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(main, style: RideUi.body(context, size: 15, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: RideUi.caption(context, size: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // Grey, borderless field (Uber style). The marker that used to sit inside it
  // is now drawn by the dot–line–square connector beside the field.
  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint,
      {ValueChanged<String>? onChanged, VoidCallback? onTap}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: RideUi.tile(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onTap: onTap,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintStyle: RideUi.caption(context, size: 15),
        ),
        style: RideUi.body(context, size: 15, weight: FontWeight.w600),
      ),
    );
  }

  // Pickup → Drop + distance/time, shown above the vehicle list.
  Widget _buildTripSummaryCard() {
    final pickup = _pickupController.text.trim().isEmpty ? 'Current Location' : _pickupController.text;
    final drop = _dropController.text.trim().isEmpty ? 'Drop' : _dropController.text;
    final dist = _rideDistance > 0 ? '${_rideDistance.toStringAsFixed(1)} km' : '— km';
    final eta = _displayTripMin > 0 ? formatMinutes(_displayTripMin) : '— min';

    return RideTile(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TripRouteSummary(pickup: pickup, drop: drop, fontSize: 13.5),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.route_rounded, size: 15, color: RideUi.muted(context)),
            const SizedBox(width: 4),
            // One flexible label so a narrow phone ellipsizes instead of overflowing.
            Expanded(
              child: Text('$dist · $eta', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: RideUi.body(context, size: 12.5, weight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() => _locationConfirmed = false),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 30)),
              child: Text('Change', style: RideUi.body(context, size: 13, weight: FontWeight.w800).copyWith(color: RideUi.accent(context))),
            ),
          ]),
        ],
      ),
    );
  }

  // One "Choose a ride" row. Prices, ETAs and seats are the fare estimate's;
  // the drop-off time is just now + driver ETA + trip time from that estimate.
  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    final etaText = (v['eta'] ?? '').toString();
    final etaMatch = RegExp(r'^(\d+) min$').firstMatch(etaText);
    final etaMin = etaMatch != null ? int.tryParse(etaMatch.group(1)!) : null;
    final noDriver = etaText == 'No driver';
    String subtitle;
    if (etaMin != null) {
      final hasTrip = _dropController.text.trim().isNotEmpty && _displayTripMin > 0;
      subtitle = hasTrip
          ? '${formatMinutes(etaMin)} away · Drop ${RideUi.clock(DateTime.now().add(Duration(minutes: etaMin + _displayTripMin)))}'
          : '${formatMinutes(etaMin)} away';
    } else {
      subtitle = noDriver ? 'No driver nearby' : '';
    }
    final net = (v['image'] == '__net__') ? (v['networkImage'] as String?) : null;
    return VehicleOptionRow(
      selected: isSelected,
      unavailable: noDriver,
      leading: VehicleThumb(
        networkUrl: net,
        asset: net == null ? v['image'] as String? : null,
        fallbackIcon: v['icon'] as IconData,
      ),
      name: v['name'] as String,
      seats: (v['capacity'] ?? '').toString(),
      subtitle: subtitle,
      tagline: v['type'] as String?,
      price: v['price'] as String?,
      onTap: () {
        setState(() => _selectedVehicle = v['name']);
        // Show the chosen type's vehicles now, not at the next poll.
        _loadNearby();
      },
    );
  }

  void _showWaitingDialog() {
    if (_bookingLocked) return; // a ride is already live
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      // Scroll-controlled so the sheet can take the height it needs on a small
      // phone; the content scrolls inside a cap instead of overflowing.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final net = (selectedVehicleData['image'] == '__net__') ? (selectedVehicleData['networkImage'] as String?) : null;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: RideSheetContainer(
                radius: 24,
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SheetHandle(bottom: 14),
                        Text('Confirm your ride', style: RideUi.title(context, size: 22)),
                        const SizedBox(height: 14),
                        // Vehicle + fare. Tapping it opens the fare breakdown.
                        RideTile(
                          onTap: _showFareBreakdown,
                          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                          child: Row(children: [
                            VehicleThumb(
                              networkUrl: net,
                              asset: net == null ? selectedVehicleData['image'] as String? : null,
                              fallbackIcon: selectedVehicleData['icon'] as IconData,
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${selectedVehicleData['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: RideUi.body(context, size: 15.5, weight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedTip != null ? '(₹$_selectedTip tip added)' : '(Tap to see breakdown)',
                                  style: TextStyle(fontSize: 11.5, color: _selectedTip != null ? Colors.green[700] : RideUi.muted(context)),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('Total Fare', style: RideUi.caption(context, size: 11)),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('${selectedVehicleData['price']}',
                                    style: RideUi.body(context, size: 18, weight: FontWeight.w900)),
                                const SizedBox(width: 4),
                                Icon(Icons.info_outline, size: 15, color: RideUi.muted(context)),
                              ]),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        TripRouteSummary(pickup: _pickupController.text, drop: _dropController.text, fontSize: 13),
                        const RideDivider(vertical: 16),
                        Text('Add Tip', style: RideUi.body(context, size: 15, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Support your driver by adding a tip', style: RideUi.caption(context, size: 12.5)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tipAmounts.map((amount) {
                            final isSelected = _selectedTip == amount;
                            return ChoiceChip(
                              label: Text('₹$amount'),
                              selected: isSelected,
                              showCheckmark: false,
                              onSelected: (_) {
                                setDialogState(() {
                                  _selectedTip = isSelected ? null : amount;
                                });
                              },
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : RideUi.ink(context),
                                fontWeight: FontWeight.w700,
                              ),
                              selectedColor: RideUi.navy,
                              backgroundColor: RideUi.tile(context),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        PaymentCouponBar(
                          baseFare: int.tryParse(
                                  (selectedVehicleData['price'] as String).replaceAll('₹', '')) ??
                              0,
                          // Show what the booking already holds (display only).
                          initialPaymentMode: _paymentMode,
                          initialCouponCode: _couponCode,
                          initialCouponDiscount: _couponDiscount,
                          onChanged: (pm, cc, cd) {
                            setDialogState(() {});
                            setState(() {
                              _paymentMode = pm;
                              _couponCode = cc;
                              _couponDiscount = cd;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        RideTile(
                          padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                          child: Row(children: [
                            Icon(Icons.female_rounded, size: 20, color: RideUi.ink(context)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Prefer a female driver', style: RideUi.body(context, size: 13.5, weight: FontWeight.w700))),
                            Switch(
                              value: _preferFemaleDriver,
                              activeThumbColor: const Color(0xFF0A3CC8),
                              onChanged: (v) => setDialogState(() => setState(() => _preferFemaleDriver = v)),
                            ),
                          ]),
                        ),
                        if (_preferFemaleDriver)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                            child: Text("We'll try to match you with one nearby — if none are free, your next-best driver is offered instead.",
                                style: RideUi.caption(context, size: 11)),
                          ),
                        // Admin-defined preferences (pet friendly, luggage ...);
                        // hidden when none apply to taxi.
                        if (_ridePrefs.isNotEmpty) ...[
                          const RideDivider(vertical: 16),
                          RidePreferenceChips(
                            preferences: _ridePrefs,
                            selected: _selectedPrefs,
                            onChanged: (s) => setDialogState(() => setState(() => _selectedPrefs = s)),
                          ),
                        ],
                        const SizedBox(height: 18),
                        PrimaryRideButton(
                          label: _selectedTip != null ? 'Confirm with ₹$_selectedTip Tip' : 'Confirm Ride',
                          onPressed: () {
                            Navigator.of(context).pop();
                            _startBooking();
                          },
                        ),
                        const SizedBox(height: 4),
                        RideTextAction(
                          label: 'Back',
                          color: RideUi.muted(context),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

}
