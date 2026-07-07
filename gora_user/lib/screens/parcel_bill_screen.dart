import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Ola-style "Parcel delivered" bill screen shown when a delivery completes.
class ParcelBillScreen extends StatelessWidget {
  final num amount;
  final String vehicleName;
  const ParcelBillScreen({super.key, required this.amount, this.vehicleName = 'Delivery'});

  @override
  Widget build(BuildContext context) {
    final amt = '₹${amount.toStringAsFixed(0)}';
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        // Header (delivered)
        Container(
          height: MediaQuery.of(context).size.height * 0.22,
          width: double.infinity,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.primaryBlue, Color(0xFF3A4A8C)])),
          child: SafeArea(
            child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.check_circle, color: Colors.white, size: 56),
                SizedBox(height: 8),
                Text('Parcel Delivered', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Text('Parcel', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Deliver anything', style: TextStyle(fontSize: 14, color: Colors.grey)),
                ])),
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.local_shipping, color: AppTheme.primaryBlue, size: 30),
                ),
              ]),
              const SizedBox(height: 20),
              // Feature row
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
                _Feature(Icons.door_front_door_outlined, 'Doorstep\nDelivery'),
                _Feature(Icons.bolt, 'Fast\nDelivery'),
                _Feature(Icons.auto_awesome, 'Best in Class\nExperience'),
              ]),
              const SizedBox(height: 24),
              // Bill card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Expanded(child: Text('Total Bill (with convenience fees)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                    Text(amt, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 14),
                  _row('Delivery charge', amt),
                  const SizedBox(height: 8),
                  _row('Total Bill (with convenience fees)', amt),
                  const SizedBox(height: 12),
                  Text(
                    'A 100% fee will be charged if orders are cancelled any time after they are accepted. However, in case of unusual delays you will not be charged a cancellation fee.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500], height: 1.4),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('Our fleet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Icon(Icons.two_wheeler, size: 40, color: Colors.grey), SizedBox(width: 16),
                  Icon(Icons.electric_moped, size: 40, color: Colors.grey), SizedBox(width: 16),
                  Icon(Icons.moped, size: 40, color: Colors.grey),
                ]),
              ),
              Text(vehicleName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ]),
          ),
        ),
        // Done
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static Widget _row(String l, String v) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ]);
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Feature(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, size: 26, color: Colors.black87),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3)),
      ]);
}
