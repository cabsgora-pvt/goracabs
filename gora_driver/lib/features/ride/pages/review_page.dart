import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

class ReviewPage extends StatefulWidget {
  static const route = '/review';
  const ReviewPage({super.key});
  @override State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  int _stars = 0;
  final _comment = TextEditingController();
  final _quickTags = ['Polite', 'Clean Ride', 'On Time', 'Good Route', 'Professional'];
  final Set<String> _selected = {};

  @override
  void dispose() { _comment.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ride = ModalRoute.of(context)?.settings.arguments as RideRequestModel?;
    return Scaffold(
      appBar: blueAppBar('Rate Rider', showBack: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 16),
          CircleAvatar(radius: 40, backgroundColor: AppColors.primary,
            child: Text(ride?.userName[0] ?? 'U', style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w800))),
          const SizedBox(height: 12),
          Text(ride?.userName ?? 'Rider', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text(ride?.pickupAddress ?? '', style: const TextStyle(color: AppColors.textGrey, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          const Text('How was your ride?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) =>
            GestureDetector(
              onTap: () => setState(() => _stars = i + 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(i < _stars ? Icons.star_rounded : Icons.star_border_rounded,
                  color: AppColors.orange, size: 44),
              ),
            ),
          )),
          const SizedBox(height: 24),
          // Quick tags
          Wrap(spacing: 8, runSpacing: 8, children: _quickTags.map((tag) {
            final sel = _selected.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: sel,
              onSelected: (v) => setState(() => v ? _selected.add(tag) : _selected.remove(tag)),
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(color: sel ? AppColors.primary : AppColors.textGrey, fontWeight: FontWeight.w500),
              side: BorderSide(color: sel ? AppColors.primary : AppColors.divider),
            );
          }).toList()),
          const SizedBox(height: 20),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Additional comments (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Submit Review',
            onTap: _stars == 0
                ? null
                : () async {
                    final tags = _selected.join(', ');
                    final review = [tags, _comment.text].where((s) => s.isNotEmpty).join(' • ');
                    if (ride != null && ride.id.isNotEmpty) {
                      try {
                        await DriverApiService.rateRide(ride.id, _stars, review);
                      } catch (_) {}
                    }
                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
                  },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false),
            child: const Text('Skip', style: TextStyle(color: AppColors.textGrey)),
          ),
        ]),
      ),
    );
  }
}
