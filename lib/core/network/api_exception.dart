import 'package:dio/dio.dart';

import '../utils/json_utils.dart';

/// A user-presentable error raised by the API layer.
///
/// Wraps [DioException] so that UI code never has to know about transport
/// details; it only needs [message] and, occasionally, [statusCode].
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// Human readable message, safe to show in a snackbar.
  final String message;

  /// HTTP status code, when the server responded at all.
  final int? statusCode;

  /// `true` when the stored token is no longer accepted by the server.
  bool get isUnauthorized => statusCode == 401;

  /// Maps a [DioException] to an [ApiException] with a friendly message.
  ///
  /// For Laravel validation errors (422) the first field error is surfaced,
  /// otherwise the server's `message` is used when present.
  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException('The server took too long to respond.');
      case DioExceptionType.connectionError:
        return const ApiException('No connection. Check your internet access.');
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.');
      default:
        break;
    }

    final status = error.response?.statusCode;
    final body = asMap(error.response?.data);
    final fieldErrors = asMap(body?['errors']);
    final firstFieldError = fieldErrors?.values
        .expand((v) => v is List ? v : [v])
        .map(asString)
        .firstWhere((m) => m != null, orElse: () => null);

    final message =
        firstFieldError ??
        asString(body?['message']) ??
        switch (status) {
          401 => 'Your session has expired. Please sign in again.',
          403 => 'You are not allowed to perform this action.',
          404 => 'The requested resource was not found.',
          _ => 'Unexpected server error (${status ?? 'unknown'}).',
        };
    return ApiException(message, statusCode: status);
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
