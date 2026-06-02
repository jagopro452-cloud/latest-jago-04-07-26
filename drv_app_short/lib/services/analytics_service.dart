import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      debugPrint('[Analytics] setUserId failed: $e');
    }
  }

  Future<void> logLogin() async {
    try {
      await _analytics.logLogin(loginMethod: 'phone_otp');
    } catch (e) {
      debugPrint('[Analytics] logLogin failed: $e');
    }
  }

  Future<void> logDriverOnline() async {
    try {
      await _analytics.logEvent(name: 'driver_went_online');
    } catch (e) {
      debugPrint('[Analytics] logDriverOnline failed: $e');
    }
  }

  Future<void> logDriverOffline() async {
    try {
      await _analytics.logEvent(name: 'driver_went_offline');
    } catch (e) {
      debugPrint('[Analytics] logDriverOffline failed: $e');
    }
  }

  Future<void> logTripAccepted({required String tripId}) async {
    try {
      await _analytics.logEvent(
        name: 'trip_accepted',
        parameters: {'trip_id': tripId},
      );
    } catch (e) {
      debugPrint('[Analytics] logTripAccepted failed: $e');
    }
  }

  Future<void> logTripRejected({required String tripId}) async {
    try {
      await _analytics.logEvent(
        name: 'trip_rejected',
        parameters: {'trip_id': tripId},
      );
    } catch (e) {
      debugPrint('[Analytics] logTripRejected failed: $e');
    }
  }

  Future<void> logTripCompleted({
    required String tripId,
    required double fare,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'trip_completed',
        parameters: {
          'trip_id': tripId,
          'fare': fare,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logTripCompleted failed: $e');
    }
  }

  Future<void> logPaymentReceived({
    required double amount,
    required String method,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'payment_received',
        parameters: {
          'amount': amount,
          'method': method,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logPaymentReceived failed: $e');
    }
  }

  Future<void> logWalletRecharge({
    required double amount,
    required bool success,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'wallet_recharge',
        parameters: {
          'amount': amount,
          'success': success,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logWalletRecharge failed: $e');
    }
  }
}
