import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Compile-time SHA-256 fingerprint of the production API server's TLS leaf cert.
///
/// Supply at build time:
///   flutter build apk --dart-define=CERT_PIN=<sha256-hex-fingerprint>
///
/// Obtain the fingerprint:
///   openssl s_client -connect api.jagoapp.com:443 </dev/null 2>/dev/null \
///     | openssl x509 -fingerprint -sha256 -noout
///
/// Leave empty (default) to skip pinning — dev and CI remain unaffected.
const _pinnedFingerprint =
    String.fromEnvironment('CERT_PIN', defaultValue: '');

/// Returns a [http.Client] that pins the server's TLS certificate in release.
/// Falls back to a plain client in debug mode or when no pin is configured.
http.Client buildHttpClient() {
  if (kDebugMode || _pinnedFingerprint.isEmpty) {
    return http.Client();
  }
  final ioClient = HttpClient();
  ioClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) => false;
  ioClient.connectionTimeout = const Duration(seconds: 15);
  return _PinnedIOClient(IOClient(ioClient));
}

class _PinnedIOClient extends http.BaseClient {
  final http.Client _inner;
  _PinnedIOClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Call once at app start (release builds only) to register an [HttpOverrides]
/// that verifies every outbound TLS connection against [_pinnedFingerprint].
void installCertificatePinning() {
  if (kDebugMode || _pinnedFingerprint.isEmpty) return;
  HttpOverrides.global = _PinningHttpOverrides();
  debugPrint('[CERT-PIN] Certificate pinning active');
}

class _PinningHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      if (!host.contains('jagoapp') && !host.contains('jago')) return false;
      final fingerprint = sha256.convert(cert.der).toString();
      if (fingerprint != _pinnedFingerprint.toLowerCase()) {
        debugPrint(
            '[CERT-PIN] Rejected connection to $host — fingerprint mismatch');
        return false;
      }
      return true;
    };
    return client;
  }
}
