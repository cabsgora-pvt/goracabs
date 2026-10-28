import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../utils/duration_format.dart';
import '../services/api_service.dart';
import '../utils/vehicle_marker.dart';
import '../utils/map_markers.dart';
import '../services/location_service.dart';
import '../services/payment_service.dart';
import '../utils/polyline_utils.dart';
import '../utils/call_util.dart';
import 'ride_chat_screen.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/payment_method_picker.dart';
import '../widgets/ride_ui/ride_ui.dart';
import '../widgets/online_payment.dart';
import '../widgets/finding_driver_view.dart';
import '../widgets/cancel_reasons_sheet.dart';
import '../widgets/no_driver_found.dart';
import 'emergency_actions_screen.dart';
import 'outstation_screen.dart';
import 'rating_screen.dart';

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
    // Two animations now: the assigned vehicle's glide and the nearby fleet.
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Top-down sprite for the assigned vehicle, so the rider watches the
  // car/auto/bike they booked approach rather than a generic pin.
  BitmapDescriptor? _vehIcon;
  // Glides the vehicle between server fixes instead of teleporting it.
  late final SmoothVehicleMarker _vehicle;
  void _loadVehIcon(String type) {
    if (_vehIcon != null) return;
    VehicleMarkers.descriptorFor(type).then((ic) {
      if (mounted) setState(() => _vehIcon = ic);
    });
  }
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
  num _payableFare = 0;
  String _couponCode = '';
  int _couponDiscount = 0;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  bool _showLocationInputs = false;
  bool _showPickupConfirmation = false;
  bool _showWaitingPopup = false;
  int? _selectedTip;
  bool _isTaxiComing = false;
  // Which sheet the live ride is on. Each phase's status handler is registered
  // once, when the phase starts — never from a sheet builder, which re-runs on
  // every route change — and ignores polls once its phase is over, so a late
  // or repeated 'accepted' cannot pop or re-show anything.
  _RidePhase _phase = _RidePhase.idle;
  // The finding and driver sheets, kept so a phase change removes exactly that
  // sheet. Navigator.pop() removes whatever is on top: with any other sheet
  // open over the finding view (cancel reasons, say) the accept used to pop
  // that one and leave "Finding your ride" under the driver sheet all trip.
  Route<void>? _findingRoute;
  // Set while completion is being handled, so overlapping polls charge once.
  bool _completing = false;
  // The trip is over: the screen shows only the map under the summary.
  bool _tripDone = false;
  // Latest driver position from the server (the marker animates towards it).
  LatLng? _driverFix;
  // Straight-line km left to the drop, shown when Directions cannot answer.
  double? _tripKmLeft;
  bool _locationConfirmed = false;
  bool _showFullTripMap = false;
  bool _showArrivingButtons = false;
  bool _showMapPicker = false;
  LatLng _selectedMapLocation = const LatLng(28.6139, 77.2090);
  LatLng _myLocation = const LatLng(28.6139, 77.2090);
  GoogleMapController? _mapController;
  List<TextEditingController> _stopControllers = [];
  final List<LatLng?> _stopLatLng = [];   // resolved coords per stop (parallel to controllers)

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
  // What the current status poll reports to (finding sheet, then arriving
  // sheet). Kept so the poll can be restarted when the app comes back from the
  // background. Null once the ride is over or cancelled.
  FutureOr<void> Function(String status, Map<String, dynamic> ride)? _statusHandler;
  // One status request (and its handler) at a time - the resume refresh and
  // the timer can otherwise overlap and both act on the same 'completed'.
  bool _statusInFlight = false;
  // Latest server status, for the arriving sheet's title / ETA line.
  String _rideStatus = 'pending';
  // Bumped whenever ride/ETA state changes. A modal sheet is its own route and
  // does not rebuild on this State's setState, so the arriving sheet listens to
  // this instead - it used to keep saying "Your taxi on the way" (with a frozen
  // ETA) for the whole trip.
  final ValueNotifier<int> _sheetTick = ValueNotifier(0);
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

  // Drop search state. "Searching…" used to be shown whenever the field had
  // text and the list was empty — so it stuck after a suggestion was picked
  // (which empties the list) and whenever a search found nothing.
  bool _searchingDrop = false;
  bool _dropSearchEmpty = false;
  // Bumped per query and on selection, so a slow answer to an older query
  // cannot refill the list after the rider has moved on.
  int _searchSeq = 0;

  void _searchPlaces(String q, {required bool forMapPicker}) {
    _searchDebounce?.cancel();
    final seq = ++_searchSeq;
    if (q.trim().length < 2) {
      setState(() {
        if (forMapPicker) {
          _mapPickerSuggestions = [];
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
        _searchingDrop = true;
        _dropSearchEmpty = false;
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
        } else {
          _dropSuggestions = results;
          _searchingDrop = false;
          _dropSearchEmpty = results.isEmpty;
        }
      });
    });
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
    _vehicle = SmoothVehicleMarker(
      vsync: this,
      onUpdate: () {
        if (!mounted) return;
        setState(() {
          _driverLatLng = _vehicle.position;
          _driverHeading = _vehicle.bearing;
        });
      },
    );
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fleet = AmbientVehicleFleet(
      vsync: this,
      duration: const Duration(seconds: 4),
      onUpdate: () { if (mounted) setState(() {}); },
    );
    _nearbyTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadNearby());
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

  /// Available vehicles of the selected type near the pickup. Only while the
  /// rider is choosing — once a driver is on the way, that driver is the map.
  Future<void> _loadNearby() async {
    if (!mounted) return;
    if (_driverLatLng != null || _isTaxiComing) {
      _fleet.clear();
      return;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _sheetTick.dispose();
    _nearbyTimer?.cancel();
    _fleet.dispose();
    _vehicle.dispose();
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

  List<Map<String, dynamic>> _vehicles = [
    {'name': 'Bike', 'type': 'Quick Rides', 'price': '—', 'eta': '—', 'capacity': '1', 'icon': Icons.two_wheeler, 'color': Color(0xFF1C2656), 'image': 'assets/images/bike.png'},
    {'name': 'Auto', 'type': 'Affordable', 'price': '—', 'eta': '—', 'capacity': '3', 'icon': Icons.electric_rickshaw, 'color': Color(0xFF1C2656), 'image': 'assets/images/auto.jpg'},
    {'name': 'Cab Economy', 'type': 'Comfortable', 'price': '—', 'eta': '—', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF1C2656), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Spacious', 'price': '—', 'eta': '—', 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF1C2656), 'image': 'assets/images/texi.png'},
    {'name': 'Premium', 'type': 'Luxury Sedan', 'price': '—', 'eta': '—', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF1C2656), 'image': 'assets/images/texi2.png'},
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
                'color': const Color(0xFF1C2656),
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
      if (!mounted || _rideId != null) { t.cancel(); _fareRefreshTimer = null; return; }
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), foregroundColor: Colors.white),
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
          _routePolylineEncoded = d['polyline'] as String;
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
  bool get _confirmingPickup => _showPickupConfirmation && _phase == _RidePhase.idle;

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
    if (_driverLatLng != null) pts.add(_driverLatLng!);
    final b = boundsFromPoints(pts);
    if (b == null || _mapController == null) return;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(b, 60));
  }

  // Poll the assigned driver's live location every 5s during the ride — and
  // once straight away, so the driver (and the ETA) shows without a 5s wait.
  void _startDriverLocationPolling() {
    _driverLocTimer?.cancel();
    if (_rideId == null) return;
    _driverLocTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) { timer.cancel(); return; }
      _pollDriverLocationOnce();
    });
    _pollDriverLocationOnce();
  }

  Future<void> _pollDriverLocationOnce() async {
    if (_rideId == null) return;
    try {
      final res = await ApiService.getDriverLocation(_rideId!);
      final dr = res['driver'] as Map<String, dynamic>?;
      if (dr == null || dr['lat'] == null || dr['lng'] == null) return;
      if (!mounted) return;
      final firstFix = _driverFix == null;
      _driverFix = LatLng((dr['lat'] as num).toDouble(), (dr['lng'] as num).toDouble());
      // Resolve the sprite for the vehicle actually assigned to this ride.
      _loadVehIcon((dr['vehicleTypeName'] ?? _selectedVehicle ?? '').toString());
      // moveTo animates and calls setState itself via onUpdate.
      _vehicle.moveTo(_driverFix!, heading: (dr['heading'] as num?)?.toDouble());
      // The ETA used to wait for the next 30s tick after the first fix, so the
      // sheet read "Calculating ETA…" for half a minute.
      if (firstFix) _fetchEtaOnce();
    } catch (_) {/* keep last known */}
  }

  // A driver this close to the pickup is there. Directions cannot route a
  // zero-length trip, which left the sheet on "Calculating ETA…" for good.
  static const double _arrivedKm = 0.15;

  // Periodically recompute ETA: driver → pickup (before start), or driver → drop (during ride)
  Future<void> _fetchEtaOnce() async {
    final from = _driverFix ?? _driverLatLng;
    if (from == null || !mounted) return;
    final goingToDrop = _showFullTripMap;
    final dest = goingToDrop ? _selectedMapLocation : _myLocation;
    final straightKm = polylineLengthMeters([from, dest]) / 1000;
    if (!goingToDrop && straightKm < _arrivedKm) {
      setState(() {
        _driverEtaMin = 0;
        _driverDistanceKm = straightKm;
      });
      _sheetTick.value++;
      return;
    }
    try {
      final d = await ApiService.getDirections(
        originLat: from.latitude,
        originLng: from.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
      );
      if (!mounted) return;
      final mins = (d['durationMin'] as num?)?.toInt();
      final km = (d['distanceKm'] as num?)?.toDouble();
      setState(() {
        if (goingToDrop) {
          _tripEtaMin = mins;
          _tripKmLeft = km ?? straightKm;
        } else {
          _driverEtaMin = mins;
          _driverDistanceKm = km ?? straightKm;
        }
      });
    } catch (_) {
      // No route answer: say how far the driver is rather than calculating forever.
      if (!mounted) return;
      setState(() {
        if (goingToDrop) {
          _tripKmLeft = straightKm;
        } else {
          _driverDistanceKm = straightKm;
        }
      });
    }
    _sheetTick.value++;
  }

  /// The driver sheet's status line before pickup: a real ETA when there is
  /// one, else the distance, and "Arriving now" once the driver is there.
  String _arrivingSubtitle() {
    final km = _driverDistanceKm;
    if (_driverEtaMin == 0 || (km != null && km < _arrivedKm)) return 'Arriving now';
    if (_driverEtaMin != null) {
      return 'Arriving in ${formatMinutes(_driverEtaMin!)}${km != null ? ' · ${km.toStringAsFixed(1)} km away' : ''}';
    }
    if (km != null) return 'Driver is ${km.toStringAsFixed(1)} km away';
    if (_driverFix == null && _driverLatLng == null) return 'Locating your driver…';
    return 'Calculating ETA…';
  }

  String _ongoingSubtitle() {
    if (_tripEtaMin != null) {
      return 'Arrive by ${RideUi.clock(DateTime.now().add(Duration(minutes: _tripEtaMin!)))}';
    }
    if (_tripKmLeft != null) return '${_tripKmLeft!.toStringAsFixed(1)} km to go';
    return 'Calculating ETA…';
  }

  /// Draws the route to the drop once the trip is under way, when the booking
  /// did not already return one. Display only: the fare inputs
  /// (_rideDistance / _rideDuration) are deliberately left alone.
  Future<void> _ensureTripRoute() async {
    if (_dropController.text.trim().isEmpty) return;
    if (_routePoints.isEmpty) {
      final from = _driverFix ?? _driverLatLng ?? _myLocation;
      try {
        final d = await ApiService.getDirections(
          originLat: from.latitude,
          originLng: from.longitude,
          destLat: _selectedMapLocation.latitude,
          destLng: _selectedMapLocation.longitude,
        );
        final enc = d['polyline'];
        if (enc is String && enc.isNotEmpty && mounted) {
          setState(() => _routePoints = decodePolyline(enc));
        }
      } catch (_) {/* the drop pin still shows */}
    }
    if (mounted) _fitMapToRoute();
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
  void _openChat() {
    if (_rideId == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => RideChatScreen(rideId: _rideId!, otherName: _driverName)));
  }

  void _shareTrip() {
    if (_rideId == null) return;
    final url = '${AppConfig.serverBaseUrl}/track/$_rideId';
    Share.share('I\'m on a Gora ride — follow me live: $url', subject: 'My Gora Cabs trip');
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

  // A booking request is out. With _phase, it locks every booking control.
  bool _booking = false;

  /// True while anything other than choosing a ride is going on: a booking
  /// request out, a ride searching / assigned / under way, or a trip just
  /// finished. Booking controls are hidden and inert whenever this is true.
  bool get _bookingLocked => _phase != _RidePhase.idle || _booking || _tripDone;

  /// Books once and opens the search. Refuses while a ride is already live, so
  /// no route back to the booking controls can create a second ride.
  Future<void> _startBooking() async {
    if (_bookingLocked) return;
    setState(() => _booking = true);
    try {
      await _bookRide();
    } finally {
      _booking = false;
    }
    if (!mounted) return;
    _showFinalWaitingDialog();
  }

  Future<void> _bookRide() async {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final basePrice = int.tryParse((selectedVehicleData['price'] as String).replaceAll('₹', '')) ?? 0;
    final tip = _selectedTip ?? 0;
    final stops = await _resolveStops();
    _payableFare = (basePrice - _couponDiscount).clamp(0, basePrice);
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
        'fare': (basePrice - _couponDiscount).clamp(0, basePrice),
        'tip': tip,
        'distance': _rideDistance,
        'duration': _rideDuration,
        'stops': stops,
        'paymentMode': _paymentMode,
        'couponCode': _couponCode,
        'couponDiscount': _couponDiscount,
        'quoteToken': selectedVehicleData['quoteToken'],
        'preferFemaleDriver': _preferFemaleDriver,
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
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final b = _fareBreakdown;
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
            if (b == null) ...[
              // Pre-booking: show what we know
              row('Distance', '${_rideDistance.toStringAsFixed(1)} km'),
              row('Duration', formatMinutes(_displayTripMin)),
              const Divider(height: 24),
              row('Estimated fare', _selectedVehicle != null
                ? (_vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => {'price': '—'})['price'] as String)
                : '—', bold: true, color: const Color(0xFF1C2656)),
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
              row('Total', '₹${((b['subtotal'] ?? 0) + (_selectedTip ?? 0)).toStringAsFixed(0)}', bold: true, color: const Color(0xFF1C2656)),
              const SizedBox(height: 8),
              Text('Admin commission: ₹${(b['commission'] ?? 0).toStringAsFixed(0)} (${b['perKm'] != null ? '' : ''}deducted from driver earnings)',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }

  // Poll ride status; invokes [onStatus] with the latest status string
  void _startStatusPolling(FutureOr<void> Function(String status, Map<String, dynamic> ride) onStatus) {
    _pollTimer?.cancel();
    _statusHandler = onStatus;
    if (_rideId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) { timer.cancel(); return; }
      _pollStatusOnce();
    });
  }

  // The ride is over (completed / cancelled): stop polling and forget the
  // handler, so coming back from the background does not restart it.
  void _stopStatusPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusHandler = null;
  }

  bool _cancelling = false;

  /// Cancels the live ride with [reason], then returns this screen to a clean
  /// pre-booking state — the same outcome as cancelling on the live ride
  /// screen, which closes back to where the rider booked from.
  ///
  /// This used to depend on the reasons sheet's own context surviving the
  /// request (it returned silently when it did not), and it set the phase to
  /// "done" first — so a failed close left the rider on "Looking for nearby
  /// drivers" with the ride already cancelled, and a second booking from the
  /// same screen was ignored by the phase guard.
  Future<void> _confirmCancel(String reason) async {
    if (_cancelling) return;
    _cancelling = true;
    // Hold the polls so a late answer cannot move the ride on while we cancel.
    final handler = _statusHandler;
    _stopStatusPolling();
    try {
      if (_rideId != null) {
        Map<String, dynamic> res;
        try {
          res = await ApiService.cancelRide(_rideId!, reason);
        } catch (e) {
          res = {'error': 'No connection'};
        }
        if (!mounted) return;
        final error = res['error'];
        if (error != null) {
          // The ride is still live: keep tracking it and say why.
          if (handler != null) {
            _startStatusPolling(handler);
            _pollStatusOnce();
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not cancel: $error'),
            backgroundColor: Colors.red,
          ));
          return;
        }
      }
      if (!mounted) return;
      _resetToPreBooking(message: 'Ride cancelled');
    } finally {
      _cancelling = false;
    }
  }

  /// Closes every booking-phase sheet and puts the screen back to choosing a
  /// vehicle, with all live-ride state, polls and phase guards reset — so the
  /// rider can book again from here and it works end to end.
  void _resetToPreBooking({String? message}) {
    _stopStatusPolling();
    _driverLocTimer?.cancel();
    _driverLocTimer = null;
    _etaTimer?.cancel();
    _etaTimer = null;
    _closeSheetsAboveScreen();
    _vehicle.clear();
    _phase = _RidePhase.idle;
    _completing = false;
    _findingRoute = null;
    setState(() {
      _rideId = null;
      _rideOtp = null;
      _rideStatus = 'pending';
      _fareBreakdown = null;
      _driverName = 'Driver';
      _driverPhone = '';
      _driverPicUrl = '';
      _driverVehicleModel = '';
      _driverVehicleNumber = '';
      _driverRating = 0;
      _driverFix = null;
      _driverLatLng = null;
      _driverEtaMin = null;
      _driverDistanceKm = null;
      _tripEtaMin = null;
      _tripKmLeft = null;
      _isTaxiComing = false;
      _showArrivingButtons = false;
      _showFullTripMap = false;
      _showPickupConfirmation = false;
      _tripDone = false;
    });
    _sheetTick.value++;
    // Fresh quotes: the old ones were spent on the cancelled booking.
    _loadRealFares();
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Pops every route above this screen (finding view, driver sheet, reasons…).
  void _closeSheetsAboveScreen() {
    final own = ModalRoute.of(context);
    if (own == null || !own.isActive) return;
    Navigator.of(context).popUntil((r) => r == own);
  }

  /// Takes [route] off the navigator, whether or not it is on top.
  ///
  /// With [withAbove], sheets opened from it (e.g. cancel reasons over the
  /// finding view) go too, since they belong to the phase that just ended.
  void _closeRoute(Route<void>? route, {bool withAbove = false}) {
    if (route == null || !route.isActive) return;
    final nav = route.navigator;
    if (nav == null) return;
    if (withAbove) nav.popUntil((r) => r == route);
    if (route.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(route);
    }
  }

  // ── Phase handlers (registered once per phase, never from a builder) ──

  void _onFindingStatus(String status, Map<String, dynamic> ride) {
    if (_phase != _RidePhase.finding) return;
    if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
      _phase = _RidePhase.arriving;
      _closeRoute(_findingRoute, withAbove: true);
      _findingRoute = null;
      _showDriverArrivingDialog();
    } else if (status == 'cancelled') {
      if (_cancelling) return;
      if (isNoDriverFound(ride)) {
        _onNoDriverFound();
        return;
      }
      // Cancelled on the server (by support, etc.): the finding view must not
      // keep "looking" for a ride that no longer exists.
      _resetToPreBooking(message: 'Your ride was cancelled');
    }
  }

  /// The server closed the search: nobody took the ride in time. Stop polling,
  /// take the finding view down, say so plainly, and on "Try again" put the
  /// rider back on the vehicle list with fresh quotes (_resetToPreBooking).
  ///
  /// Purely a reaction to server state — the app has no timer of its own.
  Future<void> _onNoDriverFound() async {
    if (_phase != _RidePhase.finding) return;
    _phase = _RidePhase.done; // later polls / handlers ignore this ride
    _stopStatusPolling();
    // The poll that saw 'cancelled' (not 'pending') may have just started the
    // driver-location and ETA timers; there is no driver to track.
    _driverLocTimer?.cancel();
    _driverLocTimer = null;
    _etaTimer?.cancel();
    _etaTimer = null;
    _closeRoute(_findingRoute, withAbove: true);
    _findingRoute = null;
    await showNoDriverFoundDialog(context);
    if (!mounted) return;
    _resetToPreBooking();
  }

  Future<void> _onArrivingStatus(String status, Map<String, dynamic> ride) async {
    if (_phase != _RidePhase.arriving) return;
    if (status == 'ongoing') {
      if (!_showFullTripMap && mounted) {
        setState(() {
          _showFullTripMap = true;
          _showArrivingButtons = false;
        });
        _sheetTick.value++;
        _fetchEtaOnce();
        _ensureTripRoute();
      }
    } else if (status == 'completed') {
      if (_completing) return;
      _completing = true;
      try {
        await PaymentService.charge(context, method: _paymentMode, amount: _payableFare, rideId: _rideId);
      } catch (_) {
        _completing = false; // as before: a failed charge is retried on the next poll
        rethrow;
      }
      if (!mounted) return;
      _phase = _RidePhase.done;
      _stopStatusPolling();
      _driverLocTimer?.cancel();
      _etaTimer?.cancel();
      _closeSheetsAboveScreen();
      // A clean base for "Ride Completed!": flipping _showFullTripMap back used
      // to bring the booking UI (the "Confirm pickup" sheet still selected) and
      // the planned route back from under the trip.
      setState(() {
        _tripDone = true;
        _showFullTripMap = false;
        _showArrivingButtons = false;
        _showPickupConfirmation = false;
        _routePoints = [];
      });
      _showRideCompletedDialog();
    } else if (status == 'cancelled') {
      if (!_cancelling) _resetToPreBooking(message: 'Your ride was cancelled');
    }
  }

  Future<void> _pollStatusOnce() async {
    final onStatus = _statusHandler;
    if (_rideId == null || onStatus == null || _statusInFlight) return;
    _statusInFlight = true;
    try {
      final ride = await ApiService.getRide(_rideId!);
      if (!mounted) return;
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
      _rideStatus = status;
      _sheetTick.value++;
      // Once a driver is assigned (status >= accepted), start live driver-location + ETA polling
      if (status != 'pending' && _driverLocTimer == null) {
        _startDriverLocationPolling();
        _startEtaPolling();
      }
      // Online gating: driver requested payment → prompt rider to pay, then complete.
      if (ride['awaitingPayment'] == true && status != 'completed') {
        promptOnlinePayment(context, _rideId, ride);
      }
      await onStatus(status, ride);
    } catch (_) {
      // keep polling on transient errors
    } finally {
      _statusInFlight = false;
    }
  }

  // Back from the background: the timers may have been paused or the process
  // frozen, so the screen could still show "Your taxi on the way" long after
  // the trip started. Re-read the ride immediately and restart the timers.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final handler = _statusHandler;
    if (_rideId == null || handler == null) return; // no live ride being tracked
    _startStatusPolling(handler);
    _pollStatusOnce();
    if (_driverLocTimer != null) {
      _startDriverLocationPolling();
      _startEtaPolling();
      _fetchEtaOnce();
    }
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
        anchor: _dropGlyph != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
        icon: _dropGlyph ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Drop', snippet: _dropController.text),
      ));
    }

    // Real nearby vehicles (only before a driver is assigned)
    if (_driverLatLng == null && !_isTaxiComing) {
      markers.addAll(_fleet.markers);
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
        icon: (_vehIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
        infoWindow: InfoWindow(
          title: eta != null ? '${formatMinutes(eta)} away' : 'Driver',
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
        color: const Color(0xFF1C2656),
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
                    bottom: _showFullTripMap ? 0 : box.maxHeight * sheetInit,
                  ),
                  markers: _tripDone ? const <Marker>{} : _buildMapMarkers(),
                  polylines: _tripDone ? const <Polyline>{} : _buildMapPolylines(),
                ),
                // Back — same as the system back button.
                if (!_showFullTripMap && !_isTaxiComing)
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
                if (_showFullTripMap)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
                        child: MapCircleButton(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                      ),
                    ),
                  ),
                if (_showFullTripMap || _showArrivingButtons)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'support_btn_map',
                              onPressed: () {},
                              backgroundColor: Theme.of(context).cardColor,
                              child: Icon(Icons.support_agent, color: Theme.of(context).colorScheme.onSurface),
                            ),
                            const SizedBox(height: 12),
                            FloatingActionButton.small(
                              heroTag: 'share_btn_map',
                              onPressed: _shareTrip,
                              backgroundColor: Theme.of(context).cardColor,
                              child: Icon(Icons.share, color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_showFullTripMap && !_bookingLocked)
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
          if (!_showFullTripMap && !_bookingLocked)
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
      _buildLocationInput(Icons.radio_button_checked, _pickupController, const Color(0xFF4CAF50), 'Current Location'),
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
                if (_dropSuggestions.isNotEmpty) ...[
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
                          backgroundColor: const Color(0xFF1C2656),
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
              child: const Icon(Icons.my_location, color: Color(0xFF1C2656)),
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

  Widget _buildSuggestionTile(Map<String, dynamic> s, {required bool forMapPicker}) {
    final main = s['mainText'] as String? ?? s['description'] as String? ?? '';
    final sub = s['secondaryText'] as String? ?? '';
    return InkWell(
      onTap: () => _selectSuggestion(s, forMapPicker: forMapPicker),
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

  // Grey, borderless field (Uber style). The marker that used to sit inside it
  // is now drawn by the dot–line–square connector beside the field.
  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint, {ValueChanged<String>? onChanged}) {
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
                              activeThumbColor: const Color(0xFF1C2656),
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

  void _showFinalWaitingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    // Selected vehicle's ETA in minutes (e.g. '4 min' -> 4), null if unavailable.
    final etaMatch = RegExp(r'\d+').firstMatch('${selectedVehicleData['eta'] ?? ''}');
    final int? etaMin = etaMatch != null ? int.tryParse(etaMatch.group(0)!) : null;

    if (_phase != _RidePhase.idle || _tripDone) return; // one search per booking
    _phase = _RidePhase.finding;
    // Full-screen Ola-style finding view, as a sheet route the accept handler
    // removes by reference. Cancel reuses the existing reason flow.
    _findingRoute = _pushSheet((BuildContext context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: FindingDriverView(
            pickupLat: _myLocation.latitude,
            pickupLng: _myLocation.longitude,
            dropLat: _selectedMapLocation.latitude,
            dropLng: _selectedMapLocation.longitude,
            pickupAddress: _pickupController.text,
            dropAddress: _dropController.text,
            fareText: () {
              final sel = _vehicles.where((v) => v['name'] == _selectedVehicle);
              if (sel.isEmpty) return null;
              final n = int.tryParse((sel.first['price'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              final f = (n - _couponDiscount).clamp(0, n);
              return '₹$f';
            }(),
            // Same chip as the live ride screen shows for a taxi.
            serviceLabel: 'Ride',
            serviceIcon: Icons.local_taxi,
            vehicleType: _selectedVehicle ?? '',
            etaMin: etaMin,
            onCancel: () => _showCancelReasonDialog(),
          ),
        );
    });
    // Poll backend: while pending keep searching; when accepted show driver.
    _startStatusPolling(_onFindingStatus);
  }

  /// Pushes a non-dismissible bottom sheet and returns its route, so the phase
  /// that opened it can later remove exactly this sheet.
  Route<void> _pushSheet(WidgetBuilder builder, {Color? barrierColor}) {
    final nav = Navigator.of(context);
    final route = ModalBottomSheetRoute<void>(
      // System Back must not close a live ride's sheet: underneath is the
      // booking UI, and closing the driver sheet used to expose an active
      // "Confirm Pickup" button for a ride that was already accepted. The
      // phase handlers still remove these sheets themselves (pop/removeRoute
      // do not consult PopScope).
      builder: (ctx) => PopScope(canPop: false, child: builder(ctx)),
      capturedThemes: InheritedTheme.capture(from: context, to: nav.context),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      modalBarrierColor: barrierColor ?? Theme.of(context).bottomSheetTheme.modalBarrierColor,
    );
    nav.push(route);
    return route;
  }

  void _showDriverArrivingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);

    // Start tracking on map. The driver marker comes from the live location
    // poll — there is no placeholder position until the server reports one.
    setState(() {
      _isTaxiComing = true;
      _showArrivingButtons = true;
    });

    _pushSheet(barrierColor: Colors.transparent, (BuildContext context) {
        // Rebuilt on every status / ETA update (see _sheetTick).
        return ValueListenableBuilder<int>(
          valueListenable: _sheetTick,
          builder: (context, tick, child) {
            final ongoing = _rideStatus == 'ongoing';
            final arrived = _rideStatus == 'arrived';
            final dropText = _dropController.text.trim();
            final dropShort = dropText.contains(',') ? dropText.substring(0, dropText.indexOf(',')).trim() : dropText;
            final etaMin = ongoing ? _tripEtaMin : _driverEtaMin;
            final title = ongoing
                ? (dropShort.isNotEmpty ? 'Heading to $dropShort' : 'On the way to your destination')
                : arrived
                    ? 'Your taxi has arrived'
                    : 'Meet at the pickup point';
            final subtitle = ongoing
                ? _ongoingSubtitle()
                : arrived
                    ? 'Share the PIN with your driver to start'
                    : _arrivingSubtitle();
            final net = (selectedVehicleData['image'] == '__net__') ? (selectedVehicleData['networkImage'] as String?) : null;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: RideSheetContainer(
                radius: 24,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 16, right: 16, top: 10,
                    // Honour system bottom inset (gesture-bar) so the cancel button never overflows
                    bottom: 12 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(bottom: 14),
                      // Status + big ETA
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: RideUi.title(context, size: 19)),
                            const SizedBox(height: 4),
                            Text(subtitle, style: RideUi.caption(context, size: 13)),
                          ]),
                        ),
                        // "0 min" says nothing; the subtitle reads "Arriving now".
                        if (etaMin != null && etaMin > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: RideUi.navy, borderRadius: BorderRadius.circular(12)),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              // "4 h" over "22 min" past the hour, not "262" over "min".
                              Text(etaMin < 60 ? '$etaMin' : '${etaMin ~/ 60} h',
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.0)),
                              if (etaMin < 60 || etaMin % 60 > 0)
                                Text(etaMin < 60 ? 'min' : '${etaMin % 60} min',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 14),
                      // The PIN starts the trip; once it is under way it is spent.
                      if (_rideOtp != null && !ongoing) ...[
                        Row(children: [
                          PinChip(_rideOtp!),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Ride PIN — share it with your driver',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: RideUi.caption(context, size: 12)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                      ],
                      // Driver card
                      DriverInfoCard(
                        name: _driverName,
                        photoUrl: _driverPicUrl,
                        rating: _driverRating > 0 ? _driverRating : null,
                        vehicleModel: _driverVehicleModel,
                        plate: _driverVehicleNumber,
                        vehicleImage: VehicleThumb(
                          networkUrl: net,
                          asset: net == null ? selectedVehicleData['image'] as String? : null,
                          fallbackIcon: selectedVehicleData['icon'] as IconData,
                          size: 56,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Call · Message · Share · Safety
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          RoundActionButton(icon: Icons.call_rounded, label: 'Call', color: const Color(0xFF16A34A),
                              onTap: () => dialPhone(_driverPhone)),
                          RoundActionButton(icon: Icons.chat_bubble_rounded, label: 'Message', onTap: _openChat),
                          RoundActionButton(icon: Icons.ios_share_rounded, label: 'Share', onTap: _shareTrip),
                          RoundActionButton(
                            icon: Icons.shield_rounded,
                            label: 'Safety',
                            color: Colors.white,
                            background: const Color(0xFFD32F2F),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmergencyActionsScreen(rideId: _rideId))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Change payment method
                      StatefulBuilder(builder: (context, setRow) => paymentMethodRow(context, _paymentMode, () async {
                        final m = await showPaymentPicker(context, _paymentMode);
                        if (m != null) { _paymentMode = m; setRow(() {}); }
                      })),
                      // A trip under way cannot be cancelled from here.
                      if (!ongoing) ...[
                        const SizedBox(height: 4),
                        RideTextAction(
                          label: 'Cancel Ride',
                          // Opens the reasons OVER this sheet: backing out of
                          // them returns here instead of to an empty map.
                          onPressed: _showCancelReasonDialog,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
    });
    // Poll backend: when the ride starts switch to the trip map; when completed show the summary.
    _startStatusPolling(_onArrivingStatus);
  }

  Future<void> _showCancelReasonDialog() async {
    // The shared reasons sheet (same as the live ride screen): pick a reason,
    // then confirm. It opens OVER the finding view / driver sheet, so backing
    // out returns there.
    final reason = await showCancelReasonsSheet(context, reasons: const [
      'Plan changed',
      'Driver is too far',
      'Found another ride',
      'Wait time is too long',
      'Wrong location selected',
      'Other',
    ]);
    if (reason == null || !mounted) return;
    _confirmCancel(reason);
  }

  void _showRideCompletedDialog() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return RideSheetContainer(
          radius: 24,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text('Ride Completed!', style: RideUi.title(context, size: 22)),
                  const SizedBox(height: 6),
                  Text(
                    'You have reached your destination safely.',
                    style: RideUi.caption(context, size: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  PrimaryRideButton(
                    label: 'Rate Your Ride',
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
                            driverPhotoUrl: _driverPicUrl,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
/// Where the live ride is, for the status poll.
enum _RidePhase { idle, finding, arriving, done }
