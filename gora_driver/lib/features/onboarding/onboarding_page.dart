import 'package:flutter/material.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import '../auth/pages/login_page.dart';

class OnboardingPage extends StatefulWidget {
  static const route = '/onboarding';
  const OnboardingPage({super.key});
  @override State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _page = 0;

  // Illustrations are the app's own bundled artwork; copy only describes
  // features the app actually has.
  static const _slides = [
    _Slide(
      image: 'assets/images/login_bg.png',
      alignment: Alignment(0, 0.55),
      title: 'Drive with Gora',
      desc: 'Go online, get trip requests near you and accept them in a single tap.',
    ),
    _Slide(
      image: 'assets/images/services/delivery.png',
      alignment: Alignment.center,
      title: 'Rides, rentals & parcels',
      desc: 'Opt in to outstation, rental, hire-a-driver and parcel jobs whenever you want more work.',
    ),
    _Slide(
      image: 'assets/images/otp_bg.png',
      alignment: Alignment(0, 0.3),
      title: 'Track every rupee',
      desc: 'See today, weekly and monthly earnings, and withdraw from your wallet to your bank.',
    ),
  ];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _goLogin() => Navigator.pushReplacementNamed(context, LoginPage.route);

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: Cap.surface,
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _SlideView(slide: _slides[i], onSkip: last ? null : _goLogin),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_slides.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _page == i ? 22 : 7, height: 7,
                decoration: BoxDecoration(
                  color: _page == i ? Cap.ink : Cap.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ))),
              const SizedBox(height: 18),
              CapButton(
                label: last ? 'Get started' : 'Next',
                icon: last ? null : Icons.arrow_forward_rounded,
                onPressed: () {
                  if (!last) {
                    _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  } else {
                    _goLogin();
                  }
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Slide {
  final String image, title, desc;
  final Alignment alignment;
  const _Slide({required this.image, required this.title, required this.desc, required this.alignment});
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final VoidCallback? onSkip;
  const _SlideView({required this.slide, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // The artwork takes what the copy leaves; on a short phone it shrinks
      // rather than pushing the title off screen.
      final imageH = (box.maxHeight - 150).clamp(120.0, box.maxHeight * 0.68);
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: imageH,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                child: Image.asset(slide.image, fit: BoxFit.cover, alignment: slide.alignment,
                    errorBuilder: (_, __, ___) => Container(color: Cap.tile)),
              ),
              if (onSkip != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 16,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onSkip,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Text('Skip', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            child: CapHeading(slide.title, subtitle: slide.desc, size: 26),
          ),
        ]),
      );
    });
  }
}
