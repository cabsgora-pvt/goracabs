// All smaller pages in one file
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';
import '../../../providers/driver_provider.dart';

// ── QR Code Page ─────────────────────────────────────
class QrCodePage extends StatelessWidget {
  static const route = '/qr-code';
  const QrCodePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('My QR Code'),
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 220, height: 220, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)]),
        child: CustomPaint(painter: _QRPainter()),
      ),
      const SizedBox(height: 24),
      const Text('DRV001 • Rajesh Kumar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
      const Text('Scan to identify driver', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
      const SizedBox(height: 32),
      PrimaryButton(label: 'Share QR Code', width: 200, onTap: () {}),
    ])),
  );
}

class _QRPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.textDark..style = PaintingStyle.fill;
    const cell = 9.0;
    final cols = (size.width / cell).floor();
    final rows = (size.height / cell).floor();
    final pattern = [1,0,1,1,0,1,0,1,1,0,1,0,1,1,0,1,0,1,1,0];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (pattern[(r * cols + c) % pattern.length] == 1) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell - 1, cell - 1), p);
        }
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

// ── Rate Card Page ─────────────────────────────────────
class RateCardPage extends StatelessWidget {
  static const route = '/rate-card';
  const RateCardPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Rate Card'),
    backgroundColor: AppColors.cardBg,
    body: ListView(padding: const EdgeInsets.all(16), children: [
      _rateCard(context, 'Sedan', [['Base Fare', '₹ 50'], ['Per km', '₹ 12'], ['Per min', '₹ 1.5'], ['Min Fare', '₹ 80']]),
      const SizedBox(height: 12),
      _rateCard(context, 'SUV / Prime', [['Base Fare', '₹ 80'], ['Per km', '₹ 18'], ['Per min', '₹ 2'], ['Min Fare', '₹ 120']]),
      const SizedBox(height: 12),
      _rateCard(context, 'Auto', [['Base Fare', '₹ 30'], ['Per km', '₹ 8'], ['Per min', '₹ 1'], ['Min Fare', '₹ 50']]),
    ]),
  );

  Widget _rateCard(BuildContext context, String type, List<List<String>> rates) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.directions_car, color: AppColors.primary, size: 20)),
        const SizedBox(width: 10),
        Text(type, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
      ]),
      const SizedBox(height: 12),
      const Divider(color: AppColors.divider, height: 1),
      ...rates.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(r[0], style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
          Text(r[1], style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
        ]),
      )),
    ]),
  );
}

// ── Referral Page ─────────────────────────────────────
class ReferralPage extends StatelessWidget {
  static const route = '/referral';
  const ReferralPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Refer & Earn'),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: [
            const Icon(Icons.share, color: Colors.white, size: 40),
            const SizedBox(height: 12),
            const Text('Invite Drivers, Earn ₹200!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text('For every driver you refer who completes 10 rides', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('GORA-DRV-2025', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 2)),
                IconButton(icon: const Icon(Icons.copy, color: AppColors.primary), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            const SectionHeader(title: 'Your Referrals'),
            const SizedBox(height: 12),
            _refRow('Suresh Kumar', 'Completed 10 rides', '₹ 200', true),
            const Divider(color: AppColors.divider),
            _refRow('Ankit Shah', '3/10 rides completed', 'Pending', false),
          ]),
        ),
      ]),
    ),
  );

  Widget _refRow(String name, String status, String reward, bool paid) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text(name[0], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 13)),
        Text(status, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
      ])),
      Text(reward, style: TextStyle(fontWeight: FontWeight.w700, color: paid ? AppColors.green : AppColors.textGrey, fontSize: 13)),
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
              Text(l.range, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
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
          Text(desc, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark)),
          Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ])),
        Text(pts, style: TextStyle(fontWeight: FontWeight.w700, color: isGain ? AppColors.green : AppColors.red)),
      ]),
    );
  }
}

// ── Reports Page ─────────────────────────────────────
class ReportsPage extends StatelessWidget {
  static const route = '/reports';
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('My Reports'),
    backgroundColor: AppColors.cardBg,
    body: ListView(padding: const EdgeInsets.all(16), children: [
      _reportCard('May 2025', '52 rides', '₹ 28,350', '647 km', '4.8 ⭐'),
      const SizedBox(height: 12),
      _reportCard('Apr 2025', '48 rides', '₹ 25,100', '581 km', '4.7 ⭐'),
      const SizedBox(height: 12),
      _reportCard('Mar 2025', '61 rides', '₹ 33,200', '774 km', '4.9 ⭐'),
    ]),
  );

  Widget _reportCard(String month, String rides, String earnings, String distance, String rating) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(month, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _stat('Rides', rides, Icons.directions_car)),
        Expanded(child: _stat('Earned', earnings, Icons.currency_rupee)),
        Expanded(child: _stat('Distance', distance, Icons.route)),
        Expanded(child: _stat('Rating', rating, Icons.star)),
      ]),
    ]),
  );

  Widget _stat(String l, String v, IconData icon) => Column(children: [
    Icon(icon, color: AppColors.primary, size: 16),
    const SizedBox(height: 4),
    Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textDark), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
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
  final _msgs = [
    _Msg('Hello! How can I help you today?', false),
    _Msg('My payment for trip T2005 was not received.', true),
    _Msg('I\'m sorry for the inconvenience. I\'m checking your account now.', false),
    _Msg('Please allow 24 hours for the payment to reflect.', false),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Support Chat', actions: [const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14), child: CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Icon(Icons.support_agent, color: Colors.white, size: 16)))]),
    body: Column(children: [
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _msgs.length,
        itemBuilder: (_, i) {
          final m = _msgs[i];
          return Align(
            alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
              decoration: BoxDecoration(
                color: m.isMe ? AppColors.primary : AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(m.text, style: TextStyle(color: m.isMe ? Colors.white : AppColors.textDark, fontSize: 13)),
            ),
          );
        },
      )),
      Container(
        padding: EdgeInsets.only(left: 16, right: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 12, top: 8),
        decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'Type message...'))),
          IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.primary), onPressed: () {
            if (_ctrl.text.isNotEmpty) {
              setState(() { _msgs.add(_Msg(_ctrl.text, true)); _ctrl.clear(); });
            }
          }),
        ]),
      ),
    ]),
  );
}

class _Msg { final String text; final bool isMe; const _Msg(this.text, this.isMe); }

// ── Subscription Page ─────────────────────────────────
class SubscriptionPage extends StatelessWidget {
  static const route = '/subscription';
  const SubscriptionPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: blueAppBar('Subscription'),
    backgroundColor: AppColors.cardBg,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(20), width: double.infinity,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Icon(Icons.workspace_premium, color: Colors.white, size: 40),
            const SizedBox(height: 8),
            const Text('Choose Your Plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const Text('Unlock unlimited rides', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 16),
        _planCard(context, 'Weekly', '₹ 199', '7 days', ['Unlimited rides', 'Priority support'], false),
        const SizedBox(height: 10),
        _planCard(context, 'Monthly', '₹ 599', '30 days', ['Unlimited rides', 'Priority support', '20% bonus rides'], true),
        const SizedBox(height: 10),
        _planCard(context, 'Quarterly', '₹ 1,499', '90 days', ['Unlimited rides', 'Priority support', '30% bonus rides', 'Gold badge'], false),
      ]),
    ),
  );

  Widget _planCard(BuildContext context, String name, String price, String duration, List<String> features, bool popular) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: popular ? AppColors.primary.withOpacity(0.05) : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: popular ? Border.all(color: AppColors.primary, width: 1.5) : null,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        if (popular) ...[
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)), child: const Text('POPULAR', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700))),
        ],
        const Spacer(),
        Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
      ]),
      Text(duration, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
      const SizedBox(height: 10),
      ...features.map((f) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
        const Icon(Icons.check_circle, color: AppColors.green, size: 16),
        const SizedBox(width: 6),
        Text(f, style: const TextStyle(fontSize: 13, color: AppColors.textDark)),
      ]))),
      const SizedBox(height: 12),
      PrimaryButton(label: 'Subscribe Now', onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscribed successfully!'), backgroundColor: AppColors.green))),
    ]),
  );
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
              const Divider(color: AppColors.divider, height: 20),
              _row('Registration No.', dp.vehicleNumber.isNotEmpty ? dp.vehicleNumber : '—'),
              const Divider(color: AppColors.divider, height: 20),
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
      Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
    ],
  );
}
