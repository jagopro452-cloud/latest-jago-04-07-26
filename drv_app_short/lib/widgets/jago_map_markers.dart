import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/jago_theme.dart';

class JagoMapMarkers {
  static final Map<String, BitmapDescriptor> _cache = {};

  static Future<BitmapDescriptor> vehicle(
    String rawType, {
    bool searching = false,
  }) async {
    final spec = _VehicleSpec.from(rawType);
    final cacheKey = 'vehicle:${spec.cacheKey}:$searching';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final icon = await _buildVehicleMarker(spec, searching: searching);
    _cache[cacheKey] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> pickup() =>
      _pin('pickup', icon: Icons.my_location_rounded, fill: JT.primary);

  static Future<BitmapDescriptor> destination() => _pin(
        'destination',
        icon: Icons.location_on_rounded,
        fill: const Color(0xFF103B70),
      );

  static Future<BitmapDescriptor> _pin(
    String key, {
    required IconData icon,
    required Color fill,
  }) async {
    final cached = _cache[key];
    if (cached != null) return cached;

    const double size = 148;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    final center = const Offset(size / 2, 54);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(size / 2, 122),
        width: 54,
        height: 18,
      ),
      shadowPaint,
    );

    final pinPath = Path()
      ..moveTo(center.dx, 136)
      ..quadraticBezierTo(center.dx + 28, 104, center.dx + 34, 72)
      ..arcToPoint(
        Offset(center.dx - 34, 72),
        radius: const Radius.circular(34),
        clockwise: false,
      )
      ..quadraticBezierTo(center.dx - 28, 104, center.dx, 136)
      ..close();

    canvas.drawPath(
      pinPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 18),
          const Offset(size, 112),
          [fill, const Color(0xFF0E4A98)],
        ),
    );
    canvas.drawPath(
      pinPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white,
    );

    canvas.drawCircle(center, 23, Paint()..color = Colors.white);
    _paintIcon(
      canvas,
      icon: icon,
      color: const Color(0xFF16304D),
      center: center,
      size: 34,
    );

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final result = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _cache[key] = result;
    return result;
  }

  static Future<BitmapDescriptor> _buildVehicleMarker(
    _VehicleSpec spec, {
    required bool searching,
  }) async {
    const double size = 156;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    const bodyCenter = Offset(size / 2, 74);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: searching ? 0.12 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(size / 2, 128),
        width: 62,
        height: 20,
      ),
      shadowPaint,
    );

    final outerPath = Path()
      ..moveTo(bodyCenter.dx, 10)
      ..lineTo(bodyCenter.dx - 15, 28)
      ..quadraticBezierTo(18, 36, 18, 74)
      ..quadraticBezierTo(18, 126, bodyCenter.dx, 126)
      ..quadraticBezierTo(size - 18, 126, size - 18, 74)
      ..quadraticBezierTo(size - 18, 36, bodyCenter.dx + 15, 28)
      ..close();

    final gradientColors = spec.premium
        ? [const Color(0xFF0F4FA3), JT.primary, const Color(0xFF0B2E56)]
        : searching
            ? [const Color(0xFF4A9BFF), JT.primary, const Color(0xFF0E4B99)]
            : [JT.primary, const Color(0xFF0E4B99)];

    canvas.drawPath(
      outerPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(8, 12),
          const Offset(size - 8, 118),
          gradientColors,
        ),
    );
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white,
    );

    if (searching) {
      canvas.drawCircle(
        bodyCenter,
        54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = JT.primary.withValues(alpha: 0.20),
      );
    }

    canvas.drawCircle(bodyCenter, 34, Paint()..color = Colors.white);
    canvas.drawCircle(
      bodyCenter,
      34,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFE6EEF8),
    );

    _paintIcon(
      canvas,
      icon: spec.icon,
      color: const Color(0xFF16304D),
      center: bodyCenter,
      size: 44,
    );

    if (spec.badge != _VehicleBadge.none) {
      _paintBadge(canvas, spec.badge);
    }

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static void _paintBadge(Canvas canvas, _VehicleBadge badge) {
    const center = Offset(114, 108);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(const Offset(114, 111), 18, shadow);

    canvas.drawCircle(center, 18, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF16304D),
    );

    final IconData icon = switch (badge) {
      _VehicleBadge.parcel => Icons.inventory_2_rounded,
      _VehicleBadge.pool => Icons.groups_rounded,
      _VehicleBadge.outstation => Icons.route_rounded,
      _VehicleBadge.none => Icons.circle,
    };

    _paintIcon(
      canvas,
      icon: icon,
      color: JT.primary,
      center: center,
      size: 18,
    );
  }

  static void _paintIcon(
    Canvas canvas, {
    required IconData icon,
    required Color color,
    required Offset center,
    required double size,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(center.dx - (textPainter.width / 2),
          center.dy - (textPainter.height / 2)),
    );
  }
}

enum _VehicleBadge { none, parcel, pool, outstation }

class _VehicleSpec {
  final String cacheKey;
  final IconData icon;
  final _VehicleBadge badge;
  final bool premium;

  const _VehicleSpec({
    required this.cacheKey,
    required this.icon,
    required this.badge,
    this.premium = false,
  });

  factory _VehicleSpec.from(String rawType) {
    final type = rawType.toLowerCase().trim();
    final bool isParcel = type.contains('parcel');
    final bool isOutstation =
        type.contains('outstation') || type.contains('intercity');
    final bool isPool = !isOutstation &&
        (type.contains('pool') ||
            type.contains('carpool') ||
            type.contains('sharing'));

    final badge = isParcel
        ? _VehicleBadge.parcel
        : isOutstation
            ? _VehicleBadge.outstation
            : isPool
                ? _VehicleBadge.pool
                : _VehicleBadge.none;

    if (type.contains('tempo') || type.contains('truck')) {
      return _VehicleSpec(
        cacheKey: 'tempo${badge.name}',
        icon: Icons.local_shipping_rounded,
        badge: badge,
      );
    }
    if (type.contains('bike') || type.contains('moto') || type.contains('scooter')) {
      return _VehicleSpec(
        cacheKey: 'bike${badge.name}',
        icon: Icons.two_wheeler_rounded,
        badge: badge,
      );
    }
    if (type.contains('auto')) {
      return _VehicleSpec(
        cacheKey: 'auto${badge.name}',
        icon: Icons.electric_rickshaw_rounded,
        badge: badge,
      );
    }
    if (type.contains('premium')) {
      return _VehicleSpec(
        cacheKey: 'premium${badge.name}',
        icon: Icons.directions_car_filled_rounded,
        badge: badge,
        premium: true,
      );
    }
    return _VehicleSpec(
      cacheKey: 'cab${badge.name}',
      icon: Icons.directions_car_rounded,
      badge: badge,
    );
  }
}
