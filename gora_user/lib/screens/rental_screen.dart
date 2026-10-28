import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/ride_booking.dart';
import '../widgets/payment_coupon_bar.dart';
import '../widgets/ride_ui/ride_ui.dart';

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

  // The booked rental is tracked on ActiveRideScreen (see _confirmRental), so
  // this screen holds no live ride state.

  @override
  void initState() {
    super.initState();
    _initLocationAndPackages();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

  /// Books the rental and returns the server's answer; [bookAndTrack] reports a
  /// failure and opens the live ride screen on success.
  Future<Map<String, dynamic>> _bookRental() async {
    if (_pickupLat == null || _selectedPackage == null || _selectedVehicle == null) {
      return {'error': 'Choose a pickup point and a package first'};
    }
    final p = _selectedPackage!;
    DateTime? startAt;
    if (_selectedDate != null) {
      final t = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
      startAt = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, t.hour, t.minute);
    }
    final fare = _scaledPrice(p);         // hours × per-hour rate
    return ApiService.bookRide({
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
  }

  /// Book once, from the button — never from a sheet builder — then track the
  /// rental on the live ride screen.
  ///
  /// No coupon is stored for the ride: a rental's coupon is applied by the
  /// server at booking, so its fare already includes the discount.
  Future<void> _confirmRental() => bookAndTrack(
    context,
    book: _bookRental,
    onBooked: (res) {
      // Tell the rider if their coupon was rejected instead of quietly
      // charging them full price. The messenger outlives this screen, so the
      // notice shows over the ride screen that replaces it.
      final promo = res['promo'];
      if (promo is Map && promo['applied'] != true && (promo['reason'] ?? '').toString().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Coupon not applied: ${promo['reason']}'),
          backgroundColor: Colors.orange,
        ));
      }
    },
  );

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

  @override
  Widget build(BuildContext context) {
    if (_showMapPicker) return _buildMapPicker();
    final selPrice = _selectedPackage != null ? _scaledPrice(_selectedPackage!) : null;
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(
        children: [
          const ServiceBackBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const ServiceTitle(title: 'Rent by the hour', subtitle: 'One car and driver for as long as you need'),
                RouteInputBlock(rows: [
                  RouteFieldRow(
                    marker: RouteMarkerKind.pickup,
                    trailing: MapPickAction(onTap: () => _openMapPicker(forPickup: true)),
                    // No fixed height: a fixed box clipped the text's descenders,
                    // and bareInput keeps the theme's outline out of the tile.
                    child: TextField(
                      controller: _pickupController,
                      onChanged: (q) => _searchPlaces(q, isPickup: true),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: RideUi.bareInput(context, 'Enter pickup location'),
                      style: RideUi.body(context, size: 14.5, weight: FontWeight.w600),
                    ),
                  ),
                  RouteFieldRow(
                    marker: RouteMarkerKind.drop,
                    trailing: MapPickAction(onTap: () => _openMapPicker(forPickup: false)),
                    child: TextField(
                      controller: _dropController,
                      onChanged: (q) => _searchPlaces(q, isPickup: false),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: RideUi.bareInput(context, 'Drop location (optional)'),
                      style: RideUi.body(context, size: 14.5, weight: FontWeight.w600),
                    ),
                  ),
                ]),
                ..._pickupSuggestions.map((s) => _suggestionTile(s, isPickup: true)),
                ..._dropSuggestions.map((s) => _suggestionTile(s, isPickup: false)),

                const ServiceSection('Pickup date & time'),
                LayoutBuilder(builder: (context, box) {
                  final date = PickerPill(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _selectedDate == null ? 'Select Date' : serviceDate(_selectedDate!),
                    placeholder: _selectedDate == null,
                    chevron: false,
                    onTap: () async {
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
                  );
                  final time = PickerPill(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: _selectedTime == null ? 'Select Time' : _selectedTime!.format(context),
                    placeholder: _selectedTime == null,
                    chevron: false,
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() => _selectedTime = time);
                      }
                    },
                  );
                  // Side by side where there is room; stacked on the narrowest
                  // phones so neither value is cut to an ellipsis.
                  if (box.maxWidth < 330) {
                    return Column(children: [date, const SizedBox(height: 10), time]);
                  }
                  return Row(children: [
                    Expanded(child: date),
                    const SizedBox(width: 10),
                    Expanded(child: time),
                  ]);
                }),

                const ServiceSection('Select Package'),
                StepperPill(
                  label: 'Select Hours',
                  caption: _selectedPackage != null
                      ? '${_scaledKm(_selectedPackage!)} km included'
                      : 'Package duration',
                  value: '$_selectedHours',
                  onMinus: _selectedHours > 1
                      ? () {
                          setState(() => _selectedHours--);
                          if (_selectedVehicle != null) setState(() => _pickPackageForVehicle(_selectedVehicle!));
                        }
                      : null,
                  onPlus: _selectedHours < 12
                      ? () {
                          setState(() => _selectedHours++);
                          if (_selectedVehicle != null) setState(() => _pickPackageForVehicle(_selectedVehicle!));
                        }
                      : null,
                ),

                const ServiceSection('Select Vehicle'),
                if (_loadingPackages)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (_packagesError != null)
                  NoticeRow(_packagesError!, tone: NoticeTone.warning)
                else
                  // Rows straight from the backend package vehicle names (no hardcoded list)
                  ..._packagesByVehicle.keys.map(_buildVehicleCard),
                const SizedBox(height: 12),
                const CollapsibleInfo(
                  title: 'Package Benefits',
                  icon: Icons.verified_outlined,
                  children: [
                    InfoLine(Icons.alt_route, 'Unlimited stops within package'),
                    InfoLine(Icons.lock_clock_outlined, 'Fixed pricing, no surge'),
                    InfoLine(Icons.add_road, 'Extra km charges apply beyond limit'),
                    InfoLine(Icons.more_time, 'Extra hour charges apply beyond limit'),
                  ],
                ),
              ],
            ),
          ),
          PrimaryCtaBar(
            top: PaymentCouponBar(
              baseFare: selPrice ?? 0,
              onChanged: (pm, cc, cd) => setState(() {
                _paymentMode = pm;
                _couponCode = cc;
                _couponDiscount = cd;
              }),
            ),
            label: _selectedVehicle == null
                ? 'Select Vehicle'
                : (selPrice != null ? 'Book Package · ₹$selPrice' : 'Book Package'),
            onPressed: _selectedVehicle == null ? null : () {
              _showBookingConfirmationDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _suggestionTile(Map<String, dynamic> s, {required bool isPickup}) {
    return PlaceSuggestionTile(
      title: s['mainText']?.toString() ?? '',
      subtitle: s['secondaryText']?.toString(),
      onTap: () => _selectSuggestion(s, isPickup: isPickup),
    );
  }

  // Full-screen draggable-pin map picker for pickup/drop
  Widget _buildMapPicker() {
    return ServiceMapPicker(
      title: _pickingPickup ? 'Pick pickup location' : 'Pick drop location',
      forPickup: _pickingPickup,
      address: _pickerAddress,
      onBack: () => setState(() => _showMapPicker = false),
      onLocate: () async {
        final pos = await LocationService.getCurrentLocation();
        if (pos == null) return;
        _pickerMapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
      },
      map: GoogleMap(
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
      onConfirm: _pickerAddress.isEmpty ? null : () {
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
    return VehicleOptionRow(
      selected: isSelected,
      onTap: () => setState(() { _selectedVehicle = vehicleName; _pickPackageForVehicle(vehicleName); }),
      leading: VehicleThumb(networkUrl: imgUrl, fallbackIcon: Icons.directions_car),
      name: vehicleName,
      seats: '$cap',
      subtitle: '$pkgHours hr / $totalDistance km',
      tagline: '${pkgList.length} package${pkgList.length != 1 ? 's' : ''}',
      price: '₹$totalPrice',
    );
  }

  /// When the rental starts, exactly as [_bookRental] sends it: no date picked
  /// means it starts now (a time alone is not sent); a date with no time
  /// starts at 9:00 AM.
  String _startLabel(BuildContext context) {
    final d = _selectedDate;
    if (d == null) return 'Starting now';
    final t = _selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
    return '${serviceDate(d)} · ${t.format(context)}';
  }

  void _showBookingConfirmationDialog() {
    final packageData = _getPackageData();
    final p = _selectedPackage;
    final cap = p?['capacity'];
    final raw = (p?['imageUrl'] as String?) ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return RideSheetContainer(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SheetHandle(),
                    Row(children: [
                      Expanded(child: Text('Confirm your rental', style: RideUi.title(context, size: 22))),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ]),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SummaryVehicleTile(
                          leading: VehicleThumb(networkUrl: raw.isEmpty ? '' : AppConfig.imageUrl(raw), fallbackIcon: Icons.directions_car, size: 48),
                          name: _selectedVehicle ?? '',
                          caption: [if (cap != null) '$cap seats', '${packageData['duration']} · ${packageData['distance']}'].join(' · '),
                          price: packageData['price'] as String,
                        ),
                        const SizedBox(height: 16),
                        TripRouteSummary(
                          pickup: _pickupController.text.isEmpty ? 'Current Location' : _pickupController.text,
                          drop: _dropController.text.isEmpty ? 'Add destination (optional)' : _dropController.text,
                          maxLines: 2,
                          fontSize: 14,
                        ),
                        const SizedBox(height: 14),
                        PickerPill(
                          icon: Icons.event_outlined,
                          label: 'Pickup Date & Time',
                          value: _startLabel(context),
                        ),

                        const ServiceSection('Package Details', top: 20),
                        SummaryRow('Duration', packageData['duration'] as String),
                        SummaryRow('Distance Included', packageData['distance'] as String),
                        SummaryRow('Extra hour rate', '₹${_selectedPackage?['extraHourRate'] ?? 0}/hr'),
                        SummaryRow('Extra km rate', '₹${_selectedPackage?['extraKmRate'] ?? 0}/km'),
                        const RideDivider(vertical: 8),
                        SummaryRow('Total Package Price', packageData['price'] as String, bold: true),

                        const SizedBox(height: 16),
                        const CollapsibleInfo(
                          title: 'What\'s Included',
                          icon: Icons.check_circle_outline,
                          children: [
                            InfoLine(Icons.alt_route, 'Unlimited stops within package', subtitle: 'Make as many stops as you need'),
                            InfoLine(Icons.lock_clock_outlined, 'Fixed pricing, no surge', subtitle: 'Price locked at booking time'),
                            InfoLine(Icons.verified_user_outlined, 'Professional driver', subtitle: 'Verified and experienced pilot'),
                            InfoLine(Icons.ac_unit, 'AC vehicle', subtitle: 'Comfortable air-conditioned ride'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // The package's own rates — the same figures listed above.
                        CollapsibleInfo(
                          title: 'Additional Charges',
                          icon: Icons.receipt_long_outlined,
                          children: [
                            InfoLine(Icons.add_road, 'Extra km charges',
                                subtitle: 'Beyond ${packageData['distance']}: ₹${_selectedPackage?['extraKmRate'] ?? 0}/km'),
                            InfoLine(Icons.schedule, 'Extra time charges',
                                subtitle: 'Beyond ${packageData['duration']}: ₹${_selectedPackage?['extraHourRate'] ?? 0}/hr'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                PrimaryCtaBar(
                  label: 'Confirm Booking',
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmRental();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
