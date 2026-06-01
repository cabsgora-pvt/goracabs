import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'ride_history_screen.dart';
import 'home_screen.dart';
import 'rating_screen.dart';
import 'rental_booking_details_screen.dart';

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
  bool _loadingPackages = true;
  String? _packagesError;
  // Packages grouped by vehicle name → list of {hours, km, basePrice, extraHourRate, extraKmRate, commissionPercent, etaMin}
  Map<String, List<Map<String, dynamic>>> _packagesByVehicle = {};
  Map<String, dynamic>? _selectedPackage; // the chosen package map

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

  @override
  void initState() {
    super.initState();
    _initLocationAndPackages();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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

  Future<void> _bookRental() async {
    if (_pickupLat == null || _selectedPackage == null || _selectedVehicle == null) return;
    final p = _selectedPackage!;
    DateTime? startAt;
    if (_selectedDate != null) {
      final t = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
      startAt = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, t.hour, t.minute);
    }
    try {
      final res = await ApiService.bookRide({
        'pickupAddress': _pickupController.text,
        'dropAddress': _dropController.text,
        'pickupLat': _pickupLat, 'pickupLng': _pickupLng,
        'dropLat': _pickupLat, 'dropLng': _pickupLng, // rental has no fixed drop
        'service': 'rental',
        'vehicleType': _selectedVehicle,
        'fare': p['basePrice'] ?? 0,
        'packageHours': p['hours'] ?? 0,
        'packageKm': p['km'] ?? 0,
        'extraHourRate': p['extraHourRate'] ?? 0,
        'extraKmRate': p['extraKmRate'] ?? 0,
        'departureAt': startAt?.toIso8601String(),
        'paymentMode': 'cash',
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
        // Completion handled at screen level
        if (status == 'completed') {
          t.cancel(); _pollTimer = null;
          if (!mounted) return;
          Navigator.of(this.context, rootNavigator: true).popUntil((r) => r.isFirst);
          Navigator.of(this.context).push(MaterialPageRoute(builder: (_) => RatingScreen(
            driverName: _driverName, vehicleName: _selectedVehicle ?? 'Rental', selectedTip: 0, rideId: _rideId,
          )));
          return;
        }
        onStatus(status, ride);
      } catch (_) {}
    });
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
    _selectedHours = (best['hours'] as num? ?? _selectedHours).toInt();
  }

  Map<String, dynamic> _getPackageData() {
    final p = _selectedPackage;
    if (p != null) {
      return {
        'duration': '${p['hours']} Hours',
        'distance': '${p['km']} km',
        'price': '₹${p['basePrice']}',
        'icon': Icons.schedule,
        'color': const Color(0xFF2196F3),
      };
    }
    return {
      'duration': '$_selectedHours Hours',
      'distance': '${_selectedHours * 10} km',
      'price': '₹—',
      'icon': Icons.schedule,
      'color': const Color(0xFF2196F3),
    };
  }

  final List<Map<String, dynamic>> _vehicles = [
    {'name': 'Economy', 'type': 'Comfortable', 'pricePerHour': 200, 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF2196F3), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Premium', 'pricePerHour': 250, 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF4CAF50), 'image': 'assets/images/texi.png'},
    {'name': 'Sedan', 'type': 'Spacious', 'pricePerHour': 300, 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF9C27B0), 'image': 'assets/images/texi2.png'},
    {'name': 'Premium', 'type': 'Luxury', 'pricePerHour': 400, 'capacity': '4', 'icon': Icons.car_rental, 'color': Color(0xFF795548), 'image': 'assets/images/texi3.png'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Package'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
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
                      color: Colors.white,
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
                              child: Container(
                                height: 40,
                                child: TextField(
                                  controller: _pickupController,
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
                          ],
                        ),
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
                              child: Container(
                                height: 40,
                                child: TextField(
                                  controller: _dropController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter drop location',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                      color: Colors.white,
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
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.remove, size: 20, color: Color(0xFF2196F3)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                '$_selectedHours',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                if (_selectedHours < 12) {
                                  setState(() => _selectedHours++);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add, size: 20, color: Color(0xFF2196F3)),
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
                    // Only vehicles that admin configured packages for
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _vehicles.where((v) => _packagesByVehicle.containsKey(v['name'])).length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final list = _vehicles.where((v) => _packagesByVehicle.containsKey(v['name'])).toList();
                        return _buildVehicleCard(list[index]);
                      },
                    ),
                  const SizedBox(height: 16),
                  Container(
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
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: ElevatedButton(
              onPressed: _selectedVehicle == null ? null : () {
                _showBookingConfirmationDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2196F3),
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
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    // Use the real backend package for this vehicle nearest to selected hours
    final pkgList = _packagesByVehicle[v['name'] as String] ?? [];
    Map<String, dynamic>? matchPkg;
    if (pkgList.isNotEmpty) {
      matchPkg = pkgList.first;
      int bd = ((matchPkg['hours'] as num? ?? 0).toInt() - _selectedHours).abs();
      for (final p in pkgList) {
        final d = ((p['hours'] as num? ?? 0).toInt() - _selectedHours).abs();
        if (d < bd) { matchPkg = p; bd = d; }
      }
    }
    final totalPrice = matchPkg != null ? (matchPkg['basePrice'] ?? 0) : v['pricePerHour'] * _selectedHours;
    final totalDistance = matchPkg != null ? (matchPkg['km'] ?? 0) : _selectedHours * 10;
    final pkgHours = matchPkg != null ? (matchPkg['hours'] ?? _selectedHours) : _selectedHours;
    return GestureDetector(
      onTap: () => setState(() { _selectedVehicle = v['name']; _pickPackageForVehicle(v['name'] as String); }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? (v['color'] as Color) : Colors.grey[200]!, 
            width: isSelected ? 2 : 1
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: (v['color'] as Color).withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Row(
          children: [
            Container(
              width: 90,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  v['image'],
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(v['icon'], color: v['color'] as Color, size: 40);
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v['name'], 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        v['type'], 
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• Up to $totalDistance km',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹$totalPrice',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2196F3)),
                ),
                Text(
                  '$pkgHours hr / $totalDistance km',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingConfirmationDialog() {
    final packageData = _getPackageData();
    final vehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    
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
                    const Icon(Icons.directions_car, color: Color(0xFF2196F3)),
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
                          color: Colors.grey[50],
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
                                const Text('Rate per hour', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text('₹${vehicleData['pricePerHour']}/hr', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
              Text('Finding your Pilot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Please wait while we connect you with a nearby pilot for your rental.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
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
              const Text('Pilot Assigned for Rental', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 12),
              // OTP box — driver asks for this to start
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF1976D2).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: Color(0xFF1976D2), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Share this PIN with the pilot to start', style: TextStyle(fontSize: 12, color: Colors.black54))),
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
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[200], border: Border.all(color: Colors.grey[200]!, width: 2),
                        image: _driverPicUrl.isNotEmpty ? DecorationImage(image: NetworkImage(_driverPicUrl), fit: BoxFit.cover) : null),
                      alignment: Alignment.center,
                      child: _driverPicUrl.isEmpty ? Text(_driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'P', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54)) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_driverName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
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
                    backgroundColor: const Color(0xFF2196F3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Trip Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: TextButton(onPressed: () => _showCancelReasonDialog(), child: const Text('Cancel Rental', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)))),
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
                  const Text('Cancel Rental', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const Text('Rental Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your rental service has been completed successfully.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => RatingScreen(driverName: 'Vikram Singh', vehicleName: _selectedVehicle!, selectedTip: 0))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate Your Experience', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
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
              const Text(
                'Booking Successful!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
                  backgroundColor: const Color(0xFF2196F3),
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
