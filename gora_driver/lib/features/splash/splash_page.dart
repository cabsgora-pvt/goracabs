import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/bloc/auth_bloc.dart';
import '../onboarding/onboarding_page.dart';
import '../home/pages/home_page.dart';
import '../registration/kyc_pending_page.dart';
import '../registration/rejection_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is UnauthenticatedState) {
          Navigator.pushReplacementNamed(context, OnboardingPage.route);
        } else if (state is AuthenticatedState) {
          Navigator.pushReplacementNamed(context, HomePage.route);
        } else if (state is RegistrationSubmittedState) {
          Navigator.pushReplacementNamed(context, KycPendingPage.route);
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
          const Positioned(
            left: 0, right: 0, bottom: 56,
            child: Center(
              child: SizedBox(
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
