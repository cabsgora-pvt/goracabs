import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import 'personal_details_page.dart';

class RejectionPage extends StatelessWidget {
  static const route = '/registration/rejected';
  const RejectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final reason = args?['reason'] as String? ?? 'Your application was not approved.';
    final driver = args?['driver'] as Map?;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
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
                  child: const Icon(Icons.cancel_rounded, size: 60, color: Colors.white),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Application\nRejected',
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
                  'We are sorry, your application was not approved at this time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.85), height: 1.5),
                ),
                const SizedBox(height: 24),
                // Reason card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.white70, size: 16),
                          SizedBox(width: 8),
                          Text('Rejection Reason', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(reason, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        PersonalDetailsPage.route,
                        (_) => false,
                        arguments: {'driver': driver},
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Resubmit Application', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support: support@goracabs.com')),
                      );
                    },
                    icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
                    label: const Text('Contact Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
}
