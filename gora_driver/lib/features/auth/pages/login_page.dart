import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/driver_api_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../../account/pages/legal_pages.dart';
import 'driver_otp_page.dart';

class LoginPage extends StatefulWidget {
  static const route = '/login';
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _phone.dispose(); super.dispose(); }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit phone number')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await DriverApiService.sendOtp(phone);
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pushNamed(context, DriverOtpPage.route, arguments: phone);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error']?.toString() ?? 'Failed to send OTP'), backgroundColor: AppColors.red),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot connect to server'), backgroundColor: AppColors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _phone.text.trim().length == 10;
    return Scaffold(
      backgroundColor: Cap.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/images/logo.png', width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44)),
              ),
              const SizedBox(width: 10),
              Text('Gora Captain', style: Cap.body(size: 15, weight: FontWeight.w800)),
            ]),
            const SizedBox(height: 32),
            const CapHeading('Enter your mobile number',
                subtitle: "We'll send a 6-digit code to verify it", size: 26),
            const SizedBox(height: 28),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Cap.tile,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Cap.divider),
                ),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🇮🇳', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('+91', style: Cap.body(size: 16, weight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phone,
                  autofocus: false,
                  keyboardType: TextInputType.phone,
                  style: Cap.body(size: 17, weight: FontWeight.w700).copyWith(letterSpacing: 1.2),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  onSubmitted: (_) => _sendOtp(),
                  decoration: Cap.input(hint: 'Mobile number'),
                ),
              ),
            ]),
          ]),
        ),
      ),
      bottomNavigationBar: CapBottomBar(
        top: Text.rich(
          TextSpan(
            text: 'By continuing, you agree to our ',
            style: Cap.caption(size: 12),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, TermsPage.route),
                  child: Text('Terms', style: Cap.caption(size: 12, color: Cap.accent).copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              const TextSpan(text: ' & '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, PrivacyPolicyPage.route),
                  child: Text('Privacy Policy', style: Cap.caption(size: 12, color: Cap.accent).copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        child: CapButton(
          label: 'Continue',
          loading: _loading,
          tone: ready ? CapButtonTone.primary : CapButtonTone.secondary,
          onPressed: _sendOtp,
        ),
      ),
    );
  }
}
