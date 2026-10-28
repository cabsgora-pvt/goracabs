import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../widgets/captain_ui/captain_ui.dart';
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
              color: Color(0xFF111111),
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
      backgroundColor: Cap.surface,
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        // Example: what a good photo looks like.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Cap.accent.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              width: 64, height: 44,
              decoration: BoxDecoration(
                color: Cap.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Cap.green, width: 2),
              ),
              child: Icon(Icons.badge_outlined, color: Cap.ink, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Upload a clear photo', style: Cap.body(size: 14, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (final tip in const ['All four corners visible', 'No glare or blur', 'Every detail readable'])
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, size: 14, color: Cap.green),
                    const SizedBox(width: 6),
                    Flexible(child: Text(tip, style: Cap.caption(size: 12.5, color: Cap.ink))),
                  ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        CapField(
          label: s.numberLabel,
          required: true,
          child: TextField(
            controller: _number,
            textCapitalization: TextCapitalization.characters,
            style: Cap.body(size: 15.5, weight: FontWeight.w700).copyWith(letterSpacing: 0.8),
            decoration: Cap.input(hint: 'Enter ${s.numberLabel}'),
          ),
        ),
        // Expiry (insurance)
        if (s.needsExpiry) ...[
          DateField(label: 'Expiry Date', value: _expiry, hint: 'Select expiry date (dd-mm-yyyy)', onTap: _pickExpiry),
          const SizedBox(height: 18),
        ],
        // Images
        _imageTile('Front side', _frontUrl, _frontBusy, () => _pick(true), () => _remove(true)),
        if (s.needsBack) ...[
          const SizedBox(height: 18),
          _imageTile('Back side', _backUrl, _backBusy, () => _pick(false), () => _remove(false)),
        ],
      ]),
      bottomNavigationBar: CapBottomBar(child: CapButton(label: 'Save', onPressed: _save)),
    );
  }

  Widget _imageTile(String label, String? url, bool busy, VoidCallback onPick, VoidCallback onRemove) {
    final has = (url ?? '').isNotEmpty;
    final src = url ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CapLabel(label, required: true),
      if (busy)
        CapDashedBox(
          height: 150,
          child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: Cap.accent))),
        )
      else if (has)
        GestureDetector(
          onTap: () => _previewImage(label, src),
          child: Container(
            height: 170,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Cap.tile,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Cap.green, width: 1.5),
            ),
            child: Stack(fit: StackFit.expand, children: [
              Image.network(src, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: Cap.muted, size: 36))),
              const Positioned(top: 8, left: 8, child: CapChip('Uploaded', color: AppColors.green, icon: Icons.check_circle_rounded, solid: true)),
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        )
      else
        CapDashedBox(
          height: 170,
          onTap: onPick,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: Cap.surface, shape: BoxShape.circle),
              child: Icon(Icons.photo_camera_rounded, color: Cap.ink, size: 22),
            ),
            const SizedBox(height: 10),
            Text('Tap to upload', style: Cap.body(size: 13.5, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: Cap.caption(size: 12)),
          ]),
        ),
      // Change / Remove actions once an image is present
      if (has && !busy) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: onPick,
              icon: Icon(Icons.photo_camera_outlined, size: 18, color: Cap.ink),
              label: Text('Retake', style: Cap.body(size: 13, weight: FontWeight.w700)),
              style: TextButton.styleFrom(
                backgroundColor: Cap.tile,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.red),
              label: Text('Remove', style: Cap.body(size: 13, weight: FontWeight.w700, color: AppColors.red)),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.red.withValues(alpha: 0.08),
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
