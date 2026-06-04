import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Retry wrapper for critical API calls.
/// Retries up to [maxAttempts] times with TRUE exponential backoff on network/5xx errors.
/// 4xx client errors are returned immediately — no retry.
Future<http.Response> apiRetry(
  Future<http.Response> Function() fn, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(seconds: 1),
}) async {
  int attempt = 0;
  while (true) {
    try {
      attempt++;
      final res = await fn();
      if (res.statusCode >= 500 && attempt < maxAttempts) {
        await Future.delayed(baseDelay * pow(2, attempt - 1).toInt());
        continue;
      }
      return res;
    } on SocketException catch (_) {
      if (attempt >= maxAttempts) rethrow;
      await Future.delayed(baseDelay * pow(2, attempt - 1).toInt());
    } on TimeoutException catch (_) {
      if (attempt >= maxAttempts) rethrow;
      await Future.delayed(baseDelay * pow(2, attempt - 1).toInt());
    } on http.ClientException catch (_) {
      if (attempt >= maxAttempts) rethrow;
      await Future.delayed(baseDelay * pow(2, attempt - 1).toInt());
    }
  }
}
