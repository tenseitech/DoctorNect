import 'doctor_notification_trigger.dart';
import 'patient_notification_trigger.dart';

enum NotificationAudience { patient, doctor }

enum AppNotificationType {
  appointment,
  labReport,
  prescription,
  reminder,
  booking,
  review,
  cancellation,
  payout,
  system,
  chat,
  kyc,
  wellness,
}

enum AppNotificationTarget {
  appointments,
  appointmentDetail,
  labReports,
  prescriptions,
  earnings,
  schedule,
  search,
  patients,
  profile,
  labBooking,
  vitals,
  vaccination,
}

class AppNotificationAction {
  const AppNotificationAction({required this.label, required this.actionKey});

  final String label;
  final String actionKey;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.type,
    this.isRead = false,
    this.target,
    this.targetId,
    this.doctorTrigger,
    this.patientTrigger,
    this.priority = NotificationPriority.medium,
    this.channelTags = const [NotificationChannelTag.app],
    this.primaryAction,
    this.dedupeKey,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final AppNotificationType type;
  final bool isRead;
  final AppNotificationTarget? target;
  final String? targetId;
  final DoctorNotificationTrigger? doctorTrigger;
  final PatientNotificationTrigger? patientTrigger;
  final NotificationPriority priority;
  final List<NotificationChannelTag> channelTags;
  final AppNotificationAction? primaryAction;

  /// Prevents duplicate scheduled alerts (e.g. same 15-min reminder).
  final String? dedupeKey;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        type: type,
        isRead: isRead ?? this.isRead,
        target: target,
        targetId: targetId,
        doctorTrigger: doctorTrigger,
        patientTrigger: patientTrigger,
        priority: priority,
        channelTags: channelTags,
        primaryAction: primaryAction,
        dedupeKey: dedupeKey,
      );
}
