import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';

class RidePreferencesScreen extends StatefulWidget {
  const RidePreferencesScreen({super.key});
  @override
  State<RidePreferencesScreen> createState() => _RidePreferencesScreenState();
}

class _RidePreferencesScreenState extends State<RidePreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _quietRide = false;
  bool _acPreferred = true;
  bool _musicOff = false;
  bool _wheelchairAccessible = false;
  bool _extraLuggage = false;
  String _preferredGender = 'any';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/app/customer/preferences'), headers: headers);
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body);
        setState(() {
          _quietRide = d['quietRide'] ?? false;
          _acPreferred = d['acPreferred'] ?? true;
          _musicOff = d['musicOff'] ?? false;
          _wheelchairAccessible = d['wheelchairAccessible'] ?? false;
          _extraLuggage = d['extraLuggage'] ?? false;
          _preferredGender = d['preferredGender'] ?? 'any';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final headers = await AuthService.getHeaders();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/app/customer/preferences'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'quietRide': _quietRide,
          'acPreferred': _acPreferred,
          'musicOff': _musicOff,
          'wheelchairAccessible': _wheelchairAccessible,
          'extraLuggage': _extraLuggage,
          'preferredGender': _preferredGender,
        }),
      );
      if (!mounted) return;
      final body = jsonDecode(res.body);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(body['message'] ?? 'Saved!'),
        backgroundColor: res.statusCode == 200 ? JT.success : JT.error,
      ));
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JT.surfaceAlt,
      appBar: AppBar(
        backgroundColor: JT.bg,
        foregroundColor: JT.textPrimary,
        elevation: 0,
        title: Text('Ride Preferences', style: JT.h4),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save', style: JT.h5.copyWith(color: JT.primary)),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: JT.primary))
          : SingleChildScrollView(
              padding: EdgeInsets.all(JT.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _banner(),
                  SizedBox(height: JT.spacing16),
                  Text('Comfort Preferences', style: JT.h5),
                  SizedBox(height: JT.spacing8),
                  _prefCard('Quiet Ride', 'No unnecessary conversation', Icons.volume_off, _quietRide, (v) => setState(() => _quietRide = v)),
                  _prefCard('AC Preferred', 'AC on during ride', Icons.ac_unit, _acPreferred, (v) => setState(() => _acPreferred = v)),
                  _prefCard('Music Off', 'Prefer silence during ride', Icons.music_off, _musicOff, (v) => setState(() => _musicOff = v)),
                  SizedBox(height: JT.spacing16),
                  Text('Special Requirements', style: JT.h5),
                  SizedBox(height: JT.spacing8),
                  _prefCard('Wheelchair Accessible', 'Need accessible vehicle', Icons.accessible, _wheelchairAccessible, (v) => setState(() => _wheelchairAccessible = v)),
                  _prefCard('Extra Luggage', 'Have large bags / extra luggage', Icons.luggage, _extraLuggage, (v) => setState(() => _extraLuggage = v)),
                  SizedBox(height: JT.spacing16),
                  Text('Driver Preference', style: JT.h5),
                  SizedBox(height: JT.spacing8),
                  Container(
                    padding: EdgeInsets.all(JT.spacing16),
                    decoration: BoxDecoration(color: JT.bg, borderRadius: BorderRadius.circular(JT.radiusLg)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preferred Driver Gender', style: JT.bodyPrimary),
                        SizedBox(height: JT.spacing12),
                        Row(children: [
                          _genderChoice('any', 'No Preference', Icons.people),
                          SizedBox(width: JT.spacing8),
                          _genderChoice('female', 'Women Driver', Icons.female),
                          SizedBox(width: JT.spacing8),
                          _genderChoice('male', 'Male Driver', Icons.male),
                        ]),
                        if (_preferredGender == 'female') ...[
                          SizedBox(height: JT.spacing8),
                          Container(
                            padding: EdgeInsets.all(JT.spacing8 + 2),
                            decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(JT.radiusSm)),
                            child: Row(children: [
                              const Icon(Icons.shield, color: Colors.pink, size: 16),
                              SizedBox(width: JT.spacing6),
                              Expanded(child: Text('Best effort to assign women driver.\nAvailability may vary.', style: JT.caption.copyWith(color: Colors.pink))),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: JT.spacing24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JT.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JT.radiusMd + 2)),
                        padding: EdgeInsets.symmetric(vertical: JT.spacing16),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Save Preferences', style: JT.btnText),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _banner() => Container(
    padding: EdgeInsets.all(JT.spacing12 + 2),
    decoration: BoxDecoration(
      color: JT.primaryLight,
      borderRadius: BorderRadius.circular(JT.radiusMd),
      border: Border.all(color: JT.primary.withValues(alpha: 0.2)),
    ),
    child: Row(children: [
      Icon(Icons.tune, color: JT.primary),
      SizedBox(width: JT.spacing8 + 2),
      Expanded(child: Text('Your preferences are shared with the driver before every ride. We\'ll match your preferences as much as possible.',
          style: JT.caption.copyWith(height: 1.4))),
    ]),
  );

  Widget _prefCard(String title, String subtitle, IconData icon, bool val, Function(bool) onChanged) => Container(
    margin: EdgeInsets.only(bottom: JT.spacing8),
    padding: EdgeInsets.symmetric(horizontal: JT.spacing16, vertical: JT.spacing12),
    decoration: BoxDecoration(color: JT.bg, borderRadius: BorderRadius.circular(JT.radiusLg)),
    child: Row(children: [
      Container(
        padding: EdgeInsets.all(JT.spacing8),
        decoration: BoxDecoration(color: val ? JT.primary.withValues(alpha: 0.1) : JT.borderLight, shape: BoxShape.circle),
        child: Icon(icon, color: val ? JT.primary : JT.textTertiary, size: 20),
      ),
      SizedBox(width: JT.spacing12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: JT.bodyPrimary),
          Text(subtitle, style: JT.caption),
        ],
      )),
      Switch(value: val, onChanged: onChanged, activeThumbColor: JT.primary),
    ]),
  );

  Widget _genderChoice(String value, String label, IconData icon) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _preferredGender = value),
      child: Container(
        padding: EdgeInsets.all(JT.spacing8 + 2),
        decoration: BoxDecoration(
          color: _preferredGender == value ? JT.primary.withValues(alpha: 0.1) : JT.borderLight,
          borderRadius: BorderRadius.circular(JT.radiusSm + 2),
          border: Border.all(color: _preferredGender == value ? JT.primary : Colors.transparent),
        ),
        child: Column(
          children: [
            Icon(icon, color: _preferredGender == value ? JT.primary : JT.textTertiary, size: 20),
            SizedBox(height: JT.spacing4),
            Text(label, style: JT.caption.copyWith(fontSize: 10, color: _preferredGender == value ? JT.primary : JT.textTertiary), textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
