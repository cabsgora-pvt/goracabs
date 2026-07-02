import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/payment_service.dart';
import '../providers/user_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  num _balance = 0;
  List<Map<String, dynamic>> _txns = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService.getWallet();
      setState(() {
        _balance = (r['balance'] as num?) ?? 0;
        _txns = ((r['transactions'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Wallet'), elevation: 0, centerTitle: false),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          // Balance card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1C2656), Color(0xFF3A4A8C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text('₹${_balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: () async {
                  final added = await showModalBottomSheet<bool>(
                    context: context, isScrollControlled: true,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => const AddMoneySheet(),
                  );
                  if (added == true) _load();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Money'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                ),
              )),
            ]),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_txns.isEmpty)
            Padding(padding: const EdgeInsets.all(40), child: Center(child: Column(children: [
              Icon(Icons.receipt_long, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text('No transactions yet', style: TextStyle(color: Colors.grey[600])),
            ])))
          else
            ..._txns.map((t) {
              final isCredit = t['type'] == 'credit';
              final isAdmin = t['source'] == 'admin';
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: (isCredit ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? Colors.green : Colors.red, size: 20),
                ),
                title: Text((t['note'] ?? (isCredit ? 'Credited' : 'Debited')).toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text('${_fmtDate(t['createdAt']?.toString())}${isAdmin ? ' • by admin' : ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                trailing: Text('${isCredit ? '+' : '-'}₹${((t['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isCredit ? Colors.green : Colors.red)),
              );
            }),
          const SizedBox(height: 20),
        ]),
      ),
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

  @override
  void dispose() { _customAmountController.dispose(); super.dispose(); }

  Future<void> _add() async {
    final amt = int.tryParse(_customAmountController.text.trim().isNotEmpty ? _customAmountController.text.trim() : (_selectedAmount ?? '')) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _busy = true);
    try {
      final cfg = await ApiService.getPaymentConfig();
      final rzpEnabled = (cfg['razorpay'] is Map) && (cfg['razorpay']['enabled'] == true);

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

      // Fallback: no gateway configured → direct credit (as before).
      final r = await ApiService.addMoney(amt);
      if (!mounted) return;
      if (r['balance'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('₹$amt added to wallet')));
        Navigator.pop(context, true);
      } else {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Failed')));
      }
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
            const Text('Add Money to Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 16),
          const Text('Select Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: amounts.map((amt) {
            final isSelected = _selectedAmount == amt;
            return GestureDetector(
              onTap: () => setState(() { _selectedAmount = amt; _customAmountController.clear(); }),
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
            controller: _customAmountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Enter custom amount',
              prefixIcon: const Icon(Icons.currency_rupee, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (val) { if (val.isNotEmpty) setState(() => _selectedAmount = null); },
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
