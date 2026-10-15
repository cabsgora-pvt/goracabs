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
    if (result['error'] != null) {
      setState(() => _lastError = result['error'].toString());
      return;
    }
    if (result['matched'] == true) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _lastError = "That didn't match our records. Please try again, or contact support if this keeps happening.");
    }
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
