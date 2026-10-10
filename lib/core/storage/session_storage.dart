import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Snapshot of everything persisted about the signed-in driver.
///
/// Persisted in [SharedPreferences] so it is readable from both the UI isolate
/// and the background-service isolate.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.serverUrl,
    this.userId,
    this.userUuid,
    this.displayName,
    this.vehicleId,
    this.vehiclePlate,
  });

  final String token;
  final String serverUrl;
  final int? userId;
  final String? userUuid;
  final String? displayName;

  /// Numeric vehicle id expected by `POST /api/telemetry` (`vehicle_id`).
  final int? vehicleId;
  final String? vehiclePlate;

  bool get hasVehicle => vehicleId != null;
}

/// Thin typed wrapper around [SharedPreferences] for session data.
abstract final class SessionStorage {
  static const _kToken = 'token';
  static const _kServerUrl = 'server_url';
  static const _kUserId = 'user_id';
  static const _kUserUuid = 'user_uuid';
  static const _kDisplayName = 'display_name';
  static const _kVehicleId = 'vehicle_id_int';
  static const _kVehiclePlate = 'vehicle_plate';

  /// Loads the current session, or `null` when signed out.
  ///
  /// Pass [reload] from the background isolate: each isolate keeps its own
  /// in-memory cache, so values written by the UI are otherwise not visible.
  static Future<StoredSession?> load({bool reload = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (reload) await prefs.reload();

    final token = prefs.getString(_kToken);
    if (token == null || token.isEmpty) return null;

    return StoredSession(
      token: token,
      serverUrl: prefs.getString(_kServerUrl) ?? AppConfig.defaultBaseUrl,
      userId: prefs.getInt(_kUserId),
      userUuid: prefs.getString(_kUserUuid),
      displayName: prefs.getString(_kDisplayName),
      vehicleId: prefs.getInt(_kVehicleId),
      vehiclePlate: prefs.getString(_kVehiclePlate),
    );
  }

  /// Last server URL the user signed in to (pre-fills the login form).
  static Future<String> lastServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrl) ?? AppConfig.defaultBaseUrl;
  }

  static Future<void> save(StoredSession s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, s.token);
    await prefs.setString(_kServerUrl, s.serverUrl);
    await _setOrRemoveInt(prefs, _kUserId, s.userId);
    await _setOrRemoveString(prefs, _kUserUuid, s.userUuid);
    await _setOrRemoveString(prefs, _kDisplayName, s.displayName);
    await _setOrRemoveInt(prefs, _kVehicleId, s.vehicleId);
    await _setOrRemoveString(prefs, _kVehiclePlate, s.vehiclePlate);
  }

  /// Clears credentials but keeps the server URL for the next sign-in.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kToken,
      _kUserId,
      _kUserUuid,
      _kDisplayName,
      _kVehicleId,
      _kVehiclePlate,
    ]) {
      await prefs.remove(key);
    }
  }

  static Future<void> _setOrRemoveInt(SharedPreferences p, String k, int? v) =>
      v == null ? p.remove(k) : p.setInt(k, v);

  static Future<void> _setOrRemoveString(
    SharedPreferences p,
    String k,
    String? v,
  ) => v == null ? p.remove(k) : p.setString(k, v);
}
