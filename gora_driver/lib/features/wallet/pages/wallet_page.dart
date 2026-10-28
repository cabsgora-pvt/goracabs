import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/wallet_bloc.dart';
import '../../../models/models.dart';
import 'withdraw_page.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

class WalletPage extends StatelessWidget {
  static const route = '/wallet';
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WalletBloc()..add(LoadWalletEvent()),
      child: Scaffold(
        appBar: blueAppBar('Wallet'),
        backgroundColor: Cap.surface,
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
    final negative = balance < 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Balance summary
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(Cap.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 18, color: Cap.muted),
              const SizedBox(width: 6),
              Flexible(child: Text('Available balance', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Cap.caption(size: 13.5).copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('₹ ${balance.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -0.8,
                      color: negative ? AppColors.red : Cap.ink)),
            ),
            if (balance <= 0) ...[
              const SizedBox(height: 4),
              Text('Recharge to keep receiving trips', style: Cap.caption(size: 12.5, color: AppColors.red)),
            ],
            const SizedBox(height: 16),
            CapButton(
              label: 'Withdraw',
              icon: Icons.north_east_rounded,
              height: 50,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawPage(balance: balance))),
            ),
          ]),
        ),
        CapSectionTitle('Transactions',
            trailing: transactions.isEmpty ? null : Text('${transactions.length}', style: Cap.caption(size: 13))),
        if (transactions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Cap.radius),
              border: Border.all(color: Cap.divider),
            ),
            child: Column(children: [
              Icon(Icons.receipt_long_outlined, size: 34, color: Cap.muted),
              const SizedBox(height: 8),
              Text('No transactions yet', style: Cap.body(size: 14, weight: FontWeight.w700)),
            ]),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Cap.surface,
              borderRadius: BorderRadius.circular(Cap.radius),
              border: Border.all(color: Cap.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < transactions.length; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsets.only(left: 66), child: Container(height: 1, color: Cap.divider)),
                _TxnRow(txn: transactions[i]),
              ],
            ]),
          ),
      ],
    );
  }
}

class _TxnRow extends StatelessWidget {
  final WalletTransaction txn;
  const _TxnRow({required this.txn});
  @override
  Widget build(BuildContext context) {
    final c = txn.isCredit ? AppColors.green : AppColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(txn.isCredit ? Icons.south_west_rounded : Icons.north_east_rounded, color: c, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(txn.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 14, weight: FontWeight.w800)),
          if (txn.description.isNotEmpty)
            Text(txn.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
          if (txn.date.isNotEmpty)
            Text(txn.date, style: Cap.caption(size: 11)),
        ])),
        const SizedBox(width: 8),
        Text(txn.amount, style: Cap.body(size: 14.5, weight: FontWeight.w900, color: txn.isCredit ? AppColors.green : null)),
      ]),
    );
  }
}
