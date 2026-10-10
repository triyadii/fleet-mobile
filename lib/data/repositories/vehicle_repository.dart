import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_utils.dart';
import '../models/vehicle.dart';

/// Read access to `/api/vehicles`.
class VehicleRepository {
  const VehicleRepository(this._api);

  final ApiClient _api;

  /// Returns the vehicle assigned to the given driver, or `null` if none is
  /// assigned (or the vehicle list is not accessible for this account).
  Future<Vehicle?> findAssignedVehicle({int? userId, String? userUuid}) async {
    try {
      final vehicles = extractList(
        await _api.get('/vehicles'),
      ).map(Vehicle.tryParse).whereType<Vehicle>();
      for (final v in vehicles) {
        if (v.isAssignedTo(userId: userId, userUuid: userUuid)) return v;
      }
    } on ApiException catch (e) {
      // Non-fatal: the caller falls back to the user id.
      debugPrint('Vehicle lookup failed: $e');
    }
    return null;
  }
}
