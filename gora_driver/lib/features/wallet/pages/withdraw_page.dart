import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBanks();
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
                const Text('Add Bank Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
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
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount'), backgroundColor: AppColors.red),
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
      final res = await DriverApiService.requestWithdrawal({
        'amount': amt,
        'accountHolderName': bank['accountHolderName'],
        'bankName': bank['bankName'],
        'accountNumber': bank['accountNumber'],
        'ifscCode': bank['ifscCode'],
      });
      if (!mounted) return;
      setState(() => _loading = false);
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Withdrawal request submitted'), backgroundColor: AppColors.green),
        );
        Navigator.pop(context);
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('₹ ${widget.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    ]),
                  ]),
                ),
                if (_driverName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.person, size: 16, color: AppColors.textGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Account holder: $_driverName',
                          style: const TextStyle(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
                const SizedBox(height: 28),
                const Text('Enter Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary),
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary),
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 16),
                // Quick amounts
                Row(children: [100, 250, 500, 1000].map((amt) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: OutlinedButton(
                      onPressed: () => _ctrl.text = amt.toString(),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.divider), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: Text('₹$amt', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                )).toList()),
                const SizedBox(height: 24),
                // Bank Account header + add
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Bank Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
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
                    child: const Row(children: [
                      Icon(Icons.info_outline, color: AppColors.textGrey, size: 20),
                      SizedBox(width: 10),
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
                        color: selected ? AppColors.cardBg : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.divider,
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: RadioListTile<int>(
                        value: i,
                        groupValue: _selectedIndex,
                        onChanged: (v) => setState(() => _selectedIndex = v ?? _selectedIndex),
                        activeColor: AppColors.primary,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        title: Text('${b['bankName'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('A/C: ${_mask('${b['accountNumber'] ?? ''}')}',
                              style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                          Text('IFSC: ${b['ifscCode'] ?? ''}',
                              style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Withdraw Now',
                  loading: _loading,
                  onTap: hasBanks ? _withdraw : null,
                ),
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
