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

  Future<void> logRideBooked({
    required String rideId,
    required double fare,
    required String rideType,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'ride_booked',
        parameters: {
          'ride_id': rideId,
          'estimated_fare': fare,
          'ride_type': rideType,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logRideBooked failed: $e');
    }
  }

  Future<void> logRideCancelled({
    required String rideId,
    required String stage,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'ride_cancelled',
        parameters: {
          'ride_id': rideId,
          'stage': stage,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logRideCancelled failed: $e');
    }
  }

  Future<void> logRideCompleted({
    required String rideId,
    required double finalFare,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'ride_completed',
        parameters: {
          'ride_id': rideId,
          'final_fare': finalFare,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logRideCompleted failed: $e');
    }
  }

  Future<void> logPaymentSuccess({
    required String orderId,
    required double amount,
    required String method,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'payment_success',
        parameters: {
          'order_id': orderId,
          'amount': amount,
          'method': method,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logPaymentSuccess failed: $e');
    }
  }

  Future<void> logPaymentFailed({
    required String reason,
    required String method,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'payment_failed',
        parameters: {
          'reason': reason,
          'method': method,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logPaymentFailed failed: $e');
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
