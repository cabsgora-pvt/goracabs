import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_step_scaffold.dart';
import '../../services/driver_api_service.dart';
import 'bank_details_page.dart';
import 'document_detail_page.dart';

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
        // Documents saved (server: registrationStep='bank'). Bank details are
        // the last step — /register/bank is what moves the server to
        // registrationStep='submitted', which the splash check relies on to
        // land a relaunched, not-yet-approved driver on "Under Review".
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
    final pct = _completed / _docSpecs.length;
    return RegStepScaffold(
      step: CapRegSteps.documents,
      stepLabel: 'Documents',
      title: 'Upload your documents',
      subtitle: 'Clear, uncropped photos help us approve you faster.',
      bottom: CapButton(
        label: _allComplete ? 'Submit documents' : 'Complete all documents to continue',
        loading: _submitting,
        onPressed: _allComplete ? _submit : null,
      ),
      children: [
        // Progress: "3 of 5 done".
        Row(children: [
          Expanded(
            child: Text('$_completed of ${_docSpecs.length} uploaded',
                style: Cap.body(size: 13.5, weight: FontWeight.w800)),
          ),
          Text('${(pct * 100).round()}%', style: Cap.body(size: 13.5, weight: FontWeight.w800, color: Cap.accent)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: Cap.divider,
            color: _allComplete ? Cap.green : Cap.accent,
          ),
        ),
        const SizedBox(height: 18),
        ..._docSpecs.map(_buildDocCard),
      ],
    );
  }

  static IconData _iconFor(String key) => switch (key) {
        'aadhaar' => Icons.badge_outlined,
        'pan' => Icons.credit_card_rounded,
        'rc' => Icons.menu_book_rounded,
        'insurance' => Icons.verified_user_outlined,
        'dl' => Icons.card_membership_rounded,
        _ => Icons.description_outlined,
      };

  Widget _buildDocCard(DocSpec spec) {
    final d = _data[spec.key]!;
    final done = d.isComplete(spec);
    final thumb = d.frontUrl ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CapCard(
        padding: const EdgeInsets.all(12),
        onTap: () => _openDoc(spec),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(12)),
            child: thumb.isNotEmpty
                ? Image.network(thumb, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(_iconFor(spec.key), color: Cap.ink, size: 24))
                : Icon(_iconFor(spec.key), color: Cap.ink, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Cap.body(size: 14.5, weight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(done ? (d.number.isNotEmpty ? d.number : 'Completed') : _requirementHint(spec),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          // Only what this screen actually knows: nothing is reviewed until the
          // application is submitted, so no "Under review" / "Rejected" here.
          CapStatusChip(done ? CapStatus.done : CapStatus.pending, label: done ? 'Uploaded' : 'Required'),
          Icon(Icons.chevron_right_rounded, color: Cap.muted),
        ]),
      ),
    );
  }

  String _requirementHint(DocSpec s) {
    final parts = <String>['Number', 'Front'];
    if (s.needsBack) parts.add('Back');
    if (s.needsExpiry) parts.add('Expiry');
    return 'Needs: ${parts.join(", ")}';
  }
}
