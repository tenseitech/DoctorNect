import '../../data/shared_appointments_store.dart';
import '../../supabase/repositories/supabase_appointment_repository.dart';

class AppointmentRepository {
  AppointmentRepository._();

  static final AppointmentRepository instance = AppointmentRepository._();

  Future<void> save(
    DoctorNectAppointmentRecord record, {
    String? patientId,
  }) =>
      SupabaseAppointmentRepository.instance.save(record, patientId: patientId);

  Future<List<DoctorNectAppointmentRecord>> fetchForDoctor(
    String doctorId, {
    bool preferCache = false,
  }) =>
      SupabaseAppointmentRepository.instance.fetchForDoctor(
        doctorId,
        preferCache: preferCache,
      );

  Stream<List<DoctorNectAppointmentRecord>> watchForDoctor(String doctorId) =>
      SupabaseAppointmentRepository.instance.watchForDoctor(doctorId);

  Stream<List<DoctorNectAppointmentRecord>> watchForPatient(String patientId) =>
      SupabaseAppointmentRepository.instance.watchForPatient(patientId);

  Future<List<DoctorNectAppointmentRecord>> fetchForPatient(
    String patientId, {
    bool preferCache = false,
  }) =>
      SupabaseAppointmentRepository.instance.fetchForPatient(
        patientId,
        preferCache: preferCache,
      );
}
