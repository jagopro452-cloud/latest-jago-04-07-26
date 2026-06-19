import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the JWT auth token.
/// Uses flutter_secure_storage (Keystore/Keychain) — NOT SharedPreferences.
/// Provides a one-time migration from legacy SharedPreferences storage.
class SecureTokenStore {
  static const _tokenKey = 'secure_auth_token';
  static const _legacyTokenKey = 'auth_token'; // old SharedPreferences key

  static final _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Read the JWT token. Returns null if not found.
  static Future<String?> read() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('[SecureStore] read failed: $e');
      return null;
    }
  }

  /// Write (store) the JWT token securely.
  static Future<void> write(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('[SecureStore] write failed: $e');
    }
  }

  /// Delete the JWT token (on logout).
  static Future<void> delete() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('[SecureStore] delete failed: $e');
    }
  }

  /// Run once at app startup: migrate token from SharedPreferences to secure storage.
  /// Safe to call every launch — no-ops if already migrated.
  static Future<void> migrateFromSharedPreferences() async {
    try {
      final existing = await _storage.read(key: _tokenKey);
      if (existing != null && existing.isNotEmpty) return; // already migrated

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyTokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.write(key: _tokenKey, value: legacy);
        await prefs.remove(_legacyTokenKey);
        debugPrint('[SecureStore] Migrated auth_token from SharedPreferences → Keystore');
      }
    } catch (e) {
      debugPrint('[SecureStore] migration failed: $e');
    }
  }
}
