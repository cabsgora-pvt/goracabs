import 'package:flutter/material.dart';

const _brand = Color(0xFF1C2656);

// Bottom sheet to change the payment method during a ride. Returns the chosen
// value ('cash' | 'wallet' | 'online') or null if dismissed.
Future<String?> showPaymentPicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) {
      Widget opt(String value, String label, IconData icon) => ListTile(
            leading: Icon(icon, color: _brand),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: current == value ? const Icon(Icons.check_circle, color: _brand) : null,
            onTap: () => Navigator.pop(context, value),
          );
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('Payment method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ),
            opt('cash', 'Cash', Icons.payments_outlined),
            opt('wallet', 'Gora Wallet', Icons.account_balance_wallet_outlined),
            opt('online', 'Online (UPI / Card)', Icons.credit_card),
            const SizedBox(height: 12),
          ]),
        ),
      );
    },
  );
}

// A tappable "Payment: Cash  ▾ Change" row shown on the ongoing/assigned view.
Widget paymentMethodRow(BuildContext context, String mode, VoidCallback onTap) {
  final label = mode == 'online' ? 'Online' : mode == 'wallet' ? 'Wallet' : 'Cash';
  final icon = mode == 'online' ? Icons.credit_card : mode == 'wallet' ? Icons.account_balance_wallet_outlined : Icons.payments_outlined;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: _brand),
        const SizedBox(width: 10),
        Text('Payment', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        const Text('Change', style: TextStyle(color: _brand, fontWeight: FontWeight.w700, fontSize: 12)),
        const Icon(Icons.keyboard_arrow_down_rounded, color: _brand, size: 20),
      ]),
    ),
  );
}
