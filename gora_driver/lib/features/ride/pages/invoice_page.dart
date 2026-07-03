import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import 'review_page.dart';

class InvoicePage extends StatelessWidget {
  static const route = '/invoice';
  const InvoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ride = ModalRoute.of(context)?.settings.arguments as RideRequestModel?;

    return Scaffold(
      backgroundColor: AppColors.cardBg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                // Success header
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 12),
                    const Text('Ride Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(ride?.fare ?? '₹ 185', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
                    const Text('Total Fare', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 16),
                // Fare breakdown
                _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fare Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 12),
                  _fareRow('Base Fare', '₹ 50'),
                  _fareRow('Distance (${ride?.distance ?? "12 km"})', '₹ 110'),
                  _fareRow('Time Charges', '₹ 30'),
                  _fareRow('GST (5%)', '₹ 9.50'),
                  Divider(color: AppColors.divider, height: 24),
                  _fareRow('Total', ride?.fare ?? '₹ 185', bold: true),
                ])),
                const SizedBox(height: 12),
                // Trip summary
                _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Trip Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 12),
                  InfoTile(icon: Icons.person, label: 'Rider', value: ride?.userName ?? 'User'),
                  const SizedBox(height: 12),
                  InfoTile(icon: Icons.route, label: 'Distance', value: ride?.distance ?? '12 km'),
                  const SizedBox(height: 12),
                  InfoTile(icon: Icons.payment, label: 'Payment', value: 'Cash'),
                  const SizedBox(height: 12),
                  InfoTile(icon: Icons.timer, label: 'Duration', value: '28 min'),
                ])),
                const SizedBox(height: 12),
                // Pickup/drop
                _Card(child: Column(children: [
                  Row(children: [
                    const Icon(Icons.radio_button_checked, color: AppColors.green, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(ride?.pickupAddress ?? '', style: TextStyle(fontSize: 13, color: AppColors.textDark))),
                  ]),
                  Padding(padding: const EdgeInsets.only(left: 9), child: Container(width: 2, height: 20, color: AppColors.divider)),
                  Row(children: [
                    const Icon(Icons.location_on, color: AppColors.red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(ride?.dropAddress ?? '', style: TextStyle(fontSize: 13, color: AppColors.textDark))),
                  ]),
                ])),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: PrimaryButton(
              label: 'Rate this Rider',
              onTap: () => Navigator.pushReplacementNamed(context, ReviewPage.route, arguments: ride),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _fareRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: bold ? AppColors.textDark : AppColors.textGrey, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, fontSize: bold ? 15 : 13)),
        Text(value, style: TextStyle(color: AppColors.textDark, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 15 : 13)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: child,
  );
}
