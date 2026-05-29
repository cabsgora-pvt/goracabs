import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';

class ProfilePage extends StatelessWidget {
  static const route = '/profile';
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final d = mockDriver;
    return Scaffold(
      appBar: blueAppBar('My Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Center(child: Stack(children: [
            CircleAvatar(radius: 50, backgroundColor: AppColors.primary,
              child: Text(d.name[0], style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.w800))),
            Positioned(bottom: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.edit, color: Colors.white, size: 16),
              )),
          ])),
          const SizedBox(height: 16),
          Text(d.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.star, color: AppColors.orange, size: 16),
            Text(' ${d.rating}  •  ${d.totalRides} trips', style: const TextStyle(color: AppColors.textGrey)),
          ]),
          const SizedBox(height: 24),
          _InfoCard(items: [
            _Item(Icons.phone, 'Mobile', d.phone),
            _Item(Icons.email, 'Email', d.email),
            _Item(Icons.badge, 'Driver ID', d.id),
          ]),
          const SizedBox(height: 16),
          _InfoCard(items: [
            _Item(Icons.directions_car, 'Vehicle', d.vehicleModel),
            _Item(Icons.pin, 'Plate Number', d.vehicleNumber),
            _Item(Icons.category, 'Type', d.vehicleType),
          ]),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Edit Profile', onTap: () {}),
        ]),
      ),
    );
  }
}

class _Item { final IconData icon; final String label, value; const _Item(this.icon, this.label, this.value); }

class _InfoCard extends StatelessWidget {
  final List<_Item> items;
  const _InfoCard({required this.items});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(children: items.map((i) => Column(children: [
      if (items.indexOf(i) > 0) const Divider(color: AppColors.divider, height: 20),
      InfoTile(icon: i.icon, label: i.label, value: i.value),
    ])).toList()),
  );
}
