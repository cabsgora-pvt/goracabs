import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text('Available Balance', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('₹1,250.00', style: TextStyle(color: Colors.black87, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (_) => const AddMoneySheet(),
                          );
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Money'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Send Money'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.5)),
                          foregroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: AppTheme.primaryBlue,
                    unselectedLabelColor: AppTheme.textGrey,
                    indicatorColor: AppTheme.primaryBlue,
                    tabs: const [
                      Tab(text: 'Transactions'),
                      Tab(text: 'Offers'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTransactionList(),
                        _buildOffersList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    final transactions = [
      {'title': 'Ride Payment', 'date': 'Today, 10:30 AM', 'amount': '-₹120', 'type': 'debit'},
      {'title': 'Wallet Recharge', 'date': 'Yesterday, 5:45 PM', 'amount': '+₹500', 'type': 'credit'},
      {'title': 'Ride Payment', 'date': '15 Jan, 2:20 PM', 'amount': '-₹180', 'type': 'debit'},
      {'title': 'Cashback Received', 'date': '14 Jan, 11:00 AM', 'amount': '+₹50', 'type': 'credit'},
      {'title': 'Ride Payment', 'date': '12 Jan, 8:15 AM', 'amount': '-₹95', 'type': 'debit'},
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final txn = transactions[i];
        final isCredit = txn['type'] == 'credit';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCredit ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward : Icons.arrow_upward,
              color: isCredit ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          title: Text(txn['title']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(txn['date']!, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
          trailing: Text(
            txn['amount']!,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isCredit ? Colors.green : Colors.red,
            ),
          ),
        );
      },
    );
  }

  Widget _buildOffersList() {
    final offers = [
      {'title': 'Get 20% Cashback', 'desc': 'Add ₹500 or more to wallet', 'code': 'WALLET20'},
      {'title': 'Flat ₹100 Off', 'desc': 'On your next 3 rides', 'code': 'RIDE100'},
      {'title': 'Refer & Earn', 'desc': 'Get ₹50 for each referral', 'code': 'REFER50'},
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final offer = offers[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryBlue.withAlpha(30), AppTheme.primaryBlue.withAlpha(10)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryBlue.withAlpha(60)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_offer, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(offer['desc']!, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.primaryBlue, style: BorderStyle.solid, width: 1),
                      ),
                      child: Text(offer['code']!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Apply', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
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
  String? _selectedPayment;
  final _customAmountController = TextEditingController();

  final amounts = ['100', '200', '500', '1000', '2000'];
  final payments = [
    {'name': 'UPI', 'icon': Icons.account_balance},
    {'name': 'Card', 'icon': Icons.credit_card},
    {'name': 'Net Banking', 'icon': Icons.account_balance_wallet},
    {'name': 'Razorpay', 'icon': Icons.payment},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Add Money to Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Select Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: amounts.map((amt) {
                final isSelected = _selectedAmount == amt;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedAmount = amt;
                    _customAmountController.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryBlue : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppTheme.primaryBlue : Colors.grey[300]!),
                    ),
                    child: Text('₹$amt', style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customAmountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter custom amount',
                prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (val) {
                if (val.isNotEmpty) setState(() => _selectedAmount = null);
              },
            ),
            const SizedBox(height: 24),
            const Text('Payment Method', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...payments.map((p) {
              final isSelected = _selectedPayment == p['name'];
              return GestureDetector(
                onTap: () => setState(() => _selectedPayment = p['name'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryBlue.withAlpha(20) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? AppTheme.primaryBlue : Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(p['icon'] as IconData, color: isSelected ? AppTheme.primaryBlue : AppTheme.textGrey),
                      const SizedBox(width: 12),
                      Text(p['name'] as String, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                      const Spacer(),
                      if (isSelected) const Icon(Icons.check_circle, color: AppTheme.primaryBlue, size: 20),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment gateway integration pending')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Proceed to Pay', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
