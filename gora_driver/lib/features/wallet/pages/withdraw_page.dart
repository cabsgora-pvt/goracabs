import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';

class WithdrawPage extends StatefulWidget {
  final double balance;
  const WithdrawPage({super.key, required this.balance});
  @override State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Withdraw Earnings'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          const SizedBox(height: 32),
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
          const Text('Bank Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.account_balance, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('State Bank of India', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text('A/C: XXXX XXXX 4821', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Primary', style: TextStyle(fontSize: 10, color: AppColors.green, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Withdraw Now',
            loading: _loading,
            onTap: () async {
              setState(() => _loading = true);
              await Future.delayed(const Duration(seconds: 1));
              if (!mounted) return;
              setState(() => _loading = false);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal request submitted!'), backgroundColor: AppColors.green));
              Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}
