import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// UUID v4 idempotency key — single source of truth for all POST calls that need deduplication.
String generateIdempotencyKey() {
  final rnd = Random.secure();
  final bytes = List.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${bytes.sublist(0, 4).map(hex).join()}-'
      '${bytes.sublist(4, 6).map(hex).join()}-'
      '${bytes.sublist(6, 8).map(hex).join()}-'
      '${bytes.sublist(8, 10).map(hex).join()}-'
      '${bytes.sublist(10).map(hex).join()}';
}

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
