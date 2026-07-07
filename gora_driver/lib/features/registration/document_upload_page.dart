import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
// import 'bank_details_page.dart'; // Bank details deferred — driver can add later from settings
import 'document_detail_page.dart';
import 'kyc_success_page.dart';

// Documents required at registration. Each opens its own detail page where the
// driver enters the number (+ expiry for insurance) and uploads front/back images.
const _docSpecs = <DocSpec>[
  DocSpec(key: 'aadhaar', name: 'Aadhaar Card', numberLabel: 'Aadhaar Number', needsBack: true),
  DocSpec(key: 'pan', name: 'PAN Card', numberLabel: 'PAN Number'),
  DocSpec(key: 'rc', name: 'RC Book', numberLabel: 'RC Book Number'),
  DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number', needsBack: true, needsExpiry: true),
  DocSpec(key: 'dl', name: 'Driving License', numberLabel: 'License Number'),
];

class DocumentUploadPage extends StatefulWidget {
  static const route = '/registration/documents';
  const DocumentUploadPage({super.key});
  @override
  State<DocumentUploadPage> createState() => _DocumentUploadPageState();
}

class _DocumentUploadPageState extends State<DocumentUploadPage> {
  final Map<String, DocData> _data = {for (final s in _docSpecs) s.key: DocData()};
  bool _submitting = false;

  int get _completed => _docSpecs.where((s) => _data[s.key]!.isComplete(s)).length;
  bool get _allComplete => _completed == _docSpecs.length;

  Future<void> _openDoc(DocSpec spec) async {
    final result = await Navigator.push<DocData>(
      context,
      MaterialPageRoute(builder: (_) => DocumentDetailPage(spec: spec, initial: _data[spec.key]!.copy())),
    );
    if (result != null && mounted) setState(() => _data[spec.key] = result);
  }

  Future<void> _submit() async {
    final missing = _docSpecs.where((s) => !_data[s.key]!.isComplete(s)).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please complete: ${missing.first.name}'), backgroundColor: AppColors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final docs = _docSpecs.map((s) {
        final d = _data[s.key]!;
        return {
          'type': s.key,
          'name': s.name,
          'number': d.number,
          'frontUrl': d.frontUrl,
          if (s.needsBack) 'backUrl': d.backUrl,
          if (s.needsExpiry) 'expiryDate': d.expiry,
          'fileUrl': d.frontUrl, // backward-compat with the old single-image field
        };
      }).toList();
      final res = await DriverApiService.saveDocuments(docs);
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        // Bank details deferred — skip directly to KYC success
        // Navigator.pushNamed(context, BankDetailsPage.route);
        Navigator.pushNamedAndRemoveUntil(context, KycSuccessPage.route, (_) => false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 12),
                // Completed counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                  child: Row(children: [
                    Icon(_allComplete ? Icons.check_circle : Icons.folder_open, color: _allComplete ? AppColors.green : AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('$_completed of ${_docSpecs.length} documents completed',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13))),
                    Text('${((_completed / _docSpecs.length) * 100).round()}%',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
                ),
                const SizedBox(height: 16),
                ..._docSpecs.map(_buildDocCard),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _allComplete ? 'Submit Documents' : 'Complete All Documents to Continue',
                  loading: _submitting,
                  onTap: _allComplete ? _submit : null,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard(DocSpec spec) {
    final d = _data[spec.key]!;
    final done = d.isComplete(spec);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? AppColors.green : AppColors.divider, width: done ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDoc(spec),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(done ? Icons.check_circle_rounded : Icons.description_outlined,
                  color: done ? AppColors.green : AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  done ? 'Completed' : _requirementHint(spec),
                  style: TextStyle(color: done ? AppColors.green : AppColors.textGrey, fontSize: 12, fontWeight: done ? FontWeight.w600 : FontWeight.normal),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
          ]),
        ),
      ),
    );
  }

  String _requirementHint(DocSpec s) {
    final parts = <String>['Number', 'Front'];
    if (s.needsBack) parts.add('Back');
    if (s.needsExpiry) parts.add('Expiry');
    return 'Needs: ${parts.join(", ")}';
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
                  'Step 3 of 3 — Upload all required documents',
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
      children: List.generate(3, (i) => Expanded(
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
