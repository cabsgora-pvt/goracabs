import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';

class DocumentsPage extends StatefulWidget {
  static const route = '/documents';
  const DocumentsPage({super.key});
  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DriverProvider>().loadProfile();
    });
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'verified':
      case 'approved':
        return AppColors.green;
      case 'rejected':
        return AppColors.red;
      default:
        return AppColors.orange;
    }
  }

  void _previewDoc(BuildContext context, String name, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ]),
            ),
            Flexible(
              child: Container(
                color: Colors.white,
                child: url.isEmpty
                    ? const Padding(padding: EdgeInsets.all(40), child: Text('No image uploaded'))
                    : InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('Could not load image'),
                          ),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : const Padding(
                                padding: EdgeInsets.all(40),
                                child: CircularProgressIndicator(color: AppColors.primary),
                              ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DriverProvider>();
    final docs = dp.documents;

    return Scaffold(
      appBar: blueAppBar('My Documents'),
      backgroundColor: AppColors.cardBg,
      body: dp.loading && docs.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : docs.isEmpty
              ? const Center(child: Text('No documents uploaded yet', style: TextStyle(color: AppColors.textGrey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final name = doc['name'] as String? ?? 'Document';
                    final url = doc['fileUrl'] as String? ?? '';
                    final status = doc['status'] as String? ?? 'pending';
                    final color = _statusColor(status);

                    return GestureDetector(
                      onTap: () => _previewDoc(context, name, url),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6)],
                        ),
                        child: Row(children: [
                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: url.isNotEmpty
                                ? Image.network(
                                    url,
                                    width: 52, height: 52, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _docIcon(color),
                                  )
                                : _docIcon(color),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
                              const SizedBox(height: 2),
                              const Text('Tap to view', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                            child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _docIcon(Color color) => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(10)),
    child: Icon(Icons.description, color: color, size: 26),
  );
}
