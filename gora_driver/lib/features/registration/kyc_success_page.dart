import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class KycSuccessPage extends StatelessWidget {
  static const route = '/registration/kyc-success';
  const KycSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated check icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 3),
                ),
                child: const Icon(Icons.check_rounded, size: 72, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text(
                'KYC Submitted\nSuccessfully!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Your application is under review.\nYou will be notified within 24 hours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.85),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    _infoRow(Icons.access_time_rounded, 'Review Time', '24-48 hours'),
                    const SizedBox(height: 12),
                    _infoRow(Icons.notifications_rounded, 'Notification', 'Via SMS & App'),
                    const SizedBox(height: 12),
                    _infoRow(Icons.support_agent_rounded, 'Support', 'Available 24/7'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
