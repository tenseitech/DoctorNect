import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/patient/profile/models/patient_profile_models.dart';

abstract final class MedicationReminderService {
  static const _channelId = 'medication_reminders';
  static const _channelName = 'Medication Reminders';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    _initialized = true;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const androidInit =
          AndroidInitializationSettings('@drawable/ic_notification');
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit),
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Daily medication reminders',
              importance: Importance.high,
            ),
          );
    }
  }

  static Future<void> updateScheduledReminders(
      List<MedicationReminder> medications) async {
    if (kIsWeb) return;
    await initialize();

    // Cancel all existing medication reminders
    await _localNotifications.cancelAll();

    int notificationId = 1000;

    for (final med in medications) {
      if (med.morningTime != null) {
        await _scheduleDaily(
            notificationId++, med.name, 'Morning dose', med.morningTime!);
      }
      if (med.afternoonTime != null) {
        await _scheduleDaily(
            notificationId++, med.name, 'Afternoon dose', med.afternoonTime!);
      }
      if (med.eveningTime != null) {
        await _scheduleDaily(
            notificationId++, med.name, 'Evening dose', med.eveningTime!);
      }
      if (med.nightTime != null) {
        await _scheduleDaily(
            notificationId++, med.name, 'Night dose', med.nightTime!);
      }
    }
  }

  static Future<void> cancelAllReminders() async {
    if (kIsWeb) return;
    await initialize();
    await _localNotifications.cancelAll();
  }

  static Future<void> _scheduleDaily(
      int id, String medName, String doseName, String timeStr) async {
    final parts = timeStr.split(' ');
    if (parts.isEmpty) return;

    final timeParts = parts[0].split(':');
    if (timeParts.length != 2) return;

    int hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    if (parts.length > 1) {
      if (parts[1].toUpperCase() == 'PM' && hour != 12) {
        hour += 12;
      } else if (parts[1].toUpperCase() == 'AM' && hour == 12) {
        hour = 0;
      }
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _localNotifications.zonedSchedule(
      id,
      'Time for your medicine',
      'Please take $medName ($doseName)',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Daily medication reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
