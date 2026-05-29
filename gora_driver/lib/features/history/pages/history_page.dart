import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../bloc/history_bloc.dart';
import 'trip_detail_page.dart';

class HistoryPage extends StatelessWidget {
  static const route = '/history';
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoryBloc()..add(LoadHistoryEvent()),
      child: Scaffold(
        appBar: blueAppBar('Trip History'),
        backgroundColor: AppColors.cardBg,
        body: BlocBuilder<HistoryBloc, HistoryState>(
          builder: (context, state) {
            if (state is HistoryLoading) return const AppLoader();
            if (state is HistoryLoaded) return _TripList(trips: state.trips);
            return const EmptyState(message: 'No trips yet', icon: Icons.history);
          },
        ),
      ),
    );
  }
}

class _TripList extends StatelessWidget {
  final List<TripModel> trips;
  const _TripList({required this.trips});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _TripCard(trip: trips[i]),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripModel trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final isCompleted = trip.status == 'completed';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip))),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
        child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 20, backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text(trip.userName[0], style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
              Text(trip.date, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(trip.fare, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isCompleted ? AppColors.green.withOpacity(0.1) : AppColors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(trip.status, style: TextStyle(fontSize: 10, color: isCompleted ? AppColors.green : AppColors.red, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
          if (isCompleted) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Row(children: [
                const Icon(Icons.route, size: 14, color: AppColors.textGrey),
                const SizedBox(width: 4),
                Text(trip.distance, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              ])),
              Expanded(child: Row(children: [
                const Icon(Icons.timer, size: 14, color: AppColors.textGrey),
                const SizedBox(width: 4),
                Text(trip.duration, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              ])),
              Row(children: List.generate(5, (i) => Icon(
                i < trip.rating ? Icons.star : Icons.star_border,
                size: 13, color: AppColors.orange,
              ))),
            ]),
          ],
        ]),
      ),
    );
  }
}
