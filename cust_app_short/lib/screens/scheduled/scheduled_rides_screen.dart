import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import '../../config/jago_theme.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../tracking/tracking_screen.dart';

class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  List<dynamic> _rides = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.scheduledRides), headers: headers);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _rides = data['scheduledRides'] ?? []; _loading = false; });
      } else {
        final msg = _errorMessage(res);
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Pull to refresh.')),
        );
      }
    }
  }

  String _errorMessage(http.Response res) {
    try {
      return jsonDecode(res.body)['message']?.toString() ?? 'Request failed (${res.statusCode})';
    } catch (_) {
      return 'Request failed (${res.statusCode})';
    }
  }

  Future<void> _cancelScheduled(String tripId) async {
    if (tripId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scheduled ride?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse(ApiConfig.cancelTrip),
        headers: headers,
        body: jsonEncode({'tripId': tripId, 'reason': 'Customer cancelled schedule'}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scheduled ride cancelled'), backgroundColor: Colors.green),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(res)), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scheduleNew() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleSheet(onBooked: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: JT.textPrimary), onPressed: () => Navigator.pop(context)),
        title: const Text('Scheduled Rides', style: TextStyle(color: JT.textPrimary, fontWeight: FontWeight.w500)),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF2563EB)), onPressed: _scheduleNew),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _rides.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rides.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _rideCard(_rides[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scheduleNew,
        backgroundColor: const Color(0xFF2563EB),
        icon: const Icon(Icons.schedule, color: Colors.white),
        label: const Text('Schedule Ride', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80, decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle), child: const Icon(Icons.schedule, color: Color(0xFF2563EB), size: 40)),
      const SizedBox(height: 16),
      const Text('No Scheduled Rides', style: TextStyle(color: JT.textPrimary, fontWeight: FontWeight.w500, fontSize: 18)),
      const SizedBox(height: 8),
      const Text('Schedule rides in advance for\nhassle-free travel', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
    ]));
  }

  Widget _rideCard(dynamic ride) {
    final scheduledAt = ride['scheduledAt'] != null ? DateTime.tryParse(ride['scheduledAt']) : null;
    final tripId = ride['id']?.toString() ?? '';
    final status = ride['currentStatus']?.toString() ?? 'scheduled';
    final isLive = ['searching', 'accepted', 'driver_assigned', 'arrived', 'in_progress', 'on_the_way'].contains(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.w500))),
          const Spacer(),
          if (scheduledAt != null)
            Text(DateFormat('dd MMM, hh:mm a').format(scheduledAt), style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w400)),
        ]),
        const SizedBox(height: 12),
        Row(children: [const Icon(Icons.my_location, color: Color(0xFF2563EB), size: 16), const SizedBox(width: 8), Expanded(child: Text(ride['pickupAddress'] ?? '', style: const TextStyle(color: JT.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))]),
        const SizedBox(height: 6),
        Row(children: [const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 16), const SizedBox(width: 8), Expanded(child: Text(ride['destinationAddress'] ?? '', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))]),
        const Divider(height: 16, color: Color(0xFFE2E8F0)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(ride['paymentMethod']?.toString().toUpperCase() ?? 'CASH', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          Text('₹${double.tryParse(ride['estimatedFare']?.toString() ?? '0')?.toStringAsFixed(0) ?? '0'}', style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w500, fontSize: 16)),
        ]),
        if (isLive && tripId.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TrackingScreen(tripId: tripId)),
              ),
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Track Live Ride'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            ),
          ),
        ] else if (status == 'scheduled' && tripId.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _cancelScheduled(tripId),
              child: const Text('Cancel schedule', style: TextStyle(color: Color(0xFFEF4444))),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ScheduleSheet extends StatefulWidget {
  final VoidCallback onBooked;
  const _ScheduleSheet({required this.onBooked});

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _pickupCtrl = TextEditingController(text: 'Current Location');
  final _destCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  String _payment = 'cash';
  bool _booking = false;

  Future<void> _pickDate() async {
    final picked = await showDateTimePicker(context);
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<DateTime?> showDateTimePicker(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDate));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<Map<String, double>?> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return null;
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.geocode(address.trim())),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = double.tryParse(data['lat']?.toString() ?? '');
        final lng = double.tryParse(data['lng']?.toString() ?? '');
        if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
      }
    } catch (_) {}
    return null;
  }

  Future<void> _book() async {
    if (_destCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter destination')));
      return;
    }
    if (_payment == 'upi') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UPI prepaid is available on instant city rides. Use Cash or Wallet for scheduled rides.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _booking = true);
    try {
      double pickupLat = 17.385044;
      double pickupLng = 78.486671;
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
          var pos = await Geolocator.getLastKnownPosition();
          pos ??= await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(const Duration(seconds: 5));
          pickupLat = pos!.latitude;
          pickupLng = pos.longitude;
        }
      } catch (_) {}

      final destGeo = await _geocodeAddress(_destCtrl.text.trim());
      if (destGeo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find destination. Try a clearer address.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse(ApiConfig.scheduleRide),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'pickupAddress': _pickupCtrl.text,
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'destinationAddress': _destCtrl.text.trim(),
          'destinationLat': destGeo['lat'],
          'destinationLng': destGeo['lng'],
          'paymentMethod': _payment,
          'scheduledAt': _selectedDate.toIso8601String(),
          'estimatedFare': 0,
          'estimatedDistance': 0,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context);
        widget.onBooked();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ride scheduled for ${DateFormat('dd MMM, hh:mm a').format(_selectedDate)}')),
        );
      } else {
        final msg = jsonDecode(res.body)['message']?.toString() ?? 'Scheduling failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24))),
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Schedule a Ride', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 20, color: JT.textPrimary)),
          const SizedBox(height: 16),
          _field(Icons.my_location, const Color(0xFF2563EB), _pickupCtrl, 'Pickup location', readOnly: true),
          const SizedBox(height: 10),
          _field(Icons.location_on, const Color(0xFFEF4444), _destCtrl, 'Destination'),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFDBFE))),
              child: Row(children: [
                const Icon(Icons.schedule, color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Pickup Time', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  Text(DateFormat('dd MMM yyyy, hh:mm a').format(_selectedDate), style: const TextStyle(color: JT.textPrimary, fontWeight: FontWeight.w500, fontSize: 15)),
                ]),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _payBtn('cash', Icons.money, 'Cash'),
            const SizedBox(width: 8),
            _payBtn('wallet', Icons.account_balance_wallet, 'Wallet'),
            const SizedBox(width: 8),
            _payBtn('upi', Icons.payment, 'UPI'),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _booking ? null : _book,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              child: _booking ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('Confirm Schedule', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(IconData icon, Color color, TextEditingController ctrl, String hint, {bool readOnly = false}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        Padding(padding: const EdgeInsets.only(left: 12), child: Icon(icon, color: color, size: 18)),
        Expanded(child: TextField(controller: ctrl, readOnly: readOnly, style: const TextStyle(fontSize: 14, color: JT.textPrimary), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFF94A3B8)), border: InputBorder.none, contentPadding: const EdgeInsets.all(12)))),
      ]),
    );
  }

  Widget _payBtn(String val, IconData icon, String label) {
    final sel = _payment == val;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _payment = val),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: sel ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0))),
        child: Column(children: [Icon(icon, size: 18, color: sel ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)), Text(label, style: TextStyle(fontSize: 10, color: sel ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)))]),
      ),
    ));
  }
}
