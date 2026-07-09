import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../widgets/jago_map_markers.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';

/// Result returned by [MapLocationPicker] when user confirms a location.
class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  const PickedLocation({required this.lat, required this.lng, required this.address});
}

/// Uber-style full-screen map location picker.
///
/// Usage:
/// ```dart
/// final result = await Navigator.push<PickedLocation>(
///   context,
///   MaterialPageRoute(builder: (_) => MapLocationPicker(title: 'Select Pickup')),
/// );
/// if (result != null) {
///   print('${result.lat}, ${result.lng} → ${result.address}');
/// }
/// ```
///
/// Reuse for different purposes:
/// - **Pickup**: `MapLocationPicker(title: 'Select Pickup Location')`
/// - **Drop**: `MapLocationPicker(title: 'Select Drop Location')`
/// - **Saved places**: `MapLocationPicker(title: 'Set Home Location')`
/// - **Pre-filled**: `MapLocationPicker(initialLat: 16.5, initialLng: 80.6)`
class MapLocationPicker extends StatefulWidget {
  /// Header title shown in the app bar.
  final String title;

  /// Optional initial position. If null, uses device GPS.
  final double? initialLat;
  final double? initialLng;

  const MapLocationPicker({
    super.key,
    this.title = 'Select Location',
    this.initialLat,
    this.initialLng,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  final JagoMapController _mapController = JagoMapController();
  LatLng? _pendingCamera; // camera move queued before map ready

  // Current center of the map (source of truth)
  // null until GPS is confirmed — avoids biasing search toward a hardcoded city
  double? _gpsLat;
  double? _gpsLng;
  double? _lat; // null until GPS is fetched
  double? _lng;
  String _address = 'Move the map to select location';
  bool _geocoding = false;
  bool _locationLoading = true;
  bool _serviceable = true;
  String? _zoneName;

  // Search state
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<_PlacePrediction> _predictions = [];
  bool _searching = false;
  bool _showSearch = false;
  Timer? _debounce;
  int _searchRequestId = 0;
  String? _searchHelperText;

  // Session token for Places Autocomplete (reduces billing)
  String _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();

  // API calls are proxied through server — no client-side key needed

  // ─── Reverse Geocode ─────────────────────────────────────────────
  Future<void> _reverseGeocode(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    setState(() => _geocoding = true);
    // Try server proxy first for consistency with the main home screen logic
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.reverseGeocode}?lat=$lat&lng=$lng'),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted && lat == _lat && lng == _lng) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['formattedAddress']?.toString() ?? '';
        if (addr.isNotEmpty) {
          setState(() {
            _address = addr;
            _serviceable = data['serviceable'] != false;
            _zoneName = data['zoneName']?.toString();
            _geocoding = false;
          });
          return;
        }
      }
    } catch (_) {}
    // Nominatim fallback
    try {
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng'),
        headers: const {'User-Agent': 'JagoPro/1.0'},
      ).timeout(const Duration(seconds: 5));
      // Defensive check: ensure results match current map center to avoid stale address updates
      if (res.statusCode == 200 && mounted && lat == _lat && lng == _lng) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = data['display_name']?.toString() ?? '';
        if (addr.isNotEmpty) {
          setState(() {
            _address = addr;
            _serviceable = false;
            _zoneName = null;
            _geocoding = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[MAP] Geocode error: $e');
    }
    if (mounted) setState(() { _address = _address == 'Move the map to select location' ? 'Unknown Location' : _address; _geocoding = false; });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null &&
        widget.initialLat != 0 && widget.initialLng != 0) {
      _lat = widget.initialLat!;
      _lng = widget.initialLng!;
      _locationLoading = false;
      _reverseGeocode(_lat!, _lng!);
    } else {
      // Show map immediately on all devices (Oppo/slow GPS must not block tiles).
      _lat = 16.5062;
      _lng = 80.6480;
      _locationLoading = false;
      _address = 'Move the map to select location';
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ─── Location ───────────────────────────────────────────────────────────

  Future<void> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final lastPos = await Geolocator.getLastKnownPosition();
      if (!serviceEnabled) {
        if (lastPos != null && mounted) {
          setState(() {
            // Use last known if valid, otherwise fallback to a default city center
            _lat = (lastPos.latitude != 0 && lastPos.latitude != 0.0) ? lastPos.latitude : 16.5062;
            _lng = (lastPos.longitude != 0 && lastPos.longitude != 0.0) ? lastPos.longitude : 80.6480;
            _gpsLat = lastPos.latitude;
            _gpsLng = lastPos.longitude;
            _locationLoading = false;
            _address = 'Using last known location';
          });
          final target = LatLng(_lat!, _lng!);
          if (!_locationLoading) {
            _mapController.moveZoom(target, 14);
          } else {
            _pendingCamera = target;
          }
          _reverseGeocode(_lat, _lng);
          return;
        }
        // Ensure loading is stopped even if no location is found
        setState(() {
          _lat = 16.5062; // Default (e.g., Vijayawada)
          _lng = 80.6480;
          _locationLoading = false;
          _address = 'Location services disabled. Showing default.';
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        setState(() {
          _locationLoading = false;
          _lat = 16.5062;
          _lng = 80.6480;
          _address = 'Location permission is needed to detect your current location.';
        });
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _locationLoading = false;
          _lat = 16.5062;
          _lng = 80.6480;
          _address = 'Location permission is blocked. Enable it from settings.';
        });
        return;
      }

      if (lastPos != null && mounted) {
        setState(() {
          // Ensure we have non-zero coordinates, otherwise fallback to default
          final isValid = lastPos.latitude != 0 && lastPos.longitude != 0;
          _lat = isValid ? lastPos.latitude : (_lat ?? 16.5062);
          _lng = isValid ? lastPos.longitude : (_lng ?? 80.6480);
          _gpsLat = lastPos.latitude;
          _gpsLng = lastPos.longitude;
        });
        final target = LatLng(_lat!, _lng!);
        if (!_locationLoading) {
          _mapController.moveZoom(target, 14);
        } else {
          _pendingCamera = target;
        }
        _reverseGeocode(_lat, _lng);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude != 0 ? pos.latitude : (_lat ?? 16.5062);
        _lng = pos.longitude != 0 ? pos.longitude : (_lng ?? 80.6480);
        _gpsLat = pos.latitude;
        _gpsLng = pos.longitude;
        _locationLoading = false;
        _address = 'Current location';
      });
      final target = LatLng(_lat!, _lng!);
      if (!_locationLoading) {
        _mapController.moveZoom(target, 14);
      } else {
        _pendingCamera = target;
      }
      _reverseGeocode(_lat, _lng);
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _lat ??= 16.5062;
          _lng ??= 80.6480;
          if (_address == 'Move the map to select location') {
            _address = 'Could not detect GPS. Move map to your area.';
          }
        });
      }
    }
  }

  // ─── Places Autocomplete Search ─────────────────────────────────────────

  Future<void> _searchPlaces(String query) async {
    if (query.length < 3) {
      setState(() {
        _predictions = [];
        _searchHelperText = null;
      });
      return;
    }
    final normalizedQuery = query.trim();
    final requestId = ++_searchRequestId;
    setState(() => _searching = true);
    try {
      Map<String, String> headers = const {};
      try {
        headers = await AuthService.getHeaders();
      } catch (_) {}
      final hasGps = _gpsLat != null && _gpsLng != null;
      final qp = StringBuffer('?query=${Uri.encodeComponent(normalizedQuery)}&sessionToken=$_sessionToken');
      if (hasGps) qp.write('&lat=$_gpsLat&lng=$_gpsLng');
      List<_PlacePrediction> finalPredictions = [];
      String? helperText;
      
      try {
        final res = await http.get(Uri.parse('${ApiConfig.placesAutocomplete}$qp'), headers: headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          helperText = data['message']?.toString();
          final preds = (data['predictions'] as List<dynamic>?) ?? [];
          finalPredictions.addAll(preds.map((p) => _PlacePrediction(
            placeId: p['placeId']?.toString() ?? '',
            description: p['fullDescription']?.toString() ?? p['mainText']?.toString() ?? '',
            mainText: p['mainText']?.toString() ?? '',
            secondaryText: p['secondaryText']?.toString() ?? '',
            lat: (p['lat'] as num?)?.toDouble(),
            lng: (p['lng'] as num?)?.toDouble(),
            serviceable: p['serviceable'] == true,
            zoneName: p['zoneName']?.toString() ?? '',
          )));
        }
      } catch (_) {}

      try {
        final nomQp = Uri.encodeComponent(normalizedQuery);
        final nomRes = await http.get(
          Uri.parse('https://nominatim.openstreetmap.org/search?q=$nomQp&format=json&addressdetails=1&limit=5&countrycodes=in'),
          headers: {'User-Agent': 'JagoCustomerApp/1.0'},
        ).timeout(const Duration(seconds: 4));
        if (nomRes.statusCode == 200) {
          final nomData = jsonDecode(nomRes.body) as List<dynamic>;
          finalPredictions.addAll(nomData.map((p) => _PlacePrediction(
            placeId: 'nom:${p['place_id']}',
            description: p['display_name']?.toString() ?? '',
            mainText: p['name']?.toString() ?? '',
            secondaryText: p['display_name']?.toString() ?? '',
            lat: double.tryParse(p['lat']?.toString() ?? '0'),
            lng: double.tryParse(p['lon']?.toString() ?? '0'),
            serviceable: true,
            zoneName: '',
          )));
        }
      } catch (_) {}

      if (!mounted || requestId != _searchRequestId) return;

      final seen = <String>{};
      final uniquePredictions = finalPredictions.where((p) {
        final name = p.description;
        if (seen.contains(name)) return false;
        seen.add(name);
        return name.isNotEmpty && p.serviceable;
      }).toList();

      setState(() {
        _predictions = uniquePredictions;
        _searchHelperText = uniquePredictions.isEmpty ? helperText : null;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _predictions = [];
        _searchHelperText =
            'We could not load serviceable destinations right now. Try again in a moment.';
      });
    }
    if (mounted && requestId == _searchRequestId) {
      setState(() => _searching = false);
    }
  }

  Future<List<_PlacePrediction>> _searchPlacesFallback(String query) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=8&addressdetails=1&countrycodes=in',
        ),
        headers: const {'User-Agent': 'JAGOPro/1.0'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as List<dynamic>;
      return data.map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        return _PlacePrediction(
          placeId: 'nom:${row['place_id']}',
          description: row['display_name']?.toString() ?? '',
          mainText: row['name']?.toString() ?? '',
          secondaryText: '',
          lat: double.tryParse((row['lat'] ?? '').toString()),
          lng: double.tryParse((row['lon'] ?? '').toString()),
          serviceable: false,
        );
      }).where((pred) => pred.description.isNotEmpty).toList();
    } catch (_) {}
    return const [];
  }

  /// Get lat/lng from a Place ID using Place Details API.
  Future<void> _selectPrediction(_PlacePrediction pred) async {
    setState(() {
      _showSearch = false;
      _predictions = [];
      _searchCtrl.clear();
      _geocoding = true;
    });
    _searchFocus.unfocus();

    // If the prediction already has coordinates (local DB result), use them directly
    if (pred.lat != null && pred.lng != null && pred.lat != 0.0 && pred.lng != 0.0) {
      if (!pred.serviceable) {
        if (mounted) {
          setState(() {
            _geocoding = false;
            _searchHelperText =
                'Choose a location inside an active service zone.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _lat = pred.lat!;
          _lng = pred.lng!;
          _address = pred.description;
          _serviceable = true;
          _zoneName = pred.zoneName;
          _geocoding = false;
        });
        final target = LatLng(_lat!, _lng!);
        _mapController.moveZoom(target, 16);
      }
      return;
    }

    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.placeDetails}?placeId=${Uri.encodeComponent(pred.placeId)}&sessionToken=$_sessionToken',
        ),
        headers: headers,
      ).timeout(const Duration(seconds: 6));
      // Generate a new session token after a detail fetch
      _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newLat = (data['lat'] as num?)?.toDouble() ?? 0.0;
        final newLng = (data['lng'] as num?)?.toDouble() ?? 0.0;
        final address = data['address']?.toString() ?? pred.description;
        if (data['serviceable'] != true) {
          setState(() {
            _geocoding = false;
            _searchHelperText =
                'Choose a location inside an active service zone.';
          });
          return;
        }
        if (newLat != 0.0 && newLng != 0.0 && mounted) {
          setState(() {
            _lat = newLat;
            _lng = newLng;
            _address = address;
            _serviceable = true;
            _zoneName = data['zoneName']?.toString();
            _geocoding = false;
          });
          _mapController.moveZoom(LatLng(newLat, newLng), 16);
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _geocoding = false;
        _searchHelperText =
            'Could not load that destination. Try another serviceable result or move the map.';
      });
    }
  }

  // ─── Map callbacks ─────────────────────────────────────────────────────

  void _onCameraIdle() {
    _reverseGeocode(_lat, _lng);
  }

  void _onCameraMove(CameraPosition pos) {
    _lat = pos.target.latitude;
    _lng = pos.target.longitude;
  }

  void _onMyLocationTap() async {
    await _getCurrentLocation();
  }

  void _confirmLocation() {
    if (_lat != null && _lng != null) {
      if (!_serviceable) {
        setState(() {
          _searchHelperText =
              'This location is outside the active service zone. Move the map to a served area.';
        });
        return;
      }
      Navigator.pop(
        context,
        PickedLocation(lat: _lat!, lng: _lng!, address: _address),
      );
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: JT.bg,
      body: Stack(
        children: [
          // ── Google Map ────────────────────────────────────────────────
          if (!_locationLoading && _lat != null && _lng != null)
            Positioned.fill(
              child: JagoMapView(
              controller: _mapController,
              initialCameraPosition: CameraPosition(
                target: LatLng(_lat!, _lng!),
                zoom: 15,
              ),
              padding: const EdgeInsets.only(bottom: 240),
              onMapCreated: (_) {
                if (_pendingCamera != null) {
                  _mapController.moveZoom(_pendingCamera!, 15);
                  _pendingCamera = null;
                }
              },
              onCameraMove: (pos) {
                _lat = pos.target.latitude;
                _lng = pos.target.longitude;
              },
              onCameraIdle: () {
                if (mounted) setState(() {});
                _reverseGeocode(_lat, _lng);
              },
            ),
            ),
          if (_locationLoading)
            const Center(child: CircularProgressIndicator()),

          // ── Center Map Pointer ─────────────────────────────────────────
          if (!_locationLoading && _lat != null && _lng != null)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 240),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Floating Icon
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Text(
                          _geocoding ? 'Loading...' : 'Set Location Here',
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.location_on, size: 48, color: JT.primary),
                      // Small dot representing the exact coordinate
                      Container(
                        width: 8, height: 4,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // Spacer to ensure the dot rests at the exact vertical center
                      const SizedBox(height: 80), 
                    ],
                  ),
                ),
              ),
            ),

        // ── Top layer (Search or Title) ──────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _showSearch
                  ? Column(
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 8),
                        _buildSearchResults(),
                      ],
                    )
                  : _buildTopBar(),
            ),
          ),
        ),

          // ── Bottom card (address + confirm) ─────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomCard(bottomPadding),
          ),

          // ── My location FAB ─────────────────────────────────────────
          Positioned(
            bottom: 200 + bottomPadding,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'my_loc',
              backgroundColor: Colors.white,
              onPressed: _onMyLocationTap,
              child: _locationLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: JT.primary),
                    )
                  : const Icon(Icons.my_location, color: JT.primary, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top bar widgets ────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: JT.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.title,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: JT.textPrimary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, color: JT.primary),
            onPressed: () {
              setState(() => _showSearch = true);
              Future.delayed(const Duration(milliseconds: 100), () => _searchFocus.requestFocus());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: JT.textPrimary),
            onPressed: () {
              setState(() {
                _showSearch = false;
                _predictions = [];
                _searchCtrl.clear();
                _searchHelperText = null;
              });
              _searchFocus.unfocus();
            },
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: GoogleFonts.poppins(fontSize: 15, color: JT.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search for a place...',
                hintStyle: GoogleFonts.poppins(fontSize: 15, color: JT.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => _searchPlaces(v));
              },
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: JT.textSecondary, size: 20),
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _predictions = []);
              },
            ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: JT.primary)),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _predictions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
        itemBuilder: (_, i) {
          final pred = _predictions[i];
          return ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: JT.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined, color: JT.primary, size: 20),
            ),
            title: Text(
              pred.mainText,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: JT.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              pred.secondaryText,
              style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            dense: true,
            onTap: () => _selectPrediction(pred),
          );
        },
      ),
    );
  }

  // ─── Bottom card ────────────────────────────────────────────────────────

  Widget _buildBottomCard(double bottomPadding) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFDCE9FF), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // Location icon + address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JT.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded, color: JT.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Location',
                      style: GoogleFonts.poppins(fontSize: 12, color: JT.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    _geocoding
                        ? Row(children: [
                            const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: JT.primary),
                            ),
                            const SizedBox(width: 8),
                            Text('Getting address...', style: GoogleFonts.poppins(fontSize: 13, color: JT.textSecondary)),
                          ])
                        : Text(
                            _address,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: JT.textPrimary),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _serviceable
                            ? JT.primary.withValues(alpha: 0.1)
                            : const Color(0xFFF43F5E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _serviceable
                            ? (_zoneName != null && _zoneName!.isNotEmpty
                                ? 'Serving in $_zoneName'
                                : 'Serving area')
                            : 'Not serving this area',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _serviceable ? JT.primary : const Color(0xFFBE123C),
                        ),
                      ),
                    ),
                    if (_searchHelperText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _searchHelperText!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: JT.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Lat/lng display
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Text(
              (_lat != null && _lng != null)
                  ? '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
                  : 'Location not set',
              style: GoogleFonts.poppins(fontSize: 11, color: JT.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // Confirm button
          JT.gradientButton(
            label: 'Confirm Location',
            onTap: _confirmLocation,
          ),
        ],
      ),
    );
  }
}

// ─── Data model for Place predictions ──────────────────────────────────────
class _PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
  final double? lat;
  final double? lng;
  final bool serviceable;
  final String? zoneName;
  const _PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
    this.lat,
    this.lng,
    this.serviceable = true,
    this.zoneName,
  });
}
