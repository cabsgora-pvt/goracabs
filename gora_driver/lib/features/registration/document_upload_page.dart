import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
import 'bank_details_page.dart';

const _requiredDocs = [
  'Aadhaar Card',
  'PAN Card',
  'RC Book (Vehicle Registration)',
  'PUC Certificate',
  'Vehicle Insurance',
  'Driving License',
];

class DocumentUploadPage extends StatefulWidget {
  static const route = '/registration/documents';
  const DocumentUploadPage({super.key});
  @override
  State<DocumentUploadPage> createState() => _DocumentUploadPageState();
}

class _DocumentUploadPageState extends State<DocumentUploadPage> {
  final Map<String, String?> _uploadedUrls = {for (final d in _requiredDocs) d: null};
  final Map<String, bool> _uploading = {for (final d in _requiredDocs) d: false};
  bool _submitting = false;

  Future<void> _pickAndUpload(String docName) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;

    setState(() => _uploading[docName] = true);
    try {
      final url = await DriverApiService.uploadFile(file);
      if (mounted) setState(() => _uploadedUrls[docName] = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading[docName] = false);
    }
  }

  Future<void> _submit() async {
    final missing = _requiredDocs.where((d) => _uploadedUrls[d] == null).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload: ${missing.first}'), backgroundColor: AppColors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final docs = _requiredDocs.map((d) => {'name': d, 'fileUrl': _uploadedUrls[d]!}).toList();
      final res = await DriverApiService.saveDocuments(docs);
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        Navigator.pushNamed(context, BankDetailsPage.route);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allUploaded = _requiredDocs.every((d) => _uploadedUrls[d] != null);
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 8),
                _stepIndicator(3),
                const SizedBox(height: 16),
                ..._requiredDocs.map((docName) => _buildDocCard(docName)),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: allUploaded ? 'Continue' : 'Upload All Documents to Continue',
                  loading: _submitting,
                  onTap: allUploaded ? _submit : null,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard(String docName) {
    final url = _uploadedUrls[docName];
    final isUploading = _uploading[docName] == true;
    final uploaded = url != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: uploaded ? AppColors.green : AppColors.divider,
          width: uploaded ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail or placeholder
            GestureDetector(
              onTap: uploaded ? () => _showPreview(context, url!) : null,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.cardBg,
                  border: Border.all(color: AppColors.divider),
                ),
                child: uploaded
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          url!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_rounded, color: AppColors.primary),
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded, color: AppColors.textGrey, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(docName, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontSize: 14)),
                  const SizedBox(height: 4),
                  uploaded
                      ? const Row(children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                          SizedBox(width: 4),
                          Text('Uploaded', style: TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                        ])
                      : const Text('Not uploaded', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isUploading
                ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : TextButton(
                    onPressed: () => _pickAndUpload(docName),
                    style: TextButton.styleFrom(
                      backgroundColor: uploaded ? AppColors.cardBg : AppColors.primary.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      uploaded ? 'Change' : 'Upload',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Upload Documents',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Step 3 of 4 — Upload all required documents',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIndicator(int current) {
    return Row(
      children: List.generate(4, (i) => Expanded(
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: i < current ? AppColors.primary : AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    );
  }
}
