import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
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

  final List<Map<String, dynamic>> _services = [
    {'icon': 'assets/images/bike-bluebg.png', 'label': 'Bike ride', 'color': Color(0xFF2196F3), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/auto-bluebg.png', 'label': 'Auto ride', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
    {'icon': 'assets/images/texi2-bluebg.png', 'label': 'Cab ride', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/rental-bluebg.png', 'label': 'Rentals', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/out-station-bluebg.png', 'label': 'Outstation', 'color': Color(0xFF2196F3), 'bgColor': Color(0xFFE3F2FD)},
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
  }

  void _startPromoTimer() {
    _promoTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPromoPage < _promos.length - 1) {
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
    _promoController.dispose();
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
        return const ServiceSelectionScreen();
      case 2:
        return const RideHistoryScreen();
      case 3:
        return _buildProfilePage();
      default:
        return _buildHomePage();
    }
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'Services',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            activeIcon: Icon(Icons.history),
            label: 'Trip Details',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final user = context.watch<UserProvider>();
    final picUrl = user.profilePicUrl;
    final displayName = user.name.isNotEmpty ? user.name : (user.phone.isNotEmpty ? user.phone : 'Guest');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryBlue,
                    backgroundImage: picUrl.isNotEmpty
                        ? NetworkImage(AppConfig.imageUrl(picUrl))
                        : null,
                    child: picUrl.isEmpty
                        ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hello,', style: TextStyle(fontSize: 13, color: AppTheme.textGrey)),
                        const SizedBox(height: 2),
                        Text(displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_outlined, size: 26),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: TextField(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaxiBookingScreen(
                          fromLocation: 'Current Location',
                          hideLocationInputs: false,
                        ),
                      ),
                    );
                  },
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Where are you going?',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue, size: 22),
                    suffixIcon: IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaxiBookingScreen(
                              fromLocation: 'Current Location',
                              hideLocationInputs: false,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward, color: AppTheme.primaryBlue, size: 22),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    
                    const Text('Popular Places', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _popularLocations.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _buildPopularCard(_popularLocations[i]),
                      ),
                    ),
                    
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Our Services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: () => setState(() => _currentIndex = 1),
                          child: const Text('View All', style: TextStyle(fontSize: 14, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _services.take(4).map((s) => _buildServiceItem(s)).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _services.skip(4).take(4).map((s) => _buildServiceItem(s)).toList(),
                    ),

                    const SizedBox(height: 24),

                    const Text('Featured Ads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: PageView.builder(
                        controller: _promoController,
                        itemCount: _promos.length,
                        onPageChanged: (int page) {
                          setState(() {
                            _currentPromoPage = page;
                          });
                        },
                        itemBuilder: (_, i) => _buildPromoBanner(_promos[i]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Why Choose Us Section
                    const Text('Why Choose Gora Cabs?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 20),
                    
                    // Footer section
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.grey[100]!,
                            Colors.grey[200]!,
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Background pattern
                          Positioned.fill(
                            child: CustomPaint(
                              painter: RajasthaniPatternPainter(),
                            ),
                          ),
                          // Content
                          Column(
                            children: [
                              Text(
                                'Gora Cabs',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.favorite, color: Colors.red[500], size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Made in India',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.location_on, color: Colors.orange[500], size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Crafted in Rajasthan',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildServiceItem(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () {
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
          Text(s['label'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildPromoBanner(Map<String, String> promo) {
    final color = Color(int.parse(promo['color']!));
    IconData adIcon = Icons.local_offer;
    if (promo['icon'] == 'security') adIcon = Icons.security;
    if (promo['icon'] == 'directions_car') adIcon = Icons.directions_car;
    if (promo['icon'] == 'local_shipping') adIcon = Icons.local_shipping;
    if (promo['icon'] == 'map') adIcon = Icons.map;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Container(
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
                  promo['title']!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  promo['sub']!,
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

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    Text(displayName, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 22)),
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
                        backgroundColor: Colors.white,
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
        color: Colors.white,
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
        title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color ?? Colors.black87)),
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
