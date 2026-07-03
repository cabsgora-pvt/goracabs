import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';

class ProfilePage extends StatefulWidget {
  static const route = '/profile';
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;

  Future<void> _changeProfilePic() async {
    if (_uploading) return;

    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _uploading = true);
    try {
      // 1. Upload the raw image → returns the full image URL (already run
      //    through AppConfig.imageUrl by the service).
      final uploadedUrl = await DriverApiService.uploadFile(picked);
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        if (!mounted) return;
        _showSnack('Failed to upload image. Please try again.', isError: true);
        return;
      }

      // 2. Persist it on the driver. Backend expects the value uploadFile returned.
      final res = await DriverApiService.saveProfilePic(uploadedUrl);
      if (!mounted) return;
      if (res['success'] != true) {
        _showSnack('Could not save profile picture. Please try again.', isError: true);
        return;
      }

      // 3. Re-fetch the profile so the provider (and every screen that reads it:
      //    home header, account page) reflects server truth for the new photo.
      await context.read<DriverProvider>().loadProfile();
      if (!mounted) return;

      _showSnack('Profile picture updated!');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : AppColors.primary,
      ),
    );
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
          // Profile picture (tappable → pick / upload new photo)
          Center(
            child: GestureDetector(
              onTap: _uploading ? null : _changeProfilePic,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: AppColors.cardBg,
                    backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                    child: picUrl.isEmpty
                        ? Text(name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 42, color: AppColors.primary, fontWeight: FontWeight.w800))
                        : null,
                  ),
                  // Dim + spinner overlay while uploading
                  if (_uploading)
                    Positioned.fill(
                      child: CircleAvatar(
                        radius: 52,
                        backgroundColor: Colors.black.withAlpha(90),
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                        ),
                      ),
                    ),
                  // Camera badge
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, color: AppColors.white, size: 16),
                    ),
                  ),
                ],
              ),
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
