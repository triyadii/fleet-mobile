import 'package:fleet_manajemen/core/utils/json_utils.dart';
import 'package:fleet_manajemen/data/models/telemetry_point.dart';
import 'package:fleet_manajemen/data/models/vehicle.dart';
import 'package:fleet_manajemen/data/repositories/telemetry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('json parsing', () {
    test('extractList handles common envelopes', () {
      expect(extractList([{'id': 1}]), hasLength(1));
      expect(extractList({'data': [{'id': 1}]}), hasLength(1));
      expect(extractList({'data': {'data': [{'id': 1}]}}), hasLength(1));
      expect(extractList({'data': {'logs': [{'id': 1}]}}, key: 'logs'), hasLength(1));
      expect(extractList({'message': 'x'}), isEmpty);
    });

    test('TelemetryPoint accepts string coordinates', () {
      final p = TelemetryPoint.tryParse({'lat': '-6.2', 'lng': 106.8, 'speed': '40'})!;
      expect(p.lat, -6.2);
      expect(p.speedKmh, 40);
      expect(TelemetryPoint.tryParse({'lat': null, 'lng': 1}), isNull);
    });

    test('Vehicle matches driver by uuid or id', () {
      final v = Vehicle.tryParse({'id': '3', 'user_uuid': 'abc', 'plate_number': 'B 1'})!;
      expect(v.id, 3);
      expect(v.isAssignedTo(userUuid: 'abc'), isTrue);
      expect(v.isAssignedTo(userId: 9), isFalse);
    });
  });

  test('timestamps are sent in WIB (UTC+7)', () {
    final s = TelemetryRepository.formatServerTimestamp(DateTime.utc(2026, 10, 8, 10, 30));
    expect(s, '2026-10-08T17:30:00+07:00');
  });
}
