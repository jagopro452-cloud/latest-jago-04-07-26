import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show cos, pi, sqrt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../services/heatmap_service.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../widgets/vehicle_artwork.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/vehicle_status_service.dart';
import '../../services/alarm_service.dart';
import '../../services/trip_service.dart';
import '../../widgets/incoming_trip_sheet.dart';
import '../../widgets/incoming_parcel_sheet.dart';
import '../../widgets/jago_map_markers.dart';
import '../../services/fcm_service.dart';
import '../auth/login_screen.dart';
import '../auth/pending_verification_screen.dart';
import '../wallet/wallet_screen.dart';
import '../history/trips_history_screen.dart';
import '../profile/profile_screen.dart';
import '../break_mode/break_mode_screen.dart';
import '../fatigue/fatigue_screen.dart';
import '../trip/trip_screen.dart';
import '../notifications/notifications_screen.dart';
import '../referral/referral_screen.dart';
import '../profile/support_chat_screen.dart';
import '../onboarding/model_selection_screen.dart';
import '../onboarding/subscription_plans_screen.dart';
import '../earnings/earnings_screen.dart';
import '../kyc/kyc_documents_screen.dart';
import '../parcel/parcel_delivery_screen.dart';
import '../outstation_pool/outstation_pool_driver_screen.dart';
import '../car_sharing/pool_driver_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SocketService _socket = SocketService();
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(17.3850, 78.4867);
  bool _isOnline = false;
  bool _toggling = false;
  bool _socketConnected = false;
  bool _acceptingIncomingTrip = false;
  String _userName = 'Pilot';
  String _userPhone = '';
  double _walletBalance = 0;
  int _tripsToday = 0;
  double _earningsToday = 0;
  double _driverRating = 5.0;
  int _unreadNotifCount = 0;
  BitmapDescriptor? _driverLocationMarkerIcon;
  Map<String, dynamic>? _incomingTrip;
  Map<String, dynamic>? _incomingParcel;
  String _vehicleCategory = '';
  String _vehicleNumber = '';
  String _vehicleModel = '';
  String _zone = '';
  bool _hasValidLocationFix = false;
  bool _hasLiveLocationAccess = false;
  Timer? _locationTimer;
  Timer? _incomingTripPollTimer;
  bool _pollingIncomingTrip = false;
  StreamSubscription<Position>? _posStream; // live GPS stream — battery-efficient
  Position? _lastPosition; // cached position for server updates
  late AnimationController _pulseCtrl;
  final List<StreamSubscription> _subs = [];
  int _navIndex = 0;
  bool _inFreePeriod = false;
  int _freeDaysRemaining = 0;
  final VehicleStatusService _vehicleStatusService = VehicleStatusService();
  Map<String, VehicleStatus> _vehicleStatuses = {
    for (final status in VehicleStatusService.fallbackStatuses) status.key: status,
  };
  StreamSubscription<Map<String, VehicleStatus>>? _vehicleStatusSub;
  bool _serviceUnavailableNoticeShown = false;

  // ── Heatmap ────────────────────────────────────────────────────────────
  final HeatmapService _heatmap = HeatmapService();
  Set<Circle> _heatmapCircles = {};
  bool _showHeatmap = true;
  HeatmapZone? _nearestHighZone;
  HeatmapSuggestion? _heatmapSuggestion;
  Timer? _idleTimer;
  int _idleSeconds = 0;
  bool _idleSuggestionShown = false;

  // ── Eligible Services ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _eligibleServices = [];
  List<Map<String, dynamic>> _parcelVehicles = [];
  List<Map<String, dynamic>> _serviceModules = [];
  bool _eligibleServicesLoaded = false;

  // ── Revenue Config ─────────────────────────────────────────────────────
  Map<String, Map<String, dynamic>> _revenueConfig = {};

  Future<void> _refreshDriverMarkerIcon([String? vehicleType]) async {
    final icon = await JagoMapMarkers.vehicle(vehicleType ?? _vehicleCategory);
    if (!mounted) return;
    setState(() => _driverLocationMarkerIcon = icon);
  }

  String _getTimeGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    if (h < 20) return 'Good Evening';
    return 'Good Night';
  }

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1: return '${day}st';
      case 2: return '${day}nd';
      case 3: return '${day}rd';
      default: return '${day}th';
    }
  }

  bool _mapReadyToLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _socket.setAppInBackground(false);
    _refreshDriverMarkerIcon('cab');
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    // DEFER ALL HEAVY UI/API TASKS UNTIL AFTER FIRST FRAME TO PREVENT ANRs
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _mapReadyToLoad = true);
      
      _checkVerificationStatus();
      _loadUser();
      _getLocation();
      _fetchDashboard();
      _fetchLaunchBenefit();
      await _fetchEligibleServices();
      _fetchRevenueConfig();
      _watchVehicleAvailability();
      _connectSocket();
      
      await _recoverActiveTrip();
      await _recoverActiveParcel();
      await _consumeQueuedAlertAction();
      await _checkPendingFcmTrip();
    });
  }

  Future<void> _checkVerificationStatus() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/verification-status'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['verificationStatus'] != 'approved') {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PendingVerificationScreen()),
          );
        } else if (data['modelSelectedAt'] == null) {
          final inFreePeriod = data['launchFreeActive'] == true &&
              data['freePeriodEnd'] != null &&
              DateTime.tryParse(data['freePeriodEnd'].toString())?.isAfter(DateTime.now()) == true;
          if (!inFreePeriod) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ModelSelectionScreen()),
            );
          }
        }
      }
    } catch (_) {}
  }

  // ── App state recovery: if driver has an active trip, go to TripScreen directly ──
  Future<void> _recoverActiveTrip() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/active-trip'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final trip = data['trip'];
      if (trip == null) return;
      final status = trip['currentStatus'] ?? trip['current_status'] ?? '';
      final updatedAt = DateTime.tryParse((trip['updatedAt'] ?? trip['updated_at'] ?? '').toString());
      if (updatedAt != null && DateTime.now().difference(updatedAt) > const Duration(hours: 12)) {
        return;
      }
      if (!['accepted', 'arrived', 'on_the_way', 'in_progress', 'driver_assigned'].contains(status)) return;
      if (!mounted) return;
      // Navigate directly to trip screen — driver was mid-trip when app crashed
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TripScreen(trip: trip),
        ),
      );
    } catch (_) {}
  }

  Future<void> _recoverActiveParcel() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http
          .get(Uri.parse(ApiConfig.driverParcelActive), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final order = data['order'];
      if (order == null) return;
      final parcel = Map<String, dynamic>.from(order as Map);
      final status = parcel['currentStatus'] ?? parcel['current_status'] ?? '';
      if (!['driver_assigned', 'accepted', 'picked_up', 'in_transit'].contains(status)) {
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ParcelDeliveryScreen(order: parcel),
        ),
      );
    } catch (_) {}
  }

  Future<void> _checkPendingFcmTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Pending ride ──────────────────────────────────────────────────────
      final pendingTripStr = prefs.getString('pending_trip_data');
      if (pendingTripStr != null && pendingTripStr.isNotEmpty) {
        await prefs.remove('pending_trip_data');
        final tripData = jsonDecode(pendingTripStr) as Map<String, dynamic>;
        if (!_canReceiveTripPayload(tripData)) {
          _showUnavailableByAdminOnce();
          return;
        }
        if (mounted && _incomingTrip == null) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          setState(() => _incomingTrip = tripData);
          _showIncomingTrip();
          return; // Show trip first; parcel can wait
        }
      }

      // ── Pending parcel ────────────────────────────────────────────────────
      final pendingParcelStr = prefs.getString('pending_parcel_data');
      if (pendingParcelStr != null && pendingParcelStr.isNotEmpty) {
        await prefs.remove('pending_parcel_data');
        final parcelData = jsonDecode(pendingParcelStr) as Map<String, dynamic>;
        if (mounted && _incomingParcel == null && _incomingTrip == null) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          setState(() => _incomingParcel = parcelData);
          _showIncomingParcel();
        }
      }
    } catch (_) {}
  }

  bool _canReceiveTripPayload(Map<String, dynamic> trip) {
    final tripVehicle = (trip['vehicleCategory'] ??
            trip['vehicleCategoryName'] ??
            trip['vehicleName'] ??
            trip['vehicle_type'] ??
            trip['vehicleType'] ??
            _vehicleCategory)
        .toString();
    if (!VehicleStatusService.isActive(_vehicleStatuses, tripVehicle)) {
      return false;
    }
    final driverVehicleKey = _vehicleFamilyKey(_vehicleCategory);
    final tripVehicleKey = _vehicleFamilyKey(tripVehicle);
    if (driverVehicleKey.isNotEmpty &&
        tripVehicleKey.isNotEmpty &&
        driverVehicleKey != tripVehicleKey) {
      return false;
    }
    final tripServiceKey = _tripServiceKey(trip);
    if (tripServiceKey == null || tripServiceKey.isEmpty) {
      return true;
    }
    if (!_eligibleServicesLoaded) {
      debugPrint(
          '[DISPATCH] Eligible services not yet loaded; rejecting trip for $tripServiceKey until config ready');
      return false;
    }
    if (_eligibleServices.isEmpty) {
      debugPrint(
          '[DISPATCH] Eligible services empty; rejecting trip for $tripServiceKey until config ready');
      return false;
    }
    final eligibleKeys = _eligibleServices
        .map((entry) => entry['key']?.toString() ?? '')
        .where((key) => key.isNotEmpty)
        .expand(_serviceKeyAliases)
        .toSet();
    return _serviceKeyAliases(tripServiceKey).any(eligibleKeys.contains);
  }

  Iterable<String> _serviceKeyAliases(String value) {
    final key = value.trim().toLowerCase().replaceAll('-', '_');
    if (key == 'bike' || key == 'bike_ride') return const ['bike', 'bike_ride'];
    if (key == 'auto' || key == 'auto_ride') return const ['auto', 'auto_ride'];
    if (key == 'cab' || key == 'car' || key == 'mini' || key == 'mini_car') {
      return const ['cab', 'car', 'mini', 'mini_car'];
    }
    return [key];
  }

  String _vehicleFamilyKey(String value) {
    final key = value.toLowerCase();
    if (key.contains('parcel') || key.contains('cargo') || key.contains('truck') || key.contains('delivery') || key.contains('tempo')) {
      return 'parcel';
    }
    if (key.contains('bike')) return 'bike';
    if (key.contains('auto')) return 'auto';
    if (key.contains('premium')) return 'premium';
    if (key.contains('sedan')) return 'sedan';
    if (key.contains('suv')) return 'suv';
    if (key.contains('mini') || key.contains('cab') || key.contains('car')) {
      return 'mini_car';
    }
    return '';
  }

  String? _tripServiceKey(Map<String, dynamic> trip) {
    final tripType = (trip['tripType'] ?? trip['trip_type'] ?? '').toString().toLowerCase();
    if (tripType.contains('parcel') || tripType.contains('delivery') || tripType.contains('cargo')) {
      return 'parcel_delivery';
    }
    if (tripType.contains('outstation')) return 'outstation_pool';
    if (tripType.contains('intercity')) return 'intercity_pool';
    if (tripType.contains('pool') || tripType.contains('carpool') || tripType.contains('share')) {
      return 'city_pool';
    }

    final vehicle = (trip['vehicleCategory'] ??
            trip['vehicleCategoryName'] ??
            trip['vehicleName'] ??
            trip['vehicle_type'] ??
            trip['vehicleType'] ??
            '')
        .toString()
        .toLowerCase();
    if (vehicle.contains('bike')) return 'bike_ride';
    if (vehicle.contains('auto')) return 'auto_ride';
    if (vehicle.contains('premium')) return 'premium';
    if (vehicle.contains('sedan')) return 'sedan';
    if (vehicle.contains('suv')) return 'suv';
    if (vehicle.contains('mini') || vehicle.contains('cab') || vehicle.contains('car')) {
      return 'mini_car';
    }
    return null;
  }

  void _showUnavailableByAdminOnce() {
    if (_serviceUnavailableNoticeShown) return;
    _serviceUnavailableNoticeShown = true;
    _showSnack('Your service is temporarily unavailable by admin', error: true);
    Future.delayed(const Duration(seconds: 4), () {
      _serviceUnavailableNoticeShown = false;
    });
  }

  Future<void> _connectSocket() async {
    await _socket.connect(ApiConfig.socketUrl);

    _subs.add(_socket.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _socketConnected = connected);
    }));

    _subs.add(_socket.onNewTrip.listen((trip) {
      if (!mounted) return;
      debugPrint('[DISPATCH] Ride offer reached HomeScreen: $trip');
      if (!_canReceiveTripPayload(trip)) {
        debugPrint('[DISPATCH] Ride offer rejected by local vehicle/service filter');
        _showUnavailableByAdminOnce();
        return;
      }
      if (_incomingTrip == null) {
        setState(() => _incomingTrip = trip);
        _showIncomingTrip();
      }
    }));

    _subs.add(_socket.onTripCancelled.listen((data) {
      if (!mounted) return;
      // Active-trip cancellation is owned by TripScreen; Home only clears incoming offers.
      if (!_incomingOfferMatchesEvent(data)) return;
      _clearIncomingTripOffer(
        snackMessage: 'Customer cancelled the trip',
        snackColor: JT.error,
      );
    }));

    _subs.add(_socket.onTripTaken.listen((data) {
      if (!mounted) return;
      if (!_incomingOfferMatchesEvent(data)) return;
      _clearIncomingTripOffer(
        snackMessage: 'Another driver accepted this trip',
        snackColor: JT.textSecondary,
        snackDuration: const Duration(seconds: 2),
      );
    }));

    _subs.add(_socket.onTripTimeout.listen((data) {
      if (!mounted) return;
      if (!_incomingOfferMatchesEvent(data)) return;
      _clearIncomingTripOffer(
        snackMessage: 'Trip request timed out',
        snackColor: JT.warning,
        snackDuration: const Duration(seconds: 3),
      );
    }));

    _subs.add(_socket.onNoDrivers.listen((_) {
      AlarmService().stopAlarm();
    }));

    _subs.add(_socket.onNewParcel.listen((parcel) {
      if (!mounted) return;
      if (!_isOnline) return;
      if (_incomingTrip != null || _incomingParcel != null) return;
      setState(() => _incomingParcel = parcel);
      _showIncomingParcel();
    }));

    _subs.add(_socket.onWalletRecharged.listen((data) {
      if (!mounted) return;
      final newBalance = double.tryParse((data['newBalance'] ?? data['balance'])?.toString() ?? '0') ?? 0.0;
      setState(() => _walletBalance = newBalance);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Wallet recharged! Balance: ₹${newBalance.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: JT.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }));

    // ── FCM foreground stream: app is open, direct-show IncomingTripSheet ─
    // Fires when FCM arrives while app is in foreground (no notification shown).
    // Also fires after notification tap when app is in background/terminated.
    _subs.add(FcmService().onForegroundAlert.listen((data) {
      if (!mounted || !_isOnline) return;
      final type = data['type'] ?? '';
      if (type == 'new_trip' && _incomingTrip == null && _incomingParcel == null) {
        if (!_canReceiveTripPayload(data)) {
          _showUnavailableByAdminOnce();
          return;
        }
        setState(() => _incomingTrip = data);
        _showIncomingTrip();
      } else if (type == 'new_parcel' && _incomingParcel == null && _incomingTrip == null) {
        setState(() => _incomingParcel = data);
        _showIncomingParcel();
      }
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) s.cancel();
    _vehicleStatusSub?.cancel();
    _locationTimer?.cancel();
    _incomingTripPollTimer?.cancel();
    _posStream?.cancel();
    _idleTimer?.cancel();
    _heatmap.stopRefresh();
    _pulseCtrl.dispose();
    _socket.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket.setAppInBackground(false);
      _consumeQueuedAlertAction();
      _checkPendingFcmTrip();
      _refreshLocationAfterResume();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // App backgrounded — suspend GPS stream + server poll to save battery
      // Socket stays connected so the driver still receives trip requests via FCM
      _socket.setAppInBackground(true);
      if (_isOnline) return;
      _locationTimer?.cancel();
      _locationTimer = null;
      _posStream?.cancel();
      _posStream = null;
    }
      // Came back to foreground — refresh GPS fix and resume live updates if needed
  }

  Future<void> _refreshLocationAfterResume() async {
    await _getLocation();
    if (!mounted || !_isOnline || !_hasValidLocationFix || !_hasLiveLocationAccess) return;
    _startLocationStreaming();
    _socket.setOnlineStatus(
      isOnline: true,
      lat: _center.latitude,
      lng: _center.longitude,
    );
  }

  void _applyLocationFix(Position pos, {bool animate = true}) {
    _lastPosition = pos;
    _hasValidLocationFix = true;
    if (!mounted) return;
    setState(() => _center = LatLng(pos.latitude, pos.longitude));
    if (animate) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_center, 15));
    }
  }

  Future<void> _showLocationRequiredDialog({
    required String title,
    required String message,
    required Future<bool> Function() openSettings,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Pilot';
      _userPhone = prefs.getString('user_phone') ?? '';
    });
  }

  bool get _isDriverVehicleActive {
    if (_vehicleCategory.trim().isEmpty) return true;
    return VehicleStatusService.isActive(_vehicleStatuses, _vehicleCategory);
  }

  void _watchVehicleAvailability() {
    _vehicleStatusSub?.cancel();
    _vehicleStatusSub = _vehicleStatusService.watchVehicleStatuses().listen((statuses) {
      if (!mounted) return;
      setState(() => _vehicleStatuses = statuses);
      if (_isOnline && !_isDriverVehicleActive) {
        _forceOfflineForInactiveService();
      }
    });
  }

  Future<void> _forceOfflineForInactiveService() async {
    if (!mounted) return;
    setState(() => _isOnline = false);
    _stopLocationStreaming();
    _stopHeatmap();
    _socket.setOnlineStatus(
      isOnline: false,
      lat: _center.latitude,
      lng: _center.longitude,
    );
    _showSnack('Your service is temporarily unavailable by admin', error: true);
    try {
      final headers = await AuthService.getHeaders();
      await http.patch(
        Uri.parse(ApiConfig.driverOnlineStatus),
        headers: headers,
        body: jsonEncode({
          'isOnline': false,
          'lat': _center.latitude,
          'lng': _center.longitude,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _getLocation() async {
    try {
      // 1. Check if service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _hasLiveLocationAccess = false;
        if (mounted) {
          _showSnack('Please turn on GPS/Location in your settings.', error: true);
          await Geolocator.openLocationSettings();
        }
        return;
      }

      // 2. Check Permissions
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _hasLiveLocationAccess = false;
        if (mounted) {
          await _showLocationRequiredDialog(
            title: 'Location Required',
            message: 'Location access is required to receive ride requests. Please set it to "Allow all the time" in settings.',
            openSettings: Geolocator.openAppSettings,
          );
        }
        return;
      }

      // 3. We have permission and service!
      _hasLiveLocationAccess = true;

      // 4. Request battery optimization exemption on Android so the GPS
      //    foreground service isn't killed when the driver goes offline.
      if (Platform.isAndroid) {
        final battStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!battStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }

      // 5. Get a position (Fallback to last known first for speed)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _applyLocationFix(lastKnown, animate: _lastPosition == null);
      }

      // 5. Get fresh accurate position
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      ).catchError((e) => lastKnown ?? Position(
        latitude: _center.latitude,
        longitude: _center.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
      ));

      _applyLocationFix(pos);
    } catch (e) {
      debugPrint('Location Error: $e');
      // If we have any last position, we allow going online even if fresh catch fails
      if (_lastPosition != null) {
        _hasValidLocationFix = true;
        _hasLiveLocationAccess = true;
      }
    }
  }

  void _handleSessionExpired() {
    AuthService.rehydrateStoredSession().then((stillValid) async {
      if (stillValid || !mounted) return;
      await AuthService.clearLocalSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session expired. Please login again.', style: TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: JT.error,
        behavior: SnackBarBehavior.floating,
      ));
    });
  }

  Future<void> _consumeQueuedAlertAction() async {
    final queued = await FcmService().consumeQueuedAction();
    if (queued == null || !mounted) return;

    final actionId = (queued['actionId'] ?? '').toString();
    final rawData = queued['data'];
    if (rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);

    final prefs = await SharedPreferences.getInstance();
    if (actionId.startsWith('trip_')) {
      await prefs.remove('pending_trip_data');
    }
    if (actionId == 'parcel_open') {
      await prefs.remove('pending_parcel_data');
    }

    if (actionId == 'trip_accept') {
      await _acceptIncomingTrip(data);
      return;
    }

    if (actionId == 'trip_reject') {
      await _rejectIncomingTrip(data);
      return;
    }

    if (actionId == 'parcel_open' && _incomingTrip == null && _incomingParcel == null) {
      setState(() => _incomingParcel = data);
      _showIncomingParcel();
    }
  }

  Future<void> _fetchDashboard() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      _handleSessionExpired();
      return;
    }
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.driverDashboard), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        setState(() {
          _isOnline = data['isOnline'] ?? false;
          _walletBalance = double.tryParse(data['walletBalance']?.toString() ?? '0') ?? 0.0;
          _tripsToday = data['tripsToday'] ?? 0;
          _earningsToday = double.tryParse(data['earningsToday']?.toString() ?? '0') ?? 0.0;
          _vehicleCategory = data['vehicleCategory'] ?? '';
          _vehicleNumber = data['vehicleNumber'] ?? '';
          _vehicleModel = data['vehicleModel'] ?? '';
          _zone = data['zone'] ?? '';
          _driverRating = double.tryParse(data['rating']?.toString() ?? '') ?? _driverRating;
        });
        _refreshDriverMarkerIcon(_vehicleCategory);
        if (_isOnline) {
          if (!_hasValidLocationFix) {
            await _getLocation();
          }
          if (_hasValidLocationFix && _hasLiveLocationAccess) {
            _startLocationStreaming();
          }
          // Re-announce online status via socket — restores driver_locations.is_online=true
          // after app restart/crash where socket disconnect handler had set it false.
          // Without this, dispatch won't find driver until first GPS update arrives (3s delay).
          if (_hasValidLocationFix && _hasLiveLocationAccess) {
            _socket.setOnlineStatus(
              isOnline: true,
              lat: _center.latitude,
              lng: _center.longitude,
            );
          }
        }
      } else if (res.statusCode == 401) {
        _handleSessionExpired();
        return;
      }
    } catch (_) {}
  }

  Future<void> _fetchLaunchBenefit() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.launchBenefit), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _inFreePeriod = data['active'] == true;
            _freeDaysRemaining = data['freeDaysRemaining'] ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchEligibleServices() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.eligibleServices), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final list = (data['services'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        final parcelVehicles = (data['parcelVehicles'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        final modules = (data['modules'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _eligibleServices = list;
          _parcelVehicles = parcelVehicles;
          _serviceModules = modules;
          _eligibleServicesLoaded = true;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _eligibleServicesLoaded = true);
    }
  }

  Future<void> _fetchRevenueConfig() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.revenueConfig), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final modules = (data['modules'] as List<dynamic>?) ?? [];
        final map = <String, Map<String, dynamic>>{};
        for (final m in modules) {
          final name = m['moduleName']?.toString() ?? '';
          if (name.isNotEmpty) map[name] = Map<String, dynamic>.from(m as Map);
        }
        setState(() => _revenueConfig = map);
      }
    } catch (_) {}
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.notifications), headers: headers).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _unreadNotifCount = (data['unreadCount'] ?? 0).toInt());
      }
    } catch (_) {}
  }

  void _startLocationStreaming() {
    _startIncomingTripPolling();
    if (!_hasValidLocationFix || !_hasLiveLocationAccess) return;
    _locationTimer?.cancel();
    _posStream?.cancel();

    // ── GPS stream: hardware-managed, emits only when device moves ≥ 15 m ──
    // Far more battery-efficient than calling getCurrentPosition every 3 s.
    _posStream = Geolocator.getPositionStream(
      locationSettings: Platform.isIOS
          ? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
          : AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: Duration(seconds: 3),
              foregroundNotificationConfig: ForegroundNotificationConfig(
                notificationText: 'JAGO Pro Pilot is tracking your location',
                notificationTitle: 'Location Tracking Active',
                enableWakeLock: true,
                setOngoing: true,
              ),
            ),
    ).listen((pos) {
      if (pos.isMocked) {
        debugPrint('[FRAUD] Mock GPS detected — ignoring position update');
        return;
      }
      final prev = _lastPosition;
      if (prev != null) {
        final distM = Geolocator.distanceBetween(
            prev.latitude, prev.longitude, pos.latitude, pos.longitude);
        final elapsed = pos.timestamp.difference(prev.timestamp).inSeconds.abs();
        if (elapsed > 0) {
          final speedKmh = (distM / elapsed) * 3.6;
          if (speedKmh > 150) {
            debugPrint('[FRAUD] Speed anomaly: ${speedKmh.toStringAsFixed(1)} km/h — ignoring');
            return;
          }
        }
        if (distM > 500 && elapsed < 5) {
          debugPrint('[FRAUD] Teleport detected: ${distM.toStringAsFixed(0)} m in ${elapsed}s — ignoring');
          return;
        }
      }
      _lastPosition = pos;
      final newCenter = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _center = newCenter);
        _mapController?.animateCamera(CameraUpdate.newLatLng(newCenter));
      }
    }, onError: (_) {});

    // ── Server-update timer: every 5 s (was 3 s) — sends cached position ──
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final pos = _lastPosition;
      if (pos == null || !mounted) return;

      final lat = pos.latitude;
      final lng = pos.longitude;
      final reqHeaders = await AuthService.getHeaders();

      _socket.sendLocation(
        lat: lat,
        lng: lng,
        heading: pos.heading,
        speed: pos.speed,
      );
      // Fire-and-forget — don't await; avoids blocking the timer tick
      http.post(
        Uri.parse(ApiConfig.driverLocation),
        headers: reqHeaders,
        body: jsonEncode({'lat': lat, 'lng': lng, 'isOnline': true}),
      ).catchError((_) => http.Response('', 500));

    });
  }

  void _stopLocationStreaming() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _incomingTripPollTimer?.cancel();
    _incomingTripPollTimer = null;
    _posStream?.cancel();
    _posStream = null;
    _lastPosition = null;
  }

  void _startIncomingTripPolling() {
    if (!_isOnline) return;
    _incomingTripPollTimer?.cancel();
    _pollIncomingTrip();
    _incomingTripPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollIncomingTrip(),
    );
  }

  Map<String, dynamic>? _incomingOfferFromResponse(Map<String, dynamic> data) {
    final nestedData = data['data'];
    final envelope = nestedData is Map
        ? Map<String, dynamic>.from(nestedData)
        : const <String, dynamic>{};
    final rawTrip = data['trip'] ??
        data['offer'] ??
        data['incomingTrip'] ??
        envelope['trip'] ??
        envelope['offer'] ??
        envelope['incomingTrip'] ??
        ((data['id'] != null || data['tripId'] != null) ? data : null) ??
        ((envelope['id'] != null || envelope['tripId'] != null)
            ? envelope
            : null);
    if (rawTrip is! Map) return null;

    final trip = Map<String, dynamic>.from(rawTrip);
    final stage = (data['stage'] ??
            data['offerStage'] ??
            data['offer_stage'] ??
            envelope['stage'] ??
            envelope['offerStage'] ??
            envelope['offer_stage'] ??
            '')
        .toString()
        .toLowerCase();
    final status = (trip['currentStatus'] ??
            trip['current_status'] ??
            trip['status'] ??
            data['status'] ??
            envelope['status'] ??
            '')
        .toString()
        .toLowerCase();
    const ignoredStatuses = {
      'accepted',
      'driver_assigned',
      'arrived',
      'on_the_way',
      'in_progress',
      'completed',
      'cancelled',
      'canceled',
      'expired',
    };
    if (ignoredStatuses.contains(status)) return null;

    const offerStages = {
      '',
      'new_request',
      'new',
      'offered',
      'offer',
      'pending',
      'searching',
    };
    if (!offerStages.contains(stage)) {
      debugPrint('[DISPATCH] Ignoring incoming-trip stage=$stage status=$status');
      return null;
    }
    trip['tripId'] = trip['tripId'] ?? trip['id'];
    return trip;
  }

  Future<void> _pollIncomingTrip() async {
    if (!mounted ||
        !_isOnline ||
        _pollingIncomingTrip ||
        _incomingTrip != null ||
        _incomingParcel != null) {
      return;
    }
    _pollingIncomingTrip = true;
    try {
      final headers = await AuthService.getHeaders();
      final resp = await http.get(
        Uri.parse(ApiConfig.driverIncomingTrip),
        headers: headers,
      ).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) {
        debugPrint(
            '[DISPATCH] HTTP fallback poll failed status=${resp.statusCode} body=${resp.body}');
        return;
      }
      if (!mounted || !_isOnline) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tripMap = _incomingOfferFromResponse(data);
      if (tripMap == null || _incomingTrip != null) {
        return;
      }

      debugPrint('[DISPATCH] HTTP fallback ride offer received: $tripMap');
      if (!_canReceiveTripPayload(tripMap)) {
        debugPrint('[DISPATCH] HTTP fallback offer rejected by local filter');
        _showUnavailableByAdminOnce();
        return;
      }
      setState(() => _incomingTrip = tripMap);
      _showIncomingTrip();
    } catch (e) {
      debugPrint('[DISPATCH] HTTP fallback poll failed: $e');
    } finally {
      _pollingIncomingTrip = false;
    }
  }

  // ── Heatmap methods ────────────────────────────────────────────────────

  void _startHeatmapRefresh() {
    _idleSuggestionShown = false;
    _heatmap.startRefresh(
      _center.latitude, _center.longitude,
      onUpdate: () {
        if (!mounted) return;
        setState(() {
          _heatmapCircles = _showHeatmap ? _heatmap.buildCircles() : {};
          _nearestHighZone = _heatmap.nearestHighDemand(
            _center.latitude, _center.longitude);
        });
      },
    );
  }

  void _stopHeatmap() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleSeconds = 0;
    _idleSuggestionShown = false;
    _heatmap.stopRefresh();
    if (mounted) setState(() { _heatmapCircles = {}; _nearestHighZone = null; _heatmapSuggestion = null; });
  }

  void _toggleHeatmap() {
    setState(() {
      _showHeatmap = !_showHeatmap;
      _heatmapCircles = _showHeatmap ? _heatmap.buildCircles() : {};
    });
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleSeconds = 0;
    _idleSuggestionShown = false;
    final timeoutSecs = _heatmap.idleTimeoutMinutes * 60;
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isOnline || _incomingTrip != null || !mounted) {
        _idleSeconds = 0;
        _idleSuggestionShown = false;
        return;
      }
      _idleSeconds++;
      if (_idleSeconds >= timeoutSecs && !_idleSuggestionShown) {
        _idleSuggestionShown = true;
        _triggerIdleSuggestion();
      }
    });
  }

  Future<void> _triggerIdleSuggestion() async {
    final sugg = await _heatmap.fetchSuggestion(_center.latitude, _center.longitude);
    if (sugg == null || !mounted) return;
    setState(() => _heatmapSuggestion = sugg);
    _showIdleSuggestionDialog(sugg);
  }

  void _showIdleSuggestionDialog(HeatmapSuggestion sugg) {
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => AlertDialog(
        backgroundColor: JT.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: JT.border, width: 1),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: sugg.demandLevel == 'high'
                  ? JT.error.withValues(alpha: 0.10)
                  : JT.warning.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_fire_department_rounded,
              color: sugg.demandLevel == 'high' ? JT.error : JT.warning,
              size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Demand Zone Nearby',
              style: GoogleFonts.poppins(color: JT.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sugg.message, style: GoogleFonts.poppins(color: JT.textPrimary, fontSize: 14, fontWeight: FontWeight.w400)),
          const SizedBox(height: 8),
          Text(sugg.detail, style: GoogleFonts.poppins(color: JT.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JT.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JT.success.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.currency_rupee_rounded, color: JT.success, size: 18),
              const SizedBox(width: 6),
              Text('₹${sugg.earningMin}–₹${sugg.earningMax} in 30 min',
                style: GoogleFonts.poppins(color: JT.success, fontWeight: FontWeight.w500, fontSize: 14)),
            ]),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _idleSuggestionShown = false; },
            child: Text('Stay Here', style: GoogleFonts.poppins(color: JT.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                LatLng(sugg.lat, sugg.lng), 14));
            },
            icon: const Icon(Icons.navigation_rounded, size: 16),
            label: const Text('Go There'),
            style: ElevatedButton.styleFrom(
              backgroundColor: JT.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  String _socketEventTripId(Map<String, dynamic> data) {
    return (data['tripId'] ?? data['trip_id'] ?? data['id'] ?? '').toString();
  }

  String _incomingOfferTripId() {
    return (_incomingTrip?['tripId'] ?? _incomingTrip?['id'] ?? '').toString();
  }

  bool _incomingOfferMatchesEvent(Map<String, dynamic> data) {
    if (_incomingTrip == null) return false;
    final eventId = _socketEventTripId(data);
    final incomingId = _incomingOfferTripId();
    if (eventId.isNotEmpty && incomingId.isNotEmpty && eventId != incomingId) {
      return false;
    }
    return true;
  }

  void _clearIncomingTripOffer({
    required String snackMessage,
    required Color snackColor,
    Duration snackDuration = const Duration(seconds: 4),
  }) {
    if (_incomingTrip == null || !mounted) return;
    FcmService().dismissTripNotification();
    setState(() => _incomingTrip = null);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(snackMessage, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: snackColor,
      behavior: SnackBarBehavior.floating,
      duration: snackDuration,
    ));
  }

  void _showIncomingTrip() {
    if (_incomingTrip == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => IncomingTripSheet(
          trip: _incomingTrip!,
          onAccept: () async => _acceptIncomingTrip(
            Map<String, dynamic>.from(_incomingTrip!),
            closePopup: true,
          ),
          onReject: () async => _rejectIncomingTrip(
            Map<String, dynamic>.from(_incomingTrip!),
            closePopup: true,
          ),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _acceptIncomingTrip(
    Map<String, dynamic> trip, {
    bool closePopup = false,
  }) async {
    if (_acceptingIncomingTrip) return;
    if (!_canReceiveTripPayload(trip)) {
      if (closePopup && mounted) {
        Navigator.pop(context);
      }
      if (mounted) setState(() => _incomingTrip = null);
      await FcmService().dismissTripNotification();
      _showUnavailableByAdminOnce();
      return;
    }
    if (closePopup && mounted) {
      Navigator.pop(context);
    }
    if (mounted) {
      setState(() {
        _incomingTrip = null;
        _acceptingIncomingTrip = true;
      });
    }
    await FcmService().dismissTripNotification();

    final tripId = (trip['tripId'] ?? trip['id'] ?? '').toString();
    if (tripId.isEmpty) {
      if (mounted) {
        setState(() => _acceptingIncomingTrip = false);
        _showSnack('Trip data is missing. Please wait for the next request.', error: true);
      }
      return;
    }

    bool accepted = false;
    Map<String, dynamic>? acceptResponse;
    final acceptIdempotencyKey = const Uuid().v4();
    if (_socketConnected) {
      accepted = await _socket.acceptTrip(tripId, idempotencyKey: acceptIdempotencyKey);
    }
    if (!accepted) {
      acceptResponse = await TripService.acceptTrip(tripId, idempotencyKey: acceptIdempotencyKey);
      accepted = acceptResponse['ok'] == true;
    }
    if (!mounted) return;

    Map<String, dynamic>? fullTrip;
    try {
      final hdrs = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.driverActiveTrip),
        headers: hdrs,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final activeTrip = data['trip'];
        if (activeTrip is Map) {
          final serverTrip = Map<String, dynamic>.from(activeTrip);
          final serverTripId = (serverTrip['id'] ?? serverTrip['tripId'] ?? '').toString();
          if (serverTripId == tripId) {
            fullTrip = Map<String, dynamic>.from(trip)..addAll(serverTrip);
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (fullTrip == null && accepted) {
      // Fallback: use what we have from the socket/notification payload
      fullTrip = Map<String, dynamic>.from(trip);
    }
    
    if (fullTrip == null) {
      _showSnack(
        _acceptTripErrorMessage(acceptResponse),
        error: true,
      );
      setState(() => _acceptingIncomingTrip = false);
      return;
    }
    setState(() => _acceptingIncomingTrip = false);
    AnalyticsService().logTripAccepted(tripId: tripId);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(trip: fullTrip!)));
  }

  String _acceptTripErrorMessage(Map<String, dynamic>? response) {
    final code = (response?['code'] ?? '').toString();
    final reason = (response?['reason'] ?? '').toString();
    final message = (response?['message'] ?? response?['error'] ?? '').toString();
    final lower = message.toLowerCase();

    if (code == 'VEHICLE_MISMATCH' || reason == 'vehicle_category_mismatch') {
      return 'This trip does not match your vehicle type. Please wait for the correct request.';
    }
    if (code == 'SERVICE_NOT_ENABLED' || reason == 'service_not_enabled') {
      return 'This service is disabled for your account right now. Please wait for the next request.';
    }
    if (code == 'CITY_NOT_ENABLED' || code == 'CITY_MISMATCH' || reason == 'city_not_enabled' || reason == 'city_mismatch') {
      return 'This trip belongs to another service area. Please wait for the next request.';
    }
    if (code == 'SERVICE_DISABLED' || reason == 'service_disabled') {
      return 'This service is currently unavailable by admin.';
    }
    if (code == 'DISPATCH_MISMATCH') {
      return 'This trip does not match your vehicle or enabled service. Please wait for the next request.';
    }
    if (code == 'TRIP_ALREADY_TAKEN' || lower.contains('already accepted by another')) {
      return 'Trip already assigned to another pilot. Please try the next request.';
    }
    if (code == 'DRIVER_BUSY' || lower.contains('already has another active trip')) {
      return 'You already have an active trip. Finish that ride and then accept the next one.';
    }
    if (code == 'TRIP_CANCELLED' || lower.contains('cancelled by customer')) {
      return 'This trip was cancelled by the customer.';
    }
    if (lower.contains('status')) {
      return 'Trip request expired or changed. Please wait for the next request.';
    }
    if (lower.contains('timeout') || lower.contains('network') || lower.contains('socket')) {
      return 'Connection issue while accepting the trip. Please try the next request.';
    }
    return 'Could not accept this trip. Please try the next request.';
  }

  Future<void> _rejectIncomingTrip(
    Map<String, dynamic> trip, {
    bool closePopup = false,
  }) async {
    if (closePopup && mounted) {
      Navigator.pop(context);
    }
    if (mounted) {
      setState(() => _incomingTrip = null);
    }
    await FcmService().dismissTripNotification();
    final tripId = (trip['tripId'] ?? trip['id'] ?? '').toString();
    if (tripId.isEmpty) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final hdrs = await AuthService.getHeaders();
        final res = await http.post(
          Uri.parse(ApiConfig.driverRejectTrip),
          headers: {...hdrs, 'Content-Type': 'application/json'},
          body: jsonEncode({'tripId': tripId}),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) return;
      } catch (_) {}
      if (attempt == 0) await Future.delayed(const Duration(seconds: 2));
    }
  }

  void _showIncomingParcel() {
    final parcel = _incomingParcel;
    if (parcel == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => IncomingParcelSheet(
          parcel: parcel,
          onAccept: () async {
            setState(() => _incomingParcel = null);
            final orderId = parcel['orderId']?.toString() ?? parcel['id']?.toString() ?? '';
            if (orderId.isEmpty) return;
            try {
              final hdrs = await AuthService.getHeaders();
              final r = await http.post(Uri.parse(ApiConfig.driverParcelAccept(orderId)), headers: hdrs).timeout(const Duration(seconds: 10));
              if (!mounted) return;
              if (r.statusCode == 200) {
                final data = jsonDecode(r.body);
                final order = data['order'] as Map<String, dynamic>? ?? {};
                Navigator.push(context, MaterialPageRoute(builder: (_) => ParcelDeliveryScreen(order: order)));
              } else {
                final data = jsonDecode(r.body) as Map<String, dynamic>;
                _showSnack(
                  data['message']?.toString() ?? 'Already taken by another driver',
                  error: true,
                );
              }
            } catch (_) {
              if (mounted) _showSnack('Network error, try again', error: true);
            }
          },
          onSkip: () {
            if (mounted) setState(() => _incomingParcel = null);
          },
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _incomingParcel = null);
    });
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.white)),
      backgroundColor: error ? JT.error : JT.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showWalletLockedDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: JT.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: JT.error.withValues(alpha: 0.3), width: 1),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: JT.error.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: JT.error.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: JT.error, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            'Wallet Balance Low',
            style: GoogleFonts.poppins(
              color: JT.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.poppins(color: JT.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: JT.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
              label: Text(
                'Recharge Wallet Now',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
              },
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: GoogleFonts.poppins(color: JT.textSecondary)),
          ),
        ]),
      ),
    );
  }


  bool _isServiceModuleEnabled(String key) {
    if (!_eligibleServicesLoaded || _serviceModules.isEmpty) return false;
    for (final module in _serviceModules) {
      if (module['key']?.toString() == key) {
        return module['enabled'] == true;
      }
    }
    return false;
  }

  Future<void> _toggleOnline() async {
    HapticFeedback.mediumImpact();
    final newStatus = !_isOnline;
    if (newStatus && !_isDriverVehicleActive) {
      _showSnack('Your service is temporarily unavailable by admin', error: true);
      return;
    }

    setState(() => _toggling = true);

    try {
      if (newStatus) {
        await _getLocation();
      }

      _socket.setOnlineStatus(
        isOnline: newStatus,
        lat: _center.latitude,
        lng: _center.longitude,
      );

      final headers = await AuthService.getHeaders();
      final res = await http.patch(
        Uri.parse(ApiConfig.driverOnlineStatus),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'isOnline': newStatus,
          'lat': _center.latitude,
          'lng': _center.longitude,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 401) {
        _handleSessionExpired();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('status_${res.statusCode}');
      }

      if (!mounted) return;
      setState(() {
        _isOnline = newStatus;
        _toggling = false;
      });

      if (newStatus) {
        _startLocationStreaming();
        _startHeatmapRefresh();
        _startIdleTimer();
        _showSnack('You are online. Waiting for ride requests.');
        AnalyticsService().logDriverOnline();
      } else {
        _stopLocationStreaming();
        _stopHeatmap();
        _showSnack('You are offline.');
        AnalyticsService().logDriverOffline();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _toggling = false);
      _showSnack(
        newStatus
            ? 'Could not go online. Check internet and try again.'
            : 'Could not go offline. Please try again.',
        error: true,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: JT.bg,
        drawer: _buildDrawer(),
        bottomNavigationBar: _buildDriverBottomNav(),
        body: Stack(children: [
          // MAP BACKGROUND
          if (_navIndex == 0) ...[
            // Full-screen map (Deferred to prevent stutter)
            if (_mapReadyToLoad)
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center, zoom: 14),
                  onMapCreated: (c) {
                    _mapController = c;
                    if (_hasValidLocationFix) {
                      c.animateCamera(CameraUpdate.newLatLngZoom(_center, 15));
                    }
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  markers: {
                    if (_driverLocationMarkerIcon != null)
                      Marker(
                        markerId: const MarkerId('driver_location'),
                        position: _center,
                        icon: _driverLocationMarkerIcon!,
                        infoWindow: const InfoWindow(title: 'You are here'),
                        rotation: _lastPosition?.heading ?? 0,
                        flat: true,
                        anchor: const Offset(0.5, 0.5),
                      ),
                  },
                  circles: _heatmapCircles,
                ),
              )
            else
              Positioned.fill(
                child: Container(color: const Color(0xFFF1F5F9)),
              ),
              
            // Clean white gradient overlay at top for readability
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.95),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],

          // TRIPS BACKGROUND
          if (_navIndex == 1)
            Positioned.fill(child: Container(color: Colors.white)),

          SafeArea(
            child: Column(children: [
              _buildTopBar(),
              
              if (_navIndex == 0) ...[
                const SizedBox(height: 10),
                const Spacer(),
                
                // Floating Location Button right above the bottom panel
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, bottom: 20),
                    child: GestureDetector(
                      onTap: _getLocation,
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1), 
                              blurRadius: 15, 
                              offset: const Offset(0, 5),
                            )
                          ],
                        ),
                        child: const Icon(Icons.my_location_rounded, color: Color(0xFF0F172A), size: 24),
                      ),
                    ),
                  ),
                ),
                // Heatmap banner
                if (_isOnline && _nearestHighZone != null && _showHeatmap)
                  _buildHeatmapBanner(_nearestHighZone!),
                _buildBottomPanel(),
              ] else if (_navIndex == 1) ...[
                const Expanded(child: InlineTripsView()),
              ] else if (_navIndex == 2) ...[
                const Expanded(child: InlineEarningsView()),
              ] else if (_navIndex == 3) ...[
                const Expanded(child: InlineWalletView()),
              ] else if (_navIndex == 4) ...[
                Expanded(child: InlineRatingsView(rating: _driverRating)),
              ]
            ]),
          ),
          
          // Heatmap toggle button
          if (_navIndex == 0 && _isOnline)
            Positioned(
              right: 14,
              bottom: 100,
              child: _buildHeatmapToggle(),
            ),
        ]),
      ),
    );
  }

  Widget _buildHeatmapBanner(HeatmapZone zone) {
    final color = zone.color;
    final icon = zone.demandLevel == 'high' ? Icons.local_fire_department_rounded : Icons.trending_up_rounded;

    return GestureDetector(
      onTap: () => _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(zone.lat, zone.lng), 15)),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: AppCard.neonGlowBorder(color: color),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              zone.demandLevel == 'high' ? '🔴 High demand zone ${_calcDist(zone)} away' : '🟡 Medium demand zone ${_calcDist(zone)} away',
              style: AppText.bodyPrimary(null),
            ),
            if (zone.earningMin > 0)
              Text(
                'Est. ₹${zone.earningMin}–₹${zone.earningMax} in 30 min',
                style: GoogleFonts.poppins(color: color, fontSize: 11, fontWeight: FontWeight.w400),
              ),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textTertiary, size: 14),
        ]),
      ),
    );
  }

  String _calcDist(HeatmapZone zone) {
    final dLat = (zone.lat - _center.latitude) * 111.32;
    final dLng = (zone.lng - _center.longitude) * 111.32 * cos(_center.latitude * pi / 180);
    final d = sqrt(dLat * dLat + dLng * dLng);
    if (d < 1.0) return '${(d * 1000).toStringAsFixed(0)} m';
    return '${d.toStringAsFixed(1)} km';
  }

  Widget _buildHeatmapToggle() {
    return GestureDetector(
      onTap: _toggleHeatmap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: _showHeatmap ? AppColors.neonGrad : null,
          color: _showHeatmap ? null : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: _showHeatmap ? AppColors.primary : AppColors.border,
            width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(
          Icons.layers_rounded,
          color: _showHeatmap ? Colors.white : AppColors.textTertiary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _iconBtn(Icons.menu_rounded, () => _scaffoldKey.currentState?.openDrawer()),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))
                        .then((_) => _fetchUnreadCount());
                    },
                    child: Stack(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: const Icon(Icons.notifications_none_rounded, color: Color(0xFF0F172A), size: 24),
                      ),
                      if (_unreadNotifCount > 0)
                        Positioned(
                          top: 10, right: 10,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9), // Light slate gray background for avatar
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(Icons.person_rounded, color: Color(0xFF64748B), size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: JT.logoBlue(height: 64),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A), size: 24),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName.isNotEmpty ? _userName : 'Arjun Sharma',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '(Active Profile)',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _toggling ? null : _toggleOnline,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 90,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: (_isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: _isOnline ? Alignment.centerLeft : Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            _isOnline ? 'ON' : 'OFF',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Container(
                            width: 36, 
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              color: _isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildNewStatCard(
                  color: const Color(0xFF2D8CFF),
                  icon: Icons.currency_rupee_rounded,
                  value: '₹${_earningsToday.toStringAsFixed(2)}',
                  label: 'Earnings',
                  onTap: () => setState(() => _navIndex = 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNewStatCard(
                  color: const Color(0xFF22C55E),
                  icon: Icons.directions_car_rounded,
                  value: '$_tripsToday',
                  label: 'Trips',
                  onTap: () => setState(() => _navIndex = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNewStatCard(
                  color: const Color(0xFFF59E0B),
                  icon: Icons.star_rounded,
                  value: _driverRating.toStringAsFixed(1),
                  label: 'Rating',
                  onTap: () => setState(() => _navIndex = 4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNewStatCard(
                  color: const Color(0xFF7C3AED),
                  icon: Icons.account_balance_wallet_rounded,
                  value: '₹${_walletBalance.toStringAsFixed(2)}',
                  label: 'Wallet',
                  onTap: () => setState(() => _navIndex = 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildNewVehicleCard(),
        ],
      ),
    );
  }

  Widget _buildNewStatCard({
    required Color color,
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 105,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewVehicleCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46, height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0F2FE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_car_rounded, color: Color(0xFF2D8CFF), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vehicleCategory.isNotEmpty ? _vehicleCategory : 'My Vehicle',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _vehicleNumber.isNotEmpty ? '$_vehicleNumber • $_vehicleModel' : 'AP37DP1235 • Gixxer',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_serviceModules.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _serviceModules.map((module) {
                      final enabled = module['enabled'] == true;
                      final label = module['label']?.toString() ?? 'Service';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: enabled ? JT.primaryLight : JT.bgSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: enabled
                                ? JT.primary.withValues(alpha: 0.25)
                                : JT.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                              color: enabled ? JT.primary : JT.textTertiary,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: GoogleFonts.poppins(
                                color: enabled ? JT.primaryDark : JT.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  if (_serviceModules.any((m) => m['enabled'] != true)) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Parcel / Pool need admin approval after onboarding. Contact support to enable.',
                      style: GoogleFonts.poppins(
                        color: JT.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
                if (_parcelVehicles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _parcelVehicles.map((vehicle) {
                      final name = vehicle['name']?.toString() ?? 'Parcel';
                      final capacity = vehicle['capacityLabel']?.toString() ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: JT.parcelGoldSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: JT.parcelGold.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_rounded, color: JT.parcelGold, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              capacity.isNotEmpty ? '$name - $capacity' : name,
                              style: GoogleFonts.poppins(
                                color: JT.parcelGoldDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0), height: 1.5),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Color(0xFF2D8CFF), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'RC Valid Till • 15 Dec 2025',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            bottom: -5,
            child: const VehicleArtwork(vehicleKey: 'bike', height: 100),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _driverNavItem(Icons.home_rounded, 'Home', 0),
              _driverNavItem(Icons.fork_right_rounded, 'Trips', 1),
              _driverNavItem(Icons.bar_chart_rounded, 'Earnings', 2),
              _driverNavItem(Icons.account_balance_wallet_rounded, 'Wallet', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverNavItem(IconData icon, String label, int index) {
    final active = _navIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _navIndex = index);
        // All tabs handled inline — no Navigator.push needed
      },
      child: Container(
        color: Colors.transparent,
        width: 60,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (active)
              Container(width: 40, height: 3, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: const Color(0xFF2D8CFF), borderRadius: BorderRadius.circular(2)))
            else
              const SizedBox(height: 9),
            Icon(icon, size: 24, color: active ? const Color(0xFF2D8CFF) : const Color(0xFF94A3B8)),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                fontSize: 11,
                color: active ? const Color(0xFF2D8CFF) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D8CFF), Color(0xFF1E6BE6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF2D8CFF).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Text(
                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'P',
                    style: GoogleFonts.poppins(color: const Color(0xFF2D8CFF), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _userName,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+91 $_userPhone',
                    style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      JT.logoWhite(height: 12),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              children: [
                _drawerItem(Icons.grid_view_rounded, 'Dashboard', null, () {
                  Navigator.pop(context);
                  setState(() => _navIndex = 0);
                }),
                _drawerItem(Icons.local_atm_rounded, 'Earnings', '₹${_earningsToday.toStringAsFixed(0)}', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsScreen()));
                }),
                _drawerItem(Icons.route_rounded, 'My Trips', null, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TripsHistoryScreen()));
                }),
                if (_isServiceModuleEnabled('city_pool'))
                  _drawerItem(Icons.directions_car_rounded, 'City Pool Rides', null, () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PoolDriverScreen()));
                  }),
                if (_isServiceModuleEnabled('outstation_pool'))
                  _drawerItem(Icons.alt_route_rounded, 'Outstation Pool', null, () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const OutstationPoolDriverScreen()));
                  }),
                _drawerItem(Icons.account_balance_wallet_rounded, 'Wallet', '₹${_walletBalance.toStringAsFixed(0)}', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                }),
                _drawerItem(Icons.person_outline_rounded, 'Profile', null, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                }),
                _drawerItem(Icons.health_and_safety_outlined, 'Safety & Fatigue', null, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FatigueScreen()));
                }),
                _drawerItem(Icons.headset_mic_outlined, 'Support', null, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverSupportChatScreen()));
                }),
                _drawerItem(Icons.card_giftcard_rounded, 'Refer & Earn', null, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen()));
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: GestureDetector(
              onTap: () async {
                _socket.resetForLogout();
                await AuthService.logout();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFEF4444).withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Logout',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFEF4444),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Center(
              child: Text(
                'v1.0.29 • MindWheel IT Solutions',
                style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, String? badge, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0xFF2D8CFF).withValues(alpha: 0.05),
          highlightColor: const Color(0xFF2D8CFF).withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: const Color(0xFF64748B), size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InlineTripsView extends StatefulWidget {
  const InlineTripsView({super.key});

  @override
  State<InlineTripsView> createState() => _InlineTripsViewState();
}

class _InlineTripsViewState extends State<InlineTripsView> {
  int _tabIndex = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _trips = [];
  Map<String, dynamic> _stats = {'totalEarnings': 0, 'completed': 0, 'cancelled': 0};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.driverTrips),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final list = (data['trips'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        
        // Always calculate local stats from the fetched list for immediate accuracy
        double calcEarnings = 0;
        int calcCompleted = 0;
        int calcCancelled = 0;
        
        for (var t in list) {
          final s = (t['currentStatus'] ?? t['status'] ?? '').toString().toLowerCase();
          if (s == 'completed') {
            calcCompleted++;
            calcEarnings += double.tryParse((t['actualFare'] ?? t['estimatedFare'] ?? 0).toString()) ?? 0;
          } else if (s == 'cancelled') {
            calcCancelled++;
          }
        }

        // Use server provided stats if they exist and are non-zero, otherwise use calculated
        final serverStats = data['stats'] as Map<String, dynamic>?;
        final stats = {
          'totalEarnings': (serverStats?['totalEarnings'] != null && (serverStats!['totalEarnings'] as num) > 0) 
              ? serverStats['totalEarnings'] 
              : calcEarnings,
          'completed': (serverStats?['completed'] != null && (serverStats!['completed'] as num) > 0) 
              ? serverStats['completed'] 
              : calcCompleted,
          'cancelled': (serverStats?['cancelled'] != null && (serverStats!['cancelled'] as num) > 0) 
              ? serverStats['cancelled'] 
              : calcCancelled,
        };

        setState(() {
          _trips = list;
          _stats = stats;
        });
      }
    } catch (e) {
      debugPrint('Error loading inline trips: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month - 1]} · $h:$m $ampm';
    } catch (_) { return ''; }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      case 'ongoing':
      case 'on_the_way': return AppColors.primary;
      case 'accepted':
      case 'driver_assigned': return const Color(0xFF8B5CF6);
      case 'arrived': return const Color(0xFFF59E0B);
      default: return AppColors.textTertiary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'ongoing':
      case 'on_the_way': return 'Ongoing';
      case 'accepted':
      case 'driver_assigned': return 'Assigned';
      case 'arrived': return 'Arrived';
      default: return status.toUpperCase();
    }
  }

  void _showTripDetail(Map<String, dynamic> t) {
    final status = (t['currentStatus'] ?? t['status'] ?? '').toString();
    final fare = double.tryParse((t['actualFare'] ?? t['estimatedFare'] ?? '0').toString()) ?? 0;
    final isPaid = (t['paymentStatus'] ?? '') == 'paid';
    final type = (t['type'] ?? 'ride').toString();
    final statusColor = _statusColor(status);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: statusColor.withValues(alpha: 0.2)),
              ),
              child: Icon(type == 'parcel' ? Icons.inventory_2_rounded : Icons.route_rounded, color: statusColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type == 'parcel' ? 'Parcel Delivery' : 'Ride Request',
                style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
              Text(_formatDate(t['createdAt']?.toString()), style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 12)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(_statusLabel(status), style: GoogleFonts.poppins(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 28),
          _detailRow(Icons.my_location_rounded, 'Pickup', t['pickupAddress']?.toString() ?? '—', AppColors.success),
          const SizedBox(height: 16),
          _detailRow(Icons.location_on_rounded, 'Drop', t['destinationAddress']?.toString() ?? '—', AppColors.error),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              _tripStat('Fare', '₹${fare.toStringAsFixed(0)}', Icons.currency_rupee_rounded, AppColors.success),
              _vDivider(),
              _tripStat('Payment', isPaid ? 'Paid' : (t['paymentMethod']?.toString() ?? 'Cash'), isPaid ? Icons.check_circle_rounded : Icons.payments_rounded, isPaid ? AppColors.success : const Color(0xFFF59E0B)),
              _vDivider(),
              _tripStat('Distance', '${(double.tryParse(t['distanceKm']?.toString() ?? '0') ?? 0).toStringAsFixed(1)} km', Icons.straighten_rounded, AppColors.primary),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Close Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(value, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      ])),
    ]);
  }

  Widget _tripStat(String label, String value, IconData icon, Color color) {
    return Expanded(child: Column(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 8),
      Text(value, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      Text(label, style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w500)),
    ]));
  }

  Widget _vDivider() => Container(width: 1, height: 40, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _buildStatCard(String title, String value, Color bgColor, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: bgColor.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(height: 10),
            Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(title, style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTrips = _trips.where((t) {
      final s = (t['currentStatus'] ?? t['status'] ?? '').toString().toLowerCase();
      if (_tabIndex == 1) return s == 'completed';
      if (_tabIndex == 2) return s == 'cancelled';
      return true;
    }).toList();

    return Container(
      color: Colors.white,
      child: _loading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            onRefresh: _loadData,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Trip Insights', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 26, letterSpacing: -0.8, fontWeight: FontWeight.w700)),
                        GestureDetector(
                          onTap: _loadData,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
                            ),
                            child: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildStatCard('Earnings', '₹${(double.tryParse(_stats['totalEarnings']?.toString() ?? '0') ?? 0).toStringAsFixed(0)}', const Color(0xFF10B981), Icons.currency_rupee_rounded),
                        _buildStatCard('Completed', '${_stats['completed'] ?? '0'}', AppColors.primary, Icons.check_circle_rounded),
                        _buildStatCard('Cancelled', '${_stats['cancelled'] ?? '0'}', AppColors.error, Icons.close_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(25)),
                      child: Row(
                        children: [
                          _buildPillTab('All History', 0),
                          _buildPillTab('Completed', 1),
                          _buildPillTab('Cancelled', 2),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (filteredTrips.isEmpty)
                    _buildEmptyState()
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTrips.length,
                      itemBuilder: (context, index) => _buildTripTile(filteredTrips[index]),
                    ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildTripTile(Map<String, dynamic> trip) {
    final rawStatus = (trip['currentStatus'] ?? trip['status'] ?? 'completed').toString().toLowerCase();
    final statusColor = _statusColor(rawStatus);
    final statusLabel = _statusLabel(rawStatus);
    final isCompleted = rawStatus == 'completed';
    final type = (trip['type'] ?? 'ride').toString();

    return GestureDetector(
      onTap: () => _showTripDetail(trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(type == 'parcel' ? Icons.inventory_2_rounded : Icons.route_rounded, color: statusColor, size: 16),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(statusLabel, style: GoogleFonts.poppins(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  Text(_formatDate(trip['createdAt']?.toString()), style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 11)),
                ]),
                const Spacer(),
                Text('₹${(double.tryParse((trip['actualFare'] ?? trip['estimatedFare'] ?? 0).toString()) ?? 0).toStringAsFixed(0)}', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            _buildLocationRow(Icons.circle, AppColors.success, trip['pickupShortName'] ?? trip['pickupAddress'] ?? 'Pickup'),
            Padding(
              padding: const EdgeInsets.only(left: 7, top: 4, bottom: 4),
              child: Container(width: 1.5, height: 18, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(1))),
            ),
            _buildLocationRow(Icons.location_on_rounded, AppColors.error, trip['destinationShortName'] ?? trip['destinationAddress'] ?? 'Destination'),
            const SizedBox(height: 18),
            const Divider(color: AppColors.border, thickness: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    const Icon(Icons.flash_on_rounded, color: const Color(0xFFF59E0B), size: 12),
                    const SizedBox(width: 6),
                    Text(trip['vehicleCategory']?.toString().toUpperCase() ?? 'RIDE', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textTertiary, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500))),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 400,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 2)),
            child: const Icon(Icons.route_outlined, size: 50, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          Text('No Trips Found', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Your complete trip history\nwill appear right here.', textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textTertiary, height: 1.5, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildPillTab(String label, int index) {
    bool active = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))] : [],
          ),
          child: Text(label, style: GoogleFonts.poppins(color: active ? AppColors.textPrimary : AppColors.textTertiary, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }
}

// ─── Inline Earnings View ──────────────────────────────────────────────────

class InlineEarningsView extends StatefulWidget {
  const InlineEarningsView({super.key});
  @override
  State<InlineEarningsView> createState() => _InlineEarningsViewState();
}

class _InlineEarningsViewState extends State<InlineEarningsView>
    with SingleTickerProviderStateMixin {
  String _period = 'today';
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _weekDays = [];
  double _weekTotal = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final _tabs = [
    {'label': 'Today', 'value': 'today'},
    {'label': 'Week', 'value': 'week'},
    {'label': 'Month', 'value': 'month'},
    {'label': 'All', 'value': 'all'},
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/earnings?period=$_period'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() => _stats = jsonDecode(res.body));
        _fadeCtrl.forward(from: 0);
      }
      final resW = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/weekly-earnings'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (resW.statusCode == 200 && mounted) {
        final d = jsonDecode(resW.body);
        setState(() {
          _weekDays = List<Map<String, dynamic>>.from(d['days'] ?? []);
          _weekTotal = double.tryParse(d['total']?.toString() ?? '0') ?? 0.0;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final net = double.tryParse(_stats['netEarnings']?.toString() ?? '0') ?? 0.0;
    final gross = double.tryParse(_stats['grossFare']?.toString() ?? '0') ?? 0.0;
    final commission = double.tryParse(_stats['commission']?.toString() ?? '0') ?? 0.0;
    final completed = _stats['completedTrips'] ?? 0;
    final cancelled = _stats['cancelledTrips'] ?? 0;
    final maxWeek = _weekDays.isEmpty
        ? 1.0
        : _weekDays.map((d) => (d['gross'] as num).toDouble()).reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ── Hero Balance Card ──
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Net Earnings', style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                          '₹${net.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.5, height: 1.1),
                        ),
                      ]),
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                        child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Period tabs
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: _tabs.map((t) {
                        final active = _period == t['value'];
                        return Expanded(
                          child: GestureDetector(
                            onTap: () { setState(() => _period = t['value']!); _loadData(); },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: active ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)] : [],
                              ),
                              child: Text(t['label']!, textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: active ? const Color(0xFF1E40AF) : Colors.white,
                                  fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                )),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 2.5)),
              )
            else
              FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // ── 4 Stat Cards ──
                      Row(children: [
                        _statChip('Gross Fare', '₹${gross.toStringAsFixed(0)}', Icons.monetization_on_rounded, const Color(0xFFF59E0B), [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)]),
                        const SizedBox(width: 10),
                        _statChip('Commission', '-₹${commission.toStringAsFixed(0)}', Icons.percent_rounded, const Color(0xFFEF4444), [const Color(0xFFFEF2F2), const Color(0xFFFEE2E2)]),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _statChip('Completed', '$completed trips', Icons.check_circle_rounded, const Color(0xFF10B981), [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]),
                        const SizedBox(width: 10),
                        _statChip('Cancelled', '$cancelled trips', Icons.cancel_rounded, const Color(0xFF8B5CF6), [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)]),
                      ]),
                      const SizedBox(height: 16),

                      // ── Weekly Bar Chart ──
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Weekly Overview', style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w700)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)]),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('₹${_weekTotal.toStringAsFixed(0)}', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          const SizedBox(height: 24),
                          if (_weekDays.isEmpty)
                            Center(child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text('No weekly data', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 13)),
                            ))
                          else
                            SizedBox(
                              height: 130,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: _weekDays.map((d) {
                                  final val = (d['gross'] as num).toDouble();
                                  final frac = val / maxWeek;
                                  final today = DateTime.now();
                                  final isToday = d['date'] == today.toIso8601String().substring(0, 10);
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                        if (val > 0)
                                          Text('₹${val.toInt()}', style: GoogleFonts.poppins(color: isToday ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8), fontSize: 8, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: (frac * 90).clamp(4.0, 90.0),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: isToday
                                                  ? [const Color(0xFF60A5FA), const Color(0xFF1E40AF)]
                                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                            ),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                            boxShadow: isToday ? [BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.3), blurRadius: 6)] : [],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(d['day'] as String, style: GoogleFonts.poppins(color: isToday ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8), fontSize: 10, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
                                      ]),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon, Color color, List<Color> gradients) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
        decoration: BoxDecoration(
          color: color, // fully solid vibrant background
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─── Inline Wallet View ───────────────────────────────────────────────────

class InlineWalletView extends StatefulWidget {
  const InlineWalletView({super.key});
  @override
  State<InlineWalletView> createState() => _InlineWalletViewState();
}

class _InlineWalletViewState extends State<InlineWalletView> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _wallet;
  bool _loading = true;
  late TabController _tabController;
  late Razorpay _razorpay;
  double _pendingAmount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _fetchWallet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _fetchWallet() async {
    if (mounted) setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.driverWallet), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() { _wallet = jsonDecode(res.body); _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    _showSnack('Processing payment...', error: false);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/wallet/verify-payment'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'razorpayOrderId': response.orderId, 'razorpayPaymentId': response.paymentId, 'razorpaySignature': response.signature, 'amount': _pendingAmount}),
      ).timeout(const Duration(seconds: 20));
      if ((res.statusCode == 200 || res.statusCode == 409) && mounted) {
        final data = jsonDecode(res.body);
        _showSnack('₹${_pendingAmount.toInt()} added! New balance: ₹${data['newBalance']?.toStringAsFixed(2) ?? ''}');
        _fetchWallet();
      }
    } catch (_) {}
  }

  void _onPaymentError(PaymentFailureResponse r) { if (r.code != 0) _showSnack('Payment failed', error: true); }
  void _onExternalWallet(ExternalWalletResponse r) {}

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _initiateRecharge(double amount) async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/app/driver/wallet/create-order'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) { _showSnack('Failed to create payment order.', error: true); return; }
      final data = jsonDecode(res.body);
      final keyId = data['keyId']?.toString() ?? '';
      if (keyId.isEmpty || !keyId.startsWith('rzp_')) {
        _showSnack('Payment setup failed. Try again.', error: true);
        return;
      }
      _pendingAmount = amount;
      _razorpay.open({
        'key': keyId,
        'amount': data['order']['amount'],
        'currency': 'INR',
        'order_id': data['order']['id'],
        'name': 'JAGO Pro Pilot',
        'description': 'Wallet Recharge ₹${amount.toInt()}',
        'timeout': 300,
        'theme': {'color': '#2D8CFF'},
      });
    } catch (e) { _showSnack('Payment error: $e', error: true); }
  }

  void _showRechargeSheet() {
    double selectedAmount = 200;
    bool isCustom = false;
    final customCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Recharge Wallet', style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Current: ₹${(_wallet?['walletBalance'] ?? 0).toStringAsFixed(2)}', style: GoogleFonts.poppins(color: const Color(0xFF64748B), fontSize: 13)),
            const SizedBox(height: 20),
            Text('SELECT AMOUNT', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final amt in [100.0, 200.0, 500.0, 1000.0])
                GestureDetector(
                  onTap: () => setSheet(() { selectedAmount = amt; isCustom = false; customCtrl.clear(); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      color: (!isCustom && selectedAmount == amt) ? const Color(0xFF2D8CFF) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: (!isCustom && selectedAmount == amt) ? [BoxShadow(color: const Color(0xFF2D8CFF).withValues(alpha: 0.3), blurRadius: 8)] : [],
                    ),
                    child: Text('₹${amt.toInt()}', style: GoogleFonts.poppins(color: (!isCustom && selectedAmount == amt) ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              GestureDetector(
                onTap: () => setSheet(() => isCustom = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(color: isCustom ? const Color(0xFFFFF7ED) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(26), border: Border.all(color: isCustom ? const Color(0xFFF59E0B) : Colors.transparent)),
                  child: Text('Custom', style: GoogleFonts.poppins(color: isCustom ? const Color(0xFFF59E0B) : const Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ]),
            if (isCustom) ...[
              const SizedBox(height: 14),
              TextField(
                controller: customCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (v) => setSheet(() => selectedAmount = double.tryParse(v) ?? 0),
                style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter amount',
                  hintStyle: GoogleFonts.poppins(color: const Color(0xFFCBD5E1)),
                  prefixText: '₹ ',
                  prefixStyle: GoogleFonts.poppins(color: const Color(0xFF2D8CFF), fontWeight: FontWeight.w600),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: const Color(0xFF2D8CFF), width: 1.5)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: selectedAmount < 1 ? null : () { Navigator.pop(ctx); _initiateRecharge(selectedAmount); },
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2D8CFF), Color(0xFF1E40AF)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xFF2D8CFF).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Center(child: Text('Pay ₹${selectedAmount.toInt()} via Razorpay', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = double.tryParse((_wallet?['walletBalance'] ?? _wallet?['balance'])?.toString() ?? '0') ?? 0.0;
    final isLocked = _wallet?['isLocked'] ?? false;
    final history = (_wallet?['history'] ?? _wallet?['transactions'] ?? []) as List;
    final withdrawals = (_wallet?['withdrawRequests'] ?? []) as List;
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // ── Compact Hero Balance Card ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF065F46), Color(0xFF10B981), Color(0xFF34D399)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(children: [
              // Top row: icon + balance
              Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                  child: Icon(isLocked ? Icons.lock_rounded : Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isLocked ? 'Account Locked' : 'Available Balance',
                    style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w500)),
                  Text('₹${balance.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1)),
                ])),
                GestureDetector(
                  onTap: () { setState(() => _loading = true); _fetchWallet(); },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              // Action buttons
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showRechargeSheet,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)]),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_circle_rounded, color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 6),
                        Text('Recharge', style: GoogleFonts.poppins(color: const Color(0xFF10B981), fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
                if (!isLocked && balance >= 100) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.5))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text('Withdraw', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ],
              ]),
              if (isLocked) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 7),
                    Expanded(child: Text('Recharge to unlock and go online.', style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500))),
                  ]),
                ),
              ],
            ]),
          ),

          // ── Quick Stats ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _walletStat('This Month', '₹0', const Color(0xFF3B82F6), Icons.calendar_month_rounded),
              const SizedBox(width: 10),
              _walletStat('Total Recharge', '₹0', const Color(0xFF8B5CF6), Icons.add_card_rounded),
              const SizedBox(width: 10),
              _walletStat('Withdrawn', '₹0', const Color(0xFFF59E0B), Icons.payment_rounded),
            ]),
          ),

          // ── Tab Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: const Color(0xFF0F172A),
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [Tab(text: 'Transactions'), Tab(text: 'Withdrawals')],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Tab Content ──
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 2.5)))
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Transactions
                  history.isEmpty
                    ? _emptyState(icon: Icons.receipt_long_rounded, title: 'No transactions yet', subtitle: 'Your recharges and ride earnings will appear here', color: const Color(0xFF3B82F6))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: history.length,
                        itemBuilder: (_, i) => _txnTile(history[i] as Map<String, dynamic>),
                      ),
                  // Withdrawals
                  withdrawals.isEmpty
                    ? _emptyState(icon: Icons.account_balance_rounded, title: 'No withdrawals yet', subtitle: 'Your withdrawal requests will appear here', color: const Color(0xFFF59E0B))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: withdrawals.length,
                        itemBuilder: (_, i) => _withdrawTile(withdrawals[i] as Map<String, dynamic>),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _walletStat(String label, String value, Color color, IconData icon) {
    final history = (_wallet?['history'] ?? _wallet?['transactions'] ?? []) as List;
    final withdrawals = (_wallet?['withdrawRequests'] ?? []) as List;
    final now = DateTime.now();

    double amountOf(dynamic raw) =>
        double.tryParse(raw?.toString() ?? '0') ?? 0;

    DateTime? parseDate(dynamic raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString());

    bool isSameMonth(DateTime? date) =>
        date != null && date.year == now.year && date.month == now.month;

    String resolvedValue = value;
    if (label == 'This Month') {
      final total = history.fold<double>(0, (sum, item) {
        final tx = Map<String, dynamic>.from(item as Map);
        final date = parseDate(tx['created_at'] ?? tx['date'] ?? tx['createdAt']);
        if (!isSameMonth(date)) return sum;
        final type = (tx['transaction_type'] ?? tx['type'] ?? '')
            .toString()
            .toLowerCase();
        final account = (tx['account'] ?? tx['description'] ?? '')
            .toString()
            .toLowerCase();
        final credit = amountOf(tx['credit']);
        final amount = amountOf(tx['amount']);
        final earned = credit > 0 ? credit : amount;
        final looksLikeEarning = type.contains('trip_earning') ||
            account.contains('trip earning') ||
            account.contains('ride earning');
        return looksLikeEarning ? sum + earned : sum;
      });
      resolvedValue = '₹${total.toStringAsFixed(0)}';
    } else if (label == 'Total Recharge') {
      final total = history.fold<double>(0, (sum, item) {
        final tx = Map<String, dynamic>.from(item as Map);
        final type = (tx['transaction_type'] ?? tx['type'] ?? '')
            .toString()
            .toLowerCase();
        final account = (tx['account'] ?? tx['description'] ?? '')
            .toString()
            .toLowerCase();
        final credit = amountOf(tx['credit']);
        final amount = amountOf(tx['amount']);
        final recharge = credit > 0 ? credit : amount;
        final looksLikeRecharge = type.contains('wallet_recharge') ||
            account.contains('wallet recharge') ||
            account.contains('recharge');
        return looksLikeRecharge ? sum + recharge : sum;
      });
      resolvedValue = '₹${total.toStringAsFixed(0)}';
    } else if (label == 'Withdrawn') {
      final total = withdrawals.fold<double>(0, (sum, item) {
        final row = Map<String, dynamic>.from(item as Map);
        return sum + amountOf(row['amount']);
      });
      resolvedValue = '₹${total.toStringAsFixed(0)}';
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 14)),
          const SizedBox(height: 6),
          Text(resolvedValue, style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w700)),
          Text(label, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _txnTile(Map<String, dynamic> txn) {
    final isCredit = (txn['type'] ?? '').toString().toLowerCase().contains('credit') ||
        (txn['amount'] ?? 0) > 0;
    final color = isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final amt = (double.tryParse(txn['amount']?.toString() ?? '0') ?? 0.0).abs();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)]),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(txn['description'] ?? txn['type'] ?? 'Transaction', style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
          Text(txn['date'] ?? '', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 11)),
        ])),
        Text('${isCredit ? '+' : '-'}₹${amt.toStringAsFixed(2)}', style: GoogleFonts.poppins(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _withdrawTile(Map<String, dynamic> wd) {
    final status = wd['status'] ?? 'pending';
    final Color statusColor = status == 'completed' ? const Color(0xFF10B981) : status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final amt = double.tryParse(wd['amount']?.toString() ?? '0') ?? 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(Icons.account_balance_rounded, color: statusColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('₹${amt.toStringAsFixed(2)} Withdrawal', style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600)),
          Text(wd['method'] ?? 'bank', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(status.toUpperCase(), style: GoogleFonts.poppins(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
      ]),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle, required Color color}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.2))),
            child: Icon(icon, color: color, size: 36)),
          const SizedBox(height: 20),
          Text(title, style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 13, height: 1.5)),
        ]),
      ),
    );
  }
}

class InlineRatingsView extends StatefulWidget {
  final double rating;
  const InlineRatingsView({super.key, required this.rating});

  @override
  State<InlineRatingsView> createState() => _InlineRatingsViewState();
}

class _InlineRatingsViewState extends State<InlineRatingsView> {
  bool _loading = true;
  List<Map<String, dynamic>> _feedbacks = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.performance), headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _feedbacks = (data['feedbacks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2D8CFF), Color(0xFF1A50D0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D8CFF).withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(children: [
                  Text(
                    'Overall Rating',
                    style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      widget.rating.toStringAsFixed(1),
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700, height: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 4),
                      child: Text('/ 5.0', style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return Icon(
                        i < widget.rating.floor() ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 24,
                      );
                    }),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Recent Feedback',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF2D8CFF))))
          else if (_feedbacks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle),
                    child: const Icon(Icons.star_outline_rounded, color: Color(0xFF94A3B8), size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('No ratings yet', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('Your customer reviews will appear here', style: GoogleFonts.poppins(color: const Color(0xFF64748B), fontSize: 13)),
                  const SizedBox(height: 100), // Push up for visual balance
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _feedbackTile(_feedbacks[index]),
                  childCount: _feedbacks.length,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  Widget _feedbackTile(Map<String, dynamic> f) {
    final stars = int.tryParse(f['rating']?.toString() ?? '5') ?? 5;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(f['customerName'] ?? 'Verified Rider', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B))),
          Row(children: List.generate(5, (i) => Icon(Icons.star_rounded, color: i < stars ? Colors.amber : const Color(0xFFE2E8F0), size: 14))),
        ]),
        const SizedBox(height: 8),
        if ((f['comment'] ?? '').isNotEmpty)
          Text('"${f['comment']}"', style: GoogleFonts.poppins(color: const Color(0xFF475569), fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
        const SizedBox(height: 10),
        Text(f['date'] ?? 'Just now', style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 11)),
      ]),
    );
  }
}
