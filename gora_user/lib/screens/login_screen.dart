import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;

  static const List<String> _welcomeWords = [
    'Welcome', 'स्वागत है', 'ਸੁਆਗਤ ਹੈ', 'સ્વાગત છે',
    'স্বাগতম', 'ಸ್ವಾಗತ', 'സ്വാഗതം', 'வரவேற்கிறோம்', 'స్వాగతం', 'स्वागतम्',
  ];

  @override
  void dispose() { _phoneController.dispose(); super.dispose(); }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit phone number')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.sendOtp(phone);
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => OtpScreen(phone: phone),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Failed to send OTP')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot connect to server. Is the admin running?')),
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
              child: Image.asset('assets/images/123456789.png', fit: BoxFit.cover),
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
                            textStyle: GoogleFonts.dancingScript(
                              fontSize: 48, fontWeight: FontWeight.w700, color: Colors.black,
                            ),
                            speed: const Duration(milliseconds: 120),
                            cursor: '|',
                          )).toList(),
                          repeatForever: true,
                          pause: const Duration(milliseconds: 1800),
                        ),
                      ),
                      const Spacer(flex: 1),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            decoration: InputDecoration(
                              hintText: 'Enter your phone number',
                              counterText: '',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('+91', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Use OTP: 1234', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _sendOtp,
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              child: _loading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Send OTP'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR', style: TextStyle(color: Colors.grey[500])),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ]),
                          const SizedBox(height: 24),
                          Row(children: [
                            Expanded(child: _buildSocialButton(icon: FontAwesomeIcons.google, color: Colors.white, textColor: Colors.black87, borderColor: Colors.grey[300])),
                            const SizedBox(width: 16),
                            Expanded(child: _buildSocialButton(icon: FontAwesomeIcons.apple, color: Colors.black, textColor: Colors.white)),
                          ]),
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

  Widget _buildSocialButton({required IconData icon, required Color color, required Color textColor, Color? borderColor}) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: borderColor != null ? BorderSide(color: borderColor) : BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: FaIcon(icon, size: 24, color: textColor),
    );
  }
}
