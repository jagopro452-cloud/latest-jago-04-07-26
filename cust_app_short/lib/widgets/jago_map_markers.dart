import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

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
        fill: JT.danger,
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

class JagoMapController {
  fmap.MapController? _inner;
  void attach(fmap.MapController map) => _inner = map;
  void move(LatLng target, {double? zoom}) {
    final m = _inner;
    if (m == null) return;
    m.move(ll.LatLng(target.latitude, target.longitude), zoom ?? m.camera.zoom);
  }
  void moveZoom(LatLng target, double zoom) {
    _inner?.move(ll.LatLng(target.latitude, target.longitude), zoom);
  }
  // Smooth follow: moves camera without changing zoom (Porter/Rapido style follow)
  void animateTo(LatLng target) {
    final m = _inner;
    if (m == null) return;
    m.move(ll.LatLng(target.latitude, target.longitude), m.camera.zoom);
  }
  void fitBounds(LatLngBounds bounds, {double padding = 48}) {
    _inner?.fitCamera(fmap.CameraFit.bounds(
      bounds: fmap.LatLngBounds(
        ll.LatLng(bounds.southwest.latitude, bounds.southwest.longitude),
        ll.LatLng(bounds.northeast.latitude, bounds.northeast.longitude),
      ),
      padding: EdgeInsets.all(padding),
    ));
  }
  void dispose() {}
}

class _MapPin extends StatelessWidget {
  final Color color;
  final String? label;
  const _MapPin({required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null && label!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Icon(
          Icons.location_on_rounded,
          color: color,
          size: 36,
          shadows: const [
            Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
      ],
    ),
    );
  }
}

class JagoMapView extends StatefulWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final EdgeInsets padding;
  final JagoMapController? controller;
  final String userAgentPackage;
  final void Function(JagoMapController controller)? onMapCreated;
  final void Function(CameraPosition position)? onCameraMove;
  final void Function()? onCameraIdle;
  const JagoMapView({
    super.key,
    required this.initialCameraPosition,
    this.markers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.padding = EdgeInsets.zero,
    this.controller,
    this.userAgentPackage = 'com.mindwhile.jago_customer',
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
  });
  @override
  State<JagoMapView> createState() => _JagoMapViewState();
}

class _JagoMapViewState extends State<JagoMapView> {
  late final fmap.MapController _mapController;
  late final JagoMapController _jagoController;
  @override
  void initState() {
    super.initState();
    _mapController = fmap.MapController();
    _jagoController = widget.controller ?? JagoMapController();
    _jagoController.attach(_mapController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMapCreated?.call(_jagoController);
    });
  }
  ll.LatLng _ll(LatLng p) => ll.LatLng(p.latitude, p.longitude);
  Color _markerColor(Marker m) {
    final id = m.markerId.value.toLowerCase();
    if (id.contains('pickup') || id == 'p' || id.contains('driver_location')) {
      return JT.primary;
    }
    if (id.contains('dest') || id == 'd' || id.contains('drop')) {
      return JT.danger;
    }
    if (id.contains('driver')) return JT.primaryDark;
    return JT.primary;
  }
  String? _markerLabel(Marker m) {
    final id = m.markerId.value.toLowerCase();
    if (id == 'p' || id.contains('pickup')) return 'PICKUP';
    if (id == 'd' || id.contains('dest') || id.contains('drop')) return 'DROP';
    return null;
  }
  Widget _markerWidget(Marker m) {
    final id = m.markerId.value.toLowerCase();
    if (id.contains('driver_location') || (id.contains('driver') && m.flat)) {
      return Transform.rotate(
        angle: m.rotation * math.pi / 180,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF1A6FDB),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
        ),
      );
    }
    return _MapPin(color: _markerColor(m), label: _markerLabel(m));
  }
  @override
  Widget build(BuildContext context) {
    final center = _ll(widget.initialCameraPosition.target);
    return SizedBox.expand(
      child: fmap.FlutterMap(
        mapController: _mapController,
        options: fmap.MapOptions(
          initialCenter: center,
          initialZoom: widget.initialCameraPosition.zoom,
          interactionOptions: const fmap.InteractionOptions(
            flags: fmap.InteractiveFlag.all,
          ),
          onPositionChanged: (pos, _) {
            widget.onCameraMove?.call(CameraPosition(
              target: LatLng(pos.center.latitude, pos.center.longitude),
              zoom: pos.zoom,
            ));
          },
          onMapEvent: (event) {
            if (event is fmap.MapEventMoveEnd) widget.onCameraIdle?.call();
          },
        ),
        children: [
          fmap.TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: widget.userAgentPackage,
            maxZoom: 19,
          ),
          if (widget.circles.isNotEmpty)
            fmap.CircleLayer(circles: widget.circles.map((c) => fmap.CircleMarker(
              point: _ll(c.center),
              radius: c.radius,
              color: c.fillColor ?? JT.primary.withValues(alpha: 0.08),
              borderColor: c.strokeColor ?? JT.primary.withValues(alpha: 0.35),
              borderStrokeWidth: c.strokeWidth.toDouble(),
            )).toList()),
          if (widget.polylines.isNotEmpty)
            fmap.PolylineLayer(polylines: widget.polylines.map((p) => fmap.Polyline(
              points: p.points.map(_ll).toList(),
              color: p.color,
              strokeWidth: p.width.toDouble(),
            )).toList()),
          if (widget.markers.isNotEmpty)
            fmap.MarkerLayer(markers: widget.markers.map((m) => fmap.Marker(
              point: _ll(m.position),
              width: 56,
              height: 64,
              alignment: Alignment.bottomCenter,
              child: _markerWidget(m),
            )).toList()),
        ],
      ),
    );
  }
}
