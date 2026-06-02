import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../home/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JAGO Driver — Parcel Delivery Screen
// Stages: navigating_pickup → verify_pickup_otp → navigating_drop → verify_drop_otp → completed
// Supports multi-drop (Porter-style)
// ─────────────────────────────────────────────────────────────────────────────

enum _ParcelStage {
  navigatingToPickup,
  atPickup,
  navigatingToDrop,
  atDrop,
  completed,
}

class ParcelDeliveryScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const ParcelDeliveryScreen({super.key, required this.order});

  @override
  State<ParcelDeliveryScreen> createState() => _ParcelDeliveryScreenState();
}

class _ParcelDeliveryScreenState extends State<ParcelDeliveryScreen>
    with SingleTickerProviderStateMixin {

  final SocketService _socket = SocketService();
  final _otpCtrl = TextEditingController();
  late AnimationController _pulseCtrl;
  Timer? _locationTimer;

  _ParcelStage _stage = _ParcelStage.navigatingToPickup;
  bool _loading = false;

  late Map<String, dynamic> _order;
  late List<Map<String, dynamic>> _drops;
  int _dropIdx = 0;
  double _driverEarnings = 0;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    final raw = _order['drop_locations'];
    if (raw is List) {
      _drops = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (raw is String) {
      final decoded = jsonDecode(raw);
      _drops = (decoded as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _drops = [];
    }
    _dropIdx = (_order['current_drop_index'] as int?) ?? 0;

    // Restore stage if order was already in transit (driver resumed app)
    final status = _order['current_status']?.toString() ?? 'driver_assigned';
    if (status == 'in_transit') {
      _stage = _dropIdx < _drops.length
          ? _ParcelStage.navigatingToDrop
          : _ParcelStage.completed;
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _socket.connect(ApiConfig.socketUrl);
    _startLocationUpdates();

    // Auto-navigate to pickup on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNavigation());
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _pulseCtrl.dispose();
    _locationTimer?.cancel();
    _socket.disconnect();
    super.dispose();
  }

  String get _orderId => _order['id']?.toString() ?? '';

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (_socket.isConnected) {
          _socket.sendLocation(lat: pos.latitude, lng: pos.longitude);
        }
      } catch (_) {}
    });
  }

  void _openNavigation() {
    double lat, lng;
    String label;
    if (_stage == _ParcelStage.navigatingToPickup ||
        _stage == _ParcelStage.atPickup) {
      lat = double.tryParse(_order['pickup_lat']?.toString() ?? '0') ?? 0;
      lng = double.tryParse(_order['pickup_lng']?.toString() ?? '0') ?? 0;
      label = Uri.encodeComponent(_order['pickup_address'] ?? 'Pickup');
    } else {
      final drop = _drops.isNotEmpty ? _drops[_dropIdx] : null;
      lat = double.tryParse(drop?['lat']?.toString() ?? '0') ?? 0;
      lng = double.tryParse(drop?['lng']?.toString() ?? '0') ?? 0;
      label = Uri.encodeComponent(drop?['address'] ?? 'Drop');
    }
    if (lat == 0 && lng == 0) return;
    launchUrl(
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => launchUrl(
      Uri.parse('https://maps.google.com/?daddr=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    ));
    debugPrint('navigate to $label');
  }

  Future<void> _verifyPickupOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) { _showSnack('Enter 4-digit pickup OTP', error: true); return; }
    setState(() => _loading = true);
    try {
      final hdrs = await AuthService.getHeaders();
      hdrs['Content-Type'] = 'application/json';
      final r = await http.post(
        Uri.parse(ApiConfig.driverParcelPickupOtp(_orderId)),
        headers: hdrs,
        body: jsonEncode({'otp': otp}),
      );
      if (r.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _otpCtrl.clear();
        setState(() {
          _stage = _drops.isNotEmpty
              ? _ParcelStage.navigatingToDrop
              : _ParcelStage.completed;
        });
        if (_stage == _ParcelStage.navigatingToDrop) {
          _openNavigation();
        }
      } else {
        final e = jsonDecode(r.body);
        _showSnack(e['message'] ?? 'Wrong OTP', error: true);
      }
    } catch (_) {
      _showSnack('Network error', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verifyDropOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) { _showSnack('Enter 4-digit delivery OTP', error: true); return; }
    setState(() => _loading = true);
    try {
      final hdrs = await AuthService.getHeaders();
      hdrs['Content-Type'] = 'application/json';
      final r = await http.post(
        Uri.parse(ApiConfig.driverParcelDropOtp(_orderId)),
        headers: hdrs,
        body: jsonEncode({'dropIndex': _dropIdx, 'otp': otp}),
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        HapticFeedback.heavyImpact();
        _otpCtrl.clear();
        final allDelivered = data['allDelivered'] == true;
        if (allDelivered) {
          final fare = double.tryParse(_order['total_fare']?.toString() ?? '0') ?? 0;
          setState(() {
            _stage = _ParcelStage.completed;
            _driverEarnings = fare * 0.85; // 15% commission
          });
        } else {
          setState(() {
            _dropIdx++;
            _stage = _ParcelStage.navigatingToDrop;
          });
          _openNavigation();
        }
      } else {
        final e = jsonDecode(r.body);
        _showSnack(e['message'] ?? 'Wrong OTP', error: true);
      }
    } catch (_) {
      _showSnack('Network error', error: true);
    }
    if (mounted) setState(() => _loading = false);
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

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JT.bg,
      appBar: AppBar(
        backgroundColor: JT.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: JT.textPrimary, size: 18),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Leave Delivery?', style: GoogleFonts.poppins(fontWeight: FontWeight.w400)),
              content: Text('You can return to this delivery from your home screen.', style: GoogleFonts.poppins(fontSize: 14)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: JT.error),
                  onPressed: () { Navigator.pop(context); _goHome(); },
                  child: const Text('Leave', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          _stage == _ParcelStage.completed ? 'Delivery Complete!' : 'Parcel Delivery',
          style: GoogleFonts.poppins(color: JT.textPrimary, fontWeight: FontWeight.w400, fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: JT.grad,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '₹${_order['total_fare'] ?? 0}',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w400, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: _stage == _ParcelStage.completed
          ? _buildCompletedView()
          : Column(children: [
              _buildProgressBar(),
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _buildPackageSummary(),
                  const SizedBox(height: 16),
                  if (_stage == _ParcelStage.navigatingToPickup) _buildNavigatingToPickup(),
                  if (_stage == _ParcelStage.atPickup) _buildAtPickup(),
                  if (_stage == _ParcelStage.navigatingToDrop) _buildNavigatingToDrop(),
                  if (_stage == _ParcelStage.atDrop) _buildAtDrop(),
                  const SizedBox(height: 24),
                ]),
              )),
            ]),
    );
  }

  // ── Progress Bar ──────────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    final steps = ['Pickup', ...List.generate(_drops.length, (i) => 'Drop ${i + 1}'), 'Done'];
    int currentStep = 0;
    if (_stage == _ParcelStage.atPickup) currentStep = 0;
    else if (_stage == _ParcelStage.navigatingToDrop || _stage == _ParcelStage.atDrop) currentStep = _dropIdx + 1;
    else if (_stage == _ParcelStage.completed) currentStep = steps.length - 1;

    return Container(
      color: JT.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Step ${currentStep + 1} of ${steps.length}',
          style: GoogleFonts.poppins(fontSize: 11, color: JT.textSecondary)),
        const SizedBox(height: 6),
        Row(children: List.generate(steps.length, (i) {
          final done = i < currentStep;
          final active = i == currentStep;
          return Expanded(child: Row(children: [
            Expanded(child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: done ? JT.success : active ? JT.primary : JT.border,
              ),
            )),
            if (i < steps.length - 1) const SizedBox(width: 4),
          ]));
        })),
        const SizedBox(height: 4),
        Text(steps[currentStep],
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: JT.primary)),
      ]),
    );
  }

  // ── Package Summary Card ──────────────────────────────────────────────────
  Widget _buildPackageSummary() {
    final vehicleType = _order['vehicle_category']?.toString() ?? 'bike_parcel';
    final vehicleEmoji = vehicleType.contains('pickup') ? '🛻'
        : vehicleType.contains('tata') || vehicleType.contains('mini') ? '🚛' : '🏍️';
    final vehicleName = vehicleType.contains('pickup') ? 'Pickup Truck'
        : vehicleType.contains('tata') || vehicleType.contains('mini') ? 'Mini Truck' : 'Bike Parcel';
    final weight = _order['weight_kg']?.toString() ?? '';
    final stops = _drops.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JT.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JT.border),
        boxShadow: JT.cardShadow,
      ),
      child: Column(children: [
        Row(children: [
          Text(vehicleEmoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vehicleName,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w400, color: JT.textPrimary)),
            Text('$stops stop${stops != 1 ? 's' : ''}${weight.isNotEmpty ? ' · $weight kg' : ''}',
              style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${_order['total_fare'] ?? 0}',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500, color: JT.primary)),
            Text('Total Fare', style: GoogleFonts.poppins(fontSize: 10, color: JT.textSecondary)),
          ]),
        ]),
        if (_order['notes']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 14, color: JT.warning),
            const SizedBox(width: 6),
            Expanded(child: Text(_order['notes'].toString(),
              style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary))),
          ]),
        ],
      ]),
    );
  }

  // ── Stage: Navigating to Pickup ───────────────────────────────────────────
  Widget _buildNavigatingToPickup() {
    return Column(children: [
      _buildAddressCard(
        icon: Icons.store_rounded,
        color: JT.success,
        label: 'Pickup Location',
        address: _order['pickup_address']?.toString() ?? '',
        subtitle: _order['pickup_contact_name'] != null
            ? '${_order['pickup_contact_name']} · ${_order['pickup_contact_phone'] ?? ''}'
            : null,
      ),
      const SizedBox(height: 16),
      _buildNavigateButton(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _stage = _ParcelStage.atPickup),
          icon: const Icon(Icons.check_circle_rounded),
          label: Text('Arrived at Pickup', style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: JT.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]);
  }

  // ── Stage: At Pickup — OTP ────────────────────────────────────────────────
  Widget _buildAtPickup() {
    return Column(children: [
      _buildAddressCard(
        icon: Icons.store_rounded,
        color: JT.success,
        label: 'Pickup Location',
        address: _order['pickup_address']?.toString() ?? '',
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JT.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JT.primary.withValues(alpha: 0.3)),
          boxShadow: JT.cardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JT.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_open_rounded, color: JT.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enter Pickup OTP', style: GoogleFonts.poppins(
                fontWeight: FontWeight.w400, fontSize: 15, color: JT.textPrimary)),
              Text('Get OTP from sender', style: GoogleFonts.poppins(
                fontSize: 12, color: JT.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28, fontWeight: FontWeight.w500,
              letterSpacing: 12, color: JT.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • •',
              hintStyle: GoogleFonts.poppins(fontSize: 24, color: JT.border, letterSpacing: 8),
              filled: true,
              fillColor: JT.bgSoft,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: JT.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyPickupOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: JT.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Verify & Pickup Parcel', style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Stage: Navigating to Drop ─────────────────────────────────────────────
  Widget _buildNavigatingToDrop() {
    final drop = _dropIdx < _drops.length ? _drops[_dropIdx] : null;
    if (drop == null) return const SizedBox.shrink();
    return Column(children: [
      if (_drops.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: JT.grad,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Stop ${_dropIdx + 1} of ${_drops.length}',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ),
      _buildAddressCard(
        icon: Icons.flag_rounded,
        color: JT.warning,
        label: 'Drop Location',
        address: drop['address']?.toString() ?? '',
        subtitle: drop['receiverName'] != null
            ? '${drop['receiverName']} · ${drop['receiverPhone'] ?? ''}'
            : null,
      ),
      const SizedBox(height: 16),
      _buildNavigateButton(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _stage = _ParcelStage.atDrop),
          icon: const Icon(Icons.check_circle_rounded),
          label: Text('Arrived at Drop', style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: JT.warning,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]);
  }

  // ── Stage: At Drop — OTP ──────────────────────────────────────────────────
  Widget _buildAtDrop() {
    final drop = _dropIdx < _drops.length ? _drops[_dropIdx] : null;
    if (drop == null) return const SizedBox.shrink();
    return Column(children: [
      _buildAddressCard(
        icon: Icons.flag_rounded,
        color: JT.warning,
        label: 'Delivering To',
        address: drop['address']?.toString() ?? '',
        subtitle: drop['receiverName'] != null
            ? '${drop['receiverName']} · ${drop['receiverPhone'] ?? ''}'
            : null,
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JT.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JT.warning.withValues(alpha: 0.4)),
          boxShadow: JT.cardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JT.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.lock_open_rounded, color: JT.warning, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enter Delivery OTP', style: GoogleFonts.poppins(
                fontWeight: FontWeight.w400, fontSize: 15, color: JT.textPrimary)),
              Text('Get OTP from receiver', style: GoogleFonts.poppins(
                fontSize: 12, color: JT.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28, fontWeight: FontWeight.w500,
              letterSpacing: 12, color: JT.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • •',
              hintStyle: GoogleFonts.poppins(fontSize: 24, color: JT.border, letterSpacing: 8),
              filled: true,
              fillColor: JT.bgSoft,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: JT.warning, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyDropOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: JT.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _dropIdx + 1 < _drops.length ? 'Confirm Delivery → Next Stop' : 'Complete Delivery',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Stage: Completed ──────────────────────────────────────────────────────
  Widget _buildCompletedView() {
    final fare = double.tryParse(_order['total_fare']?.toString() ?? '0') ?? 0;
    final earnings = _driverEarnings > 0 ? _driverEarnings : fare * 0.85;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: JT.grad,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: JT.primary.withValues(alpha: 0.35), blurRadius: 32)],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 28),
          Text('Delivery Complete!',
            style: GoogleFonts.poppins(
              fontSize: 26, fontWeight: FontWeight.w500, color: JT.textPrimary)),
          const SizedBox(height: 8),
          Text('All ${_drops.length} stop${_drops.length != 1 ? 's' : ''} delivered successfully.',
            style: GoogleFonts.poppins(fontSize: 14, color: JT.textSecondary),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: JT.grad,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: JT.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Earnings', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                Text('₹${earnings.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Order Fare', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                Text('₹${fare.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
              ]),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _goHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: JT.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Back to Home', style: GoogleFonts.poppins(fontWeight: FontWeight.w400, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Shared Widgets ────────────────────────────────────────────────────────
  Widget _buildAddressCard({
    required IconData icon,
    required Color color,
    required String label,
    required String address,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JT.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: JT.cardShadow,
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: JT.textSecondary, fontWeight: FontWeight.w400)),
          Text(address,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: JT.textPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle,
              style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  Widget _buildNavigateButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openNavigation,
        icon: const Icon(Icons.navigation_rounded),
        label: Text('Navigate with Google Maps',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 14)),
        style: OutlinedButton.styleFrom(
          foregroundColor: JT.primary,
          side: const BorderSide(color: JT.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
