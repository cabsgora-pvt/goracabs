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
import 'support_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'offers_screen.dart';
import 'service_selection_screen.dart';
import 'mini_ride_screen.dart';
import 'prime_ride_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late PageController _promoController;
  Timer? _promoTimer;
  int _currentPromoPage = 0;
  // Active ride guard — user can't book a new ride while one is in progress
  Map<String, dynamic>? _activeRide;
  Timer? _activeTimer;
  // Current location for the home mini-map + chip
  LatLng? _currentLatLng;
  String _currentAddress = 'Locating…';
  GoogleMapController? _homeMapCtrl;
  Map<String, String> _favourites = {}; // label ('Home'/'Work'/custom) → address
  Timer? _homeGeoDebounce;
  // Admin-managed app config (banners / places / whyChooseUs)
  Map<String, dynamic>? _cfg;

  final List<Map<String, dynamic>> _services = [
    {'icon': 'assets/images/bike-bluebg.png', 'label': 'Bike ride', 'color': Color(0xFF1C2656), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/auto-bluebg.png', 'label': 'Auto ride', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
    {'icon': 'assets/images/texi2-bluebg.png', 'label': 'Cab ride', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/rental-bluebg.png', 'label': 'Rentals', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/out-station-bluebg.png', 'label': 'Outstation', 'color': Color(0xFF1C2656), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/parcel-bluebg.png', 'label': 'Parcel', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/hiredriver-bluebg.png', 'label': 'Hire driver', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/query-bluebg.png', 'label': 'Any inquiry', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
  ];

  final List<Map<String, String>> _popularLocations = [
    {'name': 'Phoenix Mall', 'address': 'Nagar Road, Pune', 'image': 'https://images.unsplash.com/photo-1519567241046-7f570eee3ce6?w=400'},
    {'name': 'Airport Terminal 3', 'address': 'IGI Airport, Delhi', 'image': 'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=400'},
    {'name': 'Railway Station', 'address': 'New Delhi Railway Station', 'image': 'https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=400'},
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
      // Reverse-geocode for the chip label
      final addr = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted && addr.isNotEmpty) setState(() => _currentAddress = addr);
    } catch (_) {}
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
      if (!mounted) return;
      setState(() => _activeRide = active == null ? null : Map<String, dynamic>.from(active as Map));
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

  Widget _buildHomePage() {
    final user = context.watch<UserProvider>();
    final picUrl = user.profilePicUrl;
    final displayName = user.name.isNotEmpty ? user.name : (user.phone.isNotEmpty ? user.phone : 'Guest');

    final mapH = MediaQuery.of(context).size.height * 0.42;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Map on top (movable, live pin) with overlaid bar ──
          SizedBox(
            height: mapH,
            child: Stack(children: [
              Positioned.fill(
                child: GoogleMap(
                  key: ValueKey(_currentLatLng?.toString() ?? 'home-map'),
                  initialCameraPosition: CameraPosition(
                    target: _currentLatLng ?? const LatLng(26.2389, 73.0243),
                    zoom: 16,
                  ),
                  onMapCreated: (c) => _homeMapCtrl = c,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onCameraMove: (pos) => _currentLatLng = pos.target,
                  onCameraIdle: _onHomeMapIdle,
                ),
              ),
              // Live centre pin
              const IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(Icons.location_on, size: 46, color: AppTheme.primaryBlue),
                  ),
                ),
              ),
              // Top bar: menu · location · favourite(heart)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(children: [
                    _circleIcon(Icons.menu, _openMenu),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)],
                        ),
                        child: Text(_currentAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _circleIcon(Icons.favorite_border, _openSaveFavourite),
                  ]),
                ),
              ),
              // Recenter
              Positioned(
                right: 14, bottom: 22,
                child: GestureDetector(
                  onTap: _fetchCurrentLocation,
                  child: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.my_location, color: AppTheme.primaryBlue)),
                ),
              ),
            ]),
          ),
          // ── Bottom sheet content ──
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -16),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Search
                    _homeSearchBar(),
                    const SizedBox(height: 16),
                    // Favourites
                    if (_favourites.isNotEmpty) ...[
                      Wrap(spacing: 10, runSpacing: 10, children: _favourites.entries.map((e) => _favChip(e.key, e.value)).toList()),
                      const SizedBox(height: 18),
                    ],
                    // Active ride banner — between favourites and services (cancel etc. from here)
                    if (_activeRide != null) ...[_buildActiveRideBanner(), const SizedBox(height: 18)],
                    // Services — horizontal scroll
                    const Text('Our services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _services.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => _buildServiceItem(_services[i]),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Recent locations
                    const Text('Recent locations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._recentLocations().map((l) => _buildRecentTile(l)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Small white circular icon button used on the map overlay.
  Widget _circleIcon(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)],
          ),
          child: Icon(icon, color: Colors.black87),
        ),
      );

  Widget _homeSearchBar() => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
          ),
          child: Row(children: [
            const Icon(Icons.search, color: Colors.black87, size: 22),
            const SizedBox(width: 10),
            Text('Enter Destination', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey[800])),
          ]),
        ),
      );

  Widget _favChip(String label, String address) {
    final icon = label == 'Home' ? Icons.home_outlined : label == 'Work' ? Icons.work_outline : Icons.favorite_border;
    return GestureDetector(
      onTap: () {
        if (!_canBook()) return;
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => TaxiBookingScreen(fromLocation: 'Current Location', hideLocationInputs: false)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF3F5F9), borderRadius: BorderRadius.circular(24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
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
    return GestureDetector(
      onTap: rideId.isEmpty ? null : () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveRideScreen(rideId: rideId)));
        _checkActiveRide(); // refresh after returning (may have completed/cancelled)
      },
      child: Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1C2656), Color(0xFF1C2656)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFF1C2656).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Image.asset(svcAsset, width: 48, height: 48, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(width: 48, height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Icon(svcIcon, color: const Color(0xFF1C2656), size: 24)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$svcName · $label', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text('${r['pickupAddress'] ?? ''} → ${r['dropAddress'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: const Text('Live', style: TextStyle(color: Color(0xFF1C2656), fontWeight: FontWeight.w800, fontSize: 12))),
      ]),
      ),
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
            // Rebuild the lite map once we know the real location so it recenters
            key: ValueKey(_currentLatLng?.toString() ?? 'home-map'),
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

  // Recent locations source: admin config `places` when available, else hardcoded fallback.
  List<Map<String, String>> _recentLocations() {
    final places = _cfg?['places'];
    if (places is List && places.isNotEmpty) {
      return places.whereType<Map>().map((p) {
        return {
          'name': (p['name'] ?? '').toString(),
          'address': (p['address'] ?? '').toString(),
        };
      }).toList();
    }
    return _popularLocations;
  }

  // Recent location tile (Ola-style pin + chevron) → opens normal ride to that drop
  Widget _buildRecentTile(Map<String, String> l) {
    return InkWell(
      onTap: () {
        if (!_canBook()) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => TaxiBookingScreen(
          fromLocation: 'Current Location', hideLocationInputs: false)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.location_on_outlined, size: 20, color: AppTheme.primaryBlue)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(l['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ]),
      ),
    );
  }

  Widget _buildServiceItem(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () {
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
      },
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: s['bgColor'] as Color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: s['icon'] is String
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      s['icon'] as String,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(s['icon'] as IconData, color: s['color'] as Color, size: 32),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 72,
            child: Text(s['label'] as String, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
          ),
        ],
      ),
    );
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

  Widget _buildPromoBanner(Map<String, String> promo) {
    final color = _parseHexColor(promo['color'], AppTheme.primaryBlue);
    final imageUrl = promo['imageUrl'] ?? '';
    IconData adIcon = Icons.local_offer;
    if (promo['icon'] == 'security') adIcon = Icons.security;
    if (promo['icon'] == 'directions_car') adIcon = Icons.directions_car;
    if (promo['icon'] == 'local_shipping') adIcon = Icons.local_shipping;
    if (promo['icon'] == 'map') adIcon = Icons.map;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          imageUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(adIcon, color: color, size: 28),
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    adIcon,
                    color: color,
                    size: 28,
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  promo['title'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  promo['sub'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Learn More',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
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
