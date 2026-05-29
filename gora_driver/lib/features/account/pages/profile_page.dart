import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';

class ProfilePage extends StatelessWidget {
  static const route = '/profile';
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DriverProvider>();
    final picUrl = dp.profilePicUrl;
    final name = dp.name.isNotEmpty ? dp.name : 'Driver';

    return Scaffold(
      appBar: blueAppBar('My Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Profile picture
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: AppColors.cardBg,
              backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
              child: picUrl.isEmpty
                  ? Text(name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 42, color: AppColors.primary, fontWeight: FontWeight.w800))
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.star, color: AppColors.orange, size: 16),
            Text(' ${dp.rating}  •  ${dp.totalRides} trips',
                style: const TextStyle(color: AppColors.textGrey)),
          ]),
          const SizedBox(height: 24),

          // Personal info
          _InfoCard(items: [
            _Item(Icons.phone, 'Mobile', dp.phone.isNotEmpty ? '+91 ${dp.phone}' : '—'),
            _Item(Icons.email, 'Email', dp.email.isNotEmpty ? dp.email : '—'),
            _Item(Icons.map, 'State', dp.state.isNotEmpty ? dp.state : '—'),
          ]),
          const SizedBox(height: 16),

          // Vehicle info
          _InfoCard(items: [
            _Item(Icons.directions_car, 'Vehicle', dp.vehicleModel.isNotEmpty ? dp.vehicleModel : '—'),
            _Item(Icons.pin, 'Plate Number', dp.vehicleNumber.isNotEmpty ? dp.vehicleNumber : '—'),
            _Item(Icons.category, 'Type', dp.vehicleType.isNotEmpty ? dp.vehicleType : '—'),
          ]),
        ]),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_Item> items;
  const _InfoCard({required this.items});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)],
    ),
    child: Column(children: items.asMap().entries.map((e) => Column(children: [
      if (e.key > 0) const Divider(color: AppColors.divider, height: 20),
      Row(children: [
        Icon(e.value.icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.value.label, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
          Text(e.value.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        ])),
      ]),
    ])).toList()),
  );
}

class _Item {
  final IconData icon;
  final String label, value;
  const _Item(this.icon, this.label, this.value);
}
