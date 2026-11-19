import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/driver_payment_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// "Add balance" sheet on the wallet page: pick or type an amount, pay with
/// Razorpay, and the server adds what was actually paid.
///
/// Returns the new wallet balance when money was added, otherwise null.
Future<double?> showAddBalanceSheet(BuildContext context, {String? phone}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Cap.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => AddBalanceSheet(phone: phone),
  );
}

class AddBalanceSheet extends StatefulWidget {
  final String? phone;
  /// Test hook: replaces Razorpay checkout.
  final Future<Map<String, dynamic>> Function(int amount)? payOverride;
  const AddBalanceSheet({super.key, this.phone, this.payOverride});

  @override
  State<AddBalanceSheet> createState() => _AddBalanceSheetState();
}

class _AddBalanceSheetState extends State<AddBalanceSheet> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _enabled = false;
  bool _paying = false;
  int _min = 50, _max = 20000;
  List<int> _presets = const [200, 500, 1000, 2000];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await DriverApiService.getRechargeConfig();
      if (!mounted) return;
      setState(() {
        _enabled = c['enabled'] == true;
        _min = (c['min'] as num?)?.toInt() ?? _min;
        _max = (c['max'] as num?)?.toInt() ?? _max;
        final p = (c['presets'] as List?)?.map((e) => (e as num).toInt()).toList();
        if (p != null && p.isNotEmpty) _presets = p;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _enabled = false; });
    }
  }

  int? get _value => int.tryParse(_amount.text.trim());

  String? _validate() {
    final v = _value;
    if (v == null) return 'Enter an amount';
    if (v < _min) return 'Minimum is ₹$_min';
    if (v > _max) return 'Maximum is ₹$_max';
    return null;
  }

  Future<void> _pay() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _paying = true; _error = null; });
    final amount = _value!;
    Map<String, dynamic> res;
    try {
      res = widget.payOverride != null
          ? await widget.payOverride!(amount)
          : await DriverPaymentService.rechargeWallet(amount: amount, contact: widget.phone);
    } catch (_) {
      res = {'error': 'Something went wrong. Please try again.'};
    }
    if (!mounted) return;
    setState(() => _paying = false);
    if (res['success'] == true) {
      Navigator.of(context).pop((res['walletBalance'] as num?)?.toDouble());
    } else {
      setState(() => _error = res['error']?.toString() ?? 'Payment failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Cap.divider, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Add balance', style: Cap.title(size: 22)),
          const SizedBox(height: 4),
          Text('Money is added to your Gora wallet instantly after payment.', style: Cap.caption(size: 13)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Amount field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Cap.tile,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _error != null ? AppColors.red : Colors.transparent, width: 1.2),
              ),
              child: Row(children: [
                Text('₹', style: Cap.body(size: 26, weight: FontWeight.w900)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('add_balance_amount'),
                    controller: _amount,
                    enabled: _enabled && !_paying,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onChanged: (_) => setState(() => _error = null),
                    style: Cap.body(size: 26, weight: FontWeight.w900),
                    decoration: InputDecoration(
                      hintText: 'Enter amount',
                      hintStyle: Cap.caption(size: 18),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            // Quick amounts
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text('₹$p'),
                  selected: _value == p,
                  onSelected: !_enabled || _paying
                      ? null
                      : (_) => setState(() {
                            _amount.text = '$p';
                            _error = null;
                          }),
                  labelStyle: Cap.body(size: 14, weight: FontWeight.w800,
                      color: _value == p ? Colors.white : Cap.ink),
                  selectedColor: Cap.navy,
                  backgroundColor: Cap.tile,
                  side: BorderSide.none,
                  showCheckmark: false,
                ),
            ]),
            const SizedBox(height: 8),
            Text('Min ₹$_min · Max ₹$_max per payment', style: Cap.caption(size: 12)),
            if (!_enabled) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Online recharge is not available yet. Please contact support to add balance.',
                        style: Cap.body(size: 12.5, weight: FontWeight.w600)),
                  ),
                ]),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: Cap.caption(size: 12.5, color: AppColors.red)),
            ],
            const SizedBox(height: 18),
            CapButton(
              label: _value != null && _value! > 0 ? 'Add ₹${_value!}' : 'Add balance',
              icon: Icons.add_rounded,
              loading: _paying,
              onPressed: _enabled && !_paying ? _pay : null,
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: Cap.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Secured by Razorpay · UPI, cards, net banking',
                    maxLines: 2, textAlign: TextAlign.center, style: Cap.caption(size: 11.5)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
