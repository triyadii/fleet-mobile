import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/session_storage.dart';
import '../data/repositories/telemetry_repository.dart';
import 'location_service.dart';

/// Foreground service that keeps sending location while the app is in the
/// background or the screen is off.
///
/// **Avoiding duplicate posts:** while the UI is visible it sends telemetry
/// itself (with a camera snapshot) and pings the service with a heartbeat.
/// The service only posts when no heartbeat was received recently, so the
/// server receives exactly one sample per interval.
abstract final class BackgroundTrackingService {
  static const _evtHeartbeat = 'uiHeartbeat';
  static const _evtStop = 'stopService';

  static final _service = FlutterBackgroundService();

  /// Registers the Android notification channel and service entry points.
  /// Call once from `main()` before `runApp`.
  static Future<void> configure() async {
    if (kIsWeb) return;

    const channel = AndroidNotificationChannel(
      AppConfig.notificationChannelId,
      'Live tracking',
      description: 'Shown while your vehicle location is being shared.',
      importance: Importance.low,
    );
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConfig.notificationChannelId,
        initialNotificationTitle: AppConfig.appName,
        initialNotificationContent: 'Live tracking is active',
        foregroundServiceNotificationId: AppConfig.foregroundNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<bool> isRunning() async =>
      !kIsWeb && await _service.isRunning();

  static Future<void> start() async {
    if (!kIsWeb && !await _service.isRunning()) await _service.startService();
  }

  static void stop() {
    if (!kIsWeb) _service.invoke(_evtStop);
  }

  /// Tells the service the UI handled the current interval itself.
  static void heartbeat() {
    if (!kIsWeb) _service.invoke(_evtHeartbeat);
  }

  // ---------------------------------------------------------------------------
  // Background isolate
  // ---------------------------------------------------------------------------

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    DartPluginRegistrant.ensureInitialized();

    DateTime? lastUiBeat;
    var busy = false;

    service.on(_evtHeartbeat).listen((_) => lastUiBeat = DateTime.now());

    final timer = Timer.periodic(AppConfig.telemetryInterval, (_) async {
      // UI is in the foreground and already posting (with snapshots).
      final beat = lastUiBeat;
      if (beat != null &&
          DateTime.now().difference(beat) < AppConfig.telemetryInterval * 2) {
        return;
      }
      if (busy) return; // previous tick still running (slow network)
      busy = true;
      try {
        await _sendOnce(service);
      } catch (e) {
        debugPrint('Background telemetry failed: $e');
      } finally {
        busy = false;
      }
    });

    service.on(_evtStop).listen((_) {
      timer.cancel();
      service.stopSelf();
    });
  }

  static Future<void> _sendOnce(ServiceInstance service) async {
    final session = await SessionStorage.load(reload: true);
    final vehicleId = session?.vehicleId;
    if (session == null || vehicleId == null) {
      service.stopSelf(); // signed out: nothing to track
      return;
    }

    final point = await LocationService.currentPoint();
    if (point == null) return;

    await TelemetryRepository(
      ApiClient(baseUrl: session.serverUrl, token: session.token),
    ).submit(vehicleId: vehicleId, point: point);

    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      service.setForegroundNotificationInfo(
        title: AppConfig.appName,
        content:
            'Last sync $hh:$mm · ${point.speedKmh?.toStringAsFixed(0) ?? 0} km/h',
      );
    }
  }
}
