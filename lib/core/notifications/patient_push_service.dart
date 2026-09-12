import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase/firebase_bootstrap.dart';
/// Registers FCM for patients and routes push taps to the correct screen.
abstract final class PatientPushService {
  static const _labChannelId = 'patient_lab_bookings';
  static const _labChannelName = 'Lab Bookings';
  static const _appointmentChannelId = 'patient_appointments';
  static const _appointmentChannelName = 'Appointments';
  static const _pharmacyChannelId = 'patient_pharmacy';
  static const _pharmacyChannelName = 'Pharmacy';

  static const _appointmentStatusType = 'appointment_status_update';
  static const _pharmacyDeliveryType = 'pharmacy_delivery_update';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<RemoteMessage>? _openedSub;
  static String? _activePatientId;
  static bool _initialized = false;

  static String? pendingOpenAppointmentId;
  static String? pendingOpenPrescriptionId;

  static void Function(String appointmentId)? onAppointmentPushOpened;
  static void Function(String prescriptionId)? onPrescriptionPushOpened;

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

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _labChannelId,
          _labChannelName,
          description: 'Lab booking updates',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _appointmentChannelId,
          _appointmentChannelName,
          description: 'Appointment status updates',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _pharmacyChannelId,
          _pharmacyChannelName,
          description: 'Pharmacy pickup updates',
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

  static Future<void> registerPatient(String patientId) async {
    if (patientId.isEmpty || kIsWeb) return;

    await initialize();
    _activePatientId = patientId;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await FirestoreService.instance.patientProfile.savePatientFcmToken(patientId, token);
    }

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (_activePatientId == null || newToken.isEmpty) return;
      await FirestoreService.instance.patientProfile.savePatientFcmToken(_activePatientId!, newToken);
    });
  }

  static Future<void> unregisterPatient() async {
    final patientId = _activePatientId;
    _activePatientId = null;
    pendingOpenAppointmentId = null;
    pendingOpenPrescriptionId = null;
    onAppointmentPushOpened = null;
    onPrescriptionPushOpened = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    if (patientId == null || patientId.isEmpty) return;
    await FirestoreService.instance.patientProfile.clearPatientFcmToken(patientId);
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
    if (payload == null || payload.isEmpty) return;

    if (payload.startsWith('rx:')) {
      final prescriptionId = payload.substring(3);
      pendingOpenPrescriptionId = prescriptionId;
      onPrescriptionPushOpened?.call(prescriptionId);
      return;
    }

    pendingOpenAppointmentId = payload;
    onAppointmentPushOpened?.call(payload);
  }

  static void _storeOpenTarget(RemoteMessage message) {
    final type = message.data['type'];

    if (type == _appointmentStatusType) {
      final appointmentId = message.data['appointmentId'];
      if (appointmentId != null && appointmentId.isNotEmpty) {
        pendingOpenAppointmentId = appointmentId;
        onAppointmentPushOpened?.call(appointmentId);
      }
      return;
    }

    if (type == _pharmacyDeliveryType) {
      final prescriptionId = message.data['prescriptionId'];
      if (prescriptionId != null && prescriptionId.isNotEmpty) {
        pendingOpenPrescriptionId = prescriptionId;
        onPrescriptionPushOpened?.call(prescriptionId);
      }
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] ?? '';
    final channelId = switch (type) {
      _appointmentStatusType => _appointmentChannelId,
      _pharmacyDeliveryType => _pharmacyChannelId,
      _ => _labChannelId,
    };
    final channelName = switch (type) {
      _appointmentStatusType => _appointmentChannelName,
      _pharmacyDeliveryType => _pharmacyChannelName,
      _ => _labChannelName,
    };

    String? payload;
    if (type == _appointmentStatusType) {
      final appointmentId = message.data['appointmentId'] ?? '';
      payload = appointmentId.isEmpty ? null : appointmentId;
    } else if (type == _pharmacyDeliveryType) {
      final prescriptionId = message.data['prescriptionId'] ?? '';
      payload = prescriptionId.isEmpty ? null : 'rx:$prescriptionId';
    }

    await _localNotifications.show(
      (payload ?? type).hashCode.abs(),
      notification.title ?? 'Update',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      payload: payload,
    );
  }

  static void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    _foregroundSub = null;
    _openedSub = null;
    unawaited(_tokenRefreshSub?.cancel());
    _tokenRefreshSub = null;
    _activePatientId = null;
    pendingOpenAppointmentId = null;
    pendingOpenPrescriptionId = null;
    onAppointmentPushOpened = null;
    onPrescriptionPushOpened = null;
    _initialized = false;
  }
}
