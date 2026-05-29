import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/pages/login_page.dart';

class OnboardingPage extends StatefulWidget {
  static const route = '/onboarding';
  const OnboardingPage({super.key});
  @override State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _page = 0;

  final _slides = [
    _Slide(icon: Icons.local_taxi_rounded, title: 'Accept Rides Instantly', desc: 'Get ride requests near you and accept with a single tap. More rides, more earnings.', color: AppColors.primary),
    _Slide(icon: Icons.monetization_on_rounded, title: 'Earn More Every Day', desc: 'Track your daily and weekly earnings. Unlock bonuses and incentives for top performance.', color: AppColors.primaryDark),
    _Slide(icon: Icons.shield_rounded, title: 'Drive Safely & Securely', desc: 'SOS support, in-app chat, and 24/7 customer service. Your safety is our priority.', color: AppColors.accent),
  ];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: _slides.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _SlideWidget(slide: _slides[i]),
        ),
        // Skip
        Positioned(
          top: 52, right: 20,
          child: TextButton(
            onPressed: () => Navigator.pushReplacementNamed(context, LoginPage.route),
            child: const Text('Skip', style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.w600)),
          ),
        ),
        // Bottom
        Positioned(
          bottom: 40, left: 24, right: 24,
          child: Column(children: [
            // Dots
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_slides.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _page == i ? 24 : 8, height: 8,
              decoration: BoxDecoration(
                color: _page == i ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ))),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _page == _slides.length - 1 ? 'Get Started' : 'Next',
              onTap: () {
                if (_page < _slides.length - 1) {
                  _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                } else {
                  Navigator.pushReplacementNamed(context, LoginPage.route);
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Slide { final IconData icon; final String title, desc; final Color color;
  const _Slide({required this.icon, required this.title, required this.desc, required this.color});
}

class _SlideWidget extends StatelessWidget {
  final _Slide slide;
  const _SlideWidget({required this.slide});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 160, height: 160,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [slide.color, slide.color.withOpacity(0.6)]),
            shape: BoxShape.circle,
          ),
          child: Icon(slide.icon, size: 80, color: Colors.white),
        ),
        const SizedBox(height: 48),
        Text(slide.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        const SizedBox(height: 16),
        Text(slide.desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textGrey, height: 1.6)),
        const SizedBox(height: 120),
      ]),
    );
  }
}
