import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../main.dart' show navigatorKey;
import '../models/user_model.dart';
import '../screens/splash_screen.dart';
import 'analytics_service.dart';
import 'fcm_service.dart';
import 'secure_token_store.dart';

class AuthService {
  static const _userKey = 'user_data';
  static const _userNameKey = 'user_name';
  static const _userPhoneKey = 'user_phone';
  static const _userIdKey = 'user_id';
  static bool _is401InProgress = false;

  static const Map<String, String> _base = {
    'Content-Type': 'application/json',
    'User-Agent': 'JAGOPro-Driver/1.0 (Android)',
    'Accept': 'application/json',
  };

  /// Returns the JWT token from secure storage (never SharedPreferences).
  static Future<String?> getToken() async {
    return SecureTokenStore.read();
  }

  static Future<void> saveToken(String token) async {
    await SecureTokenStore.write(token);
  }

  static Future<void> saveUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userData));
    final name = userData['fullName'] ?? userData['full_name'] ?? userData['name'] ?? '';
    final phone = userData['phone'] ?? '';
    final id = userData['id']?.toString() ?? userData['userId']?.toString() ?? userData['user_id']?.toString() ?? '';
    if (name.toString().isNotEmpty) {
      await prefs.setString(_userNameKey, name.toString());
    } else {
      await prefs.remove(_userNameKey);
    }
    if (phone.toString().isNotEmpty) {
      await prefs.setString(_userPhoneKey, phone.toString());
    } else {
      await prefs.remove(_userPhoneKey);
    }
    if (id.isNotEmpty) {
      await prefs.setString(_userIdKey, id);
    } else {
      await prefs.remove(_userIdKey);
    }
  }

  static Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_userKey);
    if (str == null) return null;
    return jsonDecode(str) as Map<String, dynamic>;
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearLocalSession() async {
    // Delete JWT from secure storage
    await SecureTokenStore.delete();
    // Clear non-sensitive profile data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userPhoneKey);
    await prefs.remove(_userIdKey);
    // Also clear any legacy token that may still exist
    await prefs.remove('auth_token');
  }

  static Future<bool> rehydrateStoredSession({bool refreshProfile = true}) async {
    final token = (await SecureTokenStore.read())?.trim() ?? '';
    if (token.isEmpty) return false;

    final savedUser = await getSavedUser();
    if (savedUser != null && savedUser.isNotEmpty) {
      await saveUser(savedUser);
    }
    if (!refreshProfile) return true;

    try {
      final res = await http.get(
        Uri.parse(ApiConfig.driverProfile),
        headers: {..._base, 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) await saveUser(body);
        return true;
      }
      if (res.statusCode == 401) {
        await clearLocalSession();
        return false;
      }
    } on TimeoutException {
      return true;
    } catch (_) {
      return true;
    }
    return true;
  }

  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {..._base, if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<void> _saveSession(Map<String, dynamic> data) async {
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) return;
    // Store JWT in Keystore/Keychain — not SharedPreferences
    await SecureTokenStore.write(token);
    final user = (data['user'] is Map<String, dynamic>) ? data['user'] as Map<String, dynamic> : data;
    await saveUser(user);
    FcmService().onLoginSuccess().catchError((_) {});
    final userId = user['id']?.toString() ?? user['userId']?.toString() ?? user['user_id']?.toString() ?? '';
    AnalyticsService().setUserId(userId.isNotEmpty ? userId : null).catchError((_) {});
    AnalyticsService().logLogin().catchError((_) {});
  }

  static Future<Map<String, dynamic>> loginWithPassword(String phone, String password) async {
    try {
      final res = await http.post(
        Uri.parse(ApiConfig.loginPassword),
        headers: _base,
        body: jsonEncode({'phone': phone, 'password': password, 'userType': 'driver'}),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['token'] != null) await _saveSession(data);
      return data;
    } on TimeoutException {
      return {'success': false, 'message': 'Request timed out. Check your connection.'};
    } catch (_) {
      return {'success': false, 'message': 'Network error. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> registerWithPassword(
    String phone,
    String password,
    String fullName, {
    String? email,
    String? gender,
    String? vehicleNumber,
    String? vehicleModel,
    String? vehicleCategoryId,
  }) async {
    try {
      final body = <String, dynamic>{'phone': phone, 'password': password, 'fullName': fullName, 'userType': 'driver'};
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
      if (gender != null && gender.trim().isNotEmpty) body['gender'] = gender.trim();
      final res = await http.post(
        Uri.parse(ApiConfig.registerAccount),
        headers: _base,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      if (!(res.headers['content-type'] ?? '').contains('application/json')) {
        return {'success': false, 'message': 'Server error. Please try again.'};
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['token'] != null) await _saveSession(data);
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
        body: jsonEncode({'phone': phone, 'userType': 'driver'}),
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

  static Future<void> logout() async {
    try {
      final headers = await getHeaders();
      await http.post(Uri.parse(ApiConfig.logout), headers: headers).timeout(const Duration(seconds: 30));
    } catch (_) {}
    await clearLocalSession();
  }

  static Future<void> handle401() async {
    if (_is401InProgress) return;
    _is401InProgress = true;
    await clearLocalSession();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
    _is401InProgress = false;
  }

  static Future<UserModel?> getProfile() async {
    try {
      final headers = await getHeaders();
      final res = await http.get(Uri.parse(ApiConfig.driverProfile), headers: headers).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return UserModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {}
    return null;
  }
}
