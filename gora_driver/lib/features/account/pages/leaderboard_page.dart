import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';

class LeaderboardPage extends StatelessWidget {
  static const route = '/leaderboard';
  const LeaderboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Leaderboard'),
      backgroundColor: AppColors.cardBg,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockLeaderboard.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final e = mockLeaderboard[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: e.isMe ? AppColors.primary.withOpacity(0.08) : AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: e.isMe ? Border.all(color: AppColors.primary, width: 1.5) : null,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
            ),
            child: Row(children: [
              SizedBox(
                width: 36,
                child: Text(e.badge.isNotEmpty ? e.badge : '#${e.rank}',
                  style: TextStyle(fontSize: e.badge.isNotEmpty ? 22 : 15, fontWeight: FontWeight.w800, color: AppColors.textDark), textAlign: TextAlign.center),
              ),
              const SizedBox(width: 12),
              CircleAvatar(radius: 20, backgroundColor: e.isMe ? AppColors.primary : AppColors.cardBg,
                child: Text(e.name[0], style: TextStyle(fontWeight: FontWeight.w700, color: e.isMe ? Colors.white : AppColors.primary))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.isMe ? '${e.name} (You)' : e.name, style: TextStyle(fontWeight: FontWeight.w700, color: e.isMe ? AppColors.primary : AppColors.textDark)),
                Text('${e.rides} rides', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              ])),
              Text(e.earnings, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ]),
          );
        },
      ),
    );
  }
}
