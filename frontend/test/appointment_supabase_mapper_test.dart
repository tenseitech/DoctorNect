import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/mappers/appointment_supabase_mapper.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';

void main() {
  group('AppointmentSupabaseMapper cancellation reason narrowing', () {
    test(
      'non-cancelled appointment with lingering cancellation_reason does NOT evaluate to cancelled',
      () {
        final row = <String, dynamic>{
          'appointment_id': 'apt_rescheduled_100',
          'doctor_id': 'doc_1',
          'patient_id': 'pat_1',
          'doctor_name': 'Dr. Marcus Welby',
          'specialization': 'General Medicine',
          'patient_name': 'Alice Smith',
          'patient_age': 30,
          'patient_gender': 'Female',
          'date_time': '2026-10-25T10:00:00.000Z',
          'slot_label': '10:00 AM',
          'token_number': 1,
          'visit_type': 'newVisit',
          'patient_status': 'confirmed',
          'doctor_status': 'confirmed',
          // Lingering cancellation note from a prior reschedule or support un-cancel
          'cancellation_reason': 'Rescheduled from prior slot',
        };

        final record = AppointmentSupabaseMapper.fromRow(row);
        expect(record, isNotNull);
        expect(record!.doctorStatus, AppointmentStatus.confirmed);
        expect(record.patientStatus, PatientBookingStatus.confirmed);
        expect(record.isCancelled, isFalse);
        expect(record.cancellationReason, isNull);
      },
    );

    test(
      'patient_status == cancelled overrides doctorStatus and sets isCancelled to true',
      () {
        final row = <String, dynamic>{
          'appointment_id': 'apt_cancelled_200',
          'doctor_id': 'doc_1',
          'patient_id': 'pat_1',
          'doctor_name': 'Dr. Marcus Welby',
          'specialization': 'General Medicine',
          'patient_name': 'Bob Jones',
          'patient_age': 40,
          'patient_gender': 'Male',
          'date_time': '2026-10-25T11:00:00.000Z',
          'slot_label': '11:00 AM',
          'token_number': 2,
          'visit_type': 'newVisit',
          'patient_status': 'cancelled',
          'doctor_status': 'pendingRequest',
          'cancellation_reason': 'Patient emergency',
        };

        final record = AppointmentSupabaseMapper.fromRow(row);
        expect(record, isNotNull);
        expect(record!.doctorStatus, AppointmentStatus.cancelled);
        expect(record.isCancelled, isTrue);
        expect(record.cancellationReason, 'Patient emergency');
      },
    );

    test(
      'patient_status == cancelled with null cancellation_reason still sets doctorStatus cancelled and isCancelled true',
      () {
        final row = <String, dynamic>{
          'appointment_id': 'apt_cancelled_300',
          'doctor_id': 'doc_1',
          'patient_id': 'pat_1',
          'doctor_name': 'Dr. Marcus Welby',
          'specialization': 'General Medicine',
          'patient_name': 'Carol White',
          'patient_age': 28,
          'patient_gender': 'Female',
          'date_time': '2026-10-25T12:00:00.000Z',
          'slot_label': '12:00 PM',
          'token_number': 3,
          'visit_type': 'newVisit',
          'patient_status': 'cancelled',
          'doctor_status': 'pendingRequest',
          'cancellation_reason': null,
        };

        final record = AppointmentSupabaseMapper.fromRow(row);
        expect(record, isNotNull);
        expect(record!.doctorStatus, AppointmentStatus.cancelled);
        expect(record.isCancelled, isTrue);
        expect(record.cancellationReason, isNull);
      },
    );
  });
}
