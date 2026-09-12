import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';
import 'package:medibond/features/patient/booking/models/booking_models.dart';

/// Fixed future Monday for deterministic slot-generation tests.
final DateTime kBookingTestMonday = DateTime(2026, 8, 3);

DoctorNectAppointmentRecord bookingRecord({
  required String id,
  String appointmentId = 'APT001',
  String doctorId = 'doc_test',
  String doctorName = 'Dr. Test',
  DateTime? dateTime,
  String slotLabel = '10:00 AM',
  int tokenNumber = 1,
  String? cancellationReason,
}) {
  return DoctorNectAppointmentRecord(
    id: id,
    appointmentId: appointmentId,
    doctorId: doctorId,
    doctorName: doctorName,
    specialization: 'General Medicine',
    patientName: 'Test Patient',
    patientAge: 30,
    patientGender: 'Male',
    dateTime: dateTime ?? DateTime(kBookingTestMonday.year, kBookingTestMonday.month, kBookingTestMonday.day, 10, 0),
    slotLabel: slotLabel,
    tokenNumber: tokenNumber,
    visitType: AppointmentType.newVisit,
    patientStatus: PatientBookingStatus.confirmed,
    doctorStatus: AppointmentStatus.confirmed,
    cancellationReason: cancellationReason,
  );
}

TimeSlot sampleSlot({
  String label = '10:00 AM',
  SlotStatus status = SlotStatus.available,
  int bookingCount = 0,
}) {
  return TimeSlot(
    id: 'slot_$label',
    label: label,
    period: 'Morning',
    status: status,
    bookingCount: bookingCount,
  );
}

PatientAppointment patientAppointment({
  required String id,
  required DateTime dateTime,
  String? cancellationReason,
}) {
  return PatientAppointment(
    id: id,
    doctorId: 'doc_test',
    doctorName: 'Dr. Test',
    specialization: 'General Medicine',
    dateTime: dateTime,
    tokenNumber: 1,
    status: PatientBookingStatus.confirmed,
    cancellationReason: cancellationReason,
  );
}
