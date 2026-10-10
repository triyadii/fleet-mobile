import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_storage.dart';
import '../../core/utils/json_utils.dart';
import 'vehicle_repository.dart';

/// Handles sign-in / sign-out and bootstraps the persisted session.
class AuthRepository {
  const AuthRepository();

  /// Calls `POST /api/login`, resolves the driver's assigned vehicle via
  /// `GET /api/vehicles` and persists everything to [SessionStorage].
  ///
  /// Throws [ApiException] on failure.
  Future<StoredSession> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final body = asMap(
      await ApiClient(
        baseUrl: serverUrl,
      ).post('/login', data: {'username': username, 'password': password}),
    );

    final token = asString(body?['access_token']);
    if (token == null) {
      throw const ApiException(
        'Login response did not include an access token.',
      );
    }

    final user = asMap(body?['user']) ?? const {};
    final userId = asInt(user['id']);
    final userUuid = asString(user['uuid']);

    // Resolve the vehicle once at login instead of on every telemetry tick.
    final vehicle = await VehicleRepository(
      ApiClient(baseUrl: serverUrl, token: token),
    ).findAssignedVehicle(userId: userId, userUuid: userUuid);

    final session = StoredSession(
      token: token,
      serverUrl: serverUrl,
      userId: userId,
      userUuid: userUuid,
      displayName: asString(user['nama']) ?? asString(user['name']) ?? username,
      // Strictly from the API: null when no vehicle is assigned to the user.
      vehicleId: vehicle?.id,
      vehiclePlate: vehicle?.plateNumber,
    );
    await SessionStorage.save(session);
    return session;
  }

  /// Revokes the token server-side (best effort) and clears local state.
  Future<void> logout(StoredSession session) async {
    try {
      await ApiClient(
        baseUrl: session.serverUrl,
        token: session.token,
      ).post('/logout');
    } on ApiException {
      // Token may already be invalid; local sign-out must still succeed.
    } finally {
      await SessionStorage.clear();
    }
  }
}
