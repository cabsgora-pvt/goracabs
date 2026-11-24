import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/bloc/auth_bloc.dart';
import '../onboarding/onboarding_page.dart';
import '../home/pages/home_page.dart';
import '../registration/kyc_pending_page.dart';
import '../registration/rejection_page.dart';
import '../registration/resume_registration.dart';

class SplashPage extends StatefulWidget {
  static const route = '/splash';
  const SplashPage({super.key});
  @override State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.7, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.read<AuthBloc>().add(CheckAuthEvent());
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  // Set when the session could not be loaded; the spinner gives way to a retry.
  bool _offline = false;

  void _retry() {
    setState(() => _offline = false);
    context.read<AuthBloc>().add(CheckAuthEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthOfflineState) {
          setState(() => _offline = true);
        } else if (state is UnauthenticatedState) {
          Navigator.pushReplacementNamed(context, OnboardingPage.route);
        } else if (state is AuthenticatedState) {
          Navigator.pushReplacementNamed(context, HomePage.route);
        } else if (state is RegistrationSubmittedState) {
          Navigator.pushReplacementNamed(context, KycPendingPage.route);
        } else if (state is RegistrationResumeState) {
          openRegistrationStep(Navigator.of(context), state.step,
              phone: (state.driver['phone'] ?? '').toString(), driver: state.driver);
        } else if (state is RejectionState) {
          Navigator.pushReplacementNamed(
            context,
            RejectionPage.route,
            arguments: {'reason': state.reason, 'driver': state.driver},
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF010920), // matches the splash artwork + native splash
        body: Stack(fit: StackFit.expand, children: [
          FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Image.asset('assets/images/splashscreen.png', fit: BoxFit.contain),
            ),
          ),
          Positioned(
            left: 24, right: 24, bottom: 56,
            child: Center(
              child: _offline
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                        "Can't reach Gora right now. Check your internet connection.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _retry,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF010920),
                          minimumSize: const Size(160, 46),
                        ),
                        child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ])
                  : const SizedBox(
                      width: 26, height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
