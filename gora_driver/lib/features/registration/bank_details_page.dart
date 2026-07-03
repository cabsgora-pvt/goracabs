import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
import 'kyc_success_page.dart';

class BankDetailsPage extends StatefulWidget {
  static const route = '/registration/bank';
  const BankDetailsPage({super.key});
  @override
  State<BankDetailsPage> createState() => _BankDetailsPageState();
}

class _BankDetailsPageState extends State<BankDetailsPage> {
  final _form = GlobalKey<FormState>();
  final _holderName = TextEditingController();
  final _bankName = TextEditingController();
  final _branch = TextEditingController();
  final _accountNumber = TextEditingController();
  final _ifsc = TextEditingController();
  String _accountType = 'savings';
  bool _loading = false;

  @override
  void dispose() {
    _holderName.dispose();
    _bankName.dispose();
    _branch.dispose();
    _accountNumber.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await DriverApiService.saveBank({
        'accountHolderName': _holderName.text.trim(),
        'bankName': _bankName.text.trim(),
        'branch': _branch.text.trim(),
        'accountNumber': _accountNumber.text.trim(),
        'ifscCode': _ifsc.text.trim().toUpperCase(),
        'accountType': _accountType,
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        Navigator.pushNamedAndRemoveUntil(context, KycSuccessPage.route, (_) => false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    _stepIndicator(4),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _holderName,
                      decoration: const InputDecoration(
                        labelText: 'Account Holder Name *',
                        prefixIcon: Icon(Icons.person_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Account holder name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bankName,
                      decoration: const InputDecoration(
                        labelText: 'Bank Name *',
                        prefixIcon: Icon(Icons.account_balance_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _branch,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name',
                        prefixIcon: Icon(Icons.location_city_rounded, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _accountNumber,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Account Number *',
                        prefixIcon: Icon(Icons.credit_card_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().length < 9) ? 'Enter valid account number' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ifsc,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        UpperCaseFormatter(),
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'IFSC Code *',
                        hintText: 'e.g. SBIN0001234',
                        prefixIcon: Icon(Icons.code_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().length < 11) ? 'Enter valid 11-character IFSC code' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _accountType,
                      decoration: const InputDecoration(
                        labelText: 'Account Type *',
                        prefixIcon: Icon(Icons.category_rounded, color: AppColors.primary),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'savings', child: Text('Savings')),
                        DropdownMenuItem(value: 'current', child: Text('Current')),
                      ],
                      onChanged: (v) => setState(() => _accountType = v ?? 'savings'),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your bank details are encrypted and stored securely.',
                              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(label: 'Submit Application', loading: _loading, onTap: _submit),
                    const SizedBox(height: 16),
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
                  'Bank Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Step 4 of 4 — For earnings withdrawal',
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
      children: List.generate(4, (i) => Expanded(
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

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
