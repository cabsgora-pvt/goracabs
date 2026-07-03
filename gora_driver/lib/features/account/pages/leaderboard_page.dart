import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

class LeaderboardPage extends StatefulWidget {
  static const route = '/leaderboard';
  const LeaderboardPage({super.key});
  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  bool _loading = true;
  String _zone = '';
  List<LeaderboardEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DriverApiService.getLeaderboard();
      final zone = (res['zone'] ?? '').toString();
      final rows = (res['entries'] as List?) ?? [];
      final entries = rows.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final rank = (m['rank'] as num?)?.toInt() ?? 0;
        final rides = (m['rides'] as num?)?.toInt() ?? 0;
        final earnings = (m['earnings'] as num?)?.toInt() ?? 0;
        return LeaderboardEntry(
          rank: rank,
          name: (m['name'] ?? '').toString(),
          rides: '$rides',
          earnings: '₹ $earnings',
          badge: rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '',
          isMe: (m['isMe'] as bool?) ?? false,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _zone = zone;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Leaderboard'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Text('No data yet', style: TextStyle(color: AppColors.textGrey)),
                )
              : Column(children: [
                  if (_zone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Zone: $_zone',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      ),
                    ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = _entries[i];
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
                              child: Text(e.name.isNotEmpty ? e.name[0] : '?', style: TextStyle(fontWeight: FontWeight.w700, color: e.isMe ? Colors.white : AppColors.primary))),
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
                  ),
                ]),
    );
  }
}
