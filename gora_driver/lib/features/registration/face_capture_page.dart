import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../core/constants/app_colors.dart';
import '../../services/driver_api_service.dart';
import '../../services/face_service.dart';
import '../ride/widgets/face_camera_view.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'vehicle_selection_page.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_ui.dart';

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
      // Private: the face photo is served only to the driver and admins.
      final url = await DriverApiService.uploadFile(photo, private: true, purpose: 'face');
      if (!mounted) return;
      if (url == null) {
        setState(() { _saving = false; _error = DriverApiService.lastUploadError ?? 'Upload failed — check your connection and try again.'; });
        return;
      }
      final res = await DriverApiService.saveFaceSignature(vector, url);
      if (!mounted) return;
      if (res['code'] == 'FACE_LOCKED') {
        // Already registered (this step was done before): nothing to redo.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString())));
        final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
        Navigator.pushReplacementNamed(context, VehicleSelectionPage.route, arguments: args);
        return;
      }
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
      body: FaceCameraView(builder: (context, capture) => FaceCaptureChrome(
        stepIndex: _step.index,
        stepShort: _stepShort,
        instruction: _instruction,
        error: _error,
        busy: _busy,
        saving: _saving,
        onCapture: () => _onCapture(capture),
      )),
    );
  }
}

/// Everything drawn over the selfie camera: the registration step header,
/// the oval face guide and the bottom panel (pose dots, instruction, error,
/// shutter). Visual only — the page owns the capture logic.
///
/// Motion: the header and panel slide in, the instruction cross-fades when the
/// pose changes, the guide turns red on an error, the shutter dips while
/// pressed. All of it is instant when the OS asks for reduced motion.
class FaceCaptureChrome extends StatelessWidget {
  /// 0-based pose (look straight, one side, other side, tilt).
  final int stepIndex;
  final String stepShort;
  final String instruction;
  final String? error;
  final bool busy;
  final bool saving;
  final VoidCallback onCapture;
  const FaceCaptureChrome({
    super.key,
    required this.stepIndex,
    required this.stepShort,
    required this.instruction,
    this.error,
    this.busy = false,
    this.saving = false,
    required this.onCapture,
  });

  static const poses = 4;

  @override
  Widget build(BuildContext context) {
    final dur = regDuration(context, const Duration(milliseconds: 260));
    return Stack(children: [
      // Scrim behind the header so white text stays readable against a
      // bright patch of whatever the camera sees.
      Positioned(left: 0, right: 0, top: 0, height: 230, child: IgnorePointer(child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [RegPalette.heroTop.withValues(alpha: 0.85), RegPalette.heroTop.withValues(alpha: 0.35), Colors.transparent]))))),
      // Oval guide so the driver frames their face consistently. Sits in
      // the band between the header and the bottom panel.
      Positioned.fill(
        top: MediaQuery.paddingOf(context).top + 104,
        bottom: 230,
        child: IgnorePointer(
          child: Center(
            child: LayoutBuilder(builder: (context, box) {
              final h = (box.maxHeight - 20).clamp(140.0, 310.0);
              return AnimatedContainer(
                duration: dur,
                width: h * 0.76, height: h,
                decoration: BoxDecoration(
                  border: Border.all(color: error != null ? AppColors.red : Colors.white, width: 3),
                  borderRadius: BorderRadius.all(Radius.elliptical(h * 0.38, h * 0.5)),
                ),
              );
            }),
          ),
        ),
      ),
      // Header: which registration step this is, with the same numbered
      // stepper as the other steps (drawn for a dark background).
      Positioned(
        left: 0, right: 0, top: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: RegEntrance(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(
                    child: Text('Take a selfie',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Semantics(label: 'Face verification', child: const RegStepPill(step: CapRegSteps.face)),
                ]),
                const SizedBox(height: 14),
                const RegStepper(step: CapRegSteps.face, dotSize: 26),
              ]),
            ),
          ),
        ),
      ),
      // Bottom panel: progress dots, instruction, error, shutter.
      Positioned(
        left: 0, right: 0, bottom: 0,
        child: RegEntrance(
          offset: 40,
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
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(poses, (i) {
                    final done = i < stepIndex, cur = i == stepIndex;
                    return AnimatedContainer(
                      duration: dur,
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: cur ? 22 : 8, height: 8,
                      decoration: BoxDecoration(
                        color: done ? Cap.green : (cur ? Cap.accent : Cap.divider),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  })),
                  const SizedBox(height: 12),
                  // The new pose's instruction slides in as the old one fades.
                  AnimatedSwitcher(
                    duration: dur,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: Column(key: ValueKey(stepIndex), mainAxisSize: MainAxisSize.min, children: [
                      Text('Step ${stepIndex + 1} of $poses · $stepShort',
                          textAlign: TextAlign.center,
                          style: Cap.body(size: 12.5, weight: FontWeight.w800, color: Cap.accent)),
                      const SizedBox(height: 4),
                      Text(instruction, textAlign: TextAlign.center, style: Cap.title(size: 18)),
                    ]),
                  ),
                  AnimatedSize(
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    child: error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text(error!, style: Cap.body(size: 12.5, weight: FontWeight.w600, color: AppColors.red))),
                              ]),
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 72,
                    child: Center(
                      child: saving
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Cap.accent)),
                              const SizedBox(width: 12),
                              Flexible(child: Text('Saving your photo…', style: Cap.body(size: 14))),
                            ])
                          : Semantics(
                              button: true,
                              label: 'Capture',
                              child: RegPressScale(
                                pressed: 0.9,
                                child: GestureDetector(
                                  onTap: busy ? null : onCapture,
                                  child: Container(
                                    width: 70, height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Cap.accent,
                                      border: Border.all(color: Cap.tile, width: 5),
                                    ),
                                    child: busy
                                        ? const Padding(padding: EdgeInsets.all(20),
                                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                                        : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                                  ),
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
      ),
    ]);
  }
}
