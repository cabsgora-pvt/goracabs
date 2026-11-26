import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/session.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
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
    // Live figures only. Balance comes from GET /auth/driver/wallet — the same
    // call the Wallet page shows — via DriverProvider.refreshBalance. Rating is
    // the driver's server-side average, which /rides/:id/rate recomputes; the
    // home screen refreshes the profile each time this tab is opened so a new
    // rating shows without a restart.
    final ratingNum = double.tryParse(dp.rating) ?? 0;
    final ratingLabel = ratingNum > 0 ? ratingNum.toStringAsFixed(1) : 'New';
    final balanceLabel = dp.balanceLoaded ? '₹ ${dp.walletBalance.toStringAsFixed(2)}' : '—';
    final vehicleLine = [dp.vehicleModel, dp.vehicleType].where((s) => s.trim().isNotEmpty).join(' · ');

    void go(String route) => Navigator.pushNamed(context, route);
    void push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: Cap.tile,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              Expanded(child: Text('Account', style: Cap.display(size: 30))),
              CapRoundAction(
                icon: Icons.edit_outlined,
                size: 40,
                background: Cap.surface,
                tooltip: 'Edit profile',
                onTap: () => go('/profile'),
              ),
            ]),
            const SizedBox(height: 14),

            // ── Profile header: gradient hero card ──
            CapHeroCard(
              onTap: () => go('/profile'),
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                    ),
                    child: CapAvatar(name: displayName, url: picUrl, radius: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('CAPTAIN', style: Cap.overline(size: 10.5, color: Colors.white70)),
                      const SizedBox(height: 2),
                      Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Cap.display(size: 23, color: Colors.white)),
                      if (dp.phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text('+91 ${dp.phone}', maxLines: 1,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        CapHeroPill(icon: Icons.star_rounded, iconColor: Cap.amber, label: ratingLabel),
                        CapHeroPill(icon: Icons.route_rounded, label: '${dp.totalRides} trips'),
                      ]),
                    ]),
                  ),
                ]),
                if (vehicleLine.isNotEmpty || dp.vehicleNumber.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.directions_car_rounded, size: 20, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(vehicleLine.isNotEmpty ? vehicleLine : 'Your vehicle',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      if (dp.vehicleNumber.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _Plate(dp.vehicleNumber),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            // ── Quick stats ──
            Row(children: [
              Expanded(child: _QuickStat(label: 'Wallet', icon: Icons.account_balance_wallet_rounded, value: balanceLabel, onTap: () => push(const WalletPage()))),
              const SizedBox(width: 10),
              Expanded(child: _QuickStat(label: 'Rating', icon: Icons.star_rounded, value: ratingLabel)),
              const SizedBox(width: 10),
              Expanded(child: _QuickStat(label: 'Trips', icon: Icons.route_rounded, value: dp.totalRides, onTap: () => push(const HistoryPage()))),
            ]),

            CapMenuGroup(title: 'Earnings & money', children: [
              CapMenuRow(icon: Icons.bar_chart_rounded, label: 'Earnings', onTap: () => push(const EarningsPage())),
              CapMenuRow(icon: Icons.account_balance_wallet_outlined, label: 'Wallet', sub: dp.balanceLoaded ? 'Balance $balanceLabel' : null,
                  onTap: () => push(const WalletPage())),
              CapMenuRow(icon: Icons.history_rounded, label: 'Trip history', onTap: () => push(const HistoryPage())),
              CapMenuRow(icon: Icons.emoji_events_outlined, label: 'Incentives', onTap: () => go('/incentives')),
              CapMenuRow(icon: Icons.workspace_premium_outlined, label: 'Subscription', onTap: () => go('/subscription')),
              CapMenuRow(icon: Icons.receipt_long_outlined, label: 'Rate card', onTap: () => go('/rate-card')),
              CapMenuRow(icon: Icons.insert_chart_outlined_rounded, label: 'Reports', onTap: () => go('/reports')),
            ]),

            CapMenuGroup(title: 'Profile & vehicle', children: [
              CapMenuRow(icon: Icons.person_outline_rounded, label: 'Profile', onTap: () => go('/profile')),
              CapMenuRow(icon: Icons.directions_car_outlined, label: 'Vehicle', onTap: () => go('/vehicle-info')),
              CapMenuRow(icon: Icons.map_outlined, label: 'My zone', sub: dp.zoneName.isNotEmpty ? dp.zoneName : null,
                  onTap: () => go('/zone')),
              CapMenuRow(icon: Icons.folder_outlined, label: 'Documents', onTap: () => go('/documents')),
              CapMenuRow(icon: Icons.badge_outlined, label: 'ID card', onTap: () => go('/id-card')),
              CapMenuRow(icon: Icons.qr_code_2_rounded, label: 'Payment QR code', onTap: () => go('/qr-code')),
            ]),

            CapMenuGroup(title: 'Rewards', children: [
              CapMenuRow(icon: Icons.leaderboard_outlined, label: 'Leaderboard', onTap: () => go('/leaderboard')),
              CapMenuRow(icon: Icons.card_giftcard_rounded, label: 'Refer & earn', onTap: () => go('/referral')),
            ]),

            CapMenuGroup(title: 'Safety & help', children: [
              CapMenuRow(icon: Icons.sos_rounded, label: 'SOS contacts', iconColor: AppColors.red, onTap: () => go('/sos')),
              CapMenuRow(icon: Icons.chat_bubble_outline_rounded, label: 'Chat with support', onTap: () => go('/admin-chat')),
              CapMenuRow(icon: Icons.support_agent_rounded, label: 'Support tickets', onTap: () => go('/support-tickets')),
              CapMenuRow(icon: Icons.help_outline_rounded, label: 'Help & FAQ', onTap: () => go('/faq')),
            ]),

            CapMenuGroup(title: 'App', children: [
              CapMenuRow(icon: Icons.tune_rounded, label: 'Trip preferences', onTap: () => go('/preferences')),
              CapMenuRow(icon: Icons.settings_outlined, label: 'Settings', onTap: () => go('/settings')),
              CapMenuRow(icon: Icons.person_remove_outlined, label: 'Delete account', onTap: () => go('/delete-account')),
              CapMenuRow(icon: Icons.logout_rounded, label: 'Logout', danger: true, onTap: () => _confirmLogout(context)),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Logout?'),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
    if (ok != true || !context.mounted) return;
    // This used to only open the login screen: the token stayed saved, the
    // online service kept running and the server still had the driver online.
    // Now: offline on the server, service stopped, session cleared, then login.
    context.read<DriverProvider>().clear();
    await Session.logout(context: context);
  }
}

/// Number-plate styled box.
class _Plate extends StatelessWidget {
  final String number;
  const _Plate(this.number);
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 140),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF111111), width: 1.4),
      ),
      child: Text(number.toUpperCase(),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF111111), fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
    ),
  );
}

class _QuickStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;
  const _QuickStat({required this.label, required this.value, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => CapCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(12, 12, 10, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: Cap.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: Cap.accent),
      ),
      const SizedBox(height: 10),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, maxLines: 1, style: Cap.display(size: 19)),
      ),
      const SizedBox(height: 3),
      Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.overline(size: 10)),
    ]),
  );
}
