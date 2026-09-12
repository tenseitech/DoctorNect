import '../models/patient_appointment_models.dart';

/// Filters real appointment lists loaded from [SharedAppointmentsStore].
abstract final class PatientAppointmentFilters {
  static List<PatientAppointment> upcoming(List<PatientAppointment> all) =>
      all
          .where((a) =>
              a.cancellationReason == null &&
              a.dateTime.isAfter(DateTime.now().subtract(const Duration(hours: 1))))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  static List<PatientAppointment> completed(List<PatientAppointment> all) =>
      all
          .where((a) =>
              a.cancellationReason == null &&
              a.dateTime.isBefore(DateTime.now().subtract(const Duration(hours: 1))))
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

  static List<PatientAppointment> cancelled(List<PatientAppointment> all) =>
      all.where((a) => a.cancellationReason != null).toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
}
