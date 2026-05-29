import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';
import '../../earnings/pages/earnings_page.dart';
import '../../history/pages/history_page.dart';
import '../../wallet/pages/wallet_page.dart';
import '../../notifications/pages/notification_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final d = mockDriver;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircleAvatar(radius: 40, backgroundColor: Colors.white24,
                      child: Text(d.name[0], style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(height: 10),
                    Text(d.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.star, color: AppColors.orange, size: 16),
                      Text(' ${d.rating}  •  ${d.totalRides} rides', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                    ]),
                  ]),
                ),
              ),
            ),
            title: const Text('Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Quick stats
                Row(children: [
                  Expanded(child: _QuickStat(label: 'Balance', value: '₹ 2,450', icon: Icons.account_balance_wallet, color: AppColors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickStat(label: 'Rating', value: d.rating, icon: Icons.star, color: AppColors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickStat(label: 'Rides', value: d.totalRides, icon: Icons.directions_car, color: AppColors.primary)),
                ]),
                const SizedBox(height: 20),

                _Section('Activity'),
                MenuRow(icon: Icons.history, label: 'Trip History', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
                MenuRow(icon: Icons.bar_chart, label: 'Earnings', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsPage()))),
                MenuRow(icon: Icons.account_balance_wallet, label: 'Wallet', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()))),
                MenuRow(icon: Icons.notifications, label: 'Notifications', onTap: () => Navigator.pushNamed(context, '/notifications')),

                const SizedBox(height: 8),
                _Section('Driver Info'),
                MenuRow(icon: Icons.person, label: 'Profile', onTap: () => Navigator.pushNamed(context, '/profile')),
                MenuRow(icon: Icons.directions_car, label: 'Vehicle Info', onTap: () => Navigator.pushNamed(context, '/vehicle-info')),
                MenuRow(icon: Icons.folder, label: 'Documents', onTap: () => Navigator.pushNamed(context, '/documents')),
                MenuRow(icon: Icons.qr_code, label: 'My QR Code', onTap: () => Navigator.pushNamed(context, '/qr-code')),

                const SizedBox(height: 8),
                _Section('Rewards & Growth'),
                MenuRow(icon: Icons.celebration, label: 'Incentives', onTap: () => Navigator.pushNamed(context, '/incentives'), iconColor: AppColors.orange),
                MenuRow(icon: Icons.leaderboard, label: 'Leaderboard', onTap: () => Navigator.pushNamed(context, '/leaderboard'), iconColor: AppColors.orange),
                MenuRow(icon: Icons.military_tech, label: 'Driver Levels', onTap: () => Navigator.pushNamed(context, '/driver-levels'), iconColor: AppColors.orange),
                MenuRow(icon: Icons.card_giftcard, label: 'Rewards', onTap: () => Navigator.pushNamed(context, '/rewards'), iconColor: AppColors.orange),
                MenuRow(icon: Icons.share, label: 'Refer & Earn', onTap: () => Navigator.pushNamed(context, '/referral'), iconColor: AppColors.orange),

                const SizedBox(height: 8),
                _Section('Support'),
                MenuRow(icon: Icons.receipt_long, label: 'Rate Card', onTap: () => Navigator.pushNamed(context, '/rate-card')),
                MenuRow(icon: Icons.bar_chart_outlined, label: 'Reports', onTap: () => Navigator.pushNamed(context, '/reports')),
                MenuRow(icon: Icons.sos, label: 'SOS Contacts', onTap: () => Navigator.pushNamed(context, '/sos'), iconColor: AppColors.red),
                MenuRow(icon: Icons.chat, label: 'Chat with Support', onTap: () => Navigator.pushNamed(context, '/admin-chat')),
                MenuRow(icon: Icons.support_agent, label: 'Support Tickets', onTap: () => Navigator.pushNamed(context, '/support-tickets')),

                const SizedBox(height: 8),
                _Section('General'),
                MenuRow(icon: Icons.tune, label: 'Preferences', onTap: () => Navigator.pushNamed(context, '/preferences')),
                MenuRow(icon: Icons.subscriptions, label: 'Subscription', onTap: () => Navigator.pushNamed(context, '/subscription')),
                MenuRow(icon: Icons.settings, label: 'Settings', onTap: () => Navigator.pushNamed(context, '/settings')),
                MenuRow(icon: Icons.logout, label: 'Logout', onTap: () => _confirmLogout(context), iconColor: AppColors.red),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _Section(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textGrey, letterSpacing: 0.5)),
  );

  void _confirmLogout(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Logout?', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }
}

class _QuickStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickStat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
    ]),
  );
}
