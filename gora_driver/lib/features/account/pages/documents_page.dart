import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';

class DocumentsPage extends StatelessWidget {
  static const route = '/documents';
  const DocumentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('My Documents'),
      backgroundColor: AppColors.cardBg,
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockDocuments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final doc = mockDocuments[i];
          final isApproved = doc.status == 'approved';
          final isPending = doc.status == 'pending';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: (isApproved ? AppColors.green : AppColors.orange).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.description, color: isApproved ? AppColors.green : AppColors.orange, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
                if (doc.expiryDate != 'N/A')
                  Text('Expires: ${doc.expiryDate}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isApproved ? AppColors.green : isPending ? AppColors.orange : AppColors.red).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(doc.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isApproved ? AppColors.green : isPending ? AppColors.orange : AppColors.red)),
              ),
            ]),
          );
        },
      ),
    );
  }
}
