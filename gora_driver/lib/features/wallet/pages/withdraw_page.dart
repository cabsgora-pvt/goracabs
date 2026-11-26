import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';

/// The body of a withdrawal: {amount, accountId?}. The payout account is one
/// of the driver's SAVED accounts — the server takes the bank details from
/// its own record, never from here. A saved account (GET /auth/driver/banks)
/// carries its `_id`; the registration account listed when none was added
/// has none and is picked by its account number / IFSC instead (the server
/// matches it against the saved one only).
Map<String, dynamic> withdrawalBody(num amount, Map<String, dynamic> bank) {
  final id = (bank['_id'] ?? bank['id'] ?? '').toString();
  return {
    'amount': amount == amount.roundToDouble() ? amount.round() : amount,
    if (id.isNotEmpty) 'accountId': id
    else ...{
      if (bank['accountNumber'] != null) 'accountNumber': bank['accountNumber'],
      if (bank['ifscCode'] != null) 'ifscCode': bank['ifscCode'],
    },
  };
}

/// The line for a refused withdrawal, by the server's code. Null: use the
/// server's own text.
String? withdrawalRefusal(Map<String, dynamic> res) {
  switch ((res['code'] ?? '').toString()) {
    case 'bankAccountRequired':
      return 'Add a bank account to withdraw to.';
    case 'bankAccountNotFound':
      return 'That bank account is no longer saved. Pick one of your accounts, or add it again.';
    case 'notApproved':
      return 'Withdrawals are available once your account is approved.';
    case 'accountHold':
      final e = (res['error'] ?? '').toString();
      return e.isNotEmpty ? e : 'Your account is on hold, so withdrawals are paused. Please contact support.';
  }
  return null;
}

/// One withdrawal request, as GET /auth/driver/withdraw lists it.
class WithdrawalItem {
  final String id;
  final double amount;
  /// 'pending' | 'approved' | 'rejected'.
  final String status;
  final DateTime? createdAt;
  final DateTime? processedAt;
  final String bankName;
  final String accountLast4;
  /// Rejection reason / admin note.
  final String note;
  final String payoutRef;
  /// The amount left the wallet when it was requested (held until paid out).
  final bool held;
  const WithdrawalItem({
    required this.id, required this.amount, required this.status, this.createdAt, this.processedAt,
    this.bankName = '', this.accountLast4 = '', this.note = '', this.payoutRef = '', this.held = false,
  });

  factory WithdrawalItem.fromJson(Map<String, dynamic> j) {
    final acct = (j['accountNumber'] ?? '').toString().trim();
    return WithdrawalItem(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      status: (j['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal(),
      processedAt: DateTime.tryParse('${j['processedAt'] ?? ''}')?.toLocal(),
      bankName: (j['bankName'] ?? '').toString(),
      accountLast4: acct.length >= 4 ? acct.substring(acct.length - 4) : acct,
      note: (j['note'] ?? '').toString(),
      payoutRef: (j['payoutRef'] ?? '').toString(),
      held: j['holdPlaced'] == true && j['holdReleased'] != true,
    );
  }

  /// "Pending", "Paid", "Rejected".
  String get statusLabel => switch (status) {
        'approved' => 'Paid',
        'rejected' => 'Rejected',
        _ => 'Pending',
      };
}

/// The withdrawal page's figures from GET /auth/driver/withdraw.
class WithdrawalsInfo {
  final List<WithdrawalItem> items;
  /// The least a request may be (driverApp.minWithdrawal); null when the
  /// server does not say (older server) — then only it checks.
  final int? minWithdrawal;
  /// Money held by requests still waiting to be paid out.
  final double pendingHeld;
  const WithdrawalsInfo({this.items = const [], this.minWithdrawal, this.pendingHeld = 0});

  factory WithdrawalsInfo.fromJson(Map<String, dynamic> res) {
    final items = ((res['withdrawals'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => WithdrawalItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final held = res['pendingHeld'] is num
        ? (res['pendingHeld'] as num).toDouble()
        : items.where((w) => w.status == 'pending' && w.held).fold<double>(0, (s, w) => s + w.amount);
    final min = res['minWithdrawal'];
    return WithdrawalsInfo(items: items, minWithdrawal: min is num ? min.round() : null, pendingHeld: held);
  }

  bool get hasPending => items.any((w) => w.status == 'pending');
}

/// Why [amount] cannot be asked for, or null when it can.
String? withdrawalAmountProblem(double amount, {required double balance, int? min}) {
  if (amount <= 0) return 'Enter a valid amount';
  if (amount != amount.roundToDouble()) return 'Enter a whole amount';
  if (min != null && amount < min) return 'Minimum withdrawal is ₹$min';
  if (amount > balance) return 'You can withdraw up to ₹${balance.floor()}';
  return null;
}

class WithdrawPage extends StatefulWidget {
  final double balance;
  const WithdrawPage({super.key, required this.balance});
  @override State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  final _ctrl = TextEditingController();
  bool _loading = false;      // submit in-flight
  bool _fetching = true;      // initial bank fetch
  String _driverName = '';
  List<Map<String, dynamic>> _banks = [];
  int _selectedIndex = -1;
  WithdrawalsInfo _history = const WithdrawalsInfo();

  @override
  void initState() {
    super.initState();
    _loadBanks();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await DriverApiService.getWithdrawals();
      if (!mounted || res['error'] != null) return;
      setState(() => _history = WithdrawalsInfo.fromJson(res));
    } catch (_) {}
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _loadBanks({String? selectAccountNumber}) async {
    if (mounted) setState(() => _fetching = true);
    try {
      final res = await DriverApiService.getBanks();
      if (!mounted) return;
      final banks = ((res['banks'] as List?) ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      int idx = banks.isEmpty ? -1 : 0;
      if (selectAccountNumber != null) {
        final found = banks.indexWhere((b) => '${b['accountNumber']}' == selectAccountNumber);
        if (found >= 0) idx = found;
      }
      setState(() {
        _driverName = '${res['driverName'] ?? ''}';
        _banks = banks;
        _selectedIndex = idx;
        _fetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load bank accounts: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  Widget _historyRow(WithdrawalItem w) {
    final color = w.status == 'approved'
        ? AppColors.green
        : w.status == 'rejected' ? AppColors.red : AppColors.orange;
    String date(DateTime? d) {
      if (d == null) return '';
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    }
    final details = [
      date(w.createdAt),
      if (w.bankName.isNotEmpty || w.accountLast4.isNotEmpty) '${w.bankName} •••• ${w.accountLast4}'.trim(),
      if (w.status == 'approved' && w.payoutRef.isNotEmpty) 'Ref ${w.payoutRef}',
    ].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      key: ValueKey('withdrawal_${w.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('₹${w.amount.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textDark)),
          if (details.isNotEmpty)
            Text(details, style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
          if (w.status == 'rejected' && w.note.isNotEmpty)
            Text(w.note, style: const TextStyle(fontSize: 12, color: AppColors.red)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(w.statusLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ),
      ]),
    );
  }

  String _mask(String accountNumber) {
    final digits = accountNumber.trim();
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    return '•••• $last4';
  }

  Future<void> _openAddBankSheet() async {
    final holderCtrl = TextEditingController(text: _driverName);
    final bankCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    bool saving = false;
    String? errorText;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget field(String label, TextEditingController c, {TextInputType? type, List<TextInputFormatter>? fmt}) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: c,
                  keyboardType: type,
                  inputFormatters: fmt,
                  decoration: InputDecoration(
                    labelText: label,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Add Bank Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                const SizedBox(height: 16),
                field('Account holder name', holderCtrl),
                field('Bank name', bankCtrl),
                field('Account number', accountCtrl, type: TextInputType.number,
                    fmt: [FilteringTextInputFormatter.allow(RegExp(r'\d'))]),
                field('IFSC code', ifscCtrl,
                    fmt: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), UpperCaseTextFormatter()]),
                if (errorText != null) ...[
                  Text(errorText!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                PrimaryButton(
                  label: 'Save',
                  loading: saving,
                  onTap: () async {
                    final holder = holderCtrl.text.trim();
                    final bank = bankCtrl.text.trim();
                    final account = accountCtrl.text.trim();
                    final ifsc = ifscCtrl.text.trim();
                    if (holder.isEmpty || bank.isEmpty || account.isEmpty || ifsc.isEmpty) {
                      setSheet(() => errorText = 'Please fill in all fields');
                      return;
                    }
                    setSheet(() { saving = true; errorText = null; });
                    try {
                      final res = await DriverApiService.addBank({
                        'accountHolderName': holder,
                        'bankName': bank,
                        'accountNumber': account,
                        'ifscCode': ifsc,
                      });
                      if (res['success'] == true) {
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        await _loadBanks(selectAccountNumber: account);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bank account added'), backgroundColor: AppColors.green),
                          );
                        }
                      } else {
                        setSheet(() { saving = false; errorText = '${res['error'] ?? 'Failed to add bank account'}'; });
                      }
                    } catch (e) {
                      setSheet(() { saving = false; errorText = 'Failed to add bank account: $e'; });
                    }
                  },
                ),
                const SizedBox(height: 8),
              ]),
            );
          },
        );
      },
    );

    holderCtrl.dispose();
    bankCtrl.dispose();
    accountCtrl.dispose();
    ifscCtrl.dispose();
  }

  Future<void> _withdraw() async {
    final amt = double.tryParse(_ctrl.text.trim()) ?? 0;
    final problem = withdrawalAmountProblem(amt, balance: widget.balance, min: _history.minWithdrawal);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem), backgroundColor: AppColors.red),
      );
      return;
    }
    if (_selectedIndex < 0 || _selectedIndex >= _banks.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a bank account'), backgroundColor: AppColors.red),
      );
      return;
    }
    final bank = _banks[_selectedIndex];
    setState(() => _loading = true);
    try {
      final res = await DriverApiService.requestWithdrawal(withdrawalBody(amt, bank));
      if (!mounted) return;
      setState(() => _loading = false);
      if (res['success'] == true) {
        // The amount is held from the wallet straight away, until it is paid
        // out (or returned if the request is rejected).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(withdrawalHeldText(amt, res['walletBalance'])), backgroundColor: AppColors.green),
        );
        Navigator.pop(context, true);
      } else if (res['code'] == 'bankAccountRequired' || res['code'] == 'bankAccountNotFound') {
        // The saved accounts changed: reload them and offer to add one.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(withdrawalRefusal(res)!),
          backgroundColor: AppColors.orange,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Add account', onPressed: _openAddBankSheet),
        ));
        await _loadBanks();
      } else if (withdrawalRefusal(res) != null) {
        // 403 notApproved / accountHold: not something a retry fixes.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(withdrawalRefusal(res)!),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 6),
        ));
      } else if (res['_status'] == 409) {
        // One request at a time: the earlier one still holds its money.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${res['error'] ?? 'You already have a withdrawal request pending.'}'),
          backgroundColor: AppColors.orange,
          duration: const Duration(seconds: 6),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${res['error'] ?? 'Withdrawal failed'}'), backgroundColor: AppColors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Withdrawal failed: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBanks = _banks.isNotEmpty;
    return Scaffold(
      appBar: blueAppBar('Withdraw Earnings'),
      body: _fetching
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Balance card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    Icon(Icons.account_balance_wallet_outlined, color: AppColors.textDark, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Available balance', style: TextStyle(color: AppColors.textGrey, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('₹ ${widget.balance.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                        ),
                      ]),
                    ),
                  ]),
                ),
                if (_driverName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.person, size: 16, color: AppColors.textGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Account holder: $_driverName',
                          style: TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
                if (_history.pendingHeld > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('withdraw_pending_held'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '₹${_history.pendingHeld.toStringAsFixed(0)} is on hold for a withdrawal being processed '
                        '(not in the balance above).',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textDark))),
                    ]),
                  ),
                ],
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(child: Text('Enter amount', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark))),
                  if (_history.minWithdrawal != null)
                    Text('Min ₹${_history.minWithdrawal}', key: const ValueKey('withdraw_min'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textDark),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.textDark),
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 16),
                // Quick amounts
                Row(children: [100, 250, 500, 1000].map((amt) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextButton(
                      onPressed: () => _ctrl.text = amt.toString(),
                      style: TextButton.styleFrom(backgroundColor: AppColors.cardBg, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: FittedBox(fit: BoxFit.scaleDown,
                          child: Text('₹$amt', style: TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w800))),
                    ),
                  ),
                )).toList()),
                const SizedBox(height: 24),
                // Bank Account header + add
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text('Bank account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark))),
                  TextButton.icon(
                    onPressed: _openAddBankSheet,
                    icon: const Icon(Icons.add, size: 18, color: AppColors.primary),
                    label: const Text('Add bank account', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  ),
                ]),
                const SizedBox(height: 8),
                if (!hasBanks)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: AppColors.textGrey, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Add a bank account to withdraw',
                          style: TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  )
                else
                  ...List.generate(_banks.length, (i) {
                    final b = _banks[i];
                    final selected = i == _selectedIndex;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary.withOpacity(0.05) : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: RadioListTile<int>(
                        value: i,
                        groupValue: _selectedIndex,
                        onChanged: (v) => setState(() => _selectedIndex = v ?? _selectedIndex),
                        activeColor: AppColors.primary,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        title: Text('${b['bankName'] ?? ''}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('A/C: ${_mask('${b['accountNumber'] ?? ''}')}',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                          Text('IFSC: ${b['ifscCode'] ?? ''}',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Withdraw now',
                  loading: _loading,
                  onTap: hasBanks ? _withdraw : null,
                ),
                if (_history.items.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Your withdrawals', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(height: 8),
                  for (final w in _history.items.take(20)) _historyRow(w),
                ],
              ]),
            ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// "Withdrawal requested — ₹500 is on hold until it is paid out."
String withdrawalHeldText(num amount, dynamic walletBalance) {
  final bal = walletBalance is num ? ' Wallet balance: ₹${walletBalance.toStringAsFixed(0)}.' : '';
  return 'Withdrawal requested — ₹${amount.toStringAsFixed(0)} is on hold until it is paid out.$bal';
}
