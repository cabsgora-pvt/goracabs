import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/pending_coupon.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  Map<String, dynamic>? _cfg;
  // null while the admin's offers / coupons are loading; false when the
  // config could not be fetched (offline) - never a made-up list any more.
  bool? _cfgLoaded;
  Map<String, dynamic>? _referral;
  bool _referralFailed = false;
  String? get _referralCode => _referral?['code'] as String?;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    ApiService.getReferral().then((r) {
      if (!mounted) return;
      if (r['code'] == null) {
        setState(() => _referralFailed = true);
      } else {
        setState(() => _referral = r);
      }
    }).catchError((_) {
      if (mounted) setState(() => _referralFailed = true);
    });
  }

  Future<void> _loadConfig({bool force = false}) async {
    if (force) setState(() => _cfgLoaded = null);
    Map<String, dynamic> c;
    try {
      c = await ApiService.getAppConfig(force: force);
    } catch (_) {
      c = const {};
    }
    if (!mounted) return;
    // getAppConfig answers {} when the server could not be reached.
    setState(() {
      _cfg = c;
      _cfgLoaded = c.isNotEmpty;
    });
  }

  /// "Apply": keeps [code] for the next booking. That booking's coupon pill
  /// (PaymentCouponBar) checks it against the trip with the server and shows
  /// the real discount - or why it does not apply.
  Future<void> _applyForNextRide(String code, {String service = ''}) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    await PendingCoupon.save(c, service: service);
    await Clipboard.setData(ClipboardData(text: c));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$c will be applied to your next booking - the discount is confirmed on the fare screen.'),
    ));
  }

  /// Spinner, or the "couldn't load" / "nothing here" line, or null when
  /// there is a list to show.
  Widget? _stateFor(bool empty, {required String emptyTitle, required String emptySub}) {
    if (_cfgLoaded == null) {
      return const Center(key: ValueKey('offers-loading'), child: CircularProgressIndicator());
    }
    if (_cfgLoaded == false) {
      return _message(Icons.cloud_off_rounded, "Couldn't load offers",
          'Check your internet connection and try again.', retry: true);
    }
    if (empty) return _message(Icons.local_offer_outlined, emptyTitle, emptySub);
    return null;
  }

  Widget _message(IconData icon, String title, String sub, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppTheme.textGrey),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
            if (retry) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('offers-retry'),
                onPressed: () => _loadConfig(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ]),
        ),
      );

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
    // Only what the admin configured. A hard-coded list of codes (FIRST50,
    // WALLET100 ... "valid till 2024") used to show whenever there was none -
    // expired codes the server would refuse.
    final cfgOffers = (_cfg?['offers'] as List?)
            ?.where((o) => o is Map && o['isActive'] != false)
            .toList() ??
        const [];

    const palette = [
      '0xFF0052CC',
      '0xFFE65100',
      '0xFF2E7D32',
      '0xFF6A1B9A',
      '0xFFD84315',
    ];
    final offers = <Map<String, dynamic>>[];
    for (var i = 0; i < cfgOffers.length; i++) {
      final o = cfgOffers[i] as Map;
      offers.add({
        'title': (o['title'] ?? '').toString(),
        'desc': (o['desc'] ?? '').toString(),
        'imageUrl': (o['imageUrl'] ?? '').toString(),
        'code': (o['code'] ?? '').toString(),
        'service': (o['service'] ?? '').toString(),
        'validity': (o['validity'] ?? '').toString(),
        'color': palette[i % palette.length],
        'icon': Icons.local_offer,
      });
    }
    final state = _stateFor(offers.isEmpty,
        emptyTitle: 'No offers right now',
        emptySub: 'New offers from Gora will show up here.');
    if (state != null) return state;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final offer = offers[i];
        final color = offerColor(offer['color']);
        final code = (offer['code'] as String?) ?? '';
        final validity = (offer['validity'] as String?) ?? '';
        final imageUrl = (offer['imageUrl'] as String?) ?? '';
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
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          imageUrl,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      offer['desc'] as String,
                      style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 14),
                    ),
                    if (code.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      // The code chip and the validity text were both unbounded
                      // either side of a Spacer, so a long promo code with a
                      // long validity line overflowed by up to 176px. Both are
                      // flexible now and ellipsise instead of pushing out.
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                  code,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: code));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Code $code copied!')),
                                    );
                                  },
                                  child: Icon(Icons.copy, size: 16, color: color),
                                ),
                              ],
                            ),
                          ),
                          ),
                          const SizedBox(width: 8),
                          if (validity.isNotEmpty)
                            Flexible(
                              child: Text(
                                validity,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11.5),
                              ),
                            ),
                        ],
                      ),
                    ],
                    // An offer with a code is applied to the next booking (and
                    // checked there by the server); one without a code is just
                    // news - no button pretending to apply it.
                    if (code.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _applyForNextRide(code,
                            service: (offer['service'] as String?) ?? ''),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: color,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Apply to next ride', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
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
    final promoCodes = activeCoupons(_cfg?['coupons']);
    final state = _stateFor(promoCodes.isEmpty,
        emptyTitle: 'No promo codes right now',
        emptySub: 'Codes from Gora will show up here.');
    if (state != null) return state;

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
                  'Tap Apply and the code is used on your next booking - the discount is confirmed on the fare screen.',
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
            separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                              Flexible(
                                child: Text(
                                  promo['code']!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                                ),
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
                                  style: TextStyle(fontSize: 11.5, color: Colors.green[800], fontWeight: FontWeight.bold),
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
                      key: ValueKey('apply-${promo['code']}'),
                      onPressed: () => _applyForNextRide(promo['code']!, service: promo['service'] ?? ''),
                      child: const Text('Apply', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
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
    final referral = (_cfg?['referral'] as Map?) ?? const {};
    final rewardAmount = (referral['rewardAmount'] as num?) ?? 100;
    final rewardText = '₹${rewardAmount % 1 == 0 ? rewardAmount.toInt() : rewardAmount}';
    final referralMessage = (referral['message'] as String?)?.trim().isNotEmpty == true
        ? referral['message'] as String
        : 'Invite your friends and earn $rewardText for each successful referral';
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
                  referralMessage,
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
                          Text(
                            _referralCode ?? (_referralFailed ? '—' : '…'),
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, letterSpacing: 2),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: _referralCode == null ? null : () {
                              Clipboard.setData(ClipboardData(text: _referralCode!));
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
                  onPressed: _referralCode == null ? null : () {
                    Share.share(
                      'Ride with Gora Cabs! Use my code $_referralCode when you sign up and we both earn $rewardText — download the app to get started.',
                      subject: 'Join me on Gora Cabs',
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
                    _buildStatColumn('Total Referrals', '${_referral?['referredCount'] ?? (_referralFailed ? '—' : '…')}', Icons.people),
                    Container(width: 1, height: 50, color: Colors.grey[300]),
                    _buildStatColumn('Earnings', _referral != null ? '₹${_referral!['referralEarnings']}' : (_referralFailed ? '—' : '…'), Icons.currency_rupee),
                    Container(width: 1, height: 50, color: Colors.grey[300]),
                    _buildStatColumn('Per Referral', rewardText, Icons.redeem),
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
          _buildHowItWorksStep('4', 'You both earn', 'Get $rewardText in your wallet'),
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
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
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

/// The admin's active, unexpired coupons as rows for the Promo Codes tab:
/// {code, desc, type (label), service (as the booking screens name it)}.
/// Codes without text and ones past their `expiry` are left out.
List<Map<String, String>> activeCoupons(dynamic raw, {DateTime? now}) {
  if (raw is! List) return const [];
  final at = now ?? DateTime.now();
  final out = <Map<String, String>>[];
  for (final c in raw) {
    if (c is! Map || c['isActive'] == false) continue;
    final code = (c['code'] ?? '').toString().trim();
    if (code.isEmpty) continue;
    final exp = DateTime.tryParse((c['expiry'] ?? '').toString());
    if (exp != null && exp.isBefore(at)) continue;
    final svc = (c['service'] ?? '').toString();
    final norm = PendingCoupon.normalizeService(svc);
    out.add({
      'code': code.toUpperCase(),
      'desc': (c['desc'] ?? '').toString(),
      'type': _serviceLabel(norm),
      'service': norm,
    });
  }
  return out;
}

String _serviceLabel(String service) => switch (service) {
      'taxi' => 'Ride',
      'delivery' => 'Parcel',
      'rental' => 'Rental',
      'outstation' => 'Outstation',
      'hire_driver' => 'Hire driver',
      _ => 'All rides',
    };

/// An offer's colour from admin data: "0xFF0A3CC8", "#0A3CC8", "0A3CC8" or an
/// int. Anything else — a typo, null, a name — falls back to the brand blue
/// instead of crashing the offers list (it used a bare int.parse).
Color offerColor(dynamic raw, {Color fallback = const Color(0xFF0A3CC8)}) {
  if (raw is int) return Color(raw);
  var s = (raw ?? '').toString().trim();
  if (s.isEmpty) return fallback;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.toLowerCase().startsWith('0x')) s = s.substring(2);
  if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(s)) return fallback;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return fallback;
  return Color(s.length == 6 ? 0xFF000000 | v : v);
}
