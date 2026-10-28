import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../bloc/history_bloc.dart';
import 'trip_detail_page.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

class HistoryPage extends StatelessWidget {
  static const route = '/history';
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoryBloc()..add(LoadHistoryEvent()),
      child: Scaffold(
        appBar: blueAppBar('Trip History'),
        backgroundColor: Cap.tile,
        body: BlocBuilder<HistoryBloc, HistoryState>(
          builder: (context, state) {
            if (state is HistoryLoading) return const AppLoader();
            if (state is HistoryLoaded) {
              if (state.loadFailed) {
                return const EmptyState(message: "Couldn't load trips — check your connection", icon: Icons.wifi_off);
              }
              return state.trips.isEmpty
                  ? const EmptyState(message: 'No trips yet', icon: Icons.history)
                  : _TripList(trips: state.trips);
            }
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

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: Cap.muted),
    const SizedBox(width: 4),
    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12))),
  ]);

  @override
  Widget build(BuildContext context) {
    final isCompleted = trip.status == 'completed';
    final outstation = trip.service == 'outstation';
    final serviceLabel = outstation
        ? 'OUTSTATION · ${trip.tripType == "round_trip" ? "Round" : "One Way"}'
        : trip.service.toUpperCase();
    final statusColor = isCompleted ? AppColors.green : AppColors.red;
    return CapCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Date · fare
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.date, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 14.5, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (serviceLabel.isNotEmpty)
                  CapChip(serviceLabel, color: outstation ? AppColors.orange : Cap.ink, fontSize: 10),
                if (trip.vehicleType.isNotEmpty)
                  CapChip(trip.vehicleType, color: Cap.muted, fontSize: 10),
                if (trip.numPassengers > 0)
                  CapChip('${trip.numPassengers}', color: Cap.muted, icon: Icons.group_outlined, fontSize: 10),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(trip.fare, style: Cap.body(size: 16, weight: FontWeight.w900)),
            const SizedBox(height: 4),
            CapChip(trip.status, color: statusColor, fontSize: 10.5),
          ]),
        ]),
        if (outstation && (trip.cityFrom.isNotEmpty || trip.cityTo.isNotEmpty)) ...[
          const SizedBox(height: 8),
          Text('${trip.cityFrom} → ${trip.cityTo}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Cap.body(size: 12.5, weight: FontWeight.w700, color: AppColors.orange)),
        ],
        if (trip.pickupAddress.isNotEmpty) ...[
          const SizedBox(height: 12),
          CapRoute(pickup: trip.pickupAddress, drop: trip.dropAddress, maxLines: 1),
        ],
        const SizedBox(height: 12),
        Container(height: 1, color: Cap.divider),
        const SizedBox(height: 10),
        // Rider, then distance · duration · rating
        Row(children: [
          CapAvatar(name: trip.userName.isNotEmpty ? trip.userName : '?', url: trip.userProfilePicUrl, radius: 13),
          const SizedBox(width: 8),
          Expanded(
            child: Text(trip.userName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Cap.body(size: 12.5, weight: FontWeight.w700)),
          ),
          if (isCompleted && trip.rating > 0) ...[
            const SizedBox(width: 8),
            const Icon(Icons.star_rounded, size: 15, color: Cap.amber),
            Text(trip.rating.toStringAsFixed(trip.rating == trip.rating.roundToDouble() ? 0 : 1),
                style: Cap.body(size: 12, weight: FontWeight.w800)),
          ],
        ]),
        if (isCompleted) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _meta(Icons.route_outlined, trip.distance),
            _meta(Icons.timer_outlined, trip.duration),
          ]),
        ],
      ]),
    );
  }
}
