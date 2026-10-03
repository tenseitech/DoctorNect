import '../../features/patient/lab/models/lab_models.dart';

/// Tracks recent patient actions for time-based in-app notifications.
class PatientActivityStore {
  PatientActivityStore._();

  static final instance = PatientActivityStore._();

  ConfirmedLabBooking? lastLabBooking;
  DateTime? lastClinicBookingAt;
  String? lastBookedDoctorName;
  DateTime? lastBookedAppointmentAt;
  String? lastBookedSlotLabel;
  String? lastBookedClinicAddress;
  int? lastBookedToken;
}
