import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';

class CarSharingScreen extends StatefulWidget {
  const CarSharingScreen({super.key});

  @override
  State<CarSharingScreen> createState() => _CarSharingScreenState();
}

class _CarSharingScreenState extends State<CarSharingScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFF8FAFC);
  static const _blue = JT.primary;
  static const _green = Color(0xFF10B981);

  late TabController _tabs;
  bool _loading = true;
  bool _myLoading = true;
  List _rides = [];
  List _myBookings = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadRides();
    _loadMyBookings();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static String _generateIdempotencyKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${bytes.sublist(0,4).map(hex).join()}-${bytes.sublist(4,6).map(hex).join()}-${bytes.sublist(6,8).map(hex).join()}-${bytes.sublist(8,10).map(hex).join()}-${bytes.sublist(10,16).map(hex).join()}';
  }

  Future<void> _loadRides() async {
    if (mounted) setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/app/customer/car-sharing/rides'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        setState(() => _rides = jsonDecode(res.body)['data'] ?? []);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load rides. Pull to refresh.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network error. Pull to refresh.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMyBookings() async {
    if (mounted) setState(() => _myLoading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.carSharingMyBookings),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        setState(() => _myBookings = jsonDecode(res.body)['data'] ?? []);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load bookings. Pull to refresh.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network error. Pull to refresh.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _myLoading = false);
  }

  Future<void> _cancelCarSharingBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Your seat will be released. Refund (if applicable) will be credited to your wallet within 24 hours.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse(ApiConfig.carSharingCancelBooking(bookingId)),
        headers: {...headers, 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final refund = data['refundAmount'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(refund != null ? 'Cancelled. ₹${refund.toString()} refund initiated.' : 'Booking cancelled.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        _loadMyBookings();
      } else {
        final msg = (jsonDecode(res.body) as Map<String, dynamic>)['message']?.toString() ?? 'Could not cancel.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Network error. Please try again.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _book(
    String rideId,
    String from,
    String to,
    double seatPrice,
    int maxSeats,
  ) async {
    int selectedSeats = 1;
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Confirm Pool Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Route: $from -> $to',
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 4),
              Text(
                'Fare: Rs ${seatPrice.toStringAsFixed(0)} / seat',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select seats',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _seatButton(
                    icon: Icons.remove_rounded,
                    enabled: selectedSeats > 1,
                    onTap: () => setDialogState(() => selectedSeats--),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedSeats seat${selectedSeats == 1 ? '' : 's'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _seatButton(
                    icon: Icons.add_rounded,
                    enabled: selectedSeats < maxSeats,
                    onTap: () => setDialogState(() => selectedSeats++),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Total: Rs ${(seatPrice * selectedSeats).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _blue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Amount will be deducted from your wallet.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedSeats),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: Text(
                'Book $selectedSeats Seat${selectedSeats == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    try {
      final headers = await AuthService.getHeaders();
      final idempotencyKey = _generateIdempotencyKey();
      final bookRes = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/app/customer/car-sharing/book'),
        headers: {...headers, 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey},
        body: jsonEncode({'rideId': rideId, 'seatsBooked': res, 'idempotencyKey': idempotencyKey}),
      ).timeout(const Duration(seconds: 15));
      final d = jsonDecode(bookRes.body);
      if (!mounted) return;
      if (bookRes.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(d['message'] ?? 'Booking confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRides();
        _loadMyBookings();
        _tabs.animateTo(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(d['message'] ?? 'Booking failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network error. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _seatButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: enabled ? _blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: enabled ? Colors.white : Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _blue,
        elevation: 0.5,
        title: const Text(
          'City Pool',
          style: TextStyle(fontWeight: FontWeight.w400, fontSize: 18),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: _blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _blue,
          tabs: const [
            Tab(text: 'Available Rides'),
            Tab(text: 'My Bookings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildRidesList(),
          _buildMyBookings(),
        ],
      ),
    );
  }

  Widget _buildRidesList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: JT.primary));
    }
    if (_rides.isEmpty) {
      return _empty(
        'No city pool rides available',
        'CAR',
        'Check back later or post your own!',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRides,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rides.length,
        itemBuilder: (_, i) => _rideCard(_rides[i]),
      ),
    );
  }

  Widget _buildMyBookings() {
    if (_myLoading) {
      return const Center(child: CircularProgressIndicator(color: JT.primary));
    }
    if (_myBookings.isEmpty) {
      return _empty(
        'No bookings yet',
        'TICKET',
        'Book a seat on an available shared ride!',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMyBookings,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _myBookings.length,
        itemBuilder: (_, i) => _bookingCard(_myBookings[i]),
      ),
    );
  }

  Widget _rideCard(Map d) {
    final from = d['fromLocation'] ?? 'From';
    final to = d['toLocation'] ?? 'To';
    final driver = d['driverName'] ?? 'Driver';
    final vehicle = d['vehicleName'] ?? 'Vehicle';
    final available = d['availableSeats'] ?? 0;
    final seatPrice = double.tryParse(d['seatPrice']?.toString() ?? '0') ?? 0.0;
    final depTime = d['departureTime'] != null ? _fmt(d['departureTime']) : '--';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_rounded, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$from -> $to',
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Rs ${seatPrice.toStringAsFixed(0)}/seat',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(driver,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(width: 12),
              const Icon(Icons.directions_car_rounded,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(vehicle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(depTime,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: available > 0
                      ? _blue.withValues(alpha: 0.08)
                      : Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$available seats left',
                  style: TextStyle(
                    color: available > 0 ? _blue : Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (available > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: () => _book(
                  d['id'],
                  from.toString(),
                  to.toString(),
                  seatPrice,
                  int.tryParse(available.toString()) ?? 1,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Book Seats',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _bookingCard(Map d) {
    final from = d['fromLocation'] ?? 'From';
    final to = d['toLocation'] ?? 'To';
    final seats = d['seatsBooked'] ?? 1;
    final total = double.tryParse(d['totalFare']?.toString() ?? '0') ?? 0.0;
    final status = (d['status'] ?? 'confirmed').toString();
    final depTime = d['departureTime'] != null ? _fmt(d['departureTime']) : '--';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '$from -> $to',
                style:
                    const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
              ),
            ),
            _statusPill(status),
          ]),
          const SizedBox(height: 8),
          Text(
            '$seats seat(s) - Rs ${total.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Departure: $depTime',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (status.toLowerCase() == 'confirmed') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _trackDriver((d['id'] ?? d['bookingId'] ?? '').toString()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JT.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Track Driver', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelCarSharingBooking(
                    (d['id'] ?? d['bookingId'] ?? '').toString()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 0.8),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel Booking', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final s = status.toLowerCase();
    final Color color;
    if (s == 'confirmed') {
      color = _green;
    } else if (s == 'cancelled' || s == 'canceled') {
      color = Colors.red;
    } else if (s == 'completed') {
      color = _blue;
    } else {
      color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _trackDriver(String bookingId) async {
    if (bookingId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PoolDriverTrackSheet(bookingId: bookingId),
    );
  }

  Widget _empty(String title, String asciiBadge, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Text(
                asciiBadge,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '--';
    return s;
  }
}

class _PoolDriverTrackSheet extends StatefulWidget {
  final String bookingId;
  const _PoolDriverTrackSheet({required this.bookingId});

  @override
  State<_PoolDriverTrackSheet> createState() => _PoolDriverTrackSheetState();
}

class _PoolDriverTrackSheetState extends State<_PoolDriverTrackSheet> {
  Timer? _poll;
  Map<String, dynamic>? _loc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.carSharingDriverLocation(widget.bookingId)),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _loc = data['location'] is Map
              ? Map<String, dynamic>.from(data['location'] as Map)
              : null;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _loc?['driverName']?.toString() ?? 'Driver';
    final phone = _loc?['driverPhone']?.toString() ?? '';
    final vehicle = _loc?['vehicleName']?.toString() ?? 'Vehicle';
    final lat = double.tryParse(_loc?['lat']?.toString() ?? '');
    final lng = double.tryParse(_loc?['lng']?.toString() ?? '');
    final updated = _loc?['locationUpdatedAt']?.toString() ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: JT.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text('Driver Tracking', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: JT.textPrimary)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: JT.primary)))
          else ...[
            Text(driver, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: JT.textPrimary)),
            const SizedBox(height: 4),
            Text('$vehicle · $phone', style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JT.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JT.primary.withValues(alpha: 0.15)),
              ),
              child: Text(
                lat != null && lng != null
                    ? 'Live location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                    : 'Driver location will appear when trip starts',
                style: GoogleFonts.poppins(fontSize: 12, color: JT.primaryDark),
              ),
            ),
            if (updated.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Updated: $updated', style: GoogleFonts.poppins(fontSize: 11, color: JT.textSecondary)),
            ],
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Call Driver'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JT.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
