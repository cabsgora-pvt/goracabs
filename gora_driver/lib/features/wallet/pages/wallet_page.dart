import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/wallet_bloc.dart';
import '../../../models/models.dart';
import 'withdraw_page.dart';

class WalletPage extends StatelessWidget {
  static const route = '/wallet';
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WalletBloc()..add(LoadWalletEvent()),
      child: Scaffold(
        appBar: blueAppBar('Wallet'),
        backgroundColor: AppColors.cardBg,
        body: BlocBuilder<WalletBloc, WalletState>(
          builder: (context, state) {
            if (state is WalletLoading) return const AppLoader();
            if (state is WalletLoaded) return _Body(balance: state.balance, transactions: state.transactions);
            return const AppLoader();
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final double balance;
  final List<WalletTransaction> transactions;
  const _Body({required this.balance, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Balance card
        Container(
          width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: [
            const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text('₹ ${balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _actionBtn(Icons.arrow_upward, 'Withdraw', () => Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawPage(balance: balance)))),
              _actionBtn(Icons.history, 'History', () {}),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        // Transactions
        Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SectionHeader(title: 'Transactions'),
            ),
            Divider(color: AppColors.divider, height: 1),
            ...transactions.map((t) => _TxnRow(txn: t)),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _TxnRow extends StatelessWidget {
  final WalletTransaction txn;
  const _TxnRow({required this.txn});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: txn.isCredit ? AppColors.green.withOpacity(0.1) : AppColors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(txn.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: txn.isCredit ? AppColors.green : AppColors.red, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(txn.type, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark)),
        Text(txn.description, style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
        Text(txn.date, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ])),
      Text(txn.amount, style: TextStyle(fontWeight: FontWeight.w800, color: txn.isCredit ? AppColors.green : AppColors.red, fontSize: 14)),
    ]),
  );
}
