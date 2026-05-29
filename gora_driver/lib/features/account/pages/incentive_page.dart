import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';

class IncentivePage extends StatelessWidget {
  static const route = '/incentives';
  const IncentivePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Incentives'),
      backgroundColor: AppColors.cardBg,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockIncentives.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final inc = mockIncentives[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.celebration, color: AppColors.orange, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(inc.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
                  Text('Expires: ${inc.deadline}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(inc.reward, style: const TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 12),
              Text(inc.description, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Progress: ${inc.current}/${inc.target}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                Text('${(inc.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: inc.progress, minHeight: 8, backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
              ),
            ]),
          );
        },
      ),
    );
  }
}
