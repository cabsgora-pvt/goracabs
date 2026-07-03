// All smaller pages in one file
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../config/app_config.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/driver_payment_service.dart';

// ── QR Code Page (driver's own payment/UPI QR — riders scan to pay) ──
class QrCodePage extends StatefulWidget {
  static const route = '/qr-code';
  const QrCodePage({super.key});
  @override
  State<QrCodePage> createState() => _QrCodePageState();
}

class _QrCodePageState extends State<QrCodePage> {
  String _qrUrl = '';
  bool _loading = true, _busy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await DriverApiService.getProfile();
      final d = r['driver'] as Map?;
      if (d != null) _qrUrl = (d['paymentQrUrl'] ?? '').toString();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    setState(() => _busy = true);
    final url = await DriverApiService.uploadFile(x);
    if (!mounted) return;
    if (url != null) {
      await DriverApiService.savePaymentQr(url);
      if (!mounted) return;
      setState(() { _qrUrl = url; _busy = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment QR updated'), backgroundColor: AppColors.green));
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed'), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = _qrUrl.isEmpty ? '' : AppConfig.imageUrl(_qrUrl);
    return Scaffold(
      appBar: blueAppBar('My QR Code'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 240, height: 240, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)]),
                child: full.isEmpty
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.qr_code_2, size: 90, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('No payment QR yet', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ])
                    : ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(full, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 60, color: AppColors.textGrey))),
              ),
              const SizedBox(height: 20),
              Text('Your Payment QR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                child: Text('Riders can scan this to pay you directly (UPI / GPay / PhonePe).', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey, fontSize: 12.5))),
              const SizedBox(height: 24),
              PrimaryButton(label: _qrUrl.isEmpty ? 'Upload QR Code' : 'Change QR Code', width: 220, loading: _busy, onTap: _upload),
            ])),
    );
  }
}

// ── Rate Card Page (real — driver's zone pricing) ──
class RateCardPage extends StatefulWidget {
  static const route = '/rate-card';
  const RateCardPage({super.key});
  @override
  State<RateCardPage> createState() => _RateCardPageState();
}

class _RateCardPageState extends State<RateCardPage> {
  bool _loading = true;
  String _zone = '';
  List<Map<String, dynamic>> _cards = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await DriverApiService.getRateCard();
      _zone = (r['zone'] ?? '').toString();
      _cards = ((r['cards'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Rate Card'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : _cards.isEmpty
              ? Center(child: Text('No rate card set for your zone yet', style: TextStyle(color: AppColors.textGrey)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (_zone.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 10),
                      child: Text('Zone: $_zone', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 14))),
                  ..._cards.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _rateCard((c['vehicleType'] ?? 'Vehicle').toString(), [
                          ['Base Fare', '₹ ${c['baseFare'] ?? 0}'],
                          ['Per km', '₹ ${c['perKm'] ?? 0}'],
                          ['Per min', '₹ ${c['perMin'] ?? 0}'],
                          ['Min Fare', '₹ ${c['minFare'] ?? 0}'],
                        ]),
                      )),
                ]),
    );
  }

  Widget _rateCard(String type, List<List<String>> rates) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.directions_car, color: AppColors.primary, size: 20)),
        const SizedBox(width: 10),
        Text(type, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
      ]),
      const SizedBox(height: 12),
      Divider(color: AppColors.divider, height: 1),
      ...rates.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(r[0], style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
          Text(r[1], style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
        ]),
      )),
    ]),
  );
}

// ── Referral Page (real: admin-set rewards, code, stats) ──
class ReferralPage extends StatefulWidget {
  static const route = '/referral';
  const ReferralPage({super.key});
  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  bool _loading = true;
  String _code = '';
  num _referrerReward = 0, _refereeReward = 0, _referredCount = 0, _referralEarnings = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await DriverApiService.getReferral();
      _code = (r['code'] ?? '').toString();
      _referrerReward = (r['referrerReward'] as num?) ?? 0;
      _refereeReward = (r['refereeReward'] as num?) ?? 0;
      _referredCount = (r['referredCount'] as num?) ?? 0;
      _referralEarnings = (r['referralEarnings'] as num?) ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
  }

  void _share() {
    Clipboard.setData(ClipboardData(
      text: 'Join Gora Cabs as a driver! Use my referral code $_code while signing up and we both earn rewards.'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite text copied — paste in WhatsApp / SMS')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Refer & Earn'),
      backgroundColor: AppColors.cardBg,
      body: _loading ? const AppLoader() : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(20), width: double.infinity,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              const Icon(Icons.card_giftcard, color: Colors.white, size: 40),
              const SizedBox(height: 10),
              Text('Invite Drivers, Earn ₹${_referrerReward.toStringAsFixed(0)}!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Your friend also gets ₹${_refereeReward.toStringAsFixed(0)} on joining', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_code.isEmpty ? '—' : _code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 2)),
                  IconButton(icon: const Icon(Icons.copy, color: AppColors.primary), onPressed: _copy),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _statBox('Referrals', _referredCount.toStringAsFixed(0), Icons.group)),
            const SizedBox(width: 12),
            Expanded(child: _statBox('Earned', '₹ ${_referralEarnings.toStringAsFixed(0)}', Icons.account_balance_wallet)),
          ]),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Share Invite', onTap: _share),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14), width: double.infinity,
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How it works', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 8),
              Text('1. Share your code with a driver friend', style: TextStyle(fontSize: 12.5, color: AppColors.textGrey)),
              Text('2. They enter it while creating their profile', style: TextStyle(fontSize: 12.5, color: AppColors.textGrey)),
              Text('3. Reward is added to both wallets instantly', style: TextStyle(fontSize: 12.5, color: AppColors.textGrey)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Icon(icon, color: AppColors.primary, size: 22),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textDark)),
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
    ]),
  );
}

// ── Driver Levels Page ─────────────────────────────────
class DriverLevelsPage extends StatelessWidget {
  static const route = '/driver-levels';
  const DriverLevelsPage({super.key});
  final _levels = const [
    _Level('Bronze', '0 – 100 rides', AppColors.orange, Icons.military_tech, true),
    _Level('Silver', '101 – 300 rides', Color(0xFF9E9E9E), Icons.military_tech, false),
    _Level('Gold', '301 – 600 rides', Color(0xFFFFB300), Icons.emoji_events, false),
    _Level('Platinum', '601+ rides', AppColors.primary, Icons.workspace_premium, false),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Driver Levels'),
    backgroundColor: AppColors.cardBg,
    body: ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _levels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final l = _levels[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: l.current ? l.color.withOpacity(0.08) : AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: l.current ? Border.all(color: l.color, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
          ),
          child: Row(children: [
            Icon(l.icon, color: l.color, size: 36),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: l.current ? l.color : AppColors.textDark)),
              Text(l.range, style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
            ])),
            if (l.current)
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: l.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('CURRENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: l.color))),
          ]),
        );
      },
    ),
  );
}

class _Level {
  final String name, range; final Color color; final IconData icon; final bool current;
  const _Level(this.name, this.range, this.color, this.icon, this.current);
}

// ── Rewards Page ─────────────────────────────────────
class RewardsPage extends StatelessWidget {
  static const route = '/rewards';
  const RewardsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('My Rewards'),
    backgroundColor: AppColors.cardBg,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF6D00), Color(0xFFFF9100)]), borderRadius: BorderRadius.circular(20)),
          child: Column(children: const [
            Icon(Icons.card_giftcard, color: Colors.white, size: 40),
            SizedBox(height: 8),
            Text('2,340 Points', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
            Text('Reward Points', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'Recent Points'),
            const SizedBox(height: 12),
            _rewardRow('+50 pts', 'Trip completed', 'Today'),
            _rewardRow('+100 pts', 'Weekend bonus', 'Yesterday'),
            _rewardRow('+25 pts', 'Perfect rating', '2 days ago'),
            _rewardRow('-200 pts', 'Redeemed ₹ 20', '5 days ago'),
          ]),
        ),
      ]),
    ),
  );

  Widget _rewardRow(String pts, String desc, String time) {
    final isGain = pts.startsWith('+');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(isGain ? Icons.add_circle : Icons.remove_circle, color: isGain ? AppColors.green : AppColors.red, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(desc, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark)),
          Text(time, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ])),
        Text(pts, style: TextStyle(fontWeight: FontWeight.w700, color: isGain ? AppColors.green : AppColors.red)),
      ]),
    );
  }
}

// ── Reports Page ─────────────────────────────────────
class ReportsPage extends StatefulWidget {
  static const route = '/reports';
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  num _today = 0, _week = 0, _totalRides = 0, _totalEarnings = 0, _todayDistance = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await DriverApiService.getEarningsSummary();
      _today = (r['today'] as num?) ?? 0;
      _week = (r['week'] as num?) ?? 0;
      _totalRides = (r['totalRides'] as num?) ?? 0;
      _totalEarnings = (r['totalEarnings'] as num?) ?? 0;
      _todayDistance = (r['todayDistance'] as num?) ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('My Reports'),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]), borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  const Text('Total Earnings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('₹ ${_totalEarnings.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${_totalRides.toStringAsFixed(0)} total rides', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                child: Row(children: [
                  Expanded(child: _stat('Today', '₹${_today.toStringAsFixed(0)}', Icons.today)),
                  Expanded(child: _stat('This Week', '₹${_week.toStringAsFixed(0)}', Icons.calendar_today)),
                  Expanded(child: _stat('Total Rides', _totalRides.toStringAsFixed(0), Icons.directions_car)),
                  Expanded(child: _stat("Today's km", _todayDistance.toStringAsFixed(0), Icons.route)),
                ]),
              ),
            ]),
    );
  }

  Widget _stat(String l, String v, IconData icon) => Column(children: [
        Icon(icon, color: AppColors.primary, size: 16),
        const SizedBox(height: 4),
        Text(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textDark), textAlign: TextAlign.center),
        Text(l, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ]);
}

// ── Admin Chat Page ─────────────────────────────────────
class AdminChatPage extends StatefulWidget {
  static const route = '/admin-chat';
  const AdminChatPage({super.key});
  @override State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetch());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final r = await DriverApiService.getSupportChat();
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(
          (r['messages'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      final r = await DriverApiService.sendSupportChat(text);
      if (!mounted) return;
      final msgs = r['messages'] as List?;
      if (msgs != null) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(
            msgs.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        });
      } else {
        await _fetch();
      }
    } catch (_) {
      if (mounted) await _fetch();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Support Chat', actions: [const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14), child: CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Icon(Icons.support_agent, color: Colors.white, size: 16)))]),
    body: Column(children: [
      Expanded(
        child: _loading
            ? const AppLoader()
            : _messages.isEmpty
                ? Center(child: Text('Start a conversation with support', style: TextStyle(color: AppColors.textGrey, fontSize: 13)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isMe = m['sender'] == 'driver';
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.primary : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('${m['message'] ?? ''}', style: TextStyle(color: isMe ? Colors.white : AppColors.textDark, fontSize: 13)),
                        ),
                      );
                    },
                  ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8, top: 8),
          decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'Type message...'), onSubmitted: (_) => _send())),
            IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.primary), onPressed: _send),
          ]),
        ),
      ),
    ]),
  );
}

class _Msg { final String text; final bool isMe; const _Msg(this.text, this.isMe); }

// ── Subscription Page ─────────────────────────────────
class SubscriptionPage extends StatefulWidget {
  static const route = '/subscription';
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _loading = true;
  bool _busy = false;
  bool _rzpEnabled = false;
  Map<String, dynamic> _current = {};
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _history = [];
  num _wallet = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await DriverApiService.getSubscription();
      Map<String, dynamic> cfg = {};
      try { cfg = await DriverApiService.getPaymentConfig(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _current = (r['current'] as Map?)?.cast<String, dynamic>() ?? {};
        _plans = ((r['plans'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _history = ((r['history'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _wallet = (r['walletBalance'] as num?) ?? 0;
        _rzpEnabled = (cfg['razorpay'] is Map) && (cfg['razorpay']['enabled'] == true);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _fmtDate(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString())?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month-1]} ${d.year}';
  }

  Future<void> _buy(Map<String, dynamic> plan) async {
    final price = (plan['price'] as num?) ?? 0;
    final payLine = _rzpEnabled
        ? 'Pay ₹${price.toStringAsFixed(0)} online (UPI / card / net banking).'
        : '₹${price.toStringAsFixed(0)} will be deducted from your wallet (₹${_wallet.toStringAsFixed(0)}).';
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Buy ${plan['name']}?'),
      content: Text(payLine),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
      ],
    ));
    if (ok != true) return;
    setState(() => _busy = true);

    final planId = plan['_id'].toString();
    Map<String, dynamic> r;
    if (_rzpEnabled) {
      // Pay via Razorpay, then activate on the server after verification
      final phone = context.read<DriverProvider>().phone;
      r = await DriverPaymentService.paySubscription(planId: planId, contact: phone);
    } else {
      // No gateway configured → wallet payment
      r = await DriverApiService.buySubscription(planId);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription activated!'), backgroundColor: AppColors.green));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Failed'), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Subscription'),
    backgroundColor: AppColors.cardBg,
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20), width: double.infinity,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]), borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                const Icon(Icons.workspace_premium, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                const Text('Membership', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const Text('Subscribe & pay zero commission', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                  child: Text('Wallet: ₹${_wallet.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            // Current active plan / no-plan notice
            if (_current['active'] == true) ...[
              Container(
                padding: const EdgeInsets.all(16), width: double.infinity,
                decoration: BoxDecoration(color: AppColors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.green)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.verified, color: AppColors.green, size: 20), const SizedBox(width: 8),
                    Expanded(child: Text('Active: ${_current['planName'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 15))),
                  ]),
                  const SizedBox(height: 6),
                  Text('Valid till ${_fmtDate(_current['expiresAt'])}', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                  Text('Commission while active: ${_current['commissionPercent'] ?? 0}%', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14), width: double.infinity,
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.4))),
                child: Text('No active plan — you pay normal commission per ride. Subscribe to keep more of your earnings.',
                  style: TextStyle(color: AppColors.textDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),
            ],
            // Plans
            Text('Available Plans', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 10),
            if (_plans.isEmpty)
              Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No plans available right now', style: TextStyle(color: AppColors.textGrey))))
            else
              ..._plans.map(_planCard),
            // History
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Recent Plans', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 8),
              ..._history.map((h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h['planName']?.toString() ?? 'Plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark)),
                    Text('${_fmtDate(h['startedAt'])} → ${_fmtDate(h['expiresAt'])}', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                  ])),
                  Text('₹${(h['price'] as num?)?.toStringAsFixed(0) ?? '0'}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(width: 8),
                  _statusChip(h['status']?.toString() ?? ''),
                ]),
              )),
            ],
            const SizedBox(height: 20),
          ]),
        ),
  );

  Widget _statusChip(String s) {
    final Color c = s == 'active' ? AppColors.green : (s == 'cancelled' ? AppColors.red : AppColors.textGrey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(s.isEmpty ? '—' : s, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final benefits = ((plan['benefits'] as List?) ?? []).map((e) => e.toString()).toList();
    final price = (plan['price'] as num?) ?? 0;
    final days = (plan['durationDays'] as num?)?.toInt() ?? 0;
    final comm = (plan['commissionPercentWhileActive'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(plan['name']?.toString() ?? 'Plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark))),
          Text('₹${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
        ]),
        Text('$days days • ${comm == 0 ? 'Zero commission' : '$comm% commission'}', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
        if ((plan['description']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(plan['description'].toString(), style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        ...benefits.map((f) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(f, style: TextStyle(fontSize: 13, color: AppColors.textDark))),
        ]))),
        const SizedBox(height: 12),
        PrimaryButton(label: 'Subscribe Now', loading: _busy, onTap: () => _buy(plan)),
      ]),
    );
  }
}

// ── Vehicle Info Page ─────────────────────────────────
class VehicleInfoPage extends StatelessWidget {
  static const route = '/vehicle-info';
  const VehicleInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DriverProvider>();
    return Scaffold(
      appBar: blueAppBar('Vehicle Info'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Icon(Icons.directions_car, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                dp.vehicleModel.isNotEmpty ? dp.vehicleModel : 'Vehicle',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              Text(
                dp.vehicleNumber.isNotEmpty ? dp.vehicleNumber : '—',
                style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 2),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)]),
            child: Column(children: [
              _row('Vehicle Model', dp.vehicleModel.isNotEmpty ? dp.vehicleModel : '—'),
              Divider(color: AppColors.divider, height: 20),
              _row('Registration No.', dp.vehicleNumber.isNotEmpty ? dp.vehicleNumber : '—'),
              Divider(color: AppColors.divider, height: 20),
              _row('Vehicle Type', dp.vehicleType.isNotEmpty ? dp.vehicleType : '—'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
    ],
  );
}
