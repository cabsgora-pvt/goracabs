import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/user_provider.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

/// How long the rider waits before asking for another OTP. The screen opens
/// right after one was sent, so the wait starts then.
const kOtpResendCooldown = Duration(seconds: 30);

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // One field for all six digits: a paste or the keyboard's SMS-code
  // suggestion (AutofillHints.oneTimeCode) fills it in one go - six separate
  // one-character boxes took neither.
  final TextEditingController _otpCtrl = TextEditingController();
  final FocusNode _otpFocus = FocusNode();
  bool _loading = false;
  // The code last sent for checking: six digits auto-verify once, and a
  // refused code is not sent again until the rider changes it.
  String? _submitted;
  Timer? _cooldownTimer;
  int _resendIn = kOtpResendCooldown.inSeconds;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _resendIn = kOtpResendCooldown.inSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  String get _otp => _otpCtrl.text.trim();

  void _onOtpChanged(String v) {
    setState(() {}); // the boxes show the digits
    if (v.length == 6 && v != _submitted && !_loading) _verifyOtp();
  }

  Future<void> _verifyOtp() async {
    if (_loading) return; // a tap while the auto-verify is in flight
    if (_otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP')),
      );
      return;
    }
    final code = _otp;
    _submitted = code;
    setState(() => _loading = true);
    try {
      final res = await ApiService.verifyOtp(widget.phone, code);
      if (!mounted) return;

      if (res['token'] != null) {
        await ApiService.saveToken(res['token']);
        final isNewUser = res['isNewUser'] == true;
        if (!mounted) return;
        if (!isNewUser && res['user'] != null) {
          context.read<UserProvider>().setUser(res['user'] as Map<String, dynamic>);
        }
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => isNewUser ? SignupScreen(phone: widget.phone) : const HomeScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['error'] ?? res['message'] ?? 'Invalid OTP').toString())),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot connect to server')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendIn > 0 || _resending) return;
    setState(() => _resending = true);
    Map<String, dynamic> res;
    try {
      res = await ApiService.sendOtp(widget.phone);
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your connection.'};
    }
    if (!mounted) return;
    // A refusal — the daily limit (429) among them — is shown in the
    // server's words; it used to say "OTP resent" regardless.
    final ok = res['success'] == true;
    setState(() {
      _resending = false;
      if (ok) {
        _startCooldown();
        _otpCtrl.clear();
        _submitted = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'OTP resent' : (res['error'] ?? res['message'] ?? 'Could not resend the OTP').toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
              child: Image.asset('assets/images/123456123.png', fit: BoxFit.cover),
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
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Enter OTP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            'Sent to +91 ${widget.phone}',
                            style: TextStyle(fontSize: 14, color: AppTheme.textGrey),
                          ),
                          const SizedBox(height: 32),
                          _buildOtpField(),
                          const SizedBox(height: 24),
                          Center(
                            child: TextButton(
                              key: const ValueKey('otp-resend'),
                              onPressed: (_resendIn > 0 || _resending) ? null : _resendOtp,
                              child: Text(
                                  _resendIn > 0
                                      ? 'Resend code in 0:${_resendIn.toString().padLeft(2, '0')}'
                                      : "Didn't receive code? Resend",
                                  style: TextStyle(
                                      color: _resendIn > 0 ? AppTheme.textGrey : AppTheme.primaryBlue,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _verifyOtp,
                              child: _loading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Verify & Continue'),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Six boxes drawn under ONE text field, so paste and SMS-code autofill
  /// work and the digits still read as boxes.
  Widget _buildOtpField() {
    final digits = _otp;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(6, (i) {
          final focused = _otpFocus.hasFocus && (i == digits.length || (i == 5 && digits.length == 6));
          return Container(
            width: 46, height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? AppTheme.primaryBlue : (dark ? Colors.white24 : Colors.grey[300]!),
                width: focused ? 2 : 1,
              ),
            ),
            child: Text(i < digits.length ? digits[i] : '',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          );
        }),
      ),
      Positioned.fill(
        child: Opacity(
          opacity: 0.01, // invisible, but still the field that is tapped and filled
          child: TextField(
            key: const ValueKey('otp-field'),
            controller: _otpCtrl,
            focusNode: _otpFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            showCursor: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            onTap: () => setState(() {}),
            onChanged: _onOtpChanged,
          ),
        ),
      ),
    ]);
  }
}
