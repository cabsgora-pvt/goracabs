import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import 'face_single_capture_page.dart';

/// Blocking screen shown when faceVerificationRequired is set — a mid-ride
/// check came back mismatched or unanswered. The driver cannot go online
/// again until this passes; a failed attempt here just lets them retry (the
/// lock itself was already set by the ride-ending event, so there is no
/// further escalation to apply on a second failure here).
/// What a face-reverify reply means. The server answers {matched, cleared,
/// adminHold?} — no score. Only `cleared` lets the driver back online: a
/// match does not clear a lock or hold an admin set.
({bool cleared, String message}) reverifyOutcome(Map<String, dynamic> r) {
  if (r['cleared'] == true) return (cleared: true, message: '');
  if (r['adminHold'] == true) {
    return (cleared: false, message: 'Your account is on hold. Please contact support.');
  }
  final status = r['_status'];
  if (status == 429 || r['code'] == 'RATE_LIMITED') {
    return (cleared: false, message: 'Too many attempts. Please try again later or contact support.');
  }
  if (r['code'] == 'PHOTO_REQUIRED') {
    return (cleared: false, message: 'The photo did not upload. Please try again.');
  }
  if (r['error'] != null) return (cleared: false, message: r['error'].toString());
  if (r['matched'] == true) {
    // Matched, but there was nothing the check could clear.
    return (cleared: false, message: 'Verified, but your account still needs a check by support. Please contact support.');
  }
  return (cleared: false,
      message: "That didn't match our records. Please try again, or contact support if this keeps happening.");
}

class FaceReverifyPage extends StatefulWidget {
  static const route = '/account/face-reverify';
  final String reason; // 'mismatch' | 'no_response'
  const FaceReverifyPage({super.key, required this.reason});

  @override
  State<FaceReverifyPage> createState() => _FaceReverifyPageState();
}

class _FaceReverifyPageState extends State<FaceReverifyPage> {
  bool _checking = false;
  String? _lastError;

  Future<void> _start() async {
    setState(() { _checking = true; _lastError = null; });
    final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(
      builder: (_) => FaceSingleCapturePage(
        title: 'Verify your identity',
        subtitle: 'Look straight at the camera to go back online',
        submit: (embedding, photoUrl) => DriverApiService.reverifyFace(embedding, photoUrl),
      ),
    ));
    if (!mounted) return;
    setState(() => _checking = false);
    if (result == null) return;
    final outcome = reverifyOutcome(result);
    if (outcome.cleared) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    setState(() => _lastError = outcome.message);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.cardBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.verified_user_outlined, size: 72, color: AppColors.primary),
              const SizedBox(height: 20),
              Text('Identity check required', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                widget.reason == 'no_response'
                    ? "A face check during your last ride went unanswered. For everyone's safety, please verify it's really you before going online again."
                    : "A face check during your last ride didn't match. For everyone's safety, please verify it's really you before going online again.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textGrey),
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 16),
                Text(_lastError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'Verify now', loading: _checking, onTap: _start)),
            ]),
          ),
        ),
      ),
    );
  }
}
