import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../main.dart' show navigatorKey;
import '../screens/splash_screen.dart';
import 'analytics_service.dart';
import 'fcm_service.dart';
import 'secure_token_store.dart';

class AuthService {
  static const _userKey = 'user_data';
  static bool _is401InProgress = false;

  static const Map<String, String> _base = {
    'Content-Type': 'application/json',
    'User-Agent': 'JAGOPro-Customer/1.0 (Android)',
    'Accept': 'application/json',
  };

  /// Returns the JWT token from secure storage (never SharedPreferences).
  static Future<String?> getToken() async {
    return SecureTokenStore.read();
  }

  static Future<bool> isLoggedIn() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {..._base, if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<void> _saveSession(Map<String, dynamic> data, String fallbackPhone, {String? fallbackName}) async {
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) return;

    // Store JWT in Keystore/Keychain — not SharedPreferences
    await SecureTokenStore.write(token);

    // Non-sensitive profile data stays in SharedPreferences for fast sync reads
    final prefs = await SharedPreferences.getInstance();
    final user = (data['user'] is Map<String, dynamic>) ? data['user'] as Map<String, dynamic> : data;
    await prefs.setString(_userKey, jsonEncode(user));
    final name = user['fullName'] ?? user['full_name'] ?? user['name'] ?? fallbackName ?? '';
    final phone = user['phone'] ?? fallbackPhone;
    final userId = user['id']?.toString() ?? user['userId']?.toString() ?? user['user_id']?.toString() ?? '';
    if (name.toString().isNotEmpty) await prefs.setString('user_name', name.toString());
    if (phone.toString().isNotEmpty) await prefs.setString('user_phone', phone.toString());
    if (userId.isNotEmpty) await prefs.setString('user_id', userId);

    FcmService().onLoginSuccess().catchError((_) {});
    AnalyticsService().setUserId(userId.isNotEmpty ? userId : null).catchError((_) {});
    AnalyticsService().logLogin().catchError((_) {});
  }

  static Future<Map<String, dynamic>> postJson(String url, Map body) async {
    try {
      final res = await http.post(Uri.parse(url), headers: _base, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error'};
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    return postJson('${ApiConfig.baseUrl}/api/app/send-otp', {'phone': phone, 'userType': 'customer'});
  }

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    final res = await postJson('${ApiConfig.baseUrl}/api/app/verify-otp', {'phone': phone, 'otp': otp, 'userType': 'customer'});
    if (res['token'] != null) await _saveSession(res, phone);
    return res;
  }

  static Future<Map<String, dynamic>> loginWithEmail(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/app/login-email'),
        headers: _base,
        body: jsonEncode({'email': email, 'password': password, 'userType': 'customer'}),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['token'] != null) {
        await _saveSession(data, '', fallbackName: null);
      }
      return data;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> loginWithPassword(String phone, String password) async {
    try {
      final res = await http.post(
        Uri.parse(ApiConfig.loginPassword),
        headers: _base,
        body: jsonEncode({'phone': phone, 'password': password, 'userType': 'customer'}),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['token'] != null) {
        await _saveSession(data, phone);
      }
      return data;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> registerWithPassword(String phone, String password, String fullName, {String? email}) async {
    try {
      final body = {'phone': phone, 'password': password, 'fullName': fullName, 'userType': 'customer'};
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
      final res = await http.post(
        Uri.parse(ApiConfig.registerAccount),
        headers: _base,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['token'] != null) {
        await _saveSession(data, phone, fallbackName: fullName);
      }
      return data;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String phone) async {
    try {
      final res = await http.post(
        Uri.parse(ApiConfig.forgotPassword),
        headers: _base,
        body: jsonEncode({'phone': phone, 'userType': 'customer'}),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }

  static Future<void> _clearLocalSession() async {
    // Delete JWT from secure storage
    await SecureTokenStore.delete();
    // Clear non-sensitive profile data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_phone');
    // Also clear any legacy token that may still exist
    await prefs.remove('auth_token');
  }

  static Future<void> logout() async {
    try {
      final headers = await getHeaders();
      await http.post(Uri.parse(ApiConfig.logout), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    await _clearLocalSession();
  }

  static Future<void> handle401() async {
    if (_is401InProgress) return;
    _is401InProgress = true;
    await _clearLocalSession();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
    _is401InProgress = false;
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    try {
      final headers = await getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.customerProfile), headers: headers).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> updateProfile({String? fullName, String? email}) async {
    try {
      final headers = await getHeaders();
      final body = <String, dynamic>{};
      if (fullName != null) body['fullName'] = fullName;
      if (email != null) body['email'] = email;
      final res = await http.patch(
        Uri.parse(ApiConfig.updateProfile),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        await handle401();
        return {'success': false, 'message': 'Session expired. Please log in again.'};
      }
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }
}
