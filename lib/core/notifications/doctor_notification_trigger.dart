/// Doctor-side notification events (in-app only; triggers match shipped doctor features).
enum DoctorNotificationTrigger {
  newAppointmentBooked,
  patientReferredToMe,
  appointmentCancelledByPatient,
  appointmentRescheduledByPatient,
  appointmentReminderTomorrow,
  appointmentReminderToday,
  nextPatientReminder,
  patientNoShow,
  kycApproved,
  slotsFillingUp,
}

enum NotificationPriority { low, medium, high, critical }

/// Spec channels — metadata only; delivery is always in-app.
enum NotificationChannelTag { push, sms, email, app, whatsapp }

class TriggerSpec {
  const TriggerSpec({
    required this.priority,
    required this.channels,
  });

  final NotificationPriority priority;
  final List<NotificationChannelTag> channels;
}

abstract final class DoctorTriggerCatalog {
  static const specs = {
    DoctorNotificationTrigger.newAppointmentBooked: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    DoctorNotificationTrigger.patientReferredToMe: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.app],
    ),
    DoctorNotificationTrigger.appointmentCancelledByPatient: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    DoctorNotificationTrigger.appointmentRescheduledByPatient: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    DoctorNotificationTrigger.appointmentReminderTomorrow: TriggerSpec(
      priority: NotificationPriority.medium,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    DoctorNotificationTrigger.appointmentReminderToday: TriggerSpec(
      priority: NotificationPriority.medium,
      channels: [NotificationChannelTag.push],
    ),
    DoctorNotificationTrigger.nextPatientReminder: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push],
    ),
    DoctorNotificationTrigger.patientNoShow: TriggerSpec(
      priority: NotificationPriority.medium,
      channels: [NotificationChannelTag.push],
    ),
    DoctorNotificationTrigger.kycApproved: TriggerSpec(
      priority: NotificationPriority.high,
      channels: [
        NotificationChannelTag.push,
        NotificationChannelTag.sms,
        NotificationChannelTag.email,
      ],
    ),
    DoctorNotificationTrigger.slotsFillingUp: TriggerSpec(
      priority: NotificationPriority.low,
      channels: [NotificationChannelTag.push],
    ),
  };

  static TriggerSpec specFor(DoctorNotificationTrigger t) =>
      specs[t] ?? const TriggerSpec(priority: NotificationPriority.medium, channels: [NotificationChannelTag.app]);
}
