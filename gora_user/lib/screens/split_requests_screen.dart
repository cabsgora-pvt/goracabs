import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Rides where a friend split the fare with the rider and this account still
/// owes its share. Pull-based — the app has no push notifications yet, so a
/// friend who split a ride finds out here rather than being pinged instantly.
class SplitRequestsScreen extends StatefulWidget {
  const SplitRequestsScreen({super.key});
  @override
  State<SplitRequestsScreen> createState() => _SplitRequestsScreenState();
}

class _SplitRequestsScreenState extends State<SplitRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  final Set<String> _paying = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService.getSplitRequests();
      final list = ((r['requests'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _requests = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay(Map<String, dynamic> req) async {
    final rideId = req['rideId'].toString();
    setState(() => _paying.add(rideId));
    final res = await ApiService.paySplitShare(rideId);
    if (!mounted) return;
    setState(() => _paying.remove(rideId));
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paid — thanks for splitting the fare!'), backgroundColor: Colors.green),
      );
      _load();
    } else {
      final lowBalance = res['balance'] != null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        lowBalance
            ? 'Not enough wallet balance — add money to your wallet first.'
            : (res['error'] ?? 'Payment failed').toString(),
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split Requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? ListView(children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.28),
                      Icon(Icons.call_split, size: 72, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Center(child: Text('No pending split requests', style: TextStyle(color: Colors.grey[600]))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final r = _requests[i];
                        final rideId = r['rideId'].toString();
                        final busy = _paying.contains(rideId);
                        final share = (r['share'] as num?) ?? 0;
                        final riderName = '${r['riderName'] ?? 'A friend'}';
                        final initial = riderName.trim().isNotEmpty ? riderName.trim()[0].toUpperCase() : '?';
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
                                child: Text(initial, style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('$riderName split a ride with you',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.alt_route, size: 16, color: Colors.grey[500]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${r['pickupAddress'] ?? ''} → ${r['dropAddress'] ?? ''}',
                                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700]), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Icon(Icons.local_taxi_outlined, size: 16, color: Colors.grey[500]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${r['vehicleType'] ?? ''} • Driver: ${r['driverName'] ?? '—'}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            Container(height: 1, color: Colors.grey.shade200),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Your share', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                                  Text('₹${share.toStringAsFixed(0)}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primaryBlue)),
                                ]),
                              ),
                              ElevatedButton(
                                onPressed: busy ? null : () => _pay(r),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: busy
                                    ? const SizedBox(width: 18, height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Pay from Wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}
