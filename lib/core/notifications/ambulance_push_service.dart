import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase/firebase_bootstrap.dart';
import '../../features/ambulance/data/ambulance_booking_sync.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../../features/ambulance/models/ambulance_models.dart';

/// Registers FCM for ambulance drivers and shows new-request alerts.
abstract final class AmbulancePushService {
  static const _channelId = 'ambulance_requests';
  static const _channelName = 'Ambulance Requests';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<RemoteMessage>? _openedSub;
  static String? _activeDriverId;
  static bool _initialized = false;

  /// Set from [AmbulanceDriverHomeScreen] to jump to pending when a push is opened.
  static String? pendingOpenBroadcastId;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    if (!FirebaseBootstrap.isReady) return;

    _initialized = true;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const androidInit =
          AndroidInitializationSettings('@drawable/ic_notification');
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'New ambulance booking requests',
              importance: Importance.high,
            ),
          );
    }

    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub ??=
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _storeOpenTarget(initial);
    }
  }

  /// Call after ambulance driver login â€” saves token to Firestore.
  static Future<void> registerDriver(String driverId) async {
    if (driverId.isEmpty || kIsWeb) return;

    await initialize();
    _activeDriverId = driverId;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode)
        debugPrint('Ambulance push: notification permission denied');
      return;
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('Ambulance FCM token (copy for Firebase test): [REDACTED]');
      }
      await FirestoreService.instance.ambulance
          .saveDriverFcmToken(driverId, token);
    } else if (kDebugMode) {
      debugPrint('Ambulance push: FCM token is null or empty');
    }

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (_activeDriverId == null || newToken.isEmpty) return;
      if (kDebugMode) {
        debugPrint('Ambulance FCM token refreshed: [REDACTED]');
      }
      await FirestoreService.instance.ambulance
          .saveDriverFcmToken(_activeDriverId!, newToken);
    });
  }

  /// Call on ambulance logout â€” removes token from Firestore.
  static Future<void> unregisterDriver() async {
    final driverId = _activeDriverId;
    _activeDriverId = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    if (driverId == null || driverId.isEmpty) return;
    await FirestoreService.instance.ambulance.clearDriverFcmToken(driverId);
    if (!kIsWeb) {
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  static void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    unawaited(_tokenRefreshSub?.cancel());
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;
    _activeDriverId = null;
    _initialized = false;
  }

  static void _onForegroundMessage(RemoteMessage message) {
    if (message.data['type'] != 'ambulance_request') return;

    final driverId = _activeDriverId;
    if (driverId != null && driverId.isNotEmpty) {
      AmbulanceBookingSync.instance.watchDriverRequests(driverId);
    }

    _pushInAppAlert(message);
    unawaited(_showLocalNotification(message));
  }

  static void _onMessageOpened(RemoteMessage message) {
    _storeOpenTarget(message);
    final driverId = _activeDriverId;
    if (driverId != null && driverId.isNotEmpty) {
      AmbulanceBookingSync.instance.watchDriverRequests(driverId);
    }
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      pendingOpenBroadcastId = payload;
    }
  }

  static void _storeOpenTarget(RemoteMessage message) {
    final broadcastId = message.data['broadcastId'];
    if (broadcastId != null && broadcastId.isNotEmpty) {
      pendingOpenBroadcastId = broadcastId;
    }
  }

  static void _pushInAppAlert(RemoteMessage message) {
    final driverId = _activeDriverId;
    if (driverId == null || driverId.isEmpty) return;

    final broadcastId = message.data['broadcastId'] ?? '';
    final title = message.notification?.title ?? 'New ambulance request';
    final body = message.notification?.body ?? 'Tap to view details';

    final alerts = AmbulanceStore.instance.alertsFor(driverId);
    if (alerts.any((a) => a.bookingId == broadcastId && broadcastId.isNotEmpty))
      return;

    AmbulanceStore.instance.registerDriverAlert(
      driverId,
      AmbulanceDriverAlert(
        id: 'push-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
        createdAt: DateTime.now(),
        bookingId: broadcastId.isEmpty ? null : broadcastId,
      ),
    );
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final notification = message.notification;
    if (notification == null) return;

    final broadcastId = message.data['broadcastId'] ?? '';

    await _localNotifications.show(
      broadcastId.hashCode.abs(),
      notification.title ?? 'New Ambulance Request',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'New ambulance booking requests',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      payload: broadcastId.isEmpty ? null : broadcastId,
    );
  }
}
