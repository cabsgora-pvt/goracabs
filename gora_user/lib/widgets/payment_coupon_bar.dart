import 'package:flutter/material.dart';
import '../services/api_service.dart';

// Reusable Ola-style "Cash · Coupon" bottom row used across all booking screens.
// Picks a payment mode (cash/online/advance) and applies an admin-managed coupon,
// reporting back via [onChanged].
class PaymentCouponBar extends StatefulWidget {
  final num baseFare; // used to compute percentage coupons
  final void Function(String paymentMode, String couponCode, int couponDiscount) onChanged;
  final Color accent;
  /// What the bar shows when it opens. Display only — nothing is reported via
  /// [onChanged] until the rider changes something, exactly as before; this
  /// just stops a re-opened sheet from showing "Cash" when the booking already
  /// holds another choice.
  final String initialPaymentMode;
  final String initialCouponCode;
  final int initialCouponDiscount;
  const PaymentCouponBar({
    super.key,
    required this.baseFare,
    required this.onChanged,
    this.accent = const Color(0xFF1C2656),
    this.initialPaymentMode = 'cash',
    this.initialCouponCode = '',
    this.initialCouponDiscount = 0,
  });

  @override
  State<PaymentCouponBar> createState() => _PaymentCouponBarState();
}

class _PaymentCouponBarState extends State<PaymentCouponBar> {
  String _paymentMode = 'cash';
  String _couponCode = '';
  int _couponDiscount = 0;
  bool _walletEnabled = true;
  bool _onlineEnabled = false;
  num? _walletBalance;

  @override
  void initState() {
    super.initState();
    _paymentMode = widget.initialPaymentMode;
    _couponCode = widget.initialCouponCode;
    _couponDiscount = widget.initialCouponDiscount;
    _loadPaymentConfig();
    _loadWalletBalance();
  }

  Future<void> _loadPaymentConfig() async {
    final cfg = await ApiService.getPaymentConfig();
    if (!mounted) return;
    setState(() {
      _walletEnabled = cfg['walletEnabled'] != false;
      _onlineEnabled = (cfg['razorpay'] is Map) && (cfg['razorpay']['enabled'] == true);
    });
  }

  // Shown up front so a rider isn't only told their wallet was short at the
  // very end of the ride — the actual insufficient-balance check still runs
  // for real, server-side, at charge time; this is just an earlier heads-up.
  Future<void> _loadWalletBalance() async {
    try {
      final res = await ApiService.getWallet();
      if (mounted) setState(() => _walletBalance = (res['balance'] as num?) ?? 0);
    } catch (_) {}
  }

  void _notify() => widget.onChanged(_paymentMode, _couponCode, _couponDiscount);

  // Validate a code against admin-managed coupons; returns discount (₹), 0 if invalid.
  static Future<int> _validateCoupon(String code, num fare) async {
    if (code.isEmpty) return 0;
    final cfg = await ApiService.getAppConfig();
    final coupons = (cfg['coupons'] as List?) ?? [];
    for (final c in coupons) {
      if ((c['code'] ?? '').toString().toUpperCase() != code) continue;
      if (c['isActive'] == false) return 0;
      if ((c['minFare'] ?? 0) is num && fare < (c['minFare'] as num)) return 0;
      final val = (c['value'] as num?) ?? 0;
      if ((c['discountType'] ?? 'flat') == 'percent') {
        var d = (fare * val / 100).round();
        final cap = (c['maxDiscount'] as num?)?.toInt() ?? 0;
        if (cap > 0 && d > cap) d = cap;
        return d;
      }
      return val.round();
    }
    return 0;
  }

  Future<void> _pickPayment() async {
    final balance = _walletBalance;
    final short = balance != null && balance < widget.baseFare;
    Widget tile(String mode, IconData ic, String label, String sub, {Color? subColor}) => ListTile(
      leading: Icon(ic, color: widget.accent),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: TextStyle(fontSize: 11, color: subColor, fontWeight: subColor != null ? FontWeight.w700 : null)),
      trailing: _paymentMode == mode ? Icon(Icons.check_circle, color: widget.accent) : null,
      onTap: () => Navigator.pop(context, mode),
    );
    final walletSub = balance == null
        ? 'Pay from your wallet balance'
        : short
            ? 'Only ₹${balance.toStringAsFixed(0)} available — ₹${(widget.baseFare - balance).toStringAsFixed(0)} short of the fare'
            : '₹${balance.toStringAsFixed(0)} available';
    final m = await showModalBottomSheet<String>(
      context: context, backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Payment method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        tile('cash', Icons.payments_outlined, 'Cash', 'Pay the driver directly'),
        if (_walletEnabled) tile('wallet', Icons.account_balance_wallet_outlined, 'Gora Wallet', walletSub, subColor: short ? Colors.orange[800] : null),
        if (_onlineEnabled) tile('online', Icons.credit_card, 'Online', 'UPI / card / net banking'),
      ])),
    );
    if (m != null) { setState(() => _paymentMode = m); _notify(); }
  }

  Future<void> _pickCoupon() async {
    final ctrl = TextEditingController(text: _couponCode);
    await showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Apply coupon'),
      content: TextField(controller: ctrl, textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: 'e.g. FLAT100, GORA10', prefixIcon: const Icon(Icons.local_offer_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      actions: [
        TextButton(onPressed: () { setState(() { _couponCode = ''; _couponDiscount = 0; }); _notify(); Navigator.pop(dctx); }, child: const Text('Remove')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: widget.accent),
          onPressed: () async {
            final code = ctrl.text.trim().toUpperCase();
            final d = await _validateCoupon(code, widget.baseFare);
            setState(() { _couponCode = code; _couponDiscount = d; });
            _notify();
            if (dctx.mounted) Navigator.pop(dctx);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d > 0 ? 'Coupon applied: −₹$d' : 'Invalid coupon')));
          },
          child: const Text('Apply', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final payLabel = _paymentMode == 'online' ? 'Online' : (_paymentMode == 'wallet' ? 'Wallet' : 'Cash');
    final payIcon = _paymentMode == 'online' ? Icons.credit_card : (_paymentMode == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tile = dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF3F4F6);
    final ink = dark ? Colors.white : const Color(0xFF111111);
    // Two light-grey pills side by side, Uber style: "Cash ▾" | "Coupon ▾".
    Widget item(IconData ic, String label, VoidCallback onTap, {Color? c}) => Expanded(child: Material(
      color: tile,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(ic, size: 19, color: c ?? ink),
            const SizedBox(width: 8),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: c ?? ink))),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: c ?? ink),
          ]),
        ),
      ),
    ));
    return Row(children: [
      item(payIcon, payLabel, _pickPayment),
      const SizedBox(width: 8),
      item(Icons.local_offer_outlined, _couponDiscount > 0 ? '−₹$_couponDiscount' : 'Coupon', _pickCoupon,
          c: _couponDiscount > 0 ? Colors.green[700] : null),
    ]);
  }
}
