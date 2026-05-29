import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/auth_bloc.dart';
import 'otp_page.dart';

class LoginPage extends StatefulWidget {
  static const route = '/login';
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() { _phone.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is OtpSentState) Navigator.pushNamed(context, OtpPage.route, arguments: state.phone);
        if (state is AuthErrorState) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppColors.red));
      },
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            // Header
            Container(
              height: 280, width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 40),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.local_taxi_rounded, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text('GORA DRIVER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                const SizedBox(height: 4),
                Text('Welcome back, Driver!', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 8),
                  const Text('Login to your account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  const Text('Enter your mobile number to continue', style: TextStyle(color: AppColors.textGrey)),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                    decoration: const InputDecoration(
                      labelText: 'Mobile Number',
                      prefixText: '+91 ',
                      prefixIcon: Icon(Icons.phone_rounded, color: AppColors.primary),
                    ),
                    validator: (v) => (v == null || v.length < 10) ? 'Enter valid 10-digit number' : null,
                  ),
                  const SizedBox(height: 32),
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) => PrimaryButton(
                      label: 'Send OTP',
                      loading: state is AuthLoading,
                      onTap: () {
                        if (_form.currentState!.validate()) {
                          context.read<AuthBloc>().add(LoginEvent(_phone.text));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text.rich(TextSpan(
                      text: 'By continuing, you agree to our ',
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                      children: [
                        TextSpan(text: 'Terms & Privacy Policy', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    )),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
