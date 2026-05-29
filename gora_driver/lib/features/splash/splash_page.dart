import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_colors.dart';
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
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white30, width: 2),
                    ),
                    child: const Icon(Icons.local_taxi_rounded, size: 56, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text('GORA DRIVER', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3)),
                  const SizedBox(height: 8),
                  Text('Drive. Earn. Succeed.', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8), letterSpacing: 1)),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(color: Colors.white.withOpacity(0.7), strokeWidth: 2.5),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
