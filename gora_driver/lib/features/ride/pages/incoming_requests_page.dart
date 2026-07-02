import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import 'on_ride_page.dart';

// Shows up to 5 pending ride requests at once (taxi / rental / outstation / etc.).
// The driver can Accept or Reject any of them; rejected/taken ones drop off and
// fresh requests fill in. Accepting one navigates to the on-ride screen.
class IncomingRequestsPage extends StatefulWidget {
  static const route = '/incoming-requests';
  const IncomingRequestsPage({super.key});
  @override
  State<IncomingRequestsPage> createState() => _IncomingRequestsPageState();
}

class _IncomingRequestsPageState extends State<IncomingRequestsPage> {
  static const int _maxRequests = 5;
  List<RideRequestModel> _requests = [];
  final Set<String> _rejectedIds = {};
  Timer? _timer;
  bool _accepting = false;
  bool _firstLoaded = false;

  // Per-service ringtone (admin-managed) + player
  Map<String, String> _ringtones = {};
  final AudioPlayer _player = AudioPlayer();
  String? _playingService;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cfg = await DriverApiService.getDriverConfig();
      final r = (cfg['ringtones'] as Map?) ?? {};
      _ringtones = r.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    await _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_accepting || !mounted) return;
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      final models = rides
          .map((e) => RideRequestModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((m) => !_rejectedIds.contains(m.id))
          .take(_maxRequests)
          .toList();
      if (!mounted) return;
      _firstLoaded = true;
      if (models.isEmpty) { await _stopRing(); if (mounted) Navigator.pop(context); return; }
      setState(() => _requests = models);
      _updateRing();
    } catch (_) {}
  }

  // Play the ringtone of the top (nearest) request's service; loop until handled.
  void _updateRing() {
    if (_requests.isEmpty) { _stopRing(); return; }
    final svc = _requests.first.service;
    if (_playingService == svc) return;
    _playRing(svc);
  }

  Future<void> _playRing(String svc) async {
    final rel = _ringtones[svc] ?? '';
    _playingService = svc;
    try {
      await _player.stop();
      if (rel.isEmpty) return; // no custom ringtone set for this service
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(UrlSource(AppConfig.imageUrl(rel)));
    } catch (_) {}
  }

  Future<void> _stopRing() async {
    _playingService = null;
    try { await _player.stop(); } catch (_) {}
  }

  Future<void> _accept(RideRequestModel m) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _timer?.cancel();
    await _stopRing();
    final r = await DriverApiService.acceptRide(m.id);
    if (!mounted) return;
    if (r['success'] == true || r['ride'] != null) {
      Navigator.pushReplacementNamed(context, OnRidePage.route, arguments: m);
    } else {
      // Taken by someone else or error → drop it and resume
      _rejectedIds.add(m.id);
      setState(() { _requests.removeWhere((x) => x.id == m.id); _accepting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r['error']?.toString() ?? 'Ride already taken')),
      );
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
      if (_requests.isEmpty) { Navigator.pop(context); } else { _updateRing(); }
    }
  }

  void _reject(RideRequestModel m) {
    _rejectedIds.add(m.id);
    DriverApiService.rejectRide(m.id); // fire-and-forget; server records rejectedBy
    setState(() => _requests.removeWhere((x) => x.id == m.id));
    if (_requests.isEmpty && mounted) { _stopRing(); Navigator.pop(context); } else { _updateRing(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary])),
            child: Column(children: [
              Text('${_requests.length} New Request${_requests.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              const Text('Tap Accept on any ride', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          Expanded(
            child: !_firstLoaded
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _requestCard(_requests[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  ({Color color, String label}) _serviceMeta(String s) {
    switch (s) {
      case 'outstation': return (color: AppColors.orange, label: 'OUTSTATION');
      case 'rental': return (color: AppColors.primary, label: 'RENTAL');
      case 'hire_driver': return (color: Colors.indigo, label: 'HIRE DRIVER');
      case 'delivery': return (color: Colors.teal, label: 'PARCEL');
      default: return (color: AppColors.green, label: 'TAXI');
    }
  }

  Widget _requestCard(RideRequestModel r) {
    final meta = _serviceMeta(r.service);
    final cash = r.paymentMode == 'cash';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // top row: service badge + fare
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: meta.color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(meta.label, style: TextStyle(color: meta.color, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5)),
            ),
            const Spacer(),
            Text(r.fare, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark)),
          ]),
        ),
        // user + rating
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            CircleAvatar(
              radius: 16, backgroundColor: AppColors.primary,
              backgroundImage: r.userProfilePicUrl.isNotEmpty ? NetworkImage(r.userProfilePicUrl) : null,
              child: r.userProfilePicUrl.isEmpty
                  ? Text(r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'R', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(r.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark))),
            const Icon(Icons.star, color: AppColors.orange, size: 14),
            Text(' ${r.userRating}', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
            const SizedBox(width: 8),
            Text('${r.distance} • ${r.eta}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
          ]),
        ),
        const SizedBox(height: 8),
        // pickup → drop
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(children: [
            _addrRow(Icons.radio_button_checked, AppColors.green, r.pickupAddress),
            const SizedBox(height: 4),
            _addrRow(Icons.location_on, AppColors.red, r.dropAddress),
          ]),
        ),
        // payment
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(children: [
            Icon(cash ? Icons.payments : (r.paymentMode == 'wallet' ? Icons.account_balance_wallet : Icons.credit_card),
                size: 15, color: cash ? AppColors.green : AppColors.primary),
            const SizedBox(width: 5),
            Text(cash ? 'Cash — collect from rider' : (r.paymentMode == 'wallet' ? 'Paid via Wallet' : 'Paid Online'),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cash ? AppColors.green : AppColors.primary)),
          ]),
        ),
        // buttons
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _accepting ? null : () => _reject(r),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.red), padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Reject', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: _accepting ? null : () => _accept(r),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _addrRow(IconData ic, Color c, String addr) => Row(children: [
    Icon(ic, color: c, size: 16),
    const SizedBox(width: 8),
    Expanded(child: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textDark, fontWeight: FontWeight.w500))),
  ]);
}
