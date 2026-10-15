import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Front-camera preview + still capture, shared by every face-capture screen
/// (registration, mid-ride re-check, standalone re-verify). Handles its own
/// lifecycle — including releasing the camera when the app is backgrounded
/// and reopening it on resume, which `CameraController` does not do itself.
class FaceCameraView extends StatefulWidget {
  final Widget Function(BuildContext context, Future<XFile?> Function() capture) builder;
  const FaceCameraView({super.key, required this.builder});
  @override
  State<FaceCameraView> createState() => FaceCameraViewState();
}

class FaceCameraViewState extends State<FaceCameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera. Check camera permission in Settings.');
    }
  }

  Future<XFile?> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return null;
    try {
      return await c.takePicture();
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      c.dispose();
      setState(() => _controller = null);
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(fit: StackFit.expand, children: [
      // Mirrored so it feels like a selfie, matching what the driver expects.
      Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(pi),
        child: CameraPreview(c),
      ),
      widget.builder(context, _capture),
    ]);
  }
}
