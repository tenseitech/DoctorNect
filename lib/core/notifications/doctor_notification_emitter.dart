import 'package:intl/intl.dart';

import '../../features/doctor/models/doctor_models.dart';
import 'app_notification.dart';
import 'doctor_notification_trigger.dart';
import 'in_app_notification_service.dart';

/// In-app doctor notifications for shipped features only.
abstract final class DoctorNotificationEmitter {
  static String _id() => 'n${DateTime.now().microsecondsSinceEpoch}';

  static AppNotification _build({
    required DoctorNotificationTrigger trigger,
    required String title,
    required String body,
    required AppNotificationType type,
    AppNotificationTarget? target,
    String? targetId,
    AppNotificationAction? primaryAction,
    String? dedupeKey,
  }) {
    final spec = DoctorTriggerCatalog.specFor(trigger);
    return AppNotification(
      id: _id(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
      type: type,
      doctorTrigger: trigger,
      priority: spec.priority,
      channelTags: [NotificationChannelTag.app, ...spec.channels],
      target: target,
      targetId: targetId,
      primaryAction: primaryAction,
      dedupeKey: dedupeKey,
    );
  }

  static void emit(AppNotification n) =>
      InAppNotificationService.instance.addDoctor(n);

  static AppNotification newAppointmentBooked({
    required String patientName,
    required DateTime date,
    required String timeLabel,
    required AppointmentType visitType,
    String? appointmentId,
  }) {
    return _build(
      trigger: DoctorNotificationTrigger.newAppointmentBooked,
      title: 'New appointment',
      body: '$patientName · $timeLabel',
      type: AppNotificationType.booking,
      target: AppNotificationTarget.appointmentDetail,
      targetId: appointmentId,
      dedupeKey: appointmentId != null ? 'd_appt_new_$appointmentId' : null,
    );
  }

  static void notifyNewAppointmentBooked({
    required String patientName,
    required DateTime date,
    required String timeLabel,
    required AppointmentType visitType,
    String? appointmentId,
  }) =>
      emit(newAppointmentBooked(
        patientName: patientName,
        date: date,
        timeLabel: timeLabel,
        visitType: visitType,
        appointmentId: appointmentId,
      ));

  static void notifyNewAppointmentRequest({
    required String patientName,
    required DateTime date,
    required String timeLabel,
    required AppointmentType visitType,
    String? appointmentId,
  }) {
    emit(_build(
      trigger: DoctorNotificationTrigger.newAppointmentBooked,
      title: 'New request',
      body: '$patientName · $timeLabel',
      type: AppNotificationType.booking,
      target: AppNotificationTarget.appointmentDetail,
      targetId: appointmentId,
      dedupeKey: appointmentId != null ? 'd_appt_request_$appointmentId' : null,
    ));
  }

  static void notifyAppointmentCancelledByPatient({
    required String patientName,
    required String dateTimeLabel,
    required String reason,
    String? appointmentId,
  }) =>
      emit(_build(
        trigger: DoctorNotificationTrigger.appointmentCancelledByPatient,
        title: 'Cancelled',
        body: '$patientName: $reason.',
        type: AppNotificationType.cancellation,
        target: AppNotificationTarget.appointments,
        targetId: appointmentId,
        dedupeKey:
            appointmentId != null ? 'd_appt_cancel_$appointmentId' : null,
      ));

  static void notifyAppointmentRescheduledByPatient({
    required String patientName,
    required String oldLabel,
    required String newLabel,
    String? appointmentId,
  }) =>
      emit(_build(
        trigger: DoctorNotificationTrigger.appointmentRescheduledByPatient,
        title: 'Rescheduled',
        body: '$patientName: $oldLabel -> $newLabel.',
        type: AppNotificationType.appointment,
        target: AppNotificationTarget.appointmentDetail,
        targetId: appointmentId,
        dedupeKey:
            appointmentId != null ? 'd_appt_reschedule_$appointmentId' : null,
      ));

  static void notifyTomorrowSummary({required String summary}) => emit(_build(
        trigger: DoctorNotificationTrigger.appointmentReminderTomorrow,
        title: 'Tomorrow\'s schedule',
        body: summary,
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointments,
        dedupeKey:
            'reminder_tomorrow_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyTodaySchedule({required String summary}) => emit(_build(
        trigger: DoctorNotificationTrigger.appointmentReminderToday,
        title: 'Today\'s schedule',
        body: summary,
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointments,
        dedupeKey:
            'reminder_today_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyNextPatient({
    required String patientName,
    required String reason,
    required String appointmentId,
    required DateTime appointmentTime,
  }) =>
      emit(_build(
        trigger: DoctorNotificationTrigger.nextPatientReminder,
        title: 'Next patient in 15 minutes',
        body: '$patientName · Reason: $reason',
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointmentDetail,
        targetId: appointmentId,
        dedupeKey:
            'next_patient_${appointmentId}_${appointmentTime.millisecondsSinceEpoch ~/ 60000}',
      ));

  static AppNotification patientNoShowAlert({
    required String patientName,
    required String slotLabel,
    required String appointmentId,
  }) =>
      _build(
        trigger: DoctorNotificationTrigger.patientNoShow,
        title: 'No-show',
        body: patientName,
        type: AppNotificationType.appointment,
        target: AppNotificationTarget.appointmentDetail,
        targetId: appointmentId,
        primaryAction: const AppNotificationAction(
            label: 'Mark as no-show', actionKey: 'mark_no_show'),
        dedupeKey: 'no_show_$appointmentId',
      );

  static AppNotification kycApproved() => _build(
        trigger: DoctorNotificationTrigger.kycApproved,
        title: 'KYC verified',
        body: 'Account approved.',
        type: AppNotificationType.kyc,
        target: AppNotificationTarget.profile,
        primaryAction: const AppNotificationAction(
            label: 'Complete profile', actionKey: 'open_profile'),
        dedupeKey: 'kyc_approved',
      );

  static void notifySlotsFillingUp({required int percentBooked}) => emit(_build(
        trigger: DoctorNotificationTrigger.slotsFillingUp,
        title: 'Slots filling up',
        body: '$percentBooked% booked.',
        type: AppNotificationType.system,
        target: AppNotificationTarget.schedule,
        primaryAction: const AppNotificationAction(
            label: 'Add slots', actionKey: 'add_slots'),
        dedupeKey:
            'slots_80_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static AppNotification patientMarkedNoShow(String appointmentId) => _build(
        trigger: DoctorNotificationTrigger.patientNoShow,
        title: 'No-show marked',
        body: 'Appointment $appointmentId',
        type: AppNotificationType.appointment,
        target: AppNotificationTarget.appointmentDetail,
        targetId: appointmentId,
        dedupeKey: 'd_no_show_marked_$appointmentId',
      );
}
