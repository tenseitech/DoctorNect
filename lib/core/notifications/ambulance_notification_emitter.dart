import '../../features/ambulance/models/ambulance_models.dart';
import '../session/doctor_session.dart';
import '../session/patient_session.dart';
import 'app_notification.dart';
import 'in_app_notification_service.dart';

abstract final class AmbulanceNotificationEmitter {
  static void notifyBookingAcceptedForBooker({
    required AmbulanceBooking booking,
    required RegisteredAmbulance ambulance,
  }) {
    final title = 'Ambulance confirmed';
    final body =
        '${ambulance.serviceName} (${ambulance.driverName}) is on the way for ${booking.patientName}. '
        'Vehicle: ${ambulance.vehicleNumber} · ${ambulance.phone}';

    final notification = AppNotification(
      id: 'amb-accepted-${booking.id}',
      title: title,
      body: body,
      createdAt: DateTime.now(),
      type: AppNotificationType.system,
      dedupeKey: 'amb-accepted-${booking.id}',
    );

    if (booking.bookedByRole == AmbulanceBookedByRole.doctor) {
      InAppNotificationService.instance.addDoctor(notification);
    } else {
      InAppNotificationService.instance.addPatient(notification);
    }
  }

  static String bookerDisplayName(AmbulanceBookedByRole role) {
    return switch (role) {
      AmbulanceBookedByRole.doctor => DoctorSession.loggedInDoctorName.isNotEmpty
          ? DoctorSession.loggedInDoctorName
          : 'Doctor',
      AmbulanceBookedByRole.patient => PatientSession.loggedInPatientName.isNotEmpty
          ? PatientSession.loggedInPatientName
          : 'Patient',
    };
  }

  static String bookerId(AmbulanceBookedByRole role) {
    return switch (role) {
      AmbulanceBookedByRole.doctor => DoctorSession.loggedInDoctorId,
      AmbulanceBookedByRole.patient => PatientSession.loggedInPatientId,
    };
  }
}
