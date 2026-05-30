import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/driver_api_service.dart';
import '../home/pages/home_page.dart';
import 'rejection_page.dart';

class KycPendingPage extends StatefulWidget {
  static const route = '/registration/kyc-pending';
  const KycPendingPage({super.key});

  @override
  State<KycPendingPage> createState() => _KycPendingPageState();
}

class _KycPendingPageState extends State<KycPendingPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final res = await DriverApiService.getProfile();
      final driver = res['driver'] as Map<String, dynamic>?;
      final status = driver?['status']?.toString();
      if (!mounted) return;
      if (status == 'approved') {
        _poll?.cancel();
        Navigator.pushNamedAndRemoveUntil(context, HomePage.route, (_) => false);
      } else if (status == 'rejected') {
        _poll?.cancel();
        Navigator.pushNamedAndRemoveUntil(context, RejectionPage.route, (_) => false);
      }
    } catch (_) {
      // silent retry next tick
    }
  }

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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded, size: 56, color: Colors.white),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Application\nUnder Review',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your KYC application has been submitted and is currently being reviewed by our team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.85), height: 1.5),
                ),
                const SizedBox(height: 24),
                // Live indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.8)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for admin approval...',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.access_time_rounded, 'Estimated Time', '24-48 hours'),
                      const SizedBox(height: 12),
                      _infoRow(Icons.notifications_rounded, 'We will notify you', 'Via SMS'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support: support@goracabs.com')),
                      );
                    },
                    icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
                    label: const Text('Contact Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
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
