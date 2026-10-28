import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../utils/vehicle_marker.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'active_ride_screen.dart';
import 'welcome_screen.dart';
import 'taxi_booking_screen.dart';
import 'outstation_screen.dart';
import 'rental_screen.dart';
import 'hire_driver_screen.dart';
import 'parcel_booking_screen.dart';
import 'inquiry_screen.dart';
import 'wallet_screen.dart';
import 'ride_history_screen.dart';
import 'split_requests_screen.dart';
import 'support_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'offers_screen.dart';
import 'service_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _promoController;
  Timer? _promoTimer;
  int _currentPromoPage = 0;
  // Active ride guard — user can't book a new ride while one is in progress
  Map<String, dynamic>? _activeRide;
  // Most recent completed taxi ride — for "Book Again". Pulled from the same
  // fetch _checkActiveRide already makes, so this costs nothing extra.
  Map<String, dynamic>? _lastRide;
  // The rider's own recent drop-offs (newest first, de-duplicated), from that
  // same ride-history fetch. Replaces a hardcoded Pune/Delhi list; the section
  // is hidden when the rider has none.
  List<Map<String, dynamic>> _recentDrops = const [];
  static bool _autoResumed = false; // auto-open the active ride once per app launch
  Timer? _activeTimer;
  // Current location for the home mini-map + chip
  LatLng? _currentLatLng;
  String _currentAddress = 'Locating…';
  GoogleMapController? _homeMapCtrl;
  // Live nearby-vehicle markers on the home map (Rapido/Ola style)
  // Ambient "vehicles nearby" layer. One shared ticker diffs the set by driver
  // id so persisting vehicles drift to their new fix instead of jumping every
  // 4s poll — rather than 40 separate animation controllers.
  late final AmbientVehicleFleet _fleet;
  Set<Marker> get _vehicleMarkers => _fleet.markers;
  Timer? _vehiclesTimer;
  Map<String, String> _favourites = {}; // label ('Home'/'Work'/custom) → address
  Timer? _homeGeoDebounce;
  // Admin-managed app config (banners / places / whyChooseUs)
  Map<String, dynamic>? _cfg;

  // 'tile' is the transparent 3D artwork shown on the home grid (Uber-style
  // grey tile); 'icon' stays as the legacy artwork used elsewhere.
  final List<Map<String, dynamic>> _services = [
    {'icon': 'assets/images/bike-bluebg.png', 'tile': 'assets/images/services/bike.png', 'short': 'Bike', 'label': 'Bike ride', 'color': Color(0xFF1C2656), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/auto-bluebg.png', 'tile': 'assets/images/services/auto.png', 'short': 'Auto', 'label': 'Auto ride', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
    {'icon': 'assets/images/texi2-bluebg.png', 'tile': 'assets/images/services/cab.png', 'short': 'Cab', 'label': 'Cab ride', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/rental-bluebg.png', 'tile': 'assets/images/services/rental.png', 'short': 'Rental', 'label': 'Rentals', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/out-station-bluebg.png', 'tile': 'assets/images/services/outstation.png', 'short': 'Outstation', 'label': 'Outstation', 'color': Color(0xFF1C2656), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/parcel-bluebg.png', 'tile': 'assets/images/services/parcel.png', 'short': 'Parcel', 'label': 'Parcel', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/hiredriver-bluebg.png', 'tile': 'assets/images/services/hire_driver.png', 'short': 'Hire driver', 'label': 'Hire driver', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/query-bluebg.png', 'tileIcon': Icons.support_agent_rounded, 'short': 'Inquiry', 'label': 'Any inquiry', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
  ];

  final List<Map<String, String>> _promos = [
    {'title': 'Travel Safe with Gora', 'sub': 'Our drivers are vaccinated!', 'color': '0xFF0052CC', 'icon': 'security'},
    {'title': 'Gora Prime Sedan', 'sub': 'Extra comfort at affordable prices', 'color': '0xFFE65100', 'icon': 'directions_car'},
    {'title': 'Express Delivery', 'sub': 'Get your parcels delivered instantly', 'color': '0xFF2E7D32', 'icon': 'local_shipping'},
    {'title': 'Weekend Gateway?', 'sub': 'Book Gora Outstation now!', 'color': '0xFF673AB7', 'icon': 'map'},
  ];

  @override
  void initState() {
    super.initState();
    _promoController = PageController(initialPage: 0, viewportFraction: 0.9);
    _startPromoTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
    _checkActiveRide();
    // Re-check periodically so the banner clears when the ride completes/cancels
    _activeTimer = Timer.periodic(const Duration(seconds: 8), (_) => _checkActiveRide());
    _fetchCurrentLocation();
    // Live vehicles on the map — first load shortly after location is known,
    // then refresh every few seconds so they appear to move.
    _fleet = AmbientVehicleFleet(
      vsync: this,
      duration: const Duration(seconds: 4),
      onUpdate: () { if (mounted) setState(() {}); },
    );
    _loadNearbyVehicles();
    _vehiclesTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadNearbyVehicles());
    _loadFavourites();
    ApiService.getAppConfig().then((c) {
      if (mounted) setState(() => _cfg = c);
    });
  }

  // Parse '#RRGGBB' (or '0xFF...') hex strings into a Color, defensively.
  Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  IconData _iconForKey(String? key) {
    switch (key) {
      case 'shield':
        return Icons.verified_user;
      case 'clock':
        return Icons.access_time;
      case 'star':
        return Icons.star;
      case 'money':
        return Icons.savings;
      case 'support':
        return Icons.support_agent;
      default:
        return Icons.check_circle;
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
      if (!mounted) return;
      setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));
      _homeMapCtrl?.animateCamera(CameraUpdate.newLatLng(_currentLatLng!));
      _loadNearbyVehicles(); // refresh live vehicles for the new location

      // Reverse-geocode for the chip label
      final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted && addr.isNotEmpty) setState(() => _currentAddress = addr);
    } catch (_) {}
  }

  // ── Live nearby vehicles on the home map ───────────────────
  // Sprite lookup + caching now live in utils/vehicle_marker.dart so the
  // idle layer and the assigned-driver marker share one implementation.
  Future<void> _loadNearbyVehicles() async {
    final at = _currentLatLng;
    if (at == null || !mounted) return;
    try {
      final drivers = await ApiService.getNearbyDrivers(at.latitude, at.longitude, radiusKm: 6);
      if (!mounted) return;
      if (drivers.isEmpty) {
        _fleet.clear();
        return;
      }
      await _fleet.update(drivers);
    } catch (_) {
      // Never let the eye-candy layer break the home screen.
    }
  }

  // Finds any in-progress ride (pending/accepted/arrived/ongoing) for the user
  Future<void> _checkActiveRide() async {
    try {
      final res = await ApiService.getMyRides();
      final list = (res['rides'] as List?) ?? [];
      const activeStatuses = ['pending', 'accepted', 'arrived', 'ongoing'];
      final active = list.firstWhere(
        (r) => activeStatuses.contains((r['status'] ?? '').toString()),
        orElse: () => null,
      );
      // Same list, already sorted newest-first by the server — the first
      // completed taxi ride with a real drop pin is what "Book Again" repeats.
      // Rental/outstation/parcel/hire aren't offered here: re-running those
      // means re-picking a package or a delivery, not a one-tap repeat.
      final lastTaxi = list.firstWhere(
        (r) => (r['status'] ?? '').toString() == 'completed'
            && ((r['service'] ?? 'taxi').toString() == 'taxi')
            && r['dropLat'] != null && r['dropLng'] != null
            && (r['dropAddress'] ?? '').toString().isNotEmpty,
        orElse: () => null,
      );
      final recent = _recentDropsFrom(list);
      if (!mounted) return;
      setState(() {
        _activeRide = active == null ? null : Map<String, dynamic>.from(active as Map);
        _lastRide = lastTaxi == null ? null : Map<String, dynamic>.from(lastTaxi as Map);
        _recentDrops = recent;
      });
      // Auto-resume the active ride once when the app is (re)opened.
      if (_activeRide != null && !_autoResumed && mounted) {
        _autoResumed = true;
        final rideId = (_activeRide!['_id'] ?? _activeRide!['id'] ?? '').toString();
        if (rideId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: rideId)))
              .then((_) => _checkActiveRide());
        }
      }
    } catch (_) {}
  }

  // Returns true if a new booking is allowed; otherwise shows a blocker dialog
  bool _canBook() {
    if (_activeRide == null) return true;
    showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Ride in progress', style: TextStyle(fontWeight: FontWeight.bold)),
      content: const Text('You already have an active ride. Please complete or cancel it before booking a new one.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK'))],
    ));
    return false;
  }

  void _startPromoTimer() {
    _promoTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPromoPage < _banners().length - 1) {
        _currentPromoPage++;
      } else {
        _currentPromoPage = 0;
      }

      if (_promoController.hasClients) {
        _promoController.animateToPage(
          _currentPromoPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutQuart,
        );
      }
    });
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _activeTimer?.cancel();
    _vehiclesTimer?.cancel();
    _fleet.dispose();
    _promoController.dispose();
    _homeMapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserProvider>(); // rebuild when user data changes
    return PopScope(
      // If we're not on the Home tab, intercept back → switch to Home tab.
      // If we're already on Home → allow system to close the app.
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: _getSelectedPage(),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomePage();
      case 1:
        return const RideHistoryScreen();
      case 2:
        return _buildProfilePage();
      default:
        return _buildHomePage();
    }
  }

  // Custom bottom nav: 3 tabs with a sliding coloured capsule behind the active one.
  Widget _buildBottomNavBar() {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.receipt_long_rounded, 'Trips'),
      (Icons.person_rounded, 'Profile'),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final capsule = dark ? const Color(0xFF5A6CB8) : const Color(0xFF1C2656);
    final inactive = dark ? Colors.white60 : Colors.grey[500]!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: LayoutBuilder(builder: (context, constraints) {
            final itemW = constraints.maxWidth / items.length;
            const h = 46.0;
            return SizedBox(
              height: h,
              child: Stack(alignment: Alignment.center, children: [
                // Sliding capsule (slightly inset from item edges)
                AnimatedAlign(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(items.length == 1 ? 0 : (_currentIndex / (items.length - 1)) * 2 - 1, 0),
                  child: Container(
                    width: itemW - 12,
                    height: h,
                    decoration: BoxDecoration(color: capsule, borderRadius: BorderRadius.circular(h / 2)),
                  ),
                ),
                // Tab items
                Row(children: List.generate(items.length, (i) {
                  final sel = _currentIndex == i;
                  return Expanded(child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _currentIndex = i),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(items[i].$1, size: 21, color: sel ? Colors.white : inactive),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: sel
                          ? Padding(padding: const EdgeInsets.only(left: 7),
                              child: Text(items[i].$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)))
                          : const SizedBox.shrink(),
                      ),
                    ]),
                  ));
                })),
              ]),
            );
          }),
        ),
      ),
    );
  }

  // Uber/Ola-style home: a full-bleed live map on top with floating controls,
  // and a white draggable sheet holding "Where to?", recent drops, services
  // and offers.
  Widget _buildHomePage() {
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        final topInset = MediaQuery.of(context).padding.top;
        // The sheet rests at ~half the screen; the map owns the rest.
        const sheetMin = 0.5;
        const overlap = 24.0; // the sheet's rounded top sits over the map
        final mapH = h * (1 - sheetMin) + overlap;
        // Expanded sheet stops below the floating top controls.
        final sheetMax = (1 - (topInset + 64) / h).clamp(sheetMin + 0.05, 1.0).toDouble();
        return Stack(children: [
          // ── Live map (movable, centre pin) ──
          Positioned(
            top: 0, left: 0, right: 0, height: mapH,
            child: GoogleMap(
              // A STABLE key. It used to be keyed on _currentLatLng, which
              // onCameraMove rewrites: every rebuild after the camera moved (the
              // vehicle layer rebuilds every few seconds) threw the map away and
              // made a new one — a blank white map recreated every ~1.5s, its
              // centre creeping off the rider each time. The camera is moved
              // through the controller instead.
              key: const ValueKey('home-map'),
              initialCameraPosition: CameraPosition(
                target: _currentLatLng ?? const LatLng(26.2389, 73.0243),
                zoom: 16,
              ),
              onMapCreated: (c) {
                _homeMapCtrl = c;
                // The GPS fix may have landed before the map existed.
                final at = _currentLatLng;
                if (at != null) c.moveCamera(CameraUpdate.newLatLng(at));
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              // Centre the camera target in the part of the map the sheet does
              // not cover, which is where the pin is drawn.
              padding: const EdgeInsets.only(bottom: overlap),
              markers: _vehicleMarkers,
              onCameraMove: (pos) => _currentLatLng = pos.target,
              onCameraIdle: _onHomeMapIdle,
            ),
          ),
          // Live centre pin. Its TIP sits on the camera target: the map's
          // bottom padding puts the target at the centre of the uncovered band
          // (0 … mapH - overlap), and the pin is lifted so the point of the
          // glyph, not the middle of the icon, lands there.
          Positioned(
            top: 0, left: 0, right: 0, height: mapH - overlap,
            child: const IgnorePointer(
              child: Center(child: CentrePin(key: ValueKey('home-centre-pin'))),
            ),
          ),
          // Recenter on the rider's GPS position
          Positioned(
            right: 14, top: mapH - overlap - 14 - 46,
            child: MapCircleButton(icon: Icons.my_location, tooltip: 'My location', onTap: _fetchCurrentLocation,
                foreground: AppTheme.primaryBlue),
          ),
          // ── Bottom sheet ──
          DraggableScrollableSheet(
            initialChildSize: sheetMin,
            minChildSize: sheetMin,
            maxChildSize: sheetMax,
            builder: (context, scrollCtrl) => RideSheetContainer(
              radius: 24,
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  const SheetHandle(bottom: 14),
                  // Live ride / Book Again lead the sheet when present.
                  if (_activeRide != null) ...[_buildActiveRideBanner(), const SizedBox(height: 14)],
                  if (_lastRide != null && _activeRide == null) ...[_buildBookAgainCard(), const SizedBox(height: 14)],
                  _homeSearchBar(),
                  if (_favourites.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: _favourites.entries.map((e) => _favChip(e.key, e.value)).toList()),
                  ],
                  // Recent drops — the rider's real recent destinations; hidden when none.
                  if (_recentDrops.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < _recentDrops.length; i++) ...[
                      if (i > 0) const RideDivider(indent: 54),
                      _buildRecentTile(_recentDrops[i]),
                    ],
                  ],
                  const SizedBox(height: 22),
                  const RideSectionTitle('Services'),
                  const SizedBox(height: 12),
                  _buildServicesGrid(),
                  _buildBannerRow(),
                ],
              ),
            ),
          ),
          // ── Floating top controls: menu · current address · save favourite ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  MapCircleButton(icon: Icons.menu_rounded, tooltip: 'Menu', onTap: _openMenu),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: RideUi.surface(context),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                      ),
                      child: Row(children: [
                        const Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_currentAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: RideUi.body(context, size: 13.5, weight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MapCircleButton(icon: Icons.favorite_border_rounded, tooltip: 'Save as favourite', onTap: _openSaveFavourite),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  void _openSearch() => Navigator.push(context, MaterialPageRoute(
      builder: (_) => TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false)));

  // Big grey "Where to?" pill with a "Now" chip on the right. Taxi rides are
  // booked for now (there is no scheduling in the taxi flow), so the chip
  // opens the same search.
  Widget _homeSearchBar() => Material(
        color: RideUi.tile(context),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _openSearch,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.search_rounded, color: RideUi.ink(context), size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Where to?', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: RideUi.title(context, size: 19)),
              ),
              RidePillChip(
                icon: Icons.schedule_rounded,
                label: 'Now',
                background: RideUi.surface(context),
                onTap: _openSearch,
              ),
            ]),
          ),
        ),
      );

  Widget _favChip(String label, String address) {
    final icon = label == 'Home' ? Icons.home_rounded : label == 'Work' ? Icons.work_rounded : Icons.favorite_rounded;
    return RidePillChip(
      icon: icon,
      label: label,
      showChevron: false,
      onTap: () {
        if (!_canBook()) return;
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false)));
      },
    );
  }

  // Reverse-geocode the map centre (debounced) → update the pickup address.
  void _onHomeMapIdle() {
    _homeGeoDebounce?.cancel();
    _homeGeoDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (_currentLatLng == null) return;
      final addr = await ApiService.reverseGeocode(_currentLatLng!.latitude, _currentLatLng!.longitude);
      if (mounted && addr.isNotEmpty) setState(() => _currentAddress = addr);
    });
  }

  Future<void> _loadFavourites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('fav_locations');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) setState(() => _favourites = map.map((k, v) => MapEntry(k, v.toString())));
      }
    } catch (_) {}
  }

  Future<void> _saveFavourite(String label) async {
    setState(() => _favourites[label] = _currentAddress);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fav_locations', jsonEncode(_favourites));
    } catch (_) {}
  }

  // Heart icon → "Save as favourite" sheet (Home / Work / Others).
  void _openSaveFavourite() {
    String selected = 'Home';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget chip(String label, IconData icon) {
          final sel = selected == label;
          return GestureDetector(
            onTap: () => setSheet(() => selected = label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: sel ? AppTheme.primaryBlue : Colors.grey.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: sel ? AppTheme.primaryBlue : Colors.black87),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? AppTheme.primaryBlue : Colors.black87)),
              ]),
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Save as favourite', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_currentAddress, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 20),
            const Text('Save location as', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              chip('Home', Icons.home_outlined),
              chip('Work', Icons.work_outline),
              chip('Others', Icons.favorite_border),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Cancel', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { _saveFavourite(selected); Navigator.pop(ctx); },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        );
      }),
    );
  }

  // Hamburger → quick menu (bottom nav is untouched, per request).
  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget item(IconData icon, String label, Widget screen) => ListTile(
              leading: Icon(icon, color: AppTheme.primaryBlue),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => screen)); },
            );
        return SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 6),
            item(Icons.person_outline, 'Profile', const ProfileScreen()),
            item(Icons.history, 'My Rides', const RideHistoryScreen()),
            item(Icons.call_split, 'Split Requests', const SplitRequestsScreen()),
            item(Icons.account_balance_wallet_outlined, 'Wallet', const WalletScreen()),
            item(Icons.local_offer_outlined, 'Offers', const OffersScreen()),
            item(Icons.support_agent, 'Support', const SupportScreen()),
            item(Icons.settings_outlined, 'Settings', const SettingsScreen()),
            const SizedBox(height: 10),
          ]),
        );
      },
    );
  }

  Widget _buildPopularCard(Map<String, String> location) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Image.network(
              location['image']!,
              width: 200,
              height: 140,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 140,
                  color: Colors.grey[300],
                  child: const Icon(Icons.image, size: 50, color: Colors.grey),
                );
              },
            ),
            Container(
              width: 200,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location['name']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location['address']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRideBanner() {
    final r = _activeRide!;
    final status = (r['status'] ?? '').toString();
    final svc = (r['service'] ?? 'taxi').toString();
    final label = {
      'pending': 'Finding your driver…',
      'accepted': 'Driver on the way',
      'arrived': 'Driver has arrived',
      'ongoing': 'Trip in progress',
    }[status] ?? 'Active ride';
    final svcName = {'rental': 'Rental', 'outstation': 'Outstation', 'hire_driver': 'Hire Driver', 'delivery': 'Parcel'}[svc] ?? 'Ride';
    // Service image asset + fallback icon
    final vt = (r['vehicleType'] ?? '').toString().toLowerCase();
    String svcAsset; IconData svcIcon;
    if (svc == 'delivery') { svcAsset = 'assets/images/parcel-bluebg.png'; svcIcon = Icons.local_shipping; }
    else if (svc == 'outstation') { svcAsset = 'assets/images/out-station-bluebg.png'; svcIcon = Icons.map; }
    else if (svc == 'rental') { svcAsset = 'assets/images/rental-bluebg.png'; svcIcon = Icons.access_time_filled; }
    else if (svc == 'hire_driver') { svcAsset = 'assets/images/hiredriver-bluebg.png'; svcIcon = Icons.person_pin_circle; }
    else if (vt.contains('bike')) { svcAsset = 'assets/images/bike-bluebg.png'; svcIcon = Icons.two_wheeler; }
    else if (vt.contains('auto')) { svcAsset = 'assets/images/auto-bluebg.png'; svcIcon = Icons.electric_rickshaw; }
    else { svcAsset = 'assets/images/texi2-bluebg.png'; svcIcon = Icons.directions_car; }
    final rideId = (r['_id'] ?? r['id'] ?? '').toString();
    return Material(
      color: RideUi.navy,
      borderRadius: BorderRadius.circular(RideUi.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(RideUi.radius),
        onTap: rideId.isEmpty ? null : () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: rideId)));
          _checkActiveRide(); // refresh after returning (may have completed/cancelled)
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Image.asset(svcAsset, width: 52, height: 52, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(width: 52, height: 52, alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Icon(svcIcon, color: RideUi.navy, size: 24)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: 2),
              Text(svcName, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 2),
              Text('${r['pickupAddress'] ?? ''} → ${r['dropAddress'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
            ])),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 7, color: Color(0xFF16A34A)),
                SizedBox(width: 5),
                Text('Live', style: TextStyle(color: RideUi.navy, fontWeight: FontWeight.w800, fontSize: 12)),
              ])),
          ]),
        ),
      ),
    );
  }

  // "Book Again" — repeats the last completed taxi ride's drop with one tap.
  // Pickup is left on the normal current-location flow (the rider has likely
  // moved since that ride), only the destination and vehicle are pre-filled;
  // fare, driver matching and payment all run through the same booking screen
  // as a fresh booking, so nothing here bypasses the real fare estimate.
  Widget _buildBookAgainCard() {
    final r = _lastRide!;
    final pickup = (r['pickupAddress'] ?? '').toString();
    final drop = (r['dropAddress'] ?? '').toString();
    final vt = (r['vehicleType'] ?? '').toString();
    final dropLat = (r['dropLat'] as num?)?.toDouble();
    final dropLng = (r['dropLng'] as num?)?.toDouble();
    final vtLower = vt.toLowerCase();
    final vehIcon = vtLower.contains('bike')
        ? Icons.two_wheeler_rounded
        : vtLower.contains('auto')
            ? Icons.electric_rickshaw_rounded
            : Icons.directions_car_rounded;
    void go() => Navigator.push(context, MaterialPageRoute(builder: (_) => TaxiBookingScreen(
          fromLocation: 'Current Location',
          toLocation: drop,
          initialDropLat: dropLat,
          initialDropLng: dropLng,
          preselectedVehicle: vt.isNotEmpty ? vt : null,
          hideLocationInputs: false,
        )));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: RideUi.surface(context),
        borderRadius: BorderRadius.circular(RideUi.radius),
        border: Border.all(color: RideUi.divider(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.replay_rounded, color: RideUi.ink(context), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Book Again', style: RideUi.title(context, size: 16))),
          if (vt.isNotEmpty)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(vehIcon, color: RideUi.ink(context), size: 14),
                  const SizedBox(width: 4),
                  Flexible(child: Text(vt, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RideUi.body(context, size: 11.5, weight: FontWeight.w700))),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        TripRouteSummary(pickup: pickup.isNotEmpty ? pickup : 'Current location', drop: drop, fontSize: 13),
        const SizedBox(height: 14),
        PrimaryRideButton(label: 'Book This Ride Again', onPressed: go, height: 46),
      ]),
    );
  }

  // Mini map showing the user's current location (tap → start a ride)
  Widget _buildHomeMap() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        SizedBox(
          height: 170,
          child: GoogleMap(
            // Stable key — see the main home map; recentred via the controller.
            key: const ValueKey('home-lite-map'),
            initialCameraPosition: CameraPosition(
              target: _currentLatLng ?? const LatLng(26.2389, 73.0243), // Jodhpur fallback
              zoom: 15,
            ),
            onMapCreated: (c) => _homeMapCtrl = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            liteModeEnabled: true, // lightweight non-interactive map for the home card
            markers: _currentLatLng == null ? {} : {
              Marker(markerId: const MarkerId('me'), position: _currentLatLng!),
            },
          ),
        ),
        // Current-location chip (Ola-style)
        Positioned(
          left: 10, top: 10, right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)]),
            child: Row(children: [
              const Icon(Icons.my_location, size: 16, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Expanded(child: Text(_currentAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        // Tap layer → open ride booking
        Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(
          onTap: () {
            if (!_canBook()) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false)));
          },
        ))),
      ]),
    );
  }

  // Recent drop-offs from the rider's ride history (GET /rides/user, newest
  // first): completed taxi rides with a real drop pin, one entry per address,
  // at most three. Taxi only, like "Book Again" — the tile books a taxi to it,
  // and a rental/hire "drop" is just the pickup again.
  static List<Map<String, dynamic>> _recentDropsFrom(List rides) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final r in rides) {
      if (r is! Map) continue;
      if ((r['status'] ?? '').toString() != 'completed') continue;
      if ((r['service'] ?? 'taxi').toString() != 'taxi') continue;
      final addr = (r['dropAddress'] ?? '').toString().trim();
      final lat = (r['dropLat'] as num?)?.toDouble();
      final lng = (r['dropLng'] as num?)?.toDouble();
      if (addr.isEmpty || lat == null || lng == null) continue;
      if (!seen.add(addr.toLowerCase())) continue;
      // "Phoenix Marketcity, Viman Nagar, Pune" → title "Phoenix Marketcity",
      // subtitle the rest; a single-part address is shown as the title only.
      final comma = addr.indexOf(',');
      out.add({
        'name': comma > 0 ? addr.substring(0, comma).trim() : addr,
        'address': comma > 0 ? addr.substring(comma + 1).trim() : '',
        'fullAddress': addr,
        'lat': lat,
        'lng': lng,
      });
      if (out.length == 3) break;
    }
    return out;
  }

  // Recent location row (Uber shortcut style: clock · title/subtitle · chevron)
  // → opens a normal ride with that drop already filled in (address + pin), the
  // same way "Book Again" does.
  Widget _buildRecentTile(Map<String, dynamic> l) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (!_canBook()) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => TaxiBookingScreen(
          fromLocation: 'Current Location',
          toLocation: (l['fullAddress'] ?? '').toString(),
          initialDropLat: l['lat'] as double?,
          initialDropLng: l['lng'] as double?,
          hideLocationInputs: false)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
            child: Icon(Icons.access_time_filled_rounded, size: 20, color: RideUi.ink(context)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((l['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: RideUi.body(context, size: 15, weight: FontWeight.w700)),
            if ((l['address'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text((l['address'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: RideUi.caption(context, size: 12.5)),
            ],
          ])),
          Icon(Icons.chevron_right_rounded, color: RideUi.muted(context)),
        ]),
      ),
    );
  }

  // Routes a service tile to its booking flow. Same targets and the same
  // active-ride guard as before; only the tile's look changed.
  void _openService(Map<String, dynamic> s) {
    if (!_canBook()) return; // block new booking while a ride is active
    if (s['label'] == 'Bike ride') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaxiBookingScreen(
            fromLocation: 'Current Location',
            hideLocationInputs: false,
            preselectedVehicle: 'Bike',
          ),
        ),
      );
    } else if (s['label'] == 'Auto ride') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaxiBookingScreen(
            fromLocation: 'Current Location',
            hideLocationInputs: false,
            preselectedVehicle: 'Auto',
          ),
        ),
      );
    } else if (s['label'] == 'Cab ride') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaxiBookingScreen(
            fromLocation: 'Current Location',
            hideLocationInputs: false,
            preselectedVehicle: 'Cab Economy',
          ),
        ),
      );
    } else if (s['label'] == 'Outstation') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const OutstationScreen()));
    } else if (s['label'] == 'Rentals') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RentalScreen()));
    } else if (s['label'] == 'Hire driver') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HireDriverScreen()));
    } else if (s['label'] == 'Parcel') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ParcelBookingScreen()));
    } else if (s['label'] == 'Any inquiry') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const InquiryScreen()));
    } else {
      // For new services, show a coming soon message or navigate to a placeholder
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${s['label']} service coming soon!'),
          backgroundColor: AppTheme.primaryBlue,
        ),
      );
    }
  }

  // Uber "Suggestions" tile: light-grey rounded square with the service image,
  // short label underneath. The white-background artwork is multiplied onto the
  // grey so it sits IN the tile instead of as a white square on top of it.
  Widget _buildServiceItem(Map<String, dynamic> s, double width) {
    final tileColor = RideUi.tile(context);
    final art = s['tile'] as String?;
    final tileIcon = s['tileIcon'] as IconData?;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(RideUi.radius),
        onTap: () => _openService(s),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: width,
            height: width * 0.78,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(RideUi.radius),
            ),
            child: tileIcon != null
                ? Icon(tileIcon, size: width * 0.42, color: RideUi.accent(context))
                : Image.asset(
                    art ?? s['icon'] as String,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(Icons.local_taxi, color: RideUi.accent(context)),
                  ),
          ),
          const SizedBox(height: 6),
          Text((s['short'] ?? s['label']) as String,
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: RideUi.body(context, size: 12.5, weight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // 4-per-row services grid; the tile width follows the sheet width so it
  // never overflows on a 320pt phone.
  Widget _buildServicesGrid() => LayoutBuilder(builder: (context, box) {
        const gap = 10.0;
        final w = ((box.maxWidth - gap * 3) / 4).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: _services.map((s) => _buildServiceItem(s, w)).toList(),
        );
      });

  // Admin-managed banners (app config, active only) as a horizontally
  // scrolling card row. Hidden when the admin has none configured.
  Widget _buildBannerRow() {
    final raw = _cfg?['banners'];
    final banners = raw is List
        ? raw.whereType<Map>().where((b) => b['isActive'] != false).toList()
        : const <Map>[];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 26),
      const RideSectionTitle('Offers & updates'),
      const SizedBox(height: 12),
      SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: banners.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final b = banners[i];
            return _buildPromoBanner({
              'title': (b['title'] ?? '').toString(),
              'sub': (b['subtitle'] ?? '').toString(),
              'color': (b['color'] ?? '').toString(),
              'imageUrl': (b['imageUrl'] ?? '').toString(),
              'icon': '',
            });
          },
        ),
      ),
    ]);
  }

  // Featured Ads source: admin config `banners` (active only) when available, else hardcoded `_promos`.
  // Returns a normalized list with keys: title, sub, color (hex/0x string), icon, imageUrl.
  List<Map<String, String>> _banners() {
    final banners = _cfg?['banners'];
    if (banners is List) {
      final active = banners
          .whereType<Map>()
          .where((b) => b['isActive'] != false)
          .map((b) => {
                'title': (b['title'] ?? '').toString(),
                'sub': (b['subtitle'] ?? '').toString(),
                'color': (b['color'] ?? '').toString(),
                'imageUrl': (b['imageUrl'] ?? '').toString(),
                'icon': '',
              })
          .toList();
      if (active.isNotEmpty) return active;
    }
    return _promos;
  }

  // One promo card in the home "Offers & updates" row: the admin's image as a
  // full-bleed card when there is one, otherwise a tinted card in the banner's
  // colour with its title and subtitle.
  Widget _buildPromoBanner(Map<String, String> promo) {
    final color = _parseHexColor(promo['color'], AppTheme.primaryBlue);
    final imageUrl = promo['imageUrl'] ?? '';
    final title = promo['title'] ?? '';
    final sub = promo['sub'] ?? '';
    IconData adIcon = Icons.local_offer;
    if (promo['icon'] == 'security') adIcon = Icons.security;
    if (promo['icon'] == 'directions_car') adIcon = Icons.directions_car;
    if (promo['icon'] == 'local_shipping') adIcon = Icons.local_shipping;
    if (promo['icon'] == 'map') adIcon = Icons.map;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty)
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ],
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(RideUi.radius),
      child: SizedBox(
        width: 264,
        child: imageUrl.isNotEmpty
            ? Stack(fit: StackFit.expand, children: [
                Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: color)),
                DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                ))),
                Padding(padding: const EdgeInsets.all(14), child: text),
              ])
            : Container(
                color: color,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(child: text),
                  const SizedBox(width: 8),
                  Icon(adIcon, color: Colors.white.withValues(alpha: 0.9), size: 34),
                ]),
              ),
      ),
    );
  }

  // "Why Choose Us" cards: admin config `whyChooseUs` when non-empty, else hardcoded fallback.
  List<Widget> _whyChooseUs() {
    final items = _cfg?['whyChooseUs'];
    if (items is List && items.isNotEmpty) {
      const palette = [Colors.green, Colors.blue, Colors.orange, Colors.purple];
      final maps = items.whereType<Map>().toList();
      final cards = <Widget>[];
      for (var i = 0; i < maps.length; i++) {
        final m = maps[i];
        if (cards.isNotEmpty) cards.add(const SizedBox(height: 12));
        cards.add(_buildFeatureCard(
          icon: _iconForKey((m['icon'] ?? '').toString()),
          title: (m['title'] ?? '').toString(),
          description: (m['desc'] ?? '').toString(),
          color: palette[i % palette.length],
        ));
      }
      if (cards.isNotEmpty) return cards;
    }
    // Fallback: original hardcoded cards
    return [
      _buildFeatureCard(
        icon: Icons.verified_user,
        title: 'Safe & Secure',
        description: 'All drivers are verified and background checked',
        color: Colors.green,
      ),
      const SizedBox(height: 12),
      _buildFeatureCard(
        icon: Icons.access_time,
        title: '24/7 Available',
        description: 'Book rides anytime, anywhere across India',
        color: Colors.blue,
      ),
      const SizedBox(height: 12),
      _buildFeatureCard(
        icon: Icons.payments,
        title: 'Best Prices',
        description: 'Affordable rates with no hidden charges',
        color: Colors.orange,
      ),
      const SizedBox(height: 12),
      _buildFeatureCard(
        icon: Icons.support_agent,
        title: 'Customer Support',
        description: 'Dedicated support team to help you 24/7',
        color: Colors.purple,
      ),
    ];
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    final u = context.watch<UserProvider>();
    final picUrl = u.profilePicUrl;
    final displayName = u.name.isNotEmpty ? u.name : (u.phone.isNotEmpty ? '+91 ${u.phone}' : 'Guest');

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primaryBlue.withAlpha(25),
                      backgroundImage: picUrl.isNotEmpty
                          ? NetworkImage(AppConfig.imageUrl(picUrl))
                          : null,
                      child: picUrl.isEmpty
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(
                      u.email.isNotEmpty ? u.email : (u.phone.isNotEmpty ? '+91 ${u.phone}' : ''),
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        foregroundColor: AppTheme.primaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildProfileMenuItem(Icons.account_balance_wallet_outlined, 'Wallet', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
              }),
              _buildProfileMenuItem(Icons.history, 'Trip Details', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RideHistoryScreen()));
              }),
              _buildProfileMenuItem(Icons.card_giftcard_outlined, 'Offers & Promos', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen()));
              }),
              _buildProfileMenuItem(Icons.help_outline, 'Help & Support', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
              }),
              _buildProfileMenuItem(Icons.settings_outlined, 'Settings', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
              _buildProfileMenuItem(Icons.logout, 'Logout', () => _confirmLogout(), color: Colors.red),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dctx);
              await ApiService.clearToken();
              if (!mounted) return;
              context.read<UserProvider>().clear();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (color ?? AppTheme.primaryBlue).withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color ?? AppTheme.primaryBlue, size: 22),
        ),
        title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color ?? Theme.of(context).colorScheme.onSurface)),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
        onTap: onTap,
      ),
    );
  }
}

class RajasthaniPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orange.withOpacity(0.15)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.orange.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Draw palace-inspired arches and geometric patterns
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw decorative arches (like palace windows)
    for (int i = 0; i < 3; i++) {
      final x = (size.width / 4) * (i + 0.5);
      final archRect = Rect.fromCenter(
        center: Offset(x, centerY - 10),
        width: 45,
        height: 30,
      );
      
      // Draw arch
      canvas.drawArc(archRect, 0, 3.14159, false, paint);
      canvas.drawArc(archRect, 0, 3.14159, false, fillPaint);
      
      // Draw small decorative circles (like palace domes)
      canvas.drawCircle(Offset(x, centerY - 25), 4, paint);
      canvas.drawCircle(Offset(x, centerY - 25), 4, fillPaint);
    }

    // Draw geometric border patterns
    final borderPaint = Paint()
      ..color = Colors.orange.withOpacity(0.12)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Top border pattern
    for (double x = 0; x < size.width; x += 25) {
      canvas.drawLine(
        Offset(x, 8),
        Offset(x + 12, 20),
        borderPaint,
      );
      canvas.drawLine(
        Offset(x + 12, 20),
        Offset(x + 25, 8),
        borderPaint,
      );
    }

    // Bottom border pattern
    for (double x = 0; x < size.width; x += 25) {
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x + 12, size.height - 20),
        borderPaint,
      );
      canvas.drawLine(
        Offset(x + 12, size.height - 20),
        Offset(x + 25, size.height - 8),
        borderPaint,
      );
    }

    // Side decorative elements
    final sidePaint = Paint()
      ..color = Colors.orange.withOpacity(0.1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Left side pattern
    for (double y = 25; y < size.height - 25; y += 18) {
      canvas.drawCircle(Offset(12, y), 3, sidePaint);
      canvas.drawLine(Offset(6, y), Offset(18, y), sidePaint);
    }

    // Right side pattern
    for (double y = 25; y < size.height - 25; y += 18) {
      canvas.drawCircle(Offset(size.width - 12, y), 3, sidePaint);
      canvas.drawLine(Offset(size.width - 18, y), Offset(size.width - 6, y), sidePaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
