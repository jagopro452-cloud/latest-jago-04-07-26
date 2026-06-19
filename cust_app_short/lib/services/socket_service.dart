import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_token_store.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _activeTripId; // ride trip or parcel order — mutually exclusive per session
  bool _trackingParcel = false;

  final _driverAssignedController = StreamController<Map<String, dynamic>>.broadcast();
  final _driverLocationController = StreamController<Map<String, dynamic>>.broadcast();
  final _tripStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _tripCancelledController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();
  final _chatMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageHistoryController = StreamController<Map<String, dynamic>>.broadcast();
  final _noDriversController = StreamController<Map<String, dynamic>>.broadcast();
  final _tripSearchingController = StreamController<Map<String, dynamic>>.broadcast();
  final _paymentPendingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callIncomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _callOfferController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAnswerController = StreamController<Map<String, dynamic>>.broadcast();
  final _callIceController = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectedController = StreamController<Map<String, dynamic>>.broadcast();
  final _parcelDriverLocationController = StreamController<Map<String, dynamic>>.broadcast();
  final _parcelStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _parcelCancelledController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onDriverAssigned => _driverAssignedController.stream;
  Stream<Map<String, dynamic>> get onDriverLocation => _driverLocationController.stream;
  Stream<Map<String, dynamic>> get onTripStatus => _tripStatusController.stream;
  Stream<Map<String, dynamic>> get onTripCancelled => _tripCancelledController.stream;
  Stream<bool> get onConnectionChanged => _connectedController.stream;
  Stream<Map<String, dynamic>> get onChatMessage => _chatMessageController.stream;
  Stream<Map<String, dynamic>> get onMessageHistory => _messageHistoryController.stream;
  Stream<Map<String, dynamic>> get onNoDrivers => _noDriversController.stream;
  Stream<Map<String, dynamic>> get onTripSearching => _tripSearchingController.stream;
  Stream<Map<String, dynamic>> get onPaymentPending => _paymentPendingController.stream;
  Stream<Map<String, dynamic>> get onCallIncoming => _callIncomingController.stream;
  Stream<Map<String, dynamic>> get onCallOffer => _callOfferController.stream;
  Stream<Map<String, dynamic>> get onCallAnswer => _callAnswerController.stream;
  Stream<Map<String, dynamic>> get onCallIce => _callIceController.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedController.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _callRejectedController.stream;
  Stream<Map<String, dynamic>> get onParcelDriverLocation => _parcelDriverLocationController.stream;
  Stream<Map<String, dynamic>> get onParcelStatus => _parcelStatusController.stream;
  Stream<Map<String, dynamic>> get onParcelCancelled => _parcelCancelledController.stream;
  bool get isConnected => _isConnected;

  String _eventTripId(Map<String, dynamic> data) {
    final direct = data['tripId'] ?? data['trip_id'] ?? data['id'];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    final trip = data['trip'];
    if (trip is Map) {
      final nested = trip['tripId'] ?? trip['trip_id'] ?? trip['id'];
      if (nested != null && nested.toString().isNotEmpty) {
        return nested.toString();
      }
    }
    return '';
  }

  bool _matchesActiveTrip(Map<String, dynamic> data) {
    final activeTripId = _activeTripId;
    if (activeTripId == null || activeTripId.isEmpty) return true;
    final eventTripId = _eventTripId(data);
    if (eventTripId.isEmpty) return false;
    return eventTripId == activeTripId;
  }

  void _emitTrackTrip(String tripId) {
    if (_socket != null && (_isConnected || _socket!.connected)) {
      _socket!.emit('customer:track_trip', {'tripId': tripId});
    }
  }

  void _emitTrackParcel(String orderId) {
    if (_socket != null && (_isConnected || _socket!.connected)) {
      _socket!.emit('customer:track_parcel', {'orderId': orderId});
    }
  }

  String _parcelEventToStatus(String event) {
    switch (event) {
      case 'driver_assigned':
        return 'driver_assigned';
      case 'pickup_started':
        return 'picked_up';
      case 'in_transit':
      case 'delivery_approaching':
        return 'in_transit';
      case 'completed':
      case 'delivered':
        return 'completed';
      case 'cancelled':
        return 'cancelled';
      default:
        return event;
    }
  }

  void _handleParcelLifecycle(Map<String, dynamic> data) {
    final orderId = (data['orderId'] ?? data['id'] ?? '').toString();
    if (orderId.isEmpty) return;
    if (_activeTripId != null && orderId != _activeTripId) return;
    final event = (data['event'] ?? '').toString();
    final status = _parcelEventToStatus(event);
    if (status == 'completed' || status == 'cancelled') {
      _activeTripId = null;
      _trackingParcel = false;
    }
    _parcelStatusController.add({
      ...data,
      'orderId': orderId,
      'status': status,
    });
  }

  /// Reconnects only if the socket is not connected. Safe to call repeatedly.
  Future<void> reconnectIfNeeded(String baseUrl) async {
    if (_socket?.connected == true) return;
    if (_socket != null) {
      try {
        _socket!.connect();
      } catch (_) {}
      return;
    }
    await connect(baseUrl);
  }

  Future<void> connect(String baseUrl) async {
    // Guard: if a socket instance already exists (even if mid-connect), do not
    // create another — doing so registers all listeners twice and doubles events.
    if (_socket != null) return;

    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('user_id') ?? '';
    final token = (await SecureTokenStore.read()) ?? '';

    // Recovery: existing installs before the user_id fix may have empty user_id.
    // Attempt to extract it from the saved user JSON so they don't need to reinstall.
    if (userId.isEmpty) {
      final userJson = prefs.getString('user_data') ?? '';
      if (userJson.isNotEmpty) {
        try {
          final user = jsonDecode(userJson) as Map<String, dynamic>;
          final recovered = user['id']?.toString() ??
              user['userId']?.toString() ??
              user['user_id']?.toString() ?? '';
          if (recovered.isNotEmpty) {
            await prefs.setString('user_id', recovered);
            userId = recovered;
          }
        } catch (_) {}
      }
    }

    if (userId.isEmpty) return;
    if (token.isEmpty) return;

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setQuery({'userId': userId, 'userType': 'customer'})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(3000)
          .build(),
    );

    _socket!.on('connect', (_) {
      _isConnected = true;
      _connectedController.add(true);
      // Re-join trip room on every connect (first connect + reconnect after restart)
      if (_activeTripId != null) {
        if (_trackingParcel) {
          _emitTrackParcel(_activeTripId!);
        } else {
          _emitTrackTrip(_activeTripId!);
        }
      }
    });

    // On reconnect after server restart: re-join active trip room so events resume
    _socket!.on('reconnect', (_) {
      if (_activeTripId != null) {
        if (_trackingParcel) {
          _emitTrackParcel(_activeTripId!);
        } else {
          _emitTrackTrip(_activeTripId!);
        }
      }
    });

    _socket!.on('disconnect', (_) {
      _isConnected = false;
      _connectedController.add(false);
    });

    _socket!.on('connect_error', (err) {
      _isConnected = false;
      _connectedController.add(false);
    });

    _socket!.on('error', (err) {
      _isConnected = false;
      _connectedController.add(false);
      debugPrint('[SOCKET] Error: $err');
    });

    _socket!.on('auth:error', (data) {
      debugPrint('[SOCKET] Auth error received');
      // If we get an auth error, we might need to refresh the token or re-login.
      // For now, let's just push a disconnected state.
      _isConnected = false;
      _connectedController.add(false);
    });

    // Driver assigned to my trip (socket acceptance path)
    _socket!.on('trip:driver_assigned', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _driverAssignedController.add(payload);
    });

    // Real-time driver GPS location
    _socket!.on('driver:location_update', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _driverLocationController.add(payload);
    });

    // Driver accepted my trip (HTTP acceptance path)
    _socket!.on('trip:accepted', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      payload['driver'] = payload['driver'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload['driver'])
          : {
              'id': payload['driverId'],
              'fullName': payload['driverName'],
              'phone': payload['driverPhone'],
              'rating': payload['driverRating'],
              'photo': payload['driverPhoto'],
              'vehicleNumber': payload['driverVehicleNumber'],
              'vehicleModel': payload['driverVehicleModel'],
              'vehicleCategory': payload['vehicleName'],
              'lat': payload['lat'],
              'lng': payload['lng'],
            };
      payload['eventType'] = 'trip_accepted';
      _driverAssignedController.add(payload);
      // Keep status stream in sync for tracking UI updates
      _tripStatusController.add({
        'tripId': payload['tripId'],
        'status': 'accepted',
        if (payload['pickupOtp'] != null) 'otp': payload['pickupOtp'],
      });
    });

    // Trip status changed (arrived, in_progress, completed, cancelled)
    _socket!.on('trip:status_update', (data) {
      if (data == null) return;
      try {
        final payload = Map<String, dynamic>.from(data);
        if (!_matchesActiveTrip(payload)) return;
        final status =
            (payload['status'] ?? payload['currentStatus'] ?? '').toString();
        if (status == 'completed' || status == 'cancelled') {
          _activeTripId = null;
        }
        _tripStatusController.add(payload);
      } catch (e) {
        debugPrint('[SOCKET] Error processing trip:status_update: $e');
      }
    });

    // Some server paths emit completed directly instead of status_update
    _socket!.on('trip:completed', (data) {
      if (data == null) return;
      try {
        final payload = Map<String, dynamic>.from(data);
        if (!_matchesActiveTrip(payload)) return;
        _activeTripId = null;
        _tripStatusController.add({
          'tripId': payload['tripId'],
          'status': 'completed',
          // Pass through wallet payment info so tracking screen can show correct payment UI
          if (payload['walletPendingAmount'] != null) 'walletPendingAmount': payload['walletPendingAmount'],
          if (payload['walletPaidAmount'] != null) 'walletPaidAmount': payload['walletPaidAmount'],
          if (payload['requiresCashPayment'] != null) 'requiresCashPayment': payload['requiresCashPayment'],
          if (payload['fare'] != null) 'fare': payload['fare'],
          if (payload['userPayable'] != null) 'userPayable': payload['userPayable'],
        });
      } catch (e) {
        debugPrint('[SOCKET] Error processing trip:completed: $e');
      }
    });

    // Trip cancelled by driver
    _socket!.on('trip:cancelled', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _activeTripId = null;
      _tripCancelledController.add(payload);
    });

    // In-app chat message received (live)
    _socket!.on('trip:new_message', (data) {
      _chatMessageController.add(Map<String, dynamic>.from(data));
    });

    // Chat history loaded from DB on reconnect
    _socket!.on('trip:message_history', (data) {
      _messageHistoryController.add(Map<String, dynamic>.from(data));
    });

    // No drivers found — trip auto-cancelled
    _socket!.on('trip:no_drivers', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _activeTripId = null;
      _noDriversController.add(payload);
    });

    // Trip re-searching after driver rejected
    _socket!.on('trip:searching', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _tripSearchingController.add(payload);
    });

    // Trip timeout — server gave up finding driver
    _socket!.on('trip:timeout', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (!_matchesActiveTrip(payload)) return;
      _activeTripId = null;
      _noDriversController.add(payload);
    });

    // Payment not yet verified — trip held at payment_pending
    _socket!.on('trip:payment_pending', (data) {
      _paymentPendingController.add(Map<String, dynamic>.from(data));
    });

    // ── WebRTC Call Signaling ──────────────────────────────────
    _socket!.on('call:incoming', (data) {
      _callIncomingController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('call:offer', (data) {
      _callOfferController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('call:answer', (data) {
      _callAnswerController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('call:ice', (data) {
      _callIceController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('call:ended', (data) {
      _callEndedController.add(Map<String, dynamic>.from(data));
    });
    _socket!.on('call:rejected', (data) {
      _callRejectedController.add(Map<String, dynamic>.from(data));
    });

    // ── Parcel delivery tracking ───────────────────────────────────────────
    _socket!.on('parcel:driver_location', (data) {
      final payload = Map<String, dynamic>.from(data);
      final orderId = (payload['orderId'] ?? '').toString();
      if (_activeTripId != null && orderId.isNotEmpty && orderId != _activeTripId) return;
      _parcelDriverLocationController.add(payload);
    });

    for (final event in [
      'driver_assigned',
      'pickup_started',
      'in_transit',
      'delivery_approaching',
      'delivered',
      'completed',
      'cancelled',
    ]) {
      _socket!.on('parcel:$event', (data) {
        _handleParcelLifecycle(Map<String, dynamic>.from(data));
      });
    }

    _socket!.on('parcel:cancelled', (data) {
      final payload = Map<String, dynamic>.from(data);
      final orderId = (payload['orderId'] ?? '').toString();
      if (_activeTripId != null && orderId.isNotEmpty && orderId != _activeTripId) return;
      _activeTripId = null;
      _trackingParcel = false;
      _parcelCancelledController.add(payload);
      _parcelStatusController.add({
        ...payload,
        'orderId': orderId,
        'status': 'cancelled',
      });
    });

    _socket!.connect();
  }

  // Start tracking a specific trip (also stored for reconnect recovery).
  // Emits immediately if connected; the stored ID ensures re-join on reconnect.
  void trackTrip(String tripId) {
    _activeTripId = tripId;
    _trackingParcel = false;
    _emitTrackTrip(tripId);
    // If socket not ready yet, the connect handler will pick it up via _activeTripId
  }

  void trackParcel(String orderId) {
    _activeTripId = orderId;
    _trackingParcel = true;
    _emitTrackParcel(orderId);
  }

  void stopTrackingTrip(String tripId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('customer:leave_trip', {'tripId': tripId});
    }
    _activeTripId = null;
    _trackingParcel = false;
  }

  void stopTrackingParcel(String orderId) {
    _activeTripId = null;
    _trackingParcel = false;
  }

  // Cancel a trip
  void cancelTrip(String tripId) {
    if (!_isConnected) return;
    _socket!.emit('customer:cancel_trip', {'tripId': tripId});
  }

  void cancelParcel(String orderId, {String? reason}) {
    if (!_isConnected) return;
    _socket!.emit('customer:cancel_parcel', {
      'orderId': orderId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  // Send in-app chat message (persisted to DB + relayed via socket)
  void sendChatMessage({required String tripId, required String message, required String senderName}) {
    if (!_isConnected) return;
    _socket!.emit('trip:send_message', {
      'tripId': tripId,
      'message': message,
      'senderName': senderName,
      'senderType': 'customer',
    });
  }

  // Load message history from DB (call after joining trip room)
  void loadChatHistory(String tripId) {
    if (!_isConnected) return;
    _socket!.emit('trip:get_messages', {'tripId': tripId});
  }

  // ── WebRTC Call Methods ──────────────────────────────────
  void initiateCall({required String targetUserId, required String tripId, required String callerName}) {
    if (!_isConnected) return;
    _socket!.emit('call:initiate', {'targetUserId': targetUserId, 'tripId': tripId, 'callerName': callerName});
  }

  void sendCallOffer({required String targetUserId, required dynamic sdp}) {
    if (!_isConnected) return;
    _socket!.emit('call:offer', {'targetUserId': targetUserId, 'sdp': sdp});
  }

  void sendCallAnswer({required String targetUserId, required dynamic sdp}) {
    if (!_isConnected) return;
    _socket!.emit('call:answer', {'targetUserId': targetUserId, 'sdp': sdp});
  }

  void sendIceCandidate({required String targetUserId, required dynamic candidate}) {
    if (!_isConnected) return;
    _socket!.emit('call:ice', {'targetUserId': targetUserId, 'candidate': candidate});
  }

  void endCall({required String targetUserId, String? tripId, int? durationSec}) {
    if (!_isConnected) return;
    _socket!.emit('call:end', {'targetUserId': targetUserId, if (tripId != null) 'tripId': tripId, if (durationSec != null) 'durationSec': durationSec});
  }

  void rejectCall({required String targetUserId, String? tripId}) {
    if (!_isConnected) return;
    _socket!.emit('call:reject', {'targetUserId': targetUserId, if (tripId != null) 'tripId': tripId});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
  }

  /// Call on logout to reset socket state without destroying the singleton's
  /// broadcast StreamControllers. Closing controllers on a singleton is
  /// permanent — any reconnect after login would try to emit to closed streams
  /// and crash with "Bad state: Cannot add event after closing".
  void resetForLogout() {
    disconnect();
    _activeTripId = null;
    _trackingParcel = false;
  }

  // Intentionally NOT exposed: closing broadcast controllers on a singleton
  // is irreversible. Screens manage their own subscriptions via cancel().
}
