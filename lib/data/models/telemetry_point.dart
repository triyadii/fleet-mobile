import '../../core/utils/json_utils.dart';

/// One GPS sample, either read from the API history or produced locally.
class TelemetryPoint {
  const TelemetryPoint({
    required this.lat,
    required this.lng,
    this.speedKmh,
    this.timestamp,
  });

  final double lat;
  final double lng;
  final double? speedKmh;
  final DateTime? timestamp;

  /// Returns `null` for rows without valid coordinates (they are skipped).
  static TelemetryPoint? tryParse(JsonMap json) {
    final lat = asDouble(json['lat'] ?? json['latitude']);
    final lng = asDouble(json['lng'] ?? json['longitude']);
    if (lat == null || lng == null) return null;
    return TelemetryPoint(
      lat: lat,
      lng: lng,
      speedKmh: asDouble(json['speed']),
      timestamp: DateTime.tryParse(
        asString(
              json['timestamp'] ?? json['recorded_at'] ?? json['created_at'],
            ) ??
            '',
      ),
    );
  }
}
