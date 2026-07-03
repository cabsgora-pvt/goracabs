import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';
import '../../earnings/pages/earnings_page.dart';
import '../../history/pages/history_page.dart';
import '../../wallet/pages/wallet_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DriverProvider>();
    final picUrl = dp.profilePicUrl;
    final displayName = dp.name.isNotEmpty ? dp.name : 'Driver';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primary,
            automaticallyImplyLeading: false,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                tooltip: 'Edit profile',
                onPressed: () => Navigator.pushNamed(context, '/profile'),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient backdrop
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  // Soft decorative circles
                  Positioned(
                    top: -40, right: -30,
                    child: Container(width: 160, height: 160,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle)),
                  ),
                  Positioned(
                    bottom: -50, left: -40,
                    child: Container(width: 180, height: 180,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle)),
                  ),
                  // Profile content
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Avatar with white ring + camera badge
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/profile'),
                            child: Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))],
                                  ),
                                  child: CircleAvatar(
                                    radius: 38,
                                    backgroundColor: Colors.white.withOpacity(0.18),
                                    backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                                    child: picUrl.isEmpty
                                        ? Text(displayName[0].toUpperCase(),
                                            style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.w800))
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0, right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white, shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 14, color: AppColors.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Name + verified tick
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, color: Colors.white, size: 18),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Phone pill
                          if (dp.phone.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.phone, size: 11, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text('+91 ${dp.phone}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          // Rating + rides chips
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _HeaderChip(icon: Icons.star_rounded, iconColor: AppColors.orange,
                                label: dp.rating.toString() == '0' ? 'New' : dp.rating),
                              const SizedBox(width: 8),
                              _HeaderChip(icon: Icons.directions_car_rounded, iconColor: Colors.white,
                                label: '${dp.totalRides} rides'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Quick stats
                Row(children: [
                  Expanded(child: _QuickStat(label: 'Balance', value: '₹ 2,450', icon: Icons.account_balance_wallet, color: AppColors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickStat(label: 'Rating', value: dp.rating, icon: Icons.star, color: AppColors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: _QuickStat(label: 'Rides', value: dp.totalRides, icon: Icons.directions_car, color: AppColors.primary)),
                ]),
                const SizedBox(height: 20),

                _Section('Activity'),
                MenuRow(icon: Icons.history, label: 'Trip History', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
                MenuRow(icon: Icons.bar_chart, label: 'Earnings', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsPage()))),
                MenuRow(icon: Icons.account_balance_wallet, label: 'Wallet', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()))),

                const SizedBox(height: 8),
                _Section('Driver Info'),
                MenuRow(icon: Icons.person, label: 'Profile', onTap: () => Navigator.pushNamed(context, '/profile')),
                MenuRow(icon: Icons.directions_car, label: 'Vehicle Info', onTap: () => Navigator.pushNamed(context, '/vehicle-info')),
                MenuRow(icon: Icons.folder, label: 'Documents', onTap: () => Navigator.pushNamed(context, '/documents')),
                MenuRow(icon: Icons.qr_code, label: 'My QR Code', onTap: () => Navigator.pushNamed(context, '/qr-code')),

                const SizedBox(height: 8),
                _Section('Rewards & Growth'),
                MenuRow(icon: Icons.leaderboard, label: 'Leaderboard', onTap: () => Navigator.pushNamed(context, '/leaderboard'), iconColor: AppColors.orange),
                MenuRow(icon: Icons.share, label: 'Refer & Earn', onTap: () => Navigator.pushNamed(context, '/referral'), iconColor: AppColors.orange),

                const SizedBox(height: 8),
                _Section('Support'),
                MenuRow(icon: Icons.receipt_long, label: 'Rate Card', onTap: () => Navigator.pushNamed(context, '/rate-card')),
                MenuRow(icon: Icons.bar_chart_outlined, label: 'Reports', onTap: () => Navigator.pushNamed(context, '/reports')),
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

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  const _HeaderChip({required this.icon, required this.iconColor, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white24, width: 0.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 14),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    ),
  );
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
