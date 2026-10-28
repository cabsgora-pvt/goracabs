import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../earnings/pages/earnings_page.dart';
import '../../account/pages/account_page.dart';
import '../../ride/pages/incoming_requests_page.dart';
import '../../ride/logic/dismissed_requests.dart';
import '../../ride/pages/on_ride_page.dart';
import '../../ride/pages/rental_progress_page.dart';
import '../../ride/pages/hire_progress_page.dart';
import '../../ride/pages/delivery_progress_page.dart';
import '../../ride/widgets/ride_shell.dart';
import '../../../models/models.dart';
import '../../wallet/pages/wallet_page.dart';
import '../../account/service_prefs.dart';
import '../../account/pages/face_reverify_page.dart';
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

  void _openTab(int i) {
    setState(() => _tab = i);
    // Account tab shows rating / rides / wallet balance from the
    // provider, which was only loaded once at startup — refresh it
    // so a rating received this session (or a wallet change) shows.
    if (i == 2) context.read<DriverProvider>().loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeBloc()..add(LoadHomeDataEvent()),
      child: BlocConsumer<HomeBloc, HomeState>(
        listener: (context, state) {
          if (state is FaceVerificationLockedState) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => FaceReverifyPage(reason: state.reason)));
          }
        },
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
                _HomeTab(homeBloc: homeBloc, onOpenTab: _openTab),
                const EarningsPage(),
                AccountPage(),
              ]),
              bottomNavigationBar: _BottomNav(tab: _tab, onTap: _openTab),
            ),
          );
        },
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final HomeBloc homeBloc;
  final ValueChanged<int> onOpenTab;
  const _HomeTab({required this.homeBloc, required this.onOpenTab});
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  bool _statsOpen = false;

  void _toggleOnline(bool online) => context.read<HomeBloc>().add(ToggleOnlineEvent(online));

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        final isOnline = widget.homeBloc.isOnline;
        final summary = widget.homeBloc.summary;
        final loaded = state is HomeLoaded || state is OnlineStatusChanged;
        final dp = context.watch<DriverProvider>();
        final safeTop = MediaQuery.of(context).padding.top;

        return Scaffold(
          // StackFit.expand: every visible child here is Positioned, and the
          // only unpositioned one (the online-only poller) is zero-sized. With
          // the default loose fit the Stack sized itself to that 0x0 child the
          // moment the driver went online, collapsing the map and both panels
          // to nothing — a blank home screen.
          body: Stack(fit: StackFit.expand, children: [
            // Full-bleed live map
            Positioned.fill(child: MapPlaceholder(padding: EdgeInsets.only(top: safeTop + 70, bottom: 230))),
            // Background poller for incoming ride requests (no visual change)
            if (isOnline) const _RidePoller(),
            // Top bar: avatar · today's earnings · notifications
            Positioned(
              top: safeTop + 10, left: 14, right: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  _AvatarButton(name: dp.name, url: dp.profilePicUrl, onTap: () => widget.onOpenTab(2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Center(
                      child: _EarningsPill(
                        amount: loaded ? (summary['today'] ?? '₹ 0') : '…',
                        open: _statsOpen,
                        onTap: loaded ? () => setState(() => _statsOpen = !_statsOpen) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  MapCircleButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    onTap: () => Navigator.pushNamed(context, '/notifications'),
                  ),
                ]),
                if (_statsOpen && loaded) ...[
                  const SizedBox(height: 10),
                  _TodayStats(summary: summary, onMore: () => widget.onOpenTab(1)),
                ],
                if (dp.isLowBalance) ...[
                  const SizedBox(height: 10),
                  _LowBalanceBanner(
                    onTap: () => Navigator.pushNamed(context, WalletPage.route),
                  ),
                ],
              ]),
            ),
            // Bottom: resume banner · GO button · status sheet
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Resume an in-progress ride (auto on reopen + tappable banner)
                const _ActiveRideResumer(),
                if (!isOnline) ...[
                  Center(child: _GoButton(onTap: () => _toggleOnline(true))),
                  const SizedBox(height: 14),
                ],
                _StatusSheet(
                  online: isOnline,
                  onGoOffline: () => _toggleOnline(false),
                  onPrefs: () => showServicePrefsTopSheet(context),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Driver photo (or initial) in a white circle — opens the Account tab.
class _AvatarButton extends StatelessWidget {
  final String name, url;
  final VoidCallback onTap;
  const _AvatarButton({required this.name, required this.url, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Account',
    child: Material(
      color: Cap.surface,
      elevation: 3,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: CapAvatar(name: name.isNotEmpty ? name : 'D', url: url, radius: 20),
        ),
      ),
    ),
  );
}

/// "₹ 1,240 · Today" pill centred in the top bar.
class _EarningsPill extends StatelessWidget {
  final String amount;
  final bool open;
  final VoidCallback? onTap;
  const _EarningsPill({required this.amount, required this.open, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF111111),
    elevation: 3,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(26),
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(amount, maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              const Text('Today', style: TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 4),
          Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
        ]),
      ),
    ),
  );
}

/// Today's real summary, dropped down from the earnings pill.
class _TodayStats extends StatelessWidget {
  final Map<String, String> summary;
  final VoidCallback onMore;
  const _TodayStats({required this.summary, required this.onMore});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
      child: Column(children: [
        FittedBox(fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: Cap.body(size: 15.5, weight: FontWeight.w900))),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 11.5)),
      ]),
    );
    return Material(
      color: Cap.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Cap.radius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            stat('Trips', summary['totalRides'] ?? '0'),
            Container(width: 1, height: 30, color: Cap.divider),
            stat('Distance', summary['totalDistance'] ?? '0 km'),
            Container(width: 1, height: 30, color: Cap.divider),
            stat('This week', summary['week'] ?? '₹0'),
          ]),
          TextButton(onPressed: onMore, child: const Text('See earnings')),
        ]),
      ),
    );
  }
}

/// Big round "GO" button — the one thing to do while offline.
class _GoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Go online',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Cap.navy.withValues(alpha: 0.18),
      ),
      child: Material(
        color: Cap.navy,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Cap.navy.withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 82, height: 82,
            child: Center(
              child: Text('GO', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// White bottom sheet: online/offline state + trip preferences.
class _StatusSheet extends StatelessWidget {
  final bool online;
  final VoidCallback onGoOffline;
  final VoidCallback onPrefs;
  const _StatusSheet({required this.online, required this.onGoOffline, required this.onPrefs});

  @override
  Widget build(BuildContext context) {
    final dot = online ? Cap.green : Cap.muted;
    return Container(
      decoration: BoxDecoration(
        color: Cap.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CapSheetHandle(),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: dot, shape: BoxShape.circle,
              boxShadow: online ? [BoxShadow(color: Cap.green.withValues(alpha: 0.45), blurRadius: 8, spreadRadius: 2)] : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(online ? "You're online" : "You're offline",
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.title(size: 19)),
              const SizedBox(height: 2),
              Text(online ? 'Finding trips near you' : 'Tap GO to start receiving trip requests',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 13)),
            ]),
          ),
          if (online) ...[
            const SizedBox(width: 10),
            Material(
              color: Cap.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onGoOffline,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.power_settings_new_rounded, size: 17, color: Cap.red),
                    const SizedBox(width: 6),
                    Text('Go offline', style: Cap.body(size: 13, weight: FontWeight.w800, color: Cap.red)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
        if (online) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(minHeight: 3, color: Cap.accent, backgroundColor: Cap.tile),
          ),
        ],
        const SizedBox(height: 14),
        CapTile(
          onTap: onPrefs,
          child: Row(children: [
            Icon(Icons.tune_rounded, size: 20, color: Cap.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trip preferences', style: Cap.body(size: 14, weight: FontWeight.w800)),
                Text('Rental, outstation, hire & parcel',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: Cap.muted),
          ]),
        ),
      ]),
    );
  }
}

// Checks for the driver's in-progress ride: auto-opens it once on app launch,
// and shows a tappable "resume" banner while one is active.
class _ActiveRideResumer extends StatefulWidget {
  const _ActiveRideResumer();
  @override
  State<_ActiveRideResumer> createState() => _ActiveRideResumerState();
}

class _ActiveRideResumerState extends State<_ActiveRideResumer> {
  static bool _autoResumed = false; // once per app launch
  Map<String, dynamic>? _ride;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _check();
    _t = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _check() async {
    try {
      final res = await DriverApiService.getActiveRide();
      final ride = res['ride'];
      if (!mounted) return;
      setState(() => _ride = ride == null ? null : Map<String, dynamic>.from(ride as Map));
      if (_ride != null && !_autoResumed) { _autoResumed = true; _resume(); }
    } catch (_) {}
  }

  void _resume() {
    final ride = _ride;
    if (ride == null || !mounted) return;
    final m = RideRequestModel.fromJson(Map<String, dynamic>.from(ride));
    final status = (ride['status'] ?? '').toString();
    if (status == 'ongoing' && m.service == 'rental') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => RentalProgressPage(ride: m)));
    } else if (status == 'ongoing' && m.service == 'hire_driver') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => HireProgressPage(ride: m)));
    } else if (status == 'ongoing' && m.service == 'delivery') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryProgressPage(ride: m)));
    } else {
      Navigator.pushNamed(context, OnRidePage.route, arguments: m);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ride == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: Cap.navy,
        elevation: 4,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(Cap.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Cap.radius),
          onTap: _resume,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.navigation_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Ride in progress — tap to resume',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}

// Red alert shown on the home map when the driver's wallet balance is 0 or
// negative. Tapping it opens the wallet so the driver can recharge.
class _LowBalanceBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _LowBalanceBanner({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Cap.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Cap.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Cap.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: Cap.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.account_balance_wallet_rounded, color: Cap.red, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Low wallet balance', style: Cap.body(size: 14, weight: FontWeight.w800)),
                Text('Your wallet balance is low. Please recharge to continue',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
              ]),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Cap.red, size: 22),
          ]),
        ),
      ),
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
    // Not over a trip in progress. The pending feed does not leave out drivers
    // already on a job, and opt-in services (rental, hire, outstation, parcel)
    // stay listed for 15 minutes — so right after accepting one, the request
    // page kept opening over the trip screen the driver had just reached.
    if (RideShell.tripOpen) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      // Requests whose countdown just ran out on this phone are skipped, or a
      // lapsed offer still in the feed would reopen the screen in a loop.
      final rides = ((res['rides'] as List?) ?? [])
          .where((r) => r is Map && !DismissedRequests.isSuppressedJson(r))
          .toList();
      if (rides.isEmpty) return;
      // Open the multi-request screen (shows up to 5 pending requests at once).
      if (!mounted) return;
      _navigating = true;
      await Navigator.pushNamed(context, IncomingRequestsPage.route);
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
        color: Cap.surface,
        border: Border(top: BorderSide(color: Cap.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: tab,
        onTap: onTap,
        selectedItemColor: Cap.ink,
        unselectedItemColor: Cap.muted,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
    );
  }
}
