import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/earnings_bloc.dart';

// Earnings screen with three tabs: Today, Weekly, Monthly.
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
        backgroundColor: AppColors.cardBg,
        body: BlocBuilder<EarningsBloc, EarningsState>(
          builder: (context, state) {
            if (state is! EarningsLoaded) return const AppLoader();
            return Column(children: [
              _tabs(),
              Expanded(child: _content(state)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _tabs() {
    const labels = ['Today', 'Weekly', 'Monthly'];
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.all(12),
      child: Row(children: List.generate(3, (i) {
        final sel = _tab == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : AppColors.cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(labels[i], textAlign: TextAlign.center,
                  style: TextStyle(color: sel ? Colors.white : AppColors.textGrey, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
        );
      })),
    );
  }

  Widget _content(EarningsLoaded s) {
    switch (_tab) {
      case 1:
        return _periodView(s.weekly, _weekSel, (i) => setState(() => _weekSel = i), 'This Week');
      case 2:
        return _periodView(s.monthly, _monthSel, (i) => setState(() => _monthSel = i), 'Year ${DateTime.now().year}');
      default:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _heroCard("Today's Earnings", s.today),
            const SizedBox(height: 14),
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
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, idx) => _chip(items[idx], idx == i, () => onSel(idx)),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(children: [
            _heroCard('${selected.label} ${selected.sub}', selected),
            const SizedBox(height: 14),
            _statGrid(selected),
            const SizedBox(height: 18),
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
        width: 74,
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? AppColors.primary : AppColors.divider),
          boxShadow: sel ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(p.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white70 : AppColors.textGrey)),
          const SizedBox(height: 2),
          Text(p.sub, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: sel ? Colors.white : AppColors.textDark)),
          const SizedBox(height: 6),
          Text('₹${p.amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.primary)),
          if (p.isCurrent) ...[
            const SizedBox(height: 4),
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
        gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('₹${p.amount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${p.rides} ${p.rides == 1 ? "ride" : "rides"} completed', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ])),
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
        ),
      ]),
    );
  }

  Widget _statGrid(PeriodStat p) {
    final avg = p.rides > 0 ? p.amount / p.rides : 0;
    final hrs = p.durationMin ~/ 60, mins = p.durationMin % 60;
    final dur = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';
    return Column(children: [
      Row(children: [
        Expanded(child: _tile(Icons.directions_car_filled, '${p.rides}', 'Rides')),
        const SizedBox(width: 12),
        Expanded(child: _tile(Icons.route, '${p.distanceKm.toStringAsFixed(1)} km', 'Distance')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _tile(Icons.timer_outlined, dur, 'Time online')),
        const SizedBox(width: 12),
        Expanded(child: _tile(Icons.trending_up, '₹${avg.toStringAsFixed(0)}', 'Avg / ride')),
      ]),
    ]);
  }

  Widget _tile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ])),
      ]),
    );
  }

  // Full breakdown list rendered inline on the page (no bottom sheet).
  Widget _listSection(String title, List<PeriodStat> items, int selectedIndex) {
    final total = items.fold<double>(0, (s, p) => s + p.amount);
    final rides = items.fold<int>(0, (s, p) => s + p.rides);
    // Newest first so the latest day / month is on top.
    final indexed = List.generate(items.length, (i) => (i: i, p: items[i])).reversed.toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Expanded(child: Text('$title · Breakdown',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.green)),
              Text('$rides ${rides == 1 ? "ride" : "rides"}', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
            ]),
          ]),
        ),
        Divider(height: 1, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final e in indexed) ...[
              _statRow(e.p, selected: e.i == selectedIndex),
              if (e.i != indexed.last.i) const SizedBox(height: 10),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _statRow(PeriodStat p, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withOpacity(0.05) : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.primary.withOpacity(0.5) : Colors.transparent),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(p.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
            Text(p.sub, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.primary)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.rides} ${p.rides == 1 ? "ride" : "rides"}  •  ${p.distanceKm.toStringAsFixed(1)} km',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          Text('${p.durationMin} min online', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ])),
        Text('₹${p.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 16)),
      ]),
    );
  }
}
