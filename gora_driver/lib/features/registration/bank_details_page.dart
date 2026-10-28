import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_step_scaffold.dart';
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
    return RegStepScaffold(
      step: CapRegSteps.bank,
      stepLabel: 'Bank account',
      title: 'Add your bank account',
      subtitle: 'Your earnings are withdrawn to this account.',
      bottom: CapButton(label: 'Submit application', loading: _loading, onPressed: _submit),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CapField(
              label: 'Account holder name',
              required: true,
              child: TextFormField(
                controller: _holderName,
                textCapitalization: TextCapitalization.words,
                decoration: Cap.input(hint: 'Name as per bank records'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Account holder name is required' : null,
              ),
            ),
            CapField(
              label: 'Account number',
              required: true,
              child: TextFormField(
                controller: _accountNumber,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: Cap.body(size: 15.5, weight: FontWeight.w700).copyWith(letterSpacing: 1),
                decoration: Cap.input(hint: 'Enter account number'),
                validator: (v) => (v == null || v.trim().length < 9) ? 'Enter valid account number' : null,
              ),
            ),
            CapField(
              label: 'IFSC code',
              required: true,
              child: TextFormField(
                controller: _ifsc,
                textCapitalization: TextCapitalization.characters,
                style: Cap.body(size: 15.5, weight: FontWeight.w700).copyWith(letterSpacing: 1),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  UpperCaseFormatter(),
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: Cap.input(hint: 'e.g. SBIN0001234'),
                validator: (v) => (v == null || v.trim().length < 11) ? 'Enter valid 11-character IFSC code' : null,
              ),
            ),
            CapField(
              label: 'Bank name',
              required: true,
              child: TextFormField(
                controller: _bankName,
                textCapitalization: TextCapitalization.words,
                decoration: Cap.input(hint: 'e.g. State Bank of India'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank name is required' : null,
              ),
            ),
            CapField(
              label: 'Branch name',
              child: TextFormField(
                controller: _branch,
                textCapitalization: TextCapitalization.words,
                decoration: Cap.input(hint: 'Optional'),
              ),
            ),
            CapField(
              label: 'Account type',
              required: true,
              child: Row(children: [
                for (final t in const [('savings', 'Savings'), ('current', 'Current')]) ...[
                  if (t.$1 == 'current') const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _accountType = t.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _accountType == t.$1 ? Cap.accent.withValues(alpha: 0.06) : Cap.tile,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _accountType == t.$1 ? Cap.accent : Cap.divider,
                            width: _accountType == t.$1 ? 2 : 1,
                          ),
                        ),
                        child: Text(t.$2, style: Cap.body(size: 14.5, weight: FontWeight.w800,
                            color: _accountType == t.$1 ? Cap.accent : null)),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            const CapBanner(
              icon: Icons.lock_rounded,
              tone: CapTone.neutral,
              text: 'Your bank details are encrypted and stored securely.',
            ),
          ]),
        ),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
