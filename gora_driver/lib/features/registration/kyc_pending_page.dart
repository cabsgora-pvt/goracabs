import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/driver_api_service.dart';
import '../home/pages/home_page.dart';
import 'rejection_page.dart';
import 'widgets/status_views.dart';

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
  Widget build(BuildContext context) => const UnderReviewView(
        title: 'Application under review',
        subtitle: 'Your KYC application has been submitted and is being reviewed by our team.',
        justSubmitted: false,
      );
}
