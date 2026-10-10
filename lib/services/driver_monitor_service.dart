import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Kinds of unsafe driver behaviour the monitor can detect.
enum DriverAlert {
  drowsy(
    title: 'Drowsiness detected',
    message: 'Your eyes are closing. Pull over safely and take a break.',
  ),
  distracted(
    title: 'Eyes on the road',
    message: 'You are looking away from the road. Focus ahead.',
  ),
  talking(
    title: 'Too much talking',
    message: 'Long conversation detected. Keep your focus on driving.',
  );

  const DriverAlert({required this.title, required this.message});

  final String title;
  final String message;
}

/// Tunable thresholds. Values are conservative defaults for a phone mounted
/// on the dashboard facing the driver; tweak after field testing.
abstract final class MonitorThresholds {
  /// Max frames analysed per second (saves CPU/battery; 5 fps is plenty).
  static const Duration frameInterval = Duration(milliseconds: 200);

  /// Eye-open probability below which an eye counts as closed.
  static const double eyeClosedProbability = 0.25;

  /// Continuous closed-eyes time that triggers [DriverAlert.drowsy].
  static const Duration eyesClosedFor = Duration(milliseconds: 1500);

  /// Head yaw (left/right) and pitch (down) limits, in degrees.
  static const double maxYaw = 30;
  static const double maxPitchDown = 20;

  /// Continuous looking-away time that triggers [DriverAlert.distracted].
  static const Duration lookingAwayFor = Duration(milliseconds: 2500);

  /// Face missing for this long (after being seen) also counts as distracted.
  static const Duration faceMissingFor = Duration(seconds: 4);

  /// Mouth gap / face height hysteresis for open-close (speech) cycles.
  static const double mouthOpenRatio = 0.045;
  static const double mouthClosedRatio = 0.025;

  /// [DriverAlert.talking] fires when at least [talkingCycles] mouth
  /// open-close cycles happen within [talkingWindow].
  static const Duration talkingWindow = Duration(seconds: 20);
  static const int talkingCycles = 22;

  /// Minimum gap between two alerts of the same kind.
  static const Duration cooldown = Duration(seconds: 15);
}

/// Live readings, exposed for the on-screen indicator.
@immutable
class MonitorReading {
  const MonitorReading({
    this.faceVisible = false,
    this.eyesClosed = false,
    this.lookingAway = false,
    this.talking = false,
    this.analyzing = false,
    this.problem,
  });

  final bool faceVisible;
  final bool eyesClosed;
  final bool lookingAway;
  final bool talking;

  /// `true` once at least one frame has been analysed successfully.
  final bool analyzing;

  /// Why frames can't be analysed (shown on screen), or `null` when fine.
  final String? problem;
}

/// On-device driver monitoring using Google ML Kit face detection.
///
/// Runs fully offline on the camera preview stream; nothing is uploaded.
/// Frames are throttled and dropped while a previous one is still being
/// processed, so the UI and snapshot capture stay smooth.
class DriverMonitorService {
  DriverMonitorService();

  /// ML Kit only ships for Android and iOS.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final _alerts = StreamController<DriverAlert>.broadcast();
  final reading = ValueNotifier(const MonitorReading());

  /// Emits whenever an alert condition is confirmed (respecting cooldown).
  Stream<DriverAlert> get alerts => _alerts.stream;

  FaceDetector? _detector;
  bool _busy = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // Condition timers.
  DateTime? _eyesClosedSince;
  DateTime? _lookingAwaySince;
  DateTime? _faceMissingSince;
  bool _faceSeenOnce = false;
  bool _mouthOpen = false;
  final _mouthCycles = <DateTime>[];
  final _lastAlertAt = <DriverAlert, DateTime>{};

  FaceDetector get _faceDetector => _detector ??= FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eye-open probabilities
      enableContours: true, // lip contours for speech detection
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  /// Feeds one preview frame. Safe to call for every frame: excess frames are
  /// dropped by the throttle.
  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastFrame) < MonitorThresholds.frameInterval) {
      return;
    }
    final input = _toInputImage(image, camera);
    if (input == null) {
      _report(
        'Unsupported frame: ${image.format.group.name} '
        '(raw ${image.format.raw}, ${image.planes.length} planes)',
      );
      return;
    }

    _busy = true;
    _lastFrame = now;
    try {
      final faces = await _faceDetector.processImage(input);
      _evaluate(faces, now);
    } catch (e) {
      debugPrint('Face detection failed: $e');
      _report('Detector error: $e');
    } finally {
      _busy = false;
    }
  }

  void _report(String problem) {
    if (reading.value.problem != problem) {
      reading.value = MonitorReading(problem: problem);
    }
  }

  /// Clears timers, e.g. when tracking stops or the camera switches.
  void reset() {
    _eyesClosedSince = null;
    _lookingAwaySince = null;
    _faceMissingSince = null;
    _faceSeenOnce = false;
    _mouthOpen = false;
    _mouthCycles.clear();
    reading.value = const MonitorReading();
  }

  Future<void> dispose() async {
    await _alerts.close();
    reading.dispose();
    await _detector?.close();
  }

  // ---------------------------------------------------------------------------
  // Rules
  // ---------------------------------------------------------------------------

  void _evaluate(List<Face> faces, DateTime now) {
    if (faces.isEmpty) {
      _eyesClosedSince = null;
      _lookingAwaySince = null;
      if (_faceSeenOnce) {
        _faceMissingSince ??= now;
        if (now.difference(_faceMissingSince!) >=
            MonitorThresholds.faceMissingFor) {
          _raise(DriverAlert.distracted, now);
        }
      }
      reading.value = const MonitorReading(analyzing: true);
      return;
    }

    // The largest face is the driver (passengers appear smaller).
    final face = faces.reduce(
      (a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
              b.boundingBox.width * b.boundingBox.height
          ? a
          : b,
    );
    _faceSeenOnce = true;
    _faceMissingSince = null;

    final eyesClosed = _checkEyes(face, now);
    final lookingAway = _checkHeadPose(face, now);
    final talking = _checkMouth(face, now);

    reading.value = MonitorReading(
      faceVisible: true,
      analyzing: true,
      eyesClosed: eyesClosed,
      lookingAway: lookingAway,
      talking: talking,
    );
  }

  /// Drowsiness: both eyes closed continuously.
  bool _checkEyes(Face face, DateTime now) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final closed =
        left != null &&
        right != null &&
        left < MonitorThresholds.eyeClosedProbability &&
        right < MonitorThresholds.eyeClosedProbability;

    if (!closed) {
      _eyesClosedSince = null;
      return false;
    }
    _eyesClosedSince ??= now;
    if (now.difference(_eyesClosedSince!) >= MonitorThresholds.eyesClosedFor) {
      _raise(DriverAlert.drowsy, now);
    }
    return true;
  }

  /// Distraction: head turned sideways or tilted down (e.g. at a phone).
  /// Head pose is used as a robust proxy for gaze direction.
  bool _checkHeadPose(Face face, DateTime now) {
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0; // negative = looking down
    final away =
        yaw.abs() > MonitorThresholds.maxYaw ||
        pitch < -MonitorThresholds.maxPitchDown;

    if (!away) {
      _lookingAwaySince = null;
      return false;
    }
    _lookingAwaySince ??= now;
    if (now.difference(_lookingAwaySince!) >=
        MonitorThresholds.lookingAwayFor) {
      _raise(DriverAlert.distracted, now);
    }
    return true;
  }

  /// Excessive talking: many mouth open/close cycles in a rolling window.
  bool _checkMouth(Face face, DateTime now) {
    final upper = face.contours[FaceContourType.upperLipBottom]?.points;
    final lower = face.contours[FaceContourType.lowerLipTop]?.points;
    final height = face.boundingBox.height;
    if (upper == null ||
        lower == null ||
        upper.isEmpty ||
        lower.isEmpty ||
        height <= 0) {
      return false;
    }

    final gap = (_meanY(lower) - _meanY(upper)) / height;
    if (!_mouthOpen && gap > MonitorThresholds.mouthOpenRatio) {
      _mouthOpen = true;
    } else if (_mouthOpen && gap < MonitorThresholds.mouthClosedRatio) {
      _mouthOpen = false;
      _mouthCycles.add(now); // one completed open→close cycle
    }

    _mouthCycles.removeWhere(
      (t) => now.difference(t) > MonitorThresholds.talkingWindow,
    );
    final talking = _mouthCycles.length >= MonitorThresholds.talkingCycles ~/ 2;
    if (_mouthCycles.length >= MonitorThresholds.talkingCycles) {
      _raise(DriverAlert.talking, now);
      _mouthCycles.clear();
    }
    return talking;
  }

  static double _meanY(List<math.Point<int>> points) =>
      points.fold<int>(0, (sum, p) => sum + p.y) / points.length;

  void _raise(DriverAlert alert, DateTime now) {
    final last = _lastAlertAt[alert];
    if (last != null && now.difference(last) < MonitorThresholds.cooldown) {
      return;
    }
    _lastAlertAt[alert] = now;
    if (!_alerts.isClosed) _alerts.add(alert);
  }

  // ---------------------------------------------------------------------------
  // CameraImage → InputImage
  // ---------------------------------------------------------------------------

  /// Converts a preview frame for ML Kit.
  ///
  /// * iOS: single-plane BGRA8888, passed through.
  /// * Android: single-plane NV21 is passed through; multi-plane
  ///   YUV_420_888 (what many CameraX devices deliver even when NV21 is
  ///   requested) is repacked into NV21, honouring row and pixel strides.
  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation, // UI is portrait-locked: sensor angle suffices
    );
    if (rotation == null || image.planes.isEmpty) return null;

    final size = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isIOS) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    final Uint8List nv21;
    if (image.planes.length == 1) {
      nv21 = image.planes.first.bytes;
    } else if (image.planes.length == 3) {
      nv21 = _yuv420ToNv21(image);
    } else {
      return null;
    }
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: size,
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.length == 1
            ? image.planes.first.bytesPerRow
            : image.width,
      ),
    );
  }

  /// Packs Y, U, V planes into NV21 (full Y, then interleaved V/U).
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));

    // Luma, row by row (rows may be padded beyond the width).
    var o = 0;
    for (var row = 0; row < h; row++) {
      out.setRange(o, o + w, y.bytes, row * y.bytesPerRow);
      o += w;
    }

    // Chroma, subsampled 2x2; pixel stride is 1 (planar) or 2 (semi-planar).
    final uvRowStride = u.bytesPerRow;
    final uvPixelStride = u.bytesPerPixel ?? 1;
    for (var row = 0; row < h ~/ 2; row++) {
      for (var col = 0; col < w ~/ 2; col++) {
        final idx = row * uvRowStride + col * uvPixelStride;
        if (idx >= v.bytes.length || idx >= u.bytes.length) continue;
        out[o++] = v.bytes[idx];
        out[o++] = u.bytes[idx];
      }
    }
    return out;
  }
}
