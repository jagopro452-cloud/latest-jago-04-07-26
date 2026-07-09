import 'package:flutter/foundation.dart';

class BookingTrace {
  static const String _tag = '[BOOKING_TRACE]';

  static void step(String stage, Map<String, dynamic> data) {
    final buffer = StringBuffer('$_tag $stage');
    data.forEach((key, value) {
      buffer.write(' | $key=$value');
    });
    debugPrint(buffer.toString());
  }

  static void error(String stage, Object error, [StackTrace? stack]) {
    debugPrint('$_tag ERROR @$stage: $error');
    if (stack != null && kDebugMode) {
      debugPrint(stack.toString());
    }
  }

  static void api(String method, String url, {int? status, String? body}) {
    debugPrint('$_tag API $method $url status=${status ?? "?"}');
    if (body != null && body.isNotEmpty) {
      final preview = body.length > 600 ? '${body.substring(0, 600)}…' : body;
      debugPrint('$_tag API_BODY $preview');
    }
  }
}
