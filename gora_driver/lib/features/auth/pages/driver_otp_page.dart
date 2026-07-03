import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../home/pages/home_page.dart';
import '../../registration/kyc_pending_page.dart';
import '../../registration/rejection_page.dart';
import '../../registration/personal_details_page.dart';

class DriverOtpPage extends StatefulWidget {
  static const route = '/driver-otp';
  const DriverOtpPage({super.key});
  @override
  State<DriverOtpPage> createState() => _DriverOtpPageState();
}

class _DriverOtpPageState extends State<DriverOtpPage> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  int _timer = 30;
  Timer? _t;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timer > 0) {
        setState(() => _timer--);
      } else {
        _t?.cancel();
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final n in _nodes) n.dispose();
    _t?.cancel();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    final phone = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    setState(() => _loading = true);
    try {
      final result = await DriverApiService.verifyOtp(phone, _otp);
      if (!mounted) return;

      if (result['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['error'].toString()),
          backgroundColor: AppColors.red,
        ));
        for (final c in _controllers) c.clear();
        _nodes[0].requestFocus();
        setState(() => _loading = false);
        return;
      }

      // Save token
      final token = result['token'] as String?;
      if (token != null) await DriverApiService.saveToken(token);

      // Load profile into provider
      if (result['driver'] != null) {
        context.read<DriverProvider>().setData(result['driver'] as Map<String, dynamic>);
      }

      if (result['isApproved'] == true || result['isApproved'] == 'true') {
        Navigator.pushNamedAndRemoveUntil(context, HomePage.route, (_) => false);
      } else if (result['isRejected'] == true) {
        final reason = result['rejectionReason'] as String? ?? 'Your application was rejected.';
        Navigator.pushNamedAndRemoveUntil(
          context,
          RejectionPage.route,
          (_) => false,
          arguments: {'reason': reason, 'driver': result['driver']},
        );
      } else if (result['registrationStep'] == 'submitted') {
        Navigator.pushNamedAndRemoveUntil(context, KycPendingPage.route, (_) => false);
      } else {
        Navigator.pushNamedAndRemoveUntil(
          context,
          PersonalDetailsPage.route,
          (_) => false,
          arguments: {'phone': phone},
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.red,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    return Scaffold(
      body: Stack(children: [
        // Full-screen Gora background artwork
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(26), Colors.black.withAlpha(102),
                Colors.black.withAlpha(102), Colors.black.withAlpha(26),
              ],
              stops: const [0.0, 0.3, 0.7, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Image.asset('assets/images/otp_bg.png', fit: BoxFit.cover),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Enter OTP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        const SizedBox(height: 8),
                        Text('Sent to +91 $phone', style: const TextStyle(fontSize: 14, color: AppColors.textGrey)),
                        const SizedBox(height: 28),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, (i) => _buildOtpBox(i))),
                        const SizedBox(height: 20),
                        Center(
                          child: _timer > 0
                              ? Text('Resend OTP in $_timer s', style: const TextStyle(color: AppColors.textGrey))
                              : TextButton(
                                  onPressed: () { DriverApiService.sendOtp(phone); setState(() => _timer = 30); _startTimer(); },
                                  child: const Text('Resend OTP', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                                ),
                        ),
                        const SizedBox(height: 8),
                        PrimaryButton(label: 'Verify & Continue', loading: _loading, onTap: _verify),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _buildOtpBox(int i) {
    return SizedBox(
      width: 46, height: 56,
      child: TextFormField(
        controller: _controllers[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
        decoration: InputDecoration(
          counterText: '', isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider, width: 2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          filled: true, fillColor: AppColors.cardBg,
        ),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
          if (_otp.length == 6) _verify();
        },
      ),
    );
  }
}
