import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_step_scaffold.dart';
import '../../services/driver_api_service.dart';
import 'document_upload_page.dart';
import 'vehicle_selection_page.dart' show VehicleTypeImage;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _vehicle = Map<String, dynamic>.from(args?['vehicle'] as Map? ?? {});
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await DriverApiService.saveVehicle({
        'selectedVehicleTypeId': _vehicle['_id'] ?? _vehicle['id'],
        'selectedVehicleTypeName': _vehicle['name'],
        'vehicleRegistrationNumber': _regNumber.text.trim().toUpperCase(),
        'vehicleModel': _vehicleModel.text.trim(),
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        Navigator.pushNamed(context, DocumentUploadPage.route);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
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
      bottom: CapButton(label: 'Continue', loading: _loading, onPressed: _submit),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (typeName.isNotEmpty) ...[
              CapTile(
                onTap: () => Navigator.maybePop(context),
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  VehicleTypeImage(vt: _vehicle, width: 72, height: 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Vehicle type', style: Cap.caption(size: 12)),
                      Text(typeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Cap.body(size: 15, weight: FontWeight.w800)),
                    ]),
                  ),
                  Text('Change', style: Cap.body(size: 13, weight: FontWeight.w800, color: Cap.accent)),
                ]),
              ),
              const SizedBox(height: 20),
            ],
            CapField(
              label: 'Vehicle name / model',
              required: true,
              child: TextFormField(
                controller: _vehicleModel,
                textCapitalization: TextCapitalization.words,
                decoration: Cap.input(hint: 'e.g. Maruti Swift Dzire'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle model is required' : null,
              ),
            ),
            CapField(
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
                decoration: Cap.input(hint: 'e.g. GJ 03 AB 1234'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
              ),
            ),
            Text('As printed on your number plate and RC book.', style: Cap.caption(size: 12.5)),
          ]),
        ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
