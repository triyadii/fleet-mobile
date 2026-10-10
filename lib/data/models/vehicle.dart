import '../../core/utils/json_utils.dart';

/// A fleet vehicle as returned by `GET /api/vehicles`.
class Vehicle {
  const Vehicle({
    required this.id,
    this.uuid,
    this.plateNumber,
    this.userUuid,
    this.userId,
  });

  /// Numeric primary key, used as `vehicle_id` when posting telemetry.
  final int id;
  final String? uuid;
  final String? plateNumber;

  /// Assigned driver, which the API may expose by UUID, numeric id, or both.
  final String? userUuid;
  final int? userId;

  /// Returns `null` when the payload has no usable numeric id.
  static Vehicle? tryParse(JsonMap json) {
    final id = asInt(json['id']);
    if (id == null) return null;
    final user = asMap(json['user']) ?? asMap(json['pengguna']);
    return Vehicle(
      id: id,
      uuid: asString(json['uuid']),
      plateNumber: asString(json['plate_number']),
      userUuid: asString(json['user_uuid']) ?? asString(user?['uuid']),
      userId: asInt(json['user_id']) ?? asInt(user?['id']),
    );
  }

  /// Whether this vehicle is assigned to the given driver.
  bool isAssignedTo({int? userId, String? userUuid}) =>
      (userUuid != null && this.userUuid == userUuid) ||
      (userId != null && this.userId == userId);
}
