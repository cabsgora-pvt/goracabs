import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
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
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeBloc()..add(LoadHomeDataEvent()),
      child: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          final homeBloc = context.read<HomeBloc>();
          return Scaffold(
            body: IndexedStack(index: _tab, children: [
              _HomeTab(homeBloc: homeBloc),
              const EarningsPage(),
              AccountPage(),
            ]),
            bottomNavigationBar: _BottomNav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
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
        final driver = homeBloc.driver;
        final summary = homeBloc.summary;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            elevation: 0,
            title: Row(children: [
              CircleAvatar(backgroundColor: Colors.white24, radius: 18, child: const Icon(Icons.person, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(driver?.name ?? 'Driver', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(driver?.vehicleNumber ?? '', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8))),
              ]),
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
            // Simulate ride button (for demo)
            if (isOnline)
              Positioned(
                bottom: 100, left: 24, right: 24,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Simulate Incoming Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pushNamed(context, IncomingRidePage.route),
                ),
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
