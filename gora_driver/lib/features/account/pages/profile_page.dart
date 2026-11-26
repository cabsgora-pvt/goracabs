import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/token_store.dart';

class ProfilePage extends StatefulWidget {
  static const route = '/profile';
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // Fresh from the server: it puts the registration face scan back as the
    // photo if anything else was ever set.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DriverProvider>().loadProfile();
    });
  }

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
          // The photo is the face captured at registration. Drivers cannot
          // change it — riders must see the person who actually drives.
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  key: const ValueKey('driver_profile_photo'),
                  radius: 52,
                  backgroundColor: AppColors.cardBg,
                  // The photo is the private face capture: sent with the token.
                  backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl, headers: imageHeadersFor(picUrl)) : null,
                  child: picUrl.isEmpty
                      ? Text(name[0].toUpperCase(),
                          style: TextStyle(fontSize: 42, color: AppColors.textDark, fontWeight: FontWeight.w800))
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 3),
                    ),
                    child: Icon(Icons.verified_user_rounded, color: AppColors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Face verified photo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.green)),
          ),
          const SizedBox(height: 14),
          Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 17),
            Text(' ${dp.rating}  •  ${dp.totalRides} trips',
                style: TextStyle(color: AppColors.textGrey)),
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
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textGrey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your profile photo is the face scan taken when you registered, so riders can '
                'recognise you. It cannot be changed in the app — contact support if it needs updating.',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey, height: 1.35),
              ),
            ),
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
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(children: items.asMap().entries.map((e) => Column(children: [
      if (e.key > 0) Divider(color: AppColors.divider, height: 20),
      Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(e.value.icon, color: AppColors.textDark, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.value.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textGrey)),
          Text(e.value.value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
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
