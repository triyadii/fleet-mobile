import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns the single [CameraController] used for dashcam snapshots.
///
/// Fixes the issues of the previous implementation:
/// * the old controller is **disposed** before switching lenses (it leaked);
/// * initialisation is serialised, so rapid taps can't create two controllers;
/// * captures never overlap (`takePicture` throws if called concurrently);
/// * flash is forced off so a snapshot every few seconds doesn't strobe;
/// * the temporary JPEG is deleted after reading so the cache doesn't grow;
/// * the controller can be released/re-acquired around app lifecycle changes.
///
/// It can also stream preview frames to a [FrameListener] (used by the
/// on-device driver monitor) while still taking snapshots.
typedef FrameListener =
    void Function(CameraImage image, CameraDescription camera);

class CameraService extends ChangeNotifier {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _index = 0;
  bool _capturing = false;
  Future<void>? _pending;
  String? _error;
  FrameListener? _frameListener;

  /// The active controller, only when fully initialised.
  CameraController? get controller =>
      (_controller?.value.isInitialized ?? false) ? _controller : null;

  bool get isReady => controller != null;
  bool get canSwitch => _cameras.length > 1;
  String? get error => _error;

  /// Opens the preferred lens (front by default, to watch the driver/cabin).
  Future<void> initialize({
    CameraLensDirection preferred = CameraLensDirection.front,
  }) {
    return _serialised(() async {
      if (_cameras.isEmpty) {
        try {
          _cameras = await availableCameras();
        } on CameraException catch (e) {
          _setError('Camera unavailable (${e.code}).');
          return;
        }
        final i = _cameras.indexWhere((c) => c.lensDirection == preferred);
        _index = i == -1 ? 0 : i;
      }
      await _open();
    });
  }

  /// Cycles to the next lens, disposing the current controller first.
  Future<void> switchCamera() {
    if (!canSwitch) return Future.value();
    return _serialised(() async {
      _index = (_index + 1) % _cameras.length;
      await _open();
    });
  }

  /// Starts (or with `null`, stops) delivering preview frames to [listener].
  /// The listener survives lens switches and lifecycle re-opens.
  Future<void> setFrameListener(FrameListener? listener) {
    _frameListener = listener;
    return _serialised(_syncImageStream);
  }

  Future<void> _syncImageStream() async {
    final c = controller;
    if (c == null || kIsWeb) return;
    final listener = _frameListener;
    try {
      if (listener != null && !c.value.isStreamingImages) {
        final description = c.description;
        await c.startImageStream((image) => listener(image, description));
      } else if (listener == null && c.value.isStreamingImages) {
        await c.stopImageStream();
      }
    } on CameraException catch (e) {
      debugPrint('Image stream: ${e.code} ${e.description}');
    }
  }

  /// Frees the camera (call when the app goes to background).
  Future<void> release() => _serialised(_disposeController);

  /// Takes a JPEG snapshot, or returns `null` when the camera isn't ready or a
  /// capture is already in progress. Never throws.
  ///
  /// Many devices can't take a still while the preview frame stream is
  /// running, so the stream is paused for the capture and resumed after.
  Future<Uint8List?> capture() async {
    if (_capturing) return null;
    _capturing = true;
    Uint8List? result;
    try {
      await _serialised(() async {
        result = await _captureUnsafe();
      });
      return result;
    } finally {
      _capturing = false;
    }
  }

  Future<Uint8List?> _captureUnsafe() async {
    final c = controller;
    if (c == null || c.value.isTakingPicture) return null;
    final wasStreaming = c.value.isStreamingImages;
    try {
      if (wasStreaming) await c.stopImageStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      // Best-effort cleanup of the temp file written by the plugin.
      if (!kIsWeb) {
        unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      }
      return bytes;
    } on CameraException catch (e) {
      debugPrint('Snapshot failed: ${e.code} ${e.description}');
      return null;
    } finally {
      if (wasStreaming) await _syncImageStream();
    }
  }

  Future<void> _open() async {
    await _disposeController();
    if (_cameras.isEmpty) {
      _setError('No camera found on this device.');
      return;
    }

    final controller = CameraController(
      _cameras[_index],
      // 480p keeps uploads small (~40–80 KB) while staying readable.
      ResolutionPreset.medium,
      enableAudio: false,
      // Stream format for ML Kit: single-plane NV21 (Android) / BGRA (iOS).
      // Snapshots from takePicture() are JPEG regardless.
      imageFormatGroup: (!kIsWeb && Platform.isIOS)
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off).catchError((_) {});
      await controller
          .lockCaptureOrientation(DeviceOrientation.portraitUp)
          .catchError((_) {});
      _error = null;
      await _syncImageStream();
    } on CameraException catch (e) {
      _controller = null;
      await controller.dispose();
      _setError(
        e.code == 'CameraAccessDenied'
            ? 'Camera permission denied.'
            : 'Camera failed to start (${e.code}).',
      );
      return;
    }
    notifyListeners();
  }

  Future<void> _disposeController() async {
    final old = _controller;
    if (old == null) return;
    _controller = null;
    notifyListeners(); // detach CameraPreview before disposing
    if (old.value.isStreamingImages) {
      await old.stopImageStream().catchError((_) {});
    }
    await old.dispose();
  }

  /// Runs [task] after any in-flight init/switch/release has completed.
  Future<void> _serialised(Future<void> Function() task) {
    final next = (_pending ?? Future.value()).then((_) => task());
    _pending = next.catchError((Object e) => debugPrint('Camera task: $e'));
    return _pending!;
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}
