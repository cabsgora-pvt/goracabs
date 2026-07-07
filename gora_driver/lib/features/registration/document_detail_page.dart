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

  void _remove(bool front) => setState(() => front ? _frontUrl = null : _backUrl = null);

  // Full-screen zoomable preview of the uploaded image.
  void _previewImage(String label, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Flexible(
            child: Container(
              color: Colors.white,
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(40), child: Text('Could not load image')),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
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
        _imageTile('Front Image', _frontUrl, _frontBusy, () => _pick(true), () => _remove(true)),
        if (s.needsBack) ...[
          const SizedBox(height: 16),
          _imageTile('Back Image', _backUrl, _backBusy, () => _pick(false), () => _remove(false)),
        ],
        const SizedBox(height: 28),
        PrimaryButton(label: 'Save', onTap: _save),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _imageTile(String label, String? url, bool busy, VoidCallback onPick, VoidCallback onRemove) {
    final has = (url ?? '').isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
      const SizedBox(height: 6),
      // Framed preview / upload dropzone
      GestureDetector(
        onTap: busy ? null : (has ? () => _previewImage(label, url!) : onPick),
        child: Container(
          height: 180,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: has ? AppColors.green : AppColors.divider, width: has ? 1.5 : 1),
          ),
          child: busy
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : has
                  ? Stack(fit: StackFit.expand, children: [
                      Image.network(url!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textGrey, size: 40))),
                      Positioned(
                        top: 8, left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(20)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Uploaded', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 40),
                      const SizedBox(height: 8),
                      Text('Tap to upload $label', style: TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w500)),
                    ]),
        ),
      ),
      // Change / Remove actions once an image is present
      if (has && !busy) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.primary),
              label: const Text('Change', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.red),
              label: const Text('Remove', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.red.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ]),
      ],
    ]);
  }
}
