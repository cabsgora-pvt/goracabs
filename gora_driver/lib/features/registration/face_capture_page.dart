import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../core/constants/app_colors.dart';
import '../../services/driver_api_service.dart';
import '../../services/face_service.dart';
import '../ride/widgets/face_camera_view.dart';
import 'vehicle_selection_page.dart';

enum _Step { straight, sideA, sideB, tilt }

/// Guided face capture at registration: look straight, turn to each side,
/// tilt — the straight shot becomes both the profile picture and the
/// reference signature later checks are compared against. Each step is
/// validated against ML Kit's own head-pose reading before it's accepted, so
/// a static printed photo can't just be held up four times in a row.
class FaceCapturePage extends StatefulWidget {
  static const route = '/registration/face';
  const FaceCapturePage({super.key});
  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  _Step _step = _Step.straight;
  XFile? _straightPhoto;
  List<double>? _straightVector;
  double? _sideAYaw;
  bool _busy = false;
  String? _error;
  bool _saving = false;

  String get _instruction => switch (_step) {
    _Step.straight => 'Look straight at the camera',
    _Step.sideA => 'Turn your head to one side',
    _Step.sideB => 'Now turn to the other side',
    _Step.tilt => 'Tilt your head up or down slightly',
  };

  Future<void> _onCapture(Future<XFile?> Function() capture) async {
    if (_busy || _saving) return;
    setState(() { _busy = true; _error = null; });
    final photo = await capture();
    if (photo == null) {
      setState(() { _busy = false; _error = "Couldn't take the photo — try again."; });
      return;
    }
    final face = await FaceService.detectSingleFace(photo.path);
    if (face == null) {
      setState(() { _busy = false; _error = 'No single clear face found — make sure only your face is in frame.'; });
      return;
    }
    switch (_step) {
      case _Step.straight:
        if (!FaceService.looksStraight(face)) {
          setState(() { _busy = false; _error = 'Please look straight at the camera.'; });
          return;
        }
        final vec = FaceService.landmarkVector(face);
        if (vec == null) {
          setState(() { _busy = false; _error = "Couldn't read your face clearly — try better lighting."; });
          return;
        }
        setState(() {
          _straightPhoto = photo;
          _straightVector = vec;
          _step = _Step.sideA;
          _busy = false;
        });
        return;
      case _Step.sideA:
        if (!FaceService.turnedToSide(face)) {
          setState(() { _busy = false; _error = 'Turn your head further to the side.'; });
          return;
        }
        setState(() { _sideAYaw = face.headEulerAngleY ?? 0; _step = _Step.sideB; _busy = false; });
        return;
      case _Step.sideB:
        if (!FaceService.turnedOppositeSide(face, _sideAYaw ?? 0)) {
          setState(() { _busy = false; _error = 'Turn to the OTHER side from before.'; });
          return;
        }
        setState(() { _step = _Step.tilt; _busy = false; });
        return;
      case _Step.tilt:
        if (!FaceService.tiltedUpOrDown(face)) {
          setState(() { _busy = false; _error = 'Tilt your head up or down a bit more.'; });
          return;
        }
        setState(() => _busy = false);
        await _finish();
        return;
    }
  }

  Future<void> _finish() async {
    final photo = _straightPhoto, vector = _straightVector;
    if (photo == null || vector == null) return;
    setState(() => _saving = true);
    try {
      final url = await DriverApiService.uploadFile(photo);
      if (url == null) {
        setState(() { _saving = false; _error = 'Upload failed — check your connection and try again.'; });
        return;
      }
      final res = await DriverApiService.saveFaceSignature(vector, url);
      if (res['error'] != null) {
        setState(() { _saving = false; _error = res['error'].toString(); });
        return;
      }
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      Navigator.pushReplacementNamed(context, VehicleSelectionPage.route, arguments: args);
    } catch (e) {
      setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          FaceCameraView(builder: (context, capture) => Stack(children: [
            // Scrims behind the text/button overlays — without these, white
            // text disappears against a bright patch of whatever the camera
            // sees (a wall, the sky, a window) instead of a face.
            Positioned(left: 0, right: 0, top: 0, height: 140, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent])))),
            Positioned(left: 0, right: 0, bottom: 0, height: 160, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent])))),
            // Oval guide so the driver frames their face consistently.
            Center(
              child: Container(
                width: 230, height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 3),
                  borderRadius: BorderRadius.circular(140),
                ),
              ),
            ),
            Positioned(
              left: 0, right: 0, top: 24,
              child: Column(children: [
                Text('Step ${_step.index + 1} of 4', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(_instruction, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            if (_error != null)
              Positioned(
                left: 24, right: 24, bottom: 140,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                ),
              ),
            Positioned(
              left: 0, right: 0, bottom: 40,
              child: Center(
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : GestureDetector(
                        onTap: _busy ? null : () => _onCapture(capture),
                        child: Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: AppColors.primary, width: 4),
                          ),
                          child: _busy
                              ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))
                              : null,
                        ),
                      ),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}
