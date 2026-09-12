import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/prescription/prescription_header_helper.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';

DoctorNectAppointmentRecord _booking({
  required String id,
  required String appointmentId,
  required String doctorId,
  required String doctorName,
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
    dateTime: DateTime(2026, 1, 1, 10, 0),
    slotLabel: '10:00 AM',
    tokenNumber: 1,
    visitType: AppointmentType.newVisit,
    patientStatus: PatientBookingStatus.confirmed,
    doctorStatus: AppointmentStatus.confirmed,
  );
}

PrescriptionDraft _draft({
  String? appointmentId,
  String doctorName = '',
  String doctorId = '',
}) {
  final draft = PrescriptionDraft(
    patient: PatientClinicalContext(
      patientName: 'Test Patient',
      age: 30,
      appointmentId: appointmentId,
    ),
  );
  draft.doctorName = doctorName;
  draft.doctorId = doctorId;
  return draft;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrescriptionHeaderHelper.doctorNameForDraft (name printed on PDF)', () {
    setUp(() {
      // Seed two bookings with two different doctors to prove each prescription
      // resolves to *its own* booking's doctor (multi-doctor edge case).
      SharedAppointmentsStore.instance.mergeFromFirestore([
        _booking(
          id: 'rec1',
          appointmentId: 'APT001',
          doctorId: 'doc_asha',
          doctorName: 'Dr. Asha Verma',
        ),
        _booking(
          id: 'rec2',
          appointmentId: 'APT002',
          doctorId: 'doc_ravi',
          doctorName: 'Ravi Kumar', // stored without prefix on purpose
        ),
      ]);
    });

    test('uses the doctor from the linked booking (not the signed-in doctor)',
        () {
      final name = PrescriptionHeaderHelper.doctorNameForDraft(
        _draft(appointmentId: 'APT001', doctorName: 'Dr. Someone Else'),
        fallback: 'Dr. Fallback',
      );
      expect(name, 'Dr. Asha Verma');
    });

    test('resolves the correct doctor when multiple bookings/doctors exist', () {
      final name = PrescriptionHeaderHelper.doctorNameForDraft(
        _draft(appointmentId: 'APT002'),
        fallback: 'Dr. Fallback',
      );
      // Booking name lacked the prefix; helper normalizes it.
      expect(name, 'Dr. Ravi Kumar');
    });

    test('resolves by doctorId when snapshot is empty and appointment is unlinked '
        '(the real-world "Dr. Doctor" bug)', () {
      final name = PrescriptionHeaderHelper.doctorNameForDraft(
        // No snapshot, no matching appointmentId — only the doctorId is known.
        _draft(appointmentId: null, doctorName: '', doctorId: 'doc_asha'),
        fallback: 'Dr. Doctor',
      );
      expect(name, 'Dr. Asha Verma');
    });

    test('falls back to the saved snapshot when the booking is unknown', () {
      final name = PrescriptionHeaderHelper.doctorNameForDraft(
        _draft(appointmentId: 'APT_UNKNOWN', doctorName: 'Dr. Snapshot Doc'),
        fallback: 'Dr. Fallback',
      );
      expect(name, 'Dr. Snapshot Doc');
    });

    test('is never empty — falls back when there is no booking and no snapshot',
        () {
      final name = PrescriptionHeaderHelper.doctorNameForDraft(
        _draft(appointmentId: null, doctorName: ''),
        fallback: 'Dr. Fallback',
      );
      expect(name, 'Dr. Fallback');
      expect(name.isNotEmpty, isTrue);
    });
  });
}
