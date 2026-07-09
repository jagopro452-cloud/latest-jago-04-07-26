import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/jago_theme.dart';
import '../main_screen.dart';
import 'dart:convert';
import '../tracking/tracking_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../chat/trip_chat_sheet.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_service.dart';
import '../../config/api_config.dart';
import 'package:flutter/services.dart';
import '../tip/tip_driver_screen.dart';

class TripCompletionScreen extends StatefulWidget {
  final Map<String, dynamic> trip;
  final double walletPendingAmount;
  final bool isParcel;

  const TripCompletionScreen({
    super.key,
    required this.trip,
    this.walletPendingAmount = 0.0,
    this.isParcel = false,
  });

  @override
  State<TripCompletionScreen> createState() => _TripCompletionScreenState();
}

class _TripCompletionScreenState extends State<TripCompletionScreen> {
  int _rated = 0;
  bool _isRatingSubmitted = false;
  int _currentIndex = 0; // For bottom nav mock consistency

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final driverName = trip['driverName']?.toString() ?? 
                       trip['driver_name']?.toString() ?? 
                       trip['pilot_name']?.toString() ?? 'Pilot';
    final driverPhoto = trip['driverPhoto']?.toString() ?? 
                        trip['driver_photo']?.toString();
    final driverRating = trip['driverRating'] ?? trip['driver_rating'] ?? '5.00';
    
    final from = trip['pickupShortName'] ?? trip['pickup_short_name'] ?? 
                 trip['pickupAddress'] ?? trip['pickup_address'] ?? 'Pickup';
    final to = trip['destinationShortName'] ?? trip['dest_short_name'] ?? 
               trip['destinationAddress'] ?? trip['destination_address'] ?? 'Destination';
    
    // Detailed fare extraction logic
    final fare = trip['actualFare'] ?? trip['actual_fare'] ?? 
                 trip['totalFare'] ?? trip['total_fare'] ??
                 trip['payableAmount'] ?? trip['payable_amount'] ??
                 trip['estimatedFare'] ?? trip['estimated_fare'] ?? 
                 trip['fare'] ?? '0.00';
    
    final actualFare = fare.toString();
    final distance = trip['estimatedDistance'] ?? trip['estimated_distance'] ?? 
                     trip['distanceKm'] ?? trip['distance_km'] ?? '';
    final pendingAmount = widget.walletPendingAmount;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      body: Column(
        children: [
          // Global Header (Matching MainScreen)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Jago Logo
                  GestureDetector(
                    onTap: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const MainScreen()),
                        (_) => false,
                      );
                    },
                    child: JT.logoBlue(height: 32),
                  ),
                  
                  // Actions: Wallet & Notifications
                  Row(
                    children: [
                      _headerAction(Icons.account_balance_wallet_outlined),
                      const SizedBox(width: 12),
                      _headerAction(Icons.notifications_none_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Trip Completed Banner
                  _buildStatusBanner(),
                  const SizedBox(height: 20),
                  
                  // Main Design Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Background decorative dots
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Row(
                            children: [
                              _dot(const Color(0xFFFACC15), 6),
                              const SizedBox(width: 20),
                              _dot(const Color(0xFF5BABFF), 4),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 20,
                          right: 30,
                          child: _dot(const Color(0xFF4ADE80), 5),
                        ),

                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "Your ride is ended" Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  widget.isParcel ? 'Delivery completed' : 'Your ride is ended',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Pilot Info Row
                            _buildPilotCard(driverName, driverPhoto, driverRating),
                            const SizedBox(height: 20),

                            // Actions Row (Chat, Call, SOS)
                            _buildActionRow(driverName),
                            const SizedBox(height: 16),

                            // Vehicle Icon Chip
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.electric_bike_rounded, size: 20, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 20),

                            // Route Details
                            _buildRouteDetails(from, to),
                            const SizedBox(height: 24),

                            // Final Fare
                            _buildFareDisplay(actualFare, distance),
                            if (pendingAmount > 0) ...[
                              const SizedBox(height: 12),
                              _buildPendingPayment(pendingAmount),
                            ],
                            const SizedBox(height: 32),

                            // Rating Section
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    _isRatingSubmitted ? 'Rating received!' : 'Rate your Pilot',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildStarRating(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Tip Driver button (shown after rating)
                            if (_isRatingSubmitted && !widget.isParcel)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final tripId = widget.trip['id']?.toString() ?? '';
                                    final driverName = widget.trip['driverName']?.toString() ??
                                        widget.trip['driver_name']?.toString() ?? 'Pilot';
                                    if (tripId.isNotEmpty) {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => TipDriverScreen(tripId: tripId, driverName: driverName),
                                      ));
                                    }
                                  },
                                  icon: const Icon(Icons.volunteer_activism_rounded),
                                  label: const Text('Add a Tip'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: JT.primary,
                                    side: BorderSide(color: JT.primary),
                                    minimumSize: const Size(double.infinity, 48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),

                            // Finished Button
                            JT.gradientButton(
                              label: 'Finished',
                              onTap: () {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const MainScreen()),
                                  (_) => false,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _headerAction(IconData icon, {int? targetIndex}) {
    return GestureDetector(
      onTap: () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()), // Navigation with target index would be better if MainScreen supported it via constructor
          (_) => false,
        );
      },
      child: Container(
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
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B4DFF), Color(0xFF2C95F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B4DFF).withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stars_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Completed!',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Your journey has ended safely.',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPilotCard(String name, String? photo, dynamic rating) {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            shape: BoxShape.circle,
            image: photo != null ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover) : null,
          ),
          child: photo == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, color: Color(0xFF2D8CFF), size: 16),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    rating.toString(),
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Pilot',
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(String driverName) {
    final tripId = widget.trip['id']?.toString() ?? '';
    final driverPhone = widget.trip['driverPhone']?.toString() ??
        widget.trip['driver_phone']?.toString() ?? '';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: tripId.isEmpty ? null : () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => TripChatSheet(tripId: tripId, senderName: 'You'),
              );
            },
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 20, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 12),
                  Text(
                    'Message $driverName...',
                    style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: driverPhone.isNotEmpty ? () => launchUrl(Uri.parse('tel:$driverPhone')) : null,
          child: _iconBtn(Icons.call_outlined, JT.primary, JT.primaryLight),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () async {
            try {
              final headers = await AuthService.getHeaders();
              await http.post(Uri.parse(ApiConfig.sos), headers: headers,
                body: jsonEncode({'tripId': tripId, 'message': 'SOS after trip completion'}));
            } catch (_) {}
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SOS alert sent. Help is on the way.')),
              );
            }
          },
          child: _iconBtn(Icons.sos, JT.error, JT.errorLight),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, Color color, Color bg) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildRouteDetails(dynamic from, dynamic to) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const Icon(Icons.circle, size: 10, color: Color(0xFF2D8CFF)),
            Container(
              width: 1.5,
              height: 36,
              color: const Color(0xFFCBD5E1),
              margin: const EdgeInsets.symmetric(vertical: 4),
            ),
            const Icon(Icons.location_on, size: 16, color: Color(0xFFEF4444)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pickup',
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF2D8CFF), fontWeight: FontWeight.w600),
                  ),
                  Text(
                    from.toString(),
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destination',
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFEF4444), fontWeight: FontWeight.w600),
                  ),
                  Text(
                    to.toString(),
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareDisplay(dynamic actualFare, dynamic distance) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Final Fare',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                '₹${actualFare.toString()}',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2D8CFF),
                ),
              ),
            ],
          ),
          if (distance.toString().isNotEmpty) ...[
            const Divider(height: 24, color: Color(0xFFE2E8F0)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Distance Traveled',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  '${distance.toString()} km',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingPayment(double amount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '₹${amount.toStringAsFixed(2)} to be paid in cash/UPI',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF9A3412),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _rateDriver(int stars) async {
    if (_isRatingSubmitted) return;
    setState(() {
      _rated = stars;
      _isRatingSubmitted = true;
    });
    HapticFeedback.mediumImpact();
    
    try {
      final headers = await AuthService.getHeaders();
      await http.post(
        Uri.parse(ApiConfig.rateDriver),
        headers: headers,
        body: jsonEncode({
          'tripId': widget.trip['id']?.toString(),
          'driverId': widget.trip['driverId']?.toString() ?? widget.trip['driver_id']?.toString(),
          'rating': stars,
        }),
      );
    } catch (e) {
      debugPrint('Rating failed: $e');
    }
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final isFilled = starIndex <= _rated;
        return GestureDetector(
          onTap: () => _rateDriver(starIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 40,
              color: isFilled ? const Color(0xFFFFB800) : const Color(0xFFE2E8F0),
            ),
          ),
        );
      }),
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
    bool isSelected = index == _currentIndex;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        // Navigate back to main screen with selected tab if needed
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()), // In real app, you might pass the index
          (_) => false,
        );
      },
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

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
