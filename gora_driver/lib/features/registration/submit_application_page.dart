import 'package:flutter/material.dart';
import '../../services/driver_api_service.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'document_upload_page.dart';
import 'kyc_success_page.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_ui.dart';
import 'widgets/status_views.dart';

/// Opened for a driver resuming at server registrationStep 'bank': documents
/// saved by an older app build that still asked for bank details. Bank details
/// are no longer part of registration, so instead of the old bank form this
/// asks the server to submit the application (POST /register/submit):
///   * success      → "Application submitted" (under review), stack cleared;
///   * 4xx {error}  → the documents page, with the server's message on top
///                    (e.g. a required document is now missing);
///   * anything else (offline, 5xx) → stays here with a retry.
class SubmitApplicationPage extends StatefulWidget {
  static const route = '/registration/submit';
  const SubmitApplicationPage({super.key});

  @override
  State<SubmitApplicationPage> createState() => _SubmitApplicationPageState();
}

class _SubmitApplicationPageState extends State<SubmitApplicationPage> {
  bool _started = false;
  bool _busy = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _submit();
  }

  /// The driver record handed over by the resume routing, if any.
  Map? get _driver {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is Map && args['driver'] is Map ? args['driver'] as Map : null;
  }

  Future<void> _submit() async {
    final nav = Navigator.of(context);
    final vehicleType = _driver?['selectedVehicleTypeName'];
    setState(() { _busy = true; _error = null; });
    try {
      final res = await DriverApiService.submitRegistration();
      if (!mounted) return;
      final code = res['statusCode'] is int ? res['statusCode'] as int : 0;
      final error = res['error']?.toString();
      if (error == null && code >= 200 && code < 300) {
        nav.pushNamedAndRemoveUntil(KycSuccessPage.route, (_) => false);
        return;
      }
      if (error != null && code >= 400 && code < 500 && code != 401) {
        // The server will not submit what it has: let the driver fix the
        // documents, with its reason shown.
        nav.pushNamedAndRemoveUntil(DocumentUploadPage.route, (_) => false,
            arguments: {'error': error, 'vehicleType': vehicleType});
        return;
      }
      setState(() { _busy = false; _error = error ?? 'Could not submit your application. Please try again.'; });
    } catch (_) {
      if (mounted) {
        setState(() { _busy = false; _error = "Couldn't reach Gora. Check your internet connection and try again."; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RegHeroPage(
      hero: RegStatusHero(
        badge: AnimatedSwitcher(
          duration: regDuration(context, const Duration(milliseconds: 300)),
          child: Container(
            key: ValueKey(_busy),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.14)),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Cap.surface),
              child: _busy
                  ? const CapIllustration(icon: Icons.upload_file_rounded, size: 96)
                  : const CapIllustration(icon: Icons.cloud_off_rounded, color: Cap.orange, size: 96),
            ),
          ),
        ),
        title: _busy ? 'Submitting your application' : 'Not submitted yet',
        subtitle: _busy ? 'Your documents are already saved. We are sending your application for review.' : null,
      ),
      sheetChildren: [
        RegEntrance(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 26, height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: Cap.accent))),
              )
            else ...[
              CapBanner(
                key: const ValueKey('submit_error'),
                icon: Icons.error_outline_rounded,
                tone: CapTone.danger,
                text: _error ?? '',
              ),
              const SizedBox(height: 18),
              RegCta(label: 'Try again', trailing: Icons.refresh_rounded, onPressed: _submit),
            ],
          ]),
        ),
      ],
    );
  }
}
