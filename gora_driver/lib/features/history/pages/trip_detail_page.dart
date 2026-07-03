import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';

class TripDetailPage extends StatelessWidget {
  final TripModel trip;
  const TripDetailPage({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Trip Detail'),
      backgroundColor: AppColors.cardBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Status header
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                trip.status == 'completed' ? AppColors.primary : AppColors.red,
                trip.status == 'completed' ? AppColors.primaryDark : AppColors.red.withOpacity(0.7),
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Icon(trip.status == 'completed' ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 40),
              const SizedBox(height: 8),
              Text(trip.status == 'completed' ? 'Completed' : 'Cancelled', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              Text(trip.date, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
              if (trip.status == 'completed') ...[
                const SizedBox(height: 12),
                Text(trip.fare, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                const Text('Total Earned', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          // Trip stats
          if (trip.status == 'completed')
            Row(children: [
              Expanded(child: _StatBox('Distance', trip.distance, Icons.route)),
              const SizedBox(width: 10),
              Expanded(child: _StatBox('Duration', trip.duration, Icons.timer)),
              const SizedBox(width: 10),
              Expanded(child: _StatBox('Payment', trip.paymentMode, Icons.payment)),
            ]),
          const SizedBox(height: 16),
          // User card
          _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rider Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(backgroundColor: AppColors.primary, radius: 22,
                child: Text(trip.userName[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trip.userName, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                if (trip.rating > 0) Row(children: List.generate(5, (i) => Icon(i < trip.rating ? Icons.star : Icons.star_border, size: 14, color: AppColors.orange))),
              ]),
            ]),
          ])),
          const SizedBox(height: 12),
          // Route
          _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Route', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.radio_button_checked, color: AppColors.green, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(trip.pickupAddress, style: TextStyle(fontSize: 13, color: AppColors.textDark))),
            ]),
            Padding(padding: const EdgeInsets.only(left: 9), child: Container(width: 2, height: 20, color: AppColors.divider)),
            Row(children: [
              const Icon(Icons.location_on, color: AppColors.red, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(trip.dropAddress, style: TextStyle(fontSize: 13, color: AppColors.textDark))),
            ]),
          ])),
          const SizedBox(height: 12),
          // Fare
          if (trip.status == 'completed')
            _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Fare Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 12),
              _fareRow('Base Fare', '₹ 50'),
              _fareRow('Distance Fare', '₹ 110'),
              _fareRow('Waiting Charges', '₹ 0'),
              Divider(color: AppColors.divider),
              _fareRow('Total', trip.fare, bold: true),
            ])),
        ]),
      ),
    );
  }

  Widget _fareRow(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(color: bold ? AppColors.textDark : AppColors.textGrey, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
      Text(v, style: TextStyle(color: AppColors.textDark, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
    ]),
  );
}

class _StatBox extends StatelessWidget {
  final String label, value; final IconData icon;
  const _StatBox(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, color: AppColors.primary, size: 18),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textDark), textAlign: TextAlign.center),
      Text(label, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
    ]),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: child,
  );
}
