import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/auth_bloc.dart';
import '../../home/pages/home_page.dart';

class OtpPage extends StatefulWidget {
  static const route = '/otp';
  const OtpPage({super.key});
  @override State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _nodes = List.generate(4, (_) => FocusNode());
  int _timer = 30;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timer > 0) setState(() => _timer--);
      else _t?.cancel();
    });
  }

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var n in _nodes) n.dispose();
    _t?.cancel();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _verify() {
    if (_otp.length == 4) context.read<AuthBloc>().add(VerifyOtpEvent(_otp));
  }

  @override
  Widget build(BuildContext context) {
    final phone = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthenticatedState) Navigator.pushNamedAndRemoveUntil(context, HomePage.route, (_) => false);
        if (state is AuthErrorState) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppColors.red));
          for (var c in _controllers) c.clear();
          _nodes[0].requestFocus();
        }
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: AppColors.textDark, leading: BackButton()),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            const Text('Verify OTP', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Text('Enter the 4-digit OTP sent to +91 $phone', style: const TextStyle(color: AppColors.textGrey, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('(Use: 1234 for demo)', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 40),
            // OTP boxes
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(4, (i) =>
              SizedBox(
                width: 64, height: 64,
                child: TextFormField(
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary),
                  decoration: InputDecoration(
                    counterText: '',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    filled: true, fillColor: AppColors.cardBg,
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 3) _nodes[i + 1].requestFocus();
                    if (_otp.length == 4) _verify();
                  },
                ),
              ),
            )),
            const SizedBox(height: 32),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) => PrimaryButton(
                label: 'Verify & Continue',
                loading: state is AuthLoading,
                onTap: _verify,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: _timer > 0
                  ? Text('Resend OTP in $_timer seconds', style: const TextStyle(color: AppColors.textGrey))
                  : TextButton(
                      onPressed: () { setState(() => _timer = 30); _startTimer(); },
                      child: const Text('Resend OTP', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
