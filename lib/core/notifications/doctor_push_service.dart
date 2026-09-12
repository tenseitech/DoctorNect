import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase/firebase_bootstrap.dart';
/// Registers FCM for doctors and shows appointment/lab alerts on native platforms.
abstract final class DoctorPushService {
  static const _channelId = 'doctor_appointments';
  static const _channelName = 'Appointments';
  static const _appointmentNewType = 'appointment_new';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<RemoteMessage>? _openedSub;
  static String? _activeDoctorId;
  static bool _initialized = false;

  /// Set when user taps a push (background / cold start); consumed by [DoctorShell].
  static String? pendingOpenAppointmentId;

  /// Invoked when user opens an appointment push while the doctor shell may already be mounted.
  static void Function(String appointmentId)? onAppointmentPushOpened;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    if (!FirebaseBootstrap.isReady) return;

    _initialized = true;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Appointment and care-team updates',
              importance: Importance.high,
            ),
          );
    }

    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _storeOpenTarget(initial);
    }
  }

  static Future<void> registerDoctor(String doctorId) async {
    if (doctorId.isEmpty || kIsWeb) return;

    await initialize();
    _activeDoctorId = doctorId;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await FirestoreService.instance.doctorProfile.saveDoctorFcmToken(doctorId, token);
    }

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (_activeDoctorId == null || newToken.isEmpty) return;
      await FirestoreService.instance.doctorProfile.saveDoctorFcmToken(_activeDoctorId!, newToken);
    });
  }

  static Future<void> unregisterDoctor() async {
    final doctorId = _activeDoctorId;
    _activeDoctorId = null;
    pendingOpenAppointmentId = null;
    onAppointmentPushOpened = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    if (doctorId == null || doctorId.isEmpty) return;
    await FirestoreService.instance.doctorProfile.clearDoctorFcmToken(doctorId);
    if (!kIsWeb) {
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  static void _onForegroundMessage(RemoteMessage message) {
    unawaited(_showLocalNotification(message));
  }

  static void _onMessageOpened(RemoteMessage message) {
    _storeOpenTarget(message);
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      pendingOpenAppointmentId = payload;
      onAppointmentPushOpened?.call(payload);
    }
  }

  static void _storeOpenTarget(RemoteMessage message) {
    if (message.data['type'] != _appointmentNewType) return;

    final appointmentId = message.data['appointmentId'];
    if (appointmentId != null && appointmentId.isNotEmpty) {
      pendingOpenAppointmentId = appointmentId;
      onAppointmentPushOpened?.call(appointmentId);
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final notification = message.notification;
    if (notification == null) return;

    final appointmentId = message.data['appointmentId'] ?? '';

    await _localNotifications.show(
      appointmentId.hashCode.abs(),
      notification.title ?? 'New appointment',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Appointment and care-team updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      payload: appointmentId.isEmpty ? null : appointmentId,
    );
  }

  static void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    _foregroundSub = null;
    _openedSub = null;
    unawaited(_tokenRefreshSub?.cancel());
    _tokenRefreshSub = null;
    _activeDoctorId = null;
    pendingOpenAppointmentId = null;
    onAppointmentPushOpened = null;
    _initialized = false;
  }
}
