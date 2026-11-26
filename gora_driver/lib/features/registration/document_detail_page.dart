import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import '../../core/widgets/date_field.dart';
import '../../services/driver_api_service.dart';
import '../../services/token_store.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import 'widgets/reg_ui.dart';

// Describes one registration document and which fields it needs.
class DocSpec {
  /// The categories the list page groups by, in display order.
  static const categories = ['identity', 'vehicle', 'driving', 'other'];

  final String key;         // 'aadhaar' | 'pan' | ... or an admin-defined key
  final String name;        // 'Aadhaar Card'
  final String numberLabel; // 'Aadhaar Number'
  final bool needsBack;     // front + back image
  final bool needsExpiry;   // expiry date (insurance)
  final bool required;      // optional ones may be skipped
  final String category;    // one of [categories]
  final String description; // admin's instructions for the driver, may be ''
  final bool needsNumber;   // false = photo only, no number field
  final String frontLabel;  // label of the first photo
  final String backLabel;   // label of the second photo
  final List<String> vehicleTypes; // [] = every vehicle type
  const DocSpec({
    required this.key,
    required this.name,
    required this.numberLabel,
    this.needsBack = false,
    this.needsExpiry = false,
    this.required = true,
    this.category = 'other',
    this.description = '',
    this.needsNumber = true,
    this.frontLabel = 'Front side',
    this.backLabel = 'Back side',
    this.vehicleTypes = const [],
  });

  /// One row of GET /api/document-types. Null when it has no key or name.
  /// Older servers send none of category/description/needsNumber/labels/
  /// vehicleTypes, so each has a default that matches the old behaviour.
  static DocSpec? fromJson(Map<String, dynamic> m) {
    String str(String k) => (m[k] ?? '').toString().trim();
    final key = str('key');
    final name = str('name');
    if (key.isEmpty || name.isEmpty) return null;
    final label = str('numberLabel');
    final cat = str('category').toLowerCase();
    final front = str('frontLabel');
    final back = str('backLabel');
    final types = m['vehicleTypes'];
    return DocSpec(
      key: key,
      name: name,
      numberLabel: label.isNotEmpty ? label : 'Document Number',
      needsBack: m['needsBack'] == true,
      needsExpiry: m['needsExpiry'] == true,
      required: m['required'] != false,
      category: categories.contains(cat) ? cat : 'other',
      description: str('description'),
      needsNumber: m['needsNumber'] != false,
      frontLabel: front.isNotEmpty ? front : 'Front side',
      backLabel: back.isNotEmpty ? back : 'Back side',
      vehicleTypes: types is List
          ? types.map((t) => t.toString().trim()).where((t) => t.isNotEmpty).toList()
          : const [],
    );
  }

  /// Whether this document applies to [vehicleType] (case-insensitive).
  /// An empty [vehicleTypes] list, or an unknown vehicle type, means yes.
  bool appliesTo(String? vehicleType) {
    final t = (vehicleType ?? '').trim().toLowerCase();
    if (t.isEmpty || vehicleTypes.isEmpty) return true;
    return vehicleTypes.any((v) => v.toLowerCase() == t);
  }
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
      (!s.needsNumber || number.trim().isNotEmpty) &&
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

/// Asks where a document photo comes from: the camera (listed first, the
/// default) or the gallery. Null when dismissed.
Future<ImageSource?> pickPhotoSource(BuildContext context) => showModalBottomSheet<ImageSource>(
  context: context,
  showDragHandle: true,
  builder: (c) => SafeArea(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        key: const ValueKey('photo_source_camera'),
        leading: const Icon(Icons.photo_camera_outlined),
        title: const Text('Take a photo'),
        subtitle: const Text('Recommended — place the document flat, in good light'),
        onTap: () => Navigator.pop(c, ImageSource.camera),
      ),
      ListTile(
        key: const ValueKey('photo_source_gallery'),
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text('Choose from gallery'),
        onTap: () => Navigator.pop(c, ImageSource.gallery),
      ),
      const SizedBox(height: 8),
    ]),
  ),
);

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
    // Camera first: a document is usually photographed there and then. The
    // gallery is still offered for a photo already taken.
    final source = await pickPhotoSource(context);
    if (source == null || !mounted) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 70,
        maxWidth: DriverApiService.maxImageSide, maxHeight: DriverApiService.maxImageSide);
    if (file == null) return;
    setState(() => front ? _frontBusy = true : _backBusy = true);
    try {
      // KYC documents are private uploads (/api/files/…, shown with the token).
      final url = await DriverApiService.uploadFile(file, private: true, purpose: 'kyc');
      if (!mounted) return;
      if (url == null) {
        // Keep the photo that was there; say why this one did not go up.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DriverApiService.lastUploadError ?? 'Upload failed'), backgroundColor: AppColors.red));
      } else {
        setState(() => front ? _frontUrl = url : _backUrl = url);
      }
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
                  headers: imageHeadersFor(url),
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
    if (s.needsNumber && _number.text.trim().isEmpty) return _err('Please enter the ${s.numberLabel}');
    if ((_frontUrl ?? '').isEmpty) return _err('Please upload the photo: ${s.frontLabel}');
    if (s.needsBack && (_backUrl ?? '').isEmpty) return _err('Please upload the photo: ${s.backLabel}');
    if (s.needsExpiry && _expiry == null) return _err('Please select the expiry date');
    Navigator.pop(context, DocData(
      number: s.needsNumber ? _number.text.trim() : '',
      expiry: _expiry == null ? '' : fmtDate(_expiry!), // dd-MM-yyyy
      frontUrl: _frontUrl,
      backUrl: _backUrl,
    ));
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppColors.orange));

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    // Part of the documents step, so it carries the same "Step 4 of 4" header;
    // the document's name is the page title. Fields are unchanged.
    return RegStepScaffold(
      step: CapRegSteps.documents,
      stepLabel: 'Documents',
      title: s.name,
      subtitle: 'Add the details and a clear photo of this document.',
      bottom: RegCta(label: 'Save', trailing: Icons.check_rounded, onPressed: _save),
      children: [
        // The admin's instructions for this document.
        if (s.description.isNotEmpty)
          Container(
            key: const ValueKey('doc_description'),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Cap.accent.withValues(alpha: 0.10), Cap.accent.withValues(alpha: 0.03)],
              ),
              border: Border.all(color: Cap.accent.withValues(alpha: 0.18)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RegIconBadge(icon: Icons.info_rounded, color: Cap.accent, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.description, style: Cap.caption(size: 13, color: Cap.ink).copyWith(height: 1.4)),
                ),
              ),
            ]),
          ),
        // What a good photo looks like.
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RegPalette.field,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const RegIconBadge(icon: Icons.photo_camera_back_rounded, color: RegPalette.green, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text('Upload a clear photo', style: Cap.body(size: 14, weight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tip in const ['All four corners visible', 'No glare or blur', 'Every detail readable'])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Cap.surface, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_rounded, size: 14, color: Cap.green),
                    const SizedBox(width: 5),
                    Flexible(child: Text(tip, style: Cap.caption(size: 12, color: Cap.ink))),
                  ]),
                ),
            ]),
          ]),
        ),
        if (s.needsNumber)
          RegField(
            label: s.numberLabel,
            required: true,
            child: TextField(
              controller: _number,
              textCapitalization: TextCapitalization.characters,
              style: Cap.body(size: 15.5, weight: FontWeight.w700).copyWith(letterSpacing: 0.8),
              decoration: regInput(hint: 'Enter ${s.numberLabel}', icon: Icons.tag_rounded),
            ),
          ),
        // Expiry (insurance)
        if (s.needsExpiry)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: DateField(label: 'Expiry Date', value: _expiry, hint: 'Select expiry date (dd-mm-yyyy)', onTap: _pickExpiry),
          ),
        // Images
        _imageTile(s.frontLabel, _frontUrl, _frontBusy, () => _pick(true), () => _remove(true)),
        if (s.needsBack)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _imageTile(s.backLabel, _backUrl, _backBusy, () => _pick(false), () => _remove(false)),
          ),
      ],
    );
  }

  Widget _imageTile(String label, String? url, bool busy, VoidCallback onPick, VoidCallback onRemove) {
    final has = (url ?? '').isNotEmpty;
    final src = url ?? '';
    final state = busy ? 'busy' : (has ? 'has:$src' : 'empty');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CapLabel(label, required: true),
      // Uploading → uploaded → empty cross-fade with a slight zoom; the
      // "Uploaded" chip pops in once the photo is there.
      AnimatedSwitcher(
        duration: regDuration(context, const Duration(milliseconds: 280)),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(key: ValueKey(state), child: _imageBody(label, src, has, busy, onPick)),
      ),
      // Change / Remove actions once an image is present
      if (has && !busy) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: onPick,
              icon: Icon(Icons.photo_camera_outlined, size: 18, color: Cap.accent),
              label: Text('Retake', style: Cap.body(size: 13, weight: FontWeight.w700, color: Cap.accent)),
              style: TextButton.styleFrom(
                backgroundColor: Cap.accent.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 11),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ]),
      ],
    ]);
  }

  Widget _imageBody(String label, String src, bool has, bool busy, VoidCallback onPick) {
    if (busy) {
      return RegDropZone(
        height: 168,
        child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Cap.accent))),
      );
    }
    if (has) {
      return GestureDetector(
        onTap: () => _previewImage(label, src),
        child: Container(
          height: 176,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Cap.tile,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Cap.green, width: 2),
          ),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(src, headers: imageHeadersFor(src), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: Cap.muted, size: 36))),
            const Positioned(
              top: 10, left: 10,
              child: RegPopIn(child: CapChip('Uploaded', color: AppColors.green, icon: Icons.check_circle_rounded, solid: true)),
            ),
            Positioned(
              top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      );
    }
    return RegPressScale(
      child: RegDropZone(
        height: 168,
        onTap: onPick,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RegPalette.ctaAction,
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 12),
          Text('Tap to upload', style: Cap.body(size: 14, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
        ]),
      ),
    );
  }
}
