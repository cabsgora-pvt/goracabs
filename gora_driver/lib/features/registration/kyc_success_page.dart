import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/driver_api_service.dart';
import '../home/pages/home_page.dart';
import 'rejection_page.dart';
import 'widgets/status_views.dart';

class KycSuccessPage extends StatefulWidget {
  static const route = '/registration/kyc-success';
  const KycSuccessPage({super.key});

  @override
  State<KycSuccessPage> createState() => _KycSuccessPageState();
}

class _KycSuccessPageState extends State<KycSuccessPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Check immediately, then every 5s
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
  Widget build(BuildContext context) => const UnderReviewView(
        title: 'Application submitted',
        subtitle: 'Thanks! Your application is now under review. This screen will update automatically once you are approved.',
        justSubmitted: true,
      );
}
