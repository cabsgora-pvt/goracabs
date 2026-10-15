import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// On-device face geometry: detection, pose checks and a landmark-based
/// feature vector, used for the registration signature and the mid-ride
/// re-check.
///
/// This is NOT a trained deep-learning face embedding (MobileFaceNet/FaceNet
/// etc.) — every maintained Flutter package for that either ships a model of
/// unknown/unclear provenance or needs one supplied, and bundling an
/// unverified neural network into a safety feature felt worse than not
/// having one. What this computes instead is a real, deterministic
/// fingerprint from ML Kit's own detected landmarks (normalized positions of
/// eyes/ears/cheeks/nose/mouth relative to the face box) — genuine signal,
/// fully offline, no third-party model, but lower-fidelity than a trained
/// embedding would be. That's why every mismatch still goes to an admin to
/// eyeball the two photos, rather than being treated as automatic proof.
class FaceService {
  static final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  static void dispose() => _detector.close();

  /// Runs ML Kit on a captured still photo. Null if no single confident face
  /// is found — including when more than one face is in frame, since a
  /// second person defeats the point of this check.
  static Future<Face?> detectSingleFace(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final faces = await _detector.processImage(input);
    if (faces.length != 1) return null;
    return faces.first;
  }

  static const double _yawTurnDeg = 18;
  static const double _straightToleranceDeg = 12;
  static const double _tiltDeg = 12;

  static bool looksStraight(Face face) {
    final yaw = face.headEulerAngleY ?? 999, pitch = face.headEulerAngleX ?? 999;
    return yaw.abs() < _straightToleranceDeg && pitch.abs() < _straightToleranceDeg;
  }

  /// True once the head has turned meaningfully to either side — direction
  /// (left/right) is deliberately not asserted here, since ML Kit's yaw sign
  /// convention isn't worth risking a mislabel over; "turned" vs "which way"
  /// only matters for display copy, not for the security check itself.
  static bool turnedToSide(Face face) => (face.headEulerAngleY ?? 0).abs() > _yawTurnDeg;

  /// Same side-turn check, but requires the opposite yaw sign from a previous
  /// capture — used to make sure "the other side" step was a real second
  /// direction, not a repeat of the first.
  static bool turnedOppositeSide(Face face, double previousYaw) {
    final yaw = face.headEulerAngleY ?? 0;
    return yaw.abs() > _yawTurnDeg && yaw.sign != previousYaw.sign;
  }

  static bool tiltedUpOrDown(Face face) => (face.headEulerAngleX ?? 0).abs() > _tiltDeg;

  /// 20-dim vector: 10 standard landmarks × (x,y), each normalized relative
  /// to the face bounding box so it's invariant to how close/far the camera
  /// was. Null if the box is degenerate.
  static List<double>? landmarkVector(Face face) {
    final box = face.boundingBox;
    if (box.width <= 0 || box.height <= 0) return null;
    const types = [
      FaceLandmarkType.leftEye, FaceLandmarkType.rightEye,
      FaceLandmarkType.leftEar, FaceLandmarkType.rightEar,
      FaceLandmarkType.leftCheek, FaceLandmarkType.rightCheek,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth, FaceLandmarkType.rightMouth, FaceLandmarkType.bottomMouth,
    ];
    final cx = box.left + box.width / 2, cy = box.top + box.height / 2;
    final vec = <double>[];
    for (final t in types) {
      final lm = face.landmarks[t];
      if (lm == null) {
        vec..add(0)..add(0);
        continue;
      }
      vec.add((lm.position.x - cx) / box.width);
      vec.add((lm.position.y - cy) / box.height);
    }
    return vec;
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return -1;
    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return -1;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
