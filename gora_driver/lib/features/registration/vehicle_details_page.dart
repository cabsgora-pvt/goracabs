import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import '../../services/driver_api_service.dart';
import 'document_upload_page.dart';
import 'widgets/reg_ui.dart';
import 'widgets/vehicle_visuals.dart';
import 'registration_draft.dart';
import 'vehicle_categories.dart';
import 'vehicle_selection_page.dart' show VehicleSelectionPage;

/// Why /register/vehicle refused the vehicle for the chosen type
/// (400 {code: 'VEHICLE_NOT_ELIGIBLE', error, problems: [...]}): every
/// problem, or the error alone when the list is missing. Empty for any other
/// reply.
List<String> vehicleEligibilityProblems(Map<String, dynamic> res) {
  if (res['code'] != 'VEHICLE_NOT_ELIGIBLE') return const [];
  final p = res['problems'];
  final list = p is List ? p.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList() : <String>[];
  if (list.isNotEmpty) return list;
  final e = (res['error'] ?? '').toString().trim();
  return [e.isNotEmpty ? e : 'This vehicle does not meet the rules for this type'];
}

class VehicleDetailsPage extends StatefulWidget {
  static const route = '/registration/vehicle-details';
  const VehicleDetailsPage({super.key});
  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  final _form = GlobalKey<FormState>();
  final _regNumber = TextEditingController();
  final _vehicleModel = TextEditingController();
  bool _loading = false;
  late Map<String, dynamic> _vehicle;
  bool _restored = false;
  /// The vehicle's model year (tier rules: "2019 or newer").
  int? _year;
  /// Bumped when a draft restores the year, so the picker shows it.
  int _yearGen = 0;
  /// The server's BAD_YEAR message, shown under the picker until it changes.
  String? _yearError;
  /// The server's VEHICLE_NOT_ELIGIBLE reasons for the chosen type.
  List<String> _problems = const [];

  // What is typed here survives the app closing mid-form (RegistrationDraft).
  late final DraftSaver _draft = DraftSaver(RegistrationDraft.vehicle, () => {
    'model': _vehicleModel.text, 'regNumber': _regNumber.text, 'year': _year?.toString(),
  });

  @override
  void initState() {
    super.initState();
    RegistrationDraft.sealed = false; // filling in (again): drafts are kept
    _regNumber.addListener(_draft.schedule);
    _vehicleModel.addListener(_draft.schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _vehicle = Map<String, dynamic>.from(args?['vehicle'] as Map? ?? {});
    if (_restored) return;
    _restored = true;
    RegistrationDraft.load(RegistrationDraft.vehicle).then((d) {
      if (!mounted || d.isEmpty) return;
      RegistrationDraft.restoreInto(_vehicleModel, d, 'model');
      RegistrationDraft.restoreInto(_regNumber, d, 'regNumber');
      final y = int.tryParse(d['year'] ?? '');
      if (_year == null && y != null && modelYearOptions().contains(y)) {
        setState(() { _year = y; _yearGen++; });
      }
    });
  }

  /// Back to the vehicle types — the page below, or (resumed straight into
  /// this step) a fresh one.
  void _changeType() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(VehicleSelectionPage.route);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _loading = true; _problems = const []; _yearError = null; });
    try {
      final res = await DriverApiService.saveVehicle({
        'selectedVehicleTypeId': _vehicle['_id'] ?? _vehicle['id'],
        'selectedVehicleTypeName': _vehicle['name'],
        'vehicleRegistrationNumber': _regNumber.text.trim().toUpperCase(),
        'vehicleModel': _vehicleModel.text.trim(),
        'vehicleYear': _year,
      });
      if (!mounted) return;
      final problems = vehicleEligibilityProblems(res);
      if (problems.isNotEmpty) {
        // Shown as a list at the top, with a way to pick another type.
        setState(() => _problems = problems);
      } else if (res['code'] == 'BAD_YEAR') {
        final msg = (res['error'] ?? '').toString().trim();
        setState(() => _yearError = msg.isNotEmpty ? msg : 'Pick the model year from your RC book');
      } else if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        // The documents asked for depend on the vehicle type.
        Navigator.pushNamed(context, DocumentUploadPage.route, arguments: {'vehicleType': _vehicle['name']});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _draft.cancel();
    _draft.flush();
    _regNumber.dispose();
    _vehicleModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typeName = _vehicle['name'] as String? ?? '';
    return RegStepScaffold(
      step: CapRegSteps.vehicle,
      stepLabel: 'Vehicle',
      title: 'Vehicle details',
      subtitle: 'Enter them exactly as on your RC book.',
      bottom: RegCta(label: 'Continue', loading: _loading, onPressed: _submit),
      staggerChildren: false,
      children: [
        // Model, model year (v1.5.2 — a tier may need "2019 or newer") and
        // registration number, sent to /register/vehicle.
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (typeName.isNotEmpty)
              RegEntrance(
                index: RegStepScaffold.firstChildIndex,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _vehicleCard(typeName),
                ),
              ),
            if (_problems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _NotEligibleCard(typeName: typeName, problems: _problems, onChangeType: _changeType),
              ),
            RegEntrance(
              index: RegStepScaffold.firstChildIndex + 1,
              child: RegSectionCard(
                icon: Icons.directions_car_rounded,
                color: RegPalette.blue,
                title: 'Your vehicle',
                caption: 'As printed on your number plate and RC book.',
                children: [
                  RegField(
                    label: 'Vehicle name / model',
                    required: true,
                    child: TextFormField(
                      controller: _vehicleModel,
                      textCapitalization: TextCapitalization.words,
                      decoration: regInput(hint: 'e.g. Maruti Swift Dzire', icon: Icons.directions_car_filled_outlined),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle model is required' : null,
                    ),
                  ),
                  RegField(
                    label: 'Model year',
                    required: true,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      DropdownButtonFormField<int>(
                        key: ValueKey('vehicle_year_$_yearGen'),
                        initialValue: _year,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration: regInput(hint: 'Year on your RC book', icon: Icons.event_outlined,
                            iconColor: RegPalette.teal),
                        items: [
                          for (final y in modelYearOptions())
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        validator: (v) => v == null ? 'Model year is required' : null,
                        onChanged: (v) {
                          setState(() { _year = v; _yearError = null; });
                          _draft.schedule();
                        },
                      ),
                      if (_yearError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(_yearError!,
                              key: const ValueKey('vehicle_year_error'),
                              style: Cap.caption(size: 12.5, color: AppColors.red).copyWith(fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                  RegField(
                    label: 'Registration number',
                    required: true,
                    child: TextFormField(
                      controller: _regNumber,
                      textCapitalization: TextCapitalization.characters,
                      style: Cap.body(size: 15.5, weight: FontWeight.w800).copyWith(letterSpacing: 1.2),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s]')),
                        UpperCaseTextFormatter(),
                      ],
                      decoration: regInput(hint: 'e.g. GJ 03 AB 1234', icon: Icons.pin_outlined, iconColor: RegPalette.orange),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
                    ),
                  ),
                ],
              ),
            ),
            // Live number-plate preview of what is typed above (display only).
            RegEntrance(
              index: RegStepScaffold.firstChildIndex + 2,
              child: _PlatePreview(controller: _regNumber),
            ),
          ]),
        ),
      ],
    );
  }

  /// The chosen type with its real photo; tapping goes back to change it.
  Widget _vehicleCard(String typeName) {
    final radius = BorderRadius.circular(20);
    return RegPressScale(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Cap.accent.withValues(alpha: 0.12), Cap.accent.withValues(alpha: 0.03)],
            ),
            border: Border.all(color: Cap.accent.withValues(alpha: 0.25)),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: _changeType,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 96,
                  height: 66,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Cap.surface, borderRadius: BorderRadius.circular(14)),
                  child: VehicleTypeImage(vt: _vehicle, width: 88, height: 58),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Vehicle type', style: Cap.caption(size: 12)),
                    const SizedBox(height: 2),
                    Text(typeName, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Cap.body(size: 16, weight: FontWeight.w800).copyWith(height: 1.2)),
                    // The tier's rules, so the year and model below can match them.
                    if (vehicleRequirementsText(_vehicle).isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Needs: ${vehicleRequirementsText(_vehicle)}',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Cap.body(size: 12, weight: FontWeight.w700, color: RegPalette.orange)),
                    ],
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Cap.surface, borderRadius: BorderRadius.circular(20)),
                  child: Text('Change', style: Cap.body(size: 12.5, weight: FontWeight.w800, color: Cap.accent)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The server refused this vehicle for [typeName]: each reason on its own
/// line, and a button back to the vehicle types to pick another one.
class _NotEligibleCard extends StatelessWidget {
  final String typeName;
  final List<String> problems;
  final VoidCallback onChangeType;
  const _NotEligibleCard({required this.typeName, required this.problems, required this.onChangeType});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('vehicle_not_eligible'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  typeName.isEmpty ? 'Your vehicle does not qualify' : 'Your vehicle does not qualify for $typeName',
                  style: Cap.body(size: 14.5, weight: FontWeight.w800, color: AppColors.red)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final p in problems)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4, right: 8),
                  child: Container(
                      width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle)),
                ),
                Expanded(child: Text(p, style: Cap.body(size: 13.5, weight: FontWeight.w600).copyWith(height: 1.3))),
              ]),
            ),
          Text('Fix the details above, or pick a type your vehicle qualifies for.', style: Cap.caption(size: 12.5)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('vehicle_pick_another_type'),
              onPressed: onChangeType,
              style: TextButton.styleFrom(foregroundColor: Cap.accent, padding: const EdgeInsets.symmetric(horizontal: 4)),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text('Choose another type', style: Cap.body(size: 13.5, weight: FontWeight.w800, color: Cap.accent)),
            ),
          ),
        ]),
      );
}

/// A small Indian number plate showing the registration number as typed.
class _PlatePreview extends StatelessWidget {
  final TextEditingController controller;
  const _PlatePreview({required this.controller});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) {
          final text = v.text.trim();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RegPalette.field,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Plate preview', style: Cap.body(size: 13, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Check it matches your vehicle.', style: Cap.caption(size: 12)),
                ]),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  height: 40,
                  constraints: const BoxConstraints(minWidth: 96),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFF111111), width: 2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1D4ED8),
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                      ),
                      alignment: Alignment.center,
                      child: const RotatedBox(
                        quarterTurns: 3,
                        child: Text('IND', textScaler: TextScaler.noScaling,
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            text.isEmpty ? 'GJ 03 AB 1234' : text,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: text.isEmpty ? const Color(0xFFB0B6C3) : const Color(0xFF111111),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
