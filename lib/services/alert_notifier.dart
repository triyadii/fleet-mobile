import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'driver_monitor_service.dart';

/// Presents driver-safety alerts as a high-priority heads-up notification
/// (pop-up with sound + vibration), complementing the in-app banner.
abstract final class AlertNotifier {
  static const _channelId = 'driver_safety_alerts';
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Long-short-long buzz, distinct from ordinary notifications.
  static final _vibration = Int64List.fromList([0, 600, 200, 600, 200, 900]);

  /// Creates the channel and initialises the plugin. Call once at startup.
  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _channelId,
            'Driver safety alerts',
            description: 'Drowsiness, distraction and talking warnings.',
            importance: Importance.max,
            enableVibration: true,
            vibrationPattern: _vibration,
          ),
        );
    _ready = true;
  }

  /// Vibrates and shows a heads-up notification for [alert].
  static Future<void> show(DriverAlert alert) async {
    await HapticFeedback.heavyImpact();
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.show(
        id: 1000 + alert.index, // one slot per alert type, replaced not stacked
        title: '⚠ ${alert.title}',
        body: alert.message,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Driver safety alerts',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            ticker: alert.title,
            vibrationPattern: _vibration,
            timeoutAfter: 10000,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Alert notification failed: $e');
    }
  }
}
