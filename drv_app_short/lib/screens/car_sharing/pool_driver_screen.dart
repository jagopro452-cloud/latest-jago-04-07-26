import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';

class PoolDriverScreen extends StatefulWidget {
  const PoolDriverScreen({super.key});

  @override
  State<PoolDriverScreen> createState() => _PoolDriverScreenState();
}

class _PoolDriverScreenState extends State<PoolDriverScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _rides = [];
  Timer? _pollTimer;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController(text: '4');
  final _fareCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadRides();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadRides());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabs.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _seatsCtrl.dispose();
    _fareCtrl.dispose();
    _vehicleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRides() async {
    if (!mounted) return;
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.driverCarSharingRides),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rows = (data['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() { _rides = rows; _loading = false; });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createRide() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    final date = _dateCtrl.text.trim();
    final time = _timeCtrl.text.trim();
    final seats = int.tryParse(_seatsCtrl.text.trim()) ?? 0;
    final fare = double.tryParse(_fareCtrl.text.trim()) ?? 0;

    if (from.isEmpty || to.isEmpty || date.isEmpty || time.isEmpty) {
      _snack('Fill in all required fields'); return;
    }
    if (seats < 1 || seats > 6) { _snack('Seats must be between 1 and 6'); return; }
    if (fare <= 0) { _snack('Enter a valid fare per seat'); return; }

    setState(() => _creating = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse(ApiConfig.driverCarSharingCreate),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'fromLocation': from,
          'toLocation': to,
          'departureDate': date,
          'departureTime': time,
          'totalSeats': seats,
          'farePerSeat': fare,
          if (_vehicleCtrl.text.trim().isNotEmpty) 'vehicleInfo': _vehicleCtrl.text.trim(),
          if (_noteCtrl.text.trim().isNotEmpty) 'notes': _noteCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _snack('Pool ride created!', success: true);
        _fromCtrl.clear(); _toCtrl.clear(); _dateCtrl.clear();
        _timeCtrl.clear(); _fareCtrl.clear(); _vehicleCtrl.clear(); _noteCtrl.clear();
        _seatsCtrl.text = '4';
        _tabs.animateTo(0);
        await _loadRides();
      } else {
        final msg = (jsonDecode(res.body) as Map<String, dynamic>)['message']?.toString();
        _snack(msg ?? 'Could not create ride. Try again.');
      }
    } catch (_) {
      if (mounted) _snack('Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _startRide(String rideId) async {
    final headers = await AuthService.getHeaders();
    final res = await http.post(
      Uri.parse(ApiConfig.driverCarSharingStart(rideId)),
      headers: {...headers, 'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (!mounted) return;
    if (res.statusCode == 200) {
      _snack('Ride started!', success: true);
      _loadRides();
    } else {
      _snack('Could not start ride. Try again.');
    }
  }

  Future<void> _completeRide(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Complete Ride?'),
        content: const Text('Mark this pool ride as completed for all passengers?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Complete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final headers = await AuthService.getHeaders();
    final res = await http.post(
      Uri.parse(ApiConfig.driverCarSharingComplete(rideId)),
      headers: {...headers, 'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (!mounted) return;
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final earnings = data['driverEarnings']?.toString() ?? '';
      _snack(earnings.isNotEmpty ? 'Ride completed! Earned ₹$earnings' : 'Ride completed!', success: true);
      _loadRides();
    } else {
      _snack('Could not complete ride. Try again.');
    }
  }

  Future<void> _cancelRide(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Cancelling will refund all passengers and release their seats.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: JT.error),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final headers = await AuthService.getHeaders();
    final res = await http.post(
      Uri.parse(ApiConfig.driverCarSharingCancel(rideId)),
      headers: {...headers, 'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (!mounted) return;
    if (res.statusCode == 200) {
      _snack('Ride cancelled. Passengers notified.', success: true);
      _loadRides();
    } else {
      _snack('Could not cancel. Try again.');
    }
  }

  Future<void> _showManifest(String rideId, String from, String to) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      ),
    );
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(ApiConfig.driverCarSharingManifest(rideId)),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final passengers = (data['passengers'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _showManifestSheet(from, to, passengers);
      } else {
        _snack('Could not load passenger list.');
      }
    } catch (_) {
      if (mounted) { Navigator.pop(context); _snack('Network error.'); }
    }
  }

  void _showManifestSheet(String from, String to, List<Map<String, dynamic>> passengers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.people_rounded, color: JT.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Passenger List · $from → $to',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: JT.textPrimary))),
                Text('${passengers.length} passenger${passengers.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: JT.textSecondary)),
              ]),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: passengers.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person_off_rounded, size: 40, color: JT.textSecondary.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text('No passengers yet', style: TextStyle(color: JT.textSecondary)),
                    ]))
                  : ListView.separated(
                      controller: ctrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: passengers.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (_, i) {
                        final p = passengers[i];
                        final name = p['passengerName']?.toString() ?? p['name']?.toString() ?? 'Passenger ${i + 1}';
                        final phone = p['passengerPhone']?.toString() ?? p['phone']?.toString() ?? '';
                        final seats = p['seatsBooked'] ?? p['seats'] ?? 1;
                        final pickup = p['pickupAddress']?.toString() ?? '';
                        final drop = p['dropoffAddress']?.toString() ?? '';
                        final notes = p['notes']?.toString() ?? '';
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: JT.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(color: JT.primary, fontWeight: FontWeight.w600))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(fontWeight: FontWeight.w500, color: JT.textPrimary, fontSize: 14)),
                              Text('$seats seat${seats == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: JT.textSecondary)),
                            ])),
                            if (phone.isNotEmpty)
                              GestureDetector(
                                onTap: () => launchUrl(Uri.parse('tel:$phone')),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: JT.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.call_rounded, size: 14, color: JT.primary),
                                    const SizedBox(width: 4),
                                    Text('Call', style: TextStyle(fontSize: 12, color: JT.primary, fontWeight: FontWeight.w500)),
                                  ]),
                                ),
                              ),
                          ]),
                          if (pickup.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              Icon(Icons.trip_origin, size: 12, color: Colors.green),
                              const SizedBox(width: 6),
                              Expanded(child: Text(pickup, style: TextStyle(fontSize: 12, color: JT.textSecondary))),
                            ]),
                          ],
                          if (drop.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(children: [
                              Icon(Icons.location_on, size: 12, color: JT.error),
                              const SizedBox(width: 6),
                              Expanded(child: Text(drop, style: TextStyle(fontSize: 12, color: JT.textSecondary))),
                            ]),
                          ],
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: JT.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text(notes, style: TextStyle(fontSize: 11, color: JT.warning)),
                            ),
                          ],
                        ]);
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? JT.success : JT.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      _dateCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null && mounted) {
      _timeCtrl.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JT.bg,
      appBar: AppBar(
        backgroundColor: JT.bg,
        elevation: 0,
        title: Text('City Pool Rides', style: TextStyle(color: JT.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: JT.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: JT.primary,
          unselectedLabelColor: JT.textSecondary,
          indicatorColor: JT.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'My Rides'), Tab(text: 'Post Ride')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildRidesTab(), _buildCreateTab()],
      ),
    );
  }

  Widget _buildRidesTab() {
    if (_loading) return Center(child: CircularProgressIndicator(color: JT.primary));
    if (_rides.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.directions_car_rounded, size: 64, color: JT.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No pool rides yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: JT.textPrimary)),
          const SizedBox(height: 6),
          Text('Post a city pool ride from the "Post Ride" tab to start earning.',
              style: TextStyle(fontSize: 13, color: JT.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _tabs.animateTo(1),
            style: ElevatedButton.styleFrom(backgroundColor: JT.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Post a Ride'),
          ),
        ]),
      ));
    }

    return RefreshIndicator(
      onRefresh: _loadRides,
      color: JT.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rides.length,
        itemBuilder: (_, i) => _buildRideCard(_rides[i]),
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final id = ride['id']?.toString() ?? '';
    final from = ride['fromLocation']?.toString() ?? ride['from_location']?.toString() ?? '';
    final to = ride['toLocation']?.toString() ?? ride['to_location']?.toString() ?? '';
    final date = ride['departureDate']?.toString() ?? ride['departure_date']?.toString() ?? '';
    final time = ride['departureTime']?.toString() ?? ride['departure_time']?.toString() ?? '';
    final totalSeats = ride['totalSeats'] ?? ride['total_seats'] ?? 0;
    final availableSeats = ride['availableSeats'] ?? ride['available_seats'] ?? 0;
    final bookedSeats = (totalSeats as int) - (availableSeats as int);
    final farePerSeat = double.tryParse(ride['farePerSeat']?.toString() ?? ride['fare_per_seat']?.toString() ?? '0') ?? 0;
    final status = ride['status']?.toString() ?? 'active';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'active': statusColor = Colors.green; statusLabel = 'ACTIVE'; break;
      case 'started': statusColor = JT.primary; statusLabel = 'IN PROGRESS'; break;
      case 'completed': statusColor = JT.textSecondary; statusLabel = 'COMPLETED'; break;
      case 'cancelled': statusColor = JT.error; statusLabel = 'CANCELLED'; break;
      default: statusColor = JT.textSecondary; statusLabel = status.toUpperCase();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: JT.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$from  →  $to',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: JT.textPrimary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.calendar_today_rounded, size: 13, color: JT.textSecondary),
          const SizedBox(width: 5),
          Text('$date${time.isNotEmpty ? ' at $time' : ''}',
              style: TextStyle(fontSize: 12, color: JT.textSecondary)),
          const Spacer(),
          Icon(Icons.event_seat_rounded, size: 13, color: JT.textSecondary),
          const SizedBox(width: 5),
          Text('$bookedSeats/$totalSeats booked · ₹${farePerSeat.toStringAsFixed(0)}/seat',
              style: TextStyle(fontSize: 12, color: JT.textSecondary)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showManifest(id, from, to),
              icon: const Icon(Icons.people_outline, size: 15),
              label: Text('Passengers ($bookedSeats)', style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: JT.primary,
                side: BorderSide(color: JT.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (status == 'active' && bookedSeats > 0)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _startRide(id),
                icon: const Icon(Icons.play_arrow_rounded, size: 15),
                label: const Text('Start', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JT.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          if (status == 'started')
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _completeRide(id),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                label: const Text('Complete', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JT.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          if (status == 'active') ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _cancelRide(id),
              icon: Icon(Icons.cancel_outlined, color: JT.error),
              tooltip: 'Cancel ride',
              style: IconButton.styleFrom(
                backgroundColor: JT.error.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Route'),
        const SizedBox(height: 8),
        _field(_fromCtrl, 'From (city / area)', Icons.trip_origin),
        const SizedBox(height: 10),
        _field(_toCtrl, 'To (city / area)', Icons.location_on_rounded),
        const SizedBox(height: 16),
        _sectionLabel('Date & Time'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: _pickDate,
            child: AbsorbPointer(child: _field(_dateCtrl, 'Date (YYYY-MM-DD)', Icons.calendar_today_rounded)),
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            onTap: _pickTime,
            child: AbsorbPointer(child: _field(_timeCtrl, 'Time (HH:MM)', Icons.access_time_rounded)),
          )),
        ]),
        const SizedBox(height: 16),
        _sectionLabel('Seats & Fare'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _field(_seatsCtrl, 'Total seats', Icons.event_seat_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          const SizedBox(width: 10),
          Expanded(child: _field(_fareCtrl, '₹ per seat', Icons.currency_rupee_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        const SizedBox(height: 16),
        _sectionLabel('Vehicle (optional)'),
        const SizedBox(height: 8),
        _field(_vehicleCtrl, 'Vehicle model / number', Icons.directions_car_rounded),
        const SizedBox(height: 10),
        _field(_noteCtrl, 'Notes for passengers (optional)', Icons.notes_rounded, maxLines: 2),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _creating ? null : _createRide,
            style: ElevatedButton.styleFrom(
              backgroundColor: JT.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: JT.primary.withValues(alpha: 0.5),
            ),
            child: _creating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Post Pool Ride', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JT.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JT.primary.withValues(alpha: 0.15)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: JT.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Passengers book seats and pay online. You will be notified when seats are booked. '
              'Start the ride when all passengers are on board.',
              style: TextStyle(fontSize: 12, color: JT.textSecondary, height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _sectionLabel(String label) => Text(label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JT.textSecondary, letterSpacing: 0.5));

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: TextStyle(fontSize: 14, color: JT.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: JT.textSecondary, fontSize: 13),
          prefixIcon: Icon(icon, size: 18, color: JT.textSecondary),
          filled: true,
          fillColor: JT.bgSoft,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: JT.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: JT.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );
}
