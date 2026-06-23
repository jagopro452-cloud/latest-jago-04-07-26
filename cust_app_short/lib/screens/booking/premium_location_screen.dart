import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';
import '../../services/trip_service.dart';
import '../history/trips_history_screen.dart';
import '../profile/profile_screen.dart';
import 'booking_screen.dart';
import 'map_location_picker.dart';
import '../wallet/wallet_screen.dart';
import '../notifications/notifications_screen.dart';
import 'parcel_booking_screen.dart';

class PremiumLocationScreen extends StatefulWidget {
  final String serviceType; // 'ride' or 'parcel'
  final String? pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String? vehicleCategoryId;
  final String? vehicleCategoryName;

  const PremiumLocationScreen({
    super.key,
    required this.serviceType,
    this.pickupAddress,
    this.pickupLat = 0,
    this.pickupLng = 0,
    this.vehicleCategoryId,
    this.vehicleCategoryName,
  });

  @override
  State<PremiumLocationScreen> createState() => _PremiumLocationScreenState();
}

class _PremiumLocationScreenState extends State<PremiumLocationScreen> {
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropCtrl = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropFocus = FocusNode();

  String _pickup = '';
  String _drop = '';
  double _pickupLat = 0;
  double _pickupLng = 0;
  double _dropLat = 0;
  double _dropLng = 0;

  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounce;
  bool _isTyping = false;
  bool _detectingLocation = false;
  bool _searching = false;
  int _searchRequestId = 0;
  String _sessionToken = '';
  String? _zoneWarning;

  List<Map<String, dynamic>> _recentTrips = [];
  bool _isLoadingTrips = true;

  @override
  void initState() {
    super.initState();
    _pickup = widget.pickupAddress ?? '';
    _pickupLat = widget.pickupLat;
    _pickupLng = widget.pickupLng;
    _pickupCtrl.text = _pickup;
    _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    _pickupFocus.addListener(_onFocusChange);
    _dropFocus.addListener(_onFocusChange);
    _fetchRecentTrips();
  }

  Future<void> _fetchRecentTrips() async {
    try {
      final trips = await TripService.getTripHistory();
      if (mounted) {
        setState(() {
          _recentTrips = trips.cast<Map<String, dynamic>>();
          _isLoadingTrips = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrips = false);
    }
  }

  void _showNotServingMessage([String? zoneName]) {
    final zoneSuffix = (zoneName != null && zoneName.trim().isNotEmpty)
        ? ' in $zoneName'
        : '';
    setState(() {
      _zoneWarning =
          'We are coming soon to your area$zoneSuffix. JAGO services are available only inside configured service zones.';
    });
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isTyping = _pickupFocus.hasFocus || _dropFocus.hasFocus;
        if (!_isTyping) _searchResults = [];
      });
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _detectingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final addr = await _reverseGeocode(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() {
        _pickup = addr;
        _pickupLat = p.latitude;
        _pickupLng = p.longitude;
        _pickupCtrl.text = addr;
        _detectingLocation = false;
      });
    } catch (e) {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      Map<String, String> headers = const {};
      try {
        headers = await AuthService.getHeaders();
      } catch (_) {}
      final res = await http.get(
        Uri.parse('${ApiConfig.reverseGeocode}?lat=$lat&lng=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['formattedAddress']?.toString() ??
            data['address']?.toString() ??
            "Selected Location";
      }
    } catch (_) {}
    return "Selected Location";
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = query.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _searching = false;
            _zoneWarning = null;
          });
        }
        return;
      }
      final requestId = ++_searchRequestId;
      if (mounted) setState(() => _searching = true);
      try {
        Map<String, String> headers = const {};
        try {
          headers = await AuthService.getHeaders();
        } catch (_) {}

        final qp = StringBuffer('?query=${Uri.encodeComponent(q)}');
        qp.write('&sessionToken=$_sessionToken');
        if (_pickupLat != 0 && _pickupLng != 0) {
          qp.write('&lat=$_pickupLat&lng=$_pickupLng');
        }

        List<Map<String, dynamic>> finalPredictions = [];
        String? zoneWarning;

        try {
          final res = await http
              .get(Uri.parse('${ApiConfig.placesAutocomplete}$qp'), headers: headers)
              .timeout(const Duration(seconds: 4));
          if (!mounted || requestId != _searchRequestId) return;

          if (res.statusCode == 200) {
            final data = json.decode(res.body) as Map<String, dynamic>;
            zoneWarning = data['message']?.toString();
            final predictions = (data['predictions'] as List<dynamic>? ?? [])
                .map((p) => <String, dynamic>{
                      'name': p['fullDescription']?.toString() ??
                          p['description']?.toString() ??
                          p['mainText']?.toString() ??
                          '',
                      'mainText': p['mainText']?.toString() ?? '',
                      'secondaryText': p['secondaryText']?.toString() ?? '',
                      'placeId': p['placeId']?.toString() ??
                          p['place_id']?.toString() ??
                          '',
                      'lat': (p['lat'] as num?)?.toDouble() ?? 0.0,
                      'lng': (p['lng'] as num?)?.toDouble() ?? 0.0,
                      'serviceable': p['serviceable'] == true,
                      'zoneName': p['zoneName']?.toString() ?? '',
                      'notServing': p['notServing'] == true,
                      'distanceMeters': (p['distanceMeters'] as num?)?.toDouble() ?? 0.0,
                    })
                .where((p) =>
                    (p['name'] as String).isNotEmpty)
                .toList();
            finalPredictions.addAll(predictions);
          }
        } catch (_) {}

        try {
          final nomQp = Uri.encodeComponent(q);
          final nomRes = await http.get(
            Uri.parse('https://nominatim.openstreetmap.org/search?q=$nomQp&format=json&addressdetails=1&limit=5&countrycodes=in'),
            headers: {'User-Agent': 'JagoCustomerApp/1.0'},
          ).timeout(const Duration(seconds: 4));
          if (nomRes.statusCode == 200) {
            final nomData = json.decode(nomRes.body) as List<dynamic>;
            final nomPredictions = nomData.map((p) => <String, dynamic>{
              'name': p['display_name']?.toString() ?? '',
              'mainText': p['name']?.toString() ?? '',
              'secondaryText': p['display_name']?.toString() ?? '',
              'placeId': 'nom:${p['place_id']}',
              'lat': double.tryParse(p['lat']?.toString() ?? '0') ?? 0.0,
              'lng': double.tryParse(p['lon']?.toString() ?? '0') ?? 0.0,
              'serviceable': true,
              'zoneName': '',
              'notServing': false,
              'distanceMeters': 0.0,
            }).where((p) => (p['name'] as String).isNotEmpty).toList();
            finalPredictions.addAll(nomPredictions);
          }
        } catch (_) {}

        final seen = <String>{};
        final uniquePredictions = finalPredictions.where((p) {
          final name = p['name'] as String;
          if (seen.contains(name)) return false;
          seen.add(name);
          return true;
        }).toList();

        if (mounted && requestId == _searchRequestId) {
          setState(() {
            _zoneWarning = uniquePredictions.isEmpty ? zoneWarning : null;
            _searchResults = uniquePredictions;
          });
        }
      } catch (_) {
        if (mounted && requestId == _searchRequestId) {
          setState(() {
            _zoneWarning = null;
            _searchResults = [];
          });
        }
      } finally {
        if (mounted && requestId == _searchRequestId) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _selectPlace(Map<String, dynamic> p) async {
    final placeId = p['placeId']?.toString() ?? p['place_id']?.toString() ?? '';
    if (placeId.isEmpty) return;
    try {
      double lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
      double lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
      String addr = p['name']?.toString() ?? 'Selected Location';
      final alreadyServiceable = p['serviceable'] == true;
      final predictionZoneName = p['zoneName']?.toString();

      if (lat == 0.0 || lng == 0.0) {
        Map<String, String> headers = const {};
        try {
          headers = await AuthService.getHeaders();
        } catch (_) {}
        final res = await http.get(
          Uri.parse(
              '${ApiConfig.placeDetails}?placeId=${Uri.encodeComponent(placeId)}&sessionToken=$_sessionToken'),
          headers: headers,
        ).timeout(const Duration(seconds: 6));
        _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
        if (res.statusCode != 200) return;
        final data = json.decode(res.body) as Map<String, dynamic>;
        lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
        lng = (data['lng'] as num?)?.toDouble() ?? 0.0;
        addr = data['address']?.toString() ?? addr;
        if (data['serviceable'] != true) {
          if (mounted) _showNotServingMessage(data['zoneName']?.toString());
          return;
        }
      }

      if (lat == 0.0 || lng == 0.0) return;
      if (!alreadyServiceable &&
          (placeId.startsWith('local:') || placeId.startsWith('nom:'))) {
        if (p['serviceable'] != true) {
          if (mounted) _showNotServingMessage(predictionZoneName);
          return;
        }
      }
      if (mounted) {
        setState(() {
          if (_pickupFocus.hasFocus) {
            _pickup = addr;
            _pickupLat = lat;
            _pickupLng = lng;
            _pickupCtrl.text = addr;
          } else {
            _drop = addr;
            _dropLat = lat;
            _dropLng = lng;
            _dropCtrl.text = addr;
          }
          _zoneWarning = null;
          _searchResults = [];
          _searching = false;
          FocusScope.of(context).unfocus();
        });
      }
    } catch (_) {}
  }

  void _clearResults() {
    if (!mounted) return;
    setState(() {
      _searchResults = [];
      _searching = false;
    });
  }

  void _swapLocations() {
    setState(() {
      final tTxt = _pickup; final tLat = _pickupLat; final tLng = _pickupLng;
      _pickup = _drop; _pickupLat = _dropLat; _pickupLng = _dropLng; _pickupCtrl.text = _pickup;
      _drop = tTxt; _dropLat = tLat; _dropLng = tLng; _dropCtrl.text = _drop;
    });
  }

  void _proceedToBooking() {
    if (_pickupLat == 0 || _dropLat == 0) return;
    if (widget.serviceType == 'parcel') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => ParcelBookingScreen(
        pickupLat: _pickupLat, pickupLng: _pickupLng, dropLat: _dropLat, dropLng: _dropLng,
        pickupAddress: _pickup, dropAddress: _drop,
      )));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => BookingScreen(
        pickup: _pickup, destination: _drop, pickupLat: _pickupLat, pickupLng: _pickupLng,
        destLat: _dropLat, destLng: _dropLng, vehicleCategoryId: widget.vehicleCategoryId,
        vehicleCategoryName: widget.vehicleCategoryName, category: widget.serviceType,
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (!_isTyping) _buildActionPills(),
                    if (!_isTyping) const SizedBox(height: 24),
                    _buildPremiumRouteCard(),
                    const SizedBox(height: 16),
                    if (!_isTyping) _buildMapAndStopsButtons(),
                    const SizedBox(height: 24),
                    if (_isTyping && _zoneWarning != null && _searchResults.every((item) => item['serviceable'] != true))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _zoneWarning!,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isTyping && _searchResults.isNotEmpty)
                      _buildSearchResults()
                    else if (!_isTyping)
                      _buildRecentRides(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_pickupLat != 0 && _dropLat != 0)
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: _proceedToBooking,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C95F1),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2C95F1).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Center(
                    child: Text("Set your journey", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        // Logo (pops the screen back to home)
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: JT.logoBlue(height: 32),
        ),
        const SizedBox(width: 8),
        // Location indicator
        Expanded(
          child: Row(children: [
            Icon(Icons.location_on_rounded, color: JT.primary, size: 13),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                _pickup.isNotEmpty ? _pickup.split(',').first : 'Getting location...',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: JT.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        // Wallet balance link
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: JT.surfaceAlt, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.account_balance_wallet_rounded, color: JT.primary, size: 13),
              const SizedBox(width: 4),
              Text('Wallet', style: GoogleFonts.poppins(color: JT.primary, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // Notification bell
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: JT.primary.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(Icons.notifications_none_rounded, color: JT.primary, size: 20),
          ),
        ),
      ]),
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
              _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, "Home"),
              _buildNavItem(1, Icons.receipt_long_rounded, Icons.receipt_long_outlined, "Trips"),
              _buildNavItem(2, Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined, "Wallet"),
              _buildNavItem(3, Icons.person_rounded, Icons.person_outline_rounded, "Profile"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = index == 0;
    return GestureDetector(
      onTap: () {
        if (index == 0) {
           Navigator.pop(context);
        } else if (index == 1) {
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TripsHistoryScreen()));
        } else if (index == 2) {
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
        } else if (index == 3) {
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: isSelected
            ? BoxDecoration(
                color: const Color(0xFF2C95F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              )
            : const BoxDecoration(),
        child: Row(
          children: [
            Icon(isSelected ? activeIcon : inactiveIcon, color: isSelected ? const Color(0xFF2C95F1) : const Color(0xFF94A3B8), size: 22),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.poppins(color: const Color(0xFF2C95F1), fontSize: 13, fontWeight: FontWeight.w600)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildActionPills() {
    return Row(
      children: [
        _buildPill("Now", Icons.access_time_filled, true),
        const SizedBox(width: 10),
        _buildPill("Schedule", Icons.calendar_today_rounded, false),
        const SizedBox(width: 10),
        _buildPill("For me", Icons.person_rounded, false),
      ],
    );
  }

  Widget _buildPill(String text, IconData icon, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF1E293B)),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildPremiumRouteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side dots and line
          Column(
            children: [
              const SizedBox(height: 22),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981), // Green dot
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 48,
                color: const Color(0xFFE2E8F0),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C95F1), // Blue square for their theme
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Right side inputs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputField(
                  label: "FROM",
                  hint: "Starting point?",
                  controller: _pickupCtrl,
                  focusNode: _pickupFocus,
                  isPickup: true,
                ),
                const Divider(height: 24, color: Color(0xFFF1F5F9), thickness: 1.5),
                _buildInputField(
                  label: "DROP",
                  hint: "Where to?",
                  controller: _dropCtrl,
                  focusNode: _dropFocus,
                  isPickup: false,
                ),
              ],
            ),
          ),
          // Swap button
          Column(
            children: [
              const SizedBox(height: 42),
              GestureDetector(
                onTap: _swapLocations,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.swap_vert_rounded, color: Color(0xFF64748B), size: 20),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isPickup,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 1.0)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: _onSearch,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                decoration: InputDecoration(
                  hintText: (_detectingLocation && isPickup) ? "Locating you..." : hint,
                  hintStyle: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if ((_detectingLocation && isPickup) || (_searching && focusNode.hasFocus))
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2C95F1)),
              )
            else if (controller.text.isNotEmpty && focusNode.hasFocus)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  _clearResults();
                },
                child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
              )
          ],
        ),
      ],
    );
  }

  Widget _buildMapAndStopsButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MapLocationPicker())).then((res) {
                if (res != null) {
                  setState(() {
                    _drop = res.address;
                    _dropLat = res.lat;
                    _dropLng = res.lng;
                    _dropCtrl.text = _drop;
                  });
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFF2C95F1), size: 18),
                  const SizedBox(width: 8),
                  Text("Select on map", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              // Add stops feature not yet implemented, placeholder
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text("Add stops", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentRides() {
    if (_isLoadingTrips) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF2C95F1), strokeWidth: 2)),
      );
    }

    final recent = _recentTrips.where((r) => 
      (r['destinationAddress'] != null || r['destination_address'] != null) &&
      (r['destinationLat'] != null || r['destination_lat'] != null)
    ).take(5).toList();

    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("RECENT", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 1.0)),
            Text("See all", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF2C95F1))),
          ],
        ),
        const SizedBox(height: 16),
        ...recent.map((r) {
          final fullAddress = r['destinationAddress']?.toString() ?? r['destination_address']?.toString() ?? '';
          final parts = fullAddress.split(',');
          final title = parts.isNotEmpty ? parts.first : 'Location';
          final subtitle = parts.length > 1 ? parts.sublist(1).join(',').trim() : 'Previous drop location';
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _drop = fullAddress;
                  _dropCtrl.text = _drop;
                  _dropLat = (r['destinationLat'] as num?)?.toDouble() ?? (r['destination_lat'] as num?)?.toDouble() ?? 0.0;
                  _dropLng = (r['destinationLng'] as num?)?.toDouble() ?? (r['destination_lng'] as num?)?.toDouble() ?? 0.0;
                });
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C95F1).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history_rounded, color: Color(0xFF2C95F1), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFCBD5E1), size: 14),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSearchResults() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _searchResults.length,
        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (context, index) {
          final p = _searchResults[index];
          final mainText = p['mainText']?.toString().isNotEmpty == true
              ? p['mainText'].toString()
              : (p['name']?.toString().split(',').first ?? 'Location');
          final secText = p['secondaryText']?.toString() ?? '';
          final zoneName = p['zoneName']?.toString() ?? '';
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2C95F1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF2C95F1),
                size: 20,
              ),
            ),
            title: Text(mainText, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (secText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(secText, style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (zoneName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C95F1).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Serving in $zoneName',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2C95F1),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _selectPlace(p),
          );
        },
      ),
    );
  }
}
