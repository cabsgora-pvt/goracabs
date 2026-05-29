import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
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
  Timer? _pollTimer;

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
    _dropController.text = widget.toLocation ?? 'Select Destination';
    
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
        _selectedMapLocation = _myLocation;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 15));
    }
    _loadRealFares();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
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

  // Fetch real fares from admin zone pricing — overlay prices, keep same UI
  Future<void> _loadRealFares() async {
    try {
      final res = await ApiService.estimateFare(
        pickupLat: _myLocation.latitude, pickupLng: _myLocation.longitude, service: 'taxi',
      );
      if (res['available'] == true && res['vehicles'] is List) {
        final apiVehicles = res['vehicles'] as List;
        setState(() {
          for (final v in _vehicles) {
            final match = apiVehicles.firstWhere(
              (a) => (a['name'] as String?)?.toLowerCase() == (v['name'] as String).toLowerCase(),
              orElse: () => null,
            );
            if (match != null && match['fare'] != null) {
              v['price'] = '₹${match['fare']}';
            }
          }
        });
      }
    } catch (_) {/* keep default prices */}
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
        'paymentMode': 'cash',
      });
      if (res['ride'] != null) {
        _rideId = res['ride']['id']?.toString();
        _rideOtp = res['ride']['otp']?.toString();
      }
    } catch (_) {/* keep flow; polling will simply not find a ride */}
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
        onStatus(status, ride);
      } catch (_) {}
    });
  }

  // Build Google Maps marker set
  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{};

    // Pickup (your location)
    if (!_showFullTripMap) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _myLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }

    // Drop (full trip view)
    if (_showFullTripMap) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: const LatLng(28.6200, 77.2300),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Drop'),
      ));
    }

    // Nearby available vehicles for selected type
    if (!_isTaxiComing && _selectedVehicle != null) {
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

    // Driver coming marker
    if (_isTaxiComing && _comingTaxiLocation != null && !_showFullTripMap) {
      markers.add(Marker(
        markerId: const MarkerId('coming'),
        position: _comingTaxiLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Driver'),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildMapPolylines() {
    final lines = <Polyline>{};
    if (_isTaxiComing && !_showFullTripMap) {
      lines.add(Polyline(
        polylineId: const PolylineId('toPickup'),
        points: [const LatLng(28.6220, 77.2150), _myLocation],
        color: const Color(0xFF2196F3),
        width: 4,
      ));
    }
    if (_showFullTripMap) {
      lines.add(Polyline(
        polylineId: const PolylineId('trip'),
        points: [_myLocation, const LatLng(28.6200, 77.2300)],
        color: const Color(0xFF4CAF50),
        width: 4,
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
                          onPressed: () {},
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
                _buildLocationInput(Icons.location_on, _dropController, const Color(0xFFFF5252), 'Select Destination'),
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
                Text(
                  'RECENT',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                _buildRecentLocation(
                  'Audi Bangalore (Koramangala Road)',
                  'Koramangala, Bangalore - 560',
                ),
                _buildRecentLocation(
                  'Patna',
                  'Bihar, Rajendra Nagar, Patna - 800',
                ),
                _buildRecentLocation(
                  'JMD Mall (Sohna Road)',
                  'Sector 48, Gurugram - 122018',
                ),
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
                  onPressed: () {
                    if (_dropController.text.isNotEmpty && _dropController.text != 'Select Destination') {
                      setState(() {
                        _locationConfirmed = true;
                      });
                    }
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
            initialCameraPosition: CameraPosition(target: _selectedMapLocation, zoom: 15),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onCameraMove: (pos) {
              _selectedMapLocation = pos.target;
            },
            onCameraIdle: () {
              setState(() {});
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Move map to select location',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
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
                        onPressed: () {
                          setState(() {
                            _dropController.text = 'Lat: ${_selectedMapLocation.latitude.toStringAsFixed(4)}, Lng: ${_selectedMapLocation.longitude.toStringAsFixed(4)}';
                            _showMapPicker = false;
                            _locationConfirmed = true;
                          });
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
          // Current location button
          Positioned(
            bottom: 200,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                setState(() {
                  _selectedMapLocation = _myLocation;
                });
                _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_myLocation, 15.0));
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

  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint) {
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Fare: ${selectedVehicleData['price']}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _selectedTip != null ? '(₹$_selectedTip tip added)' : '(No tip added)',
                          style: TextStyle(fontSize: 12, color: _selectedTip != null ? Colors.green : Colors.grey[600]),
                        ),
                      ],
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
              
              // ETA and Distance Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: Color(0xFF2196F3), size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Arriving in 4 mins',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 15, color: Colors.grey[300]),
                    const SizedBox(width: 12),
                    const Icon(Icons.location_on, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '1.2 km away',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
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
                    // Driver Profile Image (Now on the left)
                    Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[200]!, width: 2),
                        image: const DecorationImage(
                          image: NetworkImage('https://i.pravatar.cc/150?u=rajesh'),
                          fit: BoxFit.cover,
                        ),
                      ),
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
                          const Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              SizedBox(width: 4),
                              Text('4.9 (1.2k+ rides)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'White Swift Dzire • DL 01 AB 1234',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
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
                      onPressed: () {},
                      icon: const Icon(Icons.message, color: Color(0xFF2196F3)),
                      label: const Text('Message', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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