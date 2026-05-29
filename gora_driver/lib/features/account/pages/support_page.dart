import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';

class SupportPage extends StatelessWidget {
  static const route = '/support-tickets';
  const SupportPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Support Tickets', actions: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: () => _newTicket(context)),
      ]),
      backgroundColor: AppColors.cardBg,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockTickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final t = mockTickets[i];
          final isOpen = t.status == 'open';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('#${t.id}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: (isOpen ? AppColors.orange : AppColors.green).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(t.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isOpen ? AppColors.orange : AppColors.green)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(t.lastMessage, style: const TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(t.date, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
            ]),
          );
        },
      ),
    );
  }

  void _newTicket(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('New Support Ticket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Describe your issue...')),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Submit Ticket', onTap: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket submitted!'), backgroundColor: AppColors.green));
          }),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
