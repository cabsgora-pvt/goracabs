import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/earnings_bloc.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

// Earnings screen with a Today / Week / Month segment.
// Weekly shows a horizontal day scroller (last 7 days); Monthly a horizontal
// month scroller (current year). The full breakdown list is shown inline on the
// page itself — no bottom sheet.
class EarningsPage extends StatefulWidget {
  static const route = '/earnings';
  const EarningsPage({super.key});
  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  int _tab = 0;                              // 0 Today, 1 Weekly, 2 Monthly
  int _weekSel = 6;                          // default to the last day (today)
  int _monthSel = DateTime.now().month - 1;  // default to the current month

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => EarningsBloc()..add(LoadEarningsEvent()),
      child: Scaffold(
        appBar: blueAppBar('Earnings'),
        backgroundColor: Cap.surface,
        body: BlocBuilder<EarningsBloc, EarningsState>(
          builder: (context, state) {
            if (state is! EarningsLoaded) return const AppLoader();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: CapSegmented(
                  labels: const ['Today', 'Week', 'Month'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(child: _content(state)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _content(EarningsLoaded s) {
    switch (_tab) {
      case 1:
        return _periodView(s.weekly, _weekSel, (i) => setState(() => _weekSel = i), 'Last 7 days');
      case 2:
        return _periodView(s.monthly, _monthSel, (i) => setState(() => _monthSel = i), 'Year ${DateTime.now().year}');
      default:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(children: [
            _heroCard("Today's earnings", s.today),
            const SizedBox(height: 12),
            _statGrid(s.today),
          ]),
        );
    }
  }

  Widget _periodView(List<PeriodStat> items, int sel, ValueChanged<int> onSel, String listTitle) {
    final i = sel.clamp(0, items.length - 1);
    final selected = items[i];
    return Column(children: [
      // Horizontal date/month scroller
      SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, idx) => _chip(items[idx], idx == i, () => onSel(idx)),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(children: [
            _heroCard('${selected.label} ${selected.sub}', selected),
            const SizedBox(height: 12),
            _statGrid(selected),
            const SizedBox(height: 8),
            _listSection(listTitle, items, i),
          ]),
        ),
      ),
    ]);
  }

  Widget _chip(PeriodStat p, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 68,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF111111) : Cap.tile,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(p.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: sel ? Colors.white70 : Cap.muted)),
          const SizedBox(height: 1),
          Text(p.sub, maxLines: 1, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: sel ? Colors.white : Cap.ink)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('₹${p.amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: sel ? Colors.white : Cap.ink)),
          ),
          if (p.isCurrent) ...[
            const SizedBox(height: 3),
            Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: sel ? Colors.white : AppColors.green)),
          ],
        ]),
      ),
    );
  }

  Widget _heroCard(String title, PeriodStat p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Cap.tile,
        borderRadius: BorderRadius.circular(Cap.radius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Cap.caption(size: 13.5).copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('₹${p.amount.toStringAsFixed(0)}',
              style: TextStyle(color: Cap.ink, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        ),
        const SizedBox(height: 4),
        Text('${p.rides} ${p.rides == 1 ? "trip" : "trips"} completed', style: Cap.caption(size: 13)),
      ]),
    );
  }

  Widget _statGrid(PeriodStat p) {
    final avg = p.rides > 0 ? p.amount / p.rides : 0;
    final hrs = p.durationMin ~/ 60, mins = p.durationMin % 60;
    final dur = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';
    return Column(children: [
      Row(children: [
        Expanded(child: CapStatCard(icon: Icons.directions_car_filled_outlined, value: '${p.rides}', label: 'Trips', compact: true)),
        const SizedBox(width: 10),
        Expanded(child: CapStatCard(icon: Icons.route_outlined, value: '${p.distanceKm.toStringAsFixed(1)} km', label: 'Distance', compact: true)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        // Sum of the completed trips' durations — not time spent online.
        Expanded(child: CapStatCard(icon: Icons.timer_outlined, value: dur, label: 'Trip time', compact: true)),
        const SizedBox(width: 10),
        Expanded(child: CapStatCard(icon: Icons.trending_up_rounded, value: '₹${avg.toStringAsFixed(0)}', label: 'Avg / trip', compact: true)),
      ]),
    ]);
  }

  // Full breakdown list rendered inline on the page (no bottom sheet).
  Widget _listSection(String title, List<PeriodStat> items, int selectedIndex) {
    final total = items.fold<double>(0, (s, p) => s + p.amount);
    final rides = items.fold<int>(0, (s, p) => s + p.rides);
    // Newest first so the latest day / month is on top.
    final indexed = List.generate(items.length, (i) => (i: i, p: items[i])).reversed.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CapSectionTitle(title,
          trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${total.toStringAsFixed(0)}', style: Cap.body(size: 16, weight: FontWeight.w900)),
            Text('$rides ${rides == 1 ? "trip" : "trips"}', style: Cap.caption(size: 11.5)),
          ])),
      Container(
        decoration: BoxDecoration(
          color: Cap.surface,
          borderRadius: BorderRadius.circular(Cap.radius),
          border: Border.all(color: Cap.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final e in indexed) ...[
            _statRow(e.p, selected: e.i == selectedIndex),
            if (e.i != indexed.last.i) Padding(padding: const EdgeInsets.only(left: 70), child: Container(height: 1, color: Cap.divider)),
          ],
        ]),
      ),
    ]);
  }

  Widget _statRow(PeriodStat p, {bool selected = false}) {
    return Container(
      color: selected ? Cap.accent.withValues(alpha: 0.05) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(p.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Cap.muted)),
            FittedBox(fit: BoxFit.scaleDown,
                child: Text(p.sub, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Cap.ink))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.rides} ${p.rides == 1 ? "trip" : "trips"}  •  ${p.distanceKm.toStringAsFixed(1)} km',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Cap.body(size: 13, weight: FontWeight.w700)),
          Text('${p.durationMin} min on trips', style: Cap.caption(size: 11.5)),
        ])),
        const SizedBox(width: 8),
        Text('₹${p.amount.toStringAsFixed(0)}', style: Cap.body(size: 15.5, weight: FontWeight.w900)),
      ]),
    );
  }
}
