import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/json_utils.dart';
import '../../services/driver_monitor_service.dart';
import '../models/telemetry_point.dart';

/// Read/write access to `/api/telemetry`.
///
/// Shared by the UI isolate (with camera snapshots) and the background
/// service isolate (location only).
class TelemetryRepository {
  const TelemetryRepository(this._api);

  final ApiClient _api;

  /// `POST /api/telemetry` (multipart). [snapshot] is an optional JPEG.
  Future<void> submit({
    required int vehicleId,
    required TelemetryPoint point,
    Uint8List? snapshot,
    DriverStatus? driver,
  }) async {
    final form = FormData.fromMap({
      'vehicle_id': vehicleId,
      'lat': point.lat,
      'lng': point.lng,
      'speed': (point.speedKmh ?? 0).toStringAsFixed(1),
      'timestamp': formatServerTimestamp(point.timestamp ?? DateTime.now()),
      // Optional driver-state flags. Sent as 1/0, which Laravel's `boolean`
      // rule accepts (the strings "true"/"false" would be rejected).
      if (driver != null) ...{
        'fokus': driver.focused ? 1 : 0,
        'mengantuk': driver.drowsy ? 1 : 0,
        'berisik': driver.talking ? 1 : 0,
        'tidak_ditempat': driver.away ? 1 : 0,
      },
      if (snapshot != null)
        'snapshot': MultipartFile.fromBytes(
          snapshot,
          filename: 'snapshot_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
    });
    await _api.post('/telemetry', data: form);
  }

  /// `GET /api/telemetry/{vehicle_id}`, returned oldest → newest so it can be
  /// drawn directly as a route polyline.
  Future<List<TelemetryPoint>> history(int vehicleId) async {
    final points = extractList(
      await _api.get('/telemetry/$vehicleId'),
      key: 'logs',
    ).map(TelemetryPoint.tryParse).whereType<TelemetryPoint>().toList();

    // The API does not guarantee ordering; sort when timestamps are present.
    if (points.every((p) => p.timestamp != null)) {
      points.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    }
    final overflow = points.length - AppConfig.maxRoutePoints;
    return overflow > 0 ? points.sublist(overflow) : points;
  }

  /// Formats [time] as ISO-8601 in server local time, e.g.
  /// `2026-10-08T17:30:00+07:00`.
  static String formatServerTimestamp(DateTime time) {
    final offset = AppConfig.serverUtcOffset;
    final t = time.toUtc().add(offset);
    String two(int n) => n.toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    final oh = two(offset.inHours.abs());
    final om = two(offset.inMinutes.abs() % 60);
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}$sign$oh:$om';
  }
}
