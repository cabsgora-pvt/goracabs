import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../../services/ride_alert_service.dart';
import '../../../services/device_channel.dart';
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
import '../../wallet/widgets/add_balance_sheet.dart';
import '../widgets/driver_island.dart';
import '../../account/pages/face_reverify_page.dart';
import '../../../services/location_ping.dart';
import '../bloc/home_bloc.dart';
import '../logic/feed_status.dart';
import 'background_location_disclosure.dart';
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
          } else if (state is AccountHoldState) {
            // Refresh so the red hold banner shows on the map too.
            context.read<DriverProvider>().loadProfile();
            showAccountHoldDialog(context, state.message);
          } else if (state is GoOnlineFailedState) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              key: const ValueKey('go_online_failed'),
              content: Text(state.message),
              backgroundColor: Cap.red,
              duration: const Duration(seconds: 6),
            ));
          } else if (state is OnlineStatusChanged && state.zoneChangedTo != null) {
            context.read<DriverProvider>().loadProfile();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Your zone changed to ${state.zoneChangedTo}')),
            );
          }
          // Online for the first time on this phone: ask (once, with the
          // reason) to be left out of battery optimisation, so the online
          // service keeps alerting requests with the screen off.
          if (state is OnlineStatusChanged && state.isOnline) {
            unawaited(BatteryOptimisation.askOnce(context));
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

  Future<void> _toggleOnline(bool online) async {
    final bloc = context.read<HomeBloc>();
    // Before going online: explain why location is used in the background and
    // only then show Android's "Allow all the time" prompt (Play policy).
    if (online) await maybeAskBackgroundLocation(context);
    if (!online) feedBlock.value = null;
    bloc.add(ToggleOnlineEvent(online));
  }

  /// The wallet's own top-up flow (Razorpay sheet), straight from home.
  Future<void> _topUp(BuildContext context) async {
    setState(() => _statsOpen = false);
    final dp = context.read<DriverProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final newBalance = await showAddBalanceSheet(context, phone: dp.phone);
    if (newBalance == null || !mounted) return;
    await dp.loadProfile();
    messenger.showSnackBar(SnackBar(
      content: Text('Money added. Wallet balance ₹${newBalance.toStringAsFixed(2)}'),
      backgroundColor: Cap.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        final isOnline = widget.homeBloc.isOnline;
        final summary = widget.homeBloc.summary;
        // Anything after the first load (a refusal state included) keeps the stats.
        final loaded = state is! HomeInitial && state is! HomeLoading;
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
                  onPrefs: () => Navigator.pushNamed(context, '/preferences'),
                ),
              ]),
            ),
            // Tap outside the open island closes it.
            if (_statsOpen)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('island_barrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _statsOpen = false),
                  child: const ColoredBox(color: Color(0x33000000)),
                ),
              ),
            // Top bar: avatar · today's earnings island · notifications
            Positioned(
              top: safeTop + 10, left: 14, right: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LayoutBuilder(builder: (context, box) {
                  final full = box.maxWidth;
                  return Stack(alignment: Alignment.topCenter, children: [
                    Row(children: [
                      _AvatarButton(name: dp.name, url: dp.profilePicUrl, onTap: () => widget.onOpenTab(2)),
                      const Spacer(),
                      MapCircleButton(
                        icon: Icons.notifications_none_rounded,
                        tooltip: 'Notifications',
                        onTap: () => Navigator.pushNamed(context, '/notifications'),
                      ),
                    ]),
                    DriverIsland(
                      summary: summary,
                      loaded: loaded,
                      open: _statsOpen && loaded,
                      fullWidth: full,
                      // Leaves room for the avatar and the bell either side.
                      collapsedWidth: (full - 2 * 62).clamp(96.0, 190.0),
                      onToggle: loaded ? () => setState(() => _statsOpen = !_statsOpen) : null,
                      onTopUp: () => _topUp(context),
                      onSeeEarnings: () {
                        setState(() => _statsOpen = false);
                        widget.onOpenTab(1);
                      },
                      walletBalance: dp.balanceLoaded ? dp.walletBalance : null,
                      dispatchStats: dp.data?['dispatchStats'],
                      rating: dp.rating,
                    ),
                  ]);
                }),
                if (dp.hold != null) ...[
                  const SizedBox(height: 10),
                  _HoldBanner(
                    message: dp.holdMessage,
                    onTap: () => dp.hold?['kind'] == 'face'
                        ? Navigator.push(context, MaterialPageRoute(builder: (_) => FaceReverifyPage(
                            reason: (dp.data?['faceVerificationReason'] ?? 'mismatch').toString())))
                        : Navigator.pushNamed(context, '/admin-chat'),
                  ),
                ],
                if (isOnline)
                  ValueListenableBuilder<FeedBlock?>(
                    valueListenable: feedBlock,
                    builder: (context, block, _) => block == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: FeedBlockBanner(block: block),
                          ),
                  ),
                if (dp.isLowBalance) ...[
                  const SizedBox(height: 10),
                  TopUpBanner(
                    negative: dp.isWalletNegative,
                    onTap: () => Navigator.pushNamed(context, WalletPage.route),
                    onTopUp: () => _topUp(context),
                  ),
                ],
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
        color: Cap.orange.withValues(alpha: 0.22),
      ),
      // The logo's orange: the one thing to press while offline, as Rapido
      // Captain does with its own brand colour.
      child: Material(
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Cap.orange.withValues(alpha: 0.55),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFFF8A1F), Color(0xFFEA5E00)],
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 82, height: 82,
              child: Center(
                child: Text('GO', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
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
            child: LinearProgressIndicator(minHeight: 3, color: Cap.orange, backgroundColor: Cap.tile),
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
      // An advance booking accepted for later (more than an hour away) is not
      // opened by itself: the driver is free to take other trips until then.
      if (_ride != null && !_autoResumed && !_upcoming) { _autoResumed = true; _resume(); }
    } catch (_) {}
  }

  RideRequestModel? get _model => _ride == null ? null : RideRequestModel.fromJson(Map<String, dynamic>.from(_ride!));

  /// Accepted, and not due within the hour.
  bool get _upcoming {
    final ride = _ride;
    if (ride == null || (ride['status'] ?? '') != 'accepted') return false;
    return isUpcomingTrip(_model?.dueAt);
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(_upcoming ? Icons.event_rounded : Icons.navigation_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(
                  _upcoming
                      ? 'Upcoming trip · ${scheduledLabel(_model!.dueAt!).replaceFirst('Scheduled for ', '')}'
                      : 'Ride in progress — tap to resume',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Dialog shown when going online is refused because the account is on hold.
Future<void> showAccountHoldDialog(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block_rounded, color: Cap.red, size: 30),
        title: const Text('Account on hold'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/admin-chat');
            },
            child: const Text('Contact support'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );

// Red banner on the home map while the account is on hold (profile `hold`).
// You cannot go online until the admin releases it.
class _HoldBanner extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  const _HoldBanner({required this.message, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Cap.red,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(Cap.radius),
    child: InkWell(
      borderRadius: BorderRadius.circular(Cap.radius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(children: [
          const Icon(Icons.block_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Account on hold',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              Text(message, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
        ]),
      ),
    ),
  );
}

/// The wait before the next request-feed poll after [failures] failed ones in
/// a row: 4 s normally, doubling on each failure up to 30 s, so a server or
/// network outage is not hammered every 4 s by every online phone.
Duration feedPollDelay(int failures) {
  if (failures <= 0) return const Duration(seconds: 4);
  final s = 4 * (1 << failures.clamp(0, 4));
  return Duration(seconds: s > 30 ? 30 : s);
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
  int _failures = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _schedulePoll();
    _locTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocation());
  }

  void _schedulePoll() {
    if (_disposed) return;
    _pollTimer = Timer(feedPollDelay(_failures), () async {
      await _poll();
      _schedulePoll();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _locTimer?.cancel();
    feedBlock.value = null;
    super.dispose();
  }

  /// In the background the online service sends the position instead.
  static bool get _inBackground {
    final st = WidgetsBinding.instance.lifecycleState;
    return st == AppLifecycleState.paused || st == AppLifecycleState.hidden || st == AppLifecycleState.detached;
  }

  Future<void> _pushLocation() async {
    if (_inBackground) return;
    try {
      // The home map already streams the position: its last fix is reused,
      // and a new GPS fix is only taken when nothing recent is at hand.
      // pushFreshLocation still refuses a stale one.
      await pushFreshLocation(await LocationService.fixForPing());
    } catch (_) {}
  }

  DateTime? _lastReonline;

  /// The server has this driver offline while the app says online (it timed
  /// them out). Put them back, at most once a minute.
  Future<void> _reonline() async {
    final now = DateTime.now();
    if (_lastReonline != null && now.difference(_lastReonline!) < const Duration(minutes: 1)) return;
    _lastReonline = now;
    try {
      final pos = await LocationService.getCurrentLocation();
      final fresh = isFreshFix(pos);
      await DriverApiService.setOnline(true, fresh ? pos!.latitude : null, fresh ? pos!.longitude : null);
    } catch (_) {}
  }

  Future<void> _poll() async {
    // The app is in front: the background service's own poll can rest.
    RideAlertService.foregroundHeartbeat();
    if (_navigating || !mounted) return;
    // Minimised: the online service's background poll takes over (it only
    // polls while this screen's heartbeats have stopped).
    if (_inBackground) return;
    // Not over a trip in progress. The pending feed does not leave out drivers
    // already on a job, and opt-in services (rental, hire, outstation, parcel)
    // stay listed for 15 minutes — so right after accepting one, the request
    // page kept opening over the trip screen the driver had just reached.
    if (RideShell.tripOpen) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      if (!mounted) return;
      // A refusal or outage backs the next poll off (feedPollDelay).
      _failures = res['error'] == null ? 0 : _failures + 1;
      if (res['error'] == null) {
        // An empty feed with a reason (not approved, wallet blocked …) shows
        // that reason instead of nothing.
        final block = feedBlockFrom(res);
        if (feedBlock.value != block) feedBlock.value = block;
        if (block?.kind == 'offline') unawaited(_reonline());
      }
      // Requests whose countdown just ran out on this phone are skipped, or a
      // lapsed offer still in the feed would reopen the screen in a loop.
      final rides = ((res['rides'] as List?) ?? [])
          .where((r) => r is Map && !DismissedRequests.isSuppressedJson(r))
          .toList();
      if (rides.isEmpty) return;
      // Open the multi-request screen (shows up to 5 pending requests at once).
      if (!mounted) return;
      _navigating = true;
      // Not awaited: polling (and with it the foreground heartbeat that keeps
      // the background service quiet) carries on while the page is open.
      unawaited(Navigator.pushNamed(context, IncomingRequestsPage.route)
          .whenComplete(() => _navigating = false));
    } catch (_) {
      _failures++;
    }
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

/// Why no requests are coming, shown on the home map while online.
class FeedBlockBanner extends StatelessWidget {
  final FeedBlock block;
  const FeedBlockBanner({super.key, required this.block});
  @override
  Widget build(BuildContext context) => Material(
    color: Cap.surface,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(Cap.radius),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(children: [
        Icon(block.kind == 'busy' ? Icons.directions_car_rounded : Icons.info_outline_rounded,
            color: Cap.orange, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(block.title, style: Cap.body(size: 14, weight: FontWeight.w800)),
            Text(block.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
          ]),
        ),
      ]),
    ),
  );
}
