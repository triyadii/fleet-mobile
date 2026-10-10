/// Static, compile-time configuration for the FleetTrack driver app.
///
/// Values that may differ between environments (e.g. [defaultBaseUrl]) can be
/// overridden at build time with `--dart-define`, for example:
///
/// ```sh
/// flutter run --dart-define=FLEET_BASE_URL=https://staging.example.com/fleet
/// ```
abstract final class AppConfig {
  /// Display name used across the UI and in the foreground notification.
  static const String appName = 'FleetTrack';

  /// Default backend root (without the `/api` suffix).
  static const String defaultBaseUrl = String.fromEnvironment(
    'FLEET_BASE_URL',
    defaultValue: 'https://dicotriyadi.site/fleet',
  );

  /// How often a telemetry sample is pushed while tracking is active.
  static const Duration telemetryInterval = Duration(seconds: 10);

  /// Max time to wait for a GPS fix before falling back to the last known one.
  static const Duration locationTimeout = Duration(seconds: 8);

  /// Network timeouts. Uploads get a longer budget because of the snapshot.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Upper bound of route points kept in memory for the live map polyline.
  static const int maxRoutePoints = 500;

  /// Fallback map centre (Jakarta) used before the first GPS fix arrives.
  static const double fallbackLat = -6.200000;
  static const double fallbackLng = 106.816666;

  /// Offset applied to outgoing timestamps (WIB, UTC+7), as the backend expects.
  static const Duration serverUtcOffset = Duration(hours: 7);

  /// Android notification channel used by the background tracking service.
  static const String notificationChannelId = 'fleet_tracking';
  static const int foregroundNotificationId = 888;

  /// Package name sent to OpenStreetMap tile servers (required by their policy).
  static const String userAgentPackageName = 'com.example.fleet_manajemen';
}
