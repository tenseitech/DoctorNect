import 'package:intl/intl.dart';

import 'app_notification.dart';
import 'doctor_notification_trigger.dart';
import 'in_app_notification_service.dart';
import 'patient_notification_trigger.dart';

/// In-app patient notifications for shipped features only.
abstract final class PatientNotificationEmitter {
  static String _id() => 'p${DateTime.now().microsecondsSinceEpoch}';

  static AppNotification _build({
    required PatientNotificationTrigger trigger,
    required String title,
    required String body,
    required AppNotificationType type,
    AppNotificationTarget? target,
    String? targetId,
    AppNotificationAction? primaryAction,
    String? dedupeKey,
  }) {
    final spec = PatientTriggerCatalog.specFor(trigger);
    return AppNotification(
      id: _id(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
      type: type,
      patientTrigger: trigger,
      priority: spec.priority,
      channelTags: [NotificationChannelTag.app, ...spec.channels],
      target: target,
      targetId: targetId,
      primaryAction: primaryAction,
      dedupeKey: dedupeKey,
    );
  }

  static void emit(AppNotification n) =>
      InAppNotificationService.instance.addPatient(n);

  static void notifyBookingConfirmed({
    required String doctorName,
    required DateTime date,
    required String timeLabel,
    required int token,
    required String locationOrLink,
    String? appointmentId,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.bookingConfirmed,
        title: 'Booking confirmed',
        body: 'Dr. $doctorName · $timeLabel · Token #$token',
        type: AppNotificationType.booking,
        target: AppNotificationTarget.appointments,
        targetId: appointmentId,
        dedupeKey:
            appointmentId != null ? 'p_booking_confirmed_$appointmentId' : null,
      ));

  static void notifyBookingRequestSent({
    required String doctorName,
    required DateTime date,
    required String timeLabel,
    String? appointmentId,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.bookingConfirmed,
        title: 'Request sent',
        body: 'Dr. $doctorName · $timeLabel',
        type: AppNotificationType.booking,
        target: AppNotificationTarget.appointments,
        targetId: appointmentId,
        dedupeKey:
            appointmentId != null ? 'p_booking_request_$appointmentId' : null,
      ));

  static void notifyReminderTomorrow({
    required String doctorName,
    required String dateTimeLabel,
    required String location,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.appointmentReminderTomorrow,
        title: 'Appt tomorrow',
        body: 'Dr. $doctorName',
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointments,
        dedupeKey:
            'p_tomorrow_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyReminderTwoHours({
    required String doctorName,
    required String dateTimeLabel,
    required String clinicAddress,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.appointmentReminderTwoHours,
        title: 'Appt in 2 hours',
        body: 'Dr. $doctorName',
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointments,
        dedupeKey:
            'p_2h_${dateTimeLabel}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyReminderThirtyMin({required String doctorName}) =>
      emit(_build(
        trigger: PatientNotificationTrigger.appointmentReminderThirtyMin,
        title: 'Appt in 30 mins',
        body: 'Dr. $doctorName',
        type: AppNotificationType.reminder,
        target: AppNotificationTarget.appointments,
        dedupeKey:
            'p_30m_${doctorName}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyDoctorRescheduled({
    required String doctorName,
    required String newDateTime,
    required String oldDateTime,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.doctorRescheduled,
        title: 'Rescheduled',
        body: 'Dr. $doctorName: $oldDateTime to $newDateTime.',
        type: AppNotificationType.appointment,
        target: AppNotificationTarget.appointments,
        primaryAction: const AppNotificationAction(
            label: 'View details', actionKey: 'view_appointment'),
        dedupeKey: 'p_reschedule_${doctorName}_$newDateTime',
      ));

  static void notifyDoctorCancelled({
    required String doctorName,
    required String reason,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.doctorCancelled,
        title: 'Cancelled',
        body: 'Dr. $doctorName: $reason.',
        type: AppNotificationType.cancellation,
        target: AppNotificationTarget.search,
        primaryAction: const AppNotificationAction(
            label: 'Book another doctor', actionKey: 'book_another'),
        dedupeKey: 'p_cancel_${doctorName}_$reason',
      ));

  static void notifyNewAppointmentRequest({
    required String doctorName,
    required String prescriptionId,
    required String diagnosis,
  }) =>
      notifyPrescriptionFromDoctor(
        doctorName: doctorName,
        prescriptionId: prescriptionId,
        diagnosis: diagnosis,
      );

  static void notifyPrescriptionFromDoctor({
    required String doctorName,
    required String prescriptionId,
    required String diagnosis,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.medicineReminder,
        title: 'New prescription',
        body: 'Dr. $doctorName: $diagnosis',
        type: AppNotificationType.prescription,
        target: AppNotificationTarget.prescriptions,
        targetId: prescriptionId,
        dedupeKey: 'p_rx_new_$prescriptionId',
      ));

  static void notifyReferralFromDoctor({
    required String fromDoctorName,
    required String toDoctorName,
    required String specialization,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.bookingConfirmed,
        title: 'Doctor referral',
        body:
            'Dr. $fromDoctorName referred you to Dr. $toDoctorName ($specialization).',
        type: AppNotificationType.appointment,
        target: AppNotificationTarget.search,
        dedupeKey: 'p_referral_${fromDoctorName}_$toDoctorName',
      ));

  static void notifyLabBookingRequestSent({
    required String labName,
    required String testName,
    required DateTime date,
    required String slotLabel,
    required String bookingId,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.labOrderSent,
        title: 'Request sent to lab',
        body: '$labName · $testName',
        type: AppNotificationType.labReport,
        target: AppNotificationTarget.labBooking,
        targetId: bookingId,
        dedupeKey: 'lab_request_$bookingId',
      ));

  static void notifyLabCollectionReminder({
    required String slotLabel,
    required String phlebotomistName,
    required String contact,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.labCollectionReminder,
        title: 'Home collection',
        body: '$phlebotomistName · $slotLabel',
        type: AppNotificationType.labReport,
        target: AppNotificationTarget.labBooking,
        dedupeKey: 'lab_collection_$slotLabel',
      ));

  static void notifyPhlebotomistOnTheWay({
    required String phlebotomistName,
    required String eta,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.phlebotomistOnTheWay,
        title: 'Phlebotomist on the way',
        body: 'ETA $eta',
        type: AppNotificationType.labReport,
        target: AppNotificationTarget.labBooking,
        primaryAction: const AppNotificationAction(
            label: 'Track', actionKey: 'track_phlebotomist'),
        dedupeKey: 'lab_on_way_$eta',
      ));

  static void notifyVaccinationDue({
    required String vaccineName,
    required DateTime dueDate,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.vaccinationDueReminder,
        title: 'Vaccination due',
        body: vaccineName,
        type: AppNotificationType.wellness,
        target: AppNotificationTarget.vaccination,
        dedupeKey:
            'vax_${vaccineName}_${DateFormat('yyyy-MM-dd').format(dueDate)}',
      ));

  static void notifyMedicineReminder({
    required String medicineName,
    required String dosage,
    required String foodTiming,
  }) =>
      emit(_build(
        trigger: PatientNotificationTrigger.medicineReminder,
        title: 'Medicine reminder',
        body: medicineName,
        type: AppNotificationType.prescription,
        dedupeKey: 'p_med_${medicineName}_${DateTime.now().hour}',
      ));

  static void notifyVitalsReminder() => emit(_build(
        trigger: PatientNotificationTrigger.vitalsLogReminder,
        title: 'Log vitals',
        body: 'Log your vitals',
        type: AppNotificationType.wellness,
        target: AppNotificationTarget.vitals,
        primaryAction: const AppNotificationAction(
            label: 'Log now', actionKey: 'log_vitals'),
        dedupeKey:
            'p_vitals_week_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));

  static void notifyHealthTip({required String tip}) => emit(_build(
        trigger: PatientNotificationTrigger.healthTipOfDay,
        title: 'Health tip of the day',
        body: tip,
        type: AppNotificationType.wellness,
        dedupeKey: 'p_tip_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      ));
}
