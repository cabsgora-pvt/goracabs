import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers & Promos'),
        elevation: 0,
        centerTitle: false,
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: Theme.of(context).cardColor,
              child: const TabBar(
                labelColor: AppTheme.primaryBlue,
                unselectedLabelColor: AppTheme.textGrey,
                indicatorColor: AppTheme.primaryBlue,
                tabs: [
                  Tab(text: 'Active Offers'),
                  Tab(text: 'Promo Codes'),
                  Tab(text: 'Referral'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildActiveOffers(context),
                  _buildPromoCodes(context),
                  _buildReferral(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOffers(BuildContext context) {
    final offers = [
      {
        'title': '50% OFF on First Ride',
        'desc': 'Get flat 50% discount on your first ride with Gora Cabs',
        'code': 'FIRST50',
        'validity': 'Valid till 31 Dec 2024',
        'color': '0xFF0052CC',
        'icon': Icons.local_taxi,
      },
      {
        'title': 'Flat ₹100 Cashback',
        'desc': 'Add ₹500 or more to wallet and get ₹100 cashback',
        'code': 'WALLET100',
        'validity': 'Valid till 28 Feb 2024',
        'color': '0xFFE65100',
        'icon': Icons.account_balance_wallet,
      },
      {
        'title': 'Weekend Special',
        'desc': 'Get 30% off on all rides during weekends',
        'code': 'WEEKEND30',
        'validity': 'Valid on Sat & Sun',
        'color': '0xFF2E7D32',
        'icon': Icons.celebration,
      },
      {
        'title': 'Outstation Offer',
        'desc': 'Save ₹500 on outstation trips above ₹2000',
        'code': 'OUTSTATION500',
        'validity': 'Valid till 15 Mar 2024',
        'color': '0xFF6A1B9A',
        'icon': Icons.route,
      },
      {
        'title': 'Rental Package Deal',
        'desc': 'Book 8hr rental and get 2hr extra free',
        'code': 'RENTAL2HR',
        'validity': 'Valid for 7 days',
        'color': '0xFFD84315',
        'icon': Icons.schedule,
      },
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final offer = offers[i];
        final color = Color(int.parse(offer['color'] as String));
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withAlpha(180)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: color.withAlpha(60), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Icon(offer['icon'] as IconData, size: 120, color: Colors.white.withAlpha(20)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(offer['icon'] as IconData, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            offer['title'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      offer['desc'] as String,
                      style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                offer['code'] as String,
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: offer['code'] as String));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Code ${offer['code']} copied!')),
                                  );
                                },
                                child: Icon(Icons.copy, size: 16, color: color),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          offer['validity'] as String,
                          style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Offer ${offer['code']} applied!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: color,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Apply Offer', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPromoCodes(BuildContext context) {
    final promoCodes = [
      {'code': 'GORA50', 'desc': '50% off up to ₹100', 'type': 'Ride'},
      {'code': 'NEWUSER', 'desc': 'Flat ₹150 off on first ride', 'type': 'Ride'},
      {'code': 'SAVE20', 'desc': '20% off up to ₹50', 'type': 'Ride'},
      {'code': 'WALLET200', 'desc': '₹200 cashback on wallet recharge', 'type': 'Wallet'},
      {'code': 'DELIVERY50', 'desc': 'Free delivery on orders above ₹200', 'type': 'Delivery'},
    ];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryBlue.withAlpha(60)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enter promo code at checkout to avail discount',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: promoCodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final promo = promoCodes[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_offer, color: AppTheme.primaryBlue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                promo['code']!,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  promo['type']!,
                                  style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(promo['desc']!, style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: promo['code']!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Code ${promo['code']} copied!')),
                        );
                      },
                      child: const Text('Copy', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReferral(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryBlue, AppTheme.primaryBlue.withAlpha(200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.card_giftcard, color: Colors.white, size: 60),
                const SizedBox(height: 16),
                const Text(
                  'Refer & Earn',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Invite your friends and earn ₹100 for each successful referral',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text('Your Referral Code', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'JOHN2024',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, letterSpacing: 2),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: 'JOHN2024'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Referral code copied!')),
                              );
                            },
                            icon: const Icon(Icons.copy, color: AppTheme.primaryBlue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share functionality will be implemented')),
                    );
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share with Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryBlue,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                const Text('Your Referral Stats', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn('Total Referrals', '12', Icons.people),
                    Container(width: 1, height: 50, color: Colors.grey[300]),
                    _buildStatColumn('Earnings', '₹1,200', Icons.currency_rupee),
                    Container(width: 1, height: 50, color: Colors.grey[300]),
                    _buildStatColumn('Pending', '3', Icons.hourglass_empty),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('How it Works', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildHowItWorksStep('1', 'Share your referral code', 'Send your unique code to friends'),
          const SizedBox(height: 12),
          _buildHowItWorksStep('2', 'Friend signs up', 'They register using your code'),
          const SizedBox(height: 12),
          _buildHowItWorksStep('3', 'Friend completes ride', 'They take their first ride'),
          const SizedBox(height: 12),
          _buildHowItWorksStep('4', 'You both earn', 'Get ₹100 in your wallet'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Referral bonus will be credited within 24 hours after successful ride completion',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryBlue, size: 28),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
      ],
    );
  }

  Widget _buildHowItWorksStep(String number, String title, String desc) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
            ],
          ),
        ),
      ],
    );
  }
}
