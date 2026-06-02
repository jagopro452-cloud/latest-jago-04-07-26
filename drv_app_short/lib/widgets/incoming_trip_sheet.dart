import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/jago_theme.dart';
import '../services/alarm_service.dart';

/// Redesigned Full-screen ride request overlay inspired by Rapido.
/// Pushed as a Navigator route so it sits above the home map.
class IncomingTripSheet extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingTripSheet({
    super.key,
    required this.trip,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingTripSheet> createState() => _IncomingTripSheetState();
}

class _IncomingTripSheetState extends State<IncomingTripSheet> with TickerProviderStateMixin {
  late AnimationController _ringCtrl;
  int _countdown = 40;
  Timer? _countdownTimer;
  bool _responded = false;

  static const Color _jagoBlue = JT.primary;
  static const Color _jagoBlueDark = Color(0xFF1559C9);
  static const Color _jagoBg = Color(0xFFF4F8FF);
  static const Color _surfaceTint = Color(0xFFEAF2FF);
  static const Color _textDark = JT.textPrimary;
  static const Color _textGrey = JT.textSecondary;

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..forward();

    AlarmService().startAlarm();
    _triggerAlertBurst();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 0) {
        t.cancel();
        _autoReject();
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _triggerAlertBurst() {
    for (int i = 0; i < 5; i++) {
      Future.delayed(Duration(milliseconds: 80 * i), () {
        if (mounted) {
          HapticFeedback.heavyImpact();
          if (i % 2 == 0) SystemSound.play(SystemSoundType.alert);
        }
      });
    }
  }

  Future<void> _stopAndRespond(bool accepted) async {
    if (_responded) return;
    _responded = true;
    _countdownTimer?.cancel();
    await AlarmService().stopAlarm();
    if (accepted) {
      widget.onAccept();
    } else {
      widget.onReject();
    }
  }

  Future<void> _autoReject() async {
    if (_responded) return;
    _responded = true;
    await AlarmService().stopAlarm();
    widget.onReject();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _countdownTimer?.cancel();
    if (!_responded) AlarmService().stopAlarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final pickup = trip['pickupAddress'] ?? 'Pickup location';
    final dest = trip['destinationAddress'] ?? 'Destination';
    final pickupDist = trip['driverDistanceKm'] ?? '1.4';
    final tripDist = trip['estimatedDistance'] ?? '4.8';
    final fare = trip['estimatedFare'] ?? '121';
    final extra = trip['incentive'] ?? '13';
    final vehicleType = (trip['vehicleCategoryName'] ?? 'Bike').toString();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _jagoBg,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header (Jago Pro Style) ────────────────────────────────────
              _buildTopNav(),
              
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Left Queue Sidebar ───────────────────────────────────
                    _buildQueueSidebar(extra),
                    
                    // ── Main Card Content ────────────────────────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 16, 20),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildMainTripCard(
                            vehicleType: vehicleType,
                            extra: extra,
                            fare: fare,
                            pickup: pickup,
                            dest: dest,
                            pickupDist: pickupDist,
                            tripDist: tripDist,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: _jagoBlue.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'New Request',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _textDark,
              letterSpacing: -0.5,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _jagoBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(
                  'ON',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.volume_up_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueSidebar(dynamic extra) {
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          // Current Active Trip indicator
          _sidebarItem(active: true, extra: extra),
          const SizedBox(height: 20),
          // Other placeholder
          _sidebarItem(active: false, extra: '10'),
        ],
      ),
    );
  }

  Widget _sidebarItem({required bool active, required dynamic extra}) {
    final color = active ? _jagoBlue : Colors.grey.shade300;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
          child: active 
            ? AnimatedBuilder(
                animation: _ringCtrl,
                builder: (context, child) {
                  return CircularProgressIndicator(
                    value: 1.0 - _ringCtrl.value,
                    strokeWidth: 2.5,
                    color: _jagoBlue,
                    backgroundColor: Colors.transparent,
                  );
                },
              )
            : null,
        ),
        if (extra != null) ...[
          const SizedBox(height: 6),
          Text(
            '+₹$extra',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _jagoBlueDark,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMainTripCard({
    required String vehicleType,
    required dynamic extra,
    required dynamic fare,
    required String pickup,
    required String dest,
    required dynamic pickupDist,
    required dynamic tripDist,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Go To" pill
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _jagoBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _jagoBlue.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: _jagoBlue),
              const SizedBox(width: 6),
              Text(
                'Go To',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: _jagoBlue),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _jagoBlue.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: _jagoBlue.withOpacity(0.06),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Card Header: Vehicle Type & Full Fare
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _surfaceTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_bike_rounded, size: 16, color: _jagoBlue),
                              const SizedBox(width: 6),
                              Text(
                                vehicleType,
                                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: _jagoBlue),
                              ),
                            ],
                          ),
                        ),
                        if (extra != null && extra != '0') ...[
                          const SizedBox(height: 8),
                          Text(
                            '+₹$extra incentive',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _jagoBlueDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '₹$fare',
                      style: GoogleFonts.outfit(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: _jagoBlue,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),

              // Card Body: Address Timeline
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAddressTimeline(pickup, dest, pickupDist, tripDist),
              ),

              const SizedBox(height: 24),

              // Card Footer: Action Bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                decoration: BoxDecoration(
                  color: _jagoBg,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    // Reject Button
                    GestureDetector(
                      onTap: () => _stopAndRespond(false),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: AnimatedBuilder(
                              animation: _ringCtrl,
                              builder: (context, child) {
                                return CircularProgressIndicator(
                                  value: 1.0 - _ringCtrl.value,
                                  strokeWidth: 4,
                                  color: Colors.red.shade400,
                                  backgroundColor: Colors.grey.shade200,
                                );
                              },
                            ),
                          ),
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
                              ],
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.black, size: 24),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Accept Button
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _stopAndRespond(true),
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: _jagoBlue,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: _jagoBlue.withOpacity(0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Accept Ride',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressTimeline(String pickup, String dest, dynamic pickupDist, dynamic tripDist) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline
        Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _jagoBlue,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: _jagoBlue.withOpacity(0.3), blurRadius: 4)],
              ),
            ),
            // Dynamic connector
            Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_jagoBlue, _jagoBlue.withOpacity(0.24)],
                ),
              ),
            ),
            Icon(Icons.location_on_rounded, size: 20, color: _jagoBlueDark),
          ],
        ),
        const SizedBox(width: 16),
        // Texts
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$pickupDist Km away',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark),
              ),
              const SizedBox(height: 2),
              Text(
                pickup,
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w400, color: _textGrey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Text(
                '$tripDist Km trip',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark),
              ),
              const SizedBox(height: 2),
              Text(
                dest,
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w400, color: _textGrey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
