import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../home/pages/home_page.dart';
import '../../registration/kyc_pending_page.dart';
import '../../registration/bank_details_page.dart';
import '../../registration/rejection_page.dart';
import '../../registration/personal_details_page.dart';
import '../../registration/resume_registration.dart';
import '../bloc/auth_bloc.dart';

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
    // Taken before any await, for the resume navigation below.
    final nav = Navigator.of(context);
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
      } else if (result['registrationStep'] == 'bank') {
        // Documents already on file — only the bank step is left.
        Navigator.pushNamedAndRemoveUntil(context, BankDetailsPage.route, (_) => false);
      } else {
        // Resume an unfinished registration at the server's step (after the
        // selfie → vehicle, after the vehicle → documents…). A new account,
        // or a step not listed, starts at personal details as before.
        final driver = result['driver'] is Map
            ? Map<String, dynamic>.from(result['driver'] as Map)
            : <String, dynamic>{};
        driver['registrationStep'] ??= result['registrationStep'];
        final step = resumeStepFor(driver) ?? ResumeStep.personal;
        if (step == ResumeStep.personal) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            PersonalDetailsPage.route,
            (_) => false,
            arguments: {'phone': phone},
          );
        } else {
          openRegistrationStep(nav, step, phone: phone, driver: driver);
        }
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
      backgroundColor: Cap.surface,
      appBar: AppBar(
        backgroundColor: Cap.surface,
        foregroundColor: Cap.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context))
            : null,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CapHeading('Enter the 6-digit code', size: 26),
            const SizedBox(height: 8),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Sent to +91 $phone  ', style: Cap.caption(size: 14.5)),
              if (Navigator.canPop(context))
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('Change number',
                      style: Cap.body(size: 14, weight: FontWeight.w800, color: Cap.accent)),
                ),
            ]),
            const SizedBox(height: 28),
            Row(children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _buildOtpBox(i)),
              ],
            ]),
            const SizedBox(height: 22),
            _timer > 0
                ? Row(children: [
                    Icon(Icons.schedule_rounded, size: 16, color: Cap.muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text('Resend code in 0:${_timer.toString().padLeft(2, '0')}', style: Cap.caption(size: 13.5))),
                  ])
                : GestureDetector(
                    onTap: () { DriverApiService.sendOtp(phone); setState(() => _timer = 30); _startTimer(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.refresh_rounded, size: 17, color: Cap.ink),
                        const SizedBox(width: 6),
                        Text('Resend code', style: Cap.body(size: 13.5, weight: FontWeight.w800)),
                      ]),
                    ),
                  ),
          ]),
        ),
      ),
      bottomNavigationBar: CapBottomBar(
        child: CapButton(
          label: 'Verify & continue',
          loading: _loading,
          tone: _otp.length == 6 ? CapButtonTone.primary : CapButtonTone.secondary,
          onPressed: _verify,
        ),
      ),
    );
  }

  Widget _buildOtpBox(int i) {
    return SizedBox(
      height: 56,
      child: TextFormField(
        controller: _controllers[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
        style: Cap.body(size: 22, weight: FontWeight.w800),
        decoration: Cap.input().copyWith(
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          isDense: true,
        ),
        onChanged: (v) {
          setState(() {});
          if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
          if (_otp.length == 6) _verify();
        },
      ),
    );
  }
}
