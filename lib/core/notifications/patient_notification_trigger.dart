import 'doctor_notification_trigger.dart';

/// Patient-side notification events (in-app only; triggers match shipped patient features).
enum PatientNotificationTrigger {
  bookingConfirmed,
  appointmentReminderTomorrow,
  appointmentReminderTwoHours,
  appointmentReminderThirtyMin,
  doctorRescheduled,
  doctorCancelled,
  labOrderSent,
  labBookingAccepted,
  labBookingDeclined,
  labBookingUpdate,
  labReportReady,
  labCollectionReminder,
  phlebotomistOnTheWay,
  vaccinationDueReminder,
  medicineReminder,
  pharmacyDeliveryUpdate,
  vitalsLogReminder,
  healthTipOfDay,
}

class PatientTriggerSpec {
  const PatientTriggerSpec({
    required this.priority,
    required this.channels,
  });

  final NotificationPriority priority;
  final List<NotificationChannelTag> channels;
}

abstract final class PatientTriggerCatalog {
  static const specs = {
    PatientNotificationTrigger.bookingConfirmed: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [
        NotificationChannelTag.push,
        NotificationChannelTag.sms,
        NotificationChannelTag.email,
      ],
    ),
    PatientNotificationTrigger.appointmentReminderTomorrow: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.appointmentReminderTwoHours: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.appointmentReminderThirtyMin: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push],
    ),
    PatientNotificationTrigger.doctorRescheduled: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.doctorCancelled: PatientTriggerSpec(
      priority: NotificationPriority.critical,
      channels: [
        NotificationChannelTag.push,
        NotificationChannelTag.sms,
        NotificationChannelTag.email,
      ],
    ),
    PatientNotificationTrigger.labOrderSent: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.labBookingAccepted: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.labBookingDeclined: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.labBookingUpdate: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.labReportReady: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.labCollectionReminder: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.phlebotomistOnTheWay: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.vaccinationDueReminder: PatientTriggerSpec(
      priority: NotificationPriority.medium,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.medicineReminder: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.pharmacyDeliveryUpdate: PatientTriggerSpec(
      priority: NotificationPriority.high,
      channels: [NotificationChannelTag.push, NotificationChannelTag.sms],
    ),
    PatientNotificationTrigger.vitalsLogReminder: PatientTriggerSpec(
      priority: NotificationPriority.low,
      channels: [NotificationChannelTag.push],
    ),
    PatientNotificationTrigger.healthTipOfDay: PatientTriggerSpec(
      priority: NotificationPriority.low,
      channels: [NotificationChannelTag.push],
    ),
  };

  static PatientTriggerSpec specFor(PatientNotificationTrigger t) =>
      specs[t] ??
      const PatientTriggerSpec(priority: NotificationPriority.medium, channels: [NotificationChannelTag.app]);
}
