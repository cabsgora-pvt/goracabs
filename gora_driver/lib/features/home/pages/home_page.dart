import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../providers/driver_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../earnings/pages/earnings_page.dart';
import '../../account/pages/account_page.dart';
import '../../ride/pages/incoming_ride_page.dart';
import '../bloc/home_bloc.dart';
import 'map_placeholder.dart';

class HomePage extends StatefulWidget {
  static const route = '/home';
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DriverProvider>().loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeBloc()..add(LoadHomeDataEvent()),
      child: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          final homeBloc = context.read<HomeBloc>();
          return PopScope(
            // If we're not on Home tab, intercept back → switch to Home tab (index 0).
            // If we're already on Home → allow system to close app.
            canPop: _tab == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_tab != 0) {
                setState(() => _tab = 0);
              } else {
                SystemNavigator.pop();
              }
            },
            child: Scaffold(
              body: IndexedStack(index: _tab, children: [
                _HomeTab(homeBloc: homeBloc),
                const EarningsPage(),
                AccountPage(),
              ]),
              bottomNavigationBar: _BottomNav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
            ),
          );
        },
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final HomeBloc homeBloc;
  const _HomeTab({required this.homeBloc});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        final isOnline = homeBloc.isOnline;
        final summary = homeBloc.summary;
        final dp = context.watch<DriverProvider>();
        final picUrl = dp.profilePicUrl;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Row(children: [
              CircleAvatar(
                backgroundColor: Colors.white24,
                radius: 18,
                backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                child: picUrl.isEmpty
                    ? Text(dp.name.isNotEmpty ? dp.name[0].toUpperCase() : 'D',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dp.name.isNotEmpty ? dp.name : 'Driver',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            actions: [
              // Online/Offline Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: GestureDetector(
                  onTap: () => context.read<HomeBloc>().add(ToggleOnlineEvent(!isOnline)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.green : Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: isOnline ? Colors.white : Colors.white60, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(isOnline ? 'ON DUTY' : 'OFF DUTY', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.notifications_rounded, color: Colors.white), onPressed: () => Navigator.pushNamed(context, '/notifications')),
            ],
          ),
          body: Stack(children: [
            // Map placeholder
            const MapPlaceholder(),
            // Background poller for incoming ride requests (no visual change)
            if (isOnline) const _RidePoller(),
            // Stats card at top
            if (state is HomeLoaded || state is OnlineStatusChanged)
              Positioned(
                top: 16, left: 16, right: 16,
                child: _StatsCard(summary: summary),
              ),
            // Online prompt
            if (!isOnline)
              Positioned(
                bottom: 100, left: 24, right: 24,
                child: _OfflinePrompt(onGoOnline: () => context.read<HomeBloc>().add(ToggleOnlineEvent(true))),
              ),
          ]),
        );
      },
    );
  }
}

class _StatsCard extends StatefulWidget {
  final Map<String, String> summary;
  const _StatsCard({required this.summary});
  @override State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Today's Earnings", style: TextStyle(color: Colors.white70, fontSize: 13)),
            Row(children: [
              Text(widget.summary['today'] ?? '₹ 0', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
            ]),
          ]),
          if (_expanded) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _statItem('Rides', widget.summary['totalRides'] ?? '0', Icons.directions_car),
              _statItem('Distance', widget.summary['totalDistance'] ?? '0', Icons.route),
              _statItem('This Week', widget.summary['week'] ?? '₹0', Icons.calendar_today),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) => Column(children: [
    Icon(icon, color: Colors.white60, size: 16),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
  ]);
}

class _OfflinePrompt extends StatelessWidget {
  final VoidCallback onGoOnline;
  const _OfflinePrompt({required this.onGoOnline});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)]),
      child: Row(children: [
        const Icon(Icons.power_settings_new_rounded, color: AppColors.textGrey, size: 28),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You are offline', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
          Text('Go online to start receiving ride requests', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ])),
        ElevatedButton(onPressed: onGoOnline, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)), child: const Text('Go Online')),
      ]),
    );
  }
}

// Polls the backend for pending ride requests + pushes location while online.
class _RidePoller extends StatefulWidget {
  const _RidePoller();
  @override
  State<_RidePoller> createState() => _RidePollerState();
}

class _RidePollerState extends State<_RidePoller> {
  Timer? _pollTimer;
  Timer? _locTimer;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    _locTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocation());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locTimer?.cancel();
    super.dispose();
  }

  Future<void> _pushLocation() async {
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null) {
        await DriverApiService.updateLocation(pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_navigating || !mounted) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      if (rides.isEmpty) return;
      final r = Map<String, dynamic>.from(rides.first as Map);
      final fare = (r['fare'] ?? 0);
      final tip = (r['tip'] ?? 0);
      final total = (r['totalFare'] ?? (fare + tip));
      final ratingNum = r['riderRating'];
      final ratingStr = ratingNum is num && ratingNum > 0 ? ratingNum.toStringAsFixed(1) : '5.0';
      final picRaw = (r['riderProfilePicUrl'] ?? '').toString();
      final picUrl = picRaw.isEmpty ? '' : AppConfig.imageUrl(picRaw);
      final model = RideRequestModel(
        id: r['id']?.toString() ?? '',
        userName: (r['riderName'] ?? 'Rider').toString(),
        userPhone: (r['riderPhone'] ?? '').toString(),
        userRating: ratingStr,
        userProfilePicUrl: picUrl,
        pickupAddress: (r['pickupAddress'] ?? '').toString(),
        dropAddress: (r['dropAddress'] ?? '').toString(),
        distance: '${r['distance'] ?? 0} km',
        fare: '₹ $total',
        eta: '${r['duration'] ?? 4} min',
        rideType: (r['vehicleType'] ?? 'taxi').toString(),
        pickupLat: (r['pickupLat'] ?? 23.0225).toDouble(),
        pickupLng: (r['pickupLng'] ?? 72.5714).toDouble(),
        dropLat: (r['dropLat'] ?? 23.0732).toDouble(),
        dropLng: (r['dropLng'] ?? 72.6208).toDouble(),
        service: (r['service'] ?? 'taxi').toString(),
        tripType: (r['tripType'] ?? 'one_way').toString(),
        cityFrom: (r['cityFrom'] ?? '').toString(),
        cityTo: (r['cityTo'] ?? '').toString(),
      );
      if (!mounted) return;
      _navigating = true;
      await Navigator.pushNamed(context, IncomingRidePage.route, arguments: model);
      _navigating = false;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _BottomNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.tab, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: BottomNavigationBar(
        currentIndex: tab,
        onTap: onTap,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textGrey,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
    );
  }
}
