import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../core/constants/app_colors.dart';
import '../../services/driver_api_service.dart';
import '../../services/face_service.dart';
import '../ride/widgets/face_camera_view.dart';
import '../../widgets/captain_ui/captain_ui.dart';
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

  /// Short label for the step header — "Look straight".
  String get _stepShort => switch (_step) {
    _Step.straight => 'Look straight',
    _Step.sideA => 'Turn to one side',
    _Step.sideB => 'Turn to the other side',
    _Step.tilt => 'Tilt your head',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FaceCameraView(builder: (context, capture) => Stack(children: [
        // Scrim behind the header so white text stays readable against a
        // bright patch of whatever the camera sees.
        Positioned(left: 0, right: 0, top: 0, height: 170, child: IgnorePointer(child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent]))))),
        // Oval guide so the driver frames their face consistently. Sits in
        // the band between the header and the bottom panel.
        Positioned.fill(
          bottom: 230,
          child: IgnorePointer(
            child: Center(
              child: LayoutBuilder(builder: (context, box) {
                final h = (box.maxHeight - 150).clamp(160.0, 310.0);
                return Container(
                  width: h * 0.76, height: h,
                  decoration: BoxDecoration(
                    border: Border.all(color: _error != null ? AppColors.red : Colors.white, width: 3),
                    borderRadius: BorderRadius.all(Radius.elliptical(h * 0.38, h * 0.5)),
                  ),
                );
              }),
            ),
          ),
        ),
        // Header: which registration step this is.
        Positioned(
          left: 0, right: 0, top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Step ${CapRegSteps.face} of ${CapRegSteps.total} · Face verification',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Take a selfie', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
        // Bottom panel: progress dots, instruction, error, shutter.
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Cap.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
                    final done = i < _step.index, cur = i == _step.index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: cur ? 22 : 8, height: 8,
                      decoration: BoxDecoration(
                        color: done ? Cap.green : (cur ? Cap.accent : Cap.divider),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  })),
                  const SizedBox(height: 12),
                  Text('Step ${_step.index + 1} of 4 · $_stepShort',
                      style: Cap.body(size: 12.5, weight: FontWeight.w800, color: Cap.accent)),
                  const SizedBox(height: 4),
                  Text(_instruction, textAlign: TextAlign.center, style: Cap.title(size: 18)),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: Cap.body(size: 12.5, weight: FontWeight.w600, color: AppColors.red))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 72,
                    child: Center(
                      child: _saving
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Cap.accent)),
                              const SizedBox(width: 12),
                              Text('Saving your photo…', style: Cap.body(size: 14)),
                            ])
                          : Semantics(
                              button: true,
                              label: 'Capture',
                              child: GestureDetector(
                                onTap: _busy ? null : () => _onCapture(capture),
                                child: Container(
                                  width: 70, height: 70,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Cap.accent,
                                    border: Border.all(color: Cap.tile, width: 5),
                                  ),
                                  child: _busy
                                      ? const Padding(padding: EdgeInsets.all(20),
                                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                                      : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ])),
    );
  }
}
