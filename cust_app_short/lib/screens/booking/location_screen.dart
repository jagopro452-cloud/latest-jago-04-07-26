import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';
import 'booking_screen.dart';
import 'map_location_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Jago — Full-Screen Location Picker
// Rule 1: Location ALWAYS comes before vehicle selection.
// Rule 7: Pickup auto-detect · Drop auto-focus · Map pick · Add stop · Suggestions
// ─────────────────────────────────────────────────────────────────────────────

class LocationScreen extends StatefulWidget {
  final String serviceType; // 'ride' or 'parcel'
  final String? pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String? vehicleCategoryId;
  final String? vehicleCategoryName;

  const LocationScreen({
    super.key,
    required this.serviceType,
    this.pickupAddress,
    this.pickupLat = 0.0,
    this.pickupLng = 0.0,
    this.vehicleCategoryId,
    this.vehicleCategoryName,
  });

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _dropCtrl = TextEditingController();
  final _stopCtrl = TextEditingController();
  final FocusNode _dropFocus = FocusNode();
  final FocusNode _stopFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  String _pickup = '';
  double _pickupLat = 0.0;
  double _pickupLng = 0.0;

  String _drop = '';
  double _dropLat = 0.0;
  double _dropLng = 0.0;

  bool _showStop = false;
  String _stop = '';
  double _stopLat = 0.0;
  double _stopLng = 0.0;

  bool _detectingLocation = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _popular = [];
  bool _searching = false;
  bool _activeField = true; // true = editing drop, false = editing stop
  String _activeQuery = '';
  String? _searchHelperText;
  Timer? _debounce;
  String _sessionToken = ''; // Google Places Session Token for cost optimization
  int _searchRequestId = 0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  // ── Theme ─────────────────────────────────────────────────────────────────
  bool get _isParcel => widget.serviceType == 'parcel';
  Color get _accent => JT.moduleAccent(_isParcel);
  Color get _accentLight => JT.moduleAccentLight(_isParcel);
  Color get _fieldBorder => JT.moduleFieldBorder(_isParcel);
  Color get _fieldBg => JT.moduleFieldBg(_isParcel);

  @override
  void initState() {
    super.initState();
    _pickup = widget.pickupAddress ?? '';
    _pickupLat = widget.pickupLat;
    _pickupLng = widget.pickupLng;

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();

    _loadRecent();
    _fetchPopular();
    _resetSessionToken();
    if (_pickup.isEmpty) _detectLocation();

    // Auto-focus drop field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dropFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _dropCtrl.dispose();
    _stopCtrl.dispose();
    _dropFocus.dispose();
    _stopFocus.dispose();
    _debounce?.cancel();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Location Detection ────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    setState(() => _detectingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (!serviceEnabled) {
        if (lastKnown != null) {
          final addr = await _reverseGeocode(lastKnown.latitude, lastKnown.longitude);
          if (!mounted) return;
          setState(() {
            _pickup = addr;
            _pickupLat = lastKnown.latitude;
            _pickupLng = lastKnown.longitude;
          });
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on location services to detect your pickup point.')),
          );
        }
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required to detect your current location.')),
          );
        }
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is blocked. Enable it from app settings.')),
          );
        }
        await Geolocator.openAppSettings();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
      final addr = await _reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _pickup = addr;
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
      });
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final addr = await _reverseGeocode(lastKnown.latitude, lastKnown.longitude);
        if (!mounted) return;
        setState(() {
          _pickup = addr;
          _pickupLat = lastKnown.latitude;
          _pickupLng = lastKnown.longitude;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect your location. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    // Try server proxy first
    try {
      final headers = await AuthService.getHeaders();
      final r = await http.get(
        Uri.parse('${ApiConfig.reverseGeocode}?lat=$lat&lng=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final parts = <String>[];
        for (final k in ['area', 'city', 'state']) {
          final v = d[k]?.toString() ?? '';
          if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
        }
        if (parts.isNotEmpty) return parts.take(3).join(', ');
        final full = d['formattedAddress']?.toString() ?? '';
        if (full.isNotEmpty) return full.split(', ').take(3).join(', ');
      }
    } catch (_) {}
    // Nominatim fallback
    try {
      final r = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng'),
        headers: const {'User-Agent': 'JagoPro/1.0'},
      ).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final addr = d['address'] as Map<String, dynamic>? ?? {};
        final parts = <String>[];
        for (final k in ['suburb', 'neighbourhood', 'city', 'town', 'state']) {
          final v = addr[k]?.toString() ?? '';
          if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
        }
        if (parts.isNotEmpty) return parts.take(3).join(', ');
        final full = d['display_name']?.toString() ?? '';
        if (full.isNotEmpty) return full.split(',').take(3).join(',').trim();
      }
    } catch (_) {}
    return 'Current Location';
  }

  // ── Recent Places ─────────────────────────────────────────────────────────
  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('recent_places') ?? [];
      final list = raw
          .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
          .take(5)
          .toList();
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _saveRecent(String name, double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = jsonEncode({'name': name, 'lat': lat, 'lng': lng});
      final raw = prefs.getStringList('recent_places') ?? [];
      raw.removeWhere((s) {
        try {
          return (jsonDecode(s) as Map)['name'] == name;
        } catch (_) {
          return false;
        }
      });
      raw.insert(0, entry);
      await prefs.setStringList('recent_places', raw.take(10).toList());
    } catch (_) {}
  }

  // ── Popular Locations ─────────────────────────────────────────────────────
  Future<void> _fetchPopular() async {
    try {
      final r = await http.get(
          Uri.parse(
              '${ApiConfig.baseUrl}/api/app/popular-locations?city=Vijayawada')).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = ((data['locations'] as List<dynamic>?) ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .map((x) => {
                  'name': x['name']?.toString() ?? '',
                  'lat':
                      double.tryParse((x['lat'] ?? x['latitude'] ?? 0).toString()) ??
                          0.0,
                  'lng': double.tryParse(
                          (x['lng'] ?? x['longitude'] ?? 0).toString()) ??
                      0.0,
                })
            .where((x) => (x['name'] as String).isNotEmpty)
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() => _popular = list.cast<Map<String, dynamic>>());
          return;
        }
      }
    } catch (_) {}
    if (mounted && _popular.isEmpty) {
      setState(() => _popular = const [
            {'name': 'Benz Circle', 'lat': 16.5062, 'lng': 80.6480},
            {
              'name': 'Vijayawada Railway Station',
              'lat': 16.5175,
              'lng': 80.6400
            },
            {
              'name': 'Vijayawada Bus Stand',
              'lat': 16.5179,
              'lng': 80.6238
            },
            {'name': 'Kanaka Durga Temple', 'lat': 16.5176, 'lng': 80.6121},
            {
              'name': 'Gannavaram Airport',
              'lat': 16.5304,
              'lng': 80.7968
            },
            {'name': 'Governorpet', 'lat': 16.5135, 'lng': 80.6346},
            {'name': 'Patamata', 'lat': 16.4883, 'lng': 80.6681},
          ]);
    }
  }

  // ── Session Token ─────────────────────────────────────────────────────────
  void _resetSessionToken() {
    // Generate a fresh UUID-like token for a new search session
    // This groups multiple keystrokes into 1 billable session
    final rnd = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() => _sessionToken = 'sess-$rnd-${_pickupLat.toInt()}');
  }

  void _setSearchHelper(String? message) {
    if (!mounted) return;
    setState(() => _searchHelperText = message?.trim().isEmpty == true ? null : message);
  }

  Future<Map<String, dynamic>?> _validateServiceableLocation(
    double lat,
    double lng,
  ) async {
    if (lat == 0.0 || lng == 0.0) return null;
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.reverseGeocode}?lat=$lat&lng=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _selectValidatedLocation(
    String name,
    double lat,
    double lng, {
    required bool forDrop,
  }) async {
    final validation = await _validateServiceableLocation(lat, lng);
    if (validation != null && validation['serviceable'] != true) {
      _setSearchHelper(
        validation['message']?.toString() ??
            'Choose a destination inside an active service zone.',
      );
      return false;
    }
    _setSearchHelper(null);
    final resolvedName =
        validation?['formattedAddress']?.toString() ?? validation?['address']?.toString() ?? name;
    if (forDrop) {
      _selectDrop(resolvedName, lat, lng);
    } else {
      _selectStop(resolvedName, lat, lng);
    }
    return true;
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void _onDropChanged(String q) {
    setState(() {
      _activeQuery = q;
      _activeField = true;
    });
    if (_debounce?.isActive == true) _debounce!.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchHelperText = null;
      });
      return;
    }
    // 300ms debounce for Uber-like responsiveness (WAS 450ms)
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  void _onStopChanged(String q) {
    setState(() {
      _activeQuery = q;
      _activeField = false;
    });
    if (_debounce?.isActive == true) _debounce!.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
        _searchHelperText = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String query) async {
    if (!mounted || query.trim().length < 2) return;
    final normalizedQuery = query.trim();
    final requestId = ++_searchRequestId;
    setState(() => _searching = true);
    try {
      Map<String, String> headers = const {};
      try {
        headers = await AuthService.getHeaders();
      } catch (_) {}
      final lat = _pickupLat;
      final lng = _pickupLng;
      
      // Use the session token to optimize API costs
      final qp = StringBuffer('?query=${Uri.encodeComponent(normalizedQuery)}');
      qp.write('&sessionToken=$_sessionToken');
      
      if (lat != 0.0 && lng != 0.0) qp.write('&lat=$lat&lng=$lng');
      
      debugPrint('[PLACES] Searching: $normalizedQuery');
      final r = await http.get(
        Uri.parse('${ApiConfig.placesAutocomplete}$qp'),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      
      if (!mounted || requestId != _searchRequestId) return;
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final preds = (data['predictions'] as List<dynamic>?) ?? [];
        var parsed = preds
              .map((p) {
                final lat2 = (p['lat'] as num?)?.toDouble() ?? 0.0;
                final lng2 = (p['lng'] as num?)?.toDouble() ?? 0.0;
                final main = p['mainText']?.toString() ?? '';
                final sec = p['secondaryText']?.toString() ?? '';
                return <String, dynamic>{
                  'name': p['fullDescription']?.toString() ??
                          p['mainText']?.toString() ?? '',
                  'mainText': main,
                  'secondaryText': sec,
                  'placeId': p['placeId']?.toString() ?? '',
                  'lat': lat2,
                  'lng': lng2,
                  'serviceable': p['serviceable'] == true,
                  'zoneName': p['zoneName']?.toString() ?? '',
                  'distanceMeters': (p['distanceMeters'] as num?)?.toDouble() ?? 0.0,
                };
              })
                .where((r) =>
                    (r['name'] as String).isNotEmpty)
              .cast<Map<String, dynamic>>()
              .toList();
        try {
          final nomQp = Uri.encodeComponent(normalizedQuery);
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
              'distanceMeters': 0.0,
            }).where((p) => (p['name'] as String).isNotEmpty).toList();
            
            final seenNames = parsed.map((p) => p['name'] as String).toSet();
            for (final np in nomPredictions) {
              if (!seenNames.contains(np['name'] as String)) {
                parsed.add(np);
              }
            }
          }
        } catch (_) {}

        if (parsed.isEmpty) {
          parsed = await _localSearchFallback(normalizedQuery);
        }
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults = parsed;
          _searchHelperText =
              parsed.isEmpty
                  ? data['message']?.toString() ??
                      'Choose a destination inside an active service zone.'
                  : null;
        });
        debugPrint('[PLACES] Found ${_searchResults.length} results');
      } else {
        final fallback = await _localSearchFallback(normalizedQuery);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults = fallback;
          _searchHelperText = fallback.isEmpty
              ? 'Only destinations inside active service zones are shown here.'
              : null;
        });
      }
    } catch (e) {
      debugPrint('[PLACES] Error: $e');
      final fallback = await _localSearchFallback(normalizedQuery);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = fallback;
        _searchHelperText = fallback.isEmpty
            ? 'We could not load serviceable destinations right now. Try again or use Pick on Map.'
            : null;
      });
    }
    if (mounted && requestId == _searchRequestId) {
      setState(() => _searching = false);
    }
  }

  Future<List<Map<String, dynamic>>> _localSearchFallback(String query) async {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    final q = query.trim().toLowerCase();

    void addCandidate(Map<String, dynamic> row) {
      final name = row['name']?.toString() ?? '';
      final mainText = row['mainText']?.toString() ?? name;
      final secondaryText = row['secondaryText']?.toString() ?? '';
      final haystack = '$name $mainText $secondaryText'.toLowerCase();
      if (name.isEmpty || !haystack.contains(q)) return;
      final key = '${name.toLowerCase()}|${secondaryText.toLowerCase()}';
      if (seen.add(key)) merged.add(row);
    }

    for (final row in _recent) {
      addCandidate({
        'name': row['name']?.toString() ?? '',
        'mainText': row['name']?.toString() ?? '',
        'secondaryText': row['address']?.toString() ?? 'Recent place',
        'placeId': 'recent:${row['name'] ?? ''}',
        'lat': (row['lat'] as num?)?.toDouble() ?? 0.0,
        'lng': (row['lng'] as num?)?.toDouble() ?? 0.0,
      });
    }

    for (final row in _popular) {
      addCandidate({
        'name': row['name']?.toString() ?? '',
        'mainText': row['name']?.toString() ?? '',
        'secondaryText': 'Popular location',
        'placeId': 'popular:${row['name'] ?? ''}',
        'lat': (row['lat'] as num?)?.toDouble() ?? 0.0,
        'lng': (row['lng'] as num?)?.toDouble() ?? 0.0,
      });
    }

    if (merged.length >= 5) return merged.take(8).toList();

    final nominatim = await _searchPlacesFallback(query);
    for (final row in nominatim) {
      addCandidate(row);
    }
    return merged.take(8).toList();
  }

  Future<List<Map<String, dynamic>>> _searchPlacesFallback(String query) async {
    try {
      final r = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=8&addressdetails=1&countrycodes=in',
        ),
        headers: const {'User-Agent': 'JAGOPro/1.0'},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return const [];
      final data = jsonDecode(r.body) as List<dynamic>;
      return data.map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        return <String, dynamic>{
          'name': row['display_name']?.toString() ?? '',
          'mainText': row['name']?.toString() ?? '',
          'secondaryText': '',
          'placeId': 'nom:${row['place_id']}',
          'lat': double.tryParse((row['lat'] ?? '').toString()) ?? 0.0,
          'lng': double.tryParse((row['lon'] ?? '').toString()) ?? 0.0,
        };
      }).where((row) => (row['name'] as String).isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Selection Handlers ────────────────────────────────────────────────────
  void _selectDrop(String name, double lat, double lng) {
    HapticFeedback.selectionClick();
    _saveRecent(name, lat, lng);
    setState(() {
      _drop = name;
      _dropLat = lat;
      _dropLng = lng;
      _dropCtrl.text = name;
      _searchResults = [];
      _searchHelperText = null;
    });
    FocusScope.of(context).unfocus();
    _resetSessionToken(); // Reset token after a successful selection
    _tryProceed();
  }

  void _selectStop(String name, double lat, double lng) {
    HapticFeedback.selectionClick();
    setState(() {
      _stop = name;
      _stopLat = lat;
      _stopLng = lng;
      _stopCtrl.text = name;
      _searchResults = [];
      _searchHelperText = null;
    });
    FocusScope.of(context).unfocus();
  }

  /// Resolves place coordinates from server then selects drop/stop.
  /// For local DB predictions lat/lng are inline; Google predictions need a detail fetch.
  Future<void> _selectFromSearch(
      Map<String, dynamic> p, {required bool forDrop}) async {
    final name = p['name']?.toString() ?? '';
    var lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
    var lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
    final placeId = p['placeId']?.toString() ?? '';
    if (p['serviceable'] != true) {
      _setSearchHelper('Choose a destination inside an active service zone.');
      return;
    }
    if ((lat == 0.0 || lng == 0.0) &&
        placeId.isNotEmpty &&
        !placeId.startsWith('local:')) {
      setState(() => _detectingLocation = true);
      try {
        final headers = await AuthService.getHeaders();
        final r = await http
            .get(
              Uri.parse(
                  '${ApiConfig.placeDetails}?placeId=${Uri.encodeComponent(placeId)}&sessionToken=$_sessionToken'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body) as Map<String, dynamic>;
          if (d['serviceable'] != true) {
            if (mounted) setState(() => _detectingLocation = false);
            _setSearchHelper(
              d['message']?.toString() ??
                  'Choose a destination inside an active service zone.',
            );
            return;
          }
          lat = (d['lat'] as num?)?.toDouble() ?? 0.0;
          lng = (d['lng'] as num?)?.toDouble() ?? 0.0;
          final resolvedName = d['address']?.toString() ?? name;
          if (!mounted) return;
          setState(() => _detectingLocation = false);
          await _selectValidatedLocation(
            resolvedName,
            lat,
            lng,
            forDrop: forDrop,
          );
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _detectingLocation = false);
    }
    if (lat == 0.0 || lng == 0.0) {
      _setSearchHelper(
        'Could not load that destination. Try another suggestion or use Pick on Map.',
      );
      return;
    }
    await _selectValidatedLocation(name, lat, lng, forDrop: forDrop);
  }

  void _tryProceed() {
    if (_pickup.isEmpty || _drop.isEmpty) return;
    if (_pickupLat == 0 && _pickupLng == 0) return;
    _proceedToVehicles();
  }

  void _proceedToVehicles() {
    if (_dropLat == 0 && _dropLng == 0) {
      _setSearchHelper('Select a serviceable destination to continue.');
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BookingScreen(
          pickup: _pickup,
          destination: _drop,
          pickupLat: _pickupLat,
          pickupLng: _pickupLng,
          destLat: _dropLat,
          destLng: _dropLng,
          category: widget.serviceType,
          vehicleCategoryId: widget.vehicleCategoryId,
          vehicleCategoryName: widget.vehicleCategoryName,
        ),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  // ── Map Picker ────────────────────────────────────────────────────────────
  Future<void> _pickDropOnMap() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(
          title: _isParcel ? 'Select delivery location' : 'Select Drop Location',
          initialLat: _pickupLat != 0 ? _pickupLat : null,
          initialLng: _pickupLng != 0 ? _pickupLng : null,
          accentColor: _accent,
        ),
      ),
    );
    if (result != null) {
      _selectDrop(result.address, result.lat, result.lng);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildInputCard(),
          if (_showStop) _buildStopField(),
          Expanded(child: _buildSuggestions()),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _fieldBorder),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: JT.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _isParcel ? 'Send Parcel' : 'Book a Ride',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: JT.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              _isParcel
                  ? 'Choose pickup & delivery location'
                  : 'Where are you going?',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: JT.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),
        // Service badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _accentLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _isParcel
                  ? Icons.local_shipping_rounded
                  : Icons.electric_rickshaw_rounded,
              color: _accent,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              _isParcel ? 'Parcel' : 'Ride',
              style: GoogleFonts.poppins(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Input Card ────────────────────────────────────────────────────────────
  Widget _buildInputCard() {
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _fieldBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: [
          // ── Pickup row ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Green dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.3),
                      width: 3),
                  boxShadow: [
                    BoxShadow(
                        color:
                            _accent.withValues(alpha: 0.3),
                        blurRadius: 6)
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _detectingLocation
                    ? Row(children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _accent),
                        ),
                        const SizedBox(width: 8),
                        Text('Detecting your location…',
                            style: GoogleFonts.poppins(
                                color: JT.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ])
                    : GestureDetector(
                        onTap: _pickup.isEmpty ? _detectLocation : null,
                        child: Text(
                          _pickup.isEmpty
                              ? 'Detecting current location…'
                              : _pickup.split(', ').take(2).join(', '),
                          style: GoogleFonts.poppins(
                            color: _pickup.isEmpty
                                ? JT.textSecondary
                                : JT.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              // GPS re-detect button
              GestureDetector(
                onTap: _detectLocation,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.my_location_rounded,
                      color: _accent, size: 16),
                ),
              ),
            ]),
          ),

          // Divider with dashes
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Row(children: List.generate(
                20,
                (i) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: 1,
                        color: i.isEven
                            ? _fieldBorder
                            : Colors.transparent,
                      ),
                    ))),
          ),

          // ── Drop row ──
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Red pin
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.3), width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withValues(alpha: 0.35),
                        blurRadius: 6)
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _dropCtrl,
                  focusNode: _dropFocus,
                  style: GoogleFonts.poppins(
                    color: JT.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: _isParcel
                        ? 'Enter delivery location'
                        : 'Where to?',
                    hintStyle: GoogleFonts.poppins(
                      color: JT.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onChanged: _onDropChanged,
                  onSubmitted: (_) => _tryProceed(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              if (_dropCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _dropCtrl.clear();
                    setState(() {
                      _drop = '';
                      _searchResults = [];
                    });
                    _dropFocus.requestFocus();
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: JT.textSecondary),
                ),
            ]),
          ),

          // ── Action buttons ──
          Container(
            decoration: BoxDecoration(
              color: _accentLight,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(
                  top: BorderSide(color: _fieldBorder)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              // Pick on Map
              _actionChip(
                Icons.map_rounded,
                'Pick on Map',
                onTap: _pickDropOnMap,
              ),
              const SizedBox(width: 8),
              // Add Stop
              if (!_showStop)
                _actionChip(
                  Icons.add_location_alt_rounded,
                  'Add Stop',
                  onTap: () {
                    setState(() => _showStop = true);
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) _stopFocus.requestFocus();
                    });
                  },
                ),
              if (_showStop)
                _actionChip(
                  Icons.remove_circle_outline_rounded,
                  'Remove Stop',
                  onTap: () {
                    setState(() {
                      _showStop = false;
                      _stop = '';
                      _stopCtrl.clear();
                    });
                  },
                  isDestructive: true,
                ),
              const Spacer(),
              // Proceed button (shows when drop is selected)
              if (_drop.isNotEmpty)
                GestureDetector(
                  onTap: _proceedToVehicles,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_accent, _accent.withValues(alpha: 0.8)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        'See Vehicles',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 14),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label,
      {required VoidCallback onTap, bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFFEF2F2)
              : _accentLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDestructive
                ? const Color(0xFFFCA5A5)
                : _accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            icon,
            size: 14,
            color: isDestructive
                ? const Color(0xFFEF4444)
                : _accent,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDestructive
                  ? const Color(0xFFEF4444)
                  : _accent,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Add Stop Field ─────────────────────────────────────────────────────────
  Widget _buildStopField() {
    final stopColor = _isParcel ? JT.parcelGold : JT.secondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: stopColor,
            shape: BoxShape.circle,
            border: Border.all(
                color: stopColor.withValues(alpha: 0.3),
                width: 3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _stopCtrl,
            focusNode: _stopFocus,
            style: GoogleFonts.poppins(
              color: JT.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration.collapsed(
              hintText: 'Add a stop along the way',
              hintStyle: GoogleFonts.poppins(
                color: JT.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            onChanged: _onStopChanged,
          ),
        ),
        Icon(Icons.add_circle_outline_rounded,
            size: 18, color: stopColor),
      ]),
    );
  }

  // ── Suggestions ────────────────────────────────────────────────────────────
  Widget _buildSuggestions() {
    final isSearching = _activeQuery.length >= 2;
    final List<Map<String, dynamic>> items =
        isSearching ? _searchResults : [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ── Quick Actions ──
        if (!isSearching) ...[
          _placeRow(
            name: 'Current Location',
            mainText: 'Current Location',
            secondaryText: 'Using GPS for accuracy',
            icon: Icons.my_location_rounded,
            iconColor: _accent,
            onTap: () {
              // Usually handled by the manual map picker or geocoding
              _pickDropOnMap(); 
            },
          ),
          const SizedBox(height: 8),
        ],

        // Search results
        if (isSearching) ...[
          if (_searching && items.isEmpty)
            _buildShimmerLoading()
          else if (items.isNotEmpty) ...[
            _sectionHeader('Search Results', Icons.search_rounded),
            ...items.map((p) {
               final dist = (p['lat'] != 0.0) 
                  ? JT.calculateDistance(_pickupLat, _pickupLng, p['lat'], p['lng'])
                  : null;
                return _placeRow(
                  name: p['name']?.toString() ?? '',
                  mainText: p['mainText']?.toString() ?? '',
                  secondaryText: p['secondaryText']?.toString() ?? '',
                  distanceKm: dist,
                  icon: Icons.location_on_rounded,
                  iconColor: _accent,
                  onTap: () => _selectFromSearch(p, forDrop: _activeField),
                );
            }),
          ] else if (!_searching)
            _buildNoResults(),
          if (_searchHelperText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: JT.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _searchHelperText!,
                      style: GoogleFonts.poppins(
                        color: JT.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]

        // Default state: recent + popular
        else ...[
          // Recent places
          if (_recent.isNotEmpty) ...[
            _sectionHeader('Recent', Icons.history_rounded),
            ..._recent.map((p) => _placeRow(
                  name: p['name']?.toString() ?? '',
                  mainText: p['name']?.toString() ?? '',
                  secondaryText: p['address']?.toString() ?? 'Recent search',
                  icon: Icons.history_rounded,
                  iconColor: JT.textSecondary,
                  onTap: () => _selectValidatedLocation(
                    p['name'] ?? '',
                    (p['lat'] as num).toDouble(),
                    (p['lng'] as num).toDouble(),
                    forDrop: true,
                  ),
                )),
            const SizedBox(height: 12),
          ],

          // Popular locations
          if (_popular.isNotEmpty) ...[
            _sectionHeader('Popular Locations', Icons.star_rounded),
            ..._popular.map((p) {
                  final dist = JT.calculateDistance(
                      _pickupLat, _pickupLng, 
                      (p['lat'] as num?)?.toDouble() ?? 0.0, 
                      (p['lng'] as num?)?.toDouble() ?? 0.0);
                  return _placeRow(
                    name: p['name']?.toString() ?? '',
                    mainText: p['name']?.toString() ?? '',
                    secondaryText: 'Popular Location',
                    distanceKm: dist > 0 ? dist : null,
                    icon: Icons.place_rounded,
                    iconColor: _accent,
                    onTap: () => _selectValidatedLocation(
                      p['name'] ?? '',
                      (p['lat'] as num).toDouble(),
                      (p['lng'] as num).toDouble(),
                      forDrop: true,
                    ),
                  );
                }),
          ],
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: JT.textSecondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 12, color: JT.textSecondary),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.poppins(
            color: JT.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: JT.textSecondary.withValues(alpha: 0.1), thickness: 1)),
      ]),
    );
  }

  Widget _placeRow({
    required String name,
    required String mainText,
    required String secondaryText,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    double? distanceKm,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5FA)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          // Premium Icon setup
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  iconColor.withValues(alpha: 0.15),
                  iconColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mainText.isNotEmpty ? mainText : name,
                        style: GoogleFonts.poppins(
                          color: JT.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (distanceKm != null)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${distanceKm.toStringAsFixed(1)} km',
                          style: GoogleFonts.poppins(
                            color: iconColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (secondaryText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      secondaryText,
                      style: GoogleFonts.poppins(
                        color: JT.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _accentLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_forward_ios_rounded,
                size: 10, color: JT.textSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Column(
      children: List.generate(
          5,
          (i) => Shimmer.fromColors(
                baseColor: Colors.grey[200]!,
                highlightColor: Colors.white,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.location_off_rounded, color: JT.iconInactive, size: 48),
        const SizedBox(height: 12),
        Text('No locations found',
            style: GoogleFonts.poppins(color: JT.textSecondary, fontSize: 13)),
        if (_searchHelperText != null) ...[
          const SizedBox(height: 8),
          Text(
            _searchHelperText!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: JT.textSecondary, fontSize: 12),
          ),
        ],
      ]),
    );
  }
}
