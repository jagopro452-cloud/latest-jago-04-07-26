import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../main.dart' show navigatorKey;
import '../screens/splash_screen.dart';
import 'fcm_service.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';

  static const Map<String, String> _base = {
    'Content-Type': 'application/json',
    'User-Agent': 'JAGOPro-Customer/1.0 (Android)',
    'Accept': 'application/json',
  };

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
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
    final prefs = await SharedPreferences.getInstance();
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) return;
    await prefs.setString(_tokenKey, token);
    final user = (data['user'] is Map<String, dynamic>) ? data['user'] as Map<String, dynamic> : data;
    await prefs.setString(_userKey, jsonEncode(user));
    final name = user['fullName'] ?? user['full_name'] ?? user['name'] ?? fallbackName ?? '';
    final phone = user['phone'] ?? fallbackPhone;
    final userId = user['id']?.toString() ?? user['userId']?.toString() ?? user['user_id']?.toString() ?? '';
    if (name.toString().isNotEmpty) await prefs.setString('user_name', name.toString());
    if (phone.toString().isNotEmpty) await prefs.setString('user_phone', phone.toString());
    if (userId.isNotEmpty) await prefs.setString('user_id', userId);
    FcmService().onLoginSuccess().catchError((_) {});
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_phone');
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
    await _clearLocalSession();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
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
