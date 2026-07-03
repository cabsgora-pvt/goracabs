import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
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

  static const List<String> _welcomeWords = [
    'Welcome', 'Captain', 'स्वागत है', 'ਸੁਆਗਤ ਹੈ', 'સ્વાગત છે',
    'স্বাগতম', 'ಸ್ವಾಗತ', 'സ്വാഗതം', 'வரவேற்கிறோம்', 'స్వాగతం',
  ];

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
    return Scaffold(
      body: Stack(
        children: [
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
              child: Image.asset('assets/images/login_bg.png', fit: BoxFit.cover),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Spacer(flex: 1),
                      Center(
                        child: AnimatedTextKit(
                          animatedTexts: _welcomeWords.map((word) => TypewriterAnimatedText(
                            word,
                            textStyle: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white),
                            speed: const Duration(milliseconds: 120),
                            cursor: '|',
                          )).toList(),
                          repeatForever: true,
                          pause: const Duration(milliseconds: 1600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text('GORA CAPTAIN', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 2)),
                      ),
                      const Spacer(flex: 1),
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Driver Login', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textDark)),
                          const SizedBox(height: 4),
                          const Text('Enter your mobile number to continue', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                          const SizedBox(height: 18),
                          const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                            decoration: InputDecoration(
                              hintText: 'Enter your phone number',
                              counterText: '',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('+91', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text("We'll send a 6-digit OTP to verify your number", style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                          const SizedBox(height: 20),
                          PrimaryButton(label: 'Send OTP', loading: _loading, onTap: _sendOtp),
                          const SizedBox(height: 16),
                          Center(
                            child: Text.rich(TextSpan(
                              text: 'By continuing, you agree to our ',
                              style: const TextStyle(color: AppColors.textGrey, fontSize: 11.5),
                              children: const [
                                TextSpan(text: 'Terms & Privacy Policy', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ],
                            )),
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
}
