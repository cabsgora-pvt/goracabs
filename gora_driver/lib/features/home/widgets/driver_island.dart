import 'package:flutter/material.dart';
import '../../../services/driver_api_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// "5m ago", "3h ago", "2d ago" — how long since [t].
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Share of offers accepted in the server's rolling 24 h window
/// (profile `dispatchStats`), as a whole percent. Null when nothing was
/// offered yet — then there is no rate to show, not a made-up 100%.
int? acceptanceRate(Object? dispatchStats) {
  if (dispatchStats is! Map) return null;
  final offers = dispatchStats['offers'];
  final accepts = dispatchStats['accepts'];
  if (offers is! num || offers <= 0 || accepts is! num) return null;
  return (accepts / offers * 100).round().clamp(0, 100);
}

/// The driver's most recent completed trip, from GET /rides/driver/history.
class LastTrip {
  /// What the driver kept (driverEarning) when the server recorded it,
  /// otherwise the fare — [isEarning] says which.
  final num amount;
  final bool isEarning;
  final DateTime? at;
  const LastTrip({required this.amount, required this.isEarning, this.at});

  /// The newest completed ride in a history reply; null when there is none.
  static LastTrip? fromHistory(Map<String, dynamic> res) {
    for (final r in ((res['rides'] as List?) ?? const []).whereType<Map>()) {
      if (r['status'] != 'completed') continue;
      final earn = r['driverEarning'];
      final fare = r['totalFare'] ?? r['fare'];
      final isEarning = earn is num && earn > 0;
      return LastTrip(
        amount: isEarning ? earn : (fare is num ? fare : 0),
        isEarning: isEarning,
        at: DateTime.tryParse('${r['completedAt'] ?? r['createdAt'] ?? ''}')?.toLocal(),
      );
    }
    return null;
  }
}

/// One pill in the island's stat row.
class IslandStat {
  final String id, label, value, sub;
  final IconData icon;
  final Color tint;
  const IslandStat(this.id, this.label, this.value, this.sub, this.icon, this.tint);
}

String _rupees(num v) => '₹${v.round()}';

/// The island's stats, all from what the app already reads: the earnings
/// summary, the newest history row, the wallet and the profile. A figure not
/// known yet reads "…", one that does not exist reads "—"; none is invented.
List<IslandStat> islandStats({
  required Map<String, String> summary,
  LastTrip? lastTrip,
  bool lastTripLoading = false,
  double? walletBalance,
  Object? dispatchStats,
  String rating = '',
  DateTime? now,
}) {
  final todayTrips = summary['todayRides'];
  final rate = acceptanceRate(dispatchStats);
  final r = double.tryParse(rating) ?? 0;
  return [
    IslandStat('today', 'Today', summary['today']?.replaceAll(' ', '') ?? '…',
        todayTrips == null ? 'earned' : '$todayTrips trip${todayTrips == '1' ? '' : 's'}',
        Icons.today_rounded, const Color(0xFF34C759)),
    IslandStat('last', 'Last trip',
        lastTripLoading ? '…' : (lastTrip == null ? '—' : _rupees(lastTrip.amount)),
        lastTripLoading
            ? 'loading'
            : lastTrip == null
                ? 'No trips yet'
                : (lastTrip.at != null ? timeAgo(lastTrip.at!, now: now) : (lastTrip.isEarning ? 'earned' : 'fare')),
        Icons.history_rounded, const Color(0xFF64D2FF)),
    IslandStat('week', 'This week', summary['week'] ?? '…', 'last 7 days',
        Icons.date_range_rounded, const Color(0xFFBF5AF2)),
    IslandStat('wallet', 'Wallet', walletBalance == null ? '…' : '₹${walletBalance.toStringAsFixed(0)}',
        walletBalance == null ? 'loading' : (walletBalance <= 0 ? 'top up' : 'balance'),
        Icons.account_balance_wallet_rounded,
        walletBalance != null && walletBalance <= 0 ? const Color(0xFFFF453A) : const Color(0xFFFFD60A)),
    if (rate != null)
      IslandStat('accept', 'Acceptance', '$rate%', 'last 24 h', Icons.task_alt_rounded, const Color(0xFF30D158))
    else
      IslandStat('rating', 'Rating', r > 0 ? r.toStringAsFixed(1) : '—', r > 0 ? 'from riders' : 'no ratings yet',
          Icons.star_rounded, const Color(0xFFFF9F0A)),
  ];
}

/// The black capsule at the top of the home map, iPhone Dynamic Island style:
/// "₹356 Today" collapsed; tapped, it grows into a rounded island with today's
/// earning, a scrollable row of real stats and a Top up action.
class DriverIsland extends StatefulWidget {
  final Map<String, String> summary;
  final bool loaded;
  final bool open;
  final VoidCallback? onToggle;
  final VoidCallback onTopUp;
  final VoidCallback onSeeEarnings;
  final double? walletBalance;
  final Object? dispatchStats;
  final String rating;
  /// Width the island grows to when open.
  final double fullWidth;
  /// Width of the collapsed capsule.
  final double collapsedWidth;
  const DriverIsland({
    super.key,
    required this.summary,
    required this.loaded,
    required this.open,
    required this.onToggle,
    required this.onTopUp,
    required this.onSeeEarnings,
    required this.fullWidth,
    this.collapsedWidth = 168,
    this.walletBalance,
    this.dispatchStats,
    this.rating = '',
  });

  @override
  State<DriverIsland> createState() => _DriverIslandState();
}

class _DriverIslandState extends State<DriverIsland> {
  LastTrip? _last;
  bool _lastLoading = false;
  bool _lastTried = false;

  @override
  void initState() {
    super.initState();
    // The island can be built already open (a new element when it expands):
    // load then too, or "Last trip" would sit on "loading" for good.
    if (widget.open) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadLastTrip(); });
  }

  @override
  void didUpdateWidget(covariant DriverIsland old) {
    super.didUpdateWidget(old);
    // Fresh each time it opens: a trip finished since the last look shows.
    if (widget.open && !old.open) _loadLastTrip();
  }

  Future<void> _loadLastTrip() async {
    if (_lastLoading) return;
    setState(() => _lastLoading = !_lastTried);
    try {
      final res = await DriverApiService.getTripHistory(page: 1, limit: 5);
      if (!mounted) return;
      if (res['error'] == null) _last = LastTrip.fromHistory(res);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _lastLoading = false;
      _lastTried = true;
    });
  }

  static const _curve = Curves.easeOutCubic;
  static const _dur = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    final w = open ? widget.fullWidth : widget.collapsedWidth.clamp(0.0, widget.fullWidth);
    return Semantics(
      button: true,
      label: open ? 'Close today\'s stats' : 'Today\'s earnings, open stats',
      child: AnimatedContainer(
        key: const ValueKey('driver_island'),
        duration: _dur,
        curve: _curve,
        width: w,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(open ? 30 : 26),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: open ? 0.35 : 0.22),
                blurRadius: open ? 26 : 10, offset: Offset(0, open ? 10 : 3)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // The content is laid out at its final width and clipped while the
        // capsule grows or shrinks around it, so nothing reflows mid-animation.
        child: AnimatedSize(
          duration: _dur,
          curve: _curve,
          alignment: Alignment.topCenter,
          child: ConstraintsTransformBox(
            constraintsTransform: ConstraintsTransformBox.widthUnconstrained,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            // Each face keeps its own width while the other fades out, so the
            // open layout is never squeezed into the capsule (or vice versa).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, clipBehavior: Clip.hardEdge, children: [
                ...prev,
                if (cur != null) cur,
              ]),
              child: open
                  ? SizedBox(key: const ValueKey('face_open'), width: widget.fullWidth, child: _expanded())
                  : SizedBox(key: const ValueKey('face_closed'), width: widget.collapsedWidth.clamp(0.0, widget.fullWidth),
                      child: _collapsed()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsed() => InkWell(
    key: const ValueKey('island_collapsed'),
    onTap: widget.onToggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(widget.loaded ? (widget.summary['today'] ?? '₹ 0') : '…', maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900,
                      letterSpacing: -0.3)),
            ),
            const Text('Today', style: TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
          ]),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
      ]),
    ),
  );

  Widget _expanded() {
    final stats = islandStats(
      summary: widget.summary,
      lastTrip: _last,
      lastTripLoading: _lastLoading || !_lastTried,
      walletBalance: widget.walletBalance,
      dispatchStats: widget.dispatchStats,
      rating: widget.rating,
    );
    final trips = widget.summary['todayRides'];
    return Padding(
      key: const ValueKey('island_expanded'),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TODAY\'S EARNINGS',
                    style: TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text((widget.summary['today'] ?? '₹ 0').replaceAll(' ', ''), maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900,
                          letterSpacing: -1, height: 1.1)),
                ),
                Text(
                  [
                    if (trips != null) '$trips trip${trips == '1' ? '' : 's'}',
                    if (widget.summary['totalDistance'] != null) widget.summary['totalDistance']!,
                  ].join('  ·  '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.white,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const ValueKey('island_top_up'),
                customBorder: const StadiumBorder(),
                onTap: widget.onTopUp,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 18, color: Colors.black),
                    SizedBox(width: 4),
                    Text('Top up', maxLines: 1, style: TextStyle(color: Colors.black, fontSize: 13.5, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 82,
          child: ListView.separated(
            key: const ValueKey('island_stats'),
            scrollDirection: Axis.horizontal,
            itemCount: stats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _pill(stats[i]),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Flexible(
            child: TextButton.icon(
              onPressed: widget.onSeeEarnings,
              style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: const EdgeInsets.symmetric(horizontal: 6)),
              icon: const Icon(Icons.insights_rounded, size: 18),
              label: const Text('See earnings', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onToggle,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70),
          ),
        ]),
      ]),
    );
  }

  Widget _pill(IslandStat s) => Container(
    key: ValueKey('island_stat_${s.id}'),
    width: 116,
    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Row(children: [
        Icon(s.icon, size: 14, color: s.tint),
        const SizedBox(width: 5),
        Expanded(
          child: Text(s.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w800,
                  letterSpacing: 1.1)),
        ),
      ]),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(s.value, maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
      ),
      Text(s.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: s.tint.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );
}

/// Red low-balance / top-up banner on the home map: red gradient, white icon
/// and text, a white "Top up" pill.
class TopUpBanner extends StatelessWidget {
  final bool negative;
  final VoidCallback onTap;
  final VoidCallback onTopUp;
  const TopUpBanner({super.key, required this.negative, required this.onTap, required this.onTopUp});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('top_up_banner'),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
      ),
      borderRadius: BorderRadius.circular(Cap.radius + 2),
      boxShadow: [BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(Cap.radius + 2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(negative ? 'Cash rides paused' : 'Low wallet balance',
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(negative
                        ? 'Wallet negative — cash rides are paused. Recharge to get cash rides again; '
                            'online and wallet rides still come.'
                        : 'Your wallet balance is low. Please recharge to continue',
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.white,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const ValueKey('banner_top_up'),
                customBorder: const StadiumBorder(),
                onTap: onTopUp,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text('Top up', style: TextStyle(color: Color(0xFFB71C1C), fontSize: 13, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
