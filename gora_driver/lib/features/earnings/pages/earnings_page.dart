import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/earnings_bloc.dart';
import '../../../models/models.dart';

class EarningsPage extends StatelessWidget {
  static const route = '/earnings';
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => EarningsBloc()..add(LoadEarningsEvent()),
      child: BlocBuilder<EarningsBloc, EarningsState>(
        builder: (context, state) {
          return Scaffold(
            appBar: blueAppBar('Earnings'),
            backgroundColor: AppColors.cardBg,
            body: state is EarningsLoading
                ? const AppLoader()
                : state is EarningsLoaded
                    ? _Body(weekly: state.weekly, summary: state.summary)
                    : const SizedBox(),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<EarningsModel> weekly;
  final Map<String, String> summary;
  const _Body({required this.weekly, required this.summary});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Summary cards
        Row(children: [
          Expanded(child: StatCard(label: 'Today', value: summary['today'] ?? '₹0', icon: Icons.today, color: AppColors.primary)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'This Week', value: summary['week'] ?? '₹0', icon: Icons.calendar_today, color: AppColors.primaryDark)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatCard(label: 'This Month', value: summary['month'] ?? '₹0', icon: Icons.date_range, color: AppColors.accent)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Total Rides', value: summary['totalRides'] ?? '0', icon: Icons.directions_car, color: AppColors.green)),
        ]),
        const SizedBox(height: 20),
        // Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'Weekly Earnings'),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  barGroups: weekly.asMap().entries.map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [BarChartRodData(
                      toY: double.parse(e.value.amount),
                      color: AppColors.primary,
                      width: 28,
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.accent], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                    )],
                  )).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(weekly[v.toInt()].date, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    )),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // Daily list
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'Daily Breakdown'),
            const SizedBox(height: 12),
            ...weekly.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(e.date, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.primary))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e.rides} rides  •  ${e.distance}', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                  Text(e.duration, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                ])),
                Text('₹ ${e.amount}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 15)),
              ]),
            )),
          ]),
        ),
      ]),
    );
  }
}
