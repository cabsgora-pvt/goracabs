import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// How long the trip (fare, tip, pickup) must stay unchanged before an
/// applied code is checked again.
const kCouponRecheckDelay = Duration(milliseconds: 600);

/// What the server said about a coupon on one trip (POST /promos/preview).
class CouponCheck {
  /// valid: the server will give [discount]. null: it could not be asked
  /// (offline, an error) — the code is checked at booking instead.
  final bool? valid;
  final int discount;
  final int? payable;
  final String reason;
  const CouponCheck({this.valid, this.discount = 0, this.payable, this.reason = ''});

  static const unchecked = CouponCheck();

  static CouponCheck fromResponse(Map<String, dynamic> res) {
    if (res['error'] != null || res['valid'] is! bool) return unchecked;
    final valid = res['valid'] == true;
    return CouponCheck(
      valid: valid,
      discount: valid ? ((res['discount'] as num?) ?? 0).round() : 0,
      payable: (res['payable'] as num?)?.round(),
      reason: (res['reason'] ?? '').toString(),
    );
  }

  /// The rider's line for it.
  String message() {
    if (valid == null) return 'Could not check the coupon right now — it is checked at booking.';
    if (valid == true) return 'Coupon applied: −₹$discount${payable != null ? ' · you pay ₹$payable' : ''}';
    return reason.isNotEmpty ? 'Coupon not applied: $reason' : 'Coupon not valid for this trip';
  }
}

// Reusable Ola-style "Cash · Coupon" bottom row used across all booking screens.
// Picks a payment mode (cash/online/advance) and applies an admin-managed coupon,
// reporting back via [onChanged].
class PaymentCouponBar extends StatefulWidget {
  /// The fare the coupon is previewed on (and the wallet balance compared to).
  final num baseFare;
  /// The trip the coupon is for, as /rides/book will see it: the server's
  /// preview (POST /promos/preview) applies the same rules — zone (from the
  /// pickup), service, minimum fare, per-rider use. The phone no longer works
  /// a discount out from the admin's coupon list.
  final String service;
  final num tip;
  final double? pickupLat;
  final double? pickupLng;
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
    this.service = 'taxi',
    this.tip = 0,
    this.pickupLat,
    this.pickupLng,
    this.accent = const Color(0xFF0A3CC8),
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
  // The server's last word on _couponCode for this trip.
  CouponCheck _check = CouponCheck.unchecked;
  // Re-checks the code when the fare / tip / pickup change, once they settle.
  Timer? _recheck;
  // Answers to an older check are dropped.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _paymentMode = widget.initialPaymentMode;
    _couponCode = widget.initialCouponCode;
    _couponDiscount = widget.initialCouponDiscount;
    _loadPaymentConfig();
    _loadWalletBalance();
    // A code the booking already holds: check it against this trip.
    if (_couponCode.isNotEmpty) _scheduleRecheck();
  }

  @override
  void didUpdateWidget(covariant PaymentCouponBar old) {
    super.didUpdateWidget(old);
    if (_couponCode.isEmpty) return;
    if (old.baseFare != widget.baseFare || old.tip != widget.tip || old.service != widget.service ||
        old.pickupLat != widget.pickupLat || old.pickupLng != widget.pickupLng) {
      _scheduleRecheck();
    }
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  void _scheduleRecheck() {
    _recheck?.cancel();
    _recheck = Timer(kCouponRecheckDelay, () async {
      final code = _couponCode;
      if (code.isEmpty || !mounted) return;
      final c = await _preview(code);
      if (c == null || !mounted || code != _couponCode) return;
      _applyCheck(code, c);
    });
  }

  /// POST /promos/preview for [code] on this trip; null when superseded.
  Future<CouponCheck?> _preview(String code) async {
    final mine = ++_seq;
    CouponCheck c;
    if (widget.baseFare <= 0) {
      c = CouponCheck.unchecked;
    } else {
      try {
        c = CouponCheck.fromResponse(await ApiService.previewPromo(
          code: code, service: widget.service, fare: widget.baseFare, tip: widget.tip,
          pickupLat: widget.pickupLat, pickupLng: widget.pickupLng,
        ));
      } catch (_) {
        c = CouponCheck.unchecked;
      }
    }
    return mine == _seq ? c : null;
  }

  /// Keeps the server's verdict. A code it refused is dropped (with its
  /// reason shown); one it could not check is kept, to be checked at booking.
  void _applyCheck(String code, CouponCheck c) {
    setState(() {
      _check = c;
      _couponCode = c.valid == false ? '' : code;
      _couponDiscount = c.discount;
    });
    _notify();
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
        TextButton(onPressed: () {
          _recheck?.cancel();
          _seq++;
          setState(() { _couponCode = ''; _couponDiscount = 0; _check = CouponCheck.unchecked; });
          _notify();
          Navigator.pop(dctx);
        }, child: const Text('Remove')),
        ElevatedButton(
          key: const ValueKey('coupon-apply'),
          style: ElevatedButton.styleFrom(backgroundColor: widget.accent),
          onPressed: () async {
            final code = ctrl.text.trim().toUpperCase();
            if (code.isEmpty) return;
            _recheck?.cancel();
            final c = await _preview(code);
            if (dctx.mounted) Navigator.pop(dctx);
            if (c == null || !mounted) return;
            _applyCheck(code, c);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.message())));
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
      // The server's discount; a code it could not check yet says so.
      item(Icons.local_offer_outlined,
          _couponDiscount > 0
              ? '−₹$_couponDiscount'
              : (_couponCode.isNotEmpty && _check.valid == null ? '$_couponCode · checked at booking' : 'Coupon'),
          _pickCoupon,
          c: _couponDiscount > 0 ? Colors.green[700] : null),
    ]);
  }
}
