import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/app_config.dart';
import '../data/models/telemetry_point.dart';

/// Result of [LocationService.ensurePermissions].
enum LocationAccess { granted, denied, serviceDisabled }

/// GPS access with permission handling and a time-boxed fix.
abstract final class LocationService {
  /// Requests the runtime permissions tracking needs.
  ///
  /// Foreground location is mandatory. Notification, camera, microphone and "allow all
  /// the time" location are requested but optional: tracking still works
  /// (with reduced capability) if the driver declines them.
  static Future<LocationAccess> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LocationAccess.denied;
    }

    await [
      Permission.notification,
      Permission.camera,
      Permission.microphone,
    ].request();
    // Android 11+ requires "always" to be requested after foreground access.
    if (permission == LocationPermission.whileInUse) {
      await Permission.locationAlways.request();
    }
    return LocationAccess.granted;
  }

  /// Returns a fresh GPS fix, falling back to the last known position when no
  /// fix arrives within [AppConfig.locationTimeout] (e.g. indoors).
  static Future<TelemetryPoint?> currentPoint() async {
    // A fix from the last few seconds is good enough and returns instantly.
    final last = await _lastKnown();
    var position =
        (last != null &&
            DateTime.now().difference(last.timestamp) <
                AppConfig.telemetryInterval)
        ? last
        : null;
    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: AppConfig.locationTimeout,
          ),
        );
      } on TimeoutException {
        position = last;
      }
    }
    if (position == null) return null;

    // Geolocator reports m/s; _toPoint converts to km/h as the API expects.
    return _toPoint(position);
  }

  /// Live device position for the "you are here" marker, independent of
  /// tracking. Requests foreground permission only (no background prompt).
  /// Emits nothing when GPS is off or permission is denied.
  static Stream<TelemetryPoint> watch() async* {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final initial = await _lastKnown();
    if (initial != null) yield _toPoint(initial);

    yield* Geolocator.getPositionStream(
      // Only emit after ~5 m of movement to save battery and rebuilds.
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map(_toPoint);
  }

  static TelemetryPoint _toPoint(Position p) => TelemetryPoint(
    lat: p.latitude,
    lng: p.longitude,
    speedKmh: p.speed < 0 ? 0 : p.speed * 3.6,
    timestamp: p.timestamp,
  );

  /// Last cached fix; not supported on web, where it returns `null`.
  static Future<Position?> _lastKnown() async {
    if (kIsWeb) return null;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}
