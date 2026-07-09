import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/api_config.dart';
import '../config/jago_theme.dart';

/// Single source for vehicle images with premium 3D PNG priority.
/// Priority: Local 3D PNG → Network URL → Admin Icon → Emergency SVG → Icon fallback.
class VehicleArtwork extends StatelessWidget {
  final String vehicleKey;
  final double? width;
  final double? height;
  final String? networkUrl;
  final String? adminIcon;
  final BoxFit fit;
  final Color? tint;

  const VehicleArtwork({
    super.key,
    required this.vehicleKey,
    this.width,
    this.height,
    this.networkUrl,
    this.adminIcon,
    this.fit = BoxFit.contain,
    this.tint,
  });

  /// Official JAGO customer app PNG artwork (home + booking).
  /// PRIORITY 1: Local bundled 3D PNGs for offline consistency.
  static const Map<String, String> localPng3D = {
    'bike': 'assets/vehicles_3d/bike.png',
    'auto': 'assets/vehicles_3d/auto.png',
    'cab': 'assets/vehicles_3d/cab.png',
    'mini_car': 'assets/vehicles_3d/cab.png',
    'sedan': 'assets/vehicles_3d/sedan.png',
    'suv': 'assets/vehicles_3d/suv.png',
    'premium': 'assets/vehicles_3d/premium.png',
    'parcel': 'assets/vehicles_3d/parcel.png',
    'parcel_bike': 'assets/vehicles_3d/parcel_bike.png',
    'parcel_auto': 'assets/vehicles_3d/parcel_auto.png',
    'mini_truck': 'assets/vehicles_3d/tata_ace.png',
    'tata_ace': 'assets/vehicles_3d/tata_ace.png',
    'pickup_van': 'assets/vehicles_3d/pickup_van.png',
    'pickup_truck': 'assets/vehicles_3d/pickup_van.png',
    'bolero': 'assets/vehicles_3d/bolero.png',
    'tempo_407': 'assets/vehicles_3d/tempo_407.png',
    'carpool': 'assets/vehicles_3d/carpool.png',
    'outstation': 'assets/vehicles_3d/outstation.png',
    'delivery': 'assets/vehicles_3d/delivery.png',
  };

  /// PRIORITY 2: Network PNG artwork (CDN fallback + admin icons).
  static const Map<String, String> pngByKey = {
    'bike': 'https://res.cloudinary.com/kits/image/upload/q_auto/f_auto/v1775123974/bike_logo_g7idrq.png',
    'auto': 'https://res.cloudinary.com/kits/image/upload/q_auto/f_auto/v1775125550/ChatGPT_Image_Apr_2_2026_03_55_30_PM_ywb7fj.png',
    'cab': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_27_28_AM_w0rcnh',
    'mini_car': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_27_28_AM_w0rcnh',
    'sedan': 'https://res.cloudinary.com/dg5ct7fys/image/upload/v1780038163/ChatGPT_Image_May_29_2026_12_31_37_PM_ys5bjt.png',
    'suv': 'https://res.cloudinary.com/dg5ct7fys/image/upload/v1780038163/ChatGPT_Image_May_29_2026_12_31_37_PM_ys5bjt.png',
    'premium': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_31_05_AM_kavp5e',
    'parcel': 'https://res.cloudinary.com/kits/image/upload/q_auto/f_auto/v1775126915/ChatGPT_Image_Apr_2_2026_04_18_17_PM_g83nv8.png',
    'parcel_bike': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_49_26_AM_gjbrxs',
    'parcel_auto': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_49_26_AM_gjbrxs',
    'mini_truck': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_51_59_AM_jzd119',
    'tata_ace': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_51_59_AM_jzd119',
    'pickup_van': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_54_02_AM_hicx7s',
    'pickup_truck': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_54_02_AM_hicx7s',
    'bolero': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_54_02_AM_hicx7s',
    'tempo_407': 'https://res.cloudinary.com/dg5ct7fys/image/upload/f_auto,q_auto/ChatGPT_Image_Apr_17_2026_11_54_02_AM_hicx7s',
    'carpool': 'https://res.cloudinary.com/dg5ct7fys/image/upload/v1780038580/ChatGPT_Image_May_29_2026_12_39_20_PM_s8j1bs.png',
    'outstation': 'https://res.cloudinary.com/dg5ct7fys/image/upload/v1780038697/ChatGPT_Image_May_29_2026_12_41_11_PM_xoynqv.png',
    'delivery': 'https://res.cloudinary.com/kits/image/upload/q_auto/f_auto/v1775367404/be5b86c2-7a8a-4dbd-ad33-e8da2b627d5e_vurdrg.png',
  };

  /// PRIORITY 3: Local SVG fallback (emergency only, network failure).
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
    'pickup_truck': 'assets/vehicles/parcel_van.svg',
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
    if (n.contains('premium') || n.contains('prime')) return 'premium';
    if (n.contains('pickup van') || n.contains('pickup_truck') || n.contains('pickup')) return 'pickup_van';
    if (n.contains('mini truck') || n.contains('tata ace') || n.contains('tata_ace')) return 'tata_ace';
    if (n.contains('bolero')) return 'bolero';
    if (n.contains('tempo') || n.contains('407')) return 'tempo_407';
    if (n.contains('parcel bike') || n.contains('bike parcel') || n.contains('bike_parcel')) return 'parcel_bike';
    if (n.contains('parcel auto') || n.contains('auto parcel') || n.contains('auto_parcel')) return 'parcel_auto';
    if (n.contains('parcel') || n.contains('delivery')) return 'parcel_bike';
    if (n.contains('carpool') || n.contains('pool') || n.contains('share')) return 'carpool';
    if (n.contains('outstation') || n.contains('intercity')) return 'outstation';
    if (n.contains('suv') || n.contains('xl')) return 'suv';
    if (n.contains('sedan')) return 'sedan';
    if (n.contains('mini')) return 'mini_car';
    if (n.contains('cab') || n.contains('car')) return 'cab';
    if (n.contains('auto')) return 'auto';
    if (n.contains('bike')) return 'bike';
    return n.replaceAll(' ', '_');
  }

  /// Resolve display URL: explicit networkUrl → admin icon → canonical PNG.
  static String? resolveDisplayUrl({
    required String nameOrKey,
    String? adminIcon,
    String? networkUrl,
  }) {
    final explicit = networkUrl?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final icon = adminIcon?.trim() ?? '';
    if (icon.startsWith('http://') || icon.startsWith('https://')) return icon;
    if (icon.startsWith('/')) return '${ApiConfig.baseUrl}$icon';

    final key = normalizeKey(nameOrKey);
    return pngByKey[key];
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

  static String? local3DPngPathFor(String raw) {
    final key = normalizeKey(raw);
    return localPng3D[key] ?? localPng3D[raw.toLowerCase()];
  }

  @override
  Widget build(BuildContext context) {
    // PRIORITY 1: Check for local 3D PNG first (premium consistent display)
    final local3D = local3DPngPathFor(vehicleKey);
    if (local3D != null) {
      return Image.asset(
        local3D,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _networkOrFallback(),
      );
    }

    // PRIORITY 2: Network URL (explicit, admin icon, or CDN)
    return _networkOrFallback();
  }

  Widget _networkOrFallback() {
    final url = resolveDisplayUrl(
      nameOrKey: vehicleKey,
      adminIcon: adminIcon,
      networkUrl: networkUrl,
    );
    if (url != null) {
      if (url.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(
          url,
          width: width,
          height: height,
          fit: fit,
          placeholderBuilder: (_) => _local(),
        );
      }
      return Image.network(
        url,
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
    return Icon(iconFor(vehicleKey), size: size * 0.72, color: tint ?? JT.primary);
  }
}
