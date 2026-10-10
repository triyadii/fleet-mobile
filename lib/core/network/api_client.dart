import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Pre-configured HTTP client for the Fleet Tracking API.
///
/// * Sets sensible timeouts and JSON `Accept` headers.
/// * Injects the Sanctum bearer token on every request.
/// * Normalises all failures into [ApiException].
///
/// The client is cheap to create and holds no global state, so the background
/// isolate builds its own instance from the stored session.
class ApiClient {
  ApiClient({required String baseUrl, String? token})
    : _dio = Dio(
        BaseOptions(
          baseUrl: _normalise(baseUrl),
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          sendTimeout: AppConfig.sendTimeout,
          headers: {
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      ) {
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          logPrint: (o) => debugPrint(o.toString()),
        ),
      );
    }
  }

  final Dio _dio;

  /// Strips trailing slashes and appends the `/api` prefix.
  static String _normalise(String url) =>
      '${url.trim().replaceAll(RegExp(r'/+$'), '')}/api';

  Future<dynamic> get(String path) => _send(() => _dio.get(path));

  Future<dynamic> post(String path, {Object? data}) =>
      _send(() => _dio.post(path, data: data));

  /// Executes [request] and returns the decoded body, mapping errors.
  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
