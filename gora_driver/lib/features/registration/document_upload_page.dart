import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/driver_provider.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import 'widgets/reg_ui.dart';
import '../../services/driver_api_service.dart';
import 'document_detail_page.dart';
import 'kyc_success_page.dart';

// Documents asked for at registration. The admin manages the list
// (GET /document-types); this is the fallback when that call fails or is
// empty. Each opens its own detail page where the driver enters the number
// (+ expiry) and uploads front/back images.
const kDefaultDocSpecs = <DocSpec>[
  DocSpec(key: 'aadhaar', name: 'Aadhaar Card', numberLabel: 'Aadhaar Number', needsBack: true, category: 'identity'),
  DocSpec(key: 'pan', name: 'PAN Card', numberLabel: 'PAN Number', category: 'identity'),
  DocSpec(key: 'rc', name: 'RC Book', numberLabel: 'RC Book Number', category: 'vehicle'),
  DocSpec(key: 'insurance', name: 'Vehicle Insurance', numberLabel: 'Insurance Number', needsBack: true, needsExpiry: true,
      category: 'vehicle'),
  DocSpec(key: 'dl', name: 'Driving License', numberLabel: 'License Number', category: 'driving'),
];

/// Section header shown above each document category on the list page.
const kDocCategoryTitles = <String, String>{
  'identity': 'Identity',
  'vehicle': 'Vehicle',
  'driving': 'Driving licence',
  'other': 'Other',
};

/// [specs] in category order (Identity, Vehicle, Driving licence, Other),
/// keeping server order inside each category. Empty categories are left out.
List<(String, List<DocSpec>)> groupDocSpecs(List<DocSpec> specs) => [
      for (final c in DocSpec.categories)
        if (specs.any((s) => s.category == c)) (c, specs.where((s) => s.category == c).toList()),
    ];

class DocumentUploadPage extends StatefulWidget {
  static const route = '/registration/documents';

  /// The driver's selected vehicle type name ('Cab', 'Bike' ...). When null
  /// the page looks in its route arguments ({'vehicleType': ...}), then the
  /// loaded profile, then fetches the profile.
  final String? vehicleType;

  /// Why the application could not be submitted yet — e.g. the server's
  /// "Please upload: …" when a resumed driver's saved documents are no longer
  /// complete. Shown as a banner on top. When null the page looks in its
  /// route arguments ({'error': ...}).
  final String? initialError;
  const DocumentUploadPage({super.key, this.vehicleType, this.initialError});
  @override
  State<DocumentUploadPage> createState() => _DocumentUploadPageState();
}

/// The active document list from GET /document-types, in server order —
/// or [kDefaultDocSpecs] when the reply has none we can use. Documents limited
/// to other vehicle types than [vehicleType] are dropped too, in case an older
/// server ignores ?vehicleType.
List<DocSpec> docSpecsFromApi(Map<String, dynamic> res, {String? vehicleType}) {
  final rows = res['documents'];
  if (rows is! List) return kDefaultDocSpecs;
  final seen = <String>{};
  final specs = <DocSpec>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final m = Map<String, dynamic>.from(r);
    if (m['isActive'] == false) continue;
    final s = DocSpec.fromJson(m);
    if (s != null && s.appliesTo(vehicleType) && seen.add(s.key)) specs.add(s);
  }
  return specs.isEmpty ? kDefaultDocSpecs : specs;
}

class _DocumentUploadPageState extends State<DocumentUploadPage> {
  List<DocSpec> _specs = kDefaultDocSpecs;
  final Map<String, DocData> _data = {};
  bool _loadingSpecs = true;
  bool _submitting = false;

  DocData _dataOf(DocSpec s) => _data.putIfAbsent(s.key, DocData.new);
  bool _done(DocSpec s) => _dataOf(s).isComplete(s);

  List<DocSpec> get _required => _specs.where((s) => s.required).toList();
  int get _completed => _required.where(_done).length;
  bool get _allComplete => _completed == _required.length;

  bool _started = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route arguments are only readable from here, not from initState.
    if (_started) return;
    _started = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    final e = (widget.initialError ?? (args is Map ? args['error'] : null) ?? '').toString().trim();
    _error = e.isEmpty ? null : e;
    _loadSpecs();
  }

  /// The driver's selected vehicle type, or '' when it cannot be found.
  Future<String> _vehicleType() async {
    String clean(Object? v) => (v ?? '').toString().trim();
    var t = clean(widget.vehicleType);
    if (t.isNotEmpty) return t;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) t = clean(args['vehicleType']);
    if (t.isNotEmpty) return t;
    try {
      t = clean(Provider.of<DriverProvider>(context, listen: false).vehicleType);
    } catch (_) {} // no provider above this page
    if (t.isNotEmpty) return t;
    try {
      final d = (await DriverApiService.getProfile())['driver'];
      if (d is Map) t = clean(d['selectedVehicleTypeName'] ?? d['vehicleType']);
    } catch (_) {}
    return t;
  }

  Future<void> _loadSpecs() async {
    var specs = kDefaultDocSpecs;
    try {
      final type = await _vehicleType();
      specs = docSpecsFromApi(await DriverApiService.getDocumentTypes(vehicleType: type), vehicleType: type);
    } catch (_) {}
    if (!mounted) return;
    setState(() { _specs = specs; _loadingSpecs = false; });
  }

  Future<void> _openDoc(DocSpec spec) async {
    final result = await Navigator.push<DocData>(
      context,
      MaterialPageRoute(builder: (_) => DocumentDetailPage(spec: spec, initial: _dataOf(spec).copy())),
    );
    if (result != null && mounted) setState(() => _data[spec.key] = result);
  }

  Future<void> _submit() async {
    final missing = _required.where((s) => !_done(s)).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please complete: ${missing.first.name}'), backgroundColor: AppColors.orange),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      // Optional documents go only when filled in completely.
      final docs = _specs.where(_done).map((s) {
        final d = _dataOf(s);
        return {
          'type': s.key,
          'name': s.name,
          'number': s.needsNumber ? d.number : '',
          'frontUrl': d.frontUrl,
          if (s.needsBack) 'backUrl': d.backUrl,
          if (s.needsExpiry) 'expiryDate': d.expiry,
          'fileUrl': d.frontUrl, // backward-compat with the old single-image field
        };
      }).toList();
      // finish: true — documents are the last registration step. The server
      // checks the required ones, then sets registrationStep='submitted' and
      // status='pending' (what the splash check relies on to land a
      // relaunched, not-yet-approved driver on "Under Review").
      final res = await DriverApiService.saveDocuments(docs, finish: true);
      if (!mounted) return;
      if (res['error'] != null) {
        // e.g. 400 {error: 'Please upload: Police Verification, RC Book', missing: [...]}:
        // say so and stay here so the driver can add them.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        // Submitted — the same screen a bank submit used to open, with the
        // back stack cleared: there is nothing left to go back to.
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
    final total = _required.length;
    return RegStepScaffold(
      step: CapRegSteps.documents,
      stepLabel: 'Documents',
      title: 'Upload your documents',
      subtitle: 'Clear, uncropped photos help us approve you faster.',
      heroExtra: _progressCard(total),
      bottom: RegCta(
        label: _allComplete ? 'Submit documents' : 'Complete all required documents to continue',
        loading: _submitting,
        onPressed: _allComplete && !_loadingSpecs ? _submit : null,
      ),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CapBanner(
              key: const ValueKey('doc_submit_error'),
              icon: Icons.error_outline_rounded,
              tone: CapTone.danger,
              title: "We couldn't submit your application yet",
              text: _error!,
            ),
          ),
        if (_loadingSpecs)
          // Static placeholders in the shape of the cards (no spinner).
          for (var i = 0; i < 3; i++)
            Container(
              height: 76,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(18)),
            )
        else
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Each section header / card fades in a beat after the one above.
            for (final (i, w) in _buildGroupedCards().indexed) RegEntrance(index: i, child: w),
          ]),
      ],
    );
  }

  /// On the hero: a ring "N/M" that sweeps to the new value each time a
  /// document is completed (orange, then green when all are done), with
  /// "3 of 5 required uploaded" beside it.
  Widget _progressCard(int total) {
    return Container(
      key: const ValueKey('doc_progress_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(children: [
        RegProgressRing(key: const ValueKey('doc_progress_ring'), done: _completed, total: total),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_completed of $total required uploaded',
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_allComplete ? 'All set. Submit when you are ready.' : 'Tap a document below to add it.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  static (IconData, Color) _categoryLook(String cat) => switch (cat) {
        'identity' => (Icons.badge_rounded, RegPalette.blue),
        'vehicle' => (Icons.directions_car_rounded, RegPalette.orange),
        'driving' => (Icons.card_membership_rounded, RegPalette.purple),
        _ => (Icons.folder_rounded, RegPalette.teal),
      };

  /// Cards under category headers. When every document is 'other' there is
  /// nothing to tell apart, so no headers at all.
  List<Widget> _buildGroupedCards() {
    final groups = groupDocSpecs(_specs);
    if (groups.length == 1 && groups.single.$1 == 'other') return _specs.map(_buildDocCard).toList();
    return [
      for (final (i, (cat, specs)) in groups.indexed) ...[
        Padding(
          key: ValueKey('doc_section_$cat'),
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 10),
          child: Row(children: [
            RegIconBadge(icon: _categoryLook(cat).$1, color: _categoryLook(cat).$2, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(kDocCategoryTitles[cat] ?? 'Other',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Cap.body(size: 14.5, weight: FontWeight.w800)),
            ),
            Text('${specs.where(_done).length}/${specs.length} done',
                style: Cap.caption(size: 12, color: Cap.muted).copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
        ...specs.map(_buildDocCard),
      ],
    ];
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
    final d = _dataOf(spec);
    final done = d.isComplete(spec);
    final thumb = d.frontUrl ?? '';
    final color = _categoryLook(spec.category).$2;
    final dur = regDuration(context, const Duration(milliseconds: 300));
    final radius = BorderRadius.circular(18);
    final badge = RegIconBadge(icon: _iconFor(spec.key), color: color, size: 52);
    return Padding(
      key: ValueKey('doc_card_${spec.key}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: RegPressScale(
        pressed: 0.98,
        child: AnimatedContainer(
          duration: dur,
          decoration: BoxDecoration(
            color: done ? Cap.green.withValues(alpha: 0.05) : Cap.surface,
            borderRadius: radius,
            border: Border.all(color: done ? Cap.green.withValues(alpha: 0.45) : RegPalette.hairline, width: 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: () => _openDoc(spec),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(
                    width: 52, height: 52,
                    child: Stack(clipBehavior: Clip.none, children: [
                      // Completed: the uploaded photo itself; until then the
                      // category-coloured icon.
                      if (done && thumb.isNotEmpty)
                        ClipRRect(
                          key: ValueKey('doc_thumb_${spec.key}'),
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 52, height: 52,
                            child: Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => badge),
                          ),
                        )
                      else
                        badge,
                      if (done)
                        Positioned(
                          right: -4, bottom: -4,
                          child: RegPopIn(
                            key: ValueKey('doc_done_${spec.key}'),
                            child: Container(
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color: Cap.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Cap.surface, width: 2),
                              ),
                              child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Cap.body(size: 15, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(done ? (d.number.isNotEmpty ? d.number : 'Completed') : _requirementHint(spec),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
                      const SizedBox(height: 6),
                      // Only what this screen actually knows: nothing is
                      // reviewed until the application is submitted, so no
                      // "Under review" / "Rejected" here. The chip swaps with
                      // a quick fade + scale when a document is done.
                      AnimatedSwitcher(
                        duration: dur,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: child),
                        ),
                        child: _DocChip(
                          key: ValueKey(done),
                          label: done ? 'Uploaded' : (spec.required ? 'Required' : 'Optional'),
                          color: done ? Cap.green : (spec.required ? RegPalette.orange : Cap.muted),
                          icon: done ? Icons.check_circle_rounded : (spec.required ? Icons.upload_rounded : null),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: RegPalette.field, shape: BoxShape.circle),
                    child: Icon(Icons.chevron_right_rounded, color: Cap.muted, size: 20),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _requirementHint(DocSpec s) {
    final parts = <String>[if (s.needsNumber) 'Number', s.frontLabel];
    if (s.needsBack) parts.add(s.backLabel);
    if (s.needsExpiry) parts.add('Expiry');
    return 'Needs: ${parts.join(", ")}';
  }
}

/// Small tinted status chip on a document card.
class _DocChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _DocChip({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      );
}
