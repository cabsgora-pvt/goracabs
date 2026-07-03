import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
import 'document_upload_page.dart';

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
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _stepIndicator(2),
                    const SizedBox(height: 20),
                    // Vehicle type (read only)
                    TextFormField(
                      initialValue: _vehicle['name'] as String? ?? '',
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Vehicle Type',
                        prefixIcon: Icon(Icons.directions_car_rounded, color: AppColors.textGrey),
                      ),
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _vehicleModel,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Name / Model *',
                        hintText: 'e.g. Maruti Swift Dzire',
                        prefixIcon: Icon(Icons.car_repair_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle model is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _regNumber,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s]')),
                        UpperCaseTextFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Registration Number *',
                        hintText: 'e.g. GJ01AB1234',
                        prefixIcon: Icon(Icons.pin_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
                    ),
                    const SizedBox(height: 32),
                    PrimaryButton(label: 'Continue', loading: _loading, onTap: _submit),
                  ],
                ),
              ),
            ),
          ),
        ],
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
                  'Vehicle Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Step 2 of 3 — Enter your vehicle info',
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
