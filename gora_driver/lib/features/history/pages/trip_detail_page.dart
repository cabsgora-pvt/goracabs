import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

class TripDetailPage extends StatelessWidget {
  final TripModel trip;
  const TripDetailPage({super.key, required this.trip});

  static String _money(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: Cap.caption(size: 13))),
      Text(value, style: Cap.body(size: 13.5, weight: FontWeight.w700)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final completed = trip.status == 'completed';
    final statusColor = completed ? AppColors.green : AppColors.red;
    return Scaffold(
      appBar: blueAppBar('Trip details'),
      backgroundColor: Cap.tile,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary
          CapCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(trip.date, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 13))),
                CapChip(completed ? 'Completed' : 'Cancelled', color: statusColor,
                    icon: completed ? Icons.check_circle_rounded : Icons.cancel_rounded),
              ]),
              // The fare is what the rider paid, not what the driver earned.
              // Earnings are shown only from the ride's own driverEarning.
              if (completed && trip.driverEarning > 0) ...[
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('₹${_money(trip.driverEarning)}',
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Cap.ink, letterSpacing: -0.6)),
                ),
                Text('You earned', style: Cap.caption(size: 12.5)),
                const SizedBox(height: 12),
                Container(height: 1, color: Cap.divider),
                const SizedBox(height: 10),
                _row('Fare', trip.fare),
                if (trip.commission > 0) _row('Commission', '− ₹${_money(trip.commission)}'),
              ] else if (completed) ...[
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(trip.fare, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Cap.ink, letterSpacing: -0.6)),
                ),
                Text('Fare', style: Cap.caption(size: 12.5)),
              ],
            ]),
          ),
          if (completed) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: CapStatCard(label: 'Distance', value: trip.distance, icon: Icons.route_outlined, compact: true)),
              const SizedBox(width: 8),
              Expanded(child: CapStatCard(label: 'Duration', value: trip.duration, icon: Icons.timer_outlined, compact: true)),
              const SizedBox(width: 8),
              Expanded(child: CapStatCard(label: 'Payment', value: trip.paymentMode, icon: Icons.payments_outlined, compact: true)),
            ]),
          ],
          const SizedBox(height: 10),
          // Route
          CapCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Route', style: Cap.body(size: 14.5, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              CapRoute(pickup: trip.pickupAddress, drop: trip.dropAddress, maxLines: 3),
            ]),
          ),
          const SizedBox(height: 10),
          // Rider
          CapCard(
            child: Row(children: [
              CapAvatar(name: trip.userName.isNotEmpty ? trip.userName : '?', url: trip.userProfilePicUrl, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trip.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 15, weight: FontWeight.w800)),
                  Text('Rider', style: Cap.caption(size: 12)),
                ]),
              ),
              if (trip.rating > 0)
                Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => Icon(
                  i < trip.rating ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16, color: i < trip.rating ? Cap.amber : Cap.divider))),
            ]),
          ),
        ],
      ),
    );
  }
}
