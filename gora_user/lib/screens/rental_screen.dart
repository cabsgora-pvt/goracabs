import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'ride_history_screen.dart';
import 'home_screen.dart';
import 'rating_screen.dart';
import 'rental_booking_details_screen.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/finding_driver_view.dart';

class RentalScreen extends StatefulWidget {
  const RentalScreen({super.key});

  @override
  State<RentalScreen> createState() => _RentalScreenState();
}

class _RentalScreenState extends State<RentalScreen> {
  int _selectedHours = 4;
  String? _selectedVehicle;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSearching = false;
  bool _driverAssigned = false;

  // ── Backend-wired state ──
  double? _pickupLat, _pickupLng;
  double? _dropLat, _dropLng;
  bool _loadingPackages = true;
  String? _packagesError;
  // Places autocomplete
  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _dropSuggestions = [];
  Timer? _searchDebounce;
  // Map picker
  bool _showMapPicker = false;
  bool _pickingPickup = true;
  LatLng _pickerCenter = const LatLng(23.0225, 72.5714);
  GoogleMapController? _pickerMapController;
  String _pickerAddress = '';
  // Packages grouped by vehicle name → list of {hours, km, basePrice, extraHourRate, extraKmRate, commissionPercent, etaMin}
  Map<String, List<Map<String, dynamic>>> _packagesByVehicle = {};
  Map<String, dynamic>? _selectedPackage; // the chosen package map

  // ── Payment + coupon (UI-only) ──
  String _paymentMode = 'cash';
  String _couponCode = '';
  int _couponDiscount = 0;

  // Live ride state
  String? _rideId;
  String? _rideOtp;
  String _driverName = 'Pilot';
  String _driverPhone = '';
  String _driverPicUrl = '';
  String _driverVehicleModel = '';
  String _driverVehicleNumber = '';
  double _driverRating = 0;
  Timer? _pollTimer;
  // Live rental status (from backend during ride)
  String _rentalPhase = 'pending';
  double _liveHours = 0, _liveKm = 0;
  int _pkgHrs = 0, _pkgKm = 0;
  void Function(void Function())? _dialogSetState; // rebuilds the assigned dialog live

  @override
  void initState() {
    super.initState();
    _initLocationAndPackages();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    _dialogSetState = null;
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  Future<void> _initLocationAndPackages() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos != null) {
      _pickupLat = pos.latitude; _pickupLng = pos.longitude;
      final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted && addr.isNotEmpty) _pickupController.text = addr;
    }
    await _loadPackages();
  }

  Future<void> _loadPackages() async {
    if (_pickupLat == null || _pickupLng == null) {
      setState(() { _loadingPackages = false; _packagesError = 'Location needed to load packages'; });
      return;
    }
    try {
      final res = await ApiService.getRentalPackages(pickupLat: _pickupLat!, pickupLng: _pickupLng!);
      if (res['available'] != true) {
        setState(() { _loadingPackages = false; _packagesError = (res['message'] ?? 'No packages available').toString(); });
        return;
      }
      final pkgs = (res['packages'] as List?) ?? [];
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final p in pkgs) {
        final m = Map<String, dynamic>.from(p as Map);
        final name = (m['vehicleTypeName'] as String?) ?? 'Vehicle';
        (grouped[name] ??= []).add(m);
      }
      setState(() {
        _packagesByVehicle = grouped;
        _loadingPackages = false;
        _packagesError = grouped.isEmpty ? 'No rental packages configured' : null;
      });
    } catch (e) {
      setState(() { _loadingPackages = false; _packagesError = 'Failed to load packages'; });
    }
  }

  // Debounced places autocomplete
  void _searchPlaces(String q, {required bool isPickup}) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() { if (isPickup) _pickupSuggestions = []; else _dropSuggestions = []; });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await ApiService.placesAutocomplete(q);
      if (!mounted) return;
      setState(() { if (isPickup) _pickupSuggestions = results; else _dropSuggestions = results; });
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s, {required bool isPickup}) async {
    final details = await ApiService.placeDetails(s['placeId'] as String? ?? '');
    if (details == null || !mounted) return;
    final lat = (details['lat'] as num).toDouble();
    final lng = (details['lng'] as num).toDouble();
    final addr = details['address'] as String? ?? (s['description'] ?? '').toString();
    setState(() {
      if (isPickup) {
        _pickupLat = lat; _pickupLng = lng; _pickupController.text = addr; _pickupSuggestions = [];
      } else {
        _dropLat = lat; _dropLng = lng; _dropController.text = addr; _dropSuggestions = [];
      }
    });
    if (isPickup) _loadPackages(); // pickup changed → refresh packages for new zone
  }

  void _openMapPicker({required bool forPickup}) {
    final start = forPickup
        ? (_pickupLat != null ? LatLng(_pickupLat!, _pickupLng!) : _pickerCenter)
        : (_dropLat != null ? LatLng(_dropLat!, _dropLng!) : (_pickupLat != null ? LatLng(_pickupLat!, _pickupLng!) : _pickerCenter));
    setState(() { _pickingPickup = forPickup; _pickerCenter = start; _pickerAddress = ''; _showMapPicker = true; });
  }

  Future<void> _bookRental() async {
    if (_pickupLat == null || _selectedPackage == null || _selectedVehicle == null) return;
    final p = _selectedPackage!;
    DateTime? startAt;
    if (_selectedDate != null) {
      final t = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
      startAt = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, t.hour, t.minute);
    }
    try {
      final fare = _scaledPrice(p);         // hours × per-hour rate
      final res = await ApiService.bookRide({
        'pickupAddress': _pickupController.text,
        'dropAddress': _dropController.text,
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng,
        // Use real drop if the user picked one, else fall back to pickup
        'dropLat': _dropLat ?? _pickupLat, 'dropLng': _dropLng ?? _pickupLng,
        'service': 'rental',
        'vehicleType': _selectedVehicle,
        'fare': (fare - _couponDiscount).clamp(0, fare), // apply coupon, never negative
        'packageHours': _selectedHours,     // the hours the user actually picked
        'packageKm': _scaledKm(p),          // scaled included km
        'extraHourRate': p['extraHourRate'] ?? _hourlyRate(p),
        'extraKmRate': p['extraKmRate'] ?? 0,
        'departureAt': startAt?.toIso8601String(),
        'paymentMode': _paymentMode,
        'couponCode': _couponCode,
        'couponDiscount': _couponDiscount,
      });
      if (res['ride'] != null) {
        _rideId = res['ride']['id']?.toString();
        _rideOtp = res['ride']['otp']?.toString();
      }
    } catch (_) {/* polling will just find nothing */}
  }

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
        }
        // Capture live rental fields
        _rentalPhase = (ride['rentalPhase'] ?? _rentalPhase).toString();
        _liveHours = (ride['actualHours'] as num?)?.toDouble() ?? _liveHours;
        _liveKm = (ride['actualKm'] as num?)?.toDouble() ?? _liveKm;
        _pkgHrs = (ride['packageHours'] as num?)?.toInt() ?? _pkgHrs;
        _pkgKm = (ride['packageKm'] as num?)?.toInt() ?? _pkgKm;
        _dialogSetState?.call(() {}); // refresh the assigned dialog live
        // Completion → show final bill, then rating
        if (status == 'completed') {
          t.cancel(); _pollTimer = null;
          if (!mounted) return;
          Navigator.of(this.context, rootNavigator: true).popUntil((r) => r.isFirst);
          _showFinalBill(ride);
          return;
        }
        onStatus(status, ride);
      } catch (_) {}
    });
  }

  // Final bill breakdown on rental completion → then rating
  void _showFinalBill(Map<String, dynamic> ride) {
    final base = (ride['fare'] as num?)?.toInt() ?? 0;
    final exHr = (ride['extraHoursCharge'] as num?)?.toInt() ?? 0;
    final exKm = (ride['extraKmCharge'] as num?)?.toInt() ?? 0;
    final night = (ride['nightChargeRental'] as num?)?.toInt() ?? 0;
    final total = (ride['finalFare'] as num?)?.toInt() ?? (base + exHr + exKm + night);
    Widget row(String l, String v, {bool bold = false, Color? c}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: c)),
        Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: c)),
      ]),
    );
    showModalBottomSheet(context: this.context, isDismissible: false, enableDrag: false, isScrollControlled: true, backgroundColor: Theme.of(this.context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rental Bill', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          row('Used', '${(ride['actualHours'] ?? 0).toStringAsFixed(1)} hr / ${(ride['actualKm'] ?? 0).toStringAsFixed(1)} km'),
          row('Package', '${ride['packageHours'] ?? 0} hr / ${ride['packageKm'] ?? 0} km'),
          const Divider(),
          row('Base fare', '₹$base'),
          if (exHr > 0) row('Extra hours', '₹$exHr', c: Colors.orange),
          if (exKm > 0) row('Extra km', '₹$exKm', c: Colors.orange),
          if (night > 0) row('Night charge', '₹$night'),
          const Divider(),
          row('Total', '₹$total', bold: true, c: const Color(0xFF1C2656)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () { Navigator.pop(ctx); Navigator.of(this.context).push(MaterialPageRoute(builder: (_) => RatingScreen(
              driverName: _driverName, vehicleName: _selectedVehicle ?? 'Rental', selectedTip: 0, rideId: _rideId))); },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Rate your trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          )),
        ]),
      ),
    );
  }

  // Picks the package for the selected vehicle whose hours best matches _selectedHours
  void _pickPackageForVehicle(String vehicle) {
    final list = _packagesByVehicle[vehicle] ?? [];
    if (list.isEmpty) { _selectedPackage = null; return; }
    // Exact hours match, else closest
    Map<String, dynamic> best = list.first;
    int bestDiff = (best['hours'] as num? ?? 0).toInt() - _selectedHours;
    bestDiff = bestDiff.abs();
    for (final p in list) {
      final diff = ((p['hours'] as num? ?? 0).toInt() - _selectedHours).abs();
      if (diff < bestDiff) { best = p; bestDiff = diff; }
    }
    _selectedPackage = best;
  }

  // Per-hour rate derived from the package (basePrice / package hours)
  int _hourlyRate(Map<String, dynamic> p) {
    final h = (p['hours'] as num? ?? 1).toInt();
    final base = (p['basePrice'] as num? ?? 0).toInt();
    return h > 0 ? (base / h).round() : base;
  }
  int _kmPerHour(Map<String, dynamic> p) {
    final h = (p['hours'] as num? ?? 1).toInt();
    final km = (p['km'] as num? ?? 0).toInt();
    return h > 0 ? (km / h).round() : km;
  }
  // Total price for the currently selected hours, scaled from the package rate
  int _scaledPrice(Map<String, dynamic> p) => _hourlyRate(p) * _selectedHours;
  int _scaledKm(Map<String, dynamic> p) => _kmPerHour(p) * _selectedHours;

  Map<String, dynamic> _getPackageData() {
    final p = _selectedPackage;
    if (p != null) {
      return {
        'duration': '$_selectedHours Hours',
        'distance': '${_scaledKm(p)} km',
        'price': '₹${_scaledPrice(p)}',
        'icon': Icons.schedule,
        'color': const Color(0xFF1C2656),
      };
    }
    return {
      'duration': '$_selectedHours Hours',
      'distance': '${_selectedHours * 10} km',
      'price': '₹—',
      'icon': Icons.schedule,
      'color': const Color(0xFF1C2656),
    };
  }

  final List<Map<String, dynamic>> _vehicles = [
    {'name': 'Economy', 'type': 'Comfortable', 'pricePerHour': 200, 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF1C2656), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Premium', 'pricePerHour': 250, 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF4CAF50), 'image': 'assets/images/texi.png'},
    {'name': 'Sedan', 'type': 'Spacious', 'pricePerHour': 300, 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF9C27B0), 'image': 'assets/images/texi2.png'},
    {'name': 'Premium', 'type': 'Luxury', 'pricePerHour': 400, 'capacity': '4', 'icon': Icons.car_rental, 'color': Color(0xFF795548), 'image': 'assets/images/texi3.png'},
  ];

  @override
  Widget build(BuildContext context) {
    if (_showMapPicker) return _buildMapPicker();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Package'),
        elevation: 1,
        titleTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            Icon(Icons.radio_button_checked, color: Color(0xFF4CAF50), size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _pickupController,
                                  onChanged: (q) => _searchPlaces(q, isPickup: true),
                                  decoration: InputDecoration(
                                    hintText: 'Enter pickup location',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.map, color: Color(0xFF4CAF50), size: 20),
                              tooltip: 'Pick on map',
                              onPressed: () => _openMapPicker(forPickup: true),
                            ),
                          ],
                        ),
                        ..._pickupSuggestions.map((s) => _suggestionTile(s, isPickup: true)),
                        Padding(
                          padding: const EdgeInsets.only(left: 9, top: 8, bottom: 8),
                          child: Row(
                            children: [
                              Column(
                                children: List.generate(3, (index) => Container(
                                  margin: const EdgeInsets.symmetric(vertical: 1),
                                  width: 2,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[400],
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                )),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Color(0xFFFF5252), size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _dropController,
                                  onChanged: (q) => _searchPlaces(q, isPickup: false),
                                  decoration: InputDecoration(
                                    hintText: 'Drop location (optional)',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.map, color: Color(0xFFFF5252), size: 20),
                              tooltip: 'Pick on map',
                              onPressed: () => _openMapPicker(forPickup: false),
                            ),
                          ],
                        ),
                        ..._dropSuggestions.map((s) => _suggestionTile(s, isPickup: false)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Select Date & Time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setState(() => _selectedDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(_selectedDate == null 
                            ? 'Select Date' 
                            : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null) {
                              setState(() => _selectedTime = time);
                            }
                          },
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text(_selectedTime == null 
                            ? 'Select Time' 
                            : _selectedTime!.format(context)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Select Package', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Hours',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (_selectedHours > 1) {
                                  setState(() => _selectedHours--);
                                  if (_selectedVehicle != null) setState(() => _pickPackageForVehicle(_selectedVehicle!));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                                child: const Icon(Icons.remove, size: 20, color: Color(0xFF1C2656)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text('$_selectedHours', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                            GestureDetector(
                              onTap: () {
                                if (_selectedHours < 12) {
                                  setState(() => _selectedHours++);
                                  if (_selectedVehicle != null) setState(() => _pickPackageForVehicle(_selectedVehicle!));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                                child: const Icon(Icons.add, size: 20, color: Color(0xFF1C2656)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Select Vehicle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_loadingPackages)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (_packagesError != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
                      child: Row(children: [
                        Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_packagesError!, style: TextStyle(fontSize: 13, color: Colors.orange[800]))),
                      ]),
                    )
                  else
                    // Build cards straight from backend package vehicle names (no hardcoded list)
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _packagesByVehicle.keys.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final vehicleName = _packagesByVehicle.keys.elementAt(index);
                        return _buildVehicleCard(vehicleName);
                      },
                    ),
                  const SizedBox(height: 16),
                  Container(
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
                                color: Color(0xFF4CAF50).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                            ),
                            const SizedBox(width: 8),
                            const Text('Package Benefits', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('• Unlimited stops within package', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text('• Fixed pricing, no surge', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text('• Extra km charges apply beyond limit', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text('• Extra hour charges apply beyond limit', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PaymentCouponBar(
                  baseFare: _selectedPackage != null ? _scaledPrice(_selectedPackage!) : 0,
                  onChanged: (pm, cc, cd) => setState(() {
                    _paymentMode = pm;
                    _couponCode = cc;
                    _couponDiscount = cd;
                  }),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _selectedVehicle == null ? null : () {
                    _showBookingConfirmationDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF1C2656),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _selectedVehicle == null
                        ? 'Select Vehicle'
                        : 'Book Package',
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionTile(Map<String, dynamic> s, {required bool isPickup}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 18),
      title: Text(s['mainText']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(s['secondaryText']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      onTap: () => _selectSuggestion(s, isPickup: isPickup),
    );
  }

  // Full-screen draggable-pin map picker for pickup/drop
  Widget _buildMapPicker() {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => setState(() => _showMapPicker = false)),
        title: Text(_pickingPickup ? 'Pick pickup location' : 'Pick drop location', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _pickerCenter, zoom: 14),
          onMapCreated: (c) => _pickerMapController = c,
          onCameraMove: (pos) => _pickerCenter = pos.target,
          onCameraIdle: () async {
            final addr = await ApiService.reverseGeocode(_pickerCenter.latitude, _pickerCenter.longitude);
            if (!mounted) return;
            setState(() => _pickerAddress = addr);
          },
          myLocationEnabled: true, myLocationButtonEnabled: false, zoomControlsEnabled: false, mapToolbarEnabled: false,
        ),
        const Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on, color: Color(0xFFFF5252), size: 48))),
        Positioned(bottom: 180, right: 16, child: FloatingActionButton(
          mini: true, backgroundColor: Theme.of(context).cardColor,
          onPressed: () async {
            final pos = await LocationService.getCurrentLocation();
            if (pos == null) return;
            _pickerMapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
          },
          child: const Icon(Icons.my_location, color: Color(0xFF1C2656)),
        )),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))]),
          child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(_pickingPickup ? Icons.radio_button_checked : Icons.location_on, color: _pickingPickup ? const Color(0xFF4CAF50) : const Color(0xFFFF5252), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_pickerAddress.isEmpty ? 'Move the map to set location...' : _pickerAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _pickerAddress.isEmpty ? null : () {
                setState(() {
                  if (_pickingPickup) {
                    _pickupLat = _pickerCenter.latitude; _pickupLng = _pickerCenter.longitude; _pickupController.text = _pickerAddress; _pickupSuggestions = [];
                  } else {
                    _dropLat = _pickerCenter.latitude; _dropLng = _pickerCenter.longitude; _dropController.text = _pickerAddress; _dropSuggestions = [];
                  }
                  _showMapPicker = false;
                });
                if (_pickingPickup) _loadPackages();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            )),
          ])),
        )),
      ]),
    );
  }

  Widget _buildVehicleCard(String vehicleName) {
    final isSelected = _selectedVehicle == vehicleName;
    // Real backend packages for this vehicle, nearest to selected hours
    final pkgList = _packagesByVehicle[vehicleName] ?? [];
    if (pkgList.isEmpty) return const SizedBox.shrink();
    Map<String, dynamic> matchPkg = pkgList.first;
    int bd = ((matchPkg['hours'] as num? ?? 0).toInt() - _selectedHours).abs();
    for (final p in pkgList) {
      final d = ((p['hours'] as num? ?? 0).toInt() - _selectedHours).abs();
      if (d < bd) { matchPkg = p; bd = d; }
    }
    final totalPrice = _scaledPrice(matchPkg);   // hours × per-hour rate
    final totalDistance = _scaledKm(matchPkg);   // hours × per-hour km
    final pkgHours = _selectedHours;
    final cap = matchPkg['capacity'] ?? 4;
    final raw = (matchPkg['imageUrl'] as String?) ?? '';
    final imgUrl = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    const accent = Color(0xFF1C2656);

    return GestureDetector(
      onTap: () => setState(() { _selectedVehicle = vehicleName; _pickPackageForVehicle(vehicleName); }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? accent : Colors.grey[200]!, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: accent.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90, height: 60,
              child: imgUrl.isNotEmpty
                  ? Image.network(imgUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, color: accent, size: 40))
                  : const Icon(Icons.directions_car, color: accent, size: 40),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vehicleName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text('$cap seats', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Text('• ${pkgList.length} package${pkgList.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w500)),
                  ]),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹$totalPrice', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accent)),
                Text('$pkgHours hr / $totalDistance km', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingConfirmationDialog() {
    final packageData = _getPackageData();
    final vehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle,
        orElse: () => {'name': _selectedVehicle, 'pricePerHour': 0, 'image': 'assets/images/economy.png', 'type': '', 'capacity': '4', 'icon': Icons.directions_car, 'color': const Color(0xFF1C2656)});

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
                    const Icon(Icons.directions_car, color: Color(0xFF1C2656)),
                    const SizedBox(width: 8),
                    const Text(
                      'Rental Package',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                                const Text('Pick-up', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _pickupController.text.isEmpty ? 'Current Location' : _pickupController.text,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 24),
                                const Text('Drop-off', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _dropController.text.isEmpty ? 'Select destination' : _dropController.text,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Date and Time
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pickup Date & Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    '${_selectedDate == null ? 'Today' : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'} at ${_selectedTime == null ? 'Now' : _selectedTime!.format(context)}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Package Details
                      const Text('Package Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                                      Text('${vehicleData['type']} • ${vehicleData['capacity']} seats', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Duration', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text(packageData['duration'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Distance Included', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text(packageData['distance'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Extra hour rate', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text('₹${_selectedPackage?['extraHourRate'] ?? 0}/hr', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Extra km rate', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text('₹${_selectedPackage?['extraKmRate'] ?? 0}/km', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                            const Text('Total Package Price', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              packageData['price'],
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // What's Included
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
                            _buildConditionItem(Icons.check_circle, 'Unlimited stops within package', 'Make as many stops as you need'),
                            const SizedBox(height: 12),
                            _buildConditionItem(Icons.check_circle, 'Fixed pricing, no surge', 'Price locked at booking time'),
                            const SizedBox(height: 12),
                            _buildConditionItem(Icons.check_circle, 'Professional driver', 'Verified and experienced pilot'),
                            const SizedBox(height: 12),
                            _buildConditionItem(Icons.check_circle, 'AC vehicle', 'Comfortable air-conditioned ride'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Things to keep in mind
                      const Text('Additional Charges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      
                      _buildConditionItem(
                        Icons.add_road,
                        'Extra km charges',
                        'Beyond ${packageData['distance']}: ₹10/km',
                      ),
                      const SizedBox(height: 12),
                      _buildConditionItem(
                        Icons.schedule,
                        'Extra time charges',
                        'Beyond ${packageData['duration']}: ₹100/hr',
                      ),
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

  void _showFindingDriverDialog() {
    setState(() {
      _isSearching = true;
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Book the rental then poll for driver assignment
        () async {
          await _bookRental();
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

        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: FindingDriverView(
            pickupLat: _pickupLat ?? _pickerCenter.latitude,
            pickupLng: _pickupLng ?? _pickerCenter.longitude,
            dropLat: _dropLat,
            dropLng: _dropLng,
            pickupAddress: _pickupController.text,
            dropAddress: _dropController.text,
            fareText: _selectedPackage != null ? '₹${(_scaledPrice(_selectedPackage!) - _couponDiscount).clamp(0, _scaledPrice(_selectedPackage!))}' : null,
            serviceLabel: 'Rental',
            serviceIcon: Icons.timer,
            etaMin: (_selectedPackage?['etaMin'] as num?)?.toInt(),
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
        return StatefulBuilder(builder: (context, setSheet) {
        _dialogSetState = setSheet; // let polling refresh this sheet live
        final inProgress = _rentalPhase == 'ongoing' || _rentalPhase == 'extra_time' || _rentalPhase == 'paused';
        final overLimit = _liveHours > _pkgHrs || _liveKm > _pkgKm;
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
              Text(inProgress ? 'Rental in Progress' : 'Pilot Assigned for Rental', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 12),
              // Live counter once the rental has started
              if (inProgress) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: overLimit ? Colors.orange[50] : const Color(0xFF1C2656).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: overLimit ? Colors.orange : const Color(0xFF1C2656).withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      Column(children: [
                        Text('${_liveHours.toStringAsFixed(1)} hr', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: overLimit ? Colors.orange[800] : const Color(0xFF1C2656))),
                        Text('of $_pkgHrs hr', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                      Container(width: 1, height: 36, color: Colors.grey[300]),
                      Column(children: [
                        Text('${_liveKm.toStringAsFixed(1)} km', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: overLimit ? Colors.orange[800] : const Color(0xFF1C2656))),
                        Text('of $_pkgKm km', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ]),
                    if (overLimit) const Padding(padding: EdgeInsets.only(top: 8),
                      child: Text('⚠ Limit exceeded — extra charges apply', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
                    if (_rentalPhase == 'paused') const Padding(padding: EdgeInsets.only(top: 8),
                      child: Text('⏸ Driver waiting (paused)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              // OTP box — driver asks for this to start
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF1C2656).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1C2656).withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: Color(0xFF1C2656), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Share this PIN with the pilot to start', style: TextStyle(fontSize: 12, color: Colors.black54))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1C2656))),
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
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[200], border: Border.all(color: Colors.grey[200]!, width: 2),
                        image: _driverPicUrl.isNotEmpty ? DecorationImage(image: NetworkImage(_driverPicUrl), fit: BoxFit.cover) : null),
                      alignment: Alignment.center,
                      child: _driverPicUrl.isEmpty ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'P', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54)) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_driverName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16), const SizedBox(width: 4),
                        Text(_driverRating > 0 ? _driverRating.toStringAsFixed(1) : '—', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 4),
                      Text([_driverVehicleModel, _driverVehicleNumber].where((s) => s.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ])),
                    SizedBox(width: 70, height: 50, child: Image.asset(_vehicles.firstWhere((v) => v['name'] == _selectedVehicle, orElse: () => {'image': 'assets/images/economy.png'})['image'] as String, fit: BoxFit.contain)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.call, color: Colors.green), label: Text('Call', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).colorScheme.onSurface, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.message, color: Color(0xFF1C2656)), label: Text('Message', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).colorScheme.onSurface, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final packageData = _getPackageData();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RentalBookingDetailsScreen(
                          inquiryId: 'GC-RENT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                          pickupLocation: _pickupController.text.isEmpty ? 'Current Location' : _pickupController.text,
                          dropLocation: _dropController.text.isEmpty ? 'Multiple Drops' : _dropController.text,
                          duration: '$_selectedHours Hours',
                          vehicle: _selectedVehicle!,
                          price: packageData['price'],
                          date: _selectedDate == null ? 'Today' : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                          time: _selectedTime == null ? 'Now' : _selectedTime!.format(context),
                          driverName: 'Vikram Singh',
                          driverRating: '4.9 (1.2k+ trips)',
                          driverExperience: '5 Years',
                          vehicleNumber: 'RJ 14 CD 9012',
                          vehicleModel: 'Toyota Innova',
                          vehicleColor: 'White',
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
              if (!inProgress)
                Center(child: TextButton(onPressed: () => _showCancelReasonDialog(), child: const Text('Cancel Rental', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)))),
            ],
          )),
        );
        });
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
                  const Text('Cancel Rental', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const Text('Rental Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your rental service has been completed successfully.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => RatingScreen(driverName: 'Vikram Singh', vehicleName: _selectedVehicle!, selectedTip: 0))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2656), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate Your Experience', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConditionItem(IconData icon, String title, String subtitle) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }

  void _showBookingSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 50,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Booking Successful!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your $_selectedHours hours rental package has been booked successfully with $_selectedVehicle vehicle.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You will receive driver details shortly',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const RideHistoryScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C2656),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'View Ride History',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
