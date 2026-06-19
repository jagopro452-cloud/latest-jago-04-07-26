import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Premium vehicle artwork — local SVG first, optional network overlay, icon fallback.
class VehicleArtwork extends StatelessWidget {
  final String vehicleKey;
  final double? width;
  final double? height;
  final String? networkUrl;
  final BoxFit fit;
  final Color? tint;

  const VehicleArtwork({
    super.key,
    required this.vehicleKey,
    this.width,
    this.height,
    this.networkUrl,
    this.fit = BoxFit.contain,
    this.tint,
  });

  static const Map<String, String> _assets = {
    'bike': 'assets/vehicles/bike.svg',
    'auto': 'assets/vehicles/auto.svg',
    'cab': 'assets/vehicles/mini_car.svg',
    'mini_car': 'assets/vehicles/mini_car.svg',
    'premium': 'assets/vehicles/sedan.svg',
    'sedan': 'assets/vehicles/sedan.svg',
    'suv': 'assets/vehicles/suv.svg',
    'parcel': 'assets/vehicles/parcel_bike.svg',
    'parcel_bike': 'assets/vehicles/parcel_bike.svg',
    'bike_parcel': 'assets/vehicles/parcel_bike.svg',
    'parcel_auto': 'assets/vehicles/parcel_auto.svg',
    'auto_parcel': 'assets/vehicles/parcel_auto.svg',
    'tata_ace': 'assets/vehicles/tata_ace.svg',
    'mini_truck': 'assets/vehicles/tata_ace.svg',
    'pickup_van': 'assets/vehicles/parcel_van.svg',
    'bolero_pickup': 'assets/vehicles/bolero.svg',
    'bolero': 'assets/vehicles/bolero.svg',
    'tempo_407': 'assets/vehicles/tempo_407.svg',
    'carpool': 'assets/vehicles/carpool.svg',
    'pool_bike': 'assets/vehicles/pool_bike.svg',
    'pool_auto': 'assets/vehicles/pool_auto.svg',
    'pool_mini': 'assets/vehicles/pool_mini.svg',
    'pool_sedan': 'assets/vehicles/pool_sedan.svg',
    'pool_suv': 'assets/vehicles/pool_suv.svg',
    'ride': 'assets/vehicles/sedan.svg',
    'delivery': 'assets/vehicles/parcel_bike.svg',
  };

  static String normalizeKey(String raw) {
    final n = raw.toLowerCase().trim();
    if (n.contains('premium')) return 'premium';
    if (n.contains('pickup van') || n.contains('pickup')) return 'pickup_van';
    if (n.contains('mini truck') || n.contains('tata ace') || n.contains('tata_ace')) return 'tata_ace';
    if (n.contains('bolero')) return 'bolero';
    if (n.contains('tempo')) return 'tempo_407';
    if (n.contains('parcel bike') || n.contains('bike parcel') || n.contains('bike_parcel')) return 'parcel_bike';
    if (n.contains('parcel auto') || n.contains('auto parcel') || n.contains('auto_parcel')) return 'parcel_auto';
    if (n.contains('parcel') || n.contains('delivery')) return 'parcel_bike';
    if (n.contains('carpool') || n.contains('pool')) return 'carpool';
    if (n.contains('suv') || n.contains('xl')) return 'suv';
    if (n.contains('sedan') || n.contains('cab') || n.contains('car')) return 'cab';
    if (n.contains('auto')) return 'auto';
    if (n.contains('bike')) return 'bike';
    return n.replaceAll(' ', '_');
  }

  static String? assetPathFor(String raw) {
    final key = normalizeKey(raw);
    return _assets[key] ?? _assets[raw.toLowerCase()];
  }

  static IconData iconFor(String raw) {
    final key = normalizeKey(raw);
    switch (key) {
      case 'bike':
      case 'parcel_bike':
      case 'pool_bike':
        return Icons.two_wheeler_rounded;
      case 'auto':
      case 'parcel_auto':
      case 'pool_auto':
        return Icons.electric_rickshaw_rounded;
      case 'parcel':
      case 'delivery':
      case 'tata_ace':
      case 'pickup_van':
      case 'bolero':
      case 'tempo_407':
        return Icons.local_shipping_rounded;
      case 'carpool':
        return Icons.people_alt_rounded;
      default:
        return Icons.directions_car_filled_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (networkUrl != null && networkUrl!.trim().isNotEmpty) {
      return Image.network(
        networkUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _local(),
      );
    }
    return _local();
  }

  Widget _local() {
    final path = assetPathFor(vehicleKey);
    if (path != null) {
      return SvgPicture.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        colorFilter: tint != null ? ColorFilter.mode(tint!, BlendMode.srcIn) : null,
        placeholderBuilder: (_) => _icon(),
      );
    }
    return _icon();
  }

  Widget _icon() {
    final size = height ?? width ?? 48.0;
    return Icon(iconFor(vehicleKey), size: size * 0.72, color: tint ?? const Color(0xFF2D8CFF));
  }
}
