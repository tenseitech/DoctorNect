import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/profile_completion_service.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/supabase/in_app_notification_supabase_repository.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';

DoctorNectAppointmentRecord _dummyRecord() {
  return DoctorNectAppointmentRecord(
    id: 'x',
    appointmentId: 'x',
    doctorId: 'd',
    doctorName: 'D',
    specialization: 'GP',
    patientName: 'P',
    patientAge: 1,
    patientGender: 'M',
    dateTime: DateTime.utc(2026, 1, 1),
    slotLabel: '09:00',
    tokenNumber: 1,
    visitType: AppointmentType.newVisit,
    patientStatus: PatientBookingStatus.confirmed,
    doctorStatus: AppointmentStatus.confirmed,
  );
}

void main() {
  group('Debug hooks blocked when release guard is active', () {
    tearDown(() {
      SharedAppointmentsStore.debugPatientFirestoreRefresh = null;
      SharedAppointmentsStore.debugDoctorFirestoreRefresh = null;
      SharedAppointmentsStore.debugForceReleaseMode = false;
      InAppNotificationSupabaseRepository.resetMarkReadOverrideForTesting();
      InAppNotificationSupabaseRepository.debugForceReleaseMode = false;
      ProfileCompletionService.instance.reset();
    });

    test('debugPatientFirestoreRefresh setter throws under debugForceReleaseMode',
        () {
      SharedAppointmentsStore.debugForceReleaseMode = true;
      expect(
        () => SharedAppointmentsStore.debugPatientFirestoreRefresh =
            (_) async => [_dummyRecord()],
        throwsAssertionError,
      );
    });

    test('debugDoctorFirestoreRefresh setter throws under debugForceReleaseMode',
        () {
      SharedAppointmentsStore.debugForceReleaseMode = true;
      expect(
        () => SharedAppointmentsStore.debugDoctorFirestoreRefresh =
            (_) async => [_dummyRecord()],
        throwsAssertionError,
      );
    });

    test('debugFirestoreOverride setter throws under debugForceReleaseMode', () {
      ProfileCompletionService.debugForceReleaseMode = true;
      expect(
        () => ProfileCompletionService.debugFirestoreOverride =
            () => FakeFirebaseFirestore(),
        throwsAssertionError,
      );
    });

    test('debugMarkReadOverride setter throws under debugForceReleaseMode', () {
      InAppNotificationSupabaseRepository.debugForceReleaseMode = true;
      expect(
        () => InAppNotificationSupabaseRepository.debugMarkReadOverride =
            (_) async {},
        throwsAssertionError,
      );
    });
  });
}
