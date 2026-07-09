import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../widgets/jago_map_markers.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/analytics_service.dart';
import '../../services/api_retry.dart';
import '../../services/auth_service.dart';
import '../../services/booking_trace.dart';
import '../../services/vehicle_status_service.dart';
import '../../widgets/vehicle_artwork.dart';
import '../tracking/tracking_screen.dart';
import 'ride_for_whom_screen.dart';

class BookingScreen extends StatefulWidget {
  final String pickup;
  final String destination;
  final double pickupLat, pickupLng, destLat, destLng;
  final String? vehicleCategoryId;
  final String? vehicleCategoryName;
  final String? category; // 'ride' | 'parcel' | 'pool'
  const BookingScreen({
    super.key,
    required this.pickup,
    required this.destination,
    this.pickupLat = 17.3850, this.pickupLng = 78.4867,
    this.destLat = 0, this.destLng = 0,
    this.vehicleCategoryId,
    this.vehicleCategoryName,
    this.category,
  });
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> with TickerProviderStateMixin {
  final JagoMapController _mapController = JagoMapController();
  bool _loading = false;
  bool _estimating = true;
  List<Map<String, dynamic>> _allFares = [];
  List<Map<String, dynamic>> _vehicleCategoriesCache = [];
  int _selectedFareIndex = 0;
  String _paymentMethod = 'cash';
  double _walletBalance = 0;
  final TextEditingController _promoCtrl = TextEditingController();
  final VehicleStatusService _vehicleStatusService = VehicleStatusService();
  String? _appliedPromo;
  double _promoDiscount = 0;
  bool _promoLoading = false;
  String? _promoError;
  Timer? _debounce;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late Razorpay _razorpay;

  bool _bookForSomeone = false;
  final _passengerNameCtrl = TextEditingController();
  final _passengerPhoneCtrl = TextEditingController();
  final _receiverNameCtrl = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _popularForPickup = false;
  
  Set<Polyline> _polylines = {};
  double _routedDistanceKm = 0.0;

  // Populated dynamically from /api/app/popular-locations; static data used as fallback
  List<Map<String, dynamic>> _popularLocations = const [
    {'name': 'Benz Circle', 'lat': 16.5062, 'lng': 80.6480},
    {'name': 'Vijayawada Railway Station', 'lat': 16.5175, 'lng': 80.6400},
    {'name': 'Vijayawada Bus Stand', 'lat': 16.5179, 'lng': 80.6238},
    {'name': 'Balaji Bus Stand', 'lat': 16.5106, 'lng': 80.6248},
    {'name': 'Kanaka Durga Temple', 'lat': 16.5176, 'lng': 80.6121},
    {'name': 'Gannavaram Airport', 'lat': 16.5304, 'lng': 80.7968},
    {'name': 'Governorpet', 'lat': 16.5135, 'lng': 80.6346},
    {'name': 'Patamata', 'lat': 16.4883, 'lng': 80.6681},
  ];

  static const Color _blue = JT.primary;
  static const Color _green = JT.success;

  LatLng get _pickupLatLng => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _destLatLng => widget.destLat != 0 && widget.destLng != 0
    ? LatLng(widget.destLat, widget.destLng)
    : LatLng(widget.pickupLat + 0.02, widget.pickupLng + 0.02);

  Map<String, dynamic>? get _fare => _allFares.isNotEmpty ? _allFares[_selectedFareIndex] : null;

  String get _vehicleName => _fareVehicleName(_fare ?? const <String, dynamic>{});

  String _fareVehicleName(Map<String, dynamic> fare) {
    return fare['vehicleCategoryName']?.toString() ??
        fare['vehicleName']?.toString() ??
        fare['name']?.toString() ??
        'Bike';
  }

  List<MapEntry<int, Map<String, dynamic>>> _visibleFareEntries(
    Map<String, VehicleStatus> statuses,
  ) {
    return _allFares.asMap().entries.where((entry) {
      final name = _fareVehicleName(entry.value);
      return VehicleStatusService.isActive(statuses, name);
    }).toList();
  }

  void _syncSelectedFareToVisible(Map<String, VehicleStatus> statuses) {
    if (_allFares.isEmpty) return;
    final selectedName = _fareVehicleName(_allFares[_selectedFareIndex]);
    if (VehicleStatusService.isActive(statuses, selectedName)) return;
    final visible = _visibleFareEntries(statuses);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || visible.isEmpty) return;
      setState(() => _selectedFareIndex = visible.first.key);
    });
  }

  static IconData _iconForVehicle(String name) {
    final n = name.toLowerCase();
    if (n.contains('pickup van') || n.contains('pickup')) return Icons.fire_truck_rounded;
    if (n.contains('mini truck') || n.contains('tata ace') || n.contains('mini cargo')) return Icons.local_shipping_rounded;
    if (n.contains('parcel bike') || n.contains('bike parcel') || n.contains('parcel auto')) return Icons.delivery_dining_rounded;
    if (n.contains('parcel')) return Icons.inventory_2_rounded;
    if (n.contains('bike')) return Icons.electric_bike_rounded;
    if (n.contains('auto')) return Icons.electric_rickshaw_rounded;
    if (n.contains('cargo truck')) return Icons.fire_truck_rounded;
    if (n.contains('cargo')) return Icons.local_shipping_rounded;
    if (n.contains('suv')) return Icons.directions_car_filled_rounded;
    if (n.contains('car')) return Icons.directions_car_filled_rounded;
    return Icons.directions_car_filled_rounded;
  }

  static String _emojiForVehicle(String name) {
    final n = name.toLowerCase();
    // Parcel vehicles — MUST show goods/delivery vehicles, NOT passenger
    if (n.contains('pickup van') || n.contains('pickup')) return '🚛';     // Heavy pickup van
    if (n.contains('mini truck') || n.contains('tata ace')) return '🚐';   // Mini cargo truck
    if (n.contains('parcel bike') || n.contains('bike parcel')) return '🛵'; // Delivery bike
    if (n.contains('parcel auto')) return '🛻';  // ✅ GOODS AUTO — pickup/cargo truck feel (not passenger auto 🛺, not bus)
    if (n.contains('parcel')) return '🚐';       // Generic parcel vehicle
    // Ride vehicles
    if (n.contains('bike')) return '🏍️';
    if (n.contains('auto')) return '🛺';         // Passenger auto only for ride
    if (n.contains('cargo truck')) return '🚛';
    if (n.contains('cargo')) return '🚐';
    if (n.contains('suv')) return '🚙';
    if (n.contains('car')) return '🚗';
    return '🚗';
  }

  // Rule 3: Parcel Auto subtitle must clearly say GOODS ONLY
  static String _subtitleForVehicle(String name) {
    final n = name.toLowerCase();
    if (n.contains('parcel auto')) return 'Goods Carrier Auto · CARGO ONLY';
    if (n.contains('parcel bike')) return 'Delivery bike · Up to 10 kg';
    if (n.contains('mini truck') || n.contains('tata ace')) return 'Mini cargo truck · Up to 500 kg';
    if (n.contains('pickup van') || n.contains('pickup')) return 'Large pickup van · Up to 2000 kg';
    if (n.contains('parcel')) return 'Parcel delivery';
    if (n.contains('bike')) return '1 passenger · Fastest';
    if (n.contains('auto')) return 'Up to 3 passengers';
    if (n.contains('suv')) return 'Up to 6 passengers · AC';
    if (n.contains('car')) return 'Up to 4 passengers · AC';
    return '';
  }

  // Rule 4: Returns true if vehicle should be HIDDEN
  static bool _shouldHideVehicle(String name) {
    final n = name.toLowerCase();
    
    // Whitelist only requested categories: bike, auto, cab, premium
    // Relaxed contains checks to avoid hiding valid variations (e.g. "Bike - Fast")
    if (n.contains('bike')) return false;
    if (n.contains('auto')) return false;
    if (n.contains('cab')) return false;
    if (n.contains('premium')) return false;
    if (n.contains('sedan')) return false;
    if (n.contains('suv') || n.contains(' xl')) return false;
    if (n.contains('mini')) return false;
    if (n.contains('car')) return false;

    // Hide everything else (Parcel, Pool, etc.)
    return true;
  }

  static Color _accentForVehicle(String name) {
    return const Color(0xFF2C95F1); // Unified Premium Indigo
  }

  // ── Vehicle artwork via VehicleArtwork (admin icon + app PNG + local SVG) ──

  static String? _vehicleImageKey(String name) => VehicleArtwork.normalizeKey(name);

  Widget _buildVehicleArtwork(String name, Color accent, bool isSelected, {double size = 96, String? adminIcon}) {
    final icon = _iconForVehicle(name);
    final isParcel = widget.category == 'parcel';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size, height: size,
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
          child: VehicleArtwork(
            vehicleKey: name,
            adminIcon: adminIcon,
            width: size * 0.72,
            height: size * 0.72,
            tint: accent.withValues(alpha: isSelected ? 0.85 : 0.60),
          ),
        ),
        Positioned(
          bottom: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? accent : accent.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isParcel ? 'DELIVERY' : 'RIDE',
              style: const TextStyle(color: Colors.white, fontSize: 7,
                fontWeight: FontWeight.w500, letterSpacing: 0.5),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildVehicleHero() {
    if (_allFares.isEmpty) return const SizedBox.shrink();
    final fare = _allFares[_selectedFareIndex];
    final name = fare['vehicleCategoryName']?.toString() ?? fare['name']?.toString() ?? 'Bike';
    final emoji = _emojiForVehicle(name);
    final accent = _accentForVehicle(name);
    final fareVal = (fare['estimatedFare'] ?? 0).toDouble();
    final rawMin = (fare['fareMin'] ?? (fareVal * 0.95)).toDouble();
    final rawMax = (fare['fareMax'] ?? (fareVal * 1.05)).toDouble();
    final displayMin = (rawMin - _promoDiscount).clamp(0.0, double.infinity);
    final displayMax = (rawMax - _promoDiscount).clamp(0.0, double.infinity);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Container(
        key: ValueKey('hero_$name'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent.withValues(alpha: 0.75)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8)),
              child: Text('SELECTED', style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 1.5)),
            ),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('₹${displayMin.floor()} – ₹${displayMax.ceil()}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400)),
            Text('estimated fare', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11)),
          ])),
          // Real vehicle image — emoji fallback if network fails
          Builder(builder: (_) {
            final adminIcon = fare['vehicleIcon']?.toString() ?? fare['icon']?.toString();
            return SizedBox(
              width: 100, height: 80,
              child: VehicleArtwork(
                vehicleKey: name,
                adminIcon: adminIcon,
                width: 100,
                height: 80,
                tint: Colors.white.withValues(alpha: 0.92),
              ),
            );
          }),
        ]),
      ),
    );
  }

  /// Parse "~5 min" / "5 min" / "5-8 min" → arrival minutes number
  static int _etaMins(String timeStr) {
    final match = RegExp(r'(\d+)').firstMatch(timeStr);
    return match != null ? int.tryParse(match.group(1) ?? '5') ?? 5 : 5;
  }

  /// "Drop 6:14 pm" style string from eta
  static String _dropTimeStr(String timeStr) {
    final mins = _etaMins(timeStr);
    final dropTime = DateTime.now().add(Duration(minutes: mins + 10));
    final h = dropTime.hour > 12 ? dropTime.hour - 12 : (dropTime.hour == 0 ? 12 : dropTime.hour);
    final m = dropTime.minute.toString().padLeft(2, '0');
    final ampm = dropTime.hour >= 12 ? 'pm' : 'am';
    return '$h:$m $ampm';
  }

  static String _capacityForVehicle(String name) {
    final n = name.toLowerCase();
    if (n.contains('pickup van') || n.contains('pickup')) return 'Up to 2000 kg';
    if (n.contains('mini truck') || n.contains('tata ace')) return 'Up to 500 kg';
    if (n.contains('parcel bike') || n.contains('bike parcel')) return 'Up to 10 kg';
    if (n.contains('parcel auto')) return 'Up to 50 kg';
    if (n.contains('parcel')) return 'Package delivery';
    if (n.contains('suv')) return '6 seats';
    if (n.contains('car')) return '4 seats';
    if (n.contains('auto')) return '3 seats';
    if (n.contains('bike')) return '1 rider';
    if (n.contains('cargo truck')) return 'Up to 1000 kg';
    if (n.contains('cargo')) return 'Up to 500 kg';
    return '';
  }

  double get _distanceKm {
    if (_routedDistanceKm > 0) return _routedDistanceKm;
    if (widget.destLat == 0 && widget.destLng == 0) return 3.0;
    // Haversine formula for accurate distance calculation
    const double earthRadius = 6371.0;
    final double lat1 = widget.pickupLat * pi / 180;
    final double lat2 = widget.destLat * pi / 180;
    final double dlat = (widget.destLat - widget.pickupLat) * pi / 180;
    final double dlng = (widget.destLng - widget.pickupLng) * pi / 180;
    final double a = sin(dlat / 2) * sin(dlat / 2) +
        cos(lat1) * cos(lat2) * sin(dlng / 2) * sin(dlng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    // Road distance is typically 1.3x aerial distance
    return (earthRadius * c * 1.3).clamp(0.5, 200.0);
  }

  String _shortLocation(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;
    return v.split(',').first.trim();
  }

  void _quickSelectPopular(Map<String, dynamic> location) {
    final name = (location['name'] ?? '').toString();
    final lat = (location['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (location['lng'] as num?)?.toDouble() ?? 0.0;
    if (name.isEmpty || lat == 0 || lng == 0) return;

    final next = BookingScreen(
      pickup: _popularForPickup ? name : widget.pickup,
      destination: _popularForPickup ? widget.destination : name,
      pickupLat: _popularForPickup ? lat : widget.pickupLat,
      pickupLng: _popularForPickup ? lng : widget.pickupLng,
      destLat: _popularForPickup ? widget.destLat : lat,
      destLng: _popularForPickup ? widget.destLng : lng,
      vehicleCategoryId: widget.vehicleCategoryId,
      vehicleCategoryName: widget.vehicleCategoryName,
      category: widget.category,
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  double get _finalFare {
    final f = (_fare?['estimatedFare'] ?? 0).toDouble();
    return (f - _promoDiscount).clamp(0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadVehicleCategories();
    if (!mounted) return;
    _estimateFare();
    _fetchWallet();
    _fetchPopularLocations();
    _fetchRoutePolyline();
  }

  Future<void> _loadVehicleCategories() async {
    try {
      final headers = await AuthService.getHeaders();
      // Production: /api/app/vehicle-categories returns [] when is_active=false.
      // home-data includes all categories with real UUIDs — required for booking.
      final homeRes = await http
          .get(Uri.parse(ApiConfig.customerHomeData), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (homeRes.statusCode == 200) {
        final data = jsonDecode(homeRes.body);
        final list = data is Map ? data['vehicleCategories'] as List? : null;
        if (list != null && list.isNotEmpty) {
          _vehicleCategoriesCache = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          BookingTrace.step('categories_loaded', {
            'source': 'home-data',
            'count': _vehicleCategoriesCache.length,
          });
          return;
        }
      }
      final type = widget.category ?? 'ride';
      final uri = Uri.parse(ApiConfig.vehicleCategories).replace(
        queryParameters: type.isNotEmpty ? {'type': type} : null,
      );
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final list = data is List
          ? data
          : (data is Map ? data['categories'] as List? : null);
      if (list == null) return;
      _vehicleCategoriesCache = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      BookingTrace.step('categories_loaded', {
        'source': 'vehicle-categories',
        'count': _vehicleCategoriesCache.length,
      });
    } catch (e, st) {
      BookingTrace.error('loadVehicleCategories', e, st);
    }
  }

  String? _categoryIdForName(String name) {
    if (_vehicleCategoriesCache.isEmpty) return null;
    final key = _bookingVehicleKey(name);
    for (final cat in _vehicleCategoriesCache) {
      final catName = (cat['name'] ?? '').toString();
      if (_bookingVehicleKey(catName) == key) {
        final id = cat['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    final lower = name.toLowerCase();
    for (final cat in _vehicleCategoriesCache) {
      final catName = (cat['name'] ?? '').toString().toLowerCase();
      if (catName == lower ||
          catName.contains(key) ||
          (key.isNotEmpty && lower.contains(catName.split(' ').first))) {
        final id = cat['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Map<String, dynamic> _normalizeFare(Map<String, dynamic> fare) {
    final normalized = Map<String, dynamic>.from(fare);
    final name = _fareVehicleName(normalized);
    normalized['vehicleCategoryName'] = name;
    normalized['vehicleName'] = name;
    final existingId = normalized['vehicleCategoryId']?.toString() ??
        normalized['vehicle_category_id']?.toString() ??
        normalized['id']?.toString();
    if (existingId != null && existingId.isNotEmpty) {
      normalized['vehicleCategoryId'] = existingId;
    } else {
      final resolved = _categoryIdForName(name);
      if (resolved != null) normalized['vehicleCategoryId'] = resolved;
    }
    return normalized;
  }

  void _hydrateAllFares() {
    _allFares = _allFares.map(_normalizeFare).toList();
  }

  Future<void> _fetchPopularLocations() async {
    try {
      final uri = Uri.parse(ApiConfig.popularLocations).replace(
        queryParameters: {'lat': widget.pickupLat.toString(), 'lng': widget.pickupLng.toString()},
      );
      final r = await http.get(uri).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        if (data is! Map) return;
        final rawList = data['locations'];
        final list = rawList is List ? rawList.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
        if (mounted && list.isNotEmpty) {
          setState(() => _popularLocations = list.map((l) => {
            'name': l['name']?.toString() ?? '',
            'lat': (l['lat'] as num?)?.toDouble() ?? 0.0,
            'lng': (l['lng'] as num?)?.toDouble() ?? 0.0,
          }).toList());
        }
      }
    } catch (_) { /* keep static fallback */ }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pulseController.dispose();
    _promoCtrl.dispose();
    _razorpay.clear();
    _passengerNameCtrl.dispose();
    _passengerPhoneCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _noteCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchWallet() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.wallet),
        headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _walletBalance = (data['balance'] ?? 0).toDouble());
      }
    } catch (_) {}
  }

  void _onCouponChanged(String value) {
    // Clear stale error/discount on code change
    if (_promoError != null) setState(() => _promoError = null);
    _debounce?.cancel();
    // Only auto-apply when user has typed a plausible code (≥4 chars)
    if (value.trim().length >= 4) {
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (_promoCtrl.text.trim().isNotEmpty) _applyPromo();
      });
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _promoLoading = true; _promoError = null; });
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(Uri.parse(ApiConfig.applyCoupon),
        headers: headers,
        body: jsonEncode({'code': code, 'fareAmount': (_fare?['estimatedFare'] ?? 0).toDouble()}))
        .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          setState(() {
            _appliedPromo = code;
            _promoDiscount = double.tryParse(data['discount']?.toString() ?? '0') ?? 0;
            _promoLoading = false;
          });
        } catch (_) {
          setState(() { _promoError = 'Invalid response from server'; _promoLoading = false; });
        }
      } else {
        try {
          final data = jsonDecode(res.body);
          setState(() { _promoError = data['message'] ?? 'Invalid code'; _promoLoading = false; });
        } catch (_) {
          setState(() { _promoError = 'Invalid coupon code'; _promoLoading = false; });
        }
      }
    } catch (_) {
      setState(() { _promoError = 'Network error'; _promoLoading = false; });
    }
  }

  Future<void> _estimateFare() async {
    setState(() => _estimating = true);
    try {
      final headers = await AuthService.getHeaders();
      final body = <String, dynamic>{
        'pickupLat': widget.pickupLat, 'pickupLng': widget.pickupLng,
        'destLat': widget.destLat, 'destLng': widget.destLng,
        'distanceKm': _distanceKm,
      };
      if (widget.vehicleCategoryId != null) body['vehicleCategoryId'] = widget.vehicleCategoryId;
      if (widget.category != null) body['category'] = widget.category;
      final res = await http.post(Uri.parse(ApiConfig.estimateFare),
        headers: headers,
        body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawFares = data['fares'];
        final fares = rawFares is List ? rawFares.whereType<Map<String, dynamic>>().toList() : null;
        if (fares != null && fares.isNotEmpty) {
          setState(() {
            var filtered = fares.map(_normalizeFare).toList();
            final cat = widget.category ?? 'ride';
            if (cat == 'parcel') {
              filtered = filtered.where((f) {
                final vname = _fareVehicleName(f).toLowerCase();
                final vtype = (f['type'] ?? f['vehicleType'] ?? '').toString().toLowerCase();
                return vtype == 'parcel' || vname.contains('parcel') ||
                    vname.contains('truck') || vname.contains('van') ||
                    vname.contains('tata') || vname.contains('mini');
              }).toList();
            } else {
              filtered = filtered.where((f) {
                final vname = _fareVehicleName(f).toLowerCase();
                final vtype = (f['type'] ?? f['vehicleType'] ?? '').toString().toLowerCase();
                if (vtype == 'parcel' || vname.contains('parcel') || vname.contains('truck') || vname.contains('cargo')) return false;
                if (_shouldHideVehicle(vname)) return false;
                return true;
              }).toList();
            }
            _allFares = filtered;

            final serverHasRealFares = _allFares.any(
              (f) => _vehicleCategoryId(f, includeWidgetFallback: false) != null,
            );
            if (widget.category != 'parcel' && !serverHasRealFares) {
              final fallbacks = _buildFallbackFares();
              for (var fb in fallbacks) {
                final fbName = fb['vehicleCategoryName'].toString();
                if (!_allFares.any((f) {
                  final name = _fareVehicleName(f).toLowerCase();
                  return name.contains(fbName.split(' ').first.toLowerCase());
                })) {
                  _allFares.add(fb);
                }
              }
            }

            if (_allFares.isEmpty) _allFares = _buildFallbackFares();
            _hydrateAllFares();
            if (widget.vehicleCategoryId != null || widget.vehicleCategoryName != null) {
              final targetName = (widget.vehicleCategoryName ?? '').toLowerCase();
              final idx = _allFares.indexWhere((f) {
                final fName = _fareVehicleName(f).toLowerCase();
                final fId = f['vehicleCategoryId']?.toString() ?? f['id']?.toString();
                return fId == widget.vehicleCategoryId ||
                       (targetName.isNotEmpty && fName.contains(targetName));
              });
              if (idx >= 0) _selectedFareIndex = idx;
            }
          });
        } else {
          if (mounted) setState(() {
            _allFares = _buildFallbackFares();
            _hydrateAllFares();
          });
        }
      } else {
        if (mounted) setState(() {
          _allFares = _buildFallbackFares();
          _hydrateAllFares();
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _allFares = _buildFallbackFares();
        _hydrateAllFares();
      });
    }
    if (mounted) setState(() => _estimating = false);
  }

  /// Builds client-side fare estimates (Bike/Auto/Car) when the server returns
  /// no fares. Formula: Total = Base + (Distance × Per-KM Rate) + 5% GST.
  List<Map<String, dynamic>> _buildFallbackFares() {
    final dist = _distanceKm;
    Map<String, dynamic> make(
        String name, double base, double perKm, double minFareVal, int eta) {
      final raw = (base + dist * perKm).clamp(minFareVal, double.infinity);
      final gst = double.parse((raw * 0.05).toStringAsFixed(2));
      final grandTotal = double.parse((raw + gst).toStringAsFixed(2));
      final categoryId = _categoryIdForName(name);
      return {
        'vehicleCategoryId': categoryId,
        'vehicleCategoryName': name,
        'vehicleName': name,
        'baseFare': base,
        'farePerKm': perKm,
        'billableKm': dist,
        'distanceFare': double.parse((dist * perKm).toStringAsFixed(2)),
        'timeFare': 0.0,
        'subtotal': double.parse(raw.toStringAsFixed(2)),
        'gst': gst,
        'estimatedFare': grandTotal,
        'fareMin': (grandTotal * 0.95).floor(),
        'fareMax': (grandTotal * 1.05).ceil(),
        'minimumFare': minFareVal,
        'cancellationFee': 10.0,
        'waitingChargePerMin': 0.0,
        'isNightCharge': false,
        'nightMultiplier': 1.0,
        'helperCharge': 0.0,
        'estimatedTime': '$eta min',
      };
    }
    // Parcel-specific vehicles — never mix with ride vehicles
    if (widget.category == 'parcel') {
      return [
        make('Parcel Bike',  20,  8,  25, (dist * 4).ceil()),
        make('Parcel Auto',  30, 10,  35, (dist * 4).ceil()),
        make('Mini Truck',  100, 25, 120, (dist * 5).ceil()),
        make('Pickup Van',  150, 35, 180, (dist * 5).ceil()),
      ];
    }
    // Ride vehicles (default)
    return [
      make('Bike', 25, 10, 28, (dist * 3).ceil()),
      make('Auto', 35, 13, 40, (dist * 3.5).ceil()),
      make('Cab',  50, 16, 60, (dist * 4).ceil()),
      make('Premium Cab', 70, 20, 80, (dist * 4).ceil()),
    ];
  }

  String? _vehicleCategoryId(
    Map<String, dynamic>? fare, {
    bool includeWidgetFallback = true,
  }) {
    final id = fare?['vehicleCategoryId']?.toString() ??
        fare?['vehicle_category_id']?.toString() ??
        fare?['id']?.toString() ??
        (includeWidgetFallback ? widget.vehicleCategoryId : null);
    return id == null || id.isEmpty ? null : id;
  }

  String _bookingVehicleKey(String name) {
    final value = name.toLowerCase();
    if (value.contains('parcel bike')) return 'parcel_bike';
    if (value.contains('parcel auto')) return 'parcel_auto';
    if (value.contains('mini truck') || value.contains('tata ace')) return 'mini_truck';
    if (value.contains('pickup van') || value.contains('pickup')) return 'pickup_van';
    if (value.contains('premium')) return 'premium';
    if (value.contains('bike')) return 'bike';
    if (value.contains('auto')) return 'auto';
    if (value.contains('cab') || value.contains('car') || value.contains('sedan')) return 'cab';
    return value.trim();
  }

  Future<Map<String, dynamic>?> _resolveServerFare(Map<String, dynamic>? selectedFare) async {
    final selectedName = _fareVehicleName(selectedFare ?? const <String, dynamic>{});
    final selectedKey = _bookingVehicleKey(selectedName);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse(ApiConfig.estimateFare),
        headers: headers,
        body: jsonEncode({
          'pickupLat': widget.pickupLat,
          'pickupLng': widget.pickupLng,
          'destLat': widget.destLat,
          'destLng': widget.destLng,
          'distanceKm': _distanceKm,
          if (widget.category != null) 'category': widget.category,
        }),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final rawFares = data['fares'];
      if (rawFares is! List) return null;
      for (final item in rawFares) {
        if (item is! Map) continue;
        final fare = _normalizeFare(Map<String, dynamic>.from(item));
        if (_bookingVehicleKey(_fareVehicleName(fare)) == selectedKey) return fare;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _resolveVehicleCategoryId(Map<String, dynamic>? selectedFare) async {
    var vcId = _vehicleCategoryId(selectedFare);
    if (vcId != null) return vcId;

    final name = _fareVehicleName(selectedFare ?? const <String, dynamic>{});
    vcId = _categoryIdForName(name);
    if (vcId != null) return vcId;

    final resolvedFare = await _resolveServerFare(selectedFare);
    if (resolvedFare != null) {
      vcId = _vehicleCategoryId(resolvedFare);
      if (vcId != null) {
        if (mounted && selectedFare != null) {
          final idx = _allFares.indexWhere((f) => identical(f, selectedFare));
          final targetIdx = idx >= 0 ? idx : _selectedFareIndex;
          if (targetIdx >= 0 && targetIdx < _allFares.length) {
            setState(() => _allFares[targetIdx] = resolvedFare);
          }
        }
        return vcId;
      }
    }

    if (_vehicleCategoriesCache.isEmpty) await _loadVehicleCategories();
    return _categoryIdForName(name);
  }

  Future<void> _confirmBooking({String? razorpayPaymentId}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      var selectedFare = _fare;
      BookingTrace.step('confirm_start', {
        'vehicle': _fareVehicleName(selectedFare ?? const {}),
        'payment': _paymentMethod,
        'distanceKm': _distanceKm,
      });
      var vcId = await _resolveVehicleCategoryId(selectedFare);
      BookingTrace.step('category_resolved', {'vehicleCategoryId': vcId ?? 'null'});
      if (vcId != null && selectedFare != null) {
        selectedFare = _normalizeFare(selectedFare);
        if (mounted && _selectedFareIndex < _allFares.length) {
          setState(() => _allFares[_selectedFareIndex] = selectedFare!);
        }
      }
      if (vcId == null) {
        final vehicleName = _fareVehicleName(selectedFare ?? const <String, dynamic>{});
        if (vehicleName.isEmpty) {
          if (mounted) setState(() => _loading = false);
          BookingTrace.error('confirm_abort', 'vehicleCategoryId unresolved');
          _showSnack('Could not refresh vehicle availability. Please try again.', error: true);
          return;
        }
        BookingTrace.step('category_deferred', {'vehicleName': vehicleName});
      }
      final selectedFareAmount =
          double.tryParse(selectedFare?['estimatedFare']?.toString() ?? '') ?? 0;
      final body = <String, dynamic>{
        'pickupAddress': widget.pickup,
        'destinationAddress': widget.destination,
        'pickupShortName': _shortLocation(widget.pickup),
        'destinationShortName': _shortLocation(widget.destination),
        'pickupLat': widget.pickupLat, 'pickupLng': widget.pickupLng,
        'destinationLat': widget.destLat, 'destinationLng': widget.destLng,
        'estimatedFare': (selectedFareAmount - _promoDiscount).clamp(0, double.infinity),
        'estimatedDistance': _distanceKm,
        'paymentMethod': _paymentMethod,
        if (_promoDiscount > 0) 'promoDiscount': _promoDiscount,
        if (_appliedPromo != null) 'couponCode': _appliedPromo,
        if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
        'ride_for': _bookForSomeone ? 'other' : 'self',
        if (_bookForSomeone) 'isForSomeoneElse': true,
        if (_bookForSomeone && _passengerNameCtrl.text.trim().isNotEmpty) ...{
          'passengerName': _passengerNameCtrl.text.trim(),
          'passenger_name': _passengerNameCtrl.text.trim(),
        },
        if (_bookForSomeone && _passengerPhoneCtrl.text.trim().isNotEmpty) ...{
          'passengerPhone': _passengerPhoneCtrl.text.trim(),
          'passenger_mobile': _passengerPhoneCtrl.text.trim(),
        },
        if (_bookForSomeone && _receiverNameCtrl.text.trim().isNotEmpty)
          'receiverName': _receiverNameCtrl.text.trim(),
        if (_bookForSomeone && _receiverPhoneCtrl.text.trim().isNotEmpty)
          'receiverPhone': _receiverPhoneCtrl.text.trim(),
        if (_bookForSomeone && _noteCtrl.text.trim().isNotEmpty)
          'note': _noteCtrl.text.trim(),
      };

      final vcName = _fareVehicleName(selectedFare ?? const <String, dynamic>{});
      if (vcId != null) body['vehicleCategoryId'] = vcId;
      if (vcName.isNotEmpty) {
        body['vehicleCategoryName'] = vcName;
        body['vehicleCategory'] = vcName;
        body['vehicleName'] = vcName;
      }
      BookingTrace.api('POST', ApiConfig.bookRide, body: jsonEncode(body));
      final idempotencyKey = generateIdempotencyKey();
      final res = await apiRetry(() => http.post(Uri.parse(ApiConfig.bookRide),
        headers: {...headers, 'Idempotency-Key': idempotencyKey},
        body: jsonEncode(body)).timeout(const Duration(seconds: 15)));
      BookingTrace.api('POST', ApiConfig.bookRide, status: res.statusCode, body: res.body);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tripId = data['trip']?['id']?.toString() ?? '';
        debugPrint(
            '[DISPATCH] Ride request created tripId=$tripId status=${data['trip']?['currentStatus'] ?? data['trip']?['status']} vehicleCategoryId=$vcId');
        AnalyticsService().logRideBooked(
          rideId: tripId,
          fare: (_fare?['estimatedFare'] ?? 0).toDouble(),
          rideType: vcName ?? 'standard',
        );
        if (!mounted) return;
        if (tripId.isEmpty) {
          _showSnack('Booking confirmed but could not track trip. Please check My Trips.', error: false);
          setState(() => _loading = false);
          Navigator.pop(context);
          return;
        }
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => TrackingScreen(tripId: tripId)));
      } else if (res.statusCode == 409) {
        if (!mounted) return;
        try {
          final err = jsonDecode(res.body) as Map<String, dynamic>;
          final tripId = err['tripId']?.toString() ?? err['trip']?['id']?.toString() ?? '';
          if (tripId.isNotEmpty) {
            BookingTrace.step('confirm_existing_trip', {'tripId': tripId});
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (_) => TrackingScreen(tripId: tripId)));
            return;
          }
          _showSnack(err['message']?.toString() ?? 'Active trip exists', error: true);
        } catch (_) {
          _showSnack('Active trip exists. Check My Trips.', error: true);
        }
      } else {
        debugPrint(
            '[DISPATCH] Ride request creation failed status=${res.statusCode} body=${res.body}');
        if (!mounted) return;
        try {
          final err = jsonDecode(res.body);
          _showSnack(err['message'] ?? 'Booking failed', error: true);
        } catch (_) {
          _showSnack('Booking failed. Please try again.', error: true);
        }
      }
    } catch (e) {
      debugPrint('[DISPATCH] Ride request creation threw: $e');
      if (!mounted) return;
      _showSnack('Network error. Try again.', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Offers Google Maps navigation to pickup location after booking is confirmed.
  /// Shows a premium bottom sheet with "Navigate" and "Skip" options.
  Future<void> _offerNavigateToPickup() async {
    if (!mounted) return;
    final pickupLat = widget.pickupLat;
    final pickupLng = widget.pickupLng;
    final pickupAddr = widget.pickup;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF15803D)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF16A34A).withValues(alpha: 0.35), blurRadius: 16)],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text('Ride Booked! 🎉',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500,
              color: JT.textPrimary)),
          const SizedBox(height: 8),
          Text('Navigate to pickup location?',
            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Text(pickupAddr,
            style: const TextStyle(fontSize: 13, color: JT.primary, fontWeight: FontWeight.w400),
            maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(child: Text('Skip',
                    style: TextStyle(fontWeight: FontWeight.w500,
                      color: Colors.grey[700]))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  // Try Google Maps first, fallback to geo: URI
                  final gmUrl = 'google.navigation:q=$pickupLat,$pickupLng&mode=d';
                  final geoUrl = 'geo:$pickupLat,$pickupLng?q=$pickupLat,$pickupLng($pickupAddr)';
                  final mapsUrl = 'https://maps.google.com/?daddr=$pickupLat,$pickupLng&directionsmode=driving';
                  if (await canLaunchUrl(Uri.parse(gmUrl))) {
                    await launchUrl(Uri.parse(gmUrl));
                  } else if (await canLaunchUrl(Uri.parse(geoUrl))) {
                    await launchUrl(Uri.parse(geoUrl));
                  } else {
                    await launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [JT.primary, Color(0xFF1244A2)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: JT.primary.withValues(alpha: 0.35), blurRadius: 12)],
                  ),
                  child: const Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Navigate Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
                  ])),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _goToRideForWhomScreen() async {
    try {
      final statuses = await _vehicleStatusService.watchVehicleStatuses().first;
      if (!VehicleStatusService.isActive(statuses, _vehicleName)) {
        _showSnack('$_vehicleName is temporarily unavailable by admin.', error: true);
        return;
      }
    } catch (_) {}
    final result = await Navigator.push(context, MaterialPageRoute(
      builder: (_) => RideForWhomScreen(vehicleName: _vehicleName),
    ));
    if (result != null && result is Map) {
      setState(() {
        _bookForSomeone = result['isForSomeone'] == true;
        if (_bookForSomeone) {
          _passengerNameCtrl.text = result['name'] ?? '';
          _passengerPhoneCtrl.text = result['phone'] ?? '';
          _noteCtrl.text = result['note'] ?? '';
        } else {
          _passengerNameCtrl.clear();
          _passengerPhoneCtrl.clear();
          _noteCtrl.clear();
        }
      });
      _handleOnConfirm();
    }
  }

  Future<void> _handleOnConfirm() async {
    try {
      final statuses = await _vehicleStatusService.watchVehicleStatuses().first;
      if (!VehicleStatusService.isActive(statuses, _vehicleName)) {
        _showSnack('$_vehicleName is temporarily unavailable. Please try another vehicle.', error: true);
        return;
      }
    } catch (_) {}
    if (_paymentMethod == 'upi') {
      await _startRazorpayRidePayment();
    } else {
      if (_paymentMethod == 'wallet') {
        final fare = _finalFare;
        if (_walletBalance < fare) {
          _showSnack('Insufficient wallet balance. Please recharge.', error: true);
          return;
        }
      }
      await _confirmBooking();
    }
  }

  Future<void> _startRazorpayRidePayment() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final fare = _finalFare;
      final res = await http.post(Uri.parse(ApiConfig.rideCreateOrder),
        headers: headers,
        body: jsonEncode({'amount': fare})).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        setState(() => _loading = false);
        try {
          final err = jsonDecode(res.body);
          _showSnack(err['message'] ?? 'Payment setup failed', error: true);
        } catch (_) {
          _showSnack('Payment setup failed. Try again.', error: true);
        }
        return;
      }
      final data = jsonDecode(res.body);
      final order = data['order'];
      final keyId = data['keyId'];
      if (order == null || keyId == null) {
        setState(() => _loading = false);
        _showSnack('Payment setup failed. Try again.', error: true);
        return;
      }
      final profileData = await AuthService.getProfile();
      final options = {
        'key': keyId,
        'amount': order['amount'],
        'currency': 'INR',
        'name': 'Jago Rides',
        'description': 'Ride to ${_shortLocation(widget.destination)}',
        'order_id': order['id'],
        'prefill': {
          'name': profileData?['fullName'] ?? '',
          'contact': profileData?['phone'] ?? '',
        },
        'theme': {'color': '#1E6DE5'},
      };
      _razorpay.open(options);
    } catch (_) {
      setState(() => _loading = false);
      _showSnack('Payment failed. Try again.', error: true);
    }
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final verifyRes = await http.post(Uri.parse(ApiConfig.rideVerifyPayment),
        headers: headers,
        body: jsonEncode({
          'razorpayOrderId': response.orderId,
          'razorpayPaymentId': response.paymentId,
          'razorpaySignature': response.signature,
          'amount': _finalFare,
        })).timeout(const Duration(seconds: 15));
      if (verifyRes.statusCode == 200) {
        await _confirmBooking(razorpayPaymentId: response.paymentId);
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
        _showSnack('Payment verification failed. Contact support.', error: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Payment verification failed.', error: true);
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    setState(() => _loading = false);
    _showSnack(response.message ?? 'Payment cancelled', error: true);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => _loading = false);
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: JT.buttonText)),
      backgroundColor: error ? JT.danger : JT.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> pts = [];
    int index = 0;
    int lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dLat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dLng;
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  Future<void> _fetchRoutePolyline() async {
    bool success = false;
    List<LatLng> points = [];
    double fetchedDistMeters = 0.0;

    // Attempt 1: OSRM Public Routing API (Highly reliable, no API key, returns distance)
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${widget.pickupLng},${widget.pickupLat};${widget.destLng},${widget.destLat}?overview=full&geometries=polyline'
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final encoded = route['geometry'];
          points = _decodePolyline(encoded);
          fetchedDistMeters = (route['distance'] as num).toDouble();
          success = points.isNotEmpty;
        }
      }
    } catch (_) {}

    // Attempt 2: Backend Navigation API (server-side — no client Maps REST key)
    if (!success) {
      try {
        final headers = await AuthService.getHeaders();
        final res = await http.post(
          Uri.parse(ApiConfig.routeMultiWaypoint),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'origin': {'lat': widget.pickupLat, 'lng': widget.pickupLng},
            'destination': {'lat': widget.destLat, 'lng': widget.destLng},
            'waypoints': [],
            'optimize': false,
          }),
        ).timeout(const Duration(seconds: 4));
        
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final overviewPolyline = data['overviewPolyline']?.toString();
          if (overviewPolyline != null && overviewPolyline.isNotEmpty) {
            points = _decodePolyline(overviewPolyline);
            success = points.isNotEmpty;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (success) {
      if (fetchedDistMeters > 0) {
        _routedDistanceKm = fetchedDistMeters / 1000.0;
        // Recalculate true road distance fares
        _estimateFare();
      }

      setState(() {
        _polylines = {
          Polyline( // Production quality curvy road line constraint
            polylineId: const PolylineId('route'),
            points: points,
            color: JT.primary,
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            geodesic: true,
          )
        };
      });
      _fitMapToRoute(routePoints: points);
    } else {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route_fallback'),
            points: [_pickupLatLng, _destLatLng],
            color: JT.primary, width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)]
          )
        };
      });
      _fitMapToRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookLabel = _vehicleName.split(' ').first;
    return Scaffold(
      backgroundColor: JT.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) => JagoMapView(
                controller: _mapController,
                initialCameraPosition: CameraPosition(target: _pickupLatLng, zoom: 14),
                onMapCreated: (_) => _fitMapToRoute(),
                markers: {
                  Marker(markerId: const MarkerId('pickup'), position: _pickupLatLng),
                  Marker(markerId: const MarkerId('destination'), position: _destLatLng),
                },
                circles: {
                  Circle(
                    circleId: const CircleId('pickup_pulse'),
                    center: _pickupLatLng,
                    radius: 35 + _pulseAnimation.value * 25,
                    fillColor: JT.primary.withValues(alpha: 0.10 * (1 - _pulseAnimation.value * 0.5)),
                    strokeColor: JT.primary.withValues(alpha: 0.35),
                    strokeWidth: 2,
                  ),
                },
                polylines: _polylines,
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: Material(
              color: JT.card,
              elevation: 6,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const SizedBox(
                  width: 44, height: 44,
                  child: Icon(Icons.arrow_back_rounded, color: JT.textPrimary),
                ),
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 64,
            right: 12,
            child: Column(
              children: [
                _rapidoAddressChip(
                  icon: Icons.circle,
                  iconColor: JT.primary,
                  label: _shortLocation(widget.pickup),
                ),
                const SizedBox(height: 8),
                _rapidoAddressChip(
                  icon: Icons.location_on_rounded,
                  iconColor: JT.danger,
                  label: _shortLocation(widget.destination),
                ),
              ],
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.44,
            minChildSize: 0.34,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.44, 0.68],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: JT.card,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(JT.radiusSheet)),
                  boxShadow: JT.shadowLg,
                ),
                child: StreamBuilder<Map<String, VehicleStatus>>(
                  stream: _vehicleStatusService.watchVehicleStatuses(),
                  builder: (context, snapshot) {
                    final statuses = snapshot.data ?? {};
                    final visibleFares = _visibleFareEntries(statuses);
                    final canBook = !_loading && !_estimating && visibleFares.isNotEmpty;

                    return Column(
                      children: [
                        Container(
                          width: 44, height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: JT.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            children: [
                              _buildVehicleSelector(statuses),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.fromLTRB(
                            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom,
                          ),
                          decoration: BoxDecoration(
                            color: JT.card,
                            border: Border(top: BorderSide(color: JT.border.withValues(alpha: 0.8))),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, -4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _rapidoPayRow(
                                      icon: Icons.payments_rounded,
                                      label: _paymentMethod == 'cash'
                                          ? 'Cash'
                                          : (_paymentMethod == 'wallet' ? 'Wallet' : 'UPI'),
                                      onTap: () => _showPaymentPicker(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _rapidoPayRow(
                                      icon: Icons.local_offer_outlined,
                                      label: 'Offers',
                                      onTap: _promoCtrl.text.isNotEmpty ? null : () => _showPromoDialog(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              JT.bookCta(
                                label: visibleFares.isEmpty ? 'No vehicles available' : 'Book $bookLabel',
                                loading: _loading,
                                onTap: canBook ? () => _handleOnConfirm() : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _rapidoAddressChip({
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JT.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JT.border),
        boxShadow: JT.shadowSm,
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: icon == Icons.circle ? 10 : 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: JT.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.edit_outlined, size: 16, color: JT.textTertiary),
        ],
      ),
    );
  }

  Widget _rapidoPayRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: JT.bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JT.border),
            boxShadow: JT.shadowXs,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: JT.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: JT.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: JT.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Method', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: JT.textPrimary)),
              const SizedBox(height: 12),
              _payBtn('cash', Icons.payments_rounded, 'Cash'),
              const SizedBox(height: 8),
              _payBtn('wallet', Icons.account_balance_wallet_rounded, 'Wallet'),
              const SizedBox(height: 8),
              _payBtn('upi', Icons.qr_code_scanner_rounded, 'UPI'),
            ],
          ),
        ),
      ),
    );
  }

  void _showPromoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apply Offer'),
        content: TextField(
          controller: _promoCtrl,
          decoration: const InputDecoration(hintText: 'Enter coupon code'),
          textCapitalization: TextCapitalization.characters,
          onChanged: _onCouponChanged,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _applyPromo();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }


  bool get _isParcel {
    final n = _vehicleName.toLowerCase();
    return n.contains('parcel') || n.contains('cargo') || n.contains('delivery');
  }

  Widget _buildPaymentSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payment Method',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151), letterSpacing: 0.2)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _payBtn('cash', Icons.payments_rounded, 'Cash')),
        const SizedBox(width: 8),
        Expanded(child: _payBtn('wallet', Icons.account_balance_wallet_rounded, 'Wallet')),
        const SizedBox(width: 8),
        Expanded(child: _payBtn('upi', Icons.qr_code_scanner_rounded, 'UPI')),
      ]),
      if (_paymentMethod == 'wallet') ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _walletBalance >= _finalFare
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _walletBalance >= _finalFare
                ? const Color(0xFF86EFAC)
                : const Color(0xFFFCA5A5)),
          ),
          child: Row(children: [
            Icon(
              _walletBalance >= _finalFare ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: _walletBalance >= _finalFare ? _green : const Color(0xFFDC2626),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _walletBalance >= _finalFare
                ? 'Wallet balance ₹${_walletBalance.toStringAsFixed(0)} • Sufficient'
                : 'Insufficient balance (₹${_walletBalance.toStringAsFixed(0)}). Please recharge.',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w400,
                color: _walletBalance >= _finalFare ? _green : const Color(0xFFDC2626),
              ),
            )),
          ]),
        ),
      ],
      if (_paymentMethod == 'upi') ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F7FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _blue.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_rounded, color: _blue, size: 15),
            const SizedBox(width: 8),
            const Expanded(child: Text(
              'Secure payment via Razorpay — UPI, Cards, Netbanking accepted',
              style: TextStyle(fontSize: 12, color: JT.primary, fontWeight: FontWeight.w500),
            )),
          ]),
        ),
      ],
    ]);
  }

  Widget _payBtn(String method, IconData icon, String label) {
    final selected = _paymentMethod == method;
    const blue = Color(0xFF2D8CFF);
    const lavender = Color(0xFF2C95F1);
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _paymentMethod = method);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? lavender.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? lavender : Colors.grey.shade200,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: selected ? [
            BoxShadow(color: lavender.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: selected ? lavender : Colors.grey.shade500),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? lavender : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressRow(IconData icon, Color color, String text, [Color? textColor]) {
    final tColor = textColor ?? JT.textPrimary;
    final isPickup = icon == Icons.circle;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Icon(icon, color: color, size: isPickup ? 12 : 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isPickup ? 'PICKUP' : 'DROP',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8), letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(text,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tColor),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  bool _isNightTime() {
    final hour = DateTime.now().hour;
    return hour >= 22 || hour < 6;
  }

  Widget _buildNightChargeIndicator() {
    if (!_isNightTime()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: JT.surfaceAlt, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JT.border)),
        child: Row(children: [
          const Text('🌙', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text('Night charges apply (10PM - 6AM)',
            style: TextStyle(color: JT.textPrimary, fontSize: 13, fontWeight: FontWeight.w400))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: JT.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('1.25x', style: TextStyle(color: JT.primary, fontSize: 12, fontWeight: FontWeight.w400)),
          ),
        ]),
      ),
    );
  }

  String? _getVehicleTag(int index) {
    if (_allFares.length < 2) return null;
    int fastestIdx = 0, saverIdx = 0, premiumIdx = 0;
    for (int j = 0; j < _allFares.length; j++) {
      final f = _allFares[j];
      final fare = (f['estimatedFare'] ?? 0).toDouble();
      final bestFare = (_allFares[saverIdx]['estimatedFare'] ?? 0).toDouble();
      final highFare = (_allFares[premiumIdx]['estimatedFare'] ?? 0).toDouble();
      if (fare < bestFare) saverIdx = j;
      if (fare > highFare) premiumIdx = j;
      final timeStr = f['estimatedTime']?.toString() ?? '99 min';
      final timeNum = int.tryParse(timeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 99;
      final bestTimeStr = _allFares[fastestIdx]['estimatedTime']?.toString() ?? '99 min';
      final bestTimeNum = int.tryParse(bestTimeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 99;
      if (timeNum < bestTimeNum) fastestIdx = j;
    }
    if (index == fastestIdx) return 'FASTEST';
    if (index == saverIdx && index != fastestIdx) return 'SAVER';
    if (index == premiumIdx && index != fastestIdx && _allFares.length >= 3) return 'PREMIUM';
    return null;
  }

  Widget _vehicleTagBadge(String tag) {
    Color color;
    IconData icon;
    switch (tag) {
      case 'FASTEST':
        color = const Color(0xFF2C95F1); // Premium Purple matching image
        icon = Icons.bolt_rounded;
        break;
      case 'SAVER':
        color = const Color(0xFF10B981);
        icon = Icons.savings_rounded;
        break;
      case 'PREMIUM':
        color = const Color(0xFFFFD700);
        icon = Icons.star_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 3),
        Text(tag, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
      ]),
    );
  }

  void _fitMapToRoute({List<LatLng>? routePoints}) {
    Future.delayed(const Duration(milliseconds: 300), () {
      double minLat, maxLat, minLng, maxLng;
      
      if (routePoints != null && routePoints.isNotEmpty) {
        minLat = maxLat = routePoints.first.latitude;
        minLng = maxLng = routePoints.first.longitude;
        for (final p in routePoints) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
      } else {
        final pLat = _pickupLatLng.latitude;
        final pLng = _pickupLatLng.longitude;
        final dLat = widget.destLat != 0 ? widget.destLat : pLat + 0.005;
        final dLng = widget.destLng != 0 ? widget.destLng : pLng + 0.005;
        minLat = min(pLat, dLat);
        maxLat = max(pLat, dLat);
        minLng = min(pLng, dLng);
        maxLng = max(pLng, dLng);
      }

      try {
        _mapController.fitBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          padding: 90,
        );
      } catch (_) {}
    });
  }

  Widget _buildVehicleSelector(Map<String, VehicleStatus> statuses) {
    if (_estimating) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFE5E7EB),
          highlightColor: const Color(0xFFF3F4F6),
          child: Column(children: List.generate(2, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
          ))),
        ),
      );
    }
    final visibleFares = _visibleFareEntries(statuses);
    if (visibleFares.isEmpty && !_estimating) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(Icons.no_transfer_rounded, color: Color(0xFF64748B), size: 40),
            const SizedBox(height: 12),
            Text(
              'No vehicles available',
              style: GoogleFonts.poppins(
                color: const Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check back in a few minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: visibleFares.map((entry) {
        final i = entry.key;
        final f = entry.value;
        final isActive = f['isActive'] != false;
        final isSelected = i == _selectedFareIndex && isActive;
        final name = f['vehicleCategoryName']?.toString() ?? f['vehicleName']?.toString() ?? f['name']?.toString() ?? 'Bike';
        final fareVal = (f['estimatedFare'] ?? 0).toDouble();
        final time = f['estimatedTime']?.toString() ?? '~5 min';
        final displayFare = isSelected ? (fareVal - _promoDiscount).clamp(0.0, double.infinity) : fareVal;
        
        final etaMins = _etaMins(time);
        final dropTime = _dropTimeStr(time);
        final tag = _getVehicleTag(i);
        final isFastest = tag == 'FASTEST';
        
        final subtitle = isActive ? '$etaMins min • Drop $dropTime' : 'Currently Unavailable';

        return GestureDetector(
          key: ValueKey(i),
          onTap: () {
            if (!isActive) return;
            HapticFeedback.selectionClick();
            setState(() => _selectedFareIndex = i);
          },
          child: AnimatedContainer(
            duration: JT.animationMedium,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? JT.primaryLight : JT.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? JT.primary : JT.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? JT.shadowMd : JT.shadowSm,
            ),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.55,
              child: Row(
                children: [
                  Container(
                    width: 62, height: 54,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? JT.card : JT.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? JT.primary.withValues(alpha: 0.15) : JT.border,
                      ),
                    ),
                    child: VehicleArtwork(
                      vehicleKey: name,
                      adminIcon: f['vehicleIcon']?.toString() ?? f['icon']?.toString(),
                      width: 54,
                      height: 46,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: JT.textPrimary,
                              ),
                            ),
                            if (isFastest && isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: JT.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'FASTEST',
                                  style: GoogleFonts.poppins(
                                    color: JT.primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: GoogleFonts.poppins(
                            color: isSelected ? JT.primaryDark : JT.textSecondary,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${displayFare.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: JT.textPrimary,
                        ),
                      ),
                      if (isSelected && _promoDiscount > 0)
                        Text(
                          '₹${fareVal.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: JT.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFareBreakdown(Map<String, dynamic> fare) {
    const cardBg = Color(0xFFF8FAFF);
    const borderCol = Color(0xFFE8EFFF);
    const textMain = JT.textPrimary;
    final textSub = Colors.grey.shade600;

    final baseFare = (fare['baseFare'] ?? 0).toDouble();
    final distanceFare = (fare['distanceFare'] ?? 0).toDouble();
    final timeFare = (fare['timeFare'] ?? 0).toDouble();
    final helperCharge = (fare['helperCharge'] ?? 0).toDouble();
    final gst = (fare['gst'] ?? 0).toDouble();
    final minFare = (fare['minimumFare'] ?? 0).toDouble();
    final farePerKm = (fare['farePerKm'] ?? 0).toDouble();
    final waitingChargePerMin = (fare['waitingChargePerMin'] ?? 0).toDouble();
    final subtotal = (fare['subtotal'] ?? (baseFare + distanceFare + timeFare)).toDouble();
    final isMinFareApplied = minFare > 0 && subtotal <= minFare + 0.01;
    final isNight = fare['isNightCharge'] == true;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: JT.primary.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
            border: Border(bottom: BorderSide(color: borderCol)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long_rounded, size: 16, color: JT.primary),
            const SizedBox(width: 8),
            Text(_isParcel ? 'Delivery Fare Details' : 'Fare Breakdown',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: JT.primary)),
            const Spacer(),
            if (isMinFareApplied)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: JT.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JT.primary.withValues(alpha: 0.3)),
                ),
                child: const Text('Min fare', style: TextStyle(
                  fontSize: 10, color: JT.primary, fontWeight: FontWeight.w400)),
              )
            else if (isNight)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C95F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C95F1).withValues(alpha: 0.3)),
                ),
                child: const Text('Night fare', style: TextStyle(
                  fontSize: 10, color: Color(0xFF2C95F1), fontWeight: FontWeight.w400)),
              )
            else
              Text('Incl. GST', style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.w500)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            // Base fare row with rate info
            _fareRow('Base Fare (Booking Fee)', '₹${baseFare.toStringAsFixed(0)}', textSub: textSub),
            // Distance fare — always show when farePerKm > 0
            if (farePerKm > 0) ...[
              _fareRow(
                '${_distanceKm.toStringAsFixed(1)} km × ₹${farePerKm.toStringAsFixed(0)}/km',
                '₹${distanceFare.toStringAsFixed(0)}',
                textSub: textSub,
              ),
            ] else if (distanceFare > 0)
              _fareRow('Distance (${_distanceKm.toStringAsFixed(1)} km)',
                '₹${distanceFare.toStringAsFixed(0)}', textSub: textSub),
            if (timeFare > 0)
              _fareRow('Time Charge (per min)', '₹${timeFare.toStringAsFixed(0)}', textSub: textSub),
            if (waitingChargePerMin > 0)
              _fareRow('Waiting Charge (₹${waitingChargePerMin.toStringAsFixed(0)}/min)', '—', textSub: textSub),
            // Parcel-specific: helper charge (Porter style)
            if (_isParcel && helperCharge > 0)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_2_rounded, size: 13, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Helper Charge (loading/unloading)',
                    style: TextStyle(fontSize: 11, color: textSub))),
                  Text('₹${helperCharge.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF10B981))),
                ]),
              )
            else if (!_isParcel && helperCharge > 0)
              _fareRow('Helper Charge', '₹${helperCharge.toStringAsFixed(0)}', textSub: textSub),
            // Night multiplier
            if (isNight) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.nightlight_round, size: 12, color: Color(0xFF2C95F1)),
                const SizedBox(width: 5),
                Text('Night fare applies (1.0x–1.25x)',
                  style: TextStyle(fontSize: 11, color: textSub, fontStyle: FontStyle.italic)),
              ]),
            ],
            // Minimum fare note
            if (minFare > 0) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.info_outline_rounded, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 5),
                Text('Minimum fare: ₹${minFare.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ]),
            ],
            Divider(height: 18, color: borderCol, thickness: 1),
            _fareRow('GST (5%)', '₹${gst.toStringAsFixed(0)}', textSub: textSub),
            if (_promoDiscount > 0)
              _fareRow('Promo Discount', '-₹${_promoDiscount.toInt()}', positive: true, textSub: textSub),
            const SizedBox(height: 8),
            // Total row — bold, large, orange
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total Fare', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: textMain)),
                if (minFare > 0 && isMinFareApplied)
                  Text('Min fare applied', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${_finalFare.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: JT.primary)),
                Text('incl. GST', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ]),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _fareRow(String label, String value, {bool bold = false, bool positive = false, Color? textSub}) {
    final sub = textSub ?? Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: sub))),
        Text(value, style: TextStyle(fontSize: 12,
          fontWeight: bold ? FontWeight.w500 : FontWeight.w500,
          color: positive ? _green : sub)),
      ]),
    );
  }

  Widget _buildPromoRow() {
    const cardBg = Color(0xFFF8FAFF);
    const borderCol = Color(0xFFE2E8F0);
    const textColor = JT.textPrimary;
    if (_appliedPromo != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC))),
        child: Row(children: [
          const Icon(Icons.local_offer_rounded, color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_appliedPromo applied!',
              style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF16A34A), fontSize: 13)),
            Text('You save ₹${_promoDiscount.toInt()}',
              style: TextStyle(color: Colors.green[700], fontSize: 12)),
          ])),
          GestureDetector(
            onTap: () => setState(() { _appliedPromo = null; _promoDiscount = 0; _promoCtrl.clear(); }),
            child: const Icon(Icons.close_rounded, color: Color(0xFF16A34A), size: 20)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.local_offer_outlined, color: JT.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _promoCtrl,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onCouponChanged,
              decoration: InputDecoration(
                hintText: 'Promo code',
                border: InputBorder.none, isDense: true,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFADB5BD))),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1.5, color: textColor),
            ),
          ),
          GestureDetector(
            onTap: _promoLoading ? null : _applyPromo,
            child: _promoLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: JT.primary))
              : const Text('APPLY', style: TextStyle(color: JT.primary, fontSize: 13, fontWeight: FontWeight.w400)),
          ),
        ]),
        if (_promoError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 28),
            child: Text(_promoError!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11))),
      ]),
    );
  }

  Widget _headerAction(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF64748B), size: 24),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
              _navItem(1, Icons.receipt_long_rounded, Icons.receipt_long_outlined, 'Trips'),
              _navItem(2, Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined, 'Wallet'),
              _navItem(3, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    bool isSelected = index == 0;
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: isSelected
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C95F1), Color(0xFF6366F1)], 
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2C95F1).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  const DashedLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    double dashHeight = 5, dashSpace = 3, startY = 0;
    final paint = Paint()..color = color..strokeWidth = 1;
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }
  @override
  bool shouldRepaint(DashedLinePainter oldDelegate) => oldDelegate.color != color;
}
