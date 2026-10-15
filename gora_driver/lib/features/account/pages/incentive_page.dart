import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

// Incentives with REAL progress.
//
// This screen used to render mockIncentives — invented targets and percentages,
// promising bonuses that did not exist. Progress now comes from
// /auth/driver/incentives, which counts the driver's own completed rides (or
// earnings) inside each rule's period and hour window.
class IncentivePage extends StatefulWidget {
  static const route = '/incentives';
  const IncentivePage({super.key});
  @override
  State<IncentivePage> createState() => _IncentivePageState();
}

class _IncentivePageState extends State<IncentivePage> {
  List<IncentiveModel> _items = [];
  List<bool> _achieved = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _deadline(dynamic iso) {
    final t = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (t == null) return '';
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'Ended';
    if (d.inHours < 24) return d.inHours < 1 ? '${d.inMinutes} min left' : '${d.inHours}h left';
    return '${d.inDays}d left';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await DriverApiService.getIncentives();
      final raw = (res['incentives'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _items = raw.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final isEarnings = (m['metric'] ?? 'rides') == 'earnings';
          final cur = (m['current'] as num?) ?? 0;
          final tgt = (m['target'] as num?) ?? 0;
          return IncentiveModel(
            title: (m['title'] ?? '').toString(),
            description: (m['description'] ?? '').toString(),
            target: isEarnings ? '₹$tgt' : '$tgt',
            current: isEarnings ? '₹$cur' : '$cur',
            reward: '₹ ${(m['reward'] as num?) ?? 0} Bonus',
            deadline: _deadline(m['endsAt']),
            progress: ((m['progress'] as num?) ?? 0).toDouble(),
          );
        }).toList();
        _achieved = raw.map((e) => (e as Map)['achieved'] == true).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // No invented fallback — an empty list is honest.
      setState(() { _loading = false; _error = 'Could not load incentives'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Incentives'),
      backgroundColor: AppColors.cardBg,
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Column(children: [
          Text(_error!, style: TextStyle(color: AppColors.textGrey)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ])),
      ]);
    }
    if (_items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text('No incentives running right now. Check back — new bonuses are added regularly.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey)),
        )),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final inc = _items[i];
        final done = i < _achieved.length && _achieved[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: done ? Border.all(color: AppColors.green, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (done ? AppColors.green : AppColors.orange).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(done ? Icons.check_circle : Icons.celebration,
                    color: done ? AppColors.green : AppColors.orange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inc.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
                Text(done ? 'Achieved' : inc.deadline,
                    style: TextStyle(fontSize: 11, color: done ? AppColors.green : AppColors.textGrey)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(inc.reward, style: const TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w700)),
              ),
            ]),
            if (inc.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(inc.description, style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Progress: ${inc.current}/${inc.target}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              Text('${(inc.progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 12, color: done ? AppColors.green : AppColors.primary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: inc.progress, minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(done ? AppColors.green : AppColors.primary),
              ),
            ),
          ]),
        );
      },
    );
  }
}
