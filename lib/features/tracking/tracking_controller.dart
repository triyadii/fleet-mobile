import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_storage.dart';
import '../../data/models/telemetry_point.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/telemetry_repository.dart';
import '../../services/background_tracking_service.dart';
import '../../services/alert_notifier.dart';
import '../../services/camera_service.dart';
import '../../services/driver_monitor_service.dart';
import '../../services/location_service.dart';

/// State + business logic for the tracking dashboard.
///
/// All displayed data (route, position, speed) comes from the API: after each
/// successful `POST /telemetry` the history is re-read from
/// `GET /telemetry/{id}`. Nothing is synthesised locally.
///
/// Stability / optimisation:
/// * ticks never overlap: a slow upload simply skips the next interval;
/// * concurrent history reloads are coalesced into one request;
/// * the background service is silenced via heartbeat while the UI posts,
///   so the server receives one sample per interval, not two.
///
/// While tracking, the camera also feeds [DriverMonitorService], which raises
/// on-device safety alerts (drowsiness, distraction, excessive talking).
class TrackingController extends ChangeNotifier {
  TrackingController(this.session)
    : _telemetry = TelemetryRepository(
        ApiClient(baseUrl: session.serverUrl, token: session.token),
      );

  final StoredSession session;
  final TelemetryRepository _telemetry;
  final CameraService camera = CameraService();
  final DriverMonitorService monitor = DriverMonitorService();
  StreamSubscription<DriverAlert>? _alertSub;

  Timer? _timer;
  StreamSubscription<TelemetryPoint>? _gpsSub;
  bool _tickInFlight = false;
  bool _foreground = true;

  // ---- Observable state ----------------------------------------------------
  bool isTracking = false;
  bool isStarting = false;
  bool isLoadingHistory = false;
  List<TelemetryPoint> route = const [];

  /// Latest point stored on the server (from the API history).
  TelemetryPoint? lastPoint;

  /// Live position of this phone, shown on the map even while offline.
  /// Display only — it is never used in place of API data.
  TelemetryPoint? devicePosition;
  DateTime? lastSyncAt;
  int samplesSent = 0;
  int snapshotsSent = 0;

  /// Alert currently shown in the in-app banner (null = none).
  DriverAlert? activeAlert;
  int alertsRaised = 0;

  /// Latest error, shown as a banner; cleared on the next successful sync.
  String? error;

  /// Set when the token was rejected; the screen should return to login.
  bool sessionExpired = false;

  int? get vehicleId => session.vehicleId;

  // ---- Lifecycle -----------------------------------------------------------

  /// Initial load: camera, history and a running background service (if the
  /// app was relaunched while tracking).
  Future<void> init() async {
    unawaited(camera.initialize());
    _watchDevicePosition();
    await refreshHistory();
    if (await BackgroundTrackingService.isRunning()) {
      isTracking = true;
      _startTimer();
      _setMonitoring(true);
      notifyListeners();
    }
  }

  /// Called by the screen on app lifecycle changes.
  ///
  /// In the background the camera is released (Android revokes it anyway) and
  /// the UI timer stops, letting the background service take over.
  Future<void> setForeground(bool foreground) async {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _watchDevicePosition();
      await camera.initialize();
      if (isTracking) _startTimer();
    } else {
      _timer?.cancel();
      await _gpsSub?.cancel();
      _gpsSub = null;
      await camera.release();
    }
  }

  // ---- Commands ------------------------------------------------------------

  /// Requests permissions and starts tracking.
  /// Returns a user-facing message if tracking couldn't start.
  Future<String?> start() async {
    if (isTracking || isStarting) return null;
    final id = vehicleId;
    if (id == null) return 'No vehicle is assigned to this account.';

    isStarting = true;
    notifyListeners();
    try {
      switch (await LocationService.ensurePermissions()) {
        case LocationAccess.serviceDisabled:
          return 'Turn on location services (GPS) to start tracking.';
        case LocationAccess.denied:
          return 'Location permission is required to start tracking.';
        case LocationAccess.granted:
          break;
      }
      // Go live immediately; camera + service warm up in parallel so the
      // button doesn't hang on slow devices.
      isTracking = true;
      isStarting = false;
      notifyListeners();
      _startTimer();
      _setMonitoring(true);
      unawaited(
        Future.wait([
          if (!camera.isReady) camera.initialize(),
          BackgroundTrackingService.start(),
        ]).whenComplete(_tick),
      ); // first sample as soon as the camera is ready
      return null;
    } finally {
      isStarting = false;
      notifyListeners();
    }
  }

  void stop() {
    _timer?.cancel();
    isTracking = false;
    _setMonitoring(false);
    activeAlert = null;
    BackgroundTrackingService.stop();
    notifyListeners();
  }

  Future<void> logout() async {
    stop();
    await const AuthRepository().logout(session);
  }

  Future<void>? _historyRequest;

  /// Reloads route + latest position from the API (coalesced).
  Future<void> refreshHistory() => _historyRequest ??= _loadHistory()
      .whenComplete(() => _historyRequest = null);

  Future<void> _loadHistory() async {
    final id = vehicleId;
    if (id == null) return;
    isLoadingHistory = true;
    notifyListeners();
    try {
      route = await _telemetry.history(id);
      if (route.isNotEmpty) lastPoint = route.last;
      error = null;
    } on ApiException catch (e) {
      _handleApiError(e);
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  // ---- Internals -----------------------------------------------------------

  /// Dismisses the in-app safety banner.
  void dismissAlert() {
    activeAlert = null;
    notifyListeners();
  }

  /// Connects/disconnects the camera stream to the driver monitor.
  void _setMonitoring(bool enabled) {
    if (!DriverMonitorService.isSupported) return;
    if (enabled) {
      _alertSub ??= monitor.alerts.listen((alert) {
        activeAlert = alert;
        alertsRaised++;
        notifyListeners();
        AlertNotifier.show(alert);
      });
      unawaited(camera.setFrameListener(monitor.processFrame));
    } else {
      unawaited(camera.setFrameListener(null));
      monitor.reset();
    }
  }

  /// Subscribes to the device GPS (foreground only, battery-friendly).
  void _watchDevicePosition() {
    _gpsSub?.cancel();
    _gpsSub = LocationService.watch().listen((p) {
      devicePosition = p;
      notifyListeners();
    }, onError: (Object e) => debugPrint('GPS stream: $e'));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.telemetryInterval, (_) => _tick());
  }

  /// One sample: GPS fix + snapshot â†’ POST â†’ append to route.
  Future<void> _tick() async {
    final id = vehicleId;
    if (!isTracking || !_foreground || _tickInFlight || id == null) return;
    _tickInFlight = true;
    BackgroundTrackingService.heartbeat();
    try {
      final point = await LocationService.currentPoint();
      if (point == null) {
        error = 'Waiting for GPS signal…';
        return;
      }
      final snapshot = await camera.capture();
      await _telemetry.submit(vehicleId: id, point: point, snapshot: snapshot);

      samplesSent++;
      if (snapshot != null) snapshotsSent++;
      lastSyncAt = DateTime.now();
      error = null;
      // Map and stats reflect what the server stored.
      unawaited(refreshHistory());
    } on ApiException catch (e) {
      _handleApiError(e);
    } catch (e) {
      error = 'Tracking error: $e';
    } finally {
      _tickInFlight = false;
      notifyListeners();
    }
  }

  void _handleApiError(ApiException e) {
    error = e.message;
    if (e.isUnauthorized) {
      sessionExpired = true;
      stop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gpsSub?.cancel();
    _alertSub?.cancel();
    camera.dispose();
    monitor.dispose();
    super.dispose();
  }
}
