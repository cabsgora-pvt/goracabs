import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

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
                color: Color(0xFF111111),
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

  CapStatus _status(String s) {
    switch (s) {
      case 'verified':
      case 'approved':
        return CapStatus.done;
      case 'rejected':
        return CapStatus.rejected;
      case 'expired':
        return CapStatus.expired;
      default:
        return CapStatus.review;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DriverProvider>();
    final docs = dp.documents;

    return Scaffold(
      appBar: blueAppBar('Documents'),
      backgroundColor: Cap.tile,
      body: dp.loading && docs.isEmpty
          ? const AppLoader()
          : docs.isEmpty
              ? const CapEmpty(icon: Icons.folder_open_rounded, title: 'No documents uploaded yet')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final name = doc['name'] as String? ?? 'Document';
                    final url = doc['fileUrl'] as String? ?? '';
                    final number = (doc['number'] ?? '').toString();
                    final status = doc['status'] as String? ?? 'pending';
                    final color = _statusColor(status);

                    return CapCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () => _previewDoc(context, name, url),
                      child: Row(children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: url.isNotEmpty
                              ? Image.network(
                                  url,
                                  width: 52, height: 52, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _docIcon(color),
                                )
                              : _docIcon(color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: Cap.body(size: 14.5, weight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(number.isNotEmpty ? number : 'Tap to view',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        CapStatusChip(_status(status), label: _status(status) == CapStatus.done ? 'Verified' : null),
                      ]),
                    );
                  },
                ),
    );
  }

  Widget _docIcon(Color color) => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(12)),
    child: Icon(Icons.description_outlined, color: Cap.ink, size: 24),
  );
}
