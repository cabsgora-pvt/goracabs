import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/payment_service.dart';
import '../providers/user_provider.dart';
import '../utils/net_errors.dart';

/// "₹1,234.50"-style amount with two decimals (no grouping, as elsewhere).
String walletMoney(num v) => '₹${v.toStringAsFixed(2)}';

/// What a wallet row's `source` means to a rider.
String walletSourceLabel(String source) => switch (source) {
      'recharge' => 'Money added',
      'ride' => 'Ride payment',
      'admin' => 'Adjusted by Gora',
      'refund' => 'Refund',
      'cashback' => 'Cashback',
      'cod' => 'Parcel cash on delivery',
      _ => source.isEmpty ? 'Wallet' : source[0].toUpperCase() + source.substring(1),
    };

/// Filter chip label for a source.
String walletSourceChip(String source) => switch (source) {
      'recharge' => 'Added',
      'ride' => 'Rides',
      'admin' => 'Adjustments',
      'refund' => 'Refunds',
      'cashback' => 'Cashback',
      'cod' => 'Parcel COD',
      _ => walletSourceLabel(source),
    };

/// Top-up bounds. The admin may set them in the app config
/// (`wallet: {minTopup, maxTopup}`); otherwise ₹10 to ₹1,00,000 — the server
/// refuses more than ₹1,00,000 in one payment.
class TopupLimits {
  final int min;
  final int max;
  const TopupLimits(this.min, this.max);
  static const fallback = TopupLimits(10, 100000);

  static int? _int(dynamic v) => v is num ? v.round() : int.tryParse('${v ?? ''}');

  factory TopupLimits.fromConfig(Map<String, dynamic>? cfg) {
    final w = cfg?['wallet'];
    final mn = _int(w is Map ? w['minTopup'] : null) ?? _int(cfg?['walletMinTopup']);
    final mx = _int(w is Map ? w['maxTopup'] : null) ?? _int(cfg?['walletMaxTopup']);
    var lo = (mn != null && mn > 0) ? mn : fallback.min;
    // Never above what the server accepts.
    var hi = (mx != null && mx > 0 && mx <= fallback.max) ? mx : fallback.max;
    if (lo > hi) lo = fallback.min;
    if (lo > hi) hi = fallback.max;
    return TopupLimits(lo, hi);
  }

  String get hint => 'Min ₹$min · Max ₹$max';

  /// Null when [text] is a whole-rupee amount within bounds, else why not.
  String? check(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Enter an amount';
    final v = int.tryParse(t);
    if (v == null || v <= 0) return 'Enter a valid amount';
    if (v < min) return 'Minimum top-up is ₹$min';
    if (v > max) return 'Maximum top-up is ₹$max';
    return null;
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  // Null until the server has answered once: a failed load never shows ₹0.
  num? _balance;
  List<Map<String, dynamic>> _txns = [];
  bool _loading = true;
  String? _error;
  String? _source; // filter: null = all
  int _seq = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final seq = ++_seq;
    if (mounted) setState(() { _loading = true; _error = null; });
    String? error;
    Map<String, dynamic>? r;
    try {
      r = await ApiService.getWallet();
      if (r['error'] != null || r['balance'] is! num) {
        error = loadFailureMessage(classifyResponse(r), what: 'your wallet');
        r = null;
      }
    } catch (e) {
      error = loadFailureMessage(classifyFailure(e), what: 'your wallet');
    }
    if (!mounted || seq != _seq) return;
    final ok = r;
    setState(() {
      _loading = false;
      _error = error;
      if (ok != null) {
        _balance = ok['balance'] as num;
        _txns = ((ok['transactions'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (_source != null && !_txns.any((t) => t['source'] == _source)) _source = null;
      }
    });
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _openAddMoney() async {
    final added = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const AddMoneySheet(),
    );
    if (added == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final failedFirst = _balance == null && _error != null && !_loading;
    final sources = <String>[for (final t in _txns) (t['source'] ?? '').toString()].where((s) => s.isNotEmpty).toSet().toList();
    final shown = _source == null ? _txns : _txns.where((t) => t['source'] == _source).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('My Wallet'), elevation: 0, centerTitle: false),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          if (failedFirst)
            _errorCard(_error!)
          else ...[
            _balanceCard(),
            if (_error != null) _staleBanner(_error!),
          ],
          if (!failedFirst) ...[
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            if (sources.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                child: Wrap(
                  runSpacing: 4,
                  children: [
                    _chip('All', null),
                    for (final s in sources) _chip(walletSourceChip(s), s),
                  ],
                ),
              ),
            if (_loading && _balance == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              Padding(padding: const EdgeInsets.all(40), child: Center(child: Column(children: [
                Icon(Icons.receipt_long, size: 56, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(_source == null ? 'No transactions yet' : 'No transactions of this kind',
                    style: TextStyle(color: Colors.grey[600])),
              ])))
            else
              ...shown.map(_txnTile),
          ],
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _chip(String label, String? source) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: ValueKey('wallet-filter-${source ?? 'all'}'),
      label: Text(label),
      selected: _source == source,
      onSelected: (_) => setState(() => _source = source),
    ),
  );

  Widget _balanceCard() => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF0A3CC8), Color(0xFF3B6BF0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6))],
    ),
    child: Column(children: [
      const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 8),
      _balance == null
          ? const SizedBox(height: 44, child: Center(child: SizedBox(width: 26, height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(Colors.white)))))
          : Text(walletMoney(_balance!), key: const ValueKey('wallet-balance'),
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _balance == null ? null : _openAddMoney,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Money'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white, foregroundColor: AppTheme.primaryBlue,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
        ),
      )),
    ]),
  );

  /// The first load failed: say so, never a ₹0 balance.
  Widget _errorCard(String msg) => Padding(
    key: const ValueKey('wallet-error'),
    padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
    child: Column(children: [
      Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey[500]),
      const SizedBox(height: 14),
      Text('Couldn\'t load your wallet', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
      const SizedBox(height: 18),
      ElevatedButton.icon(
        key: const ValueKey('wallet-retry'),
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ]),
  );

  /// A refresh failed but an earlier answer is on screen.
  Widget _staleBanner(String msg) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(fontSize: 12.5))),
      TextButton(onPressed: _load, child: const Text('Retry')),
    ]),
  );

  Widget _txnTile(Map<String, dynamic> t) {
    final isCredit = t['type'] == 'credit';
    final source = (t['source'] ?? '').toString();
    final note = (t['note'] ?? '').toString().trim();
    final amount = (t['amount'] as num?) ?? 0;
    final after = t['balanceAfter'];
    final label = walletSourceLabel(source);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: (isCredit ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? Colors.green : Colors.red, size: 20),
      ),
      title: Text(note.isNotEmpty ? note : (isCredit ? 'Credited' : 'Debited'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        [label, _fmtDate(t['createdAt']?.toString())].where((s) => s.isNotEmpty).join(' • '),
        style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${isCredit ? '+' : '-'}${walletMoney(amount)}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isCredit ? Colors.green : Colors.red)),
        if (after is num)
          Text('Bal ${walletMoney(after)}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
      ]),
    );
  }
}

class AddMoneySheet extends StatefulWidget {
  const AddMoneySheet({super.key});
  @override
  State<AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends State<AddMoneySheet> {
  String? _selectedAmount;
  final _customAmountController = TextEditingController();
  bool _busy = false;
  final amounts = ['100', '200', '500', '1000', '2000'];
  TopupLimits _limits = TopupLimits.fallback;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    ApiService.getAppConfig().then((c) {
      if (mounted) setState(() => _limits = TopupLimits.fromConfig(c));
    }).catchError((_) {});
  }

  @override
  void dispose() { _customAmountController.dispose(); super.dispose(); }

  String get _amountText => _customAmountController.text.trim().isNotEmpty
      ? _customAmountController.text.trim()
      : (_selectedAmount ?? '');

  Future<void> _add() async {
    final problem = _limits.check(_amountText);
    if (problem != null) {
      setState(() => _fieldError = problem);
      return;
    }
    final amt = int.parse(_amountText.trim());
    setState(() { _busy = true; _fieldError = null; });
    try {
      final cfg = await ApiService.getPaymentConfig();
      final rzpEnabled = (cfg['razorpay'] is Map) && (cfg['razorpay']['enabled'] == true);
      if (!mounted) return;

      if (rzpEnabled) {
        // Real payment via Razorpay — server credits wallet after verification.
        final user = context.read<UserProvider>().user;
        final res = await PaymentService.topUpWallet(
          amount: amt,
          contact: user?['phone']?.toString(),
          email: user?['email']?.toString(),
        );
        if (!mounted) return;
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('₹$amt added to wallet')));
          Navigator.pop(context, true);
        } else {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Payment failed')));
        }
        return;
      }

      // No gateway: there is no other way to add money. The old fallback
      // credited the wallet with no payment at all (POST /wallet, now 410).
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Online payment is not available right now, so money cannot be added. Please try again later.')));
    } catch (_) {
      if (mounted) { setState(() => _busy = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add money'))); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Add Money to Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 16),
          const Text('Select Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: amounts.where((a) {
            final v = int.parse(a);
            return v >= _limits.min && v <= _limits.max;
          }).map((amt) {
            final isSelected = _selectedAmount == amt;
            return GestureDetector(
              onTap: () => setState(() { _selectedAmount = amt; _customAmountController.clear(); _fieldError = null; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryBlue : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? AppTheme.primaryBlue : Colors.grey[300]!),
                ),
                child: Text('₹$amt', style: TextStyle(color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('wallet-topup-amount'),
            controller: _customAmountController,
            keyboardType: TextInputType.number,
            // Whole rupees only: no "1e3", "-50", "10.5" or pasted spaces.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              hintText: 'Enter custom amount',
              helperText: _limits.hint,
              errorText: _fieldError,
              prefixIcon: const Icon(Icons.currency_rupee, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (val) => setState(() {
              if (val.isNotEmpty) _selectedAmount = null;
              _fieldError = null;
            }),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _add,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue, minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)))
              : const Text('Add Money', style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}
