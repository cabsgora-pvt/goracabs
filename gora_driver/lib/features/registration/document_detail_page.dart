import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/date_field.dart';
import '../../services/driver_api_service.dart';

// Describes one required document and which fields it needs.
class DocSpec {
  final String key;         // 'aadhaar' | 'pan' | 'rc' | 'insurance' | 'dl'
  final String name;        // 'Aadhaar Card'
  final String numberLabel; // 'Aadhaar Number'
  final bool needsBack;     // front + back image
  final bool needsExpiry;   // expiry date (insurance)
  const DocSpec({
    required this.key,
    required this.name,
    required this.numberLabel,
    this.needsBack = false,
    this.needsExpiry = false,
  });
}

// Data collected for one document.
class DocData {
  String number;
  String expiry; // ISO yyyy-MM-dd
  String? frontUrl;
  String? backUrl;
  DocData({this.number = '', this.expiry = '', this.frontUrl, this.backUrl});

  DocData copy() => DocData(number: number, expiry: expiry, frontUrl: frontUrl, backUrl: backUrl);

  bool isComplete(DocSpec s) =>
      number.trim().isNotEmpty &&
      (frontUrl?.isNotEmpty ?? false) &&
      (!s.needsBack || (backUrl?.isNotEmpty ?? false)) &&
      (!s.needsExpiry || expiry.isNotEmpty);
}

// Per-document form: number (+ expiry) + front (+ back) image upload.
// Returns the filled [DocData] via Navigator.pop when the driver taps Save.
class DocumentDetailPage extends StatefulWidget {
  final DocSpec spec;
  final DocData initial;
  const DocumentDetailPage({super.key, required this.spec, required this.initial});
  @override
  State<DocumentDetailPage> createState() => _DocumentDetailPageState();
}

class _DocumentDetailPageState extends State<DocumentDetailPage> {
  late final TextEditingController _number;
  DateTime? _expiry;
  String? _frontUrl, _backUrl;
  bool _frontBusy = false, _backBusy = false;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.initial.number);
    _frontUrl = widget.initial.frontUrl;
    _backUrl = widget.initial.backUrl;
    _expiry = parseDate(widget.initial.expiry);
  }

  @override
  void dispose() { _number.dispose(); super.dispose(); }

  Future<void> _pick(bool front) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;
    setState(() => front ? _frontBusy = true : _backBusy = true);
    try {
      final url = await DriverApiService.uploadFile(file);
      if (mounted) setState(() => front ? _frontUrl = url : _backUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => front ? _frontBusy = false : _backBusy = false);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await pickDate(context, initial: _expiry ?? now, first: DateTime(now.year - 5), last: DateTime(now.year + 15));
    if (picked != null) setState(() => _expiry = picked);
  }

  void _save() {
    final s = widget.spec;
    if (_number.text.trim().isEmpty) return _err('Please enter the ${s.numberLabel}');
    if ((_frontUrl ?? '').isEmpty) return _err('Please upload the front image');
    if (s.needsBack && (_backUrl ?? '').isEmpty) return _err('Please upload the back image');
    if (s.needsExpiry && _expiry == null) return _err('Please select the expiry date');
    Navigator.pop(context, DocData(
      number: _number.text.trim(),
      expiry: _expiry == null ? '' : fmtDate(_expiry!), // dd-MM-yyyy
      frontUrl: _frontUrl,
      backUrl: _backUrl,
    ));
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppColors.orange));

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return Scaffold(
      appBar: blueAppBar(s.name),
      backgroundColor: AppColors.cardBg,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Number field
        Text(s.numberLabel, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _number,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Enter ${s.numberLabel}',
            filled: true, fillColor: AppColors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.divider)),
          ),
        ),
        // Expiry (insurance)
        if (s.needsExpiry) ...[
          const SizedBox(height: 16),
          DateField(label: 'Expiry Date', value: _expiry, hint: 'Select expiry date (dd-mm-yyyy)', onTap: _pickExpiry),
        ],
        const SizedBox(height: 20),
        // Images
        _imageTile('Front Image', _frontUrl, _frontBusy, () => _pick(true)),
        if (s.needsBack) ...[
          const SizedBox(height: 12),
          _imageTile('Back Image', _backUrl, _backBusy, () => _pick(false)),
        ],
        const SizedBox(height: 28),
        PrimaryButton(label: 'Save', onTap: _save),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _imageTile(String label, String? url, bool busy, VoidCallback onPick) {
    final has = (url ?? '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: has ? AppColors.green : AppColors.divider, width: has ? 1.5 : 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.divider)),
          child: has
              ? ClipRRect(borderRadius: BorderRadius.circular(7),
                  child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_rounded, color: AppColors.primary)))
              : Icon(Icons.upload_file_rounded, color: AppColors.textGrey, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 14)),
          const SizedBox(height: 4),
          has
              ? const Row(children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                  SizedBox(width: 4),
                  Text('Uploaded', style: TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                ])
              : Text('Not uploaded', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
        ])),
        busy
            ? const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : TextButton(
                onPressed: onPick,
                style: TextButton.styleFrom(
                  backgroundColor: has ? AppColors.cardBg : AppColors.primary.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(has ? 'Change' : 'Upload', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
      ]),
    );
  }
}
