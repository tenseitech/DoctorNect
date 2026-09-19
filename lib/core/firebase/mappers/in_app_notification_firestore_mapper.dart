import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../notifications/app_notification.dart';
import '../../notifications/doctor_notification_trigger.dart';
import '../../notifications/patient_notification_trigger.dart';

abstract final class InAppNotificationFirestoreMapper {
  static AppNotification? fromMap(String docId, Map<String, dynamic> data) {
    try {
      final title = (data['title'] as String?)?.trim();
      final body = (data['body'] as String?)?.trim();
      if (title == null || title.isEmpty || body == null || body.isEmpty) {
        return null;
      }

      final doctorTrigger = _doctorTrigger(data['doctorTrigger'] as String?);
      final patientTrigger = _patientTrigger(data['patientTrigger'] as String?);

      final NotificationPriority priority;
      final List<NotificationChannelTag> channelTags;
      if (patientTrigger != null) {
        final spec = PatientTriggerCatalog.specFor(patientTrigger);
        priority = spec.priority;
        channelTags = [NotificationChannelTag.app, ...spec.channels];
      } else if (doctorTrigger != null) {
        final spec = DoctorTriggerCatalog.specFor(doctorTrigger);
        priority = spec.priority;
        channelTags = [NotificationChannelTag.app, ...spec.channels];
      } else {
        priority = NotificationPriority.medium;
        channelTags = [NotificationChannelTag.app];
      }

      return AppNotification(
        id: docId,
        title: title,
        body: body,
        createdAt: _createdAt(data['createdAt']),
        type: _type(data['type'] as String?),
        isRead: data['isRead'] == true,
        target: _target(data['target'] as String?),
        targetId: (data['targetId'] as String?)?.trim(),
        doctorTrigger: doctorTrigger,
        patientTrigger: patientTrigger,
        priority: priority,
        channelTags: channelTags,
        dedupeKey: (data['dedupeKey'] as String?)?.trim(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'InAppNotificationFirestoreMapper.fromMap failed ($docId): $e\n$st');
      }
      return null;
    }
  }

  static DateTime _createdAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static AppNotificationType _type(String? raw) {
    if (raw == null || raw.isEmpty) return AppNotificationType.system;
    for (final type in AppNotificationType.values) {
      if (type.name == raw) return type;
    }
    return AppNotificationType.system;
  }

  static AppNotificationTarget? _target(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final target in AppNotificationTarget.values) {
      if (target.name == raw) return target;
    }
    return null;
  }

  static DoctorNotificationTrigger? _doctorTrigger(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final trigger in DoctorNotificationTrigger.values) {
      if (trigger.name == raw) return trigger;
    }
    return null;
  }

  static PatientNotificationTrigger? _patientTrigger(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final trigger in PatientNotificationTrigger.values) {
      if (trigger.name == raw) return trigger;
    }
    return null;
  }
}
