import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../../core/constants/app_colors.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/face_service.dart';
import '../../ride/widgets/face_camera_view.dart';

/// Single-shot "look straight at the camera" capture, used both for the
/// mid-ride mandatory re-check and the standalone unlock-after-lock flow.
/// [submit] does the actual API call and gets back the raw response, so the
/// caller decides what matched/mismatch/error means for its own flow.
class FaceSingleCapturePage extends StatefulWidget {
  final String title;
  final String subtitle;
  final int? deadlineSec;
  final Future<Map<String, dynamic>> Function(List<double> embedding, String photoUrl) submit;
  const FaceSingleCapturePage({super.key, required this.title, required this.subtitle, this.deadlineSec, required this.submit});

  @override
  State<FaceSingleCapturePage> createState() => _FaceSingleCapturePageState();
}

class _FaceSingleCapturePageState extends State<FaceSingleCapturePage> {
  bool _busy = false;
  String? _error;
  int? _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.deadlineSec != null) {
      _remaining = widget.deadlineSec;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining = (_remaining ?? 1) - 1);
        if ((_remaining ?? 0) <= 0) {
          _timer?.cancel();
          Navigator.pop(context, {'matched': false, 'timedOut': true});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onCapture(Future<XFile?> Function() capture) async {
    if (_busy) return;
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
    if (!FaceService.looksStraight(face)) {
      setState(() { _busy = false; _error = 'Please look straight at the camera.'; });
      return;
    }
    final vec = FaceService.landmarkVector(face);
    if (vec == null) {
      setState(() { _busy = false; _error = "Couldn't read your face clearly — try better lighting."; });
      return;
    }
    try {
      final url = await DriverApiService.uploadFile(photo);
      if (url == null) {
        setState(() { _busy = false; _error = 'Upload failed — check your connection and try again.'; });
        return;
      }
      final res = await widget.submit(vec, url);
      _timer?.cancel();
      if (!mounted) return;
      Navigator.pop(context, res);
    } catch (e) {
      setState(() { _busy = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.deadlineSec == null,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: FaceCameraView(builder: (context, capture) => Stack(children: [
            // Scrims so the overlay text/button stay readable against
            // whatever the camera happens to be pointed at.
            Positioned(left: 0, right: 0, top: 0, height: 160, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent])))),
            Positioned(left: 0, right: 0, bottom: 0, height: 160, child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent])))),
            Center(
              child: Container(
                width: 230, height: 300,
                decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 3), borderRadius: BorderRadius.circular(140)),
              ),
            ),
            Positioned(
              left: 0, right: 0, top: 24,
              child: Column(children: [
                Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(widget.subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ),
                if (_remaining != null) ...[
                  const SizedBox(height: 12),
                  Text('$_remaining s', style: TextStyle(color: (_remaining ?? 0) <= 15 ? AppColors.red : Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                ],
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
                child: GestureDetector(
                  onTap: _busy ? null : () => _onCapture(capture),
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: AppColors.primary, width: 4)),
                    child: _busy ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  ),
                ),
              ),
            ),
          ])),
        ),
      ),
    );
  }
}
