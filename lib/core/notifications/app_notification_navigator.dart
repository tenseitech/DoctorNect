import 'package:medibond/core/firebase/firestore_service.dart';
import './app_toast.dart';
import 'package:flutter/material.dart';

import '../data/shared_appointments_store.dart';
import '../session/doctor_session.dart';
import '../session/patient_session.dart';
import 'package:medibond/features/shared/screens/appointment_detail_screen.dart';
import '../../features/doctor/clinical/referral_consult_service.dart';
import '../../features/doctor/home/widgets/doctor_referred_patients_screen.dart';
import '../../features/doctor/clinical/data/clinical_prescription_store.dart';
import '../../features/doctor/clinical/data/lab_order_store.dart';
import '../../features/doctor/clinical/prescription/prescription_preview_modal.dart';
import '../../features/doctor/lab/doctor_connected_labs_screen.dart';
import '../../features/doctor/pharmacy/doctor_connected_stores_screen.dart';
import '../../features/patient/lab/lab_report_screen.dart';
import '../../features/patient/records/data/patient_lab_booking_store.dart';
import '../../features/patient/records/widgets/patient_blood_test_sheet.dart';
import '../../features/patient/records/widgets/patient_lab_order_sheet.dart';
import '../../features/pharmacy/data/pharmacy_prescription_store.dart';
import '../../features/doctor/verification/doctor_verification_gate.dart';
import 'app_notification.dart';
import 'doctor_notification_trigger.dart';
import 'patient_notification_trigger.dart';

/// Opens the screen or modal that matches an in-app notification's metadata.
abstract final class AppNotificationNavigator {
  /// Routes from an FCM data payload (background / killed-app tap).
  static Future<bool> openFromPushData(
    BuildContext context, {
    required Map<String, dynamic> data,
    required NotificationAudience audience,
  }) async {
    final type = data['type']?.toString().trim();
    if (type == null || type.isEmpty) return false;

    if (type == 'appointment_new' && audience == NotificationAudience.doctor) {
      final appointmentId = data['appointmentId']?.toString().trim();
      if (appointmentId == null || appointmentId.isEmpty) return false;
      return _openAppointment(
        context,
        targetId: appointmentId,
        audience: audience,
      );
    }

    if (type == 'referral_received' && audience == NotificationAudience.doctor) {
      final referralId = data['referralId']?.toString().trim();
      if (referralId == null || referralId.isEmpty) return false;
      return _openDoctorReferralConsult(context, referralId: referralId);
    }

    if (audience == NotificationAudience.patient) {
      if (type == 'appointment_status_update') {
        final appointmentId = data['appointmentId']?.toString().trim();
        if (appointmentId == null || appointmentId.isEmpty) return false;
        return _openAppointment(
          context,
          targetId: appointmentId,
          audience: audience,
        );
      }
      if (type == 'pharmacy_delivery_update') {
        final prescriptionId = data['prescriptionId']?.toString().trim();
        if (prescriptionId == null || prescriptionId.isEmpty) return false;
        return _openPatientPrescription(context, prescriptionId: prescriptionId);
      }
    }

    return false;
  }

  static Future<bool> open(
    BuildContext context, {
    required AppNotification notification,
    required NotificationAudience audience,
  }) async {
    final targetId = notification.targetId?.trim();
    if (targetId == null || targetId.isEmpty) {
      return _openWithoutTargetId(context, notification: notification, audience: audience);
    }

    final target = notification.target ?? _inferTarget(notification, audience);
    if (target != null) {
      return _openForTarget(
        context,
        target: target,
        targetId: targetId,
        notification: notification,
        audience: audience,
      );
    }

    return _openFromFallback(
      context,
      notification: notification,
      audience: audience,
      targetId: targetId,
    );
  }

  static AppNotificationTarget? _inferTarget(
    AppNotification notification,
    NotificationAudience audience,
  ) {
    if (audience == NotificationAudience.patient) {
      return switch (notification.patientTrigger) {
        PatientNotificationTrigger.labBookingAccepted ||
        PatientNotificationTrigger.labBookingDeclined ||
        PatientNotificationTrigger.labBookingUpdate =>
          notification.target ?? AppNotificationTarget.labBooking,
        PatientNotificationTrigger.labReportReady ||
        PatientNotificationTrigger.labOrderSent =>
          AppNotificationTarget.labReports,
        PatientNotificationTrigger.medicineReminder ||
        PatientNotificationTrigger.pharmacyDeliveryUpdate =>
          AppNotificationTarget.prescriptions,
        PatientNotificationTrigger.bookingConfirmed => AppNotificationTarget.appointments,
        _ => null,
      };
    }

    final doctorTarget = switch (notification.doctorTrigger) {
      DoctorNotificationTrigger.newAppointmentBooked => AppNotificationTarget.appointmentDetail,
      DoctorNotificationTrigger.patientReferredToMe => AppNotificationTarget.patients,
      _ => null,
    };
    if (doctorTarget != null) return doctorTarget;

    final dedupeKey = notification.dedupeKey ?? '';
    if (_isDoctorPharmacyDeliveryDedupe(dedupeKey)) {
      return AppNotificationTarget.prescriptions;
    }

    return null;
  }

  static bool _isDoctorPharmacyDeliveryDedupe(String dedupeKey) {
    return dedupeKey.startsWith('d_pharm_view_') ||
        dedupeKey.startsWith('d_pharm_disp_') ||
        dedupeKey.startsWith('d_pharm_oos_');
  }

  static Future<bool> _openWithoutTargetId(
    BuildContext context, {
    required AppNotification notification,
    required NotificationAudience audience,
  }) async {
    final dedupeKey = notification.dedupeKey ?? '';
    if (dedupeKey.startsWith('d_lab_conn_')) {
      return _openDoctorConnectedLabs(context);
    }
    if (dedupeKey.startsWith('d_pharm_conn_')) {
      return _openDoctorConnectedStores(context);
    }
    if (notification.type == AppNotificationType.kyc ||
        notification.title.toLowerCase().contains('kyc') ||
        notification.title.toLowerCase().contains('verification') ||
        notification.body.toLowerCase().contains('verification')) {
      final doctorId = DoctorSession.loggedInDoctorId;
      if (doctorId.isNotEmpty && audience == NotificationAudience.doctor) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DoctorVerificationGate(doctorId: doctorId),
          ),
        );
        return true;
      }
    }
    _showFailure(context, 'This notification has no linked record.');
    return false;
  }

  static Future<bool> _openForTarget(
    BuildContext context, {
    required AppNotificationTarget target,
    required String targetId,
    required AppNotification notification,
    required NotificationAudience audience,
  }) async {
    return switch (target) {
      AppNotificationTarget.appointmentDetail ||
      AppNotificationTarget.appointments =>
        _openAppointment(context, targetId: targetId, audience: audience),
      AppNotificationTarget.labBooking =>
        _openLabBooking(context, bookingId: targetId),
      AppNotificationTarget.labReports => _openLabReports(
          context,
          targetId: targetId,
          notification: notification,
        ),
      AppNotificationTarget.prescriptions when audience == NotificationAudience.patient =>
        _openPatientPrescription(context, prescriptionId: targetId),
      AppNotificationTarget.prescriptions when audience == NotificationAudience.doctor =>
        _openDoctorPharmacyDelivery(context, deliveryId: targetId),
      AppNotificationTarget.patients when audience == NotificationAudience.doctor =>
        _openDoctorReferralConsult(context, referralId: targetId),
      _ => _openFromFallback(
          context,
          notification: notification,
          audience: audience,
          targetId: targetId,
        ),
    };
  }

  static Future<bool> _openFromFallback(
    BuildContext context, {
    required AppNotification notification,
    required NotificationAudience audience,
    required String targetId,
  }) async {
    final dedupeKey = notification.dedupeKey ?? '';

    if (dedupeKey.startsWith('d_lab_conn_')) {
      return _openDoctorConnectedLabs(context);
    }
    if (dedupeKey.startsWith('d_pharm_conn_')) {
      return _openDoctorConnectedStores(context);
    }
    if (_isDoctorPharmacyDeliveryDedupe(dedupeKey)) {
      return _openDoctorPharmacyDelivery(context, deliveryId: targetId);
    }

    if (notification.patientTrigger == PatientNotificationTrigger.labBookingAccepted ||
        notification.patientTrigger == PatientNotificationTrigger.labBookingDeclined ||
        notification.patientTrigger == PatientNotificationTrigger.labBookingUpdate) {
      if (notification.target == AppNotificationTarget.labReports ||
          (notification.dedupeKey?.startsWith('p_lab_order_') ?? false)) {
        return _openLabOrder(context, orderId: targetId);
      }
      return _openLabBooking(context, bookingId: targetId);
    }
    if (notification.patientTrigger == PatientNotificationTrigger.labReportReady) {
      return _openLabReport(context, bookingId: targetId);
    }
    if (notification.patientTrigger == PatientNotificationTrigger.labOrderSent) {
      return _openLabOrder(context, orderId: targetId);
    }
    if ((notification.patientTrigger == PatientNotificationTrigger.medicineReminder ||
            notification.patientTrigger == PatientNotificationTrigger.pharmacyDeliveryUpdate) &&
        audience == NotificationAudience.patient) {
      return _openPatientPrescription(context, prescriptionId: targetId);
    }
    if (notification.doctorTrigger == DoctorNotificationTrigger.newAppointmentBooked) {
      return _openAppointment(context, targetId: targetId, audience: audience);
    }
    if (notification.doctorTrigger == DoctorNotificationTrigger.patientReferredToMe) {
      return _openDoctorReferralConsult(context, referralId: targetId);
    }

    if (audience == NotificationAudience.doctor &&
        notification.type == AppNotificationType.prescription) {
      return _openDoctorPharmacyDelivery(context, deliveryId: targetId);
    }

    _showFailure(context, 'Could not open this notification.');
    return false;
  }

  // â”€â”€ Group 1: appointments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _openDoctorReferralConsult(
    BuildContext context, {
    required String referralId,
  }) async {
    final referral = await FirestoreService.instance.referral.fetchById(
      referralId,
      preferCache: false,
    );
    if (!context.mounted) return false;
    if (referral == null) {
      await DoctorReferredPatientsScreen.open(context);
      return true;
    }
    if (referral.toDoctorId != DoctorSession.loggedInDoctorId) {
      await DoctorReferredPatientsScreen.open(context);
      return true;
    }
    await ReferralConsultService.openIncomingConsult(context, referral);
    return true;
  }

  static Future<bool> _openAppointment(
    BuildContext context, {
    required String targetId,
    required NotificationAudience audience,
  }) async {
    if (audience == NotificationAudience.doctor) {
      final doctorId = DoctorSession.loggedInDoctorId;
      var appointment = SharedAppointmentsStore.instance.doctorAppointmentForTarget(
        targetId,
        doctorId,
      );
      if (appointment == null && doctorId.isNotEmpty) {
        await SharedAppointmentsStore.instance.refreshForDoctor(
          doctorId,
          preferCache: false,
          force: true,
        );
        appointment = SharedAppointmentsStore.instance.doctorAppointmentForTarget(
          targetId,
          doctorId,
        );
      }
      if (appointment == null) {
        if (!context.mounted) return false;
        _showFailure(context, 'Appointment not found. Pull to refresh and try again.');
        return false;
      }
      if (!context.mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AppointmentDetailScreen(appointment: appointment!),
        ),
      );
      return true;
    }

    final patientId = PatientSession.loggedInPatientId;
    var patientAppointment =
        SharedAppointmentsStore.instance.patientAppointmentForTarget(targetId);
    if (patientAppointment == null && patientId.isNotEmpty) {
      await SharedAppointmentsStore.instance.refreshForPatient(patientId);
      patientAppointment =
          SharedAppointmentsStore.instance.patientAppointmentForTarget(targetId);
    }
    if (patientAppointment == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Appointment not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentDetailScreen(
          appointment: patientAppointment!,
        ),
      ),
    );
    return true;
  }

  // â”€â”€ Group 2: lab booking / report / order â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _openLabBooking(BuildContext context, {required String bookingId}) async {
    final patientId = PatientSession.loggedInPatientId;
    var booking = PatientLabBookingStore.instance.findById(bookingId);
    if (booking == null && patientId.isNotEmpty) {
      await PatientLabBookingStore.instance.refreshForPatient(patientId, preferCache: false);
      booking = PatientLabBookingStore.instance.findById(bookingId);
    }
    if (booking == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Lab booking not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    await PatientBloodTestSheet.show(context, booking);
    return true;
  }

  static Future<bool> _openLabReports(
    BuildContext context, {
    required String targetId,
    required AppNotification notification,
  }) async {
    if (notification.patientTrigger == PatientNotificationTrigger.labOrderSent ||
        (notification.patientTrigger == PatientNotificationTrigger.labBookingUpdate &&
            (notification.dedupeKey?.startsWith('p_lab_order_') ?? false)) ||
        _isLabOrderId(targetId)) {
      return _openLabOrder(context, orderId: targetId);
    }
    return _openLabReport(context, bookingId: targetId);
  }

  static bool _isLabOrderId(String id) {
    return id.startsWith('lab_');
  }

  static Future<bool> _openLabReport(BuildContext context, {required String bookingId}) async {
    final patientId = PatientSession.loggedInPatientId;
    var booking = PatientLabBookingStore.instance.findById(bookingId);
    if (booking == null && patientId.isNotEmpty) {
      await PatientLabBookingStore.instance.refreshForPatient(patientId, preferCache: false);
      booking = PatientLabBookingStore.instance.findById(bookingId);
    }
    if (booking == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Lab report not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    if (booking.hasReport) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LabReportScreen(booking: booking)),
      );
    } else {
      await PatientBloodTestSheet.show(context, booking);
    }
    return true;
  }

  static Future<bool> _openLabOrder(BuildContext context, {required String orderId}) async {
    final patientId = PatientSession.loggedInPatientId;
    var order = LabOrderStore.instance.findById(orderId);
    if (order == null && patientId.isNotEmpty) {
      await LabOrderStore.instance.refreshForPatient(patientId, preferCache: false);
      order = LabOrderStore.instance.findById(orderId);
    }
    if (order == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Lab test order not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    await PatientLabOrderSheet.show(context, order);
    return true;
  }

  // â”€â”€ Group 3: doctor connections + pharmacy delivery â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _openDoctorConnectedLabs(BuildContext context) async {
    if (!context.mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DoctorConnectedLabsScreen()),
    );
    return true;
  }

  static Future<bool> _openDoctorConnectedStores(BuildContext context) async {
    if (!context.mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DoctorConnectedStoresScreen()),
    );
    return true;
  }

  static Future<bool> _openDoctorPharmacyDelivery(
    BuildContext context, {
    required String deliveryId,
  }) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    var delivery = PharmacyPrescriptionStore.instance.findById(deliveryId);
    if (delivery == null && doctorId.isNotEmpty) {
      await PharmacyPrescriptionStore.instance.refreshForDoctor(
        doctorId,
        preferCache: false,
      );
      delivery = PharmacyPrescriptionStore.instance.findById(deliveryId);
    }
    if (delivery == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Prescription delivery not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    PrescriptionPreviewModal.show(context, draft: delivery.draft);
    return true;
  }

  // â”€â”€ Group 4: patient prescriptions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> _openPatientPrescription(
    BuildContext context, {
    required String prescriptionId,
  }) async {
    final patientId = PatientSession.loggedInPatientId;
    var draft = ClinicalPrescriptionStore.instance.findById(prescriptionId);
    if (draft == null && patientId.isNotEmpty) {
      await ClinicalPrescriptionStore.instance.refreshForPatient(
        patientId,
        preferCache: false,
      );
      draft = ClinicalPrescriptionStore.instance.findById(prescriptionId);
    }
    if (draft == null) {
      if (!context.mounted) return false;
      _showFailure(context, 'Prescription not found. Pull to refresh and try again.');
      return false;
    }
    if (!context.mounted) return false;
    PrescriptionPreviewModal.show(context, draft: draft);
    return true;
  }

  static void _showFailure(BuildContext context, String message) {
    AppToast.info(context, message);
  }
}
