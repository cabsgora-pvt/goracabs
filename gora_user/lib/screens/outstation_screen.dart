import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
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

  // Live ride state
  String? _rideId;
  String? _rideOtp;
  String _driverName = 'Pilot';
  String _driverPhone = '';
  String _driverPicUrl = '';
  String _driverVehicleModel = '';
  String _driverVehicleNumber = '';
  Timer? _pollTimer;

  final List<Map<String, dynamic>> _vehicles = [
    {'name': 'Economy', 'type': 'Comfortable', 'oneWayPrice': '—', 'roundTripPrice': '—', 'oneWayFare': 0, 'roundTripFare': 0, 'capacity': '4', 'icon': Icons.directions_car, 'image': 'assets/images/economy.png'},
    {'name': 'Sedan',   'type': 'Premium',     'oneWayPrice': '—', 'roundTripPrice': '—', 'oneWayFare': 0, 'roundTripFare': 0, 'capacity': '4', 'icon': Icons.directions_car, 'image': 'assets/images/texi.png'},
    {'name': 'SUV',     'type': 'Spacious',    'oneWayPrice': '—', 'roundTripPrice': '—', 'oneWayFare': 0, 'roundTripFare': 0, 'capacity': '6', 'icon': Icons.airport_shuttle, 'image': 'assets/images/texi2.png'},
    {'name': 'Premium', 'type': 'Luxury',      'oneWayPrice': '—', 'roundTripPrice': '—', 'oneWayFare': 0, 'roundTripFare': 0, 'capacity': '4', 'icon': Icons.car_rental, 'image': 'assets/images/texi3.png'},
  ];

  @override
  void initState() {
    super.initState();
    // Set empty controllers for placeholders
    _fromController.text = '';
    _toController.text = '';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _distanceKm = (oneWay['oneWayKm'] as num?)?.toDouble() ?? (oneWay['distance'] as num?)?.toDouble() ?? 0;
        _durationMin = (oneWay['oneWayMin'] as num?)?.toInt() ?? (oneWay['duration'] as num?)?.toInt() ?? 0;

        final oneWayVehicles = (oneWay['vehicles'] as List?) ?? [];
        final roundVehicles = (round['vehicles'] as List?) ?? [];
        for (final v in _vehicles) {
          final ow = oneWayVehicles.firstWhere(
            (a) => (a['name'] as String?)?.toLowerCase() == (v['name'] as String).toLowerCase(),
            orElse: () => null);
          final rt = roundVehicles.firstWhere(
            (a) => (a['name'] as String?)?.toLowerCase() == (v['name'] as String).toLowerCase(),
            orElse: () => null);
          if (ow != null) { v['oneWayFare'] = ow['fare'] ?? 0; v['oneWayPrice'] = '₹${ow['fare']}'; }
          if (rt != null) { v['roundTripFare'] = rt['fare'] ?? 0; v['roundTripPrice'] = '₹${rt['fare']}'; }
        }
        _loadingFares = false;
      });
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

    // Combine date + time controllers into ISO strings
    DateTime? departureAt;
    DateTime? returnAt;
    try {
      if (_departureDateController.text.isNotEmpty) {
        departureAt = DateTime.tryParse(_departureDateController.text);
      }
      if (isRoundTrip && _returnDateController.text.isNotEmpty) {
        returnAt = DateTime.tryParse(_returnDateController.text);
      }
    } catch (_) {}

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
        'departureAt': departureAt?.toIso8601String(),
        'returnAt': returnAt?.toIso8601String(),
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
        }
        onStatus(status, ride);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      Padding(
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
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(28.6139, 77.2090),
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.goracabs.customer',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(28.6139, 77.2090),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on, color: Color(0xFF4CAF50), size: 40),
                        ),
                        Marker(
                          point: LatLng(28.7041, 77.1025),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
                DraggableScrollableSheet(
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
                                              'Estimated distance: 45 km • Duration: 1h 30m',
                                              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_showVehicleSelection)
                                    const SizedBox(height: 16),
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

  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint) {
    final isFrom = identical(controller, _fromController);
    final suggestions = isFrom ? _fromSuggestions : _toSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 18),
                  title: Text(s['mainText']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(s['secondaryText']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  onTap: () => _selectSuggestion(s, isFrom: isFrom),
                );
              },
            ),
          ),
      ],
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
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  controller.text = '${date.day}/${date.month}/${date.year}';
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
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  controller.text = time.format(context);
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
            Container(
              width: 60,
              height: 50,
              child: Image.asset(
                v['image'],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(v['icon'], color: Color(0xFF2196F3), size: 40);
                },
              ),
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
                                const Text('~250 km', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Estimated Duration', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                const Text('~5 hours', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
        // Actually book the outstation ride then poll backend for driver assignment
        () async {
          await _bookOutstationRide();
          _startStatusPolling((status, ride) {
            if (status == 'accepted' || status == 'arrived' || status == 'ongoing') {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
                _showDriverAssignedDialog();
              }
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
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3))),
              SizedBox(height: 16),
              Text('Finding your Outstation Pilot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Please wait while we connect you with a nearby pilot for your outstation trip.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              SizedBox(height: 20),
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
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const Text('Pilot Assigned for Outstation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 16),
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
                    SizedBox(width: 70, height: 50, child: Image.asset(_vehicles.firstWhere((v) => v['name'] == _selectedVehicle)['image'], fit: BoxFit.contain)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.call, color: Colors.green), label: const Text('Call', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.message, color: Color(0xFF2196F3)), label: const Text('Message', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
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
                          inquiryId: 'GC-OUT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                          fromLocation: _fromController.text.isEmpty ? 'Current Location' : _fromController.text,
                          toLocation: _toController.text.isEmpty ? 'Select Destination' : _toController.text,
                          vehicleName: _selectedVehicle!,
                          vehicleType: selectedVehicleData['type'],
                          capacity: selectedVehicleData['capacity'],
                          tripType: _tripType,
                          departureDate: _departureDateController.text.isEmpty ? 'Today' : _departureDateController.text,
                          departureTime: _departureTimeController.text.isEmpty ? 'Now' : _departureTimeController.text,
                          returnDate: _tripType == 'Round Trip' ? (_returnDateController.text.isEmpty ? 'Not Set' : _returnDateController.text) : null,
                          returnTime: _tripType == 'Round Trip' ? (_returnTimeController.text.isEmpty ? 'Not Set' : _returnTimeController.text) : null,
                          price: currentPrice,
                          estimatedDistance: '~250 km',
                          estimatedDuration: '~5 hours',
                          driverName: 'Rahul Sharma',
                          driverRating: '4.8 (2.5k+ trips)',
                          driverExperience: '7 Years',
                          vehicleNumber: 'RJ 14 EF 1234',
                          vehicleModel: 'Mahindra Marazzo',
                          vehicleColor: 'Silver',
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
          ),
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
